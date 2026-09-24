#!/usr/bin/env python3
"""Generate directional intra pixels with unchanged pinned libaom scalar C.

Example (no MoonBit build or formatter is involved)::

    python scripts/generate-av1-directional-reference.py --source-dir path/to/aom
    python scripts/generate-av1-directional-reference.py --source-dir path/to/aom --check

The local source checkout must match every pinned SHA-256 below. The original
high-bit-depth builder performs edge preparation, filtering, corner filtering,
upsampling and scalar directional prediction for 8/10/12-bit inputs. Python only
constructs inputs and packs the resulting native samples. No AV1 encoder runs.

output.bin concatenates row-major uint16 little-endian samples for every case.
manifest.json stores case inputs as deterministic formulas, offsets, hashes and
actual C path counters; it contains no output pixel arrays. Temporary C source
and executable are removed after each invocation. --check recompiles the oracle
and compares the complete binary and deterministic metadata without writing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
SOURCE_URL = f"https://aomedia.googlesource.com/aom/+/{REVISION}/"
SOURCE_HASHES = {
    "av1/common/reconintra.c": "e5edc08da243008f08a2e6f0bd49b812bf04c7366cca27b37eb96322b9049190",
    "av1/common/reconintra.h": "80b8cf1912641c1f2fd3bbed701a5ee77121754551c0de044f314e144f7dcfa4",
    "aom_dsp/intrapred.c": "d49c64a7d3507775b7d106bb3d8f52d3e420dd5aa999dd2ef8f3473b12ac9d15",
    "aom_dsp/aom_dsp_common.h": "d7dfeb3a2cde0579cdf29e420de121c2058e158d76606510b256a88d33593500",
    "aom_ports/mem.h": "1d24465759072fc2096b89a96a346402d73671d9477d0b98350c70872669453a",
    "aom_mem/aom_mem.h": "08667ece79624894a8085b280e2e6e52735d4eaf1fbbd089b7da43423f86bfe8",
    "av1/common/common_data.h": "ea34ab639d0a95dd7e2b3062be171bb995b5aceed7210c31b8f4e8df96ae8362",
    "av1/common/blockd.h": "81e0430c63d44bb3871a6d554c4e626d3115922afb026e3d80b313601ab80c9f",
    "av1/common/enums.h": "5c5e687c99335d01161ff939fb3e506be6d3aaf8d215d4848a00d67b5450b7b9",
    "aom_dsp/txfm_common.h": "58ae2822756f679087bff8a40e2c5e9088d4dc672c8ac501a998de9a4d657369",
}
SHAPES = ((4, 4), (8, 8), (16, 16), (32, 32), (64, 64), (4, 8),
          (8, 4), (8, 16), (16, 8), (16, 32), (32, 16), (32, 64),
          (64, 32), (4, 16), (16, 4), (8, 32), (32, 8), (16, 64), (64, 16))
ANGLES = (0, 90, 180, 45, 135, 113, 157, 203, 67)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_sources(directory: Path) -> dict[str, str]:
    sources = {}
    for name, expected in SOURCE_HASHES.items():
        data = (directory / name).read_bytes()
        actual = sha256(data)
        if actual != expected:
            raise RuntimeError(f"{name}: SHA-256 {actual}, expected {expected}")
        sources[name] = data.decode("utf-8").replace("\r\n", "\n")
    return sources


def braced(source: str, marker: str, *, declaration: bool = False) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    nesting, end = 1, opening + 1
    while nesting:
        nesting += (source[end] == "{") - (source[end] == "}")
        end += 1
    if declaration:
        end = source.index(";", end) + 1
    return source[start:end]


def enum_declaration(source: str, first: str) -> str:
    start = source.rindex("enum {", 0, source.index(first + ","))
    return braced(source[start:], "enum {", declaration=True)


def macro(source: str, name: str) -> str:
    lines = source.splitlines()
    start = next(i for i, line in enumerate(lines)
                 if re.match(r"#define " + re.escape(name) + r"(?:\(|\s)", line))
    end = start
    while lines[end].endswith("\\"):
        end += 1
    return "\n".join(lines[start:end + 1])


C_TYPES = r"""
/* Header-free ABI declarations for MoonBit's bundled Windows x64 TinyCC. */
typedef unsigned char uint8_t;
typedef signed short int16_t;
typedef unsigned short uint16_t;
typedef unsigned long long uintptr_t;
typedef unsigned long long size_t;
typedef signed long long ptrdiff_t;
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern int abs(int);
extern void exit(int);
extern void *memcpy(void *, const void *, size_t);
#define DECLARE_ALIGNED(n, type, var) type var
static void oracle_assert_fail(int line) {
  printf("original C assertion failed at extracted line %d\n", line);
  exit(10);
}
#define assert(condition) ((condition) ? (void)0 : oracle_assert_fail(__LINE__))
static int clip_low, clip_high, upsample_calls, corner_calls, filter_calls;
static int filter_strength_mask, active_tx_size;
static int filter_strength_calls[4];
"""

C_DISPATCH = r"""
/* Dispatch wrappers preserve the original scalar implementations and only
   record which edge paths actually execute. */
