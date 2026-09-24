#!/usr/bin/env python3
"""Filter-intra tile references:12 stock candidates and at most5 constructions.

Expected native samples come from two unmodified dav1d decoders and an AVIF
remux. The entropy-only reader records actual filter flags/modes through tile
termination. Stock flags alone are not coverage. No MoonBit builds run.
"""

# Entropy-reader adaptation of go-av1, BSD 2-Clause License.
# Copyright (c) 2026, Oleksandr Zhabotynskyi
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
    value=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


base=module("filter_intra_tile_helpers","generate-av1-directional-tile-reference.py")
small,arithmetic=base.small,base.arithmetic
run,sha256,trace_value=base.run,base.sha256,base.trace_value
FILTER_TX_CONTEXT=(0,1,2,6,0)


def source_planes(depth,monochrome,texture):
    result=[]
    for plane in range(1 if monochrome else 3):
        side=32 if plane==0 else 16
        values=[]
        for y in range(side):
            for x in range(side):
                xx,yy=(x+.5)/side,(y+.5)/side
                value=(38+94*xx+77*yy+12*math.cos((x+y+plane)*math.pi/9)) if texture==0 else (
                    62+57*math.sin((x+plane)*math.pi/19)+66*xx*yy+25*math.cos((y+plane)*math.pi/13))
                values.append(max(0,min((1<<depth)-1,round(value*(1<<(depth-8))))))
        result.append(values)
    return result


