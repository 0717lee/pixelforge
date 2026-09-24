#!/usr/bin/env python3
"""Bounded complete AV1 superres frame references, no MoonBit builds.

Fourteen untouched stock encodes cover denom9..16,8/10/12-bit color/mono,
odd crop and two-tile seams. Two explicitly constructed headers reuse unchanged
q0 stock tile entropy to exercise screen/intrabc and restoration syntax gates.
Native references must match unmodified dav1d CLI, FFmpeg/libdav1d and AVIF.
--append-grid-pair adds exactly two even128x64 display cells for AVIF integration.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import math
import re
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]


def module(name,filename):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


fi=module("superres_frame_helpers","generate-av1-filter-intra-reference.py")
small,arithmetic=fi.small,fi.arithmetic
run,sha256,trace_value=fi.run,fi.sha256,fi.trace_value
cdef=module("superres_source_pattern","generate-av1-cdef-frame-reference.py")


def candidates():
    result=[{"depth":10,"monochrome":False,"width":97,"height":65,"denom":denom,"tiles":1} for denom in range(9,17)]
    result += [{"depth":depth,"monochrome":mono,"width":129,"height":65,"denom":12,"tiles":1} for depth,mono in itertools.product((8,12),(False,True))]
    result += [{"depth":10,"monochrome":mono,"width":385,"height":65,"denom":12,"tiles":2} for mono in (False,True)]
    return result


def source_planes(candidate):
    planes=cdef.input_planes(candidate["width"],candidate["height"],candidate["depth"],2)
    return planes[:1] if candidate["monochrome"] else planes


def q0_stream(monochrome):
    directory=ROOT/"tests/fixtures/av1-small-block"
    manifest=json.loads((directory/"manifest.json").read_text(encoding="utf-8"))
    original=next(record for record in manifest["fixtures"] if record["name"]==f"{'mono' if monochrome else 'color'}_16x16_10bit_fixed4_q0")
    data=(directory/original["obu_file"]).read_bytes()
    if sha256(data)!=original["obu_sha256"]:
        raise ValueError("source q0 stock entropy changed")
    tile,_=small.large.frame_tile(data,(directory/original["trace_file"]).read_text(encoding="utf-8"))
    writer=arithmetic.BitWriter()
    for value,bits in ((0,3),(1,1),(1,1),(0,5),(4,4),(3,4),(31,5),(15,4)):
        writer.f(value,bits)  # reducedstill,Up32x16.
    for value in (0,0,0,1,1,1,1,int(monochrome),0,1):
        writer.f(value,1)  # SB64/FI/edge/superres/CDEF/restoration/highbd/mono/description/fullrange.
    if not monochrome:
        writer.f(0,2);writer.f(0,1)
    writer.f(0,1);writer.trailing()
    sequence=writer.to_bytes();writer=arithmetic.BitWriter()
    writer.f(0,1)  # disable_cdf_update: preserve stock adaptive entropy.
    writer.f(1,1)  # allow_screen_content_tools.
    writer.f(1,1)  # force_integer_mv, consumed even on intra then implied1.
    writer.f(1,1);writer.f(7,3)  # use_superres,denom16 -> coded16.
    writer.f(0,1)  # default render32x16.
    # Active superres omits allow_intrabc entirely. All stock blocks are4x4,
    # so enabling screen tools adds no palette symbols to the unchanged tile.
    writer.f(1,1)  # uniform tile spacing, one64SB.
    writer.f(0,8);writer.f(0,1)  # baseq0,Ydc delta absent.
    if not monochrome:
        writer.f(0,1);writer.f(0,1)
    writer.f(0,1);writer.f(0,1)  # qmatrix,segmentation.
    # CodedLossless skips LF/CDEF and tx_mode. AllLossless is false because
    # width changes, so restoration-enabled still reads one NONE type perplane.
    for _ in range(1 if monochrome else 3):
        writer.f(0,2)
    writer.f(0,1)  # reduced_tx_set.
    while len(writer.bits)%8:
        writer.f(0,1)
    result=arithmetic.obu(2,b"")+arithmetic.obu(1,sequence)+arithmetic.obu(6,writer.to_bytes()+tile)
    return result,{"provenance":"complete constructed superres/q0 header with unchanged stock libaom tile entropy",
        "source_obu":str(directory/original["obu_file"]),"source_obu_sha256":original["obu_sha256"],
        "source_tile_sha256":sha256(tile),"source_coded_dimensions":[16,16],"output_dimensions":[32,16],
        "superres_denom":16,"base_q_idx":0,"allow_screen_content_tools":True,"allow_intrabc_bit_present":False,
        "coded_lossless":True,"all_lossless":False,"restoration_types":[0]*(1 if monochrome else 3),
        "unchanged_entropy_boundary":"only header/sequence synthesized; no entropy bytes modified; independent decoders validate complete result"}


def header_evidence(data,trace,width,height,depth,monochrome,denom,tiles,q0=False):
    fields={name:trace_value(trace,name) for name in ("enable_superres","use_superres","coded_denom","enable_restoration","enable_cdef",
        "base_q_idx","mono_chrome","high_bitdepth","color_range","max_frame_width_minus_1","max_frame_height_minus_1",
        "use_128x128_superblock","allow_screen_content_tools","tile_cols_log2","tile_rows_log2","uniform_tile_spacing_flag")}
    if fields["enable_superres"]!=1 or fields["use_superres"]!=1 or fields["coded_denom"]+9!=denom:
        raise ValueError(f"actual superres syntax mismatch: {fields}")
    if fields["max_frame_width_minus_1"]+1!=width or fields["max_frame_height_minus_1"]+1!=height or fields["mono_chrome"]!=monochrome or fields["high_bitdepth"]!=(depth>8) or fields["color_range"]!=1:
        raise ValueError("actual superres output dimensions/format mismatch")
    if fields["tile_cols_log2"]!=tiles.bit_length()-1 or fields["tile_rows_log2"] or fields["uniform_tile_spacing_flag"]!=1 or fields["use_128x128_superblock"]:
        raise ValueError("actual superres tile geometry mismatch")
    coded=(width*8+denom//2)//denom
    if coded<16:
        raise ValueError("this corpus excludes the small-size AOM/spec clamp difference")
    available=(coded+7)//8*8
    sb_cols=(available+63)//64;tile_sb=(sb_cols+tiles-1)//tiles
    starts=list(range(0,sb_cols,tile_sb))+[sb_cols]
    seams=[(start*64*denom)//8 for start in starts[1:-1]]
    levels=[int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)",trace)]
    cdef_config=None
    if not q0:
        bits=trace_value(trace,"cdef_bits")
        cdef_config={"bits":bits,"damping_minus3":trace_value(trace,"cdef_damping_minus_3")}
        for name in ("cdef_y_pri_strength","cdef_y_sec_strength")+(() if monochrome else ("cdef_uv_pri_strength","cdef_uv_sec_strength")):
            cdef_config[name]=cdef.trace_array(trace,name,1<<bits)
    elif fields["base_q_idx"]!=0 or fields["allow_screen_content_tools"]!=1 or fields["enable_restoration"]!=1:
        raise ValueError("q0 constructed header gate mismatch")
    lr_types=[int(value) for value in re.findall(r"lr_type\[\d+\]\s+[^=\n]+=\s*(\d+)",trace)]
    if q0 and (len(lr_types)!=(1 if monochrome else 3) or any(lr_types)):
        raise ValueError(f"q0 superres did not consume per-plane restoration NONE types: {lr_types}")
    if q0 and re.search(r"\ballow_intrabc\s+[^=\n]+=",trace):
        raise ValueError("active superres unexpectedly contains allow_intrabc syntax")
    return {"headers":fields,"coded_visible_width":coded,"source_mi_width":available,"upscaled_width":width,"height":height,
        "superres_denom":denom,"tile_col_starts_sb":starts,"upscaled_tile_seams":seams,"loop_filter_levels":levels,
        "cdef":cdef_config,"restoration_types":lr_types,"q0_header_gate_case":q0,
        "dimensions_evidence":"decoded superres flag/denom and reduced-still maximum dimensions; normative width/MI/tile formulas"}


def filter_toggles(args,name,record,evidence):
    path=args.out/record["obu_file"]
    baseline=(args.out/record["reference_file"]).read_bytes()
    width,height=record["dimensions"];depth=record["bit_depth"];mono=record["monochrome"]
    original=small.native_planes(baseline,depth,mono,width,height)
    counts={};files={};commands={}
    for switch in ("nocdef","nodeblock","none"):
        output=args.out/f"{name}.{switch}.yuv"
        command=[args.dav1d,"--quiet","--input",str(path),"--demuxer","section5","--muxer","yuv","--output",str(output),"--limit","1","--inloopfilters",switch]
        small.helpers.run_binary(command)
        data=output.read_bytes()
        planes=small.native_planes(data,depth,mono,width,height)
        if len(data)!=len(baseline):
            raise ValueError("filter toggle unexpectedly changed superres output dimensions")
        changes=[sum(a!=b for a,b in zip(p,q)) for p,q in zip(original,planes)]
        seam_changes=[]
        for seam in evidence["upscaled_tile_seams"]:
            seam_changes.append(sum(original[0][y*width+x]!=planes[0][y*width+x] for y in range(height) for x in range(max(0,seam-4),min(width,seam+4))))
        counts[switch]={"changed_native_samples_by_plane":changes,"changed_y_samples_near_tile_seams":seam_changes}
        files[switch+"_file"],files[switch+"_sha256"]=output.name,sha256(data);commands[switch]=command
    record.update(files)
    return {"decoder_toggles":counts,"commands":commands,
        "ordering_boundary":"unmodified decoder performs LF then CDEF then superres; toggles prove pre-upscale filters change final native samples, not an alternate-order oracle"}


def generated_test(records,directory):
    # Color vendor RGBA is retained as a binary, not copied into an unused test
    # array; the established converter checks the color API from native planes.
    text=fi.generated_test(records,directory).replace("scripts/generate-av1-filter-intra-reference.py","scripts/generate-av1-superres-reference.py")
    text=text.replace("Actual filter-intra stock syntax and complete five-mode conformance streams.","Actual superres denominators/dimensions and complete native frame references.")
    text=text.replace("av1_filter_intra_tile_reference_","av1_superres_frame_reference_").replace("external filter intra tile","external superres frame")
    for record in records:
        if not record["monochrome"]:
            start=text.index(f'test "external superres frame {record["name"]}"')
            a=text.index("let rgba : Array[Int] = ",start);b=text.index("\n",a)
            text=text[:a]+"let rgba : Array[Int] = []"+text[b:]
    helper="""
