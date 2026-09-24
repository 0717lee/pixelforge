#!/usr/bin/env python3
"""Run unmodified dav1d projection/temporal-candidate functions as a C oracle."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-compound-temporal"
WB = ROOT / "av1_compound_temporal_oracle_wbtest.mbt"

PRELUDE = r'''
typedef signed char int8_t; typedef short int16_t;
typedef unsigned short uint16_t; typedef unsigned long long uint64_t;
extern int printf(const char *, ...); extern void abort(void);
#define assert(x) ((x) ? (void)0 : abort())
#define INVALID_MV 0x80008000U
static int abs(int v) { return v < 0 ? -v : v; }
static int iclip(int v,int lo,int hi) { return v < lo ? lo : v > hi ? hi : v; }
typedef union mv { struct { int16_t y,x; }; unsigned n; } mv;
typedef union refmvs_mvpair { mv mv[2]; uint64_t n; } refmvs_mvpair;
typedef union refmvs_refpair { int8_t ref[2]; uint16_t pair; } refmvs_refpair;
typedef struct refmvs_candidate { refmvs_mvpair mv; int weight; } refmvs_candidate;
typedef struct refmvs_temporal_block { mv mv; int8_t ref; } refmvs_temporal_block;
typedef struct Dav1dFrameHeader { int force_integer_mv,hp; } Dav1dFrameHeader;
typedef struct refmvs_frame { const Dav1dFrameHeader *frm_hdr; int8_t pocdiff[7]; } refmvs_frame;
'''

HARNESS = r'''
int main(void) {
  for (int policy=0;policy<5;policy++) {
    /* AV1 uncompressed_header: force_integer_mv implies hp == 0. */
    Dav1dFrameHeader hdr={ policy==2, policy!=1 && policy!=2 };
    refmvs_frame rf={0}; rf.frm_hdr=&hdr;
    rf.pocdiff[0]=policy==3?0:1; rf.pocdiff[4]=policy==3?1:-1;
    refmvs_candidate stack[8]={0}; int count=0;
    refmvs_refpair refs={.ref={1,5}};
    if (policy==4) {
      count=8;
      for(int i=0;i<8;i++) {
        stack[i].mv.mv[0].y=i*8; stack[i].mv.mv[1].y=-i*8;
        stack[i].weight=640;
      }
    }
    for(int step=0;step<3;step++) {
      const int y=policy==4?(step==2?65:40):(step==2?33:31);
      const int x=policy==4?0:(step==2?-49:-47);
      refmvs_temporal_block rb={.mv={.y=y,.x=x},.ref=policy>=3?1:2};
      add_temporal_candidate(&rf,stack,&count,&rb,refs,0,0);
    }
    printf("C %d %d\n",policy,count);
    for(int i=0;i<count;i++) printf("M %d %d %d %d %d\n",
      stack[i].mv.mv[0].y,stack[i].mv.mv[0].x,
      stack[i].mv.mv[1].y,stack[i].mv.mv[1].x,stack[i].weight);
  }
  return 0;
}
'''


def function(text, name):
    marker = text.index(name + "(")
    start = text.rfind("\nstatic ", 0, marker) + 1
    body = text.index("{", marker)
    depth = 1
    end = body + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def reference_source(source):
    ref = (source / "src/refmvs.c").read_text(encoding="utf-8")
    env = (source / "src/env.h").read_text(encoding="utf-8")
    license_text = ref[:ref.index("#include")]
    functions = [function(env, "fix_int_mv_precision"), function(env, "fix_mv_precision"),
                 function(ref, "mv_projection"), function(ref, "add_temporal_candidate")]
    return license_text + PRELUDE + "\n\n".join(functions) + HARNESS


def whitebox(cases):
    arrays = ["  [" + ", ".join(str(v) for row in case["candidates"] for v in row) + "]," for case in cases]
    return """/// Original dav1d 1.2.1 C oracle; regenerate with scripts/generate-av1-compound-temporal-reference.py.
