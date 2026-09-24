#!/usr/bin/env python3
"""Generate bounded real small AV1 coding-block references without OBU edits.

Color/monochrome x 8/10/12-bit, 16x16 visible dimensions, q30. Independent
Python MSAC reads the first 16->8->4 partition chain and first luma EOB prefix.
Native references must match FFmpeg/libdav1d, dav1d CLI and remuxed AVIF.
RGBA is recorded from actual scalar libavif (avoidLibYUV=1); FFmpeg raw-OBU
RGBA is retained separately so conversion differences are visible.

--append-rectangles-lossless preserves the original six-candidate manifest and
adds exactly eight 10-bit rectangle attempts plus two q0 fixed4 full ramps.
Only genuinely selected HORZ/VERT or HORZ4/VERT4 targets are accepted; rejected
geometries remain in the candidate ledger. Appended tests default to _refs.

--append-constructed appends exactly eight explicitly constructed q0 conformance
streams (color/mono 10-bit x four rectangle geometries). The first color 4x8
pilot must pass both unmodified dav1d decoders before the remaining seven are
constructed. These streams are complete syntax constructions, not aomenc output
or modifications of an existing stream. Every transform contains two AC levels.

White-box RLE is generated from the canonical hashed reference binaries; the
manifest contains metadata and evidence only. This script never runs MoonBit.
--check verifies stored artifact hashes, reconstructs conformance OBU bytes and
checks the canonical prospective MoonBit output without invoking a decoder.
"""

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

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


large = module("small_large_helpers", "generate-av1-large-block-reference.py")
mono_helpers = large.mono_helpers
helpers = large.helpers
arithmetic = large.arithmetic
run, sha256, trace_value, rle = large.run, large.sha256, large.trace_value, large.rle

PARTITION16 = [15597, 20929, 24571, 26706, 27664, 28821, 29601, 30571, 31902, 32768, 0]
PARTITION8 = [19132, 25510, 30392, 32768, 0]
WIDTH = HEIGHT = 16
PATTERN = {
    "name": "strong_2d_gradient_with_small_separable_cosine",
    "base_slope_x_slope_y": [[40, 112, 64], [80, 80, -30], [160, -50, 45]],
    "formula": "round((base + sx*(x+0.5)/plane_width + sy*(y+0.5)/plane_height + 3*cos(pi*(x+0.5)/4)*cos(pi*(y+0.5)/4))*(1<<(bit_depth-8)))",
    "rounding": "Python round, nearest ties to even",
    "color_range": "limited for color, full for monochrome",
}


def source_planes(depth: int, monochrome: bool) -> list[list[int]]:
    output = []
    for plane in range(1 if monochrome else 3):
        size = 16 if plane == 0 else 8
        base, sx, sy = PATTERN["base_slope_x_slope_y"][plane]
        values = [round((base + sx * (x + 0.5) / size + sy * (y + 0.5) / size
                         + 3 * math.cos(math.pi * (x + 0.5) / 4) * math.cos(math.pi * (y + 0.5) / 4))
                        * (1 << (depth - 8))) for y in range(size) for x in range(size)]
        if any(value < 0 or value >= 1 << depth for value in values):
            raise RuntimeError("input pattern outside coded-depth range")
        output.append(values)
    return output


def first_leaf_prefix(data: bytes, trace: str, fields: dict[str, int], *,
                      width: int = 16, target: tuple[int, int] = (4, 4), lossless: bool = False) -> dict[str, object]:
    tile, header_bytes = large.frame_tile(data, trace)
    reader = arithmetic.MsacDecoder(tile, allow_update=not fields["disable_cdf_update"])
    # Nodes larger than the visible 8x8/16x16 square are forced edge SPLIT.
    # They consume no symbols. No block syntax precedes the following reads.
    split16 = reader.symbol(PARTITION16.copy()) if width == 16 else None
    split8 = reader.symbol(PARTITION8.copy()) if width == 8 or split16 == 3 else None
    geometry = ({0: [8, 8], 1: [8, 4], 2: [4, 8], 3: [4, 4]}.get(split8)
                if split8 is not None else {0: [16, 16], 1: [16, 8], 2: [8, 16], 8: [16, 4], 9: [4, 16]}.get(split16))
    result = {"frame_header_bytes": header_bytes, "tile_payload_bytes": len(tile),
              "forced_edge_splits": [64, 32] if width == 16 else [64, 32, 16], "partition16_symbol": split16,
              "partition8_symbol": split8, "first_coding_dimensions": geometry,
              "four_pixel_coding_proven": geometry == [4, 4], "target_coding_proven": geometry == list(target)}
    if not result["target_coding_proven"]:
        return result
    tables = arithmetic.Tables()
    skip = reader.symbol(tables.skip[0])
    result["skip"] = skip
    index = None
    if not skip and fields["enable_cdef"]:
        index = 0
        for _ in range(fields["cdef_bits"]):
            index = index * 2 + reader.bool()
    result["cdef_index"] = index
    mode = reader.symbol(tables.y_mode[0][0])
    block_index = {(4, 4): 0, (4, 8): 1, (8, 4): 2, (4, 16): 16, (16, 4): 17}[target]
    angle_present = block_index >= 3 and 1 <= mode <= 8
    if angle_present:
        delta = reader.symbol(arithmetic._parse_go_table("DefaultAngleDeltaCdf")[mode - 1]) - 3
        result["angle_delta"] = delta
        if delta:
            raise RuntimeError("angle-delta-disabled candidate emitted a nonzero delta")
    palette_present = bool(fields["allow_screen_content_tools"] and block_index >= 3 and mode == 0)
    if palette_present:
        context = target[0].bit_length() + target[1].bit_length() - 8
        if reader.symbol(arithmetic._parse_go_table("DefaultPaletteYModeCdf")[context][0]):
            raise RuntimeError("palette-disabled candidate emitted a palette")
    result.update({"y_mode": mode, "angle_syntax_present": angle_present,
                   "uv_syntax_present": False, "palette_syntax_present": False,
                   "tx_depth_syntax_present": False, "first_nonzero_ac_proven": False})
    result["palette_syntax_present"] = palette_present
    if skip:
        return result
    qctx = tables.qctx(fields["base_q_idx"])
    tx_context = 0 if lossless else (target[0].bit_length() - 3 + target[1].bit_length() - 3 + 1) // 2
    skip_context = 1 if lossless and target != (4, 4) else 0
    all_zero = reader.symbol(tables.txb_skip[qctx][tx_context][skip_context])
    result["all_zero"] = all_zero
    if all_zero:
        return result
    if lossless:
        tx_symbol, tx_type = None, 0
    elif fields["reduced_tx_set"]:
        tx_symbol = reader.symbol(tables.intra_tx_set2[0][mode])
        tx_type = (9, 0, 3, 1, 2)[tx_symbol]
    else:
        tx_symbol = reader.symbol(tables.intra_tx_set1[0][mode])
        tx_type = (9, 0, 10, 11, 3, 1, 2)[tx_symbol]
    eob_tables = {16: tables.eob_pt_16, 32: arithmetic._parse_go_table("DefaultEobPt32Cdf"), 64: tables.eob_pt_64}
    eob_pt = reader.symbol(eob_tables[16 if lossless else target[0] * target[1]][qctx][0][int(tx_type in (10, 11))]) + 1
    result.update({"tx_type_symbol": tx_symbol, "tx_type": tx_type, "eob_pt": eob_pt,
                   "first_nonzero_ac_proven": eob_pt > 1,
                   "ac_evidence": "EOB position exceeds the scan's DC position in the first real 4x4 transform"})
    return result