def read_stock(stream,trace):
    fields={name:base.field(trace,name) for name in ("base_q_idx","tx_mode","reduced_tx_set","disable_cdf_update","mono_chrome",
        "enable_filter_intra","enable_cdef","enable_restoration","allow_screen_content_tools","segmentation_enabled","delta_q_present",
        "max_frame_width_minus_1","max_frame_height_minus_1","tile_cols_log2","tile_rows_log2")}
    if fields["enable_filter_intra"]!=1 or fields["tx_mode"]!=1 or fields["base_q_idx"]<=0 or fields["max_frame_width_minus_1"]!=31 or fields["max_frame_height_minus_1"]!=31:
        raise ValueError("stock reader requires32x32 nonlossless maximum-TX filter-intra")
    if any(fields[name] for name in ("enable_cdef","enable_restoration","segmentation_enabled","delta_q_present","tile_cols_log2","tile_rows_log2")):
        raise ValueError("stock reader encountered an unsupported header tool")
    if base.field(trace,"color_range")!=1 or base.field(trace,"color_description_present_flag")!=0:
        raise ValueError("stock corpus requires full range and unspecified matrix2")
    tile,header_bytes=small.large.frame_tile(stream,trace)
    reader=base.Reader(tile,allow_update=not fields["disable_cdf_update"])
    tables=arithmetic.Tables()
    coeffs=base.Coefficients(reader,tables,fields["base_q_idx"],bool(fields["reduced_tx_set"]))
    partitions={32:tables.partition_w32,16:arithmetic._parse_go_table("DefaultPartitionW16Cdf"),8:arithmetic._parse_go_table("DefaultPartitionW8Cdf")}
    flags=arithmetic._parse_go_table("DefaultFilterIntraCdf")
    modes=arithmetic._parse_go_table("DefaultFilterIntraModeCdf")
    angles=arithmetic._parse_go_table("DefaultAngleDeltaCdf")
    palette_y=arithmetic._parse_go_table("DefaultPaletteYModeCdf")
    palette_uv=arithmetic._parse_go_table("DefaultPaletteUvModeCdf")
    y_modes,skips,sizes=([[0]*8 for _ in range(8)] for _ in range(3))
    blocks,partition_trace=[],[]
    def leaf(x,y,side):
        row,col,units=y//4,x//4,side//4
        owner=not fields["mono_chrome"] and (side!=4 or (row%2==1 and col%2==1))
        reader.where=f"filter block({x},{y}) {side}"
        skip_context=(skips[row-1][col] if row else 0)+(skips[row][col-1] if col else 0)
        skip=reader.symbol(tables.skip[skip_context])
        above=y_modes[row-1][col] if row else 0
        left=y_modes[row][col-1] if col else 0
        ym=reader.symbol(tables.y_mode[base.Y_CONTEXT[above]][base.Y_CONTEXT[left]])
        yd=reader.symbol(angles[ym-1])-3 if side>=8 and 1<=ym<=8 else 0
        um,ud=None,0
        if owner:
            um=reader.symbol(tables.uv_mode_cfl[ym])
            if um==13:
                raise ValueError("CfL is outside this filter-intra corpus")
            ud=reader.symbol(angles[um-1])-3 if side>=8 and 1<=um<=8 else 0
        if fields["allow_screen_content_tools"] and side>=8:
            context=2*(side.bit_length()-1)-6
            if ym==0 and reader.symbol(palette_y[context][0]):
                raise ValueError("luma palette outside filter-intra corpus")
            if owner and um==0 and reader.symbol(palette_uv[0]):
                raise ValueError("chroma palette outside filter-intra corpus")
        # The gate does not depend on skip. UV has no filter-intra syntax.
        enabled=reader.symbol(flags[{4:0,8:3,16:6}[side]]) if ym==0 else 0
        mode=reader.symbol(modes) if enabled else None
        pseudo=FILTER_TX_CONTEXT[mode] if enabled else ym
        for r in range(row,row+units):
            for c in range(col,col+units):
                y_modes[r][c],skips[r][c],sizes[r][c]=ym,skip,side
        result={"origin":[x,y],"coding_dimensions":[side,side],"has_chroma":owner,"skip":skip,"y_mode":ym,"y_delta":yd,
            "uv_mode":um,"uv_delta":ud,"use_filter_intra":bool(enabled),"filter_mode":mode,"luma_tx_cdf_direction":pseudo,"transforms":[]}
        for plane in range(3 if owner else 1):
            px,py=(x,y) if plane==0 else ((col>>1)*4,(row>>1)*4)
            result["transforms"].append(coeffs.read(plane,px,py,side,skip,pseudo if plane==0 else ym,um))
        blocks.append(result)
    def partition(x,y,side):
        if side==4:
            leaf(x,y,side);return
        row,col=y//4,x//4
        context=int(row>0 and sizes[row-1][col]<side)+2*int(col>0 and sizes[row][col-1]<side)
        value=reader.symbol(partitions[side][context])
        partition_trace.append({"origin":[x,y],"size":side,"context":context,"symbol":value})
        if value==3:
            half=side//2
            for dx,dy in ((0,0),(half,0),(0,half),(half,half)):
                partition(x+dx,y+dy,half)
        elif value==0 and side<=16:
            leaf(x,y,side)
        else:
            raise ValueError(f"unsupported actual stock partition {side}/{value}")
    partition(0,0,32)
    return {"scope":"complete independent partition/mode/filter/coeff entropy trace","headers":fields,"frame_header_bytes":header_bytes,
        "partitions":partition_trace,"blocks":blocks,"entropy_end":reader.finish(),"filter_blocks":sum(b["use_filter_intra"] for b in blocks)}


