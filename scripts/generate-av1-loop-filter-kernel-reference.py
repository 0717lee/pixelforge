#!/usr/bin/env python3
"""Generate scalar AV1 deblock goldens with the unmodified pinned AOM C file.

Generation requires Python, a C compiler, moonfmt and the pinned AOM checkout.
--check requires only Python: it checks deterministic inputs, canonical binary
hashes, branch coverage and exact generated-test bytes without compiling C/Moon.
The shim supplies headers and dispatch only; it never calculates filtered pixels.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
SOURCE_HASHES = {
    "aom_dsp/loopfilter.c": "bb9d6de53a4ad448af145892fc59dd72c767224d02532409305505d9d330fdb5",
    "aom_dsp/aom_dsp_common.h": "438b026ee7fc0484643ac7ca73246290a77c1384862264df146f669893ee98d9",
    "aom_ports/mem.h": "6d3c074d3e295e64c634101a0f95341a69331d3c880b8a3fce7095355f37cb1c",
    "av1/common/av1_loopfilter.c": "385077f5637f33947d4a8ef3dca02931cbce4d4764a19124be4860d3494d71bd",
}
WIDTHS = (4, 6, 8, 14)
DEPTHS = (8, 10, 12)
RECORD = struct.Struct("<4B28H")  # width, level, sharpness, depth, input14, output14
THRESHOLD = struct.Struct("<5B")  # level, sharpness, limit, blimit, hev


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def braced(source: str, marker: str) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    nesting, end = 1, opening + 1
    while nesting:
        nesting += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def pinned_sources(directory: Path) -> dict[str, str]:
    revision = subprocess.run(["git", "-C", str(directory), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    if revision != REVISION:
        raise RuntimeError(f"AOM checkout revision {revision}, expected {REVISION}")
    sources = {}
    for name, digest in SOURCE_HASHES.items():
        data = subprocess.run(["git", "-C", str(directory), "show", f"{REVISION}:{name}"],
                              capture_output=True, check=True).stdout
        if sha(data) != digest:
            raise RuntimeError(f"pinned AOM source changed: {name}")
        if (directory / name).read_bytes().replace(b"\r\n", b"\n") != data:
            raise RuntimeError(f"AOM working source differs from its pinned original: {name}")
        sources[name] = data.decode("utf-8")
    return sources


@dataclass(frozen=True)
class Case:
    name: str
    width: int
    level: int
    sharpness: int
    depth: int
    samples: tuple[int, ...]


def cases() -> list[Case]:
    result = []
    for depth in DEPTHS:
        scale = 1 << (depth - 8)
        maximum = (1 << depth) - 1
        for width in WIDTHS:
            def add(name, values, level=32, sharpness=0, native=False):
                pixels = tuple(values if native else (v * scale for v in values))
                if len(pixels) != 14 or any(v < 0 or v > maximum for v in pixels):
                    raise RuntimeError(f"invalid input {name}")
                result.append(Case(f"{depth}bit_w{width}_{name}", width, level,
                                   sharpness, depth, pixels))

            add("constant", [128] * 14)
            add("step", [100] * 7 + [108] * 7)
            add("reverse_step", [108] * 7 + [100] * 7)
            add("level_zero_bypass", [100] * 7 + [101] * 7, level=0)
            add("blimit_reject", [0] * 7 + [255] * 7, level=63)
            add("hev_off_not_flat", [100, 100, 100, 103, 102, 101, 100,
                                       108, 109, 110, 111, 108, 108, 108])
            add("hev_on", [104] * 6 + [100, 108] + [112] * 6)
            add("flat_at_limit", [101] * 6 + [100, 108] + [109] * 6)
            add("flat_with_hev", [101] * 6 + [100, 108] + [109] * 6, level=15)
            add("flat_beyond_limit", [102] * 6 + [100, 108] + [110] * 6)
            add("flat2_false", [110, 110, 110, 100, 100, 100, 100,
                                 108, 108, 108, 108, 118, 118, 118])
            add("flat_false_flat2_true", [100, 100, 100, 103, 100, 100, 100,
                                          108, 108, 108, 111, 108, 108, 108])
            # The narrow public entry ignores outer slots. The wider entry must
            # retain its own mask even when falling back to the four-tap kernel.
            radius = {4: 2, 6: 3, 8: 4, 14: 7}[width]
            values = [100] * 7 + [108] * 7
            for i in range(14):
                if i < 7 - radius or i >= 7 + radius:
                    values[i] = 0 if i % 2 else 255
            add("unused_slots_extreme", values)
            for side in ("p", "q"):
                for distance in (1, 2, 3):
                    values = [100] * 7 + [108] * 7
                    values[6 - distance if side == "p" else 7 + distance] = 160
                    add(f"{side}{distance}_wide_mask_reject", values)
            for difference in (32, 33):
                values = [100] * 7 + [108] * 7
                values[5] = 100 + difference
                add(f"limit_boundary_{difference}", values)
            for q1 in (141, 142):
                add(f"blimit_boundary_{q1}", [100] * 7 + [140] + [q1] * 6)
            for sharpness in (4, 5):
                add(f"sharpness_change_{sharpness}", [105] * 6 + [100, 108] + [113] * 6,
                    sharpness=sharpness)
            # Equality versus strictly-greater threshold, including sharpness
            # change points. Threshold expectations themselves come from C.
            for sharpness in (0, 1, 4, 5, 7):
                for level in (1, 15, 16, 31, 32, 63):
                    add(f"threshold_step_l{level}_s{sharpness}",
                        [100] * 7 + [104] * 7, level, sharpness)
            # Native-unit steps exercise all signed rounding residues, including
            # highbd low bits that cannot be tested by scaled 8-bit samples.
            for delta in range(-12, 13):
                midpoint = 128 * scale
                add(f"round_native_{delta:+d}", [midpoint] * 7 +
                    [midpoint + delta] * 7, level=63, native=True)
            for base in (0, maximum):
                for delta in (1, 4, 7, 16, 48):
                    other = base + delta if base == 0 else base - delta
                    add(f"bound_{base}_{delta}", [base] * 7 + [other] * 7,
                        level=63, native=True)
            # Opposing slopes reject at the cross-edge mask even at level63.
            add("opposing_slopes_reject_positive", [0] * 6 + [63, 139] + [202] * 6, 63)
            add("opposing_slopes_reject_negative", [202] * 6 + [139, 63] + [0] * 6, 63)
            output_low = [0] * 8 + [63 * scale] * 6
            outer_positive = [163 * scale] * 6 + [100 * scale, 56 * scale] + [0] * 6
            for name, values in (("output_clip_low", output_low),
                                 ("output_clip_high", [maximum - v for v in output_low]),
                                 ("outer_clip_positive", outer_positive),
                                 ("outer_clip_negative", [maximum - v for v in outer_positive])):
                add(name, values, level=63, native=True)
            for name, left, right in (("post_add_clamp", 0, (128 * scale) // 3),
                                      ("inner_clamp", 0, 64 * scale),
                                      ("round_fallback_positive", 0, 4),
                                      ("round_fallback_negative", 4, 0)):
                values = [left] * 7 + [right] * 7
                values[4] = left + scale + 1
                add(name, values, level=63, native=True)
            # Input-only fixed LCG, local walks and almost-flat edges. No Python
            # implementation of filtering contributes to expected samples.
            seed = 0xA01F0000 + depth * 256 + width
            for index in range(48):
                values = []
                for slot in range(14):
                    seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF
                    span = (3, 11, 31, 127)[index % 4] * scale
                    edge = (index % 7 - 3) * scale if slot >= 7 else 0
                    values.append(max(0, min(maximum, 128 * scale + edge +
                                           seed % (2 * span + 1) - span)))
                add(f"lcg_{index:02d}", values,
                    (1, 15, 16, 31, 32, 63)[index % 6], index % 8, native=True)
    return result


C_HEADER = r"""
typedef unsigned char uint8_t;
typedef signed char int8_t;
typedef unsigned short uint16_t;
typedef signed short int16_t;
extern int abs(int);
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern void *memset(void *, int, unsigned long long);
#define CONFIG_AV1_HIGHBITDEPTH 1
#define MAX_LOOP_FILTER 63
#define SIMD_WIDTH 16
typedef struct {
  uint8_t lim[SIMD_WIDTH], mblim[SIMD_WIDTH], hev_thr[SIMD_WIDTH];
} loop_filter_thresh;
typedef struct { loop_filter_thresh lfthr[64]; } loop_filter_info_n;
"""


C_MAIN = r"""
static void dispatch8(uint8_t *h, uint8_t *v, int width,
                      const uint8_t *blimit, const uint8_t *limit,
                      const uint8_t *hev) {
#define RUN8(W) case W: aom_lpf_horizontal_##W##_c(h, 4, blimit, limit, hev); \
                        aom_lpf_vertical_##W##_c(v, 14, blimit, limit, hev); break
  switch (width) { RUN8(4); RUN8(6); RUN8(8); RUN8(14); }
#undef RUN8
}
static void dispatch16(uint16_t *h, uint16_t *v, int width, int depth,
                       const uint8_t *blimit, const uint8_t *limit,
                       const uint8_t *hev) {
#define RUN16(W) case W: aom_highbd_lpf_horizontal_##W##_c(h, 4, blimit, limit, hev, depth); \
                         aom_highbd_lpf_vertical_##W##_c(v, 14, blimit, limit, hev, depth); break
  switch (width) { RUN16(4); RUN16(6); RUN16(8); RUN16(14); }
#undef RUN16
}
int main(void) {
  int width, level, sharpness, depth, i, lane;
  loop_filter_info_n thresholds;
  if (sizeof(int) != 4 || sizeof(uint16_t) != 2 || sizeof(void *) != 8) return 1;
  for (sharpness = 0; sharpness < 8; ++sharpness) {
    reference_thresholds(&thresholds, sharpness);
    for (level = 0; level < 64; ++level)
      printf("T %d %d %d %d %d\n", level, sharpness,
             thresholds.lfthr[level].lim[0], thresholds.lfthr[level].mblim[0], thresholds.lfthr[level].hev_thr[0]);
  }
  while (scanf("%d %d %d %d", &width, &level, &sharpness, &depth) == 4) {
    uint16_t x[14], h[56], v[56];
    uint8_t h8[56], v8[56], limit, blimit, hev_threshold;
    int mask, hev, flat = -1, flat2 = -1, value;
    if (level < 0 || level > 63 || sharpness < 0 || sharpness > 7 ||
        (depth != 8 && depth != 10 && depth != 12)) return 2;
    reference_thresholds(&thresholds, sharpness);
    limit = thresholds.lfthr[level].lim[0];
    blimit = thresholds.lfthr[level].mblim[0];
    hev_threshold = thresholds.lfthr[level].hev_thr[0];
    for (i = 0; i < 14; ++i) {
      if (scanf("%d", &value) != 1 || value < 0 || value >= (1 << depth)) return 3;
      x[i] = value;
      for (lane = 0; lane < 4; ++lane) {
        h[i * 4 + lane] = v[lane * 14 + i] = value;
        h8[i * 4 + lane] = v8[lane * 14 + i] = value;
      }
    }
    if (width == 4) {
      mask = highbd_filter_mask2(limit, blimit, x[5], x[6], x[7], x[8], depth) != 0;
    } else if (width == 6) {
      mask = highbd_filter_mask3_chroma(limit, blimit, x[4], x[5], x[6], x[7], x[8], x[9], depth) != 0;
      flat = highbd_flat_mask3_chroma(1, x[4], x[5], x[6], x[7], x[8], x[9], depth) != 0;
    } else if (width == 8 || width == 14) {
      mask = highbd_filter_mask(limit, blimit, x[3], x[4], x[5], x[6], x[7], x[8], x[9], x[10], depth) != 0;
      flat = highbd_flat_mask4(1, x[3], x[4], x[5], x[6], x[7], x[8], x[9], x[10], depth) != 0;
      if (width == 14)
        flat2 = highbd_flat_mask4(1, x[0], x[1], x[2], x[6], x[7], x[11], x[12], x[13], depth) != 0;
    } else return 4;
    hev = highbd_hev_mask(hev_threshold, x[5], x[6], x[7], x[8], depth) != 0;
    /* Level0 bypass belongs to edge selection, so don't invoke a scalar kernel. */
    if (level) {
      dispatch16(h + 28, v + 7, width, depth, &blimit, &limit, &hev_threshold);
      if (depth == 8) dispatch8(h8 + 28, v8 + 7, width, &blimit, &limit, &hev_threshold);
    }
    for (i = 0; i < 14; ++i) {
      for (lane = 0; lane < 4; ++lane) {
        if (h[i * 4 + lane] != v[lane * 14 + i] || h[i * 4 + lane] != h[i * 4]) return 5;
        if (depth == 8 && (h8[i * 4 + lane] != h[i * 4] || v8[lane * 14 + i] != h[i * 4])) return 6;
      }
    }
    printf("K %d %d %d %d %d %d %d", limit, blimit, hev_threshold, mask, hev, flat, flat2);
    for (i = 0; i < 14; ++i) printf(" %d", h[i * 4]);
    printf("\n");
  }
  return 0;
}
"""


def run_oracle(args, inputs):
    sources = pinned_sources(args.aom_source)
    clamp = braced(sources["aom_dsp/aom_dsp_common.h"], "static inline int clamp(")
    macro = next(line for line in sources["aom_ports/mem.h"].splitlines()
                 if line.startswith("#define ROUND_POWER_OF_TWO(value, n)"))
    sharpness = braced(sources["av1/common/av1_loopfilter.c"], "static void update_sharpness(")
    initialization = braced(sources["av1/common/av1_loopfilter.c"], "void av1_loop_filter_init(")
    hev_loop = initialization[initialization.index("  for (lvl ="):initialization.rindex("}")]
    threshold_init = "static void reference_thresholds(loop_filter_info_n *lfi, int sharpness) {\n  int lvl;\n  update_sharpness(lfi, sharpness);\n" + hev_loop + "}\n"
    with tempfile.TemporaryDirectory(prefix="pixelforge-loop-filter-") as temporary:
        build = Path(temporary)
        for name in ("stdlib.h", "config/aom_config.h", "config/aom_dsp_rtcd.h",
                     "aom_dsp/aom_dsp_common.h", "aom_ports/mem.h"):
            path = build / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("/* Types and pinned utilities supplied by harness. */\n")
        # A byte-identical copy avoids C string/path encoding ambiguity on Windows.
        original = sources["aom_dsp/loopfilter.c"].encode()
        (build / "loopfilter-original.c").write_bytes(original)
        source = C_HEADER + "\n" + clamp + "\n" + macro + '\n#include "loopfilter-original.c"\n' + sharpness + "\n" + threshold_init + C_MAIN
        (build / "reference.c").write_text(source, encoding="utf-8", newline="\n")
        executable = build / "reference.exe"
        command = [args.cc]
        compiler = Path(args.cc).resolve()
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command.extend(["-B", str(moon_root)])
        command.extend(["-I", str(build), str(build / "reference.c"), "-o", str(executable)])
        print("Compiling unmodified original C:", subprocess.list2cmdline(command))
        subprocess.run(command, check=True)
        payload = "".join(f"{c.width} {c.level} {c.sharpness} {c.depth} " +
                          " ".join(map(str, c.samples)) + "\n" for c in inputs)
        completed = subprocess.run([str(executable)], input=payload,
                                   capture_output=True, text=True, check=True)
    threshold_rows, output_rows = [], []
    for line in completed.stdout.splitlines():
        tag, *words = line.split()
        values = list(map(int, words))
        if tag == "T" and len(values) == 5:
            threshold_rows.append(values)
        elif tag == "K" and len(values) == 21:
            output_rows.append(values)
        else:
            raise RuntimeError(f"invalid original-C output: {line}")
    if len(threshold_rows) != 512 or len(output_rows) != len(inputs):
        raise RuntimeError("original-C output count mismatch")
    return threshold_rows, output_rows, {
        "translation_unit_sha256": sha(source.encode()),
        "command_template": "<cc> [-B <moon-root>] -I <temporary> <temporary>/reference.c -o <temporary>/reference.exe",
        "compiler": str(Path(args.cc).resolve()),
        "source_copy_sha256": sha(original),
    }


def branch_name(case, proof):
    mask, hev, flat, flat2 = proof
    if case.level == 0:
        return "level_zero"
    if not mask:
        return "mask_reject"
    if case.width == 14 and flat and flat2:
        return "filter14"
    if case.width in (8, 14) and flat:
        return "filter8"
    if case.width == 6 and flat:
        return "filter6"
    return "filter4_hev" if hev else "filter4_no_hev"


def hex_array(data: bytes) -> str:
    return "[\n" + "\n".join(f'    "{data[i:i + 60].hex()}",' for i in range(0, len(data), 60)) + "\n  ]"


def generated_test(binary: bytes, thresholds: bytes) -> str:
    lines = ["""///|
