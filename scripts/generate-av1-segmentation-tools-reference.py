#!/usr/bin/env python3
"""Controlled AV1 segmentation tools, verified by release/debug dav1d.

The key picture and general frame prefix are untouched libaom output. Segment
features and the complete inter tile are written explicitly in normative order.
Golden samples are exclusively the independent decoder's output.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile

from craft_av1_fixture import MsacEncoder, BitWriter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-segmentation-tools"
TEST = ROOT / "av1_segmentation_tools_reference_wbtest.mbt"


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


common = load_script("generate-av1-film-grain-sequence-reference.py")
header_tools = load_script("generate-av1-inter-reference.py")

# AV1 default CDF rows, retained locally so construction needs no private cache.
PART64 = [20137,21547,23078,29566,29837,30261,30524,30892,31724,32768,0]
PART32 = [18462,20920,23124,27647,28227,29049,29519,30178,31544,32768,0]
SEGID = [[5622,7893,16093,18233,27809,28373,32533,32768,0],
         [14274,18230,22557,24935,29980,30851,32344,32768,0],
         [27527,28487,28723,28890,32397,32647,32679,32768,0]]
SKIP = [[31671,32768,0],[16515,32768,0],[4576,32768,0]]
INTER = [806,32768,0]
NEW = [24035,32768,0]
GLOBAL = [2175,32768,0]
YMODE64 = [20155,21301,22838,23178,23261,23533,23703,24804,25352,26575,27016,28049,32768,0]
UVDC = [22631,24152,25378,25661,25986,26520,27055,27923,28244,30059,30941,31961,32768,0]


def tile(features: dict[int, int], split: bool) -> tuple[bytes, list[dict]]:
    enc = MsacEncoder()
    part64, part32, seg, skip = copy.deepcopy((PART64, PART32, SEGID, SKIP))
    symbols = []
    def symbol(row, value, name):
        enc.encode_symbol(row, value)
        symbols.append(dict(name=name, value=value, range=enc.rng))
    symbol(part64, 3 if split else 0, "partition64")
    for index in range(4 if split else 1):
        if split:
            symbol(part32, 0, "partition32")
        symbol(seg[2 if index == 3 else 0], 0, "segment_preskip")
        if 6 not in features:
            symbol(skip[0 if index == 0 else 2 if index == 3 else 1], 1, "skip")
        if 5 not in features and 7 not in features:
            symbol(INTER.copy(), 1, "is_inter")
        if features.get(5) == 0:
            symbol(YMODE64.copy(), 0, "intra_y_dc")
            symbol(UVDC.copy(), 0, "intra_uv_dc")
        elif 6 not in features and 7 not in features:
            symbol(NEW.copy(), 1, "new_mv")
            symbol(GLOBAL.copy(), 0, "global_mv")
    return enc.finish(), symbols


def segment_bits(features: dict[int, int]) -> list[int]:
    writer = BitWriter()
    writer.f(1, 1)  # segmentation_enabled; PRIMARY_REF_NONE implies map/data update.
    widths = [8,6,6,6,6,3,0,0]
    for segment in range(8):
        for feature in range(8):
            enabled = segment == 0 and feature in features
            writer.f(int(enabled), 1)
            if enabled and widths[feature]:
                width = widths[feature] + int(feature < 5)
                writer.f(features[feature] & ((1 << width) - 1), width)
    return writer.bits


def construct(base: bytes, headers: list[dict], features: dict[int, int], split: bool,
              levels: list[int], translate: bool) -> tuple[bytes, list[dict]]:
    out, index = bytearray(), 0
    entropy, symbols = tile(features, split)
    for kind, prefix, payload, overhead in common.packets(base):
        if kind == 6:
            if index == 1:
                fields = headers[1]
                assert fields["primary_ref_frame"]["value"] == 7
                bits = [int(c) for byte in payload for c in f"{byte:08b}"]
                def at(name): return fields[name]["bit"] - overhead * 8
                header = bits[:at("segmentation_enabled")] + segment_bits(features)
                header += bits[at("delta_q_present"):at("loop_filter_level[0]")]
                lf = BitWriter()
                for value in levels[:2]: lf.f(value, 6)
                if any(levels[:2]):
                    for value in levels[2:]: lf.f(value, 6)
                lf.f(0, 3)  # sharpness
                lf.f(0, 1)  # mode_ref_delta_enabled
                header += lf.bits
                # Encoder flags disable CDEF/restoration, so TX mode follows LF.
                header += bits[at("tx_mode"):at("is_global[1]")]
                if translate:
                    hp = 0 if fields["allow_high_precision_mv"]["value"] else 1
                    header += [1,0,1]
                    header += header_tools._write_global_param(2 << 16, 0, 0, 9-hp, 3-hp)
                    header += header_tools._write_global_param(0, 0, 1, 9-hp, 3-hp)
                    header += [0] * 6
                else:
                    header += [0] * 7
                header += [0] * (-len(header) % 8)
                payload = bytes(sum(header[i+j] << (7-j) for j in range(8)) for i in range(0,len(header),8)) + entropy
            index += 1
        out += prefix + common.leb(len(payload)) + payload
    assert index == 2
    return bytes(out), symbols


def base_stream(tools, scratch):
    raw = bytearray()
    for _ in range(2):
        for plane, size, base in ((0,64,100),(1,32,90),(2,32,140)):
            for y in range(size):
                for x in range(size):
                    raw.append(base + (8 if x >= size//2 else 0) + (6 if y >= size//2 else 0))
    (scratch/"source.yuv").write_bytes(raw)
    flags = ["--codec=av1","--obu","--i420","--width=64","--height=64","--fps=1/1","--limit=2",
             "--passes=2","--lag-in-frames=0","--threads=1","--row-mt=0","--cpu-used=0","--end-usage=q",
             "--cq-level=20","--debug","--disable-warning-prompt","--deltaq-mode=0","--enable-intrabc=0",
             "--enable-palette=0","--enable-cdef=0","--enable-restoration=0","--loopfilter-control=0",
             "--enable-tx64=0","--sb-size=64","--enable-order-hint=1","--enable-ref-frame-mvs=0",
             "--enable-warped-motion=0","--enable-global-motion=0","--enable-obmc=0","--enable-interintra-comp=0",
             "--enable-masked-comp=0","--enable-dual-filter=0","-o","base.obu","source.yuv"]
    common.run([tools["aomenc"]]+flags,scratch)
    trace, headers = common.trace(tools["ffmpeg"],scratch/"base.obu",scratch)
    return (scratch/"base.obu").read_bytes(),headers,bytes(raw),flags,trace


def specs():
    return [dict(name="forced_skip",features={6:0}),
            dict(name="forced_intra_reference",features={5:0}),
            dict(name="forced_inter_reference",features={5:1}),
            dict(name="forced_global_translation",features={7:0},translate=True),
            dict(name="lf_baseline",features={7:0},split=True,levels=[16]*4)] + [
                dict(name="alt_lf_"+name,features={7:0,feature:-16},split=True,levels=[16]*4)
                for feature,name in enumerate(("y_vertical","y_horizontal","u","v"),1)]


def emit_test(records, artifacts):
    output = '''/// Generated by scripts/generate-av1-segmentation-tools-reference.py.
/// Controlled complete tiles, independently decoded by dav1d 1.2.1.

///|
fn av1_segment_tools_bytes(hex : String) -> Array[Byte] {
  let chars = hex.to_array()
  let nibble = fn(c : Char) { if c <= '9' { c.to_int()-48 } else { c.to_int()-87 } }
  Array::makei(chars.length()/2, i => (16*nibble(chars[2*i])+nibble(chars[2*i+1])).to_byte())
}

///|
fn av1_segment_tools_samples(pairs : Array[Int]) -> Array[Int] {
  let values : Array[Int] = []
  for i in 0..<(pairs.length()/2) { for _ in 0..<pairs[i*2+1] { values.push(pairs[i*2]) } }
  values
}
'''
    for record in records:
        name=record["name"]
        output += f'\n///|\ntest "segmentation tool {name} matches complete dav1d frames" {{\n'
        output += '  let stream = av1_segment_tools_bytes(\n' + common.hex_literal(artifacts[name+".obu"])+'\n  )\n'
        pairs=[]
        for value in artifacts[name+".reference.yuv"]:
            if pairs and pairs[-2]==value: pairs[-1]+=1
            else: pairs += [value,1]
        output += '  let expected = av1_segment_tools_samples([\n'
        output += ''.join('    '+', '.join(map(str,pairs[i:i+24]))+',\n' for i in range(0,len(pairs),24))
        output += '''  ])
  let map = av1_frame_map()
  let (_, frames) = av1_decode_obu_planes(stream, map, None, false).unwrap()
  assert_eq(frames.length(), 2)
  let mut offset = 0
  for frame in frames { for plane in 0..<3 {
    let samples = av1_frame_crop(frame, plane)
    for i in 0..<samples.length() { assert_eq(samples[i], expected[offset+i]) }
    offset = offset + samples.length()
  } }
  assert_eq(offset, expected.length())
'''
        flags=record["header"]["refresh_frame_flags"]["value"]
        slot=next(i for i in range(8) if (flags>>i)&1)
        output += f'  let segments = map.saved_segmentation[{slot}]\n  assert_true(segments.seg_id_pre_skip)\n'
        for feature,value in record["features"].items():
            output += f'  assert_true(segments.feature_enabled[0][{feature}])\n  assert_eq(segments.feature_data[0][{feature}], {value})\n'
        output += '}\n'
    return output.encode()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aomenc",default="aomenc")
    parser.add_argument("--dav1d",default="dav1d")
    parser.add_argument("--ffmpeg",default="ffmpeg")
    parser.add_argument("--trace-dav1d",required=True)
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    tools={key:common.resolve(getattr(args,key)) for key in ("aomenc","dav1d","ffmpeg","trace_dav1d")}
    artifacts,records={},[]
    with tempfile.TemporaryDirectory(prefix="pixelforge-segment-tools-") as directory:
        scratch=Path(directory)
        base,headers,raw,flags,base_trace=base_stream(tools,scratch)
        artifacts.update({"base.obu":base,"base.trace.txt":base_trace})
        for spec in specs():
            name=spec["name"]
            stream,symbols=construct(base,headers,spec["features"],spec.get("split",False),spec.get("levels",[0]*4),spec.get("translate",False))
            path=scratch/(name+".obu");path.write_bytes(stream)
            trace,frames=common.trace(tools["ffmpeg"],path,scratch)
            native=common.decode(tools["dav1d"],path,scratch,False)
            debug_args=["-q","--threads=1","--framedelay=1","--filmgrain","0","--muxer=yuv","-i",path.name,"-o",name+".debug.yuv"]
            debug=common.run([tools["trace_dav1d"]]+debug_args,scratch)
            assert native==(scratch/(name+".debug.yuv")).read_bytes()
            assert len(native)==12288
            lines=[line for line in debug.splitlines() if line.startswith(("poc=","Post-"))]
            # Only the constructed inter frame is the syntax oracle; its blocks
            # use upstream DEBUG_BLOCK_INFO lines and contain no coefficients.
            begin=next(i for i,line in enumerate(lines) if line.startswith("poc=1,"))
            lines=lines[begin:]
            blocks=4 if spec.get("split") else 1
            assert sum(line.startswith("Post-segid[preskip;0]") for line in lines)==blocks
            assert sum(line.startswith("Post-skip[") for line in lines)==(0 if 6 in spec["features"] else blocks)
            assert not any(line.startswith("Post-ref[") for line in lines)
            assert sum(line.startswith("Post-intra[") for line in lines)==int(5 not in spec["features"] and 7 not in spec["features"])
            assert int(re.search(r"r=(\d+)",lines[-1])[1])==symbols[-1]["range"]
            for feature,value in spec["features"].items():
                assert frames[-1][f"feature_enabled[0][{feature}]"]["value"]==1
            debug=("\n".join(lines)+"\n").encode()
            artifacts.update({name+".obu":stream,name+".trace.txt":trace,name+".reference.yuv":native,name+".symbols.txt":debug})
            record=dict(spec, tile_symbols=symbols, header=frames[-1])
            records.append(record)
            print(name,"verified",blocks,"preskip blocks, terminal range",symbols[-1]["range"])
        key=artifacts["forced_skip.reference.yuv"][:6144]
        assert artifacts["forced_skip.reference.yuv"][6144:]==key
        assert artifacts["forced_inter_reference.reference.yuv"][6144:]==key
        assert set(artifacts["forced_intra_reference.reference.yuv"][6144:])=={128}
        assert artifacts["forced_global_translation.reference.yuv"][6144:]!=key
        baseline=artifacts["lf_baseline.reference.yuv"][6144:]
        for record in records:
            name=record["name"]
            if name.startswith("alt_lf_"):
                target=artifacts[name+".reference.yuv"][6144:]
                counts=[sum(a!=b for a,b in zip(baseline[start:end],target[start:end])) for start,end in ((0,4096),(4096,5120),(5120,6144))]
                assert sum(counts)>0,(name,counts)
                record["differences_from_lf_baseline"]=counts
                print(name,"sample differences",counts)
        versions=dict(aomenc=re.search(r"AOMedia Project AV1 Encoder[^\r\n]+",common.run([tools["aomenc"],"--help"],scratch))[0],
                      dav1d=common.run([tools["dav1d"],"--version"],scratch).strip(),
                      trace_dav1d=common.run([tools["trace_dav1d"],"--version"],scratch).strip(),
                      ffmpeg=common.run([tools["ffmpeg"],"-version"],scratch).splitlines()[0])
        test=emit_test(records,artifacts)
        formatted=scratch/TEST.name;formatted.write_bytes(test)
        common.run([common.resolve("moonfmt"),"-w",str(formatted)],ROOT)
        test=formatted.read_bytes().replace(b"\r\n",b"\n")
        manifest=dict(versions=versions,encoder_command=["aomenc"]+flags,source_sha256=hashlib.sha256(raw).hexdigest(),fixtures=records,
                      whitebox_sha256=hashlib.sha256(test).hexdigest(),
                      files={name:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest()) for name,data in artifacts.items()})
        artifacts["manifest.json"]=(json.dumps(manifest,indent=2)+"\n").encode()
    for name,data in artifacts.items():
        path=OUT/name
        if args.check:
            current=path.read_bytes() if path.exists() else None
            if current is not None and path.suffix in (".json",".txt"): current=current.replace(b"\r\n",b"\n")
            if current!=data: raise RuntimeError(f"reference differs: {path}")
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    if args.check:
        if TEST.read_bytes().replace(b"\r\n",b"\n")!=test: raise RuntimeError(f"whitebox differs: {TEST}")
    else: TEST.write_bytes(test)
    print("checked" if args.check else "generated",len(records),"segmentation tools")


if __name__=="__main__": main()