def references(args,name,data,width,height,depth,monochrome,scalar):
    if not monochrome:
        record=base.cfl.references(args,name,data,width,height,depth,scalar)
        record["monochrome"]=False
        return record
    obu=args.out/(name+".obu");native=args.out/(name+".reference.yuv")
    pixel_format="gray" if depth==8 else f"gray{depth}le"
    decode=[args.ffmpeg,"-hide_banner","-loglevel","verbose","-xerror","-y","-c:v","libdav1d","-i",str(obu),"-frames:v","1","-f","rawvideo","-pix_fmt",pixel_format,str(native)]
    output=run(decode);reference=native.read_bytes()
    values=small.native_planes(reference,depth,True,width,height)[0]
    cli_path=args.out/(name+".cli.yuv")
    cli=[args.dav1d,"--quiet","--input",str(obu),"--demuxer","section5","--muxer","yuv","--output",str(cli_path),"--limit","1"]
    small.helpers.run_binary(cli)
    if cli_path.read_bytes()!=reference:
        raise ValueError("monochrome dav1d native decoders disagree")
    cli_path.unlink()
    avif=args.out/(name+".avif")
    wrap=[args.ffmpeg,"-hide_banner","-loglevel","error","-y","-i",str(obu),"-c","copy","-frames:v","1","-f","avif",str(avif)]
    run(wrap)
    avif_native=args.out/(name+".avif.native.yuv")
    second=decode.copy();second[second.index("-i")+1]=str(avif);second[-1]=str(avif_native);run(second)
    if avif_native.read_bytes()!=reference:
        raise ValueError("monochrome AVIF remux changed pixels")
    avif_native.unlink()
    rgba=small.mono_helpers.scalar_rgba(avif.read_bytes(),scalar)
    scalar_path=args.out/(name+".scalar_libavif.rgba");scalar_path.write_bytes(rgba)
    if not (len(rgba)==width*height*4 and rgba[0::4]==rgba[1::4]==rgba[2::4] and all(v==255 for v in rgba[3::4])):
        raise ValueError("invalid monochrome scalar RGBA")
    raw=args.out/(name+".raw_ffmpeg.rgba");rgb=decode.copy();rgb[rgb.index("-pix_fmt")+1]="rgba";rgb[-1]=str(raw);run(rgb)
    record={"name":name,"dimensions":[width,height],"bit_depth":depth,"monochrome":True,"native_pixel_format":pixel_format,
        "native_cli_matches_ffmpeg":True,"avif_native_matches_obu":True,"native_plane_ranges":[[min(values),max(values)]],
        "ffmpeg_libdav1d":re.findall(r"libdav1d\s+([0-9][^\s]*)",output.stderr)[0],
        "rgba_assertion_contract":"actual scalar libavif full-range UNORM", "vendor_rgb_parity_asserted":True,
        "raw_ffmpeg_vs_scalar_differing_bytes":sum(a!=b for a,b in zip(raw.read_bytes(),rgba)),
        "commands":{"decode_native":decode,"dav1d_cli":cli,"wrap_avif":wrap,"decode_avif_native":second,"decode_raw_rgba":rgb}}
    for key,p in (("obu",obu),("avif",avif),("reference",native),("rgba_reference",scalar_path),("raw_rgba",raw)):
        record[key+"_file"],record[key+"_sha256"]=p.name,sha256(p.read_bytes())
    return record


def generated_test(records,directory):
    return (small.generated_test(records,directory).replace("scripts/generate-av1-small-block-reference.py","scripts/generate-av1-filter-intra-reference.py")
        .replace("Stock libaom fixed4 and explicitly constructed rectangle conformance streams.","Actual filter-intra stock syntax and complete five-mode conformance streams.")
        .replace("av1_small_reference_","av1_filter_intra_tile_reference_").replace("external small coding block","external filter intra tile")
        .replace("assert_eq(frame.planes.length(), planes.length())","assert_eq(frame.planes.length(), planes.length())\n  assert_eq((frame.full_range, frame.matrix_coefficients), (true, 2))"))


