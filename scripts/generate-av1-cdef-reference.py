#!/usr/bin/env python3
"""Regenerate CDEF pixel goldens by executing the pinned libaom C kernel.

Run from any directory with Python 3, a C compiler and MoonBit's moonfmt::

    python scripts/generate-av1-cdef-reference.py --cc path/to/tcc.exe
    python scripts/generate-av1-cdef-reference.py --check

Use --moonfmt path/to/moonfmt.exe when moonfmt is not on PATH. Only the generated
source is formatted, through moonfmt's stdin/stdout interface; no package-wide
formatting is performed.

The three upstream sources are downloaded only when absent from the local
cache; every source must match its pinned SHA-256 before compilation. The
kernel, constrain/sign functions and tap/direction tables are extracted from
upstream verbatim. The C shim supplies integer utilities, sentinel padding and
block dispatch. Python generates input pixels and serializes results; it does
not implement the filter. Temporary C source/executables are removed on exit.

The committed MoonBit tests contain all expected pixels and need neither a C
compiler nor network access. Hex strings encode complete output samples, not
hashes or samples of selected pixels. --check verifies reproducible generation.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import shutil
import subprocess
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REVISION = "1a4b3aef9b3e5b9251c45e9f986f41894dd45bb2"
SOURCE_URL = f"https://aomedia.googlesource.com/aom/+/{REVISION}/av1/common/"
SOURCE_HASHES = {
    "cdef_block.c": "e22f2e787adc8d78c4c88e03617a25db2603081ec18ca442a3e2f9a7bc5b5636",
    "cdef.h": "ecccc8e9e50fe4e552fa4a2aebd849fd16c175293226d0030429eef24202efc0",
    "cdef_block.h": "6659e09e0cdbd99ece619d704235ac49821d2c691e892736e39d9d45db59a32f",
}
DEPTHS = (8, 10, 12)
SECONDARY = (0, 1, 2, 4)


@dataclass(frozen=True)
class Params:
    primary: int
    secondary: int
    damping: int
    direction: int


@dataclass(frozen=True)
class Case:
    name: str
    width: int
    height: int
    depth: int
    seed: int
    params: tuple[Params, ...]
    block_size: int = 8
    damping_offset: int = 0

    def pixels(self) -> list[int]:
        # Keep this input-only formula identical to cdef_reference_input below.
        scale = 1 << (self.depth - 8)
        base = (128, 8, 247)[self.seed % 3]
        return [
            max(0, min((1 << self.depth) - 1,
                (base + (x * 13 + y * 17 + x * y * 3 + self.seed * 7) % 23 - 11
                 + (x // 3 + y // 2 + self.seed) % 7 - 3) * scale
                + (x * 5 + y * 7 + self.seed) % scale))
            for y in range(self.height) for x in range(self.width)
        ]


def load_sources(directory: Path) -> dict[str, str]:
    sources = {}
    for name, expected in SOURCE_HASHES.items():
        path = directory / name
        if path.exists():
            data = path.read_bytes()
        else:
            with urllib.request.urlopen(SOURCE_URL + name + "?format=TEXT", timeout=60) as response:
                data = base64.b64decode(response.read(), validate=True)
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise RuntimeError(f"{name}: SHA-256 {actual}, expected {expected}")
        if not path.exists():
            directory.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f"{name}: SHA-256 {actual}")
        sources[name] = data.decode("utf-8")
    return sources


def extract_braced(source: str, marker: str, *, declaration: bool = False) -> str:
    """Extract a hash-pinned upstream function/table without modifying its body."""
    start = source.index(marker)
    opening = source.index("{", start)
    nesting = 1
    end = opening + 1
    while nesting:
        nesting += (source[end] == "{") - (source[end] == "}")
        end += 1
    if declaration:
        if source[end] != ";":
            raise RuntimeError(f"missing declaration terminator for {marker}")
        end += 1
    return source[start:end]


C_SHIM = r"""
/* Header-free declarations also support MoonBit's bundled TinyCC, which does
   not ship the standard C development headers. Widths are checked in main. */
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef signed short int16_t;
typedef signed int int32_t;
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern int abs(int);

