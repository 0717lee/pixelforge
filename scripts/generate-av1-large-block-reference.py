#!/usr/bin/env python3
"""Generate bounded real 128-axis coding-block candidates and native references.

SB128 alone is not evidence of a 128-pixel coding block. An independent MSAC
prefix reader confirms the first partition, skip, DC modes and tx_depth before
accepting a candidate. Libaom min/max controls constrain both block dimensions;
the reader also checks their picture-boundary exceptions for rectangles/crops.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import math
import re
import shutil
import struct
import sys
from pathlib import Path


sys.dont_write_bytecode = True


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


helpers = module("large_cdef_helpers", "generate-av1-cdef-frame-reference.py")
arithmetic = module("large_msac_reader", "craft_av1_fixture.py")
mono_helpers = module("large_mono_helpers", "generate-av1-monochrome-reference.py")
run = helpers.run
sha256 = helpers.sha256
trace_value = helpers.helpers.helpers.trace_value
rle = helpers.helpers.helpers.rle

# Normative default CDF rows at the first tile block (no top/left neighbours).
# AV1 spec sections 9.3/10, also present in go-av1/cdf/tables_gen.go and
# tables_txsize_gen.go. Only the decoder from craft_av1_fixture is used; this
# script never invokes its range encoder or writes synthesized OBU bytes.
PARTITION128 = [27899, 28219, 28529, 32484, 32539, 32619, 32639, 32768, 0]
SKIP0 = [31671, 32768, 0]
Y_MODE00 = [15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093, 30466, 32768, 0]
UV_DC_NO_CFL = [22631, 24152, 25378, 25661, 25986, 26520, 27055, 27923, 28244, 30059, 30941, 31961, 32768, 0]
TX64_DEPTH0 = [5782, 11475, 32768, 0]


def frame_tile(data: bytes, trace: str) -> tuple[bytes, int]:
    frames = []
    position = 0
    while position < len(data):
        start = position
        header = data[position]
        position += 1 + ((header >> 2) & 1)
        if not header & 2:
            raise RuntimeError("candidate OBU lacks its size field")
        size = 0
        for shift in range(0, 56, 7):
            byte = data[position]
            position += 1
            size |= (byte & 127) << shift
            if byte < 128:
                break
        else:
            raise RuntimeError("unbounded OBU size")
        if position + size > len(data):
            raise RuntimeError("truncated encoder OBU")
        if (header >> 3) & 15 == 6:
            frames.append((data[position:position + size], position - start))
        position += size
    if len(frames) != 1:
        raise RuntimeError("candidate must have one FRAME OBU")
    section = trace.split("Frame Header")[-1].split("Tile Group")[0]
    bits = re.findall(r"\]\s+(\d+)\s+\S+\s+([01]*)\s*=\s*-?\d+", section)
    if not bits:
        raise RuntimeError("missing actual frame-header bit offsets")
    bit_end = max(int(position) + len(value) for position, value in bits)
    if bit_end % 8:
        raise RuntimeError("frame header did not end on byte alignment")
    payload, obu_header = frames[0]
    header_bytes = bit_end // 8 - obu_header
    if header_bytes <= 0 or header_bytes >= len(payload):
        raise RuntimeError("invalid frame-header extent")
    return payload[header_bytes:], header_bytes


def first_block_prefix(data: bytes, trace: str, width: int, height: int, monochrome: bool, lossless: bool = False) -> dict[str, object]:
    tile, header_bytes = frame_tile(data, trace)
    reader = arithmetic.MsacDecoder(tile)
    rows = ((height + 7) // 8) * 8 > 64
    cols = ((width + 7) // 8) * 8 > 64
    cdf = PARTITION128.copy()
    if rows and cols:
        partition = reader.symbol(cdf)
    elif rows or cols:
        selected = (2, 3, 4, 6, 7) if cols else (1, 3, 4, 5, 6)
        split_probability = sum(cdf[index] - (cdf[index - 1] if index else 0) for index in selected)
        symbol = reader.symbol([32768 - split_probability, 32768, 0])
        partition = 3 if symbol else (1 if cols else 2)
    else:
        partition = 3
    geometries = {0: [128, 128], 1: [128, 64], 2: [64, 128]}
    result = {"partition_symbol": partition, "partition_name": ("NONE", "HORZ", "VERT", "SPLIT")[partition] if partition < 4 else str(partition),
              "coding_dimensions": geometries.get(partition), "frame_header_bytes": header_bytes, "tile_payload_bytes": len(tile)}
    if partition not in geometries:
        return result
    skip = reader.symbol(SKIP0.copy())
    result["skip"] = skip
    if skip != 0:
        return result
    cdef_bits = 0 if lossless else trace_value(trace, "cdef_bits")
    cdef_index = 0
    for _ in range(cdef_bits):
        cdef_index = (cdef_index << 1) | reader.bool()
    result["cdef_index"] = None if lossless else cdef_index
    result["y_mode"] = reader.symbol(Y_MODE00.copy())
    if result["y_mode"] != 0:
        raise RuntimeError("candidate was not DC-only at its first large coding block")
    if not monochrome:
        result["uv_mode"] = reader.symbol(UV_DC_NO_CFL.copy())
        if result["uv_mode"] != 0:
            raise RuntimeError("candidate chroma was not DC-only")
    # Every accepted block has an axis of 128, hence no palette mode syntax,
    # even with allow_screen_content_tools=1 (AV1 palette_mode_info condition).
    result["palette_syntax_present"] = False
    mode = 0 if lossless else trace_value(trace, "tx_mode")
    depth = reader.symbol(TX64_DEPTH0.copy()) if mode == 2 else 0
    result["tx_mode"] = mode
    result["tx_depth"] = depth
    result["luma_tx_side"] = 4 if lossless else 64 >> depth
    if lossless:
        result["lossless_inference"] = "qindex zero with zero deltas: ONLY_4X4, no CDEF index or tx_depth syntax"
    return result


def chunk_residual_evidence(planes: list[list[int]], width: int, height: int, depth: int, lossless: bool = False) -> list[dict[str, object]]:
    evidence = []
    for plane, values in enumerate(planes):
        divisor = 1 if plane == 0 else 2
        pw, ph = (width + divisor - 1) // divisor, (height + divisor - 1) // divisor
        chunk_side = 64 // divisor
        tx_side = 4 if lossless else ((64 >> depth) if plane == 0 else 32)
        for chunk_y in range(0, ph, chunk_side):
            for chunk_x in range(0, pw, chunk_side):
                varying_transforms = 0
                for y in range(chunk_y, min(chunk_y + chunk_side, ph), tx_side):
                    for x in range(chunk_x, min(chunk_x + chunk_side, pw), tx_side):
                        block = [values[row * pw + col] for row in range(y, min(y + tx_side, ph)) for col in range(x, min(x + tx_side, pw))]
                        varying_transforms += len(set(block)) > 1
                evidence.append({"plane": plane, "chunk_x": chunk_x, "chunk_y": chunk_y, "transform_side": tx_side, "varying_transforms": varying_transforms})
    return evidence


def guided_input(width: int, height: int, bit_depth: int, mono: bool, lossless: bool) -> tuple[list[list[int]], dict[str, object]]:
    planes = []
    scale = 1 << (bit_depth - 8)
    maximum = (1 << bit_depth) - 1
    for plane in range(1 if mono else 3):
        divisor = 1 if plane == 0 else 2
        pw, ph = width // divisor, height // divisor
        values = []
        for y in range(ph):
            for x in range(pw):
                if lossless:
                    value = (x + pw * y + plane * 137) % (maximum + 1)
                else:
                    cell = 16 // divisor
                    base = 64 if ((x // cell + y // cell + plane) % 2 == 0) else 192
                    cosine = math.cos(math.pi * (2 * (x % cell) + 1) / (2 * cell)) * math.cos(math.pi * (2 * (y % cell) + 1) / (2 * cell))
                    value = round((base + 4 * cosine) * scale)
                values.append(max(0, min(maximum, value)))
        planes.append(values)
    pattern = ({"name": "native_full_range_ramp", "formula": "(x + plane_width*y + plane*137) modulo (1<<bit_depth)", "full_range": True}
               if lossless else {"name": "physical_16x16_checkerboard_with_local_cosine", "formula": "round((base + 4*cos(pi*(2*(x%cell)+1)/(2*cell))*cos(pi*(2*(y%cell)+1)/(2*cell)))*(1<<(bit_depth-8)))", "base": "64 or 192 selected by (x//cell+y//cell+plane)%2", "cell": "16 for Y, 8 for U/V", "rounding": "Python round, nearest ties to even", "monochrome_uses_only_y": mono})
    return planes, pattern


def verify_existing_artifacts(manifest: dict[str, object], base: Path) -> None:
    for case in manifest["fixtures"]:
        for key, filename in case.items():
            if key.endswith("_file"):
                hash_key = key[:-5] + "_sha256"
                if hash_key in case and sha256((base / filename).read_bytes()) != case[hash_key]:
                    raise RuntimeError(f"existing artifact hash mismatch: {filename}")


def generated_test(cases: list[dict[str, object]], base: Path) -> str:
    source = """/// Generated by scripts/generate-av1-large-block-reference.py.