/// Generated from the canonical binary corpus by
/// scripts/generate-av1-loop-filter-kernel-reference.py. Expected pixels are produced
/// by unmodified pinned AOM C horizontal/vertical scalar entry points.
fn av1_loop_filter_reference_bytes(rows : Array[String]) -> Array[Int] {
  let result : Array[Int] = []
  for row in rows {
    let chars = row.to_array()
    for i in 0..<(chars.length() / 2) {
      let hi = chars[i * 2].to_int()
      let lo = chars[i * 2 + 1].to_int()
      let high = if hi >= 97 { hi - 87 } else { hi - 48 }
      let low = if lo >= 97 { lo - 87 } else { lo - 48 }
      result.push((high << 4) | low)
    }
  }
  result
}

///|
fn av1_loop_filter_reference_samples(data : Array[Int], start : Int) -> Array[Int] {
  Array::makei(14, i => data[start + i * 2] | (data[start + i * 2 + 1] << 8))
}
"""]
    for depth in DEPTHS:
        for width in WIDTHS:
            group = b"".join(binary[i:i + RECORD.size] for i in range(0, len(binary), RECORD.size)
                             if binary[i] == width and binary[i + 3] == depth)
            lines.append(f'''///|
test "original AOM loop filter {depth}bit width{width} complete corpus" {{
  let data = av1_loop_filter_reference_bytes({hex_array(group)})
  assert_eq(data.length() % 60, 0)
  for index in 0..<(data.length() / 60) {{
    let start = index * 60
    let input = av1_loop_filter_reference_samples(data, start + 4)
    let saved = input.copy()
    let expected = av1_loop_filter_reference_samples(data, start + 32)
    let actual = av1_loop_filter_edge(
      input, data[start], data[start + 1], data[start + 2], data[start + 3],
    ).unwrap()
    assert_eq((index, actual), (index, expected))
    assert_eq(input, saved)
  }}
}}
''')
    lines.append(f'''///|
test "original AOM loop filter all512 level sharpness thresholds" {{
  let data = av1_loop_filter_reference_bytes({hex_array(thresholds)})
  assert_eq(data.length(), 512 * 5)
  for index in 0..<512 {{
    let start = index * 5
    assert_eq(
      av1_loop_filter_thresholds(data[start], data[start + 1]),
      Some((data[start + 2], data[start + 3], data[start + 4])),
    )
  }}
}}
''')
    lines.append('''///|
test "loop filter scalar input validation" {
  let samples = Array::make(14, 128)
  for width in [0, 5, 7, 16] {
    assert_eq(av1_loop_filter_edge(samples, width, 32, 0, 8), None)
  }
  for depth in [0, 7, 9, 11, 13, 16] {
    assert_eq(av1_loop_filter_edge(samples, 4, 32, 0, depth), None)
  }
  for level in [-1, 64] {
    assert_eq(av1_loop_filter_edge(samples, 4, level, 0, 8), None)
    assert_eq(av1_loop_filter_thresholds(level, 0), None)
  }
  for sharpness in [-1, 8] {
    assert_eq(av1_loop_filter_edge(samples, 4, 32, sharpness, 8), None)
    assert_eq(av1_loop_filter_thresholds(32, sharpness), None)
  }
  for count in [0, 13, 15] {
    assert_eq(av1_loop_filter_edge(Array::make(count, 128), 4, 32, 0, 8), None)
  }
  for depth in [8, 10, 12] {
    for value in [-1, 1 << depth] {
      let invalid = samples.copy()
      invalid[6] = value
      assert_eq(av1_loop_filter_edge(invalid, 4, 32, 0, depth), None)
    }
  }
}
''')
    return "\n".join(lines)


def validate(inputs, binary, thresholds, records):
    if len(binary) != len(inputs) * RECORD.size or len(records) != len(inputs):
        raise RuntimeError("kernel corpus record count mismatch")
    if len(thresholds) != 512 * THRESHOLD.size:
        raise RuntimeError("threshold corpus record count mismatch")
    for i, (level, sharpness, limit, blimit, hev) in enumerate(THRESHOLD.iter_unpack(thresholds)):
        if (level, sharpness) != (i % 64, i // 64) or hev != level >> 4:
            raise RuntimeError("threshold order or HEV mismatch")
    coverage, changed, indexed = {}, {}, {}
    for index, (case, unpacked, record) in enumerate(zip(inputs, RECORD.iter_unpack(binary), records)):
        if unpacked[:4] != (case.width, case.level, case.sharpness, case.depth) or unpacked[4:18] != case.samples:
            raise RuntimeError(f"deterministic input differs: {case.name}")
        if record["name"] != case.name or record["offset"] != index * RECORD.size:
            raise RuntimeError("manifest record order mismatch")
        proof = record["mask_hev_flat_flat2"]
        branch = branch_name(case, proof)
        if record["branch"] != branch:
            raise RuntimeError(f"branch metadata mismatch: {case.name}")
        output = unpacked[18:]
        indexed[case.name] = (case, record, output)
        if any(v < 0 or v >= 1 << case.depth for v in output):
            raise RuntimeError(f"sample out of range: {case.name}")
        if (branch in ("level_zero", "mask_reject")) and output != case.samples:
            raise RuntimeError(f"non-filtering branch altered samples: {case.name}")
        first, last = {4: (5, 9), 6: (5, 9), 8: (4, 10), 14: (1, 13)}[case.width]
        if output[:first] != case.samples[:first] or output[last:] != case.samples[last:]:
            raise RuntimeError(f"kernel changed a read-only/unused tap: {case.name}")
        key = f"{case.depth}bit_width{case.width}"
        coverage.setdefault(key, Counter())[branch] += 1
        if output != case.samples:
            changed.setdefault(key, Counter())[branch] += 1
    for depth in DEPTHS:
        for width in WIDTHS:
            key = f"{depth}bit_width{width}"
            required = {"level_zero", "mask_reject", "filter4_hev", "filter4_no_hev"}
            if width in (6, 8, 14):
                required.add(f"filter{8 if width == 14 else width}")
            if width == 14:
                required.add("filter14")
            if not required.issubset(coverage[key]):
                raise RuntimeError(f"missing original-C branch proof: {key} {required - coverage[key].keys()}")
            active = required - {"level_zero", "mask_reject"}
            if not active.issubset(changed[key]):
                raise RuntimeError(f"branch lacks observable filtering: {key}")
            prefix = f"{depth}bit_w{width}_"
            base = indexed[prefix + "step"][2]
            perturbed = indexed[prefix + "unused_slots_extreme"][2]
            radius = {4: 2, 6: 3, 8: 4, 14: 7}[width]
            if base[7 - radius:7 + radius] != perturbed[7 - radius:7 + radius]:
                raise RuntimeError(f"unused-slot perturbation changed used taps: {key}")
            for distance in (2, 3):
                narrow = indexed[f"{depth}bit_w4_p{distance}_wide_mask_reject"][1]
                wide = indexed[f"{depth}bit_w8_p{distance}_wide_mask_reject"][1]
                if narrow["mask_hev_flat_flat2"][0] != 1 or wide["mask_hev_flat_flat2"][0] != 0:
                    raise RuntimeError("wide fallback failed to preserve its original mask")
            if width > 4:
                proof = indexed[prefix + "flat_with_hev"][1]["mask_hev_flat_flat2"]
                if proof[:3] != [1, 1, 1]:
                    raise RuntimeError("missing HEV-on strong-filter branch")
    return {key: dict(sorted(counts.items())) for key, counts in coverage.items()}


def check(args):
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    if manifest["generator_sha256"] != sha(Path(__file__).read_bytes()):
        raise RuntimeError("generator hash changed; regenerate to verify new construction")
    artifacts = {}
    for name, expected in manifest["artifact_sha256"].items():
        data = (args.out / name).read_bytes()
        if sha(data) != expected:
            raise RuntimeError(f"artifact hash mismatch: {name}")
        artifacts[name] = data
    coverage = validate(cases(), artifacts["samples.bin"], artifacts["thresholds.bin"], manifest["cases"])
    if coverage != manifest["branch_counts"]:
        raise RuntimeError("branch coverage changed")
    raw_test = generated_test(artifacts["samples.bin"], artifacts["thresholds.bin"])
    if sha(raw_test.encode()) != manifest["unformatted_test_sha256"]:
        raise RuntimeError("canonical test reconstruction mismatch")
    target = args.test or ROOT / manifest["test_file"]
    if sha(target.read_bytes()) != manifest["test_sha256"]:
        raise RuntimeError(f"generated test differs: {target}")
    print(f"Checked {len(cases())} canonical edge cases,512 thresholds, all hashes, branch proofs and WB; no C/Moon build")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    moon_tcc = Path.home() / ".moon/bin/internal/tcc.exe"
    parser.add_argument("--cc", default=shutil.which("cc") or str(moon_tcc))
    parser.add_argument("--aom-source", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-loop-filter-kernel")
    parser.add_argument("--test", type=Path)
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check(args)
        return
    inputs = cases()
    threshold_rows, output_rows, compile_info = run_oracle(args, inputs)
    thresholds = b"".join(THRESHOLD.pack(*row) for row in threshold_rows)
    binary, records = bytearray(), []
    for case, row in zip(inputs, output_rows):
        limit, blimit, hev_threshold, mask, hev, flat, flat2, *output = row
        proof = [mask, hev, flat, flat2]
        records.append({"name": case.name, "offset": len(binary),
                        "mask_hev_flat_flat2": proof, "branch": branch_name(case, proof)})
        binary.extend(RECORD.pack(case.width, case.level, case.sharpness, case.depth, *case.samples, *output))
        expected_threshold = threshold_rows[case.sharpness * 64 + case.level][2:]
        if [limit, blimit, hev_threshold] != expected_threshold:
            raise RuntimeError("oracle threshold dispatch mismatch")
    binary = bytes(binary)
    coverage = validate(inputs, binary, thresholds, records)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "samples.bin").write_bytes(binary)
    (args.out / "thresholds.bin").write_bytes(thresholds)
    raw_test = generated_test(binary, thresholds)
    formatted = subprocess.run([args.moonfmt, "-"], input=raw_test,
                               capture_output=True, text=True, check=True).stdout
    target = args.test or ROOT / "_refs/av1_loop_filter_wbtest.mbt"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(formatted, encoding="utf-8", newline="\n")
    manifest = {
        "scope": "independent original-C scalar deblock edge and threshold oracle",
        "revision": REVISION, "source_sha256": SOURCE_HASHES,
        "source_url": f"https://aomedia.googlesource.com/aom/+/{REVISION}/aom_dsp/loopfilter.c",
        "compile": compile_info, "generator_sha256": sha(Path(__file__).read_bytes()),
        "edge_count": len(inputs), "threshold_count": len(threshold_rows),
        "layout": {"samples.bin": "60-byte records: u8 width,level,sharpness,depth;14 LE-u16 input;14 LE-u16 output; p6..p0,q0..q6",
                   "thresholds.bin": "5-byte records: u8 level,sharpness,limit,blimit,hev; sharpness-major level-minor"},
        "cross_checks": {"horizontal_vertical_and_four_lanes": len(inputs),
                         "lowbd8_highbd8": sum(c.depth == 8 for c in inputs)},
        "branch_counts": coverage,
        "artifact_sha256": {"samples.bin": sha(binary), "thresholds.bin": sha(thresholds)},
        "test_file": target.relative_to(ROOT).as_posix(),
        "test_sha256": sha(target.read_bytes()), "unformatted_test_sha256": sha(raw_test.encode()),
        "cases": records,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(inputs)} original-C edge cases and512 threshold tuples; WB {manifest['test_sha256']}")
    check(args)


if __name__ == "__main__":
    main()