///|
let av1_compound_temporal_c_oracle : Array[Array[Int]] = [
""" + "\n".join(arrays) + """
]

///|
test "compound temporal candidate pairs agree with original dav1d C projection and precision" {
  for policy in 0..<5 {
    let grid = av1_compound_temporal_grid()
    let block = av1_temporal_test_block(4, 4, 2, 2)
    block.refs[1] = av1_bwd_ref_frame
    // The frame header sets allow_high_precision_mv to 0 for integer MVs.
    let frame = av1_temporal_test_frame(Some(grid), policy != 1 && policy != 2, if policy == 2 { 1 } else { 0 })
    let stack = av1_mv_stack_new()
    if policy == 4 {
      stack.count = 8
      for index in 0..<8 {
        av1_stack_set_mv(stack, index, 0, index * 8, 0)
        av1_stack_set_mv(stack, index, 1, -index * 8, 0)
        stack.weights[index] = 640
      }
    }
    for step in 0..<3 {
      let row = if policy == 4 { if step == 2 { 65 } else { 40 } } else { if step == 2 { 33 } else { 31 } }
      let col = if policy == 4 { 0 } else { if step == 2 { -49 } else { -47 } }
      let denominator = if policy >= 3 { 1 } else { 2 }
      let first = av1_mv_projection(row, col, if policy == 3 { 0 } else { 1 }, denominator)
      let second = av1_mv_projection(row, col, if policy == 3 { 1 } else { -1 }, denominator)
      av1_compound_temporal_put(grid, 2, 2, first, second)
      av1_temporal_sample(stack, block, frame, grid, 0, 0, is_compound=true)
    }
    let expected = av1_compound_temporal_c_oracle[policy]
    assert_eq(stack.count, expected.length() / 5)
    for index in 0..<stack.count {
      assert_eq(av1_stack_mv(stack, index, 0), (expected[index * 5], expected[index * 5 + 1]))
      assert_eq(av1_stack_mv(stack, index, 1), (expected[index * 5 + 2], expected[index * 5 + 3]))
      assert_eq(stack.weights[index], expected[index * 5 + 4])
    }
  }
}
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--cc", default=str(Path.home() / ".moon/bin/internal/tcc.exe"))
    parser.add_argument("--cc-root", default=str(Path.home() / ".moon"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = reference_source(args.source_dir) if args.source_dir else (OUT / "reference.c").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="pixelforge-temporal-") as temp:
        work = Path(temp)
        (work / "reference.c").write_text(source, encoding="utf-8", newline="\n")
        command = [args.cc]
        if "tcc" in Path(args.cc).name:
            command += ["-B", args.cc_root]
        command += [str(work / "reference.c"), "-o", str(work / "oracle.exe")]
        subprocess.run(command, check=True, capture_output=True)
        result = subprocess.run([str(work / "oracle.exe")], check=True, capture_output=True, text=True)
    cases = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if parts[0] == "C":
            cases.append({"policy": int(parts[1]), "count": int(parts[2]), "candidates": []})
        else:
            cases[-1]["candidates"].append(list(map(int, parts[1:])))
    document = {"source": "dav1d 1.2.1 src/refmvs.c and src/env.h, original function bodies",
                "reference_c_sha256": hashlib.sha256(source.encode()).hexdigest(), "cases": cases}
    encoded = json.dumps(document, indent=2) + "\n"
    if args.check:
        assert (OUT / "reference.c").read_text(encoding="utf-8") == source
        assert (OUT / "oracle.json").read_text(encoding="utf-8") == encoded
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "reference.c").write_text(source, encoding="utf-8", newline="\n")
        (OUT / "oracle.json").write_text(encoded, encoding="utf-8", newline="\n")
        WB.write_text(whitebox(cases), encoding="utf-8", newline="\n")
    print("Verified 5 original dav1d compound temporal candidate cases")


if __name__ == "__main__":
    main()