#define NULL ((void *)0)
#define INLINE inline
#define AOMMAX(a, b) ((a) > (b) ? (a) : (b))
#define AOMMIN(a, b) ((a) < (b) ? (a) : (b))
#define DECLARE_ALIGNED(n, type, var) type var
/* A local scratch stride; upstream direction expressions use this same value. */
#define CDEF_BSTRIDE 32
#define CDEF_VERY_LARGE 30000
enum { BLOCK_4X4, BLOCK_4X8, BLOCK_8X4, BLOCK_8X8 };
static int get_msb(unsigned int value) {
  int result = 0;
  while (value >>= 1) ++result;
  return result;
}
static int clamp(int value, int minimum, int maximum) {
  return value < minimum ? minimum : value > maximum ? maximum : value;
}
"""

C_MAIN = r"""
int main(void) {
  int width, height, depth, block_size, damping_offset, count;
  uint16_t source[4096], result[4096];
  if (sizeof(uint16_t) != 2 || sizeof(int16_t) != 2 || sizeof(int) != 4) return 1;
  while (scanf("%d %d %d %d %d %d", &width, &height, &depth,
               &block_size, &damping_offset, &count) == 6) {
    int i, bi, value;
    int direction = -1;
    int32_t variance = 0;
    int blocks_x = (width + block_size - 1) / block_size;
    if (width <= 0 || height <= 0 || width * height > 4096) return 2;
    for (i = 0; i < width * height; ++i) {
      if (scanf("%d", &value) != 1) return 3;
      source[i] = value;
    }
    if (width >= 8 && height >= 8)
      direction = cdef_find_dir_c(source, width, &variance, depth - 8);
    for (bi = 0; bi < count; ++bi) {
      int primary, secondary, damping, direction, x, y;
      int bx = (bi % blocks_x) * block_size;
      int by = (bi / blocks_x) * block_size;
      int bw = AOMMIN(block_size, width - bx);
      int bh = AOMMIN(block_size, height - by);
      int bsize = bh <= 4 ? (bw <= 4 ? BLOCK_4X4 : BLOCK_8X4)
                         : (bw <= 4 ? BLOCK_4X8 : BLOCK_8X8);
      int shift = depth - 8;
      uint16_t scratch[12 * CDEF_BSTRIDE], out16[64];
      uint8_t out8[64];
      if (scanf("%d %d %d %d", &primary, &secondary, &damping, &direction) != 4)
        return 4;
      for (i = 0; i < 12 * CDEF_BSTRIDE; ++i) scratch[i] = CDEF_VERY_LARGE;
      /* Every block reads the original whole-plane snapshot, including halos. */
      for (y = -2; y < block_size + 2; ++y) {
        for (x = -2; x < block_size + 2; ++x) {
          int sx = bx + x, sy = by + y;
          if (sx >= 0 && sy >= 0 && sx < width && sy < height)
            scratch[(y + 2) * CDEF_BSTRIDE + x + 2] = source[sy * width + sx];
        }
      }
      cdef_filter_block_c(depth == 8 ? out8 : NULL, depth == 8 ? NULL : out16,
          8, scratch + 2 * CDEF_BSTRIDE + 2,
          primary << shift, secondary << shift, direction,
          damping + shift + damping_offset, damping + shift + damping_offset,
          bsize, shift);
      for (y = 0; y < bh; ++y) {
        for (x = 0; x < bw; ++x)
          result[(by + y) * width + bx + x] =
              depth == 8 ? out8[y * 8 + x] : out16[y * 8 + x];
      }
    }
    printf("%d %d ", direction, variance);
    for (i = 0; i < width * height; ++i)
      printf("%d%c", result[i], i + 1 == width * height ? '\n' : ' ');
  }
  return 0;
}
"""


def reference_source(sources: dict[str, str]) -> str:
    block = sources["cdef_block.c"]
    header = sources["cdef.h"]
    license_header = block[:block.index("*/") + 2]
    parts = [license_header, C_SHIM]
    parts.extend(extract_braced(header, f"static INLINE int {name}(")
                 for name in ("sign", "constrain"))
    parts.extend(extract_braced(block, marker, declaration=True) for marker in (
        "DECLARE_ALIGNED(16, const int, cdef_directions[8][2])",
        "const int cdef_pri_taps[2][2]",
        "const int cdef_sec_taps[2]",
    ))
    parts.append(extract_braced(block, "void cdef_filter_block_c("))
    parts.append(extract_braced(block, "int cdef_find_dir_c("))
    parts.append(C_MAIN)
    return "\n\n".join(parts)


def make_cases() -> tuple[list[Case], list[Case], list[tuple[Case, Case, Case]]]:
    matrix, edges, yuv = [], [], []
    for depth in DEPTHS:
        index = 0
        for direction in range(8):
            for primary in (7, 8):
                for secondary in SECONDARY:
                    for damping in range(3, 7):
                        matrix.append(Case(f"matrix_{depth}_{index}", 8, 8, depth,
                            depth * 101 + index, (Params(primary, secondary, damping, direction),)))
                        index += 1
        for index, (width, height) in enumerate(((1, 1), (3, 5), (4, 8), (8, 4),
                                               (9, 9), (16, 16), (23, 13))):
            count = ((width + 7) // 8) * ((height + 7) // 8)
            params = tuple(Params((0, 15, 2, 1, 8, 7)[i % 6], SECONDARY[i % 4],
                                  3 + i % 4, (index + i * 3) % 8) for i in range(count))
            # Nonzero single-block cases exercise tiny and rectangular borders.
            if count == 1:
                params = (Params(15, 4, 6, index % 8),)
            edges.append(Case(f"edge_{depth}_{width}x{height}", width, height, depth,
                              depth * 31 + index, params))
        for direction in range(8):
            yp = tuple(Params((15, 0, 2, 1)[i], SECONDARY[i], 3 + i,
                              (direction + i) % 8) for i in range(4))
            uvp = tuple(Params((7, 8, 0, 15)[i], (1, 2, 4, 0)[i], 3 + i,
                               (direction + i * 2) % 8) for i in range(4))
            # Odd dimensions include partial right/bottom chroma blocks.
            width, height = (13, 11) if direction % 2 else (16, 16)
            seed = depth * 17 + direction * 3
            yuv.append((
                Case(f"yuv_{depth}_{direction}_y", width, height, depth, seed, yp),
                Case(f"yuv_{depth}_{direction}_u", (width + 1) // 2, (height + 1) // 2,
                     depth, seed + 1, uvp, 4, -1),
                Case(f"yuv_{depth}_{direction}_v", (width + 1) // 2, (height + 1) // 2,
                     depth, seed + 2, uvp, 4, -1),
            ))
    return matrix, edges, yuv


def run_reference(cc: str, source: str, cases: list[Case]) -> tuple[dict[str, list[int]], dict[str, tuple[int, int]]]:
    payload = []
    for case in cases:
        payload.append(f"{case.width} {case.height} {case.depth} {case.block_size} "
                       f"{case.damping_offset} {len(case.params)}")
        payload.append(" ".join(map(str, case.pixels())))
        payload.extend(f"{p.primary} {p.secondary} {p.damping} {p.direction}" for p in case.params)
    with tempfile.TemporaryDirectory(prefix="pixelforge-cdef-") as directory:
        path = Path(directory)
        c_file = path / "cdef_reference.c"
        executable = path / "cdef_reference.exe"
        c_file.write_text(source, encoding="utf-8")
        command = [cc]
        compiler_path = Path(cc).resolve()
        moon_root = compiler_path.parent.parent.parent
        if compiler_path.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command.extend(["-B", str(moon_root)])
        command.extend([str(c_file), "-o", str(executable)])
        print("Compiling extracted upstream C kernel:", " ".join(command))
        subprocess.run(command, check=True)
        result = subprocess.run([str(executable)], input="\n".join(payload) + "\n",
                                capture_output=True, text=True, check=True)
    lines = result.stdout.splitlines()
    if len(lines) != len(cases):
        raise RuntimeError(f"reference returned {len(lines)} planes, expected {len(cases)}")
    outputs, directions = {}, {}
    for case, line in zip(cases, lines):
        direction, variance, *values = map(int, line.split())
        if len(values) != case.width * case.height or any(v < 0 or v >= 1 << case.depth for v in values):
            raise RuntimeError(f"invalid reference output for {case.name}")
        outputs[case.name] = values
        directions[case.name] = (direction, variance)
    return outputs, directions


MOON_HELPERS = """///|
// Input generation only; filter expectations below come from the upstream C.
fn cdef_reference_input(
  width : Int,
  height : Int,
  bit_depth : Int,
  seed : Int,
) -> Array[Int] {
  let scale = 1 << (bit_depth - 8)
  let base = if seed % 3 == 0 { 128 } else if seed % 3 == 1 { 8 } else { 247 }
  let maximum = (1 << bit_depth) - 1
  let pixels : Array[Int] = []
  for y in 0..<height {
    for x in 0..<width {
      let value = (base + (x * 13 + y * 17 + x * y * 3 + seed * 7) % 23 - 11 +
        (x / 3 + y / 2 + seed) % 7 - 3) * scale + (x * 5 + y * 7 + seed) % scale
      pixels.push(if value < 0 { 0 } else if value > maximum { maximum } else { value })
    }
  }
  pixels
}

