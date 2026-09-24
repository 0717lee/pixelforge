#!/usr/bin/env python3
"""Regenerate compound-warp native-sample references from dav1d 1.2.1.

--check only reads committed files (and optional --source-dir); it never
compiles, formats, creates temporary files, or updates artifacts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests/fixtures/av1-compound-warp"
TEST = ROOT / "av1_compound_warp_wbtest.mbt"
MARKER = "// BEGIN DAV1D COMPOUND WARP REFERENCES\n"


PRELUDE = r'''
typedef signed char int8_t;typedef unsigned char uint8_t;
typedef unsigned short uint16_t;typedef short int16_t;typedef int int32_t;
typedef long long int64_t;typedef unsigned long long uint64_t;typedef long long ptrdiff_t;
extern int printf(const char *, ...);extern void abort(void);
#define INT16_MIN (-32768)
#define INT16_MAX 32767
#define assert(x) ((x) ? (void)0 : abort())
#define COLD
static int abs(int v){return v<0?-v:v;}
static int64_t llabs(int64_t v){return v<0?-v:v;}
static int iclip(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static int imin(int a,int b){return a<b?a:b;}
static int apply_sign(int v,int s){return s<0?-v:v;}
static int apply_sign64(int v,int64_t s){return s<0?-v:v;}
static int ulog2(unsigned v){int s=0;while(v>>1){s++;v>>=1;}return s;}
static int u64log2(uint64_t v){int s=0;while(v>>1){s++;v>>=1;}return s;}
typedef union mv{struct{int16_t y,x;};unsigned n;}mv;
typedef struct Dav1dWarpedMotionParams{int type;int32_t matrix[6];union{struct{int16_t alpha,beta,gamma,delta;}p;int16_t abcd[4];}u;}Dav1dWarpedMotionParams;
#define pixel uint16_t
#define HIGHBD_DECL_SUFFIX ,const int bitdepth_max
#define PXSTRIDE(x) ((x)/2)
#define get_intermediate_bits(x) ((x)==4095?2:4)
#define bitdepth_from_max(x) ((x)==4095?12:((x)==1023?10:8))
#define PREP_BIAS ((bitdepth_max)==255?0:8192)
#define iclip_pixel(x) iclip(x,0,bitdepth_max)
'''

HARNESS = r'''static int sample(int x,int y,int list,int plane,int depth) {
  int lim=(1<<depth)-1;int ramp=(x*7+y*3+list*11+plane*17)&(lim>>3);
  return ((x/2+y/3+list+plane)%4<2)?ramp:lim-ramp;
}
static void predict(int16_t *out,int depth,int sx,int sy,int list,int pl) {
  const int bitdepth_max=(1<<depth)-1;
  const int32_t matrices[2][6]={{73728,-32768,65664,256,-256,65664},{-16384,77824,65344,-128,128,65344}};
  Dav1dWarpedMotionParams wm={0};for(int i=0;i<6;i++)wm.matrix[i]=matrices[list][i];
  assert(!dav1d_get_shear_params(&wm));
  const int w=16>>sx,h=16>>sy,rw=32>>sx,rh=32>>sy;
  uint16_t edge[15*15];
  for(int y=0;y<h;y+=8){
    const int src_y=16+((y+4)<<sy);
    const int64_t mat3_y=(int64_t)wm.matrix[3]*src_y+wm.matrix[0];
    const int64_t mat5_y=(int64_t)wm.matrix[5]*src_y+wm.matrix[1];
    for(int x=0;x<w;x+=8){
      const int src_x=16+((x+4)<<sx);
      const int64_t mvx=((int64_t)wm.matrix[2]*src_x+mat3_y)>>sx;
      const int64_t mvy=((int64_t)wm.matrix[4]*src_x+mat5_y)>>sy;
      const int dx=(int)(mvx>>16)-4,dy=(int)(mvy>>16)-4;
      const int mx=(((int)mvx&0xffff)-wm.u.p.alpha*4-wm.u.p.beta*7)&~63;
      const int my=(((int)mvy&0xffff)-wm.u.p.gamma*4-wm.u.p.delta*4)&~63;
      for(int ey=0;ey<15;ey++)for(int ex=0;ex<15;ex++)edge[ey*15+ex]=sample(iclip(dx+ex-3,0,rw-1),iclip(dy+ey-3,0,rh-1),list,pl,depth);
      warp_affine_8x8t_c(out+y*w+x,w,edge+3*15+3,30,wm.u.abcd,mx,my,bitdepth_max);
    }
  }
}
int main(void){
  for(int bd=8;bd<=12;bd+=2)for(int layout=0;layout<3;layout++){
    const int bitdepth_max=(1<<bd)-1;const int sx=layout>0,sy=layout==2;
    int16_t pred[3][2][256];
    for(int pl=0;pl<3;pl++)for(int list=0;list<2;list++){
      int px=pl?sx:0,py=pl?sy:0,n=(16>>px)*(16>>py);
      predict(pred[pl][list],bd,px,py,list,pl);
      printf("P %d %d %d %d",bd,layout,pl,list);
      for(int i=0;i<n;i++)printf(" %d",pred[pl][list][i]+PREP_BIAS);printf("\n");
    }
    for(int mode=0;mode<6;mode++){
      uint8_t mask[256];uint16_t out[256];
      for(int pl=0;pl<3;pl++){
        int px=pl?sx:0,py=pl?sy:0,w=16>>px,h=16>>py;
        int sign=(mode==3||mode==5),sel=sign;
        if(mode==0)avg_c(out,w*2,pred[pl][0],pred[pl][1],w,h,bitdepth_max);
        else if(mode==1)w_avg_c(out,w*2,pred[pl][0],pred[pl][1],w,h,11,bitdepth_max);
        else if(mode<4){
          if(pl==0)w_mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,sign,sx,sy,bitdepth_max);
          else mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,bitdepth_max);
        }else{
          // 16x16 codebook entry4 is horizontal at yoff=28, sign bit4 of0x7bfb is1.
          const int border[8]={0,2,7,21,43,57,62,64};uint8_t luma[256];
          for(int y=0;y<16;y++)for(int x=0;x<16;x++)luma[y*16+x]=64-(y<8?border[y]:64);
          if(pl&&sx)init_chroma(mask,luma,sign,16,16,sy);else for(int i=0;i<256;i++)mask[i]=luma[i];
          mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,bitdepth_max);
        }
        printf("B %d %d %d %d",bd,layout,mode,pl);
        for(int i=0;i<w*h;i++)printf(" %d",out[i]);printf("\n");
      }
    }
  }return 0;
}
'''

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def function(source: str, name: str) -> str:
    start = source.rfind("\n", 0, source.index(name + "(")) + 1
    brace = source.index("{", source.index(name + "("))
    nesting, cursor = 1, brace + 1
    while nesting:
        nesting += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor] + "\n"


def reference_source(source_dir: Path):
    paths = ["src/mc_tmpl.c", "src/tables.c", "src/warpmv.c", "src/wedge.c"]
    contents = {path: (source_dir / path).read_text(encoding="utf-8") for path in paths}
    mc, tables, warpmv, wedge = (contents[path] for path in paths)
    start = tables.index("const int8_t ALIGN(dav1d_mc_warp_filter")
    end = tables.index("\n};", start) + 3
    table = re.sub(r"ALIGN\((dav1d_mc_warp_filter\[193\]\[8\]), 8\)", r"\1", tables[start:end])
    start = mc.index("#define FILTER_WARP_RND")
    macros = mc[start:mc.index("static void warp_affine_8x8_c", start)]
    names = ["warp_affine_8x8t_c", "avg_c", "w_avg_c", "mask_c", "w_mask_c"]
    functions = {name: function(mc, name) for name in names}
    functions["init_chroma"] = function(wedge, "init_chroma")
    original = warpmv[warpmv.index("static const uint16_t div_lut"):] + table + "\n" + macros
    original += "\n".join(functions[name] for name in names) + functions["init_chroma"]
    license_text = mc[:mc.index('#include "config.h"')].rstrip() + "\n"
    provenance = {
        "project": "dav1d", "version": "1.2.1", "license": "BSD-2-Clause",
        "upstream": "https://code.videolan.org/videolan/dav1d/-/tree/1.2.1",
        "source_sha256": {path: sha((source_dir / path).read_bytes()) for path in paths},
        "function_sha256": {name: sha(body.encode()) for name, body in functions.items()},
        "notes": "Scalar function bodies are unmodified; the standalone harness supplies typedefs, edge replication, model/plane geometry and output serialization. pixel uses uint16_t for every depth; arithmetic and PREP_BIAS match the 8/10/12-bit kernels.",
    }
    return license_text + PRELUDE + original + HARNESS, license_text, provenance


def parse_output(output: str):
    cases = {}
    for line in output.splitlines():
        kind, *words = line.split()
        nums = list(map(int, words))
        key = (kind, *nums[:4])
        values = nums[4:]
        if key in cases or kind not in ("P", "B"):
            raise ValueError("duplicate or invalid oracle key")
        cases[key] = values
    expected = {(kind, depth, layout, a, b)
                for depth in (8, 10, 12) for layout in range(3)
                for kind in ("P", "B")
                for a in range(3 if kind == "P" else 6)
                for b in range(2 if kind == "P" else 3)}
    if set(cases) != expected:
        raise ValueError("oracle does not cover all 216 groups")
    for (kind, depth, layout, a, b), pixels in cases.items():
        plane = a if kind == "P" else b
        sx = int(plane != 0 and layout > 0)
        sy = int(plane != 0 and layout == 2)
        if len(pixels) != (16 >> sx) * (16 >> sy):
            raise ValueError("oracle plane extent mismatch")
    return cases


def crc(pixels):
    return zlib.crc32(b"".join(struct.pack("<i", value) for value in pixels))


def canonical_tests(text):
    compact = re.sub(r"\s+", "", text)
    return re.sub(r",(?=[\])}])", "", compact)


def render(cases):
    out = MARKER
    fmt = lambda values: ", ".join(f"0x{value:08x}U" for value in values)
    for depth in (8, 10, 12):
        for layout, name in enumerate(("444", "422", "420")):
            predictions = [crc(cases["P", depth, layout, plane, ref]) for plane in range(3) for ref in range(2)]
            blends = [crc(cases["B", depth, layout, mode, plane]) for mode in range(6) for plane in range(3)]
            out += f'\n///|\ntest "compound warp original C {depth}bit {name} all signed blends" {{\n'
            out += f"  av1_compound_warp_oracle_case({depth}, {layout}, [{fmt(predictions)}], [{fmt(blends)}])\n}}\n"
    for depth, layout, mode, plane in ((8, 0, 0, 0), (10, 1, 3, 1), (12, 2, 5, 2)):
        pixels = ", ".join(map(str, cases["B", depth, layout, mode, plane]))
        out += f'\n///|\ntest "compound warp full pixels depth{depth} layout{layout} blend{mode} plane{plane}" {{\n'
        out += f"  av1_compound_warp_full_pixels({depth}, {layout}, {mode}, {plane}, [{pixels}])\n}}\n"
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="dav1d 1.2.1 source root; required for regeneration")
    parser.add_argument("--cc", default=shutil.which("cc") or str(Path.home() / ".moon/bin/internal/tcc.exe"))
    parser.add_argument("--check", action="store_true", help="read-only fixture and expected-test validation")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((FIXTURES / "manifest.json").read_text())
        for name, digest in manifest["artifacts"].items():
            if sha((FIXTURES / name).read_bytes()) != digest:
                raise SystemExit(f"fixture hash mismatch: {name}")
        cases = parse_output((FIXTURES / "oracle.txt").read_text())
        expected = render(cases)
        actual = TEST.read_text(encoding="utf-8").split(MARKER, 1)[1]
        if canonical_tests(MARKER + actual) != canonical_tests(expected):
            raise SystemExit("compound warp expected tests differ from original-C output")
        if args.source_dir:
            source, _, provenance = reference_source(args.source_dir)
            if sha(source.encode()) != manifest["artifacts"]["reference.c"] or provenance["function_sha256"] != manifest["reference"]["function_sha256"]:
                raise SystemExit("reference source or provenance differs")
        print(f"Validated {len(cases)} original-C groups and three complete pixel arrays; no files changed.")
        return
    if not args.source_dir:
        parser.error("--source-dir is required to regenerate")
    source, license_text, provenance = reference_source(args.source_dir)
    with tempfile.TemporaryDirectory(prefix="pixelforge-compound-warp-") as temporary:
        temporary = Path(temporary)
        c_file, executable = temporary / "reference.c", temporary / "reference.exe"
        c_file.write_text(source, encoding="utf-8", newline="\n")
        compiler = Path(shutil.which(args.cc) or args.cc).resolve()
        command = [str(compiler)]
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command += ["-B", str(moon_root)]
        subprocess.run(command + [str(c_file), "-o", str(executable)], check=True)
        output = subprocess.check_output([str(executable)], text=True)
    cases = parse_output(output)
    rendered = render(cases)
    prefix = TEST.read_text(encoding="utf-8").split(MARKER, 1)[0]
    formatted = subprocess.run(["moonfmt", "-"], input=prefix + rendered, capture_output=True, text=True, check=True).stdout
    files = {"reference.c": source, "oracle.txt": output, "LICENSE": license_text}
    FIXTURES.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (FIXTURES / name).write_text(content, encoding="utf-8", newline="\n")
    manifest = {
        "reference": provenance,
        "artifacts": {name: sha(content.encode()) for name, content in files.items()},
        "groups": len(cases), "sample_count": sum(map(len, cases.values())),
        "serialization": "oracle.txt decimal row-major samples; test CRC covers signed int32 little endian",
        "prediction_groups_with_fraction": sum(any(v & ((1 << (2 if key[1] == 12 else 4)) - 1) for v in pixels) for key, pixels in cases.items() if key[0] == "P"),
        "prediction_groups_with_overshoot": sum(any(v < 0 or v > (((1 << key[1]) - 1) << (2 if key[1] == 12 else 4)) for v in pixels) for key, pixels in cases.items() if key[0] == "P"),
    }
    (FIXTURES / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    TEST.write_text(formatted, encoding="utf-8", newline="\n")
    print(f"Generated {len(cases)} original-C groups, {manifest['sample_count']} samples, and three complete pixel arrays.")


if __name__ == "__main__":
    main()