/// Real coding-block dimensions are verified by an independent entropy prefix.
fn av1_large_block_reference_compare(
  stream : Array[Byte], avif : Array[Byte], width : Int, height : Int, depth : Int,
  mono : Bool, y_runs : Array[Int], u_runs : Array[Int], v_runs : Array[Int],
  gray8_runs : Array[Int],
) -> Unit raise {
  let references = [av1_reference_planes_expand(y_runs)]
  if !mono {
    references.push(av1_reference_planes_expand(u_runs))
    references.push(av1_reference_planes_expand(v_runs))
  }
  let frame = av1_decode_frame_planes(stream, allow_monochrome=mono).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, depth))
  assert_eq(frame.planes.length(), references.length())
  for plane in 0..<references.length() {
    let actual = av1_frame_crop(frame, plane)
    assert_eq(actual.length(), references[plane].length())
    for index in 0..<actual.length() {
      assert_eq((plane, index, actual[index]), (plane, index, references[plane][index]))
    }
  }
  let actual = av1_decode(stream).unwrap()
  let container = avif_decode_rgba(avif).unwrap()
  assert_eq((actual.width, actual.height), (width, height))
  assert_eq((container.width, container.height), (width, height))
  if !mono {
    let expected = av1_yuv420_highbd_to_rgba(width, height, references[0], references[1], references[2], depth,
      full_range=frame.full_range, matrix_coefficients=frame.matrix_coefficients).unwrap()
    for y in 0..<height { for x in 0..<width {
      assert_eq(actual.get_pixel(x,y), expected.get_pixel(x,y))
      assert_eq(container.get_pixel(x,y), expected.get_pixel(x,y))
    } }
  } else {
    let gray8 = av1_reference_planes_expand(gray8_runs)
    assert_eq(gray8.length(), width * height)
    for index in 0..<gray8.length() {
      let value = gray8[index].to_byte()
      let expected = (value, value, value, b'\\xFF')
      assert_eq(actual.get_pixel(index % width, index / width), expected)
      assert_eq(container.get_pixel(index % width, index / width), expected)
    }
  }
}
"""
    for case in cases:
        name = case["name"]
        width, height = case["dimensions"]
        depth = case["bit_depth"]
        reference = mono_helpers.read_hashed(base / case["reference_file"], case["reference_sha256"])
        planes = ([mono_helpers.unpack(reference, width * height, depth)] if case["monochrome"]
                  else helpers.unpack_planes(reference, width, height, depth))
        gray8 = (mono_helpers.unpack(mono_helpers.read_hashed(base / case["gray8_reference_file"], case["gray8_reference_sha256"]), width * height, 8)
                 if case["monochrome"] else [])
        stream = mono_helpers.read_hashed(base / case["obu_file"], case["obu_sha256"])
        source += f'\n///|\ntest "external true large coding block {name}" {{\n'
        lines = ["    " + ", ".join(f"b'\\x{x:02X}'" for x in stream[i:i + 12]) + "," for i in range(0, len(stream), 12)]
        source += "  let stream : Array[Byte] = [\n" + "\n".join(lines) + "\n  ]\n"
        avif = mono_helpers.read_hashed(base / case["avif_file"], case["avif_sha256"])
        lines = ["    " + ", ".join(f"b'\\x{x:02X}'" for x in avif[i:i + 12]) + "," for i in range(0, len(avif), 12)]
        source += "  let avif : Array[Byte] = [\n" + "\n".join(lines) + "\n  ]\n"
        for index, plane in enumerate(("y", "u", "v")):
            values = rle(planes[index]) if index < len(planes) else []
            source += f"  let {plane}_runs : Array[Int] = " + helpers.helpers.helpers.array(values) + "\n"
        source += "  let gray8_runs : Array[Int] = " + helpers.helpers.helpers.array(rle(gray8)) + "\n"
        source += f'  av1_large_block_reference_compare(stream, avif, {width}, {height}, {case["bit_depth"]}, {str(case["monochrome"]).lower()}, y_runs, u_runs, v_runs, gray8_runs)\n}}\n'
    return source


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("tests/fixtures/av1-cdef-frame/manifest.json"))
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-large-block"))
    parser.add_argument("--test", type=Path, default=Path("_refs/av1_large_block_reference_wbtest.mbt"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--include-source-guided-tx32", action="store_true", help="append six deterministic tx_depth=1 candidates by enabling search and disabling 64-point transforms")
    parser.add_argument("--include-rectangles-lossless", action="store_true", help="append exactly four source-guided 10-bit rectangle and two lossless128 candidates")
    parser.add_argument("--include-neutral-chroma-rectangles", action="store_true", help="append exactly two 10-bit color rectangles with unchanged checkerboard Y and neutral U/V")
    parser.add_argument("--reuse-existing", action="store_true", help="verify and preserve the current manifest/artifacts, encoding only new candidate names")
    parser.add_argument("--verify-existing-test", action="store_true", help="regenerate the recorded test in memory from hashed references; require unchanged bytes without encoding or writing files")
    args = parser.parse_args()
    if args.verify_existing_test:
        manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        verify_existing_artifacts(manifest, args.out)
        mono_helpers.verify_generated_test(manifest, generated_test(manifest["fixtures"], args.out), args.moonfmt)
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    scalar, scalar_version = mono_helpers.scalar_library(args.libavif_scalar)
    source_manifest = json.loads(args.source.read_text(encoding="utf-8"))
    templates = {case["name"]: case for case in source_manifest["fixtures"]}
    help_result = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", help_result.stdout + help_result.stderr).group(0)
    ffmpeg_version = run([args.ffmpeg, "-version"]).stdout.splitlines()
    cli_result = run([args.dav1d, "--version"])
    cli_version = (cli_result.stdout + cli_result.stderr).strip()
    candidates = [(mono, depth, 128, 128, search, False, "square", False) for search, mono, depth in itertools.product((0, 1), (False, True), (8, 10, 12))]
    candidates += [(mono, depth, width, height, 0, True, "rectangle", False) for mono, depth in ((False, 8), (True, 10)) for width, height in ((128, 64), (64, 128))]
    candidates += [(False, 10, 127, 125, 0, False, "crop", False), (True, 12, 127, 125, 0, False, "crop", False)]
    if args.include_source_guided_tx32:
        candidates += [(mono, depth, 128, 128, 1, False, "source_guided_tx32", True) for mono, depth in itertools.product((False, True), (8, 10, 12))]
    if args.include_rectangles_lossless:
        candidates += [(mono, 10, width, height, 1, True, "source_guided_rectangle", True) for mono in (False, True) for width, height in ((128, 64), (64, 128))]
        candidates += [(mono, 10, 128, 128, 0, False, "lossless128", False) for mono in (False, True)]
    if args.include_neutral_chroma_rectangles:
        candidates += [(False, 10, width, height, 1, True, "neutral_chroma_rectangle", True) for width, height in ((128, 64), (64, 128))]
    records, ledger = [], []
    decoder_version = None
    reused_names = set()
    previous_generation = None
    if args.reuse_existing:
        previous = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        verify_existing_artifacts(previous, args.out)
        records, ledger = previous["fixtures"].copy(), previous["candidates"].copy()
        reused_names = {entry["name"] for entry in ledger}
        decoder_version = previous["ffmpeg_decoder_version"]
        previous_generation = previous["generation_command"]
        if previous["encoder_version"] != encoder_version or previous["dav1d_cli_version"] != cli_version:
            raise RuntimeError("reuse requires the recorded encoder and CLI decoder versions")
    for mono, bit_depth, width, height, search, rectangles, kind, disable_tx64 in candidates:
        lossless = kind == "lossless128"
        neutral_chroma = kind == "neutral_chroma_rectangle"
        guided_rectangle = kind in ("source_guided_rectangle", "neutral_chroma_rectangle")
        transform_label = "lossless" if lossless else "neutral_chroma_search" if neutral_chroma else "guided_rect_search" if kind == "source_guided_rectangle" else "search_tx32" if disable_tx64 else "search" if search else "largest"
        name = f"{'mono' if mono else 'color'}_{width}x{height}_{bit_depth}bit_{transform_label}"
        if name in reused_names:
            continue
        if lossless or guided_rectangle:
            source_values, input_pattern = guided_input(width, height, bit_depth, mono, lossless)
            if neutral_chroma:
                midpoint = 1 << (bit_depth - 1)
                source_values[1:] = [[midpoint] * len(values) for values in source_values[1:]]
                input_pattern.update({"chroma_override": "U and V are the native midpoint (1<<(bit_depth-1))", "luma_unchanged_from_monochrome_rectangle": True})
                luma_data = mono_helpers.pack(source_values[0], bit_depth)
                mono_name = f"mono_{width}x{height}_{bit_depth}bit_guided_rect_search"
                prior_mono = next((record for record in records if record["name"] == mono_name), None)
                if prior_mono is None or luma_data != (args.out / prior_mono["source_file"]).read_bytes():
                    raise RuntimeError(f"{name}: controlled luma differs from accepted monochrome source")
                input_pattern["luma_source_sha256"] = sha256(luma_data)
        else:
            source_values = helpers.input_planes(width, height, bit_depth, 1)
            if mono:
                source_values = [source_values[0]]
            input_pattern = {**helpers.INPUT_PATTERN, "amplitude": 1, "monochrome_uses_only_y": mono}
        source_data = helpers.helpers.helpers.pack_planes(source_values, bit_depth)
        source_path = args.out / f"{name}.source.yuv"
        source_path.write_bytes(source_data)
        input_path = source_path
        full_range = mono or lossless
        if full_range:
            input_path = args.out / f"{name}.input.y4m"
            if mono and bit_depth == 8:
                format_name, payload = "mono", source_data
            else:
                format_name = "420" if bit_depth == 8 else f"420p{bit_depth}"
                neutral = [1 << (bit_depth - 1)] * (2 * ((width + 1) // 2) * ((height + 1) // 2))
                payload = source_data + mono_helpers.pack(neutral, bit_depth) if mono else source_data
            input_path.write_bytes(f"YUV4MPEG2 W{width} H{height} F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode() + payload)
        obu_path = args.out / f"{name}.obu"
        reference_path = args.out / f"{name}.reference.yuv"
        unfiltered_path = args.out / f"{name}.unfiltered.yuv"
        template = templates[f"cdef_64x64_1tile_{bit_depth}bit"]
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        encode.insert(1, "--tune-content=screen")
        if mono:
            encode.insert(1, "--monochrome")
        replacements = {"--width": width, "--height": height, "--sb-size": 128,
                        "--min-partition-size": 64 if guided_rectangle else 128, "--max-partition-size": 128,
                        "--enable-rect-partitions": int(rectangles), "--enable-palette": 1,
                        "--enable-directional-intra": 0, "--enable-smooth-intra": 0, "--enable-paeth-intra": 0,
                        "--enable-tx-size-search": search}
        if disable_tx64:
            replacements["--enable-tx64"] = 0
        if lossless:
            replacements.update({"--cq-level": 0, "--lossless": 1})
        for flag, value in replacements.items():
            index = next(index for index, argument in enumerate(encode) if argument.startswith(flag + "="))
            encode[index] = f"{flag}={value}"
        output = encode.index("-o")
        encode[output + 1], encode[output + 2] = str(obu_path), str(input_path)
        run(encode)
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        fields = {field: trace_value(trace, field) for field in ("seq_profile", "high_bitdepth", "max_frame_width_minus_1", "max_frame_height_minus_1", "use_128x128_superblock", "mono_chrome", "color_range", "allow_screen_content_tools", "allow_intrabc", "base_q_idx", "enable_cdef", "tile_cols_log2", "tile_rows_log2", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled", "delta_q_y_dc.delta_coded")}
        if not lossless:
            fields.update({field: trace_value(trace, field) for field in ("tx_mode", "cdef_bits", "cdef_damping_minus_3", "delta_q_present")})
        if lossless and fields["base_q_idx"] != 0:
            raise RuntimeError(f"{name}: encoder did not select qindex zero")
        if fields["use_128x128_superblock"] != 1 or fields["mono_chrome"] != mono or fields["color_range"] != full_range or fields["allow_screen_content_tools"] != 1:
            raise RuntimeError(f"{name}: expected actual SB128, screen-content flag and requested color format")
        if fields["seq_profile"] != (2 if bit_depth == 12 else 0) or fields["high_bitdepth"] != (bit_depth > 8) or fields["max_frame_width_minus_1"] != width - 1 or fields["max_frame_height_minus_1"] != height - 1:
            raise RuntimeError(f"{name}: unexpected profile, depth or visible dimensions")
        if any(fields.get(key, 0) for key in ("allow_intrabc", "tile_cols_log2", "tile_rows_log2", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled", "delta_q_present", "delta_q_y_dc.delta_coded")):
            raise RuntimeError(f"{name}: unexpected unhandled frame syntax")
        loop_levels = [int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]
        if (not lossless and not loop_levels) or any(loop_levels):
            raise RuntimeError(f"{name}: loop filter is not disabled")
        data = obu_path.read_bytes()
        prefix = first_block_prefix(data, trace, width, height, mono, lossless)
        expected_geometry = [128, 64] if width == 128 and height == 64 else [64, 128] if width == 64 and height == 128 else [128, 128]
        reason = None
        if prefix.get("coding_dimensions") != expected_geometry or prefix.get("skip") != 0:
            reason = "encoder_did_not_emit_requested_nonzero_large_block"
        elif search and (fields["tx_mode"] != 2 or prefix["tx_depth"] not in (1, 2)):
            reason = "encoder_did_not_select_depth_1_or_2"
        entry = {"name": name, "category": kind, "requested_search": search, "disable_tx64": disable_tx64, "header_trace": fields,
                 "actual_prefix": prefix, "encoder_command": encode, "trace_command": trace_command,
                 "obu_sha256": sha256(data), "outcome": reason or "accepted"}
        if lossless or guided_rectangle:
            entry.update({"input_pattern": input_pattern, "source_sha256": sha256(source_data), "lossless": lossless})
        ledger.append(entry)
        if reason:
            if kind == "square" and not search:
                raise RuntimeError(f"required base candidate failed: {entry}")
            print(f"candidate {name}: {reason}, actual prefix {prefix}", flush=True)
            # Reproducible commands and hashes remain in the ledger. Discard
            # duplicate optional candidates that did not exercise a new path.
            obu_path.unlink()
            source_path.unlink()
            if input_path != source_path:
                input_path.unlink()
            continue
        pixel_format = ("gray" if bit_depth == 8 else f"gray{bit_depth}le") if mono else ("yuv420p" if bit_depth == 8 else f"yuv420p{bit_depth}le")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(obu_path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(reference_path)]
        result = run(decode)
        versions = re.findall(r"libdav1d\s+([0-9][^\s]*)", result.stderr)
        if not versions or (decoder_version is not None and versions[0] != decoder_version):
            raise RuntimeError("missing or inconsistent libdav1d version")
        decoder_version = versions[0]
        reference = reference_path.read_bytes()
        if lossless and reference != source_data:
            raise RuntimeError(f"{name}: lossless native decoded samples differ from source")
        reference_planes = [mono_helpers.unpack(reference, width * height, bit_depth)] if mono else helpers.unpack_planes(reference, width, height, bit_depth)
        cli_temp = args.out / f"{name}.cli.tmp.yuv"
        cli_all = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_temp), "--limit", "1", "--inloopfilters", "all"]
        helpers.run_binary(cli_all)
        if cli_temp.read_bytes() != reference:
            raise RuntimeError(f"{name}: CLI and FFmpeg native references differ")
        cli_temp.unlink()
        cli_nocdef = cli_all.copy()
        cli_nocdef[cli_nocdef.index("--output") + 1] = str(unfiltered_path)
        cli_nocdef[-1] = "nocdef"
        helpers.run_binary(cli_nocdef)
        raw = unfiltered_path.read_bytes()
        raw_planes = [mono_helpers.unpack(raw, width * height, bit_depth)] if mono else helpers.unpack_planes(raw, width, height, bit_depth)
        chunk_evidence = chunk_residual_evidence(raw_planes, width, height, prefix["tx_depth"], lossless)
        if any(chunk["varying_transforms"] == 0 for chunk in chunk_evidence if not neutral_chroma or chunk["plane"] == 0):
            raise RuntimeError(f"{name}: a plane/chunk lacks proven nonzero AC under DC prediction: {chunk_evidence}")
        if neutral_chroma and any(value != (1 << (bit_depth - 1)) for planes in (reference_planes, raw_planes) for plane in planes[1:] for value in plane):
            raise RuntimeError(f"{name}: neutral chroma reference changed")
        cdef = None
        if not lossless:
            cdef = {"bits": fields["cdef_bits"], "damping_minus_3": fields["cdef_damping_minus_3"],
                    "y_primary": helpers.trace_array(trace, "cdef_y_pri_strength", 1 << fields["cdef_bits"]),
                    "y_secondary_raw": helpers.trace_array(trace, "cdef_y_sec_strength", 1 << fields["cdef_bits"])}
            if not mono:
                cdef["uv_primary"] = helpers.trace_array(trace, "cdef_uv_pri_strength", 1 << fields["cdef_bits"])
                cdef["uv_secondary_raw"] = helpers.trace_array(trace, "cdef_uv_sec_strength", 1 << fields["cdef_bits"])
        avif_path = args.out / f"{name}.avif"
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
        run(wrap)
        avif_temp = args.out / f"{name}.avif.tmp.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1] = str(avif_path)
        decode_avif[-1] = str(avif_temp)
        run(decode_avif)
        if avif_temp.read_bytes() != reference:
            raise RuntimeError(f"{name}: AVIF remux changed native decoded samples")
        avif_temp.unlink()
        gray8_fields = {}
        if mono:
            rgba = mono_helpers.scalar_rgba(avif_path.read_bytes(), scalar)
            gray8 = rgba[0::4]
            if rgba[1::4] != gray8 or rgba[2::4] != gray8 or any(a != 255 for a in rgba[3::4]):
                raise RuntimeError(f"{name}: scalar grayscale oracle is not opaque gray")
            gray8_path = args.out / f"{name}.gray8.scalar.reference"
            gray8_path.write_bytes(gray8)
            gray8_fields = {"gray8_reference_file": gray8_path.name, "gray8_reference_sha256": sha256(gray8)}
        records.append({"name": name, "category": kind, "dimensions": [width, height], "bit_depth": bit_depth, "monochrome": mono,
                        "source_file": source_path.name, "source_sha256": sha256(source_data), "encoder_input_file": input_path.name, "encoder_input_sha256": sha256(input_path.read_bytes()),
                        "input_pattern": input_pattern,
                        "obu_file": obu_path.name, "obu_bytes": len(data), "obu_sha256": sha256(data),
                        "avif_file": avif_path.name, "avif_sha256": sha256(avif_path.read_bytes()), "avif_reference_matches_obu": True,
                        "reference_file": reference_path.name, "reference_sha256": sha256(reference),
                        "unfiltered_file": unfiltered_path.name, "unfiltered_sha256": sha256(raw), "pixel_format": pixel_format,
                        "actual_prefix": prefix, "header_trace": fields, "cdef": cdef, "loop_filter_levels": loop_levels,
                        "nonzero_chunk_evidence": chunk_evidence, "nonzero_evidence_reason": "DC prediction is constant within a transform; visible variation within every reported unfiltered transform proves nonzero AC residual in that plane/chunk",
                        "cdef_changed_samples": sum(a != b for p, q in zip(reference_planes, raw_planes) for a, b in zip(p, q)),
                        **({"neutral_chroma_reference": 1 << (bit_depth - 1), "nonzero_chunk_requirement": "each luma chunk; U/V are independently verified constant midpoint"} if neutral_chroma else {}),
                        **({"lossless_reference_equals_source": True, "lossless_transform": "ONLY_4X4/WHT"} if lossless else {}),
                        **gray8_fields,
                        "commands": {"encode": encode, "trace_headers": trace_command, "decode_reference": decode, "cli_all": cli_all, "cli_nocdef_same_obu": cli_nocdef, "wrap_avif": wrap, "decode_avif_reference": decode_avif}})
        nonzero_chunks = sum(chunk["varying_transforms"] > 0 for chunk in chunk_evidence)
        print(f"accepted {name}: coding={prefix['coding_dimensions']}, tx_mode={prefix['tx_mode']}, tx_depth={prefix['tx_depth']}, CDEF bits={fields.get('cdef_bits', 'absent(lossless)')}, nonzero chunks={nonzero_chunks}/{len(chunk_evidence)}, OBU={len(data)}", flush=True)
    if len(ledger) != len(candidates):
        raise RuntimeError("reuse manifest does not match the requested bounded candidate set")
    source = generated_test(records, args.out)
    args.test.parent.mkdir(parents=True, exist_ok=True)
    args.test.write_text(run([args.moonfmt, "-"], input_text=source).stdout, encoding="utf-8", newline="\n")
    aom_header = Path(args.aomenc).parent.parent / "include" / "aom" / "aomcx.h"
    manifest = {"scope": "verified 128-axis coding blocks, not merely SB128; bounded candidate ledger and original libaom/dav1d pixel references",
                "generation_command": [sys.executable, *sys.argv], "encoder_version": encoder_version, "ffmpeg_version": ffmpeg_version,
                "ffmpeg_decoder_version": decoder_version, "dav1d_cli_version": cli_version,
                "scalar_libavif_version": scalar_version, "scalar_libavif_path": args.libavif_scalar, "mono_gray8_oracle": "actual avifImageYUVToRGB with avoidLibYUV=1, depth=8",
                "candidate_limit": len(candidates), "candidate_count": len(ledger), "accepted_count": len(records),
                "reuse": {"enabled": args.reuse_existing, "verified_existing_candidates": len(reused_names), "previous_generation_command": previous_generation},
                "source_guided_tx32": {"enabled": args.include_source_guided_tx32,
                                       "recipe": "enable-tx-size-search=1 and enable-tx64=0 on the existing square128 configuration",
                                       "source_revision": "v3.6.0 (the installed encoder version)",
                                       "source_evidence": ["aom/aomcx.h AV1E_SET_ENABLE_TX64 disables transforms with either 64-point axis", "av1/encoder/tx_search.c:2877-2883 excludes 64-point candidates when enable_tx64 is false", "av1/encoder/speed_features.c:340 uses square search init_depth=1 for allintra CPU0", "av1/encoder/encodeframe.c:2293-2296 changes an unsplit selected frame to ONLY_LARGEST"],
                                       "source_urls": ["https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/speed_features.c", "https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/tx_search.c", "https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/encodeframe.c"],
                                       "limit": "exactly six appended candidates; original square128 search only considered 64 and 32, so a new texture cannot establish depth2 under those settings"},
                "source_guided_rectangles_lossless": {"enabled": args.include_rectangles_lossless,
                    "recipe": "four 10-bit color/mono 128x64/64x128: min64/max128, rect1, CPU0, tx search1, tx64 disabled, physical16 checkerboard; two color/mono10 lossless128 fullrange ramps: min=max128",
                    "source_revision": "v3.6.0 (the installed encoder version)",
                    "source_evidence": ["av1/encoder/partition_strategy.c:1733-1761 disables rectangle partition when the current square is no larger than min_partition_size; min64 admits rectangles from the root128", "av1/encoder/speed_features.c:1985 retains rectangle search init_depth=0 at CPU0; CPU1 changes it to1 at377", "av1/encoder/tx_search.c:311-330 selects initialization by block shape; with tx64 disabled rectangle search can compare32 and16"],
                    "source_urls": ["https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/partition_strategy.c", "https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/speed_features.c", "https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/tx_search.c"],
                    "limit": "exactly six appended configurations, with independently decoded geometry/depth; edge H/S or V/S remains an encoder RD decision"},
                "neutral_chroma_rectangle_control": {"enabled": args.include_neutral_chroma_rectangles,
                    "recipe": "exactly two 10-bit color128x64/64x128 candidates with the accepted monochrome Y source unchanged and U/V constant512; all other encoder controls unchanged from prior color rectangle attempts",
                    "luma_evidence": "source Y bytes must equal the retained monochrome source; every luma chunk must show nonzero AC in same-OBU unfiltered reference",
                    "chroma_evidence": "every U/V native reference sample must remain512; no claim of nonzero chroma AC for these controlled fixtures"},
                "partition_control_semantics": "min/max constrain both coding-block width and height; minimum admits picture-boundary exceptions; actual first partition is decoded independently",
                "control_primary_source": {"url": "https://aomedia.googlesource.com/aom/+/v3.6.0/aom/aomcx.h", "local_header": str(aom_header), "sha256": sha256(aom_header.read_bytes()), "symbols": ["AV1E_SET_MIN_PARTITION_SIZE", "AV1E_SET_MAX_PARTITION_SIZE"]},
                "prefix_reader": {"implementation": "MsacDecoder from scripts/craft_av1_fixture.py; decoder only", "symbol_order": "root partition/edge gather, skip, CDEF index, DC luma/chroma modes, optional tx_depth", "cdf_context": "first tile block, unavailable top/left, partition and tx-depth context zero"},
                "residual_order": "chunkY -> chunkX -> plane -> transform rows -> transform columns; luma max64, chroma max32",
                "generated_test": str(args.test), "generated_test_sha256": sha256(args.test.read_bytes()), "candidates": ledger, "fixtures": records}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"finished {len(ledger)} bounded candidates: {len(records)} accepted real large-block fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