///|
// Two hex digits per 8-bit sample; three per 10/12-bit sample.
fn cdef_reference_pixels(hex : String, bit_depth : Int) -> Array[Int] {
  let digits = if bit_depth == 8 { 2 } else { 3 }
  let pixels : Array[Int] = []
  for i in 0..<(hex.length() / digits) {
    let mut value = 0
    for j in 0..<digits {
      let code = hex[i * digits + j].to_int()
      value = value * 16 + (if code <= 57 { code - 48 } else { code - 87 })
    }
    pixels.push(value)
  }
  pixels
}
"""


def moon_params(params: tuple[Params, ...]) -> str:
    return "[\n" + "".join(
        f"    {{ primary_strength: {p.primary}, secondary_strength: {p.secondary}, "
        f"damping: {p.damping}, direction: {p.direction} }},\n" for p in params) + "  ]"


def render(matrix: list[Case], edges: list[Case], yuv: list[tuple[Case, Case, Case]],
           outputs: dict[str, list[int]], directions: dict[str, tuple[int, int]]) -> str:
    def packed(case: Case) -> str:
        digits = 2 if case.depth == 8 else 3
        return "".join(f"{v:0{digits}x}" for v in outputs[case.name])

    text = [
        "// Generated by scripts/generate-av1-cdef-reference.py. Do not edit.\n",
        f"// libaom revision: {REVISION}\n",
        f"// Source: {SOURCE_URL}\n",
        "// Reference: original cdef_filter_block_c, sign, constrain and tap tables.\n",
        "// Upstream copyright (c) 2016, Alliance for Open Media. All rights reserved.\n",
        "// Upstream code is subject to the BSD 2 Clause License and the Alliance for\n",
        "// Open Media Patent License 1.0. License texts:\n",
        "// https://www.aomedia.org/license/software and https://www.aomedia.org/license/patent\n",
    ]
    for name, digest in SOURCE_HASHES.items():
        text.append(f"// {name} SHA-256: {digest}\n")
    text.append("// 768 Cartesian luma cases: 8 directions x 3 depths x primary 7/8 x\n")
    text.append("// secondary 0/1/2/4 x damping 3..6; 21 border cases; 24 YUV420 cases.\n\n")
    text.append("// Additional upstream cdef_find_dir_c goldens (not asserted by these kernel tests).\n")
    text.append("// Input: cdef_reference_input(8, 8, bit_depth, seed). Columns: depth seed direction variance.\n")
    for case in matrix[::32]:
        direction, variance = directions[case.name]
        text.append(f"// direction-golden: {case.depth} {case.seed} {direction} {variance}\n")
    text.append("\n")
    text.append(MOON_HELPERS)
    for depth in DEPTHS:
        cases = [c for c in matrix if c.depth == depth]
        text.append(f'\n///|\ntest "cdef libaom Cartesian pixel reference {depth}-bit" {{\n')
        text.append(f"  let bit_depth = {depth}\n  let expected : Array[String] = [\n")
        text.extend(f'    "{packed(case)}",\n' for case in cases)
        text.append("  ]\n  let mut index = 0\n")
        text.append("  for direction in 0..<8 {\n    for primary_strength in [7, 8] {\n")
        text.append("      for secondary_strength in [0, 1, 2, 4] {\n        for damping in 3..<7 {\n")
        text.append("          let input = cdef_reference_input(8, 8, bit_depth, bit_depth * 101 + index)\n")
        text.append("          let params : Array[Av1CdefParams] = [{ primary_strength, secondary_strength, damping, direction }]\n")
        text.append("          let actual = av1_cdef_filter_plane(8, 8, input, params, bit_depth~).unwrap()\n")
        text.append("          assert_eq((index, actual), (index, cdef_reference_pixels(expected[index], bit_depth)))\n")
        text.append("          index += 1\n        }\n      }\n    }\n  }\n}\n")
    for case in edges:
        text.append(f'\n///|\ntest "cdef libaom border reference {case.depth}-bit {case.width}x{case.height}" {{\n')
        text.append(f"  let input = cdef_reference_input({case.width}, {case.height}, {case.depth}, {case.seed})\n")
        text.append(f"  let params : Array[Av1CdefParams] = {moon_params(case.params)}\n")
        text.append(f"  let actual = av1_cdef_filter_plane({case.width}, {case.height}, input, params, bit_depth={case.depth}).unwrap()\n")
        text.append(f'  assert_eq(actual, cdef_reference_pixels("{packed(case)}", {case.depth}))\n}}\n')
    for y, u, v in yuv:
        text.append(f'\n///|\ntest "cdef libaom YUV420 reference {y.depth}-bit direction {y.params[0].direction}" {{\n')
        for label, case in (("y", y), ("u", u), ("v", v)):
            text.append(f"  let {label} = cdef_reference_input({case.width}, {case.height}, {case.depth}, {case.seed})\n")
        text.append(f"  let y_params : Array[Av1CdefParams] = {moon_params(y.params)}\n")
        text.append(f"  let uv_params : Array[Av1CdefParams] = {moon_params(u.params)}\n")
        text.append(f"  let (yf, uf, vf) = av1_cdef_filter_yuv420({y.width}, {y.height}, y, u, v, y_params, uv_params, bit_depth={y.depth}).unwrap()\n")
        for label, case in (("yf", y), ("uf", u), ("vf", v)):
            text.append(f'  assert_eq({label}, cdef_reference_pixels("{packed(case)}", {case.depth}))\n')
        text.append("}\n")
    return "".join(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    moon_tcc = Path.home() / ".moon/bin/internal/tcc.exe"
    default_cc = shutil.which("cc") or shutil.which("gcc") or (str(moon_tcc) if moon_tcc.exists() else "cc")
    parser.add_argument("--cc", default=default_cc, help="C compiler executable")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt",
                        help="standalone MoonBit formatter executable")
    parser.add_argument("--source-dir", type=Path, default=ROOT / "_refs/aom-cdef")
    parser.add_argument("--output", type=Path, default=ROOT / "av1_cdef_reference_test.mbt")
    parser.add_argument("--check", action="store_true", help="compare existing goldens without rewriting")
    args = parser.parse_args()
    formatter = shutil.which(args.moonfmt)
    if formatter is None:
        parser.error(f"MoonBit formatter not found: {args.moonfmt}; supply --moonfmt path/to/moonfmt")
    sources = load_sources(args.source_dir)
    matrix, edges, yuv = make_cases()
    cases = matrix + edges + [plane for triplet in yuv for plane in triplet]
    outputs, directions = run_reference(args.cc, reference_source(sources), cases)
    generated = subprocess.run(
        [formatter, "-"], input=render(matrix, edges, yuv, outputs, directions),
        text=True, encoding="utf-8", capture_output=True, check=True,
    ).stdout
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
            raise RuntimeError(f"{args.output}: goldens differ; regenerate without --check")
        print(f"Reproducibility check passed: {args.output}")
    else:
        args.output.write_text(generated, encoding="utf-8", newline="\n")
        print(f"Wrote {args.output}")
    pixels = sum(len(values) for values in outputs.values())
    changed = sum(a != b for case in cases for a, b in zip(case.pixels(), outputs[case.name]))
    print(f"{len(matrix)} matrix + {len(edges)} border + {len(yuv)} YUV420 cases; "
          f"{pixels} exact pixels; {changed} changed pixels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
