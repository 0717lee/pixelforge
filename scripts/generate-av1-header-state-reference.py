#!/usr/bin/env python3
"""Independent references for inherited size/superres and AV1 frame IDs."""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-header-state"
TEST = ROOT / "av1_header_state_reference_wbtest.mbt"
spec = importlib.util.spec_from_file_location("grain_reference", ROOT/"scripts/generate-av1-film-grain-sequence-reference.py")
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def bits(data): return [int(c) for byte in data for c in f"{byte:08b}"]
def uint(value, width): return [int(c) for c in f"{value:0{width}b}"]
def packed(data):
    data = data + [0] * (-len(data) % 8)
    return bytes(sum(data[i+j] << (7-j) for j in range(8)) for i in range(0,len(data),8))


def sequence_fields(trace):
    active = False
    fields = {}
    for line in trace.decode().splitlines():
        if line == "Sequence Header":
            if fields: return fields
            active = True
        elif line == "Frame Header":
            if fields: return fields
            active = False
        field = re.match(r"\s*(\d+)\s+(\S+)\s+([01]+)\s*=\s*(-?\d+)\s*$",line)
        if active and field:
            fields[field[2]]=dict(bit=int(field[1]),width=len(field[3]),value=int(field[4]))
    return fields


def header_end(fields, overhead):
    last = "reduced_tx_set" if fields["frame_type"]["value"] == 0 else "is_global[7]"
    return fields[last]["bit"] + fields[last]["width"] - overhead*8