typedef void (*intra_high_pred_fn)(uint16_t *, ptrdiff_t,
                                  const uint16_t *, const uint16_t *, int);
static intra_high_pred_fn pred_high[INTRA_MODES][TX_SIZES_ALL];
static void oracle_v(uint16_t *dst, ptrdiff_t stride, const uint16_t *above,
                     const uint16_t *left, int bd) {
  highbd_v_predictor(dst, stride, tx_size_wide[active_tx_size],
                    tx_size_high[active_tx_size], above, left, bd);
}
static void oracle_h(uint16_t *dst, ptrdiff_t stride, const uint16_t *above,
                     const uint16_t *left, int bd) {
  highbd_h_predictor(dst, stride, tx_size_wide[active_tx_size],
                    tx_size_high[active_tx_size], above, left, bd);
}
static void highbd_filter_intra_predictor(uint16_t *dst, ptrdiff_t stride,
    TX_SIZE tx_size, const uint16_t *above, const uint16_t *left,
    FILTER_INTRA_MODE mode, int bd) {
  /* Directional-only harness: reaching this unrelated branch is an error. */
  exit(11);
}
#define av1_highbd_dr_prediction_z1 av1_highbd_dr_prediction_z1_c
#define av1_highbd_dr_prediction_z2 av1_highbd_dr_prediction_z2_c
#define av1_highbd_dr_prediction_z3 av1_highbd_dr_prediction_z3_c
"""

C_CLIP_COUNTER = r"""
static uint16_t oracle_clip_pixel_highbd(int value, int bd) {
  clip_low += value < 0;
  clip_high += value >= (1 << bd);
  return clip_pixel_highbd(value, bd);
}
#define clip_pixel_highbd oracle_clip_pixel_highbd
"""

C_EDGE_DISPATCH = r"""
#undef clip_pixel_highbd
static void oracle_filter_edge(uint16_t *p, int sz, int strength) {
  ++filter_strength_calls[strength];
  if (strength) {
    ++filter_calls;
    filter_strength_mask |= 1 << strength;
  }
  av1_highbd_filter_intra_edge_c(p, sz, strength);
}
static void oracle_upsample_edge(uint16_t *p, int sz, int bd) {
  ++upsample_calls;
  av1_highbd_upsample_intra_edge_c(p, sz, bd);
}
static void oracle_filter_corner(uint16_t *above, uint16_t *left) {
  ++corner_calls;
  highbd_filter_intra_edge_corner(above, left);
}
#define av1_highbd_filter_intra_edge oracle_filter_edge
#define av1_highbd_upsample_intra_edge oracle_upsample_edge
#define highbd_filter_intra_edge_corner oracle_filter_corner
"""

C_MAIN = r"""
int main(void) {
  uint16_t reference[130 * 130], output[64 * 64];
  int id, mode, delta, tx, bd, nt, nr, nl, nb, edge_filter, smooth, corner;
  assert(sizeof(uint16_t) == 2 && sizeof(int) == 4 && sizeof(void *) == 8);
  assert((-1 >> 1) == -1);
  for (int i = 0; i < TX_SIZES_ALL; ++i) {
    pred_high[V_PRED][i] = oracle_v;
    pred_high[H_PRED][i] = oracle_h;
  }
  while (scanf("%d %d %d %d %d %d %d %d %d %d %d %d", &id, &mode, &delta,
               &tx, &bd, &nt, &nr, &nl, &nb, &edge_filter, &smooth, &corner) == 12) {
    assert(tx >= 0 && tx < TX_SIZES_ALL && mode >= 1 && mode <= 8);
    assert(bd == 8 || bd == 10 || bd == 12);
    int w = tx_size_wide[tx], h = tx_size_high[tx], value;
    assert(nt >= 0 && nt <= w && nl >= 0 && nl <= h);
    assert(nr >= -1 && nr <= w && nb >= -1 && nb <= h);
    aom_memset16(reference, 0x6A6A, 130 * 130);
    aom_memset16(output, 0x6A6A, 64 * 64);
    reference[0] = corner;
    for (int i = 0; i < 2 * (w > h ? w : h); ++i) {
      if (scanf("%d", &value) != 1) return 12;
      reference[1 + i] = value;
    }
    for (int i = 0; i < 2 * (w > h ? w : h); ++i) {
      if (scanf("%d", &value) != 1) return 13;
      reference[(1 + i) * 130] = value;
    }
    active_tx_size = tx;
    clip_low = clip_high = upsample_calls = corner_calls = filter_calls = 0;
    filter_strength_mask = 0;
    for (int i = 0; i < 4; ++i) filter_strength_calls[i] = 0;
    highbd_build_directional_and_filter_intra_predictors(
        CONVERT_TO_BYTEPTR(reference + 131), 130, CONVERT_TO_BYTEPTR(output), 64,
        mode, mode_to_angle_map[mode] + 3 * delta, FILTER_INTRA_MODES, tx,
        !edge_filter, nt, nr, nl, nb, smooth, bd);
    printf("%d %d %d %d %d %d %d", id, upsample_calls, clip_low, clip_high,
           corner_calls, filter_calls, filter_strength_mask);
    for (int i = 0; i < 4; ++i) printf(" %d", filter_strength_calls[i]);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        assert(output[y * 64 + x] < (1 << bd));
        printf(" %d", output[y * 64 + x]);
      }
    }
    printf("\n");
  }
  return 0;
}
"""


def reference_source(sources: dict[str, str]) -> tuple[str, list[dict[str, object]]]:
    recon = sources["av1/common/reconintra.c"]
    parts = [recon[:recon.index("*/") + 2], C_TYPES]
    extracted = []

    def add(filename: str, name: str, text: str) -> None:
        source = sources[filename]
        start = source.index(text)
        extracted.append({"source": filename, "name": name,
                          "line": source[:start].count("\n") + 1,
                          "sha256": sha256(text.encode("utf-8"))})
        parts.append(text)

    def function(filename: str, marker: str) -> None:
        add(filename, marker.split("(")[0], braced(sources[filename], marker))

    def table(filename: str, marker: str) -> None:
        add(filename, marker.split("[")[0], braced(sources[filename], marker, declaration=True))

    for name in ("ROUND_POWER_OF_TWO", "CONVERT_TO_SHORTPTR", "CONVERT_TO_BYTEPTR", "UENUM1BYTE"):
        add("aom_ports/mem.h", name, macro(sources["aom_ports/mem.h"], name))
    for filename, first in (("aom_dsp/txfm_common.h", "TX_4X4"),
                            ("av1/common/enums.h", "DC_PRED"),
                            ("av1/common/enums.h", "FILTER_DC_PRED")):
        add(filename, first + " enum", enum_declaration(sources[filename], first))
    for name in ("MAX_TX_SIZE_LOG2", "MAX_TX_SIZE"):
        add("av1/common/enums.h", name, macro(sources["av1/common/enums.h"], name))
    add("av1/common/reconintra.c", "NEED_LEFT enum", braced(recon, "enum {", declaration=True))
    for name in ("INTRA_EDGE_FILT", "INTRA_EDGE_TAPS", "MAX_UPSAMPLE_SZ", "NUM_INTRA_NEIGHBOUR_PIXELS"):
        add("av1/common/reconintra.c", name, macro(recon, name))
    table("av1/common/reconintra.c", "static const uint8_t extend_modes[")
    table("av1/common/common_data.h", "static const int tx_size_wide[")
    table("av1/common/common_data.h", "static const int tx_size_high[")
    table("av1/common/blockd.h", "static const uint8_t mode_to_angle_map[")
    table("av1/common/reconintra.h", "static const int16_t dr_intra_derivative[")
    function("aom_mem/aom_mem.h", "static inline void *aom_memset16(")
    function("aom_dsp/aom_dsp_common.h", "static inline int clamp(")
    function("aom_dsp/aom_dsp_common.h", "static inline uint16_t clip_pixel_highbd(")
    for marker in ("static inline int av1_is_directional_mode(", "static inline int av1_get_dx(",
                   "static inline int av1_get_dy(", "static inline int av1_use_intra_edge_upsample("):
        function("av1/common/reconintra.h", marker)
    for marker in ("static inline void highbd_v_predictor(", "static inline void highbd_h_predictor("):
        function("aom_dsp/intrapred.c", marker)
    parts.append(C_DISPATCH)
    for marker in ("void av1_highbd_dr_prediction_z1_c(", "void av1_highbd_dr_prediction_z2_c(",
                   "void av1_highbd_dr_prediction_z3_c(", "static void highbd_dr_predictor(",
                   "static int intra_edge_filter_strength(", "void av1_highbd_filter_intra_edge_c(",
                   "static void highbd_filter_intra_edge_corner("):
        function("av1/common/reconintra.c", marker)
    parts.append(C_CLIP_COUNTER)
    function("av1/common/reconintra.c", "void av1_highbd_upsample_intra_edge_c(")
    parts.append(C_EDGE_DISPATCH)
    function("av1/common/reconintra.c", "static void highbd_build_directional_and_filter_intra_predictors(")
    parts.append(C_MAIN)
    return "\n\n".join(parts), extracted


def edge_inputs(case: dict[str, object]) -> tuple[list[int], list[int]]:
    maximum, seed = (1 << case["bit_depth"]) - 1, case["seed"]
    length = 2 * max(case["width"], case["height"])
    if case["variant"] == 1:
        above = [0 if (i + seed) % 4 < 2 else maximum for i in range(length)]
        left = [maximum if (i + seed + 1) % 4 < 2 else 0 for i in range(length)]
    else:
        above = [(seed * 37 + i * 29 + (i % 7) * i * 11) & maximum for i in range(length)]
        left = [(seed * 53 + i * 43 + (i % 5) * i * 17) & maximum for i in range(length)]
    return above, left


def make_cases() -> list[dict[str, object]]:
    cases = []
    offset = 0
    for depth_index, depth in enumerate((8, 10, 12)):
        for mode in range(1, 9):
            for delta in range(-3, 4):
                base_index = (depth_index * 8 + mode - 1) * 7 + delta + 3
                tx_size, seed = base_index % len(SHAPES), 1009 + base_index
                width, height = SHAPES[tx_size]
                angle = ANGLES[mode] + 3 * delta
                for variant in range(4):
                    n_top, n_left = width, height
                    n_tr = width if angle < 90 else -1
                    n_bl = height if angle > 180 else -1
                    availability = "full"
                    if variant == 2:
                        policy = base_index % 6
                        availability = ("missing_top", "missing_left", "missing_both",
                                        "partial_top", "partial_left", "missing_extensions")[policy]
                        if policy in (0, 2, 3):
                            n_top = 0 if policy in (0, 2) else max(1, width - 2)
                            n_tr = 0 if angle < 90 else -1
                        if policy in (1, 2, 4):
                            n_left = 0 if policy in (1, 2) else max(1, height - 2)
                            n_bl = 0 if angle > 180 else -1
                        if policy == 5:
                            n_tr, n_bl = (0 if angle < 90 else -1), (0 if angle > 180 else -1)
                    maximum = (1 << depth) - 1
                    corner = (maximum if seed % 2 else 0) if variant == 1 else (seed * 97 + 19) & maximum
                    cases.append({"index": len(cases), "base_index": base_index,
                        "variant": variant, "mode": mode, "angle_delta": delta, "angle": angle,
                        "bit_depth": depth, "tx_size": tx_size, "width": width, "height": height,
                        "n_top": n_top, "n_left": n_left, "n_topright": n_tr, "n_bottomleft": n_bl,
                        "edge_filter": variant != 3, "neighbor_smooth": variant == 1 or (variant == 2 and base_index % 2 == 1),
                        "availability": availability, "seed": seed, "corner": corner,
                        "input_pattern": "extreme_pairs" if variant == 1 else "modular",
                        "offset_bytes": offset, "sample_count": width * height})
                    offset += width * height * 2
    return cases


def run_reference(cc: str, source: str, cases: list[dict[str, object]]) -> tuple[bytes, dict[str, object]]:
    compiler = Path(shutil.which(cc) or cc).resolve()
    payload = []
    for case in cases:
        fields = ("index", "mode", "angle_delta", "tx_size", "bit_depth", "n_top", "n_topright",
                  "n_left", "n_bottomleft", "edge_filter", "neighbor_smooth", "corner")
        payload.append(" ".join(str(int(case[field])) for field in fields))
        payload.extend(" ".join(map(str, edge)) for edge in edge_inputs(case))
    with tempfile.TemporaryDirectory(prefix="pixelforge-directional-") as directory:
        temporary = Path(directory)
        c_file, executable = temporary / "directional_reference.c", temporary / "directional_reference.exe"
        c_file.write_text(source, encoding="utf-8", newline="\n")
        command = [str(compiler)]
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command += ["-B", str(moon_root)]
        command += [str(c_file), "-o", str(executable)]
        subprocess.run(command, check=True, capture_output=True, text=True)
        result = subprocess.run([str(executable)], input="\n".join(payload) + "\n",
                                check=True, capture_output=True, text=True)
        display_command = [arg.replace(str(temporary), "<temporary>") for arg in command]
    lines = result.stdout.splitlines()
    if len(lines) != len(cases):
        raise RuntimeError(f"oracle returned {len(lines)} cases, expected {len(cases)}")
    binary = bytearray()
    for case, line in zip(cases, lines):
        values = list(map(int, line.split()))
        if values[0] != case["index"] or len(values) != case["sample_count"] + 11:
            raise RuntimeError(f"case {case['index']}: invalid oracle output extent/order")
        case["oracle_paths"] = dict(zip(("upsample_calls", "upsample_clip_low", "upsample_clip_high",
                                         "corner_filter_calls", "edge_filter_calls", "filter_strength_mask"), values[1:7]))
        case["oracle_paths"]["filter_strength_calls"] = values[7:11]
        pixels = values[11:]
        if any(pixel < 0 or pixel >= 1 << case["bit_depth"] for pixel in pixels):
            raise RuntimeError(f"case {case['index']}: pixel outside native bit depth")
        packed = struct.pack("<" + "H" * len(pixels), *pixels)
        case["output_sha256"] = sha256(packed)
        case["output_crc32"] = zlib.crc32(packed)
        binary.extend(packed)
    version = subprocess.run([str(compiler), "-v"], capture_output=True, text=True, check=True)
    return bytes(binary), {"path": str(compiler), "sha256": sha256(compiler.read_bytes()),
                           "version": (version.stdout + version.stderr).strip(), "compile_command": display_command}


def coverage(cases: list[dict[str, object]], binary: bytes) -> dict[str, object]:
    assert len(cases) == 672
    assert len({(c["mode"], c["angle_delta"], c["bit_depth"]) for c in cases}) == 168
    assert len({c["tx_size"] for c in cases}) == 19
    paths = {key: sum(case["oracle_paths"][key] for case in cases)
             for key in ("upsample_calls", "upsample_clip_low", "upsample_clip_high", "corner_filter_calls", "edge_filter_calls")}
    if any(paths[key] == 0 for key in paths):
        raise RuntimeError(f"intended original C edge paths were not exercised: {paths}")
    changed = 0
    for offset in range(0, len(cases), 4):
        a, b = cases[offset], cases[offset + 3]
        size = a["sample_count"] * 2
        changed += binary[a["offset_bytes"]:a["offset_bytes"] + size] != binary[b["offset_bytes"]:b["offset_bytes"] + size]
    if not changed:
        raise RuntimeError("filter-on/off pairs produced no observable pixel differences")
    return {"case_count": len(cases), "mode_delta_depth_combinations": 168,
            "legal_tx_shapes": [list(shape) for shape in SHAPES],
            "total_native_samples": len(binary) // 2, "actual_original_c_paths": paths,
            "actual_filter_strength_calls": [sum(c["oracle_paths"]["filter_strength_calls"][i] for c in cases) for i in range(4)],
            "filter_on_off_pairs_with_different_pixels": changed,
            "availability_counts": {name: sum(c["availability"] == name for c in cases)
                                    for name in sorted({c["availability"] for c in cases})}}


def manifest_text(manifest: dict[str, object]) -> str:
    metadata = {key: value for key, value in manifest.items() if key != "cases"}
    text = json.dumps(metadata, ensure_ascii=False, indent=2)[:-2]
    return text + ',\n  "cases": [\n' + ",\n".join(
        "    " + json.dumps(case, separators=(",", ":")) for case in manifest["cases"]) + "\n  ]\n}\n"


MOON_HELPER = """///|
// Inputs only; all expected hashes and small complete arrays come from libaom C.
fn av1_directional_reference_case(
  index : Int,
  mode : Int,
  delta : Int,
  width : Int,
  height : Int,
  depth : Int,
  variant : Int,
  seed : Int,
  corner : Int,
  n_top : Int,
  n_left : Int,
  n_topright : Int,
  n_bottomleft : Int,
  edge_filter : Bool,
  neighbor_smooth : Bool,
  expected_crc : UInt,
  expected_pixels : Array[Int],
) -> Unit raise {
  let maximum = (1 << depth) - 1
  let length = 2 * (if width > height { width } else { height })
  let above : Array[Int] = []
  let left : Array[Int] = []
  for i in 0..<length {
    if variant == 1 {
      above.push(if (i + seed) % 4 < 2 { 0 } else { maximum })
      left.push(if (i + seed + 1) % 4 < 2 { maximum } else { 0 })
    } else {
      above.push((seed * 37 + i * 29 + (i % 7) * i * 11) & maximum)
      left.push((seed * 53 + i * 43 + (i % 5) * i * 17) & maximum)
    }
  }
  let actual = av1_directional_predict(
    mode, delta, width, height, above, left, corner, depth,
    n_top, n_left, n_topright, n_bottomleft, edge_filter, neighbor_smooth,
  ).unwrap()
  assert_eq((index, actual.length()), (index, width * height))
  let packed : Array[Byte] = []
  let mut in_range = true
  for pixel in actual {
    if pixel < 0 || pixel > maximum { in_range = false }
    packed.push((pixel & 255).to_byte())
    packed.push((pixel >> 8).to_byte())
  }
  assert_eq((index, in_range), (index, true))
  assert_eq((index, crc32(packed, 0, packed.length())), (index, expected_crc))
  if expected_pixels.length() > 0 {
    assert_eq((index, actual), (index, expected_pixels))
  }
}
"""


def render_test(cases: list[dict[str, object]], binary: bytes) -> str:
    text = ["// Generated by scripts/generate-av1-directional-reference.py.\n",
            f"// Original scalar libaom revision: {REVISION}\n",
            f"// Complete native output SHA-256: {sha256(binary)}\n",
            "// 672 cases; CRC-32 covers every native uint16-LE sample.\n",
            "// Every TX4x4 case additionally compares its complete 16 pixels.\n",
            "// Availability derivation from coding context is outside this pure-kernel suite.\n\n",
            MOON_HELPER]
    fields = ("index", "mode", "angle_delta", "width", "height", "bit_depth", "variant", "seed",
              "corner", "n_top", "n_left", "n_topright", "n_bottomleft", "edge_filter", "neighbor_smooth")
    for depth in (8, 10, 12):
        for mode in range(1, 9):
            text.append(f'\n///|\ntest "directional original libaom {depth}-bit mode{mode} all deltas and edges" {{\n')
            for case in cases:
                if case["bit_depth"] != depth or case["mode"] != mode:
                    continue
                arguments = [str(case[key]).lower() for key in fields]
                arguments.append(f"0x{case['output_crc32']:08x}U")
                start, size = case["offset_bytes"], case["sample_count"]
                expected = list(struct.unpack("<" + "H" * size, binary[start:start + size * 2])) if size <= 16 else []
                arguments.append(str(expected))
                text.append("  av1_directional_reference_case(" + ", ".join(arguments) + ")\n")
            text.append("}\n")
    return "".join(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True, help="local checkout matching all pinned source hashes")
    moon_tcc = Path.home() / ".moon/bin/internal/tcc.exe"
    parser.add_argument("--cc", default=str(moon_tcc) if moon_tcc.is_file() else "cc")
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-directional")
    parser.add_argument("--test", nargs="?", type=Path, const=ROOT / "_refs/av1_directional_predict_wbtest.mbt",
                        help="also generate a prospective white-box test under _refs (never run it)")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sources = load_sources(args.source_dir)
    source, extracted = reference_source(sources)
    cases = make_cases()
    binary, compiler = run_reference(args.cc, source, cases)
    result = {"schema": 1, "scope": "pure directional predictor and original C edge preparation; frame availability derivation is supplied as input",
        "libaom_revision": REVISION, "source_url": SOURCE_URL, "source_sha256": SOURCE_HASHES,
        "copyright": "Copyright (c) 2016, Alliance for Open Media. All rights reserved.",
        "licenses": ["https://www.aomedia.org/license/software", "https://www.aomedia.org/license/patent"],
        "extracted_unchanged": extracted, "extracted_c_sha256": sha256(source.encode("utf-8")),
        "shim_contract": "header-free x64 ABI, ref-plane packing, scalar dispatch, fail-only unused filter-intra stub and path counters; original prediction/filter/rounding/clip function bodies unchanged",
        "compiler": compiler, "generator_sha256": sha256(Path(__file__).read_bytes()),
        "input_contract": {"edge_length": "2*max(width,height); above[0] and left[0] are the immediate neighboring samples; corner is separate",
            "count_contract": "n_top<=width, n_left<=height; extension>0 only with full primary edge; -1 means extension unneeded by angle",
            "ordinary_above": "(seed*37+i*29+(i%7)*i*11)&((1<<bit_depth)-1)",
            "ordinary_left": "(seed*53+i*43+(i%5)*i*17)&((1<<bit_depth)-1)",
            "extreme_above": "0 if (i+seed)%4<2 else maximum",
            "extreme_left": "maximum if (i+seed+1)%4<2 else 0",
            "variants": ["full edges, filter on, type0, modular", "full edges, filter on, type1, extreme_pairs",
                         "base_index%6 selects missing_top/missing_left/missing_both/partial_top/partial_left/missing_extensions; filter on; type=base_index%2",
                         "same as variant0 but edge filter disabled"]},
        "output_file": "output.bin", "output_format": "concatenated row-major unsigned16 little-endian at every bit depth",
        "output_sha256": sha256(binary), "output_bytes": len(binary), "coverage": coverage(cases, binary), "cases": cases}
    output_path, manifest_path = args.out / "output.bin", args.out / "manifest.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if args.check else None
    test_path = args.test
    if args.check and test_path is None and "prospective_test" in previous:
        test_path = Path(previous["prospective_test"])
    if test_path is not None:
        if not test_path.resolve().is_relative_to((ROOT / "_refs").resolve()):
            raise RuntimeError("directional white-box output must remain prospective under _refs")
        formatted = subprocess.run([args.moonfmt, "-"], input=render_test(cases, binary),
                                   text=True, encoding="utf-8", capture_output=True, check=True).stdout
        result["prospective_test"] = str(test_path)
        result["prospective_test_sha256"] = sha256(formatted.encode("utf-8"))
        result["white_box_contract"] = {"groups": 24, "case_count": len(cases),
            "native_crc32_cases": len(cases), "complete_pixel_cases": sum(c["sample_count"] <= 16 for c in cases),
            "native_crc32_format": "unsigned16 little-endian, zlib.crc32 matches private png.mbt crc32",
            "runtime_validation": "not run by this generator"}
    result["generation_command"] = [sys.executable, str(Path(__file__).resolve()),
        "--source-dir", str(args.source_dir.resolve()), "--cc", compiler["path"], "--out", str(args.out.resolve())]
    if test_path is not None:
        formatter = Path(shutil.which(args.moonfmt) or args.moonfmt).resolve()
        result["generation_command"] += ["--test", str(test_path.resolve()), "--moonfmt", str(formatter)]
    if args.check:
        stable_keys = ("schema", "libaom_revision", "source_sha256", "extracted_unchanged", "extracted_c_sha256",
                       "generator_sha256", "input_contract", "output_sha256", "output_bytes", "coverage", "cases")
        if output_path.read_bytes() != binary or any(previous[key] != result[key] for key in stable_keys):
            raise RuntimeError("directional reference binary or deterministic metadata differs; regenerate without --check")
        if test_path is not None and (test_path.read_text(encoding="utf-8") != formatted or
                                     previous.get("prospective_test_sha256") != result["prospective_test_sha256"]):
            raise RuntimeError("prospective directional white-box test differs from the original C goldens")
        print(f"verified {len(cases)} cases / {len(binary) // 2} exact native pixels")
    else:
        args.out.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(binary)
        if test_path is not None:
            test_path.parent.mkdir(parents=True, exist_ok=True)
            test_path.write_text(formatted, encoding="utf-8", newline="\n")
        manifest_path.write_text(manifest_text(result), encoding="utf-8", newline="\n")
        print(f"wrote {len(cases)} cases / {len(binary) // 2} exact native pixels to {args.out}")
    print(json.dumps(result["coverage"], separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