def write_manifest(args,manifest):
    source=run([args.moonfmt,"-"],input_text=generated_test(manifest["fixtures"],args.out)).stdout
    args.test.write_text(source,encoding="utf-8",newline="\n")
    manifest["generated_test"],manifest["generated_test_sha256"]=str(args.test),sha256(args.test.read_bytes())
    (args.out/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8",newline="\n")


def stock(args):
    args.out.mkdir(parents=True,exist_ok=True)
    if (args.out/"manifest.json").exists():
        raise ValueError("bounded stock matrix already exists")
    scalar,scalar_version=small.mono_helpers.scalar_library(args.libavif_scalar)
    source_manifest=json.loads((ROOT/"tests/fixtures/av1-directional-tile/manifest.json").read_text(encoding="utf-8"))
    ledger,records=[],[]
    for mono,depth,texture in itertools.product((False,True),(8,10,12),(0,1)):
        name=f"stock_{'mono' if mono else 'color'}_{depth}bit_texture{texture}_32x32"
        native=b"".join(small.mono_helpers.pack(plane,depth) for plane in source_planes(depth,mono,texture))
        source_path,input_path,obu,trace_path,syntax_path=(args.out/(name+suffix) for suffix in (".source.yuv",".input.y4m",".obu",".trace.txt",".syntax.json"))
        source_path.write_bytes(native)
        format_name="mono" if mono and depth==8 else "420" if depth==8 else f"420p{depth}"
        payload=native+small.mono_helpers.pack([1<<(depth-1)]*512,depth) if mono and depth>8 else native
        input_path.write_bytes(f"YUV4MPEG2 W32 H32 F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode()+payload)
        encode=source_manifest["candidates"][0]["encoder_command"].copy()
        changes={"profile":2 if depth==12 else 0,"bit-depth":depth,"input-bit-depth":depth,"enable-filter-intra":1,
            "enable-diagonal-intra":0,"enable-directional-intra":0,"enable-smooth-intra":0,"enable-paeth-intra":0,
            "enable-angle-delta":0,"enable-intra-edge-filter":0,"enable-cfl-intra":0}
        encode[0],encode[-2],encode[-1]=args.aomenc,str(obu),str(input_path)
        for i,arg in enumerate(encode):
            for key,value in changes.items():
                if arg.startswith(f"--{key}="):
                    encode[i]=f"--{key}={value}"
        if mono:
            encode.insert(1,"--monochrome")
        run(encode)
        trace=run([args.ffmpeg,"-hide_banner","-i",str(obu),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        trace_path.write_text(trace,encoding="utf-8",newline="\n")
        syntax=read_stock(obu.read_bytes(),trace)
        syntax_path.write_text(json.dumps(syntax,indent=2)+"\n",encoding="utf-8",newline="\n")
        entry={"name":name,"provenance":"untouched libaom encoder output","monochrome":mono,"bit_depth":depth,"texture":texture,
            "dimensions":[32,32],"encoder_partition_bounds":[16,16],"encoder_command":encode,"outcome":"complete entropy/native validation",
            "actual_filter_modes":[b["filter_mode"] for b in syntax["blocks"] if b["use_filter_intra"]]}
        for key,p in (("source",source_path),("input",input_path),("obu",obu),("trace",trace_path),("syntax",syntax_path)):
            entry[key+"_file"],entry[key+"_sha256"]=p.name,sha256(p.read_bytes())
        ledger.append(entry)
        record=references(args,name,obu.read_bytes(),32,32,depth,mono,scalar)
        record.update(provenance=entry["provenance"],syntax_file=syntax_path.name,syntax_sha256=entry["syntax_sha256"],actual_filter_modes=entry["actual_filter_modes"])
        records.append(record)
        print(name,"actual filter modes",entry["actual_filter_modes"],flush=True)
    write_manifest(args,{"scope":"bounded12 color/mono8/10/12 stock filter-intra candidates with complete entropy traces","candidate_limit":12,
        "candidates":ledger,"fixtures":records,"scalar_libavif_version":scalar_version,"generation_command":[sys.executable,*sys.argv],
        "test_status":"prospective under _refs; no MoonBit build"})


def conformance_plans():
    return [
        {"name":"constructed_filter0_dc_crop13","mode":0,"size":13,"shape":[8,8],"partition":"split8","select":False,"skip_last":True},
        {"name":"constructed_filter1_v_4x16","mode":1,"size":16,"shape":[4,16],"partition":"vert4","select":False},
        {"name":"constructed_filter2_h_16x4","mode":2,"size":16,"shape":[16,4],"partition":"horz4","select":False},
        {"name":"constructed_filter3_d157_block32_tx16","mode":3,"size":32,"shape":[32,32],"partition":"none32","select":True},
        {"name":"constructed_filter4_paeth_sub8_crop13","mode":4,"size":13,"shape":[4,4],"partition":"split4","select":False},
    ]


def headers(size,select):
    bw=arithmetic.BitWriter();bits=(size-1).bit_length()
    for value,n in ((0,3),(1,1),(1,1),(0,5),(bits-1,4),(bits-1,4),(size-1,bits),(size-1,bits)):
        bw.f(value,n)
    for value in (0,1,0,0,0,0,1,0,0,1):
        bw.f(value,1)  # SB64/FI/edge/superres/CDEF/restoration/highbd/mono/description/fullrange.
    bw.f(0,2);bw.f(0,1);bw.f(0,1);bw.trailing()
    sequence=bw.to_bytes();bw=arithmetic.BitWriter()
    for value in (0,0,0,1):
        bw.f(value,1)
    bw.f(32,8)
    for _ in range(6):
        bw.f(0,1)  # Ydc/Udc/Uac deltas, qmatrix, segmentation, delta_q.
    bw.f(0,6);bw.f(0,6);bw.f(0,3);bw.f(0,1);bw.f(int(select),1);bw.f(0,1)
    while len(bw.bits)%8:
        bw.f(0,1)
    return sequence,bw.to_bytes()


def constructed_stream(plan):
    lossy=base.cfl.rectangle_helpers()
    enc,tables=lossy.CheckedEncoder(),arithmetic.Tables()
    flags=arithmetic._parse_go_table("DefaultFilterIntraCdf");modes=arithmetic._parse_go_table("DefaultFilterIntraModeCdf")
    part8=arithmetic._parse_go_table("DefaultPartitionW8Cdf");part16=arithmetic._parse_go_table("DefaultPartitionW16Cdf")
    eob_tables={16:tables.eob_pt_16,32:arithmetic._parse_go_table("DefaultEobPt32Cdf"),64:tables.eob_pt_64}
    top_level,left_level,top_dc,left_dc=([[0]*8 for _ in range(3)] for _ in range(4))
    sizes=[[0]*8 for _ in range(8)]
    blocks=[]
    mode,pseudo=plan["mode"],FILTER_TX_CONTEXT[plan["mode"]]
    def emit(x,y,width,height):
        mx,my=x//4,y//4
        owner=(width!=4 or mx%2==1) and (height!=4 or my%2==1)
        skip=bool(plan.get("skip_last") and x==8 and y==8)
        enc.encode_symbol(tables.skip[0],int(skip))
        enc.encode_symbol(tables.y_mode[0][0],0)
        if owner:
            enc.encode_symbol(tables.uv_mode_cfl[0],0)
        block_id={(4,4):0,(8,8):3,(4,16):16,(16,4):17,(32,32):9}[width,height]
        enc.encode_symbol(flags[block_id],1)
        enc.encode_symbol(modes,mode)
        if plan["select"]:
            enc.encode_symbol(tables.tx32[0],1)  # coding32 maxTX32→TX16, before any residuals.
        evidence={"origin":[x,y],"dimensions":[width,height],"block_enum":block_id,"skip":skip,"has_chroma":owner,
            "y_mode":0,"uv_mode":0 if owner else None,"use_filter_intra":True,"filter_mode":mode,"luma_tx_cdf_direction":pseudo,
            "tx_depth":1 if plan["select"] else 0,"transforms":[]}
        for yy in range(my,my+height//4):
            for xx in range(mx,mx+width//4):
                sizes[yy][xx]=width
        for plane in range(3 if owner else 1):
            pw,ph=(width,height) if plane==0 else (max(4,width//2),max(4,height//2))
            txw,txh=(16,16) if plane==0 and plan["select"] else (pw,ph)
            bx,by=(x,y) if plane==0 else ((x//8)*4,(y//8)*4)
            for oy in range(0,ph,txh):
                for ox in range(0,pw,txw):
                    px,py=bx+ox,by+oy;sx,sy,nw,nh=px//4,py//4,txw//4,txh//4
                    if skip:
                        cumulative,category=0,0
                        coef={"all_zero_context":None,"eob":0,"skip":True}
                    else:
                        top,left=top_level[plane][sx:sx+nw],left_level[plane][sy:sy+nh]
                        whole=txw*txh==pw*ph
                        context=arithmetic.txb_skip_ctx_luma(max(top),max(left),whole) if plane==0 else 7+int(any(top))+int(any(left))+(0 if whole else 3)
                        enc.encode_symbol(tables.txb_skip[1][lossy.tx_context(txw,txh)][context],0)
                        if plane==0 and max(txw,txh)<32:
                            cdf=tables.intra_tx_set2[2][pseudo] if min(txw,txh)==16 else tables.intra_tx_set1[1 if min(txw,txh)==8 else 0][pseudo]
                            enc.encode_symbol(cdf,1)
                        score=sum(-1 if v==1 else 1 if v==2 else 0 for v in top_dc[plane][sx:sx+nw]+left_dc[plane][sy:sy+nh])
                        dc_context=1 if score<0 else 2 if score>0 else 0
                        if txw==txh:
                            scan=arithmetic.build_scan(txw,0)
                            levels={scan[0]:2,scan[1]:2,scan[2]:2}
                            cumulative,category=arithmetic.encode_leaf_coeffs(enc,tables,32,txw,int(plane!=0),levels,0,dc_context)
                            coef={"eob":3,"positive_quantized_levels":list(map(list,levels.items())),"dc_sign_context":dc_context}
                        else:
                            coef=lossy.coefficients(enc,tables,eob_tables,(txw,txh),int(plane!=0),dc_context)
                            cumulative,category=6,2
                        coef["all_zero_context"]=context
                    top_level[plane][sx:sx+nw],left_level[plane][sy:sy+nh]=[cumulative]*nw,[cumulative]*nh
                    top_dc[plane][sx:sx+nw],left_dc[plane][sy:sy+nh]=[category]*nw,[category]*nh
                    evidence["transforms"].append({"plane":plane,"origin":[px,py],"size":[txw,txh],
                        "filter_intra_applied":plane==0,"tx_type":"DCT_DCT","tx_type_signaled":plane==0 and max(txw,txh)<32 and not skip,**coef})
        blocks.append(evidence)
    def split(x,y,side,to4):
        row,col=y//4,x//4
        context=int(y>0 and sizes[row-1][col]<side)+2*int(x>0 and sizes[row][col-1]<side)
        should_split=side==16 or to4
        enc.encode_symbol((part16 if side==16 else part8)[context],3 if should_split else 0)
        if should_split:
            half=side//2
            for dx,dy in ((0,0),(half,0),(0,half),(half,half)):
                if half==4:
                    emit(x+dx,y+dy,4,4)
                else:
                    split(x+dx,y+dy,half,to4)
        else:
            emit(x,y,8,8)
    if plan["partition"] in ("split8","split4"):
        split(0,0,16,plan["partition"]=="split4")
    elif plan["partition"]=="none32":
        enc.encode_symbol(tables.partition_w32[0],0);emit(0,0,32,32)
    else:
        enc.encode_symbol(part16[0],9 if plan["partition"]=="vert4" else 8)
        for i in range(4):
            emit(i*4 if plan["partition"]=="vert4" else 0,0 if plan["partition"]=="vert4" else i*4,*plan["shape"])
    tile=enc.finish();reader=arithmetic.MsacDecoder(tile)
    for cdf,symbol in enc.symbols:
        if reader.symbol(cdf)!=symbol:
            raise ValueError("filter-intra construction arithmetic roundtrip failed")
    sequence,frame=headers(plan["size"],plan["select"])
    data=arithmetic.obu(2,b"")+arithmetic.obu(1,sequence)+arithmetic.obu(6,frame+tile)
    return data,{"provenance":"complete constructed q32 filter-intra syntax, not encoder output or patched entropy","plan":plan,
        "bit_depth":10,"blocks":blocks,"entropy_symbols_checked":len(enc.symbols),"raw_y_mode_remains_dc":True,
        "transform_cdf_filter_mode_mapping":list(FILTER_TX_CONTEXT),"uv_filter_intra_syntax":False}


def conformance(args):
    path=args.out/"manifest.json";previous=json.loads(path.read_text(encoding="utf-8"))
    if len(previous["candidates"])!=12:
        raise ValueError("bounded construction append requires12 stock candidates")
    small.large.verify_existing_artifacts(previous,args.out)
    scalar,_=small.mono_helpers.scalar_library(args.libavif_scalar)
    records,ledger=previous["fixtures"].copy(),previous["candidates"].copy()
    for plan in conformance_plans():
        name=plan["name"];data,syntax=constructed_stream(plan)
        obu,sy,tr=(args.out/(name+suffix) for suffix in (".obu",".syntax.json",".trace.txt"))
        obu.write_bytes(data);sy.write_text(json.dumps(syntax,indent=2)+"\n",encoding="utf-8",newline="\n")
        trace=run([args.ffmpeg,"-hide_banner","-i",str(obu),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        tr.write_text(trace,encoding="utf-8",newline="\n")
        if trace_value(trace,"enable_filter_intra")!=1 or trace_value(trace,"base_q_idx")!=32 or trace_value(trace,"tx_mode")!=(2 if plan["select"] else 1):
            raise ValueError("constructed filter-intra header mismatch")
        record=references(args,name,data,plan["size"],plan["size"],10,False,scalar)
        record.update(provenance=syntax["provenance"],syntax_file=sy.name,syntax_sha256=sha256(sy.read_bytes()),trace_file=tr.name,trace_sha256=sha256(tr.read_bytes()),actual_filter_modes=[plan["mode"]])
        records.append(record)
        ledger.append({"name":name,"kind":"constructed","provenance":syntax["provenance"],"obu_file":obu.name,"obu_sha256":sha256(data),
            "syntax_file":sy.name,"syntax_sha256":sha256(sy.read_bytes()),"actual_filter_modes":[plan["mode"]],"outcome":"dual-dav1d and AVIF native validation"})
        print(name,"mode",plan["mode"],"native validated",flush=True)
    small.large.verify_existing_artifacts(previous,args.out)
    manifest=previous.copy();manifest.update(scope="12 complete stock traces plus5 five-mode geometry conformance streams",candidate_limit=17,candidates=ledger,fixtures=records)
    write_manifest(args,manifest)


def evidence(args):
    path=args.out/"manifest.json";manifest=json.loads(path.read_text(encoding="utf-8"))
    counts=[0]*5;active_ac=0;stock_blocks=0;groups={}
    for candidate in manifest["candidates"][:12]:
        syntax=read_stock((args.out/candidate["obu_file"]).read_bytes(),(args.out/candidate["trace_file"]).read_text(encoding="utf-8"))
        if syntax!=json.loads((args.out/candidate["syntax_file"]).read_text(encoding="utf-8")):
            raise ValueError("complete stock entropy evidence changed")
        key=f"{'mono' if candidate['monochrome'] else 'color'}_{candidate['bit_depth']}bit"
        found=groups.setdefault(key,set())
        stock_blocks+=len(syntax["blocks"])
        for block in syntax["blocks"]:
            if block["use_filter_intra"]:
                counts[block["filter_mode"]]+=1;found.add(block["filter_mode"])
                active_ac+=block["transforms"][0].get("eob",0)>1
    if any(modes!=set(range(5)) for modes in groups.values()):
        raise ValueError("stock matrix lacks an actual filter mode in a color/depth group")
    encoder=run([args.aomenc,"--help"]);decoder=run([args.dav1d,"--version"])
    sources=[Path(__file__),ROOT/"scripts/generate-av1-directional-tile-reference.py",ROOT/"scripts/generate-av1-small-lossy-reference.py",
        ROOT/"scripts/generate-av1-small-block-reference.py",ROOT/"scripts/craft_av1_fixture.py"]
    sources+=list((ROOT/"_refs/go-av1/cdf").glob("*.go"))
    sources+=[ROOT/"_refs/go-av1/decode"/name for name in ("block.go","txtype.go","coeff.go","coeffctx.go","scans_all_gen.go","scan_gen.go")]
    manifest.update({"coverage":{"stock_coding_blocks":stock_blocks,"actual_filter_mode_block_counts":counts,
        "active_filter_blocks_with_ac":active_ac,"actual_modes_by_color_depth":{k:sorted(v) for k,v in groups.items()},
        "constructed_cases":5,"constructive_gates":["FI on skipped block","4x16/16x4 full block enum CDF","4x4 owner","coding32/TX16 SELECT","odd visible crop"],
        "clipping_claim":False},
        "versions":{"encoder":re.search(r"AOMedia Project AV1 Encoder[^\r\n]+",encoder.stdout+encoder.stderr).group(0),
            "dav1d_cli":(decoder.stdout+decoder.stderr).strip(),"ffmpeg":run([args.ffmpeg,"-version"]).stdout.splitlines()[0],
            "ffmpeg_libdav1d":manifest["fixtures"][0]["ffmpeg_libdav1d"],"scalar_libavif":manifest["scalar_libavif_version"]},
        "support_hashes":{p.relative_to(ROOT).as_posix():sha256(p.read_bytes()) for p in sources},
        "normative_sources":["https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/blockd.h",
            "https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/decoder/decodemv.c"],
        "transform_cdf_direction_map":list(FILTER_TX_CONTEXT),
        "oracle_boundary":"all native pixels from unmodified external decoders; stock syntax independently parsed completely; constructions explicitly recorded and arithmetic-roundtripped",
        "reference_contract":"canonical native binary planes; color nearest420 API conversion, monochrome actual scalar full-range UNORM; no full pixel/RLE arrays in manifest"})
    if (args.out/"README.md").exists():
        manifest.update(documentation_file="README.md",documentation_sha256=sha256((args.out/"README.md").read_bytes()))
    write_manifest(args,manifest)
    print(f"stock {stock_blocks} blocks, actual FI counts{counts}, {active_ac} active blocks with AC")


def check(args):
    manifest=json.loads((args.out/"manifest.json").read_text(encoding="utf-8"))
    if len(manifest["candidates"])!=17 or len(manifest["fixtures"])!=17:
        raise ValueError("expected exactly12 stock plus5 constructed cases")
    for record in manifest["candidates"]+manifest["fixtures"]:
        for key,name in record.items():
            if key.endswith("_file") and key[:-5]+"_sha256" in record and sha256((args.out/name).read_bytes())!=record[key[:-5]+"_sha256"]:
                raise ValueError(f"artifact hash mismatch: {name}")
    plans={p["name"]:p for p in conformance_plans()}
    for candidate in manifest["candidates"]:
        if candidate.get("kind")=="constructed":
            data,syntax=constructed_stream(plans[candidate["name"]])
            if data!=(args.out/candidate["obu_file"]).read_bytes():
                raise ValueError("constructed byte regeneration mismatch")
        else:
            syntax=read_stock((args.out/candidate["obu_file"]).read_bytes(),(args.out/candidate["trace_file"]).read_text(encoding="utf-8"))
            source=b"".join(small.mono_helpers.pack(p,candidate["bit_depth"]) for p in source_planes(candidate["bit_depth"],candidate["monochrome"],candidate["texture"]))
            if source!=(args.out/candidate["source_file"]).read_bytes():
                raise ValueError("stock source pattern regeneration mismatch")
        if syntax!=json.loads((args.out/candidate["syntax_file"]).read_text(encoding="utf-8")):
            raise ValueError("syntax evidence regeneration mismatch")
    for name,expected in manifest["support_hashes"].items():
        if sha256((ROOT/name).read_bytes())!=expected:
            raise ValueError(f"source hash mismatch: {name}")
    source=run([args.moonfmt,"-"],input_text=generated_test(manifest["fixtures"],args.out)).stdout
    if args.test.read_text(encoding="utf-8")!=source:
        raise ValueError("canonical generated test mismatch")
    print("checked17 native references,12 complete stock traces,5 constructed bytes and canonical tests")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,default=ROOT/"tests/fixtures/av1-filter-intra")
    parser.add_argument("--test",type=Path,default=ROOT/"_refs/av1_filter_intra_reference_wbtest.mbt")
    for name in ("aomenc","ffmpeg","dav1d","moonfmt"):
        parser.add_argument("--"+name,default=shutil.which(name) or name)
    parser.add_argument("--libavif-scalar",default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--conformance",action="store_true")
    parser.add_argument("--evidence",action="store_true")
    parser.add_argument("--check",action="store_true")
    args=parser.parse_args()
    check(args) if args.check else evidence(args) if args.evidence else conformance(args) if args.conformance else stock(args)


if __name__=="__main__":
    main()