def native_planes(data: bytes, depth: int, monochrome: bool, width: int = 16, height: int = 16) -> list[list[int]]:
    return [mono_helpers.unpack(data, width * height, depth)] if monochrome else helpers.unpack_planes(data, width, height, depth)


def additional_candidates() -> list[dict[str, object]]:
    candidates = []
    for monochrome, target in itertools.product((False, True), ((4, 8), (8, 4), (4, 16), (16, 4))):
        size = max(target)
        candidates.append({"monochrome": monochrome, "depth": 10, "width": size, "height": size,
                           "target": target, "quantizer": 30, "kind": "rectangle"})
    candidates += [{"monochrome": monochrome, "depth": 10, "width": 16, "height": 16,
                    "target": (4, 4), "quantizer": 0, "kind": "lossless"} for monochrome in (False, True)]
    return candidates


def additional_source(candidate: dict[str, object]) -> tuple[list[list[int]], dict[str, object]]:
    depth, mono = candidate["depth"], candidate["monochrome"]
    width, height = candidate["width"], candidate["height"]
    target_w, target_h = candidate["target"]
    lossless = candidate["quantizer"] == 0
    planes = []
    for plane in range(1 if mono else 3):
        pw, ph = (width, height) if plane == 0 else (width // 2, height // 2)
        if lossless:
            count, maximum = pw * ph, (1 << depth) - 1
            values = [round(((i + plane * 7) % count) * maximum / (count - 1)) for i in range(count)]
        elif plane > 0:
            values = [1 << (depth - 1)] * (pw * ph)
        else:
            values = []
            for y in range(ph):
                for x in range(pw):
                    stripe = (x // 4) if target_w == 4 else (y // 4)
                    base = 64 if stripe % 2 == 0 else 192
                    ac = 4 * math.cos(math.pi * ((x % target_w) + 0.5) / target_w) * math.cos(math.pi * ((y % target_h) + 0.5) / target_h)
                    values.append(round((base + ac) * (1 << (depth - 8))))
        planes.append(values)
    pattern = ({"name": "native_full_range_ramp", "formula": "round(((i+plane*7)%count)*((1<<bit_depth)-1)/(count-1))"}
               if lossless else {"name": "four_pixel_stripes_with_local_cosine", "target_cell": list(candidate["target"]),
                    "formula": "round((base+4*cos(pi*((x%target_w)+0.5)/target_w)*cos(pi*((y%target_h)+0.5)/target_h))*(1<<(bit_depth-8)))",
                    "base": "64/192 alternates every4 luma pixels along the short coding axis", "chroma": "neutral native midpoint"})
    return planes, pattern


def generated_test(records: list[dict[str, object]], directory: Path) -> str:
    text = """/// Generated by scripts/generate-av1-small-block-reference.py.
/// Stock libaom fixed4 and explicitly constructed rectangle conformance streams.
/// All expected native planes come from unmodified dav1d decoders.
/// Color RGBA uses the established nearest-420 conversion contract; monochrome
/// RGBA is compared with actual scalar libavif full-range UNORM conversion.
fn av1_small_reference_expand(runs : Array[Int]) -> Array[Int] {
  let values : Array[Int] = []
  for i in 0..<(runs.length() / 2) {
    for _ in 0..<runs[i * 2 + 1] { values.push(runs[i * 2]) }
  }
  values
}

///|
fn av1_small_reference_compare(stream : Array[Byte], avif : Array[Byte], mono : Bool,
  depth : Int, width : Int, height : Int, planes : Array[Array[Int]], rgba_runs : Array[Int]) -> Unit raise {
  let frame = av1_decode_frame_planes(stream, allow_monochrome=mono).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, depth))
  assert_eq(frame.planes.length(), planes.length())
  let references : Array[Array[Int]] = []
  for plane in 0..<planes.length() {
    let expected = av1_small_reference_expand(planes[plane])
    references.push(expected)
    assert_eq(av1_frame_crop(frame, plane), expected)
  }
  let raw = av1_decode(stream).unwrap()
  let container = avif_decode_rgba(avif).unwrap()
  assert_eq((raw.width, raw.height, container.width, container.height), (width, height, width, height))
  if mono {
    let rgba = av1_small_reference_expand(rgba_runs)
    assert_eq(rgba.length(), width * height * 4)
    for i in 0..<(width * height) {
      let expected = (rgba[i*4].to_byte(), rgba[i*4+1].to_byte(), rgba[i*4+2].to_byte(), rgba[i*4+3].to_byte())
      assert_eq(raw.get_pixel(i % width, i / width), expected)
      assert_eq(container.get_pixel(i % width, i / width), expected)
    }
  } else {
    let expected = av1_yuv420_highbd_to_rgba(width, height, references[0], references[1], references[2], depth,
      full_range=frame.full_range, matrix_coefficients=frame.matrix_coefficients).unwrap()
    for y in 0..<height { for x in 0..<width {
      assert_eq(raw.get_pixel(x, y), expected.get_pixel(x, y))
      assert_eq(container.get_pixel(x, y), expected.get_pixel(x, y))
    } }
  }
}
"""
    for record in records:
        text += f'\n///|\ntest "external small coding block {record["name"]}" {{\n'
        for variable, field in (("stream", "obu_file"), ("avif", "avif_file")):
            data = (directory / record[field]).read_bytes()
            text += f"let {variable} : Array[Byte] = [" + ",".join(f"b'\\x{x:02X}'" for x in data) + "]\n"
        reference = (directory / record["reference_file"]).read_bytes()
        rgba = (directory / record["rgba_reference_file"]).read_bytes()
        if sha256(reference) != record["reference_sha256"] or sha256(rgba) != record["rgba_reference_sha256"]:
            raise RuntimeError(f"{record['name']}: canonical reference hash mismatch")
        width, height = record["dimensions"]
        planes = native_planes(reference, record["bit_depth"], record["monochrome"], width, height)
        text += "let planes : Array[Array[Int]] = " + json.dumps([rle(plane) for plane in planes]) + "\n"
        text += "let rgba : Array[Int] = " + json.dumps(rle(list(rgba))) + "\n"
        text += f'av1_small_reference_compare(stream, avif, {str(record["monochrome"]).lower()}, {record["bit_depth"]}, {width}, {height}, planes, rgba)\n}}\n'
    return text


def constructed_headers(size: int, monochrome: bool) -> tuple[bytes, bytes]:
    """AV1 sections 5.5.1/5.5.2/5.9.2, reduced still, profile0 10-bit q0.

    Mono color_config returns before separate_uv_delta_q. At q0, delta_q_params,
    loop_filter_params and read_tx_mode consume no bits. The FRAME header uses
    zero byte_alignment; the sequence header uses trailing_bits.
    """
    bw = arithmetic.BitWriter()
    dimension_bits = (size - 1).bit_length()
    for value, bits in ((0, 3), (1, 1), (1, 1), (0, 5),
                        (dimension_bits - 1, 4), (dimension_bits - 1, 4),
                        (size - 1, dimension_bits), (size - 1, dimension_bits)):
        bw.f(value, bits)
    for _ in range(6):
        bw.f(0, 1)  # SB128, filter intra, edge filter, superres, CDEF, restoration.
    bw.f(1, 1)  # high_bitdepth (profile0 => 10-bit).
    bw.f(int(monochrome), 1)
    bw.f(0, 1)  # color_description_present_flag => unspecified matrix2.
    bw.f(1, 1)  # full color range for both color and mono.
    if not monochrome:
        bw.f(0, 2)  # chroma_sample_position, profile0 implies 4:2:0.
        bw.f(0, 1)  # separate_uv_delta_q.
    bw.f(0, 1)  # film_grain_params_present.
    bw.trailing()
    sequence = bw.to_bytes()
    bw = arithmetic.BitWriter()
    for value in (0, 0, 0, 1):
        bw.f(value, 1)  # disable CDF update, screen tools, render size, uniform tiles.
    bw.f(0, 8)  # base_q_idx.
    bw.f(0, 1)  # delta_q_y_dc.delta_coded.
    if not monochrome:
        bw.f(0, 1)  # delta_q_u_dc.delta_coded.
        bw.f(0, 1)  # delta_q_u_ac.delta_coded; V deltas inherited.
    bw.f(0, 1)  # using_qmatrix.
    bw.f(0, 1)  # segmentation_enabled.
    bw.f(0, 1)  # reduced_tx_set; tx_mode is inferred ONLY_4X4.
    while len(bw.bits) % 8:
        bw.f(0, 1)
    return sequence, bw.to_bytes()


def constructed_stream(target: tuple[int, int], monochrome: bool) -> tuple[bytes, dict[str, object]]:
    """Write complete normative syntax; no MoonBit implementation is consulted.

    Context/order sources: AV1 5.11.2, 5.11.34, 5.11.39 and 8.3; independently
    inspected go-av1 decode/{block,residual,coeff}.go. The reused arithmetic
    coder is the od_ec encoder port documented in craft_av1_fixture.py.
    """
    class CheckedEncoder(arithmetic.MsacEncoder):
        def __init__(self):
            super().__init__()
            self.symbols = []

        def encode_symbol(self, cdf, symbol):
            self.symbols.append((cdf.copy(), symbol))
            super().encode_symbol(cdf, symbol)

    bw, bh = target
    size = max(target)
    enc, tables = CheckedEncoder(), arithmetic.Tables()
    partition = (2 if bw == 4 else 1) if size == 8 else (9 if bw == 4 else 8)
    enc.encode_symbol((PARTITION8 if size == 8 else PARTITION16).copy(), partition)
    count = size // 4
    top_level = [[0] * (size // 4) for _ in range(3)]
    left_level = [[0] * (size // 4) for _ in range(3)]
    top_dc = [[0] * (size // 4) for _ in range(3)]
    left_dc = [[0] * (size // 4) for _ in range(3)]
    blocks = []
    # HORZ/VERT and HORZ_4/VERT_4 encode leaves in top-to-bottom/left-to-right
    # order. Blocks have skip0/DC mode, so all skip/Y-neighbor contexts are0.
    for block_index in range(count):
        x, y = (block_index * 4, 0) if bw == 4 else (0, block_index * 4)
        owner = not monochrome and ((x // 4) % 2 == 1 if bw == 4 else (y // 4) % 2 == 1)
        enc.encode_symbol(tables.skip[0], 0)
        enc.encode_symbol(tables.y_mode[0][0], 0)
        if owner:
            # Lossless CfL availability uses the full chroma residual size,
            # not the forced 4x4 transform size.
            enc.encode_symbol((tables.uv_mode_cfl if size == 8 else tables.uv_mode)[0], 0)
        block = {"origin": [x, y], "dimensions": [bw, bh], "has_chroma": owner,
                 "skip": 0, "y_mode": 0, "uv_mode": 0 if owner else None,
                 "cfl_allowed": size == 8 if owner else None, "transforms": []}
        for plane in range(3 if owner else 1):
            pw, ph = (bw, bh) if plane == 0 else (max(4, bw // 2), max(4, bh // 2))
            px, py = (x, y) if plane == 0 else ((x // 8) * 4, (y // 8) * 4)
            for ty in range(0, ph, 4):
                for tx in range(0, pw, 4):
                    x4, y4 = (px + tx) // 4, (py + ty) // 4
                    top, left = top_level[plane][x4], left_level[plane][y4]
                    if plane == 0:
                        context = arithmetic.txb_skip_ctx_luma(top, left, False)
                    else:
                        context = (7 if pw * ph == 16 else 10) + int(top != 0) + int(left != 0)
                    enc.encode_symbol(tables.txb_skip[0][0][context], 0)
                    score = sum(-1 if value == 1 else 1 if value == 2 else 0
                                for value in (top_dc[plane][x4], left_dc[plane][y4]))
                    dc_context = 1 if score < 0 else 2 if score > 0 else 0
                    # Existing coefficient helper's base-only path is exact for
                    # levels1/2. Level3 would require a coeff_br symbol; avoid it.
                    levels = {0: 2, 1: 2, 4: 2}
                    cumulative, dc_category = arithmetic.encode_leaf_coeffs(
                        enc, tables, 0, 4, int(plane != 0), levels, 0, dc_context)
                    top_level[plane][x4] = left_level[plane][y4] = cumulative
                    top_dc[plane][x4] = left_dc[plane][y4] = dc_category
                    block["transforms"].append({"plane": plane, "origin": [px + tx, py + ty],
                        "size": [4, 4], "inverse_transform": "WHT", "all_zero_context": context,
                        "dc_sign_context": dc_context, "eob": 3, "positive_quantized_levels": [[0, 2], [1, 2], [4, 2]]})
        blocks.append(block)
    tile = enc.finish()
    # Roundtrip all entropy events with the independent decoder dual. This
    # checks encoder arithmetic; external decoders below validate AV1 semantics.
    reader = arithmetic.MsacDecoder(tile)
    for cdf, expected in enc.symbols:
        if reader.symbol(cdf) != expected:
            raise RuntimeError("constructed entropy arithmetic roundtrip failed")
    sequence, frame_header = constructed_headers(size, monochrome)
    stream = arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame_header + tile)
    return stream, {"provenance": "complete constructed AV1 syntax, not libaom encoder output",
        "partition_symbol": partition, "partition_name": {1: "HORZ", 2: "VERT", 8: "HORZ_4", 9: "VERT_4"}[partition],
        "target_coding_dimensions": list(target), "blocks": blocks, "entropy_symbol_count": len(enc.symbols),
        "entropy_roundtrip": "all emitted symbols checked with MsacDecoder; external dav1d validates syntax semantics",
        "frame_header_bytes": len(frame_header), "tile_payload_bytes": len(tile)}


def append_constructed(args) -> int:
    previous = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    large.verify_existing_artifacts(previous, args.out)
    if len(previous["candidates"]) != 16 or len(previous["fixtures"]) != 8:
        raise RuntimeError("constructed append requires the preserved 16 candidates and 8 stock references")
    published = Path(previous["generated_test"])
    if sha256(published.read_bytes()) != previous["generated_test_sha256"]:
        raise RuntimeError("published stock tests differ from their recorded hash")
    test_path = args.test or ROOT / "_refs/av1_small_block_reference_wbtest.mbt"
    if test_path.resolve() == published.resolve():
        raise RuntimeError("constructed tests must remain prospective under _refs")
    scalar, scalar_version = mono_helpers.scalar_library(args.libavif_scalar)
    dav1d_version = run([args.dav1d, "--version"])
    versions = {"ffmpeg": run([args.ffmpeg, "-version"]).stdout.splitlines()[0],
                "dav1d_cli": (dav1d_version.stdout + dav1d_version.stderr).strip(),
                "scalar_libavif": scalar_version}
    records, ledger = previous["fixtures"].copy(), previous["candidates"].copy()
    # Pilot is first and every external validation must finish before the next
    # stream is constructed. No existing stock stream is rewritten.
    for monochrome, target in itertools.product((False, True), ((4, 8), (8, 4), (4, 16), (16, 4))):
        size, depth = max(target), 10
        name = f"constructed_{'mono' if monochrome else 'color'}_{size}x{size}_10bit_{target[0]}x{target[1]}_q0"
        stream, syntax = constructed_stream(target, monochrome)
        obu_path = args.out / f"{name}.obu"
        if obu_path.exists() and obu_path.read_bytes() != stream:
            raise RuntimeError(f"{name}: construction differs from the existing pilot bytes")
        obu_path.write_bytes(stream)
        syntax_path = args.out / f"{name}.syntax.json"
        syntax_path.write_text(json.dumps(syntax, indent=2) + "\n", encoding="utf-8", newline="\n")
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        trace_path = args.out / f"{name}.trace.txt"
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        fields = {field: trace_value(trace, field) for field in (
            "seq_profile", "high_bitdepth", "mono_chrome", "color_range", "reduced_still_picture_header",
            "max_frame_width_minus_1", "max_frame_height_minus_1", "use_128x128_superblock",
            "allow_screen_content_tools", "disable_cdf_update", "base_q_idx", "enable_cdef", "enable_restoration",
            "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled",
            "delta_q_y_dc.delta_coded", "reduced_tx_set", "tile_cols_log2", "tile_rows_log2")}
        expected = {field: 0 for field in fields}
        expected.update({"high_bitdepth": 1, "mono_chrome": int(monochrome), "color_range": 1,
                         "reduced_still_picture_header": 1, "max_frame_width_minus_1": size - 1,
                         "max_frame_height_minus_1": size - 1})
        if fields != expected:
            raise RuntimeError(f"{name}: constructed header differs from requested profile0/10-bit/q0 tools: {fields}")
        fields.update({"tx_mode": 0, "delta_q_present": 0, "allow_intrabc": 0})
        prefix = first_leaf_prefix(stream, trace, fields, width=size, target=target, lossless=True)
        if not prefix["target_coding_proven"] or prefix.get("eob_pt") != 3 or prefix.get("skip") != 0:
            raise RuntimeError(f"{name}: independent first partition/AC prefix failed: {prefix}")
        pixel_format = "gray10le" if monochrome else "yuv420p10le"
        reference_path = args.out / f"{name}.reference.yuv"
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-xerror", "-y", "-c:v", "libdav1d", "-i", str(obu_path),
                  "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(reference_path)]
        decoded = run(decode)
        decoder_version = re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)[0]
        if versions.setdefault("ffmpeg_libdav1d", decoder_version) != decoder_version:
            raise RuntimeError("inconsistent decoder version")
        reference = reference_path.read_bytes()
        planes = native_planes(reference, depth, monochrome, size, size)
        cli_path = args.out / f"{name}.cli.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv",
               "--output", str(cli_path), "--limit", "1", "--inloopfilters", "all"]
        helpers.run_binary(cli)
        if cli_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: unmodified dav1d decoders disagree on complete native planes")
        cli_path.unlink()
        # Check every coded transform, including every UV owner, has within-TX
        # variation in the external output. A block-level DC step is insufficient.
        for block in syntax["blocks"]:
            for transform in block["transforms"]:
                plane = transform["plane"]
                x, y = transform["origin"]
                stride = size if plane == 0 else size // 2
                pixels = [planes[plane][(y + dy) * stride + x + dx] for dy in range(4) for dx in range(4)]
                if len(set(pixels)) <= 1:
                    raise RuntimeError(f"{name}: transform {plane,x,y} has no visible AC variation")
        avif_path = args.out / f"{name}.avif"
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
        run(wrap)
        avif_native_path = args.out / f"{name}.avif.native.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1] = str(avif_path)
        decode_avif[-1] = str(avif_native_path)
        run(decode_avif)
        if avif_native_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: AVIF remux changes native samples")
        avif_native_path.unlink()
        scalar_rgba = mono_helpers.scalar_rgba(avif_path.read_bytes(), scalar)
        scalar_path = args.out / f"{name}.scalar_libavif.rgba"
        scalar_path.write_bytes(scalar_rgba)
        if len(scalar_rgba) != size * size * 4 or any(value != 255 for value in scalar_rgba[3::4]):
            raise RuntimeError(f"{name}: invalid scalar RGBA size/alpha")
        if monochrome and not (scalar_rgba[0::4] == scalar_rgba[1::4] == scalar_rgba[2::4]):
            raise RuntimeError(f"{name}: scalar monochrome is not gray")
        raw_rgba_path = args.out / f"{name}.raw_ffmpeg.rgba"
        decode_rgba = decode.copy()
        decode_rgba[decode_rgba.index("-pix_fmt") + 1] = "rgba"
        decode_rgba[-1] = str(raw_rgba_path)
        run(decode_rgba)
        raw_rgba = raw_rgba_path.read_bytes()
        if len(raw_rgba) != len(scalar_rgba):
            raise RuntimeError(f"{name}: invalid FFmpeg RGBA size")
        record = {"name": name, "provenance": syntax["provenance"], "dimensions": [size, size],
            "bit_depth": depth, "monochrome": monochrome, "quantizer": 0, "lossless": True,
            "source_image": None, "source_image_note": "syntax fixture; native decoder output is the canonical reference, not an encoder input",
            "target_coding_dimensions": list(target), "actual_prefix": prefix, "header_trace": fields,
            "cdef": None, "loop_filter_levels": [], "allowed_predictors": ["DC"],
            "native_pixel_format": pixel_format, "native_cli_matches_ffmpeg": True, "avif_native_matches_obu": True,
            "nonconstant_transform_count": sum(len(block["transforms"]) for block in syntax["blocks"]),
            "uv_owner_count": sum(block["has_chroma"] for block in syntax["blocks"]),
            "every_transform_has_nonzero_ac_and_native_variation": True,
            "native_plane_ranges": [[min(plane), max(plane)] for plane in planes],
            "rgba_assertion_contract": "actual scalar libavif full-range UNORM" if monochrome else "av1_yuv420_highbd_to_rgba from exact native reference planes using decoded sequence range/matrix; nearest420 entry propagation",
            "vendor_rgb_parity_asserted": monochrome,
            "scalar_rgba_conversion": "actual avifImageYUVToRGB, output depth8, avoidLibYUV=1",
            "raw_ffmpeg_vs_scalar_differing_bytes": sum(a != b for a, b in zip(raw_rgba, scalar_rgba)),
            "commands": {"trace": trace_command, "decode_native": decode, "dav1d_cli": cli, "wrap_avif": wrap,
                         "decode_avif_native": decode_avif, "decode_raw_rgba": decode_rgba}}
        for key, path in (("obu", obu_path), ("avif", avif_path), ("syntax", syntax_path), ("reference", reference_path),
                          ("rgba_reference", scalar_path), ("raw_rgba", raw_rgba_path), ("trace", trace_path)):
            record[key + "_file"], record[key + "_sha256"] = path.name, sha256(path.read_bytes())
        records.append(record)
        ledger.append({"name": name, "kind": "constructed_q0_rectangle", "provenance": syntax["provenance"],
            "dimensions": [size, size], "bit_depth": 10, "monochrome": monochrome, "quantizer": 0,
            "target_coding_dimensions": list(target), "actual_prefix": prefix,
            "obu_file": obu_path.name, "obu_sha256": sha256(stream),
            "syntax_file": syntax_path.name, "syntax_sha256": sha256(syntax_path.read_bytes()), "outcome": "accepted"})
        print(f"accepted {name}: partition={syntax['partition_name']} native={len(reference)} bytes, nonconstantTX={record['nonconstant_transform_count']}, UVowners={record['uv_owner_count']}", flush=True)
    if len(ledger) != 24 or len(records) != 16:
        raise RuntimeError("constructed append exceeded or missed exactly eight cases")
    large.verify_existing_artifacts(previous, args.out)
    if sha256(published.read_bytes()) != previous["generated_test_sha256"]:
        raise RuntimeError("published stock tests changed during construction")
    manifest = previous.copy()
    manifest.update({"scope": "six fixed4 originals, ten stock rectangle/q0 candidates, eight constructed q0 rectangle conformance streams",
        "candidate_count": len(ledger), "candidate_limit": 24, "accepted_count": len(records),
        "candidates": ledger, "fixtures": records, "fixture_test_status": "8 stock tests published; constructed tests prospective under _refs",
        "prefix_evidence": "per-candidate independent MSAC first partition and EOB prefix; fixed4 requires SPLIT while constructed rectangles require their exact HORZ/VERT/HORZ_4/VERT_4 symbol",
        "prefix_reader_source": "scripts/craft_av1_fixture.py MsacDecoder; stock streams use decoder only, explicitly constructed streams also use its encoder primitives",
        "constructed_scope": {"count": 8, "targets": [[4, 8], [8, 4], [4, 16], [16, 4]], "monochrome": [False, True],
            "bit_depth": 10, "quantizer": 0, "pilot": "color4x8 passed both unmodified dav1d decoders before remaining seven",
            "generation_command": [sys.executable, *sys.argv], "versions": versions,
            "source": "complete syntax construction with existing MsacEncoder/BitWriter/Tables/encode_leaf_coeffs primitives; no SDK and no edited encoder entropy",
            "references": ["https://aomediacodec.github.io/av1-spec/av1-spec.html",
                           "_refs/go-av1/decode/block.go", "_refs/go-av1/decode/residual.go", "_refs/go-av1/decode/coeff.go"],
            "support_hashes": {str(path.relative_to(ROOT)).replace("\\", "/"): sha256(path.read_bytes()) for path in (
                Path(__file__), ROOT / "scripts/craft_av1_fixture.py", ROOT / "_refs/go-av1/cdf/tables_gen.go",
                ROOT / "_refs/go-av1/cdf/tables_coeff_gen.go", ROOT / "_refs/go-av1/cdf/tables_coeff2_gen.go",
                ROOT / "_refs/go-av1/cdf/tables_txeob_gen.go")}}})
    formatted = run([args.moonfmt, "-"], input_text=generated_test(records, args.out)).stdout
    test_path.write_text(formatted, encoding="utf-8", newline="\n")
    manifest["prospective_test"], manifest["prospective_test_sha256"] = str(test_path), sha256(test_path.read_bytes())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("wrote 8 constructed references; all 16 previous candidate records and 8 stock references preserved")
    return 0


def check_references(args) -> int:
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    for record in manifest["fixtures"] + manifest["candidates"]:
        for key, filename in record.items():
            if key.endswith("_file") and key[:-5] + "_sha256" in record:
                if sha256((args.out / filename).read_bytes()) != record[key[:-5] + "_sha256"]:
                    raise RuntimeError(f"artifact hash mismatch: {filename}")
    for key in ("generated_test", "prospective_test"):
        if key in manifest and sha256(Path(manifest[key]).read_bytes()) != manifest[key + "_sha256"]:
            raise RuntimeError(f"test hash mismatch: {manifest[key]}")
    constructed = [record for record in manifest["fixtures"] if record.get("provenance", "").startswith("complete constructed")]
    for record in constructed:
        stream, syntax = constructed_stream(tuple(record["target_coding_dimensions"]), record["monochrome"])
        if stream != (args.out / record["obu_file"]).read_bytes():
            raise RuntimeError(f"constructed OBU regeneration mismatch: {record['name']}")
        if syntax != json.loads((args.out / record["syntax_file"]).read_text(encoding="utf-8")):
            raise RuntimeError(f"constructed syntax regeneration mismatch: {record['name']}")
    for filename, expected in manifest.get("constructed_scope", {}).get("support_hashes", {}).items():
        if sha256((ROOT / filename).read_bytes()) != expected:
            raise RuntimeError(f"construction support source changed: {filename}")
    target = args.test or Path(manifest.get("prospective_test", manifest["generated_test"]))
    formatted = run([args.moonfmt, "-"], input_text=generated_test(manifest["fixtures"], args.out)).stdout
    if target.read_text(encoding="utf-8") != formatted:
        raise RuntimeError(f"canonical generated test mismatch: {target}")
    print(f"checked {len(manifest['candidates'])} candidates, {len(manifest['fixtures'])} references, {len(constructed)} reconstructed streams and canonical tests")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-small-block")
    parser.add_argument("--test", type=Path)
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe") or "ffprobe")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--reuse-encoded", action="store_true", help="reuse existing candidate OBUs after an interrupted reference-generation run")
    parser.add_argument("--append-rectangles-lossless", action="store_true", help="preserve the six fixed4 fixtures and append exactly eight rectangle plus two q0 candidates")
    parser.add_argument("--append-constructed", action="store_true", help="append exactly eight q0 rectangle conformance streams after a dual-decoder pilot")
    parser.add_argument("--check", action="store_true", help="verify hashes, deterministic constructed streams and canonical test output; no decoders or encoders")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.check:
        return check_references(args)
    if args.append_constructed:
        return append_constructed(args)
    scalar, scalar_version = mono_helpers.scalar_library(args.libavif_scalar)
    encoder_help = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", encoder_help.stdout + encoder_help.stderr).group(0)
    dav1d_result = run([args.dav1d, "--version"])
    versions = {"encoder_version": encoder_version,
                "ffmpeg_version": run([args.ffmpeg, "-version"]).stdout.splitlines()[0],
                "dav1d_cli_version": (dav1d_result.stdout + dav1d_result.stderr).strip(),
                "scalar_libavif_version": scalar_version, "scalar_libavif_path": args.libavif_scalar}
    records, ledger = [], []
    previous = None
    if args.append_rectangles_lossless:
        previous = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        large.verify_existing_artifacts(previous, args.out)
        records, ledger = previous["fixtures"].copy(), previous["candidates"].copy()
        if len(ledger) != 6:
            raise RuntimeError("the bounded append requires exactly the original six-candidate manifest")
        if previous["encoder_version"] != encoder_version or previous["dav1d_cli_version"] != versions["dav1d_cli_version"]:
            raise RuntimeError("appending requires the recorded encoder and decoder versions")
        candidates = additional_candidates()
        if args.test is None:
            args.test = ROOT / "_refs/av1_small_block_reference_wbtest.mbt"
    else:
        candidates = [{"monochrome": mono, "depth": depth, "width": 16, "height": 16,
                       "target": (4, 4), "quantizer": 30, "kind": "fixed4"}
                      for mono, depth in itertools.product((False, True), (8, 10, 12))]
        if args.test is None:
            args.test = ROOT / "av1_small_block_reference_wbtest.mbt"
    for candidate in candidates:
        monochrome, depth = candidate["monochrome"], candidate["depth"]
        width, height, target = candidate["width"], candidate["height"], candidate["target"]
        quantizer, kind = candidate["quantizer"], candidate["kind"]
        lossless, rectangles = quantizer == 0, kind == "rectangle"
        extended = rectangles and width == 16
        label = f"target{target[0]}x{target[1]}" if rectangles else "fixed4"
        name = f"{'mono' if monochrome else 'color'}_{width}x{height}_{depth}bit_{label}_q{quantizer}"
        values, pattern = additional_source(candidate) if kind != "fixed4" else (source_planes(depth, monochrome), PATTERN)
        source = b"".join(mono_helpers.pack(plane, depth) for plane in values)
        source_path = args.out / f"{name}.source.yuv"
        source_path.write_bytes(source)
        input_path = source_path
        full_range = monochrome or lossless
        if full_range:
            input_path = args.out / f"{name}.input.y4m"
            format_name = "mono" if monochrome and depth == 8 else "420" if depth == 8 else f"420p{depth}"
            payload = source if not monochrome or depth == 8 else source + mono_helpers.pack([1 << (depth - 1)] * (width * height // 2), depth)
            input_path.write_bytes(f"YUV4MPEG2 W{width} H{height} F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode() + payload)
        obu_path = args.out / f"{name}.obu"
        encode = [args.aomenc, "--enable-diagonal-intra=0", "--debug", "--disable-warning-prompt", "--allintra", "--obu", "--i420",
                  f"--width={width}", f"--height={height}", f"--profile={2 if depth == 12 else 0}", f"--bit-depth={depth}", f"--input-bit-depth={depth}",
                  "--fps=1/1", "--limit=1", "--cpu-used=0", "--threads=1", "--end-usage=q", f"--cq-level={quantizer}", f"--lossless={int(lossless)}",
                  "--sb-size=64", "--tile-columns=0", "--tile-rows=0", "--aq-mode=0", "--deltaq-mode=0", "--enable-chroma-deltaq=0", "--enable-qm=0",
                  "--enable-cdef=0", "--enable-restoration=0", "--enable-filter-intra=0", "--enable-intra-edge-filter=0", "--enable-angle-delta=0",
                  f"--enable-rect-partitions={int(rectangles)}", f"--enable-1to4-partitions={int(extended)}", "--enable-ab-partitions=0", "--enable-smooth-intra=1", "--enable-paeth-intra=1",
                  "--enable-palette=0", "--enable-flip-idtx=0", "--enable-tx64=1", "--enable-tx-size-search=0", "--use-intra-default-tx-only=1",
                  "--min-partition-size=4", f"--max-partition-size={width if rectangles else 4}", "--enable-directional-intra=1", "--enable-cfl-intra=0", "--enable-intrabc=0",
                  "--loopfilter-control=0", "-o", str(obu_path), str(input_path)]
        if monochrome:
            encode.insert(1, "--monochrome")
        if not args.reuse_encoded or not obu_path.exists():
            run(encode)
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        trace_path = args.out / f"{name}.trace.txt"
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        fields = {field: trace_value(trace, field) for field in (
            "seq_profile", "high_bitdepth", "mono_chrome", "color_range", "reduced_still_picture_header", "max_frame_width_minus_1", "max_frame_height_minus_1",
            "use_128x128_superblock", "allow_screen_content_tools", "disable_cdf_update", "base_q_idx", "enable_cdef",
            "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled",
            "delta_q_y_dc.delta_coded", "reduced_tx_set", "tile_cols_log2", "tile_rows_log2")}
        fields["tx_mode"] = 0 if lossless else trace_value(trace, "tx_mode")
        fields["delta_q_present"] = 0 if lossless else trace_value(trace, "delta_q_present")
        fields["allow_intrabc"] = trace_value(trace, "allow_intrabc") if fields["allow_screen_content_tools"] else 0
        if fields["mono_chrome"] != monochrome or fields["color_range"] != full_range or fields["max_frame_width_minus_1"] != width - 1 or fields["max_frame_height_minus_1"] != height - 1:
            raise RuntimeError(f"{name}: unexpected actual dimensions/color format")
        if fields["seq_profile"] != (2 if depth == 12 else 0) or fields["high_bitdepth"] != (depth > 8) or fields["reduced_still_picture_header"] != 1 or fields["tx_mode"] != (0 if lossless else 1):
            raise RuntimeError(f"{name}: unexpected profile/depth/transform header")
        disabled = ("use_128x128_superblock", "allow_intrabc", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled", "delta_q_present", "delta_q_y_dc.delta_coded", "tile_cols_log2", "tile_rows_log2")
        if any(fields[field] for field in disabled):
            raise RuntimeError(f"{name}: unexpected enabled tool")
        if depth == 12:
            fields["twelve_bit"] = trace_value(trace, "twelve_bit")
            if fields["twelve_bit"] != 1:
                raise RuntimeError(f"{name}: missing 12-bit flag")
        cdef = None
        if fields["enable_cdef"]:
            fields["cdef_bits"] = trace_value(trace, "cdef_bits")
            cdef = {"bits": fields["cdef_bits"], "damping_minus_3": trace_value(trace, "cdef_damping_minus_3")}
            for plane in (("y",) if monochrome else ("y", "uv")):
                cdef[plane + "_primary"] = helpers.trace_array(trace, f"cdef_{plane}_pri_strength", 1 << cdef["bits"])
                cdef[plane + "_secondary_raw"] = helpers.trace_array(trace, f"cdef_{plane}_sec_strength", 1 << cdef["bits"])
        loop_levels = [int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]
        if (not lossless and not loop_levels) or any(loop_levels):
            raise RuntimeError(f"{name}: loop filter not disabled")
        if lossless and fields["base_q_idx"] != 0:
            raise RuntimeError(f"{name}: encoder did not emit qindex zero")
        prefix = first_leaf_prefix(obu_path.read_bytes(), trace, fields, width=width, target=target, lossless=lossless)
        accepted = prefix["target_coding_proven"] and (kind != "fixed4" or prefix["first_nonzero_ac_proven"])
        ledger.append({"name": name, "kind": kind, "target_coding_dimensions": list(target), "actual_prefix": prefix, "encoder_command": encode,
                       "dimensions": [width, height], "bit_depth": depth, "monochrome": monochrome, "quantizer": quantizer,
                       "input_pattern": pattern, "header_trace": fields, "cdef": cdef,
                       "input_file": input_path.name, "input_sha256": sha256(input_path.read_bytes()),
                       "source_file": source_path.name, "source_sha256": sha256(source), "obu_file": obu_path.name, "obu_sha256": sha256(obu_path.read_bytes()),
                       "trace_file": trace_path.name, "trace_sha256": sha256(trace_path.read_bytes()),
                       "outcome": "accepted" if accepted else "encoder did not select required coding geometry/AC evidence"})
        if not accepted:
            print(f"candidate {name}: {ledger[-1]['outcome']}, {prefix}", flush=True)
            continue
        pixel_format = ("gray" if depth == 8 else f"gray{depth}le") if monochrome else ("yuv420p" if depth == 8 else f"yuv420p{depth}le")
        probe_command = [args.ffprobe, "-v", "error", "-show_entries", "stream=width,height,pix_fmt,color_range", "-of", "json", str(obu_path)]
        probe = json.loads(run(probe_command).stdout)["streams"]
        if len(probe) != 1 or probe[0]["pix_fmt"] != pixel_format or (probe[0]["width"], probe[0]["height"]) != (width, height):
            raise RuntimeError(f"{name}: unexpected native decoder format {probe}")
        reference_path = args.out / f"{name}.reference.yuv"
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(obu_path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(reference_path)]
        decoded = run(decode)
        decoder_version = re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)[0]
        if versions.setdefault("ffmpeg_decoder_version", decoder_version) != decoder_version:
            raise RuntimeError("inconsistent FFmpeg/libdav1d decoder")
        reference = reference_path.read_bytes()
        planes = native_planes(reference, depth, monochrome, width, height)
        if lossless and reference != source:
            raise RuntimeError(f"{name}: q0 native reference differs from source")
        cli_path = args.out / f"{name}.cli.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_path), "--limit", "1", "--inloopfilters", "all"]
        helpers.run_binary(cli)
        if cli_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: dav1d CLI differs from FFmpeg native output")
        cli_path.unlink()
        unfiltered_path = args.out / f"{name}.unfiltered.yuv"
        no_cdef = cli.copy()
        no_cdef[no_cdef.index("--output") + 1] = str(unfiltered_path)
        no_cdef[-1] = "nocdef"
        helpers.run_binary(no_cdef)
        avif_path = args.out / f"{name}.avif"
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
        run(wrap)
        avif_native_path = args.out / f"{name}.avif.native.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1] = str(avif_path)
        decode_avif[-1] = str(avif_native_path)
        run(decode_avif)
        if avif_native_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: AVIF remux changed decoded samples")
        avif_native_path.unlink()
        scalar_rgba = mono_helpers.scalar_rgba(avif_path.read_bytes(), scalar)
        scalar_path = args.out / f"{name}.scalar_libavif.rgba"
        scalar_path.write_bytes(scalar_rgba)
        if len(scalar_rgba) != width * height * 4 or any(value != 255 for value in scalar_rgba[3::4]):
            raise RuntimeError(f"{name}: invalid scalar RGBA reference")
        if monochrome and not (scalar_rgba[0::4] == scalar_rgba[1::4] == scalar_rgba[2::4]):
            raise RuntimeError(f"{name}: scalar monochrome output not grayscale")
        raw_rgba_path = args.out / f"{name}.raw_ffmpeg.rgba"
        decode_rgba = decode.copy()
        decode_rgba[decode_rgba.index("-pix_fmt") + 1] = "rgba"
        decode_rgba[-1] = str(raw_rgba_path)
        run(decode_rgba)
        raw_rgba = raw_rgba_path.read_bytes()
        if len(raw_rgba) != len(scalar_rgba):
            raise RuntimeError(f"{name}: invalid raw RGBA size")
        record = {"name": name, "dimensions": [width, height], "bit_depth": depth, "monochrome": monochrome,
                  "quantizer": quantizer, "lossless": lossless, "lossless_reference_matches_source": True if lossless else None,
                  "coding_block_constraints": {"minimum": 4, "maximum": width if rectangles else 4, "rectangles": rectangles, "ab": False, "one_to_four": extended},
                  "allowed_predictors": ["DC", "V", "H", "SMOOTH", "SMOOTH_V", "SMOOTH_H", "PAETH"],
                  "input_pattern": pattern, "header_trace": fields, "cdef": cdef, "loop_filter_levels": loop_levels,
                  "actual_prefix": prefix, "native_pixel_format": pixel_format, "probe": probe[0],
                  "native_cli_matches_ffmpeg": True, "avif_native_matches_obu": True,
                  "rgba_assertion_contract": "actual scalar libavif full-range UNORM" if monochrome else "av1_yuv420_highbd_to_rgba from exact native reference planes using decoded sequence range/matrix; nearest420 entry propagation",
                  "vendor_rgb_parity_asserted": monochrome,
                  "scalar_rgba_conversion": "actual avifImageYUVToRGB, output depth8, avoidLibYUV=1",
                  "raw_ffmpeg_vs_scalar_differing_bytes": sum(a != b for a, b in zip(raw_rgba, scalar_rgba)),
                  "cdef_changed_native_bytes": sum(a != b for a, b in zip(reference, unfiltered_path.read_bytes())),
                  "commands": {"encode": encode, "trace": trace_command, "probe": probe_command, "decode_native": decode,
                               "dav1d_cli": cli, "dav1d_no_cdef": no_cdef, "wrap_avif": wrap, "decode_avif_native": decode_avif, "decode_raw_rgba": decode_rgba}}
        for key, path in (("source", source_path), ("input", input_path), ("obu", obu_path), ("avif", avif_path),
                          ("reference", reference_path), ("unfiltered", unfiltered_path), ("rgba_reference", scalar_path),
                          ("raw_rgba", raw_rgba_path), ("trace", trace_path)):
            record[key + "_file"] = path.name
            record[key + "_sha256"] = sha256(path.read_bytes())
        records.append(record)
        print(f"accepted {name}: coding={prefix['first_coding_dimensions']} partition16={prefix['partition16_symbol']} partition8={prefix['partition8_symbol']} EOBpt={prefix.get('eob_pt')} q0exact={lossless} OBU={obu_path.stat().st_size}", flush=True)
    if len(ledger) != (16 if previous else 6):
        raise RuntimeError("candidate ledger exceeds or misses the bounded request")
    if previous:
        large.verify_existing_artifacts(previous, args.out)
        if sha256(Path(previous["generated_test"]).read_bytes()) != previous["generated_test_sha256"]:
            raise RuntimeError("the original published six-test file changed")
        if args.test.resolve() == Path(previous["generated_test"]).resolve():
            raise RuntimeError("appended candidates must use the prospective _refs test file")
    manifest = {"scope": "six original q30 fixed4 cases plus bounded 10-bit rectangle/q0 candidates" if previous else "six real q30 fixed4 coding-block encodes; color/mono x8/10/12, original OBU bytes", **versions,
                "generation_command": [sys.executable, *sys.argv], "candidate_limit": 16 if previous else 6, "candidate_count": len(ledger), "accepted_count": len(records),
                "prefix_evidence": "forced edge64/32 splits consume no bits, then normative partition16[0] and partition8[0] both decode SPLIT; first leaf is4x4; first EOBpt>1 proves an off-DC coefficient",
                "prefix_reader_source": "scripts/craft_av1_fixture.py MsacDecoder (decoder only; no synthesized bitstream)",
                "cdf_source": "_refs/go-av1/cdf default tables, independently matched AV1 normative tables",
                "partition_control_source": "https://aomedia.googlesource.com/aom/+/v3.6.0/aom/aomcx.h AV1E_SET_MIN_PARTITION_SIZE/MAX_PARTITION_SIZE",
                "reference_notes": "Exact native samples are independent of RGB policy. Color vendor RGBA files are retained as evidence with no parity assertion; production uses nearest420 upsampling. Mono RGBA uses actual scalar full-range UNORM.",
                "fixture_test_status": "appended tests prospective under _refs; original six published tests unchanged" if previous else "published white-box tests; generator does not run MoonBit builds", "candidates": ledger, "fixtures": records}
    if previous:
        manifest["generated_test"] = previous["generated_test"]
        manifest["generated_test_sha256"] = previous["generated_test_sha256"]
        manifest["previous_generation_command"] = previous["generation_command"]
        manifest["append_scope"] = {"candidate_count": 10, "rectangle_targets": [[4, 8], [8, 4], [4, 16], [16, 4]],
                                    "rectangle_modes": "color/mono10bit; min4/max8 or16; rectangular search, no fixed partition, no tx search", "lossless": "color/mono10bit16x16 fixed4 full native ramps", "preserved_original_candidates": 6}
        manifest["rectangle_source_analysis"] = {
            "encoder_reference": "libaom v3.6.0",
            "min_max_rule": "rectangle pruning by minimum applies only when current square <=minimum; roots8/16 exceed min4, so these controls do not force or hard-disable the requested rectangles",
            "allintra_initial_speed_defaults": {"less_rectangular_check_level": 1, "ml_prune_partition": 1, "prune_ext_partition_types_search_level": 1, "prune_part4_search": 2},
            "limitation": "final NONE proves the selected coding geometry only; it does not distinguish rate-distortion loss from a candidate pruned before evaluation",
            "sources": ["https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/partition_strategy.c (1729-1758)",
                        "https://aomedia.googlesource.com/aom/+/v3.6.0/av1/encoder/speed_features.c (318-344)"],
            "additional_texture_searches": 0,
        }
    if records:
        formatted = run([args.moonfmt, "-"], input_text=generated_test(records, args.out)).stdout
        args.test.parent.mkdir(parents=True, exist_ok=True)
        args.test.write_text(formatted, encoding="utf-8", newline="\n")
        key = "prospective_test" if previous else "generated_test"
        manifest[key] = str(args.test)
        manifest[key + "_sha256"] = sha256(args.test.read_bytes())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(records)}/{len(ledger)} accepted small-block fixtures")
    return 0 if previous or len(records) == 6 else 1


if __name__ == "__main__":
    raise SystemExit(main())
