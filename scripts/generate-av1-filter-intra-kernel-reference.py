#!/usr/bin/env python3
"""Build filter-intra references using unchanged, pinned scalar libaom C.

No AV1 encoding or Moon build is involved. --check uses only Python to verify
canonical outputs, per-case SHA/CRC, deterministic inputs and generated WB bytes.
The original full edge builders handle missing/partial references before the
original predictors run. Python constructs inputs and packs outputs only.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib


ROOT = Path(__file__).resolve().parents[1]
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
SOURCE_HASHES = {
    "av1/common/reconintra.c": "710299b97e4bede074bd098ad2c0154d21c8734f0a0cb344de15d5d03dd62fe9",
    "av1/common/reconintra.h": "7a63726d585ecd4c7cbe2502de8a6cdbf386e5c589ecf6f807e70059f4ed9a78",
    "aom_dsp/aom_dsp_common.h": "438b026ee7fc0484643ac7ca73246290a77c1384862264df146f669893ee98d9",
    "aom_ports/mem.h": "6d3c074d3e295e64c634101a0f95341a69331d3c880b8a3fce7095355f37cb1c",
    "aom_mem/aom_mem.h": "71b98c64b9d7b3380e796e3a7fcd7ea98f6c7b135a3576357cf23eb647acba61",
    "av1/common/common_data.h": "8561eb7066fa5f49a2d74c5ec9b8e7ed6dff93254414997f7497863dd1aa4938",
    "av1/common/enums.h": "d5fe41da228fb0bbb303776024971f2cb2c81e4231aa9e75c244578cd9f0ffb5",
    "aom_dsp/txfm_common.h": "2bb0a38e0b5d5358f463f5f652b59fa8859f206f0355c0b66895801851b4b983",
}
ALL_SHAPES = ((4, 4), (8, 8), (16, 16), (32, 32), (64, 64), (4, 8),
              (8, 4), (8, 16), (16, 8), (16, 32), (32, 16), (32, 64),
              (64, 32), (4, 16), (16, 4), (8, 32), (32, 8), (16, 64), (64, 16))
SHAPES = tuple(shape for shape in ALL_SHAPES if max(shape) <= 32)
AVAILABILITY = ("full", "missing_top", "missing_left", "missing_both",
                "partial_top", "partial_left")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def packed(values) -> bytes:
    return struct.pack("<" + "H" * len(values), *values)


def load_sources(directory: Path) -> dict[str, str]:
    revision = subprocess.run(["git", "-C", str(directory), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    if revision != REVISION:
        raise RuntimeError(f"unexpected source revision: {revision}")
    result = {}
    for name, digest in SOURCE_HASHES.items():
        data = subprocess.run(["git", "-C", str(directory), "show", f"{REVISION}:{name}"],
                              capture_output=True, check=True).stdout
        if sha(data) != digest or (directory / name).read_bytes().replace(b"\r\n", b"\n") != data:
            raise RuntimeError(f"modified or incorrectly pinned original source: {name}")
        result[name] = data.decode()
    return result


def braced(source: str, marker: str, declaration=False) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    nesting, end = 1, opening + 1
    while nesting:
        nesting += (source[end] == "{") - (source[end] == "}")
        end += 1
    if declaration:
        end = source.index(";", end) + 1
    return source[start:end]


def macro(source: str, name: str) -> str:
    lines = source.splitlines()
    start = next(i for i, line in enumerate(lines)
                 if re.match(r"#define " + re.escape(name) + r"(?:\(|\s)", line))
    end = start
    while lines[end].endswith("\\"):
        end += 1
    return "\n".join(lines[start:end + 1])


C_TYPES = r"""
typedef unsigned char uint8_t;
typedef signed char int8_t;
typedef unsigned short uint16_t;
typedef signed short int16_t;
typedef unsigned long long uintptr_t;
typedef unsigned long long size_t;
typedef signed long long ptrdiff_t;
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern void exit(int);
extern void *memcpy(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
#define DECLARE_ALIGNED(n, type, var) type var
static int oracle_forbidden(int line) {
  printf("unreachable/assertion path at extracted line %d\n", line);
  exit(10);
  return 0;
}
#define assert(condition) ((condition) ? (void)0 : (void)oracle_forbidden(__LINE__))
static int low_clips[2], high_clips[2], low_calls, high_calls;
static int record_rounding, negative_round_inputs, rounding_residues[16];
static uint16_t prepared_top[33], prepared_left[32];
"""


C_CLIP_WRAPPERS = r"""
/* These wrappers only count real clipping calls; original helpers return pixels. */
static uint8_t oracle_clip_pixel(int value) {
  low_clips[0] += value < 0;
  low_clips[1] += value > 255;
  return clip_pixel(value);
}
static uint16_t oracle_clip_pixel_highbd(int value, int depth) {
  high_clips[0] += value < 0;
  high_clips[1] += value >= (1 << depth);
  return clip_pixel_highbd(value, depth);
}
static int oracle_round(int value, int bits) {
  assert(bits == 4);
  if (record_rounding) {
    ++rounding_residues[value & 15];
    negative_round_inputs += value < 0;
  }
  return ROUND_POWER_OF_TWO(value, bits);
}
#define clip_pixel oracle_clip_pixel
#define clip_pixel_highbd oracle_clip_pixel_highbd
#undef ROUND_POWER_OF_TWO
#define ROUND_POWER_OF_TWO oracle_round
"""


C_DISPATCH = r"""
#undef clip_pixel
#undef clip_pixel_highbd
static void oracle_filter8(uint8_t *dst, ptrdiff_t stride, TX_SIZE tx_size,
                           const uint8_t *above, const uint8_t *left, int mode) {
  ++low_calls;
  for (int i = -1; i < tx_size_wide[tx_size]; ++i) assert(above[i] == prepared_top[i + 1]);
  for (int i = 0; i < tx_size_high[tx_size]; ++i) assert(left[i] == prepared_left[i]);
  av1_filter_intra_predictor_c(dst, stride, tx_size, above, left, mode);
}
static void oracle_filter16(uint16_t *dst, ptrdiff_t stride, TX_SIZE tx_size,
                            const uint16_t *above, const uint16_t *left,
                            int mode, int depth) {
  ++high_calls;
  for (int i = -1; i < tx_size_wide[tx_size]; ++i) prepared_top[i + 1] = above[i];
  for (int i = 0; i < tx_size_high[tx_size]; ++i) prepared_left[i] = left[i];
  highbd_filter_intra_predictor(dst, stride, tx_size, above, left, mode, depth);
}
#define av1_filter_intra_predictor oracle_filter8
#define highbd_filter_intra_predictor oracle_filter16
/* The unchanged full builders return from filter-intra before these paths.
   Fail-fast substitutions ensure a routing mistake cannot yield fake pixels. */
#define intra_edge_filter_strength(...) oracle_forbidden(__LINE__)
#define av1_use_intra_edge_upsample(...) oracle_forbidden(__LINE__)
#define filter_intra_edge_corner(...) oracle_forbidden(__LINE__)
#define highbd_filter_intra_edge_corner(...) oracle_forbidden(__LINE__)
#define av1_filter_intra_edge(...) oracle_forbidden(__LINE__)
#define av1_highbd_filter_intra_edge(...) oracle_forbidden(__LINE__)
#define av1_upsample_intra_edge(...) oracle_forbidden(__LINE__)
#define av1_highbd_upsample_intra_edge(...) oracle_forbidden(__LINE__)
#define dr_predictor(...) oracle_forbidden(__LINE__)
#define highbd_dr_predictor(...) oracle_forbidden(__LINE__)
"""


C_MAIN = r"""
int main(void) {
  uint16_t reference[34 * 34], output[32 * 32];
  uint8_t reference8[34 * 34], output8[32 * 32];
  int id, mode, tx, depth, n_top, n_left, corner;
  assert(sizeof(uint16_t) == 2 && sizeof(int) == 4 && sizeof(void *) == 8);
  assert((-1 >> 1) == -1);
  while (scanf("%d %d %d %d %d %d %d", &id, &mode, &tx, &depth,
               &n_top, &n_left, &corner) == 7) {
    assert(tx >= 0 && tx < TX_SIZES_ALL && mode >= 0 && mode < FILTER_INTRA_MODES);
    assert(depth == 8 || depth == 10 || depth == 12);
    int w = tx_size_wide[tx], h = tx_size_high[tx], value;
    assert(w <= 32 && h <= 32 && n_top >= 0 && n_top <= w && n_left >= 0 && n_left <= h);
    aom_memset16(reference, 0x6A6A, 34 * 34);
    aom_memset16(output, 0x6A6A, 32 * 32);
    memset(reference8, 0xAA, 34 * 34);
    memset(output8, 0xAA, 32 * 32);
    reference[0] = corner;
    reference8[0] = corner;
    for (int i = 0; i < w; ++i) {
      if (scanf("%d", &value) != 1) return 11;
      reference[1 + i] = value;
      reference8[1 + i] = value;
    }
    for (int i = 0; i < h; ++i) {
      if (scanf("%d", &value) != 1) return 12;
      reference[(1 + i) * 34] = value;
      reference8[(1 + i) * 34] = value;
    }
    low_calls = high_calls = 0;
    low_clips[0] = low_clips[1] = high_clips[0] = high_clips[1] = 0;
    record_rounding = 1;
    negative_round_inputs = 0;
    for (int i = 0; i < 16; ++i) rounding_residues[i] = 0;
    highbd_build_directional_and_filter_intra_predictors(
        CONVERT_TO_BYTEPTR(reference + 35), 34, CONVERT_TO_BYTEPTR(output), 32,
        DC_PRED, 0, mode, tx, 0, n_top, -1, n_left, -1, 0, depth);
    assert(high_calls == 1);
    record_rounding = 0;
    if (depth == 8) {
      build_directional_and_filter_intra_predictors(
          reference8 + 35, 34, output8, 32,
          DC_PRED, 0, mode, tx, 0, n_top, -1, n_left, -1, 0);
      assert(low_calls == 1 && low_clips[0] == high_clips[0] && low_clips[1] == high_clips[1]);
    }
    printf("%d %d %d %d %d", id, high_calls, low_calls, high_clips[0], high_clips[1]);
    printf(" %d", negative_round_inputs);
    for (int i = 0; i < 16; ++i) printf(" %d", rounding_residues[i]);
    for (int i = 0; i < w + 1; ++i) printf(" %d", prepared_top[i]);
    for (int i = 0; i < h; ++i) printf(" %d", prepared_left[i]);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        assert(output[y * 32 + x] < (1 << depth));
        if (depth == 8) assert(output[y * 32 + x] == output8[y * 32 + x]);
        printf(" %d", output[y * 32 + x]);
      }
    }
    for (int y = 0; y < 32; ++y) {
      for (int x = 0; x < 32; ++x) {
        if (y >= h || x >= w) {
          assert(output[y * 32 + x] == 0x6A6A);
          if (depth == 8) assert(output8[y * 32 + x] == 0xAA);
        }
      }
    }
    printf("\n");
  }
  return 0;
}
"""


def reference_source(sources):
    recon = sources["av1/common/reconintra.c"]
    parts, extracted = [recon[:recon.index("*/") + 2], C_TYPES], []

    def add(filename, name, text):
        start = sources[filename].index(text)
        extracted.append({"source": filename, "name": name,
                          "line": sources[filename][:start].count("\n") + 1,
                          "sha256": sha(text.encode())})
        parts.append(text)

    def function(filename, marker):
        add(filename, marker.split("(")[0], braced(sources[filename], marker))

    def table(filename, marker):
        add(filename, marker.split("[")[0], braced(sources[filename], marker, declaration=True))

    for name in ("ROUND_POWER_OF_TWO", "CONVERT_TO_SHORTPTR", "CONVERT_TO_BYTEPTR", "UENUM1BYTE"):
        add("aom_ports/mem.h", name, macro(sources["aom_ports/mem.h"], name))
    for filename, first in (("aom_dsp/txfm_common.h", "TX_4X4"),
                            ("av1/common/enums.h", "DC_PRED"),
                            ("av1/common/enums.h", "FILTER_DC_PRED")):
        source = sources[filename]
        start = source.rindex("enum {", 0, source.index(first + ","))
        add(filename, first + " enum", braced(source[start:], "enum {", declaration=True))
    for name in ("MAX_TX_SIZE_LOG2", "MAX_TX_SIZE"):
        add("av1/common/enums.h", name, macro(sources["av1/common/enums.h"], name))
    add("av1/common/reconintra.h", "FILTER_INTRA_SCALE_BITS", macro(sources["av1/common/reconintra.h"], "FILTER_INTRA_SCALE_BITS"))
    add("av1/common/reconintra.c", "NUM_INTRA_NEIGHBOUR_PIXELS", macro(recon, "NUM_INTRA_NEIGHBOUR_PIXELS"))
    add("av1/common/reconintra.c", "NEED_LEFT enum", braced(recon, "enum {", declaration=True))
    table("av1/common/reconintra.c", "static const uint8_t extend_modes[")
    table("av1/common/common_data.h", "static const int tx_size_wide[")
    table("av1/common/common_data.h", "static const int tx_size_high[")
    table("av1/common/reconintra.c", "DECLARE_ALIGNED(16, const int8_t,")
    function("aom_mem/aom_mem.h", "static inline void *aom_memset16(")
    function("aom_dsp/aom_dsp_common.h", "static inline int clamp(")
    function("aom_dsp/aom_dsp_common.h", "static inline uint8_t clip_pixel(")
    function("aom_dsp/aom_dsp_common.h", "static inline uint16_t clip_pixel_highbd(")
    function("av1/common/reconintra.h", "static inline int av1_is_directional_mode(")
    parts.append(C_CLIP_WRAPPERS)
    function("av1/common/reconintra.c", "void av1_filter_intra_predictor_c(")
    function("av1/common/reconintra.c", "static void highbd_filter_intra_predictor(")
    parts.append(C_DISPATCH)
    function("av1/common/reconintra.c", "static void build_directional_and_filter_intra_predictors(")
    function("av1/common/reconintra.c", "static void highbd_build_directional_and_filter_intra_predictors(")
    parts.append(C_MAIN)
    return "\n\n".join(parts), extracted


def edge_inputs(case):
    maximum, seed = (1 << case["bit_depth"]) - 1, case["seed"]
    if case["variant"] == 1:
        above = [0 if (i + seed) % 4 < 2 else maximum for i in range(case["width"])]
        left = [maximum if (i + seed + 2) % 4 < 2 else 0 for i in range(case["height"])]
    else:
        above = [(seed * 37 + i * 29 + (i % 7) * i * 11) & maximum for i in range(case["width"])]
        left = [(seed * 53 + i * 43 + (i % 5) * i * 17) & maximum for i in range(case["height"])]
    return above, left


def make_cases():
    result, offset = [], 0
    for depth in (8, 10, 12):
        for mode in range(5):
            for width, height in SHAPES:
                for availability in AVAILABILITY:
                    n_top = 0 if availability in ("missing_top", "missing_both") else width
                    n_left = 0 if availability in ("missing_left", "missing_both") else height
                    if availability == "partial_top":
                        n_top = width - 3
                    if availability == "partial_left":
                        n_left = height - 3
                    for variant in range(2):
                        index, maximum = len(result), (1 << depth) - 1
                        seed = 1009 + index
                        corner = ((maximum - (seed & 3)) if seed & 4 else seed & 3) if variant else (seed * 97 + 19) & maximum
                        case = {"index": index, "mode": mode, "width": width, "height": height,
                                "tx_size": ALL_SHAPES.index((width, height)), "bit_depth": depth,
                                "availability": availability, "n_top": n_top, "n_left": n_left,
                                "variant": variant, "seed": seed, "corner": corner,
                                "offset_bytes": offset, "sample_count": width * height}
                        above, left = edge_inputs(case)
                        case["input_sha256"] = sha(packed([corner] + above + left))
                        result.append(case)
                        offset += width * height * 2
    return result


def run_reference(args, source, cases):
    compiler = Path(shutil.which(args.cc) or args.cc).resolve()
    payload = []
    for case in cases:
        payload.append(" ".join(str(case[field]) for field in
                               ("index", "mode", "tx_size", "bit_depth", "n_top", "n_left", "corner")))
        payload.extend(" ".join(map(str, edge)) for edge in edge_inputs(case))
    with tempfile.TemporaryDirectory(prefix="pixelforge-filter-intra-") as temporary_name:
        temporary = Path(temporary_name)
        c_file, executable = temporary / "reference.c", temporary / "reference.exe"
        c_file.write_text(source, encoding="utf-8", newline="\n")
        command = [str(compiler)]
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command += ["-B", str(moon_root)]
        command += [str(c_file), "-o", str(executable)]
        print("Compiling unchanged original scalar functions:", subprocess.list2cmdline(command))
        subprocess.run(command, check=True)
        output = subprocess.run([str(executable)], input="\n".join(payload) + "\n",
                                capture_output=True, text=True, check=True).stdout
        display_command = [word.replace(str(temporary), "<temporary>") for word in command]
    lines = output.splitlines()
    if len(lines) != len(cases):
        raise RuntimeError(f"original-C case count {len(lines)}, expected {len(cases)}")
    binary = bytearray()
    for case, line in zip(cases, lines):
        values = list(map(int, line.split()))
        edge_count = case["width"] + case["height"] + 1
        if len(values) != 22 + edge_count + case["sample_count"] or values[0] != case["index"]:
            raise RuntimeError(f"invalid original-C result extent/order: {case['index']}")
        case["oracle_paths"] = dict(zip(("highbd_predictor_calls", "lowbd_predictor_calls", "clip_low", "clip_high"), values[1:5]))
        case["oracle_paths"]["negative_round_inputs"] = values[5]
        case["rounding_residue_counts"] = values[6:22]
        case["prepared_edges_sha256"] = sha(packed(values[22:22 + edge_count]))
        pixels = values[22 + edge_count:]
        if any(v < 0 or v >= 1 << case["bit_depth"] for v in pixels):
            raise RuntimeError(f"invalid original-C native sample: {case['index']}")
        data = packed(pixels)
        case["output_sha256"], case["output_crc32"] = sha(data), zlib.crc32(data)
        binary.extend(data)
    version = subprocess.run([str(compiler), "-v"], capture_output=True, text=True, check=True)
    return bytes(binary), {"path": str(compiler), "sha256": sha(compiler.read_bytes()),
                           "version": (version.stdout + version.stderr).strip(),
                           "command": display_command, "translation_unit_sha256": sha(source.encode())}


def validate(cases, binary):
    expected = make_cases()
    if len(cases) != 2520 or len(cases) != len(expected) or len(binary) != 1203840:
        raise RuntimeError("corpus count/extent mismatch")
    paths = Counter()
    clipped_groups, rounding_groups = {}, {}
    for case, construction in zip(cases, expected):
        if any(case.get(key) != value for key, value in construction.items()):
            raise RuntimeError(f"deterministic construction changed: {construction['index']}")
        start, size = case["offset_bytes"], case["sample_count"] * 2
        data = binary[start:start + size]
        if sha(data) != case["output_sha256"] or zlib.crc32(data) != case["output_crc32"]:
            raise RuntimeError(f"canonical pixels changed: {case['index']}")
        if any(v[0] >= 1 << case["bit_depth"] for v in struct.iter_unpack("<H", data)):
            raise RuntimeError("canonical sample exceeds native depth")
        trace = case["oracle_paths"]
        if trace["highbd_predictor_calls"] != 1 or trace["lowbd_predictor_calls"] != (case["bit_depth"] == 8):
            raise RuntimeError("original predictor routing proof mismatch")
        paths.update(trace)
        key = f"{case['bit_depth']}bit_mode{case['mode']}"
        clipped_groups.setdefault(key, Counter()).update({"clip_low": trace["clip_low"], "clip_high": trace["clip_high"]})
        if len(case["rounding_residue_counts"]) != 16 or sum(case["rounding_residue_counts"]) != case["sample_count"]:
            raise RuntimeError("original rounding call count mismatch")
        rounding_groups.setdefault(key, Counter()).update(dict(enumerate(case["rounding_residue_counts"])))
    if any(not counts["clip_low"] or not counts["clip_high"] for counts in clipped_groups.values()):
        raise RuntimeError(f"missing clipping direction in mode/depth group: {clipped_groups}")
    if any(not counts[8] for counts in rounding_groups.values()):
        raise RuntimeError("missing native-unit half-way rounding in a mode/depth group")
    return {"case_count": len(cases), "shape_count": len(SHAPES), "native_sample_count": len(binary) // 2,
            "legal_tx_shapes": [list(shape) for shape in SHAPES],
            "availability_counts": dict(Counter(c["availability"] for c in cases)),
            "actual_original_c_paths": dict(paths),
            "clipping_by_depth_mode": {key: dict(value) for key, value in clipped_groups.items()},
            "rounding_residues_by_depth_mode": {key: [value[i] for i in range(16)] for key, value in rounding_groups.items()},
            "lowbd_highbd8_pixel_and_prepared_edge_parity_cases": 840,
            "directional_edge_filter_or_upsample_calls": 0}


MOON_HELPER = """///|
// Only input construction is reproduced here; all expected pixels come from C.
fn av1_filter_intra_kernel_reference_case(
  index : Int,
  mode : Int,
  width : Int,
  height : Int,
  depth : Int,
  variant : Int,
  seed : Int,
  corner : Int,
  n_top : Int,
  n_left : Int,
  expected_crc : UInt,
  expected_pixels : Array[Int],
) -> Unit raise {
  let maximum = (1 << depth) - 1
  let above : Array[Int] = []
  let left : Array[Int] = []
  for i in 0..<n_top {
    above.push(if variant == 1 {
      if (i + seed) % 4 < 2 { 0 } else { maximum }
    } else {
      (seed * 37 + i * 29 + (i % 7) * i * 11) & maximum
    })
  }
  for i in 0..<n_left {
    left.push(if variant == 1 {
      if (i + seed + 2) % 4 < 2 { maximum } else { 0 }
    } else {
      (seed * 53 + i * 43 + (i % 5) * i * 17) & maximum
    })
  }
  let actual = av1_filter_intra_predict(
    mode, width, height, above, left, corner, depth, n_top, n_left,
  ).unwrap()
  assert_eq((index, actual.length()), (index, width * height))
  let bytes : Array[Byte] = []
  let mut in_range = true
  for pixel in actual {
    if pixel < 0 || pixel > maximum { in_range = false }
    bytes.push((pixel & 255).to_byte())
    bytes.push((pixel >> 8).to_byte())
  }
  assert_eq((index, in_range), (index, true))
  assert_eq((index, crc32(bytes, 0, bytes.length())), (index, expected_crc))
  if expected_pixels.length() > 0 {
    assert_eq((index, actual), (index, expected_pixels))
  }
}
"""


def render_test(cases, binary):
    parts = ["// Generated by scripts/generate-av1-filter-intra-kernel-reference.py.\n",
             f"// Unchanged original scalar AOM revision: {REVISION}\n",
             f"// Full canonical uint16LE output SHA-256: {sha(binary)}\n",
             "// 2520 cases; every output sample contributes to CRC32.\n",
             "// All180 TX4x4 cases also compare complete pixel arrays.\n\n", MOON_HELPER]
    fields = ("index", "mode", "width", "height", "bit_depth", "variant", "seed", "corner", "n_top", "n_left")
    for depth in (8, 10, 12):
        for mode in range(5):
            parts.append(f'\n///|\ntest "original AOM filter intra {depth}bit mode{mode} all shapes and edges" {{\n')
            for case in cases:
                if case["bit_depth"] != depth or case["mode"] != mode:
                    continue
                args = [str(case[field]) for field in fields]
                args.append(f"0x{case['output_crc32']:08x}U")
                start, count = case["offset_bytes"], case["sample_count"]
                pixels = list(struct.unpack("<16H", binary[start:start + 32])) if count == 16 else []
                args.append(str(pixels))
                parts.append("  av1_filter_intra_kernel_reference_case(" + ", ".join(args) + ")\n")
            parts.append("}\n")
    return "".join(parts)


def manifest_text(manifest):
    metadata = {key: value for key, value in manifest.items() if key != "cases"}
    text = json.dumps(metadata, indent=2)[:-2]
    return text + ',\n  "cases": [\n' + ",\n".join(
        "    " + json.dumps(case, separators=(",", ":")) for case in manifest["cases"]) + "\n  ]\n}\n"


def check(args):
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    if manifest["generator_sha256"] != sha(Path(__file__).read_bytes()):
        raise RuntimeError("generator changed; regenerate original-C outputs")
    binary = (args.out / "output.bin").read_bytes()
    if sha(binary) != manifest["output_sha256"] or manifest["source_sha256"] != SOURCE_HASHES:
        raise RuntimeError("canonical output or original source hashes changed")
    if validate(manifest["cases"], binary) != manifest["coverage"]:
        raise RuntimeError("coverage evidence changed")
    raw = render_test(manifest["cases"], binary)
    if sha(raw.encode()) != manifest["unformatted_test_sha256"]:
        raise RuntimeError("canonical test reconstruction changed")
    target = args.test or ROOT / manifest["test_file"]
    if sha(target.read_bytes()) != manifest["test_sha256"]:
        raise RuntimeError(f"generated WB hash differs: {target}")
    print("Checked2520 original-C cases, canonical output and per-case SHA/CRC, coverage and15-group WB; Python only")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    parser.add_argument("--cc", default=shutil.which("cc") or str(Path.home() / ".moon/bin/internal/tcc.exe"))
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-filter-intra-kernel")
    parser.add_argument("--test", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check(args)
        return
    sources = load_sources(args.source_dir)
    source, excerpts = reference_source(sources)
    cases = make_cases()
    binary, compiler = run_reference(args, source, cases)
    coverage = validate(cases, binary)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "output.bin").write_bytes(binary)
    target = args.test or ROOT / "_refs/av1_filter_intra_kernel_reference_wbtest.mbt"
    raw = render_test(cases, binary)
    formatted = subprocess.run([args.moonfmt, "-"], input=raw, capture_output=True, text=True, check=True).stdout
    target.write_text(formatted, encoding="utf-8", newline="\n")
    manifest = {"scope": "all5 filter-intra modes,14 legal TX shapes,3 native depths,6 edge states,2 input patterns",
                "revision": REVISION, "source_sha256": SOURCE_HASHES, "extracted_original_fragments": excerpts,
                "source_url": f"https://aomedia.googlesource.com/aom/+/{REVISION}/av1/common/reconintra.c",
                "compiler": compiler, "generator_sha256": sha(Path(__file__).read_bytes()),
                "generation_command": [sys.executable, str(Path(__file__).resolve()),
                                       "--source-dir", str(args.source_dir.resolve()),
                                       "--cc", compiler["path"], "--moonfmt", args.moonfmt,
                                       "--out", str(args.out.resolve()), "--test", str(target.resolve())],
                "input_patterns": {"0": "above=(seed*37+i*29+(i%7)*i*11)&maximum; left=(seed*53+i*43+(i%5)*i*17)&maximum",
                                   "1": "above=0 if(i+seed)%4<2 else maximum; left=maximum if(i+seed+2)%4<2 else0"},
                "edge_builder": {"mode": "DC_PRED", "n_topright": -1, "n_bottomleft": -1,
                                 "disable_edge_filter": 0, "intra_edge_filter_type": 0,
                                 "prepared_edge_hash_layout": "corner, width top samples, height left samples;uint16LE"},
                "output_layout": "concatenated row-major native uint16 little-endian planes, offsets in cases",
                "output_sha256": sha(binary), "coverage": coverage,
                "test_file": target.relative_to(ROOT).as_posix(), "test_sha256": sha(target.read_bytes()),
                "unformatted_test_sha256": sha(raw.encode()), "cases": cases}
    (args.out / "manifest.json").write_text(manifest_text(manifest), encoding="utf-8", newline="\n")
    print(f"Generated2520 original-C filter-intra cases; output SHA256 {sha(binary)}")
    check(args)


if __name__ == "__main__":
    main()
