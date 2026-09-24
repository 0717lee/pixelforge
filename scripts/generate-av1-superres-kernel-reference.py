#!/usr/bin/env python3
"""Generate AV1 superres goldens using unchanged pinned AOM scalar C.

Python constructs native input samples and serializes C output; it does not
implement a resampler. Original rect wrappers supply repeated borders, original
step/x0 functions select phase, and original scalar convolution produces pixels.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
HELPER = Path(__file__).with_name("generate-av1-filter-intra-kernel-reference.py")
spec = importlib.util.spec_from_file_location("superres_source_helpers", HELPER)
assert spec is not None and spec.loader is not None
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
braced, macro = helpers.braced, helpers.macro
SOURCE_NAMES = ("av1/common/resize.c", "av1/common/resize.h", "av1/common/convolve.c",
                "aom_dsp/aom_filter.h", "aom_dsp/aom_dsp_common.h", "aom_ports/mem.h", "aom_mem/aom_mem.h")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, encoding="utf-8", **kwargs)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"reference command failed: {command}\n{error.stderr[-2000:]}\n{error.stdout[-1000:]}") from error


def load_sources(directory):
    if run(["git", "-C", str(directory), "rev-parse", "HEAD"]).stdout.strip() != REVISION:
        raise RuntimeError("unexpected original source revision")
    sources = {}
    for name in SOURCE_NAMES:
        original = subprocess.run(["git", "-C", str(directory), "show", f"{REVISION}:{name}"], check=True, capture_output=True).stdout
        original = original.replace(b"\r\n", b"\n")
        current = (directory / name).read_bytes().replace(b"\r\n", b"\n")
        if current != original:
            raise RuntimeError(f"modified original C source: {name}")
        sources[name] = original.decode("utf-8")
    return sources


C_TYPES = r"""
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef signed short int16_t;
typedef signed int int32_t;
typedef unsigned int uint32_t;
typedef unsigned long long uintptr_t;
typedef unsigned long long size_t;
typedef int bool;
#define true 1
#define false 0
#define NULL ((void *)0)
extern int scanf(const char *, ...);
extern int printf(const char *, ...);
extern void exit(int);
extern void *malloc(size_t);
extern void free(void *);
extern void *memcpy(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
extern int memcmp(const void *, const void *, size_t);
#define aom_malloc malloc
#define aom_free free
static void fail(int line) { printf("C oracle failed at line %d\n", line); exit(10); }
#define assert(x) ((x) ? (void)0 : fail(__LINE__))
static int clip_low, clip_high, negative_rounds, halfway_rounds, round_calls;
"""

C_COUNTERS = r"""
/* Observe arguments, then delegate the result to the original helpers. */
static uint8_t oracle_clip8(int value) {
  clip_low += value < 0; clip_high += value > 255;
  return clip_pixel(value);
}
static uint16_t oracle_clip16(int value, int depth) {
  clip_low += value < 0; clip_high += value >= (1 << depth);
  return clip_pixel_highbd(value, depth);
}
static int oracle_round(int value, int bits) {
  ++round_calls;
  negative_rounds += value < 0;
  halfway_rounds += (value & ((1 << bits) - 1)) == (1 << (bits - 1));
  return ROUND_POWER_OF_TWO(value, bits);
}
#define clip_pixel oracle_clip8
#define clip_pixel_highbd oracle_clip16
#undef ROUND_POWER_OF_TWO
#define ROUND_POWER_OF_TWO oracle_round
"""

C_DISPATCH = r"""
#define av1_convolve_horiz_rs av1_convolve_horiz_rs_c
#define av1_highbd_convolve_horiz_rs av1_highbd_convolve_horiz_rs_c
"""

C_MAIN = r"""
static void reset_counters(void) {
  clip_low = clip_high = negative_rounds = halfway_rounds = round_calls = 0;
}
static int differences(const uint16_t *a, const uint16_t *b, int stride, int w, int h) {
  int count = 0;
  for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x)
    count += a[y * stride + x] != b[y * stride + x];
  return count;
}
int main(void) {
  int id, d, u, available, rows, input_stride, depth, denom, split;
  assert(sizeof(void *) == 8 && sizeof(int) == 4 && sizeof(uint16_t) == 2);
  assert((-1 >> 1) == -1 && (-7 / 2) == -3);
  while (scanf("%d %d %d %d %d %d %d %d %d", &id, &d, &u, &available,
               &rows, &input_stride, &depth, &denom, &split) == 9) {
    assert(d > 0 && u > d && u <= 2 * d && available >= d && available <= input_stride);
    assert(rows > 0 && (depth == 8 || depth == 10 || depth == 12));
    const int stride = input_stride + 10, dst_stride = u + 3;
    const size_t bytes = (size_t)stride * rows * sizeof(uint16_t);
    const size_t out_bytes = (size_t)dst_stride * rows * sizeof(uint16_t);
    uint16_t *buffer = malloc(bytes), *saved = malloc(bytes);
    uint16_t *output = malloc(out_bytes), *alternate = malloc(out_bytes);
    assert(buffer && saved && output && alternate);
    aom_memset16(buffer, 0x6A6A, stride * rows);
    aom_memset16(output, 0x6B6B, dst_stride * rows);
    uint16_t *input = buffer + 5;
    for (int y = 0; y < rows; ++y) for (int x = 0; x < input_stride; ++x) {
      int value; assert(scanf("%d", &value) == 1 && value >= 0 && value <= 65535);
      if (x < available) assert(value < (1 << depth));
      input[y * stride + x] = value;
    }
    memcpy(saved, buffer, bytes);
    const int step = av1_get_upscale_convolve_step(d, u);
    const int x0 = get_upscale_convolve_x0(d, u, step);
    reset_counters();
    assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input), rows, available,
        stride, CONVERT_TO_BYTEPTR(output), rows, u, dst_stride, step, x0, 1, 1, depth));
    const int low = clip_low, high = clip_high, neg = negative_rounds, half = halfway_rounds;
    assert(round_calls == rows * u && !memcmp(saved, buffer, bytes));
    for (int y = 0; y < rows; ++y) for (int x = u; x < dst_stride; ++x)
      assert(output[y * dst_stride + x] == 0x6B6B);
    int lowbd_checked = 0;
    if (depth == 8) {
      uint8_t *src8 = malloc(stride * rows), *copy8 = malloc(stride * rows);
      uint8_t *out8 = malloc(dst_stride * rows);
      assert(src8 && copy8 && out8);
      for (int i = 0; i < stride * rows; ++i) src8[i] = buffer[i];
      memcpy(copy8, src8, stride * rows); memset(out8, 0x6B, dst_stride * rows);
      reset_counters();
      assert(upscale_normative_rect(src8 + 5, rows, available, stride, out8,
          rows, u, dst_stride, step, x0, 1, 1));
      assert(!memcmp(src8, copy8, stride * rows));
      assert(clip_low == low && clip_high == high && negative_rounds == neg && halfway_rounds == half);
      for (int y = 0; y < rows; ++y) for (int x = 0; x < dst_stride; ++x)
        assert(out8[y * dst_stride + x] == (x < u ? output[y * dst_stride + x] : 0x6B));
      lowbd_checked = 1; free(src8); free(copy8); free(out8);
    }
    int truncated_changes = 0, segmented = 0, internal_pad_changes = 0;
    if (available > d) {
      assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input), rows, d,
          stride, CONVERT_TO_BYTEPTR(alternate), rows, u, dst_stride, step, x0, 1, 1, depth));
      truncated_changes = differences(output, alternate, dst_stride, u, rows);
      assert(!memcmp(saved, buffer, bytes));
    }
    if (split > 0) {
      const int dst_split = split * denom / 8;
      const int next_x0 = x0 + dst_split * step - (split << RS_SCALE_SUBPEL_BITS);
      assert(split < d && dst_split > 0 && dst_split < u);
      assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input), rows, split,
          stride, CONVERT_TO_BYTEPTR(alternate), rows, dst_split, dst_stride, step, x0, 1, 0, depth));
      assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input + split), rows,
          available - split, stride, CONVERT_TO_BYTEPTR(alternate + dst_split), rows,
          u - dst_split, dst_stride, step, next_x0, 0, 1, depth));
      assert(differences(output, alternate, dst_stride, u, rows) == 0);
      assert(!memcmp(saved, buffer, bytes)); segmented = 1;
      /* An ancillary negative control uses the original C with tile-edge padding. */
      assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input), rows, split,
          stride, CONVERT_TO_BYTEPTR(alternate), rows, dst_split, dst_stride, step, x0, 1, 1, depth));
      assert(highbd_upscale_normative_rect(CONVERT_TO_BYTEPTR(input + split), rows,
          available - split, stride, CONVERT_TO_BYTEPTR(alternate + dst_split), rows,
          u - dst_split, dst_stride, step, next_x0, 1, 1, depth));
      internal_pad_changes = differences(output, alternate, dst_stride, u, rows);
      assert(!memcmp(saved, buffer, bytes));
    }
    int phases[64] = { 0 }, position = x0;
    for (int x = 0; x < u; ++x, position += step)
      phases[(position & RS_SCALE_SUBPEL_MASK) >> RS_SCALE_EXTRA_BITS] += rows;
    printf("%d %d %d %d %d %d %d %d %d %d %d", id, step, x0, low, high, neg, half,
           lowbd_checked, truncated_changes, segmented, internal_pad_changes);
    for (int i = 0; i < 64; ++i) printf(" %d", phases[i]);
    for (int y = 0; y < rows; ++y) for (int x = 0; x < u; ++x) {
      assert(output[y * dst_stride + x] < (1 << depth));
      printf(" %d", output[y * dst_stride + x]);
    }
    printf("\n"); free(buffer); free(saved); free(output); free(alternate);
  }
  return 0;
}
"""


def reference_source(sources):
    resize = sources["av1/common/resize.c"]
    parts, excerpts = [resize[:resize.index("*/") + 2], C_TYPES], []

    def add(name, label, body):
        excerpts.append({"file": name, "name": label, "line": sources[name][:sources[name].index(body)].count("\n") + 1, "sha256": sha(body.encode())})
        parts.append(body)

    def function(name, label):
        add(name, label, braced(sources[name], label))

    for name in ("ROUND_POWER_OF_TWO", "CONVERT_TO_SHORTPTR", "CONVERT_TO_BYTEPTR"):
        add("aom_ports/mem.h", name, macro(sources["aom_ports/mem.h"], name))
    for name in ("FILTER_BITS", "RS_SUBPEL_BITS", "RS_SUBPEL_MASK", "RS_SCALE_SUBPEL_BITS", "RS_SCALE_SUBPEL_MASK", "RS_SCALE_EXTRA_BITS", "RS_SCALE_EXTRA_OFF"):
        add("aom_dsp/aom_filter.h", name, macro(sources["aom_dsp/aom_filter.h"], name))
    add("av1/common/resize.h", "UPSCALE_NORMATIVE_TAPS", macro(sources["av1/common/resize.h"], "UPSCALE_NORMATIVE_TAPS"))
    add("av1/common/resize.c", "av1_resize_filter_normative", braced(resize, "const int16_t av1_resize_filter_normative[", declaration=True))
    function("aom_mem/aom_mem.h", "static inline void *aom_memset16(")
    for marker in ("static inline int clamp(", "static inline uint8_t clip_pixel(", "static inline uint16_t clip_pixel_highbd("):
        function("aom_dsp/aom_dsp_common.h", marker)
    function("av1/common/resize.c", "int32_t av1_get_upscale_convolve_step(")
    function("av1/common/resize.c", "static int32_t get_upscale_convolve_x0(")
    parts.append(C_COUNTERS)
    function("av1/common/convolve.c", "void av1_convolve_horiz_rs_c(")
    function("av1/common/convolve.c", "void av1_highbd_convolve_horiz_rs_c(")
    parts.append(C_DISPATCH)
    function("av1/common/resize.c", "static bool upscale_normative_rect(")
    function("av1/common/resize.c", "static bool highbd_upscale_normative_rect(")
    parts.append(C_MAIN)
    return "\n\n".join(parts), excerpts


def make_cases():
    cases = []
    widths = (33, 47, 63, 65, 95, 127, 129, 257)
    parameters = [(u, denominator, plane, depth, pattern, 1 + 2 * (wi % 4), False)
                  for depth in (8, 10, 12) for denominator in range(9, 17)
                  for wi, u in enumerate(widths) for plane in (0, 1) for pattern in (0, 1)]
    parameters += [(u, 16, plane, depth, 1, 1, True)
                   for depth in (8, 10, 12) for u in (65535, 65536) for plane in (0, 1)]
    offset = 0
    for uy, denominator, plane, depth, pattern, luma_rows, boundary in parameters:
        dy = (uy * 8 + denominator // 2) // denominator
        assert dy >= 16 and uy > dy
        divisor = 1 << plane
        d, u = (dy + divisor - 1) // divisor, (uy + divisor - 1) // divisor
        available = ((dy + 7) // 8 * 8) // divisor
        rows = (luma_rows + divisor - 1) // divisor
        stride = available + (7 if pattern else 0)
        split = (64 // divisor) if d > 64 // divisor else 0
        cases.append({"index": len(cases), "luma_upscaled_width": uy, "luma_downscaled_width": dy,
                      "denominator": denominator, "plane": plane, "bit_depth": depth, "pattern": pattern,
                      "seed": 107 + len(cases), "downscaled_width": d, "upscaled_width": u,
                      "available_width": available, "src_stride": stride, "rows": rows,
                      "tile_split": split, "width_boundary": boundary,
                      "offset_bytes": offset, "sample_count": rows * u})
        offset += rows * u * 2
    return cases


def input_samples(case):
    maximum = (1 << case["bit_depth"]) - 1
    result = []
    for row in range(case["rows"]):
        for x in range(case["src_stride"]):
            if x >= case["available_width"]:
                value = 65535
            elif case["pattern"]:
                value = 0 if (x + 2 * row + case["seed"]) % 4 < 2 else maximum
            else:
                value = (case["seed"] * 37 + x * 29 + row * 43 + (x % 7) * x * 11 + row * x * 3) & maximum
            result.append(value)
    return result


def run_reference(cc, source, cases):
    compiler = Path(shutil.which(cc) or cc).resolve()
    fields = ("index", "downscaled_width", "upscaled_width", "available_width", "rows", "src_stride", "bit_depth", "denominator", "tile_split")
    request = []
    for case in cases:
        request.append(" ".join(str(case[key]) for key in fields))
        samples = input_samples(case)
        case["input_sha256"] = sha(struct.pack(f"<{len(samples)}H", *samples))
        request.append(" ".join(map(str, samples)))
    with tempfile.TemporaryDirectory(prefix="pixelforge-superres-") as folder:
        directory = Path(folder)
        c_file, executable = directory / "superres.c", directory / "superres.exe"
        c_file.write_text(source, encoding="utf-8", newline="\n")
        command = [str(compiler)]
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command += ["-B", str(moon_root)]
        command += [str(c_file), "-o", str(executable)]
        run(command)
        result = run([str(executable)], input="\n".join(request) + "\n")
        command = [argument.replace(str(directory), "<temporary>") for argument in command]
    lines = result.stdout.splitlines()
    if len(lines) != len(cases):
        raise RuntimeError(f"original C returned {len(lines)} cases instead of {len(cases)}")
    output = bytearray()
    for case, line in zip(cases, lines):
        values = list(map(int, line.split()))
        if len(values) != 75 + case["sample_count"] or values[0] != case["index"]:
            raise RuntimeError(f"invalid original-C result extent: {case['index']}")
        case.update(dict(zip(("step", "x0", "clip_low", "clip_high", "negative_rounds", "halfway_rounds", "lowbd_crosscheck", "truncated_available_changes", "segmented_crosscheck", "internal_tile_padding_changes"), values[1:11])))
        case["phase_counts"] = values[11:75]
        samples = values[75:]
        if any(value < 0 or value >= 1 << case["bit_depth"] for value in samples):
            raise RuntimeError("native output sample out of range")
        packed = struct.pack(f"<{len(samples)}H", *samples)
        case["output_sha256"], case["output_crc32"] = sha(packed), zlib.crc32(packed)
        output.extend(packed)
    version = run([str(compiler), "-v"])
    return bytes(output), {"path": str(compiler), "sha256": sha(compiler.read_bytes()), "version": (version.stdout + version.stderr).strip(), "compile_command": command}


def coverage(cases, binary):
    assert len(cases) == 780
    phases = [sum(case["phase_counts"][i] for case in cases) for i in range(64)]
    assert all(phases) and sum(phases) == len(binary) // 2
    keys = ("clip_low", "clip_high", "negative_rounds", "halfway_rounds", "lowbd_crosscheck", "truncated_available_changes", "segmented_crosscheck", "internal_tile_padding_changes")
    totals = {key: sum(case[key] for case in cases) for key in keys}
    assert totals["lowbd_crosscheck"] == 260 and all(totals.values())
    for depth in (8, 10, 12):
        assert sum(c["clip_low"] for c in cases if c["bit_depth"] == depth) > 0
        assert sum(c["clip_high"] for c in cases if c["bit_depth"] == depth) > 0
    return {"cases": len(cases), "native_samples": len(binary) // 2, "phase_counts": phases,
            "actual_original_c_observations": totals,
            "mi_padding_cases_with_pixel_effect": sum(c["truncated_available_changes"] > 0 for c in cases),
            "tile_boundary_cases_with_pixel_effect": sum(c["internal_tile_padding_changes"] > 0 for c in cases),
            "normal_denominators": list(range(9, 17)), "width_boundary_cases": 12}


MOON_HELPER = """///|
// Only input construction is shared; expected pixels and parameters are from C.
fn av1_superres_reference_case(
  index : Int, depth : Int, pattern : Int, seed : Int, stride : Int,
  available : Int, downscaled : Int, upscaled : Int, rows : Int,
  expected_step : Int, expected_x0 : Int, expected_crc : UInt,
  expected_pixels : Array[Int],
) -> Unit raise {
  let maximum = (1 << depth) - 1
  let source : Array[Int] = []
  for row in 0..<rows { for x in 0..<stride {
    source.push(if x >= available { 65535 } else if pattern == 1 {
      if (x + 2 * row + seed) % 4 < 2 { 0 } else { maximum }
    } else {
      (seed * 37 + x * 29 + row * 43 + (x % 7) * x * 11 + row * x * 3) & maximum
    })
  } }
  let before = source.copy()
  assert_eq(av1_superres_params(downscaled, upscaled), Some((expected_step, expected_x0)))
  let actual = av1_superres_upscale_plane(source, stride, available, downscaled, upscaled, rows, depth).unwrap()
  assert_eq((index, actual.length()), (index, upscaled * rows))
  assert_eq(source, before)
  let packed : Array[Byte] = []
  for value in actual {
    assert_true(value >= 0 && value <= maximum)
    packed.push((value & 255).to_byte())
    packed.push((value >> 8).to_byte())
  }
  assert_eq((index, crc32(packed, 0, packed.length())), (index, expected_crc))
  if expected_pixels.length() > 0 { assert_eq((index, actual), (index, expected_pixels)) }
}
"""


def render_test(cases, binary):
    text = ["// Generated by scripts/generate-av1-superres-kernel-reference.py.\n",
            f"// Unchanged original scalar AOM revision {REVISION}.\n",
            f"// Canonical uint16-LE output SHA256 {sha(binary)}.\n", MOON_HELPER]
    for depth in (8, 10, 12):
        for plane in (0, 1):
            text.append(f'\n///|\ntest "original C superres {depth}bit plane{plane} phases padding stride" {{\n')
            for case in cases:
                if case["bit_depth"] != depth or case["plane"] != plane:
                    continue
                keys = ("index", "bit_depth", "pattern", "seed", "src_stride", "available_width", "downscaled_width", "upscaled_width", "rows", "step", "x0")
                args = [str(case[key]) for key in keys] + [f"0x{case['output_crc32']:08x}U"]
                start, count = case["offset_bytes"], case["sample_count"]
                full = list(struct.unpack(f"<{count}H", binary[start:start + count * 2])) if count <= 64 else []
                args.append(str(full))
                text.append("  av1_superres_reference_case(" + ", ".join(args) + ")\n")
            text.append("}\n")
    return "".join(text)


def write_json(path, manifest):
    metadata = {key: value for key, value in manifest.items() if key != "cases"}
    text = json.dumps(metadata, indent=2, ensure_ascii=False)[:-2]
    text += ',\n  "cases": [\n' + ",\n".join("    " + json.dumps(case, separators=(",", ":")) for case in manifest["cases"]) + "\n  ]\n}\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def check(args):
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    if manifest["generator_sha256"] != sha(Path(__file__).read_bytes()) or manifest["helper_generator_sha256"] != sha(HELPER.read_bytes()):
        raise RuntimeError("generator source changed")
    binary = (args.out / "output.bin").read_bytes()
    if sha(binary) != manifest["output_sha256"]:
        raise RuntimeError("canonical binary hash changed")
    generated = make_cases()
    for case, initial in zip(manifest["cases"], generated):
        assert all(case[key] == value for key, value in initial.items())
        start, count = case["offset_bytes"], case["sample_count"]
        data = binary[start:start + count * 2]
        assert len(data) == count * 2 and sha(data) == case["output_sha256"] and zlib.crc32(data) == case["output_crc32"]
        samples = input_samples(case)
        assert sha(struct.pack(f"<{len(samples)}H", *samples)) == case["input_sha256"]
    assert coverage(manifest["cases"], binary) == manifest["coverage"]
    raw = render_test(manifest["cases"], binary)
    assert sha(raw.encode()) == manifest["unformatted_test_sha256"]
    path = args.test or Path(manifest["test_file"])
    assert sha(path.read_bytes()) == manifest["test_sha256"]
    print("Verified780 canonical original-C cases, all64 phases and input/output/WB hashes; no builds")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--cc", default=str(Path.home() / ".moon/bin/internal/tcc.exe"))
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-superres-kernel")
    parser.add_argument("--test", type=Path)
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check(args)
        return 0
    if args.source_dir is None:
        parser.error("generation requires --source-dir")
    test = args.test or ROOT / "_refs/av1_superres_kernel_reference_wbtest.mbt"
    sources = load_sources(args.source_dir)
    source, excerpts = reference_source(sources)
    cases = make_cases()
    binary, compiler = run_reference(args.cc, source, cases)
    raw = render_test(cases, binary)
    formatted = run([args.moonfmt, "-"], input=raw).stdout
    manifest = {"scope": "active pure horizontal superres, original C normative rect wrappers and scalar convolutions; header policy is outside this corpus",
                "revision": REVISION, "source_sha256": {name: sha(text.encode()) for name, text in sources.items()},
                "source_url": f"https://aomedia.googlesource.com/aom/+/{REVISION}/", "original_fragments": excerpts,
                "extracted_c_sha256": sha(source.encode()), "compiler": compiler,
                "generator_sha256": sha(Path(__file__).read_bytes()), "helper_generator_sha256": sha(HELPER.read_bytes()),
                "generation_command": [sys.executable, str(Path(__file__).resolve()), "--source-dir", str(args.source_dir.resolve()), "--cc", args.cc,
                                       "--out", str(args.out), "--test", str(test), "--moonfmt", args.moonfmt],
                "input_contract": "strided native rows; available=align8(luma decoded width)/plane divisor, phase uses visible ceil plane widths; gap pixels65535 are not samples",
                "pattern0": "(seed*37+x*29+row*43+(x%7)*x*11+row*x*3)&maximum",
                "pattern1": "0 if (x+2*row+seed)%4<2 else maximum",
                "output_format": "concatenated row-major unsigned16 little-endian",
                "output_sha256": sha(binary), "coverage": coverage(cases, binary),
                "test_file": str(test), "test_sha256": sha(formatted.encode()), "unformatted_test_sha256": sha(raw.encode()), "cases": cases}
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "output.bin").write_bytes(binary)
    test.parent.mkdir(parents=True, exist_ok=True)
    test.write_text(formatted, encoding="utf-8", newline="\n")
    write_json(args.out / "manifest.json", manifest)
    print(json.dumps(manifest["coverage"], separators=(",", ":")))
    print("Generated original-C superres corpus; no Moon build")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
