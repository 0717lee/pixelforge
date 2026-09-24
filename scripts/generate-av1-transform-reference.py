#!/usr/bin/env python3
"""Generate exact residual goldens with the original pinned libaom transforms.

    python scripts/generate-av1-transform-reference.py
    python scripts/generate-av1-transform-reference.py --check

Requires Python 3, a C compiler and standalone moonfmt. Sources are downloaded
from a fixed revision into an OS temporary-directory cache and SHA-256 checked
before every compilation. --source-dir, --cc and --moonfmt override locations.
No MoonBit implementation is used to compute the expected arrays.

Oracle boundary: the original inv_txfm2d_add_c, configuration/stage/flip
functions, integer helpers, tables and all 1D kernels are extracted unchanged.
Only highbd_clip_pixel_add is replaced by a recording sink: tests compare the
signed residual BEFORE prediction addition and pixel clipping. The sink does
not feed back into the transform. Input row-major coefficients are transposed
into libaom's column-major layout; recorded samples are returned row-major.
The shim supplies primitive C types, declarations and runtime dispatch macros.
CONFIG_COEFFICIENT_RANGE_CHECKING and DO_RANGE_CHECK_CLAMP are disabled, matching
normal libaom builds; the explicit original clamp_buf/clamp_value remain active.

Generated MoonBit tests need no C compiler or network. Each expected string
contains every signed residual as four hexadecimal digits (two's complement).
The 12-bit stress pattern stays inside the signed (bit_depth + 8)-bit input
range and deliberately exercises products exceeding signed 32-bit arithmetic.
It tests kernel arithmetic and clamping, not encoder reachability of a stream.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
BASE_URL = f"https://aomedia.googlesource.com/aom/+/{REVISION}/"
SOURCE_HASHES = {
    "av1_inv_txfm2d.c": "2956712253cd0a546ac8c4a1431322cee39538d6991fc25d0891090bc0f2be08",
    "av1_inv_txfm1d.c": "a4b9699340740844f1ad486e2d696ce52fd62f15d242b3203e54b71046bc4b07",
    "av1_inv_txfm1d_cfg.h": "bc8c410ea1492ccaaa8ded42bfe6aa52b66ea004a4790afde2769103325eb925",
    "av1_inv_txfm1d.h": "076be6972bb19f58bf3ad85b4118a05a327e4b4548ee8d5167eb51b49d126ed6",
    "av1_txfm.h": "af3bcaae01687bb47cb82386b619b6534962fe4c187e5bda54439d42071e5aad",
    "av1_txfm.c": "b5e16fad02ab634226ad1e10e9ea55ac6132aad376f70de710108f2f73b9035b",
    "enums.h": "d5fe41da228fb0bbb303776024971f2cb2c81e4231aa9e75c244578cd9f0ffb5",
    "common_data.h": "8561eb7066fa5f49a2d74c5ec9b8e7ed6dff93254414997f7497863dd1aa4938",
    "txfm_common.h": "2bb0a38e0b5d5358f463f5f652b59fa8859f206f0355c0b66895801851b4b983",
}
SIZES = ((4, 4, 0), (8, 8, 1), (16, 16, 2), (4, 8, 5), (8, 4, 6), (8, 16, 7), (16, 8, 8))
TYPES = (
    "Av1TxDctDct", "Av1TxAdstDct", "Av1TxDctAdst", "Av1TxAdstAdst",
    "Av1TxFlipadstDct", "Av1TxDctFlipadst", "Av1TxFlipadstFlipadst",
    "Av1TxAdstFlipadst", "Av1TxFlipadstAdst", "Av1TxIdentityIdentity",
    "Av1TxVerticalDct", "Av1TxHorizontalDct", "Av1TxVerticalAdst",
    "Av1TxHorizontalAdst", "Av1TxVerticalFlipadst", "Av1TxHorizontalFlipadst",
)


def load_sources(directory: Path) -> dict[str, str]:
    result = {}
    for name, expected in SOURCE_HASHES.items():
        path = directory / name
        if path.exists():
            data = path.read_bytes()
        else:
            folder = "aom_dsp/" if name == "txfm_common.h" else "av1/common/"
            with urllib.request.urlopen(BASE_URL + folder + name + "?format=TEXT", timeout=60) as response:
                data = base64.b64decode(response.read(), validate=True)
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise RuntimeError(f"{name}: SHA-256 {actual}, expected {expected}")
        if not path.exists():
            directory.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f"{name}: SHA-256 {actual}")
        result[name] = data.decode("utf-8")
    return result


def braced(source: str, marker: str, declaration: bool = False) -> str:
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if declaration:
        end = source.index(";", end) + 1
    return source[start:end]


def enum(source: str, name: str) -> str:
    end = source.index(f"}} UENUM1BYTE({name});") + len(f"}} UENUM1BYTE({name});")
    start = source.rindex("enum {", 0, end)
    return source[start:end]


C_SHIM = r"""
/* Header-free primitive declarations for MoonBit's bundled TinyCC. */
typedef signed char int8_t;
typedef unsigned short uint16_t;
typedef signed int int32_t;
typedef signed long long int64_t;
typedef int64_t tran_high_t;
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern int abs(int);
extern void abort(void);
extern void *memcpy(void *, const void *, unsigned long long);
extern void *memset(void *, int, unsigned long long);
#define NULL ((void *)0)
#define INT32_MIN (-2147483647 - 1)
#define INT32_MAX 2147483647
#define assert(condition) ((condition) ? (void)0 : abort())
#define AOMMAX(a, b) ((a) > (b) ? (a) : (b))
#define AOMMIN(a, b) ((a) < (b) ? (a) : (b))
#define UENUM1BYTE(name) ; typedef int name
#define av1_zero(array) memset(array, 0, sizeof(array))
#define CONFIG_COEFFICIENT_RANGE_CHECKING 0
#define DO_RANGE_CHECK_CLAMP 0
#define MAX_TXFM_STAGE_NUM 12
#define INV_COS_BIT 12
#define NewSqrt2Bits ((int32_t)12)
#define av1_round_shift_array av1_round_shift_array_c
static const int cos_bit_min = 10;
static const int32_t NewSqrt2 = 5793;
static const int32_t NewInvSqrt2 = 2896;
static int64_t clamp64(int64_t value, int64_t low, int64_t high) {
  return value < low ? low : value > high ? high : value;
}
typedef void (*TxfmFunc)(const int32_t *, int32_t *, int8_t, const int8_t *);
static int32_t captured[256];
static int captured_count;
/* Observe original final residuals, before pixel addition and clipping. */
static uint16_t highbd_clip_pixel_add(uint16_t prediction, tran_high_t residual, int bd) {
  (void)prediction;
  (void)bd;
  assert(captured_count < 256);
  captured[captured_count++] = residual;
  return 0;
}
"""

C_MAIN = r"""
int main(void) {
  int width, height, depth, tx_type, tx_size;
  int32_t coefficients[256], temporary[288];
  uint16_t output[256];
  assert(sizeof(int32_t) == 4 && sizeof(int64_t) == 8 && sizeof(uint16_t) == 2);
  while (scanf("%d %d %d %d %d", &width, &height, &depth, &tx_type, &tx_size) == 5) {
    assert(width <= 16 && height <= 16);
    assert(tx_size_wide[tx_size] == width && tx_size_high[tx_size] == height);
    for (int row = 0; row < height; ++row) {
      for (int col = 0; col < width; ++col) {
        /* The Moon API is row-major; the upstream 2D input is column-major. */
        if (scanf("%d", &coefficients[col * height + row]) != 1) return 2;
      }
    }
    av1_zero(output);
    captured_count = 0;
    inv_txfm2d_add_facade(coefficients, output, width, temporary, tx_type, tx_size, depth);
    assert(captured_count == width * height);
    for (int row = 0; row < height; ++row) {
      for (int col = 0; col < width; ++col) {
        printf("%d%c", captured[col * height + row],
               row == height - 1 && col == width - 1 ? '\n' : ' ');
      }
    }
  }
  return 0;
}
"""


def oracle_source(sources: dict[str, str]) -> str:
    one = sources["av1_inv_txfm1d.c"]
    two = sources["av1_inv_txfm2d.c"]
    txfm = sources["av1_txfm.c"]
    header = sources["av1_txfm.h"]
    parts = [one[:one.index("*/") + 2], C_SHIM]
    parts += [enum(sources["txfm_common.h"], name) for name in ("TX_SIZE", "TX_TYPE")]
    parts += [enum(sources["enums.h"], "TX_TYPE_1D"), enum(header, "TXFM_TYPE")]
    parts.append(braced(header, "typedef struct TXFM_2D_FLIP_CFG", True))
    for marker in ("static const TX_TYPE_1D vtx_tab", "static const TX_TYPE_1D htx_tab",
                   "static const int tx_size_wide[", "static const int tx_size_high[",
                   "static const int tx_size_wide_log2[", "static const int tx_size_high_log2["):
        parts.append(braced(sources["common_data.h"], marker, True))
    for marker in ("const int32_t av1_cospi_arr_data", "const int32_t av1_sinpi_arr_data",
                   "const TXFM_TYPE av1_txfm_type_ls", "const int8_t av1_txfm_stage_num_list"):
        parts.append(braced(txfm, marker, True))
    for marker in ("static inline const int32_t *cospi_arr(", "static inline const int32_t *sinpi_arr(",
                   "static inline int32_t range_check_value(", "static inline int64_t range_check_value64(",
                   "static inline int32_t round_shift(", "static inline int32_t half_btf(",
                   "static inline void get_flip_cfg(", "static inline void set_flip_cfg(",
                   "static inline int get_rect_tx_log_ratio(", "static inline int get_txw_idx(",
                   "static inline int get_txh_idx("):
        parts.append(braced(header, marker))
    for marker in ("static inline int32_t clamp_value(", "static inline void clamp_buf("):
        parts.append(braced(sources["av1_inv_txfm1d.h"], marker))
    parts += [braced(txfm, "void av1_range_check_buf("), braced(txfm, "void av1_round_shift_array_c(")]
    for name in ("av1_idct4", "av1_idct8", "av1_idct16", "av1_idct32", "av1_idct64",
                 "av1_iadst4", "av1_iadst8", "av1_iadst16", "av1_iidentity4_c",
                 "av1_iidentity8_c", "av1_iidentity16_c", "av1_iidentity32_c"):
        parts.append(braced(one, f"void {name}("))
    parts.append(two[two.index("static const int8_t inv_shift_4x4"):two.index("void av1_get_inv_txfm_cfg(")])
    parts.append(braced(sources["av1_inv_txfm1d_cfg.h"], "static const int8_t inv_start_range", True))
    for marker in ("static inline TxfmFunc inv_txfm_type_to_func(", "void av1_get_inv_txfm_cfg(",
                   "void av1_gen_inv_stage_range(", "static inline void inv_txfm2d_add_c(",
                   "static inline void inv_txfm2d_add_facade("):
        parts.append(braced(two, marker))
    parts.append(C_MAIN)
    return "\n\n".join(parts)


def coefficients(width: int, height: int, depth: int, stress: bool) -> list[int]:
    values = []
    for y in range(height):
        for x in range(width):
            if stress and ((x * 3 + y * 5) % 11 == 0 or (y == 0 and x == 2)):
                value = 450000 - (x * 733 + y * 941) % 40000
                if (x + y) % 2:
                    value = -value
            else:
                value = ((x * 37 + y * 53 + x * y * 11) % 257 - 128) * (1 << (depth - 8))
                value += (x + 3 * y) % 5 - 2
            values.append(value)
    return values


def make_cases() -> list[tuple[int, int, int, int, int, bool]]:
    return [(width, height, depth, tx_type, tx_size, stress)
            for depth, stress in ((8, False), (10, False), (12, False), (12, True))
            for width, height, tx_size in SIZES for tx_type in range(16)]


def run_oracle(cc: str, source: str, cases: list[tuple]) -> list[list[int]]:
    payload = []
    for width, height, depth, tx_type, tx_size, stress in cases:
        payload.append(f"{width} {height} {depth} {tx_type} {tx_size}")
        payload.append(" ".join(map(str, coefficients(width, height, depth, stress))))
    with tempfile.TemporaryDirectory(prefix="pixelforge-txfm-oracle-") as directory:
        root = Path(directory)
        source_path, executable = root / "reference.c", root / "reference.exe"
        source_path.write_text(source, encoding="utf-8")
        command = [cc]
        compiler_path = Path(cc).resolve()
        moon_root = compiler_path.parent.parent.parent
        if compiler_path.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command.extend(["-B", str(moon_root)])
        command.extend([str(source_path), "-o", str(executable)])
        print("Compile extracted original 2D/1D functions:", " ".join(command))
        subprocess.run(command, check=True)
        result = subprocess.run([str(executable)], input="\n".join(payload) + "\n",
                                text=True, capture_output=True, check=True)
    rows = [list(map(int, line.split())) for line in result.stdout.splitlines()]
    if len(rows) != len(cases):
        raise RuntimeError("oracle output case count mismatch")
    for case, row in zip(cases, rows):
        if len(row) != case[0] * case[1] or any(v < -32768 or v > 32767 for v in row):
            raise RuntimeError(f"invalid residual output for {case}")
    return rows


MOON_HELPERS = """///|
// Input generation only; expected residuals come from the original C kernels.
fn transform_reference_coefficients(width : Int, height : Int, bit_depth : Int, stress : Bool) -> Array[Int] {
  let values : Array[Int] = []
  for y in 0..<height {
    for x in 0..<width {
      let value = if stress && ((x * 3 + y * 5) % 11 == 0 || (y == 0 && x == 2)) {
        let magnitude = 450000 - (x * 733 + y * 941) % 40000
        if (x + y) % 2 == 0 { magnitude } else { -magnitude }
      } else {
        ((x * 37 + y * 53 + x * y * 11) % 257 - 128) * (1 << (bit_depth - 8)) + (x + 3 * y) % 5 - 2
      }
      values.push(value)
    }
  }
  values
}