def encode(tools,scratch,name,width,height,frames,kf_denom=8,inter_denom=8,superres=False):
    raw=bytearray()
    for _ in range(frames):
        for plane in range(3):
            w,h=(width,height) if plane==0 else ((width+1)//2,(height+1)//2)
            base=(80,110,160)[plane]
            for y in range(h):
                for x in range(w): raw.append(base+(x*3+y*5)%16+(8 if x>=w//2 else 0)+(6 if y>=h//2 else 0))
    source=scratch/(name+".input.yuv");source.write_bytes(raw)
    target=scratch/(name+".encoder.obu")
    flags=["--codec=av1","--obu","--i420",f"--width={width}",f"--height={height}",f"--limit={frames}","--fps=1/1",
           f"--passes={2 if frames>1 else 1}","--lag-in-frames=0","--threads=1","--row-mt=0","--cpu-used=0",
           "--end-usage=q","--cq-level=20","--debug","--disable-warning-prompt","--deltaq-mode=0",
           "--enable-intrabc=0","--enable-palette=0","--enable-cdef=0","--enable-restoration=0","--loopfilter-control=0",
           "--enable-tx64=0","--sb-size=64","--enable-order-hint=1","--enable-ref-frame-mvs=0",
           "--enable-warped-motion=0","--enable-global-motion=0","--enable-obmc=0","--enable-interintra-comp=0",
           "--enable-masked-comp=0","--enable-dual-filter=0",f"--superres-mode={1 if superres else 0}",
           f"--superres-denominator={inter_denom}",f"--superres-kf-denominator={kf_denom}","-o",target.name,source.name]
    common.run([tools["aomenc"]]+flags,scratch)
    trace,headers=common.trace(tools["ffmpeg"],target,scratch)
    return target.read_bytes(),trace,headers,dict(encoder_command=["aomenc"]+flags,source_sha256=hashlib.sha256(raw).hexdigest())


def inherit_size(original,headers):
    output=bytearray();index=0
    for kind,prefix,payload,overhead in common.packets(original):
        if kind==6:
            if index==1:
                fields=headers[index];data=bits(payload)
                offset=fields["frame_size_override_flag"]["bit"]-overhead*8
                assert data[offset]==0
                data[offset]=1
                insertion=fields["use_superres"]["bit"]-overhead*8
                end=header_end(fields,overhead)
                # Slot zero is already the first named reference. found_ref=1
                # supplies its display geometry and omits render_size syntax.
                assert fields["render_and_frame_size_different"]["value"]==0
                render=fields["render_and_frame_size_different"]["bit"]-overhead*8
                header=data[:insertion]+[1]+data[insertion:render]+data[render+1:end]
                payload=packed(header)+payload[(end+7)//8:]
            index+=1
        output+=prefix+common.leb(len(payload))+payload
    return bytes(output)


def frame_ids(original,trace,headers,bad_delta=False,bad_display=False):
    output=bytearray();index=0;stored=[None]*8
    sequence=sequence_fields(trace)
    for kind,prefix,payload,overhead in common.packets(original):
        if kind==1:
            data=bits(payload);at=sequence["frame_id_numbers_present_flag"]["bit"]-overhead*8
            assert data[at]==0
            end=max(i for i,bit in enumerate(data) if bit)+1
            payload=packed(data[:at]+[1]+[0]*7+data[at+1:end])
        elif kind==6:
            fields=headers[index];data=bits(payload);end=header_end(fields,overhead)
            current=[6,7,0][index]
            insertions=[(fields["frame_size_override_flag"]["bit"]-overhead*8,uint(current,3))]
            if index:
                for ref in range(7):
                    field=fields[f"ref_frame_idx[{ref}]"]
                    slot=field["value"];delta=(current-stored[slot])%8
                    assert 1<=delta<=4
                    value=delta-1
                    if bad_delta and index==2 and ref==6: value=(value+1)%4
                    insertions.append((field["bit"]+3-overhead*8,uint(value,2)))
            header=data[:end]
            for at,value in sorted(insertions,reverse=True): header[at:at]=value
            payload=packed(header)+payload[(end+7)//8:]
            refresh=255 if index==0 else fields["refresh_frame_flags"]["value"]
            for slot in range(8):
                if (refresh>>slot)&1: stored[slot]=current
            index+=1
        output+=prefix+common.leb(len(payload))+payload
    assert index==3
    # Four leading show-existing bits, three ID bits, one trailing-one bit.
    output+=bytes([0x12,0x00,0x1A,0x01,0xA3 if bad_display else 0xA1])
    return bytes(output)


def samples_rle(data):
    pairs=[]
    for value in data:
        if pairs and pairs[-2]==value: pairs[-1]+=1
        else: pairs += [value,1]
    return ''.join('    '+', '.join(map(str,pairs[i:i+24]))+',\n' for i in range(0,len(pairs),24))


def emit_test(records,artifacts):
    out='''/// Generated by scripts/generate-av1-header-state-reference.py.

///|
fn av1_header_state_bytes(hex : String) -> Array[Byte] {
  let chars = hex.to_array()
  let nibble = fn(c : Char) { if c <= '9' { c.to_int()-48 } else { c.to_int()-87 } }
  Array::makei(chars.length()/2, i => (16*nibble(chars[2*i])+nibble(chars[2*i+1])).to_byte())
}

///|
fn av1_header_state_samples(pairs : Array[Int]) -> Array[Int] {
  let output : Array[Int] = []
  for i in 0..<(pairs.length()/2) { for _ in 0..<pairs[i*2+1] { output.push(pairs[i*2]) } }
  output
}
'''
    for record in records:
        name=record['name']
        out+=f'\n///|\ntest "header state {name} matches independent dav1d" {{\n'
        out+='  let stream = av1_header_state_bytes(\n'+common.hex_literal(artifacts[name+'.obu'])+'\n  )\n'
        if record.get('rejected'):
            out+='  assert_true(av1_decode_obu_planes(stream, av1_frame_map(), None, false) is None)\n}\n'
            continue
        out+='  let expected = av1_header_state_samples([\n'+samples_rle(artifacts[name+'.reference.yuv'])+'  ])\n'
        out+='  let map = av1_frame_map()\n  let (_, frames) = av1_decode_obu_planes(stream, map, None, false).unwrap()\n'
        out+=f'  assert_eq(frames.length(), {record["frames"]})\n  let mut offset = 0\n'
        out+=f'  for frame in frames {{\n    assert_eq((frame.width, frame.height), ({record["width"]}, {record["height"]}))\n'
        out+='    for plane in 0..<3 {\n      let samples = av1_frame_crop(frame, plane)\n      for i in 0..<samples.length() { assert_eq(samples[i], expected[offset+i]) }\n      offset = offset + samples.length()\n    }\n  }\n  assert_eq(offset, expected.length())\n'
        if 'coded_widths' in record:
            for slot,coded in enumerate(record['coded_widths']):
                out+=f'  assert_eq(map.slots[{slot}].unwrap().frame_width, {coded})\n'
        if record.get('frame_ids'):
            out+='  assert_eq(map.current_frame_id, 0)\n  assert_true(map.has_frame_id)\n  assert_eq([map.frame_ids[0], map.frame_ids[1], map.frame_ids[2]], [6,7,0])\n'
        out+='}\n'
    return out.encode()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for tool in ('aomenc','dav1d','ffmpeg'): parser.add_argument('--'+tool,default=tool)
    parser.add_argument('--check',action='store_true');args=parser.parse_args()
    tools={tool:common.resolve(getattr(args,tool)) for tool in ('aomenc','dav1d','ffmpeg')}
    artifacts,records={},[]
    with tempfile.TemporaryDirectory(prefix='pixelforge-header-state-') as directory:
        scratch=Path(directory)
        for kf,inter in ((8,12),(12,8),(12,16)):
            name=f'inherit_superres_{kf}_to_{inter}'
            original,traced,headers,metadata=encode(tools,scratch,name,64,64,2,kf,inter,True)
            data=inherit_size(original,headers);path=scratch/(name+'.obu');path.write_bytes(data)
            trace,new_headers=common.trace(tools['ffmpeg'],path,scratch)
            assert new_headers[1]['frame_size_override_flag']['value']==1
            assert new_headers[1]['found_ref[0]']['value']==1
            reference=common.decode(tools['dav1d'],path,scratch,False)
            encoder_path=scratch/(name+'.encoder.obu')
            assert reference==common.decode(tools['dav1d'],encoder_path,scratch,False)
            artifacts.update({name+'.obu':data,name+'.encoder.obu':original,name+'.trace.txt':trace,name+'.reference.yuv':reference})
            records.append(dict(name=name,width=64,height=64,frames=2,coded_widths=[(512+kf//2)//kf,(512+inter//2)//inter],**metadata))
        for width in (8,16,17,24):
            name=f'small_superres_{width}x8_denom16'
            data,trace,headers,metadata=encode(tools,scratch,name,width,8,1,16,16,True)
            assert headers[0]['use_superres']['value']==1 and headers[0]['coded_denom']['value']==7
            path=scratch/(name+'.obu');path.write_bytes(data)
            reference=common.decode(tools['dav1d'],path,scratch,False)
            artifacts.update({name+'.obu':data,name+'.trace.txt':trace,name+'.reference.yuv':reference})
            records.append(dict(name=name,width=width,height=8,frames=1,coded_widths=[max((width*8+8)//16,min(16,width))],**metadata))
        original,trace,headers,metadata=encode(tools,scratch,'frame_id_wrap',64,64,3)
        for variant in ('valid','bad_delta','bad_display'):
            name='frame_id_wrap_'+variant
            data=frame_ids(original,trace,headers,variant=='bad_delta',variant=='bad_display')
            path=scratch/(name+'.obu');path.write_bytes(data)
            artifacts[name+'.obu']=data
            if variant=='valid':
                reference=common.decode(tools['dav1d'],path,scratch,False)
                normal=common.decode(tools['dav1d'],scratch/'frame_id_wrap.encoder.obu',scratch,False)
                assert reference==normal+normal[-6144:]
                checked_trace,checked_headers=common.trace(tools['ffmpeg'],path,scratch)
                assert [h['current_frame_id']['value'] for h in checked_headers[:3]]==[6,7,0]
                artifacts[name+'.reference.yuv']=reference;artifacts[name+'.trace.txt']=checked_trace
                records.append(dict(name=name,width=64,height=64,frames=4,frame_ids=True,**metadata))
            else:
                proc=subprocess.run([tools['dav1d'],'-q','--threads=1','--filmgrain','0','--muxer=yuv','-i',path.name,'-o',name+'.partial.yuv'],cwd=scratch,capture_output=True,text=True)
                errors='\n'.join(line for line in proc.stderr.splitlines() if 'Error' in line or 'error' in line)+'\n'
                partial=(scratch/(name+'.partial.yuv')).read_bytes()
                # The dav1d CLI may return zero after recovering from a corrupt
                # OBU. Require its explicit parser error and missing pictures.
                assert 'Error parsing frame header' in errors and len(partial)<4*6144,(name,proc.returncode,errors)
                artifacts[name+'.error.txt']=errors.encode()
                records.append(dict(name=name,rejected=True,decoder_exit=proc.returncode,partial_frames=len(partial)//6144))
        test=emit_test(records,artifacts);formatted=scratch/TEST.name;formatted.write_bytes(test)
        common.run([common.resolve('moonfmt'),'-w',str(formatted)],ROOT)
        test=formatted.read_bytes().replace(b'\r\n',b'\n')
        versions=dict(aomenc=re.search(r"AOMedia Project AV1 Encoder[^\r\n]+",common.run([tools['aomenc'],'--help'],scratch))[0],
                      dav1d=common.run([tools['dav1d'],'--version'],scratch).strip(),
                      ffmpeg=common.run([tools['ffmpeg'],'-version'],scratch).splitlines()[0])
        manifest=dict(versions=versions,fixtures=records,whitebox_sha256=hashlib.sha256(test).hexdigest(),files={name:dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest()) for name,data in artifacts.items()})
        artifacts['manifest.json']=(json.dumps(manifest,indent=2)+'\n').encode()
    for name,data in artifacts.items():
        path=OUT/name
        if args.check:
            current=path.read_bytes() if path.exists() else None
            if current is not None and path.suffix in ('.txt','.json'): current=current.replace(b'\r\n',b'\n')
            if current!=data: raise RuntimeError(f'reference differs: {path}')
        else: path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    if args.check:
        if TEST.read_bytes().replace(b'\r\n',b'\n')!=test: raise RuntimeError(f'whitebox differs: {TEST}')
    else: TEST.write_bytes(test)
    print('checked' if args.check else 'generated',len(records),'header-state fixtures')


if __name__=='__main__': main()