///|
fn av1_superres_frame_reference_raw_paths(stream : Array[Byte], avif : Array[Byte],
  width : Int, height : Int, coded : Int, denom : Int, depth : Int, mono : Bool) -> Unit raise {
  let seq = av1_sequence_info(stream).unwrap()
  let frame = av1_parse_stage1_frame(av1_obu_payloads(stream, 6)[0], seq,
    allow_highbd=true, allow_monochrome=true).unwrap()
  assert_eq((frame.frame_width, frame.upscaled_width, frame.superres_denom), (coded, width, denom))
  let stage = avif_stage1_input(avif).unwrap()
  assert_eq((stage.width, stage.frame_width, stage.superres_denom), (width, coded, denom))
  assert_eq(stage.height, height)
  let raw = av1_decode(stream).unwrap()
  let direct = av1_decode_tile_group_with_boundaries(coded, height,
    frame.tile_col_starts_sb, frame.tile_row_starts_sb, 64, frame.tile_payload,
    frame.tile_size_bytes, frame.base_q_idx,
    disable_cdf_update=frame.disable_cdf_update, full_range=true, matrix_coefficients=2,
    bit_depth=depth, allow_screen_content_tools=frame.allow_screen_content_tools,
    tx_mode_select=frame.tx_mode_select, reduced_tx_set=frame.reduced_tx_set,
    enable_filter_intra=seq.enable_filter_intra, enable_intra_edge_filter=seq.enable_intra_edge_filter,
    cdef=frame.cdef, loop_filter=frame.loop_filter, upscaled_width=width, monochrome=mono).unwrap()
  assert_eq((direct.width, direct.height), (width, height))
  for y in 0..<height { for x in 0..<width {
    assert_eq(direct.get_pixel(x,y), raw.get_pixel(x,y))
  } }
  if mono && frame.tile_cols == 1 && frame.tile_rows == 1 {
    let alpha = av1_decode_alpha_tile(coded, height, frame.tile_payload, frame.base_q_idx,
      allow_screen_content_tools=frame.allow_screen_content_tools, bit_depth=depth,
      disable_cdf_update=frame.disable_cdf_update, tx_mode_select=frame.tx_mode_select,
      reduced_tx_set=frame.reduced_tx_set, enable_filter_intra=seq.enable_filter_intra,
      enable_intra_edge_filter=seq.enable_intra_edge_filter, cdef=frame.cdef,
      loop_filter=frame.loop_filter, upscaled_width=width).unwrap()
    assert_eq(alpha.length(), width * height)
    for i in 0..<alpha.length() { assert_eq(alpha[i], raw.get_pixel(i % width, i / width).0) }
  }
}
"""
    text+=helper
    for record in records:
        marker=f'test "external superres frame {record["name"]}"'
        start=text.index(marker);end=text.index("\n}",start)
        width,height=record["dimensions"];fact=record["superres"]
        call=f'\nav1_superres_frame_reference_raw_paths(stream, avif, {width}, {height}, {fact["coded_visible_width"]}, {fact["superres_denom"]}, {record["bit_depth"]}, {str(record["monochrome"]).lower()})'
        text=text[:end]+call+text[end:]
    return text


def finalize(args,records,ledger,scalar_version,previous=None):
    if len(records) not in (16,18) or len(ledger)!=len(records):
        raise ValueError("expected16 original cases or18 with the fixed grid pair")
    stock=[record for record in records if not record["superres"]["q0_header_gate_case"]]
    active_cdef=[r["name"] for r in stock if any(r["filter_order_evidence"]["decoder_toggles"]["nocdef"]["changed_native_samples_by_plane"])]
    active_lf=[r["name"] for r in stock if any(r["filter_order_evidence"]["decoder_toggles"]["nodeblock"]["changed_native_samples_by_plane"])]
    if not set(active_cdef)&set(active_lf):
        raise ValueError("no stock frame proves both pre-superres filters are active")
    encoder=run([args.aomenc,"--help"]);decoder=run([args.dav1d,"--version"])
    sources=[Path(__file__),Path(fi.__file__),Path(cdef.__file__),ROOT/"scripts/generate-av1-small-block-reference.py",ROOT/"scripts/craft_av1_fixture.py"]
    manifest={"scope":f"bounded{len(records)} complete superres references;{len(stock)} untouched stock and2 constructed q0 headers",
        "candidate_limit":len(records),"candidates":ledger,"fixtures":records,"generation_command":[sys.executable,*sys.argv],
        "versions":{"encoder":re.search(r"AOMedia Project AV1 Encoder[^\r\n]+",encoder.stdout+encoder.stderr).group(0),
            "dav1d_cli":(decoder.stdout+decoder.stderr).strip(),"ffmpeg":run([args.ffmpeg,"-version"]).stdout.splitlines()[0],
            "ffmpeg_libdav1d":records[0]["ffmpeg_libdav1d"],"scalar_libavif":scalar_version},
        "coverage":{"actual_denominators":sorted({r["superres"]["superres_denom"] for r in records}),
            "minimum_coded_width":min(r["superres"]["coded_visible_width"] for r in records),"active_cdef_cases":active_cdef,"active_loop_filter_cases":active_lf,
            "q0_header_gates":[r["name"] for r in records if r["superres"]["q0_header_gate_case"]],"tile_seam_cases":[r["name"] for r in records if r["superres"]["upscaled_tile_seams"]]},
        "support_hashes":{p.relative_to(ROOT).as_posix():sha256(p.read_bytes()) for p in sources},
        "normative_sources":["https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/resize.c",
            "https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/decoder/decodeframe.c"],
        "reference_contract":"canonical full native binaries; color nearest420 API contract and actual scalar mono UNORM; vendor RGBA retained without color parity assertion",
        "test_status":"prospective under _refs; no MoonBit build"}
    if previous is not None:
        manifest.update(previous_generation_command=previous["generation_command"],preserved_original_case_count=16,
            grid_pair_scope="exactly128x64 display color/mono10bit,d12; MIAF420 grid cell needs even width/height and both>=64")
    formatted=run([args.moonfmt,"-"],input_text=generated_test(records,args.out)).stdout
    args.test.write_text(formatted,encoding="utf-8",newline="\n")
    manifest["generated_test"],manifest["generated_test_sha256"]=str(args.test),sha256(args.test.read_bytes())
    (args.out/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8",newline="\n")


def check(args):
    manifest=json.loads((args.out/"manifest.json").read_text(encoding="utf-8"))
    if len(manifest["fixtures"]) not in (16,18):
        raise ValueError("expected16 or18 bounded superres references")
    for record in manifest["fixtures"]+manifest["candidates"]:
        for key,name in record.items():
            if key.endswith("_file") and key[:-5]+"_sha256" in record and sha256((args.out/name).read_bytes())!=record[key[:-5]+"_sha256"]:
                raise ValueError(f"artifact hash mismatch: {name}")
    for candidate in manifest["candidates"]:
        if candidate["kind"]=="stock":
            plan=candidate["candidate"]
            source=b"".join(small.mono_helpers.pack(p,plan["depth"]) for p in source_planes(plan))
            if source!=(args.out/candidate["source_file"]).read_bytes():
                raise ValueError("stock source formula changed")
            data=(args.out/candidate["obu_file"]).read_bytes();q0=False
            params=(plan["width"],plan["height"],plan["depth"],plan["monochrome"],plan["denom"],plan["tiles"])
        else:
            data,syntax=q0_stream(candidate["monochrome"]);q0=True
            if data!=(args.out/candidate["obu_file"]).read_bytes() or syntax!=json.loads((args.out/candidate["syntax_file"]).read_text(encoding="utf-8")):
                raise ValueError("q0 header construction/source entropy changed")
            params=(32,16,10,candidate["monochrome"],16,1)
        trace=(args.out/candidate["trace_file"]).read_text(encoding="utf-8")
        if header_evidence(data,trace,*params,q0)!=candidate["superres"]:
            raise ValueError("actual superres header evidence changed")
    for name,expected in manifest["support_hashes"].items():
        if sha256((ROOT/name).read_bytes())!=expected:
            raise ValueError(f"source hash mismatch: {name}")
    formatted=run([args.moonfmt,"-"],input_text=generated_test(manifest["fixtures"],args.out)).stdout
    if args.test.read_text(encoding="utf-8")!=formatted:
        raise ValueError("canonical generated superres tests changed")
    print(f"checked{len(manifest['fixtures'])} native references,actualheader/denominator evidence,q0 entropy reuse,and canonical tests")


def append_grid_pair(args):
    previous=json.loads((args.out/"manifest.json").read_text(encoding="utf-8"))
    if len(previous["fixtures"])!=16:
        raise ValueError("grid-pair append requires exactly16 original references")
    small.large.verify_existing_artifacts(previous,args.out)
    scalar,scalar_version=small.mono_helpers.scalar_library(args.libavif_scalar)
    records,ledger=previous["fixtures"].copy(),previous["candidates"].copy()
    for mono in (False,True):
        candidate={"depth":10,"monochrome":mono,"width":128,"height":64,"denom":12,"tiles":1}
        name=f"stock_{'mono' if mono else 'color'}_10bit_d12_128x64_1tile"
        source=b"".join(small.mono_helpers.pack(p,10) for p in source_planes(candidate))
        sp,ip,op,tp=(args.out/(name+suffix) for suffix in (".source.yuv",".input.y4m",".obu",".trace.txt"))
        sp.write_bytes(source)
        payload=source+small.mono_helpers.pack([512]*(64*32*2),10) if mono else source
        ip.write_bytes(b"YUV4MPEG2 W128 H64 F1:1 Ip A1:1 C420p10 XCOLORRANGE=FULL\nFRAME\n"+payload)
        encode=previous["candidates"][0]["encoder_command"].copy()
        changes={"width":128,"height":64,"superres-denominator":12,"superres-kf-denominator":12}
        encode[0],encode[-2],encode[-1]=args.aomenc,str(op),str(ip)
        for i,arg in enumerate(encode):
            for key,value in changes.items():
                if arg.startswith(f"--{key}="):
                    encode[i]=f"--{key}={value}"
        if mono:encode.insert(1,"--monochrome")
        run(encode)
        trace=run([args.ffmpeg,"-hide_banner","-i",str(op),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        tp.write_text(trace,encoding="utf-8",newline="\n")
        fact=header_evidence(op.read_bytes(),trace,128,64,10,mono,12,1)
        record=fi.references(args,name,op.read_bytes(),128,64,10,mono,scalar)
        record.update(provenance="untouched libaom encoder output",superres=fact)
        record["filter_order_evidence"]=filter_toggles(args,name,record,fact)
        entry={"name":name,"kind":"stock","candidate":candidate,"encoder_command":encode,"superres":fact,"outcome":"native validated"}
        for key,p in (("source",sp),("input",ip),("obu",op),("trace",tp)):
            entry[key+"_file"],entry[key+"_sha256"]=p.name,sha256(p.read_bytes())
        records.append(record);ledger.append(entry)
        print(name,"coded",fact["coded_visible_width"],"native/AVIF validated",flush=True)
    small.large.verify_existing_artifacts(previous,args.out)
    finalize(args,records,ledger,scalar_version,previous)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,default=ROOT/"tests/fixtures/av1-superres")
    parser.add_argument("--test",type=Path,default=ROOT/"_refs/av1_superres_reference_wbtest.mbt")
    for name in ("aomenc","ffmpeg","dav1d","moonfmt"):
        parser.add_argument("--"+name,default=shutil.which(name) or name)
    parser.add_argument("--libavif-scalar",default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--append-grid-pair",action="store_true")
    args=parser.parse_args()
    if args.check:
        return check(args)
    if args.append_grid_pair:
        return append_grid_pair(args)
    args.out.mkdir(parents=True,exist_ok=True)
    if (args.out/"manifest.json").exists():
        raise ValueError("bounded16-case superres corpus already exists")
    scalar,scalar_version=small.mono_helpers.scalar_library(args.libavif_scalar)
    source_manifest=json.loads((ROOT/"tests/fixtures/av1-cfl/manifest.json").read_text(encoding="utf-8"))
    records,ledger=[],[]
    for candidate in candidates():
        depth,mono,width,height,denom,tiles=(candidate[key] for key in ("depth","monochrome","width","height","denom","tiles"))
        name=f"stock_{'mono' if mono else 'color'}_{depth}bit_d{denom}_{width}x{height}_{tiles}tile"
        planes=source_planes(candidate);source=b"".join(small.mono_helpers.pack(p,depth) for p in planes)
        sp,ip,op,tp=(args.out/(name+suffix) for suffix in (".source.yuv",".input.y4m",".obu",".trace.txt"))
        sp.write_bytes(source)
        fmt="mono" if mono and depth==8 else "420" if depth==8 else f"420p{depth}"
        cw,ch=(width+1)//2,(height+1)//2
        payload=source+small.mono_helpers.pack([1<<(depth-1)]*(2*cw*ch),depth) if mono and depth>8 else source
        ip.write_bytes(f"YUV4MPEG2 W{width} H{height} F1:1 Ip A1:1 C{fmt} XCOLORRANGE=FULL\nFRAME\n".encode()+payload)
        encode=source_manifest["candidates"][0]["encoder_command"].copy()
        changes={"width":width,"height":height,"profile":2 if depth==12 else 0,"bit-depth":depth,"input-bit-depth":depth,
            "cq-level":40,"tile-columns":tiles.bit_length()-1,"enable-cdef":1,"loopfilter-control":1,"enable-cfl-intra":0,
            "min-partition-size":8,"max-partition-size":16}
        encode[0],encode[-2],encode[-1]=args.aomenc,str(op),str(ip)
        for i,arg in enumerate(encode):
            for key,value in changes.items():
                if arg.startswith(f"--{key}="):
                    encode[i]=f"--{key}={value}"
        encode[1:1]=["--superres-mode=1",f"--superres-denominator={denom}",f"--superres-kf-denominator={denom}"]
        if mono:encode.insert(1,"--monochrome")
        run(encode)
        trace=run([args.ffmpeg,"-hide_banner","-i",str(op),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        tp.write_text(trace,encoding="utf-8",newline="\n")
        fact=header_evidence(op.read_bytes(),trace,width,height,depth,mono,denom,tiles)
        record=fi.references(args,name,op.read_bytes(),width,height,depth,mono,scalar)
        record.update(provenance="untouched libaom encoder output",superres=fact)
        record["filter_order_evidence"]=filter_toggles(args,name,record,fact)
        entry={"name":name,"kind":"stock","candidate":candidate,"encoder_command":encode,"superres":fact,"outcome":"native validated"}
        for key,p in (("source",sp),("input",ip),("obu",op),("trace",tp)):
            entry[key+"_file"],entry[key+"_sha256"]=p.name,sha256(p.read_bytes())
        records.append(record);ledger.append(entry)
        print(name,"coded",fact["coded_visible_width"],"changes",record["filter_order_evidence"]["decoder_toggles"],flush=True)
    for mono in (False,True):
        name=f"constructed_{'mono' if mono else 'color'}_10bit_d16_q0_header_gates"
        data,syntax=q0_stream(mono)
        op,tp,sy=(args.out/(name+suffix) for suffix in (".obu",".trace.txt",".syntax.json"))
        op.write_bytes(data);sy.write_text(json.dumps(syntax,indent=2)+"\n",encoding="utf-8",newline="\n")
        trace=run([args.ffmpeg,"-hide_banner","-i",str(op),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        tp.write_text(trace,encoding="utf-8",newline="\n")
        fact=header_evidence(data,trace,32,16,10,mono,16,1,True)
        record=fi.references(args,name,data,32,16,10,mono,scalar)
        record.update(provenance=syntax["provenance"],superres=fact,syntax_file=sy.name,syntax_sha256=sha256(sy.read_bytes()))
        records.append(record)
        ledger.append({"name":name,"kind":"constructed_q0","monochrome":mono,"superres":fact,"obu_file":op.name,"obu_sha256":sha256(data),
            "trace_file":tp.name,"trace_sha256":sha256(tp.read_bytes()),"syntax_file":sy.name,"syntax_sha256":sha256(sy.read_bytes()),"outcome":"native validated"})
        print(name,"q0 gates/native validated",flush=True)
    finalize(args,records,ledger,scalar_version)


if __name__=="__main__":
    main()