///|
fn transform_reference_residual(hex : String) -> Array[Int] {
  let values : Array[Int] = []
  for i in 0..<(hex.length() / 4) {
    let mut value = 0
    for j in 0..<4 {
      let code = hex[i * 4 + j].to_int()
      value = value * 16 + (if code <= 57 { code - 48 } else { code - 87 })
    }
    values.push(if value < 32768 { value } else { value - 65536 })
  }
  values
}
"""


def render(cases: list[tuple], outputs: list[list[int]]) -> str:
    text = [
        "// Generated by scripts/generate-av1-transform-reference.py. Do not edit.\n",
        f"// Original libaom revision: {REVISION}\n// Source: {BASE_URL}\n",
        "// Copyright (c) 2016-2017, Alliance for Open Media. All rights reserved.\n",
        "// Upstream code: BSD 2 Clause License and Alliance for Open Media Patent License 1.0.\n",
        "// https://www.aomedia.org/license/software and https://www.aomedia.org/license/patent\n",
        "// Oracle: unmodified inv_txfm2d_add_c + cfg/stage/flip functions + original 1D kernels.\n",
        "// Boundary: replace final highbd_clip_pixel_add with a signed residual recording sink.\n",
        "// Transpose row-major coefficients to upstream column-major input; retain all residuals.\n",
        "// Normal coefficient range-check build flags; original explicit clamps remain active.\n",
        "// 336 asymmetric cases + 112 bounded 12-bit stress cases; 16 types x 7 geometries.\n",
    ]
    for name, digest in SOURCE_HASHES.items():
        text.append(f"// {name} SHA-256: {digest}\n")
    text.append("\n" + MOON_HELPERS)
    for start in range(0, len(cases), 16):
        width, height, depth, _, _, stress = cases[start]
        label = "stress" if stress else "asymmetric"
        text.append(f'\n///|\ntest "av1 libaom all transform residuals {width}x{height} {depth}-bit {label}" {{\n')
        text.append(f"let width = {width}\nlet height = {height}\nlet bit_depth = {depth}\n")
        text.append(f"let input = transform_reference_coefficients(width, height, bit_depth, {str(stress).lower()})\n")
        text.append("let types : Array[Av1TxType] = [" + ", ".join(TYPES) + "]\n")
        text.append("let expected : Array[String] = [\n")
        for row in outputs[start:start + 16]:
            text.append('"' + "".join(f"{value & 65535:04x}" for value in row) + '",\n')
        text.append(
            "]\nfor index in 0..<types.length() {\n"
            "let actual = av1_inverse_transform_2d(types[index], input, width, height, bit_depth).unwrap()\n"
            "assert_eq((index, actual), (index, transform_reference_residual(expected[index])))\n}\n}\n"
        )
    return "".join(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    moon_tcc = Path.home() / ".moon/bin/internal/tcc.exe"
    parser.add_argument("--cc", default=shutil.which("cc") or shutil.which("gcc") or (str(moon_tcc) if moon_tcc.exists() else "cc"))
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--source-dir", type=Path, default=Path(tempfile.gettempdir()) / ("pixelforge-aom-transform-" + REVISION))
    parser.add_argument("--output", type=Path, default=ROOT / "av1_transform_reference_test.mbt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    formatter = shutil.which(args.moonfmt)
    if formatter is None:
        parser.error(f"MoonBit formatter not found: {args.moonfmt}; supply --moonfmt")
    cases = make_cases()
    outputs = run_oracle(args.cc, oracle_source(load_sources(args.source_dir)), cases)
    generated = subprocess.run([formatter, "-"], input=render(cases, outputs), text=True,
                               encoding="utf-8", capture_output=True, check=True).stdout
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
            raise RuntimeError(f"{args.output}: generated reference differs; regenerate without --check")
        print(f"Reproducibility check passed: {args.output}")
    else:
        args.output.write_text(generated, encoding="utf-8", newline="\n")
        print(f"Wrote {args.output}")
    print(f"{len(cases)} cases, {sum(map(len, outputs))} exact signed residuals, "
          f"range [{min(map(min, outputs))}, {max(map(max, outputs))}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
