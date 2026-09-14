#!/usr/bin/env python3
"""Bounded AV1 chroma-from-luma corpus with actual entropy and native references.

Stock candidates are untouched libaom output. An independent MSAC prefix reader
records the actual first-block UV mode, joint signs and alpha contexts; enabling
CfL alone is never coverage evidence. Canonical native binaries must match two
unmodified dav1d decoders and an AVIF remux. White-box RLE is generated from
these binaries and is not duplicated in the manifest. No MoonBit build runs.
The stock matrix has14 candidates. --append-sub8 adds exactly3 complete q0
syntax constructions for4x4/4x8/8x4 ownership, with no encoder-output edits.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import math
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


small = module("cfl_small_helpers", "generate-av1-small-block-reference.py")
large, arithmetic = small.large, small.arithmetic
mono_helpers, helpers = small.mono_helpers, small.helpers
run, sha256, trace_value, rle = small.run, small.sha256, small.trace_value, small.rle


def support_hashes() -> dict[str, str]:
    paths = [Path(__file__), ROOT / "scripts/generate-av1-small-block-reference.py", ROOT / "scripts/craft_av1_fixture.py"]
    paths += [ROOT / "_refs/go-av1/cdf" / name for name in (
        "tables_gen.go", "tables_coeff_gen.go", "tables_coeff2_gen.go", "tables_txeob_gen.go", "tables_cfl_gen.go")]
    return {str(path.relative_to(ROOT)).replace("\\", "/"): sha256(path.read_bytes()) for path in paths}


def coverage(records: list[dict[str, object]]) -> dict[str, object]:
    prefixes = [record["actual_prefix"] for record in records if "actual_prefix" in record]
    return {"stock_actual_cfl_count": len(prefixes), "constructed_conformance_count": len(records) - len(prefixes),
        "constructed_sub8_count": sum(min(record.get("target_coding_dimensions", [8, 8])) == 4 for record in records if "actual_prefix" not in record),
        "actual_alpha_pairs": sorted({tuple(prefix["alpha_numerators"]) for prefix in prefixes}),
        "same_sign_shared_cdf_count": sum(prefix["same_alpha_cdf_adapts_between_u_v"] for prefix in prefixes),
        "one_zero_alpha_count": sum(0 in prefix["alpha_numerators"] for prefix in prefixes),
        "saturating_prediction_cases": [record["name"] for record in records if any(record.get("first_block_prediction", {}).get("below_zero_counts", []))
                                       or any(record.get("first_block_prediction", {}).get("above_maximum_counts", []))],
        "crop_evidence_boundary": "13x9 stock stream has first-block CfL proof and exact full cropped reference; no claim that every edge block selects CfL"}


def candidates() -> list[dict[str, object]]:
    result = [{"name": f"stock_{depth}bit_{name}_8x8", "depth": depth, "width": 8, "height": 8,
               "alpha_targets": pair, "kind": "correlated"}
              for depth, (name, pair) in itertools.product((8, 10, 12), (
                  ("positive_positive", [1.0, 0.5]), ("negative_negative", [-1.0, -0.5]),
                  ("positive_negative", [1.0, -1.0]), ("positive_zero", [1.0, 0.0])))]
    result += [{"name": "stock_10bit_saturation_8x8", "depth": 10, "width": 8, "height": 8,
                "alpha_targets": [2.0, -2.0], "kind": "saturation"},
               {"name": "stock_10bit_crop_13x9", "depth": 10, "width": 13, "height": 9,
                "alpha_targets": [1.0, -0.75], "kind": "crop"}]
    return result


def source_planes(candidate: dict[str, object]) -> list[list[int]]:
    width, height, depth = candidate["width"], candidate["height"], candidate["depth"]
    scale, maximum = 1 << (depth - 8), (1 << depth) - 1
    luma = []
    for y in range(height):
        for x in range(width):
            value = (24 if ((x // 2 + y // 2) & 1) == 0 else 232) if candidate["kind"] == "saturation" else (
                128 + 38 * math.sin(math.pi * (x + 0.5) / 4) + 26 * math.cos(math.pi * (y + 0.5) / 4)
                + 18 * math.sin(math.pi * (x + 2 * y + 0.5) / 3))
            luma.append(max(0, min(maximum, round(value * scale))))
    cw, ch = (width + 1) // 2, (height + 1) // 2
    averages = [sum(luma[min(height - 1, 2 * y + dy) * width + min(width - 1, 2 * x + dx)]
                    for dy in range(2) for dx in range(2)) / 4 for y in range(ch) for x in range(cw)]
    mean = sum(averages) / len(averages)
    planes = [luma]
    for alpha in candidate["alpha_targets"]:
        planes.append([max(0, min(maximum, round((1 << (depth - 1)) + alpha * (value - mean)))) for value in averages])
    return planes


def cfl_prefix(stream: bytes, trace: str, fields: dict[str, int], width: int, height: int, coding_size: int = 8) -> dict[str, object]:
    tile, header_bytes = large.frame_tile(stream, trace)
    reader = arithmetic.MsacDecoder(tile, allow_update=not fields["disable_cdf_update"])
    result = {"frame_header_bytes": header_bytes, "tile_payload_bytes": len(tile), "first_block_origin": [0, 0]}
    tables = arithmetic.Tables()
    if coding_size == 32:
        result["partition64"] = reader.symbol(tables.partition_w64[0])
        result["partition32"] = reader.symbol(tables.partition_w32[0])
        if result["partition64"] != 3 or result["partition32"] != 0:
            raise RuntimeError("fixed32 candidate did not select SPLIT64 then NONE32")
        result["first_coding_dimensions"] = [32, 32]
        result["first_luma_tx_size"] = [32, 32]
        result["first_uv_tx_size"] = [16, 16]
        result["tx_size_evidence"] = "decoded nonlossless TX_MODE_LARGEST plus decoded32x32 coding block; no tx-depth symbol"
    elif max(width, height) > 8:
        partition16 = reader.symbol(small.PARTITION16.copy())
        result["partition16"] = partition16
        if partition16 != 3:
            raise RuntimeError("fixed8 candidate did not split its16 root")
    if coding_size == 8:
        partition8 = reader.symbol(small.PARTITION8.copy())
        result["partition8"] = partition8
        if partition8 != 0:
            raise RuntimeError("fixed8 candidate did not select an8x8 coding block")
    result["skip"] = reader.symbol(tables.skip[0])
    mode = reader.symbol(tables.y_mode[0][0])
    result["y_mode"] = mode
    if 1 <= mode <= 8:
        result["angle_delta_y"] = reader.symbol(arithmetic._parse_go_table("DefaultAngleDeltaCdf")[mode - 1]) - 3
    uv_mode = reader.symbol(tables.uv_mode_cfl[mode])
    result.update({"uv_mode": uv_mode, "cfl_selected": uv_mode == 13, "cfl_allowed": True})
    if uv_mode != 13:
        return result
    signs = reader.symbol(arithmetic._parse_go_table("DefaultCflSignCdf"))
    sign_u, sign_v = (signs + 1) // 3, (signs + 1) % 3
    alpha_cdfs = arithmetic._parse_go_table("DefaultCflAlphaCdf")
    alphas, contexts, symbols = [0, 0], [None, None], [None, None]
    for plane, sign in enumerate((sign_u, sign_v)):
        if sign:
            context = signs - 2 if plane == 0 else (sign_v - 1) * 3 + sign_u
            contexts[plane] = context
            symbols[plane] = reader.symbol(alpha_cdfs[context])
            alphas[plane] = (symbols[plane] + 1) * (-1 if sign == 1 else 1)
    result.update({"joint_sign_symbol": signs, "signs": [sign_u, sign_v], "alpha_numerators": alphas,
                   "alpha_denominator": 8, "alpha_contexts": contexts, "alpha_symbols": symbols,
                   "same_alpha_cdf_adapts_between_u_v": contexts[0] is not None and contexts[0] == contexts[1]})
    return result


def first_cfl_prediction_stats(planes: list[list[int]], width: int, depth: int, alphas: list[int]) -> dict[str, object]:
    """Coverage evidence only; expected pixels still come solely from dav1d.

    First block has8x8 luma,4x4 UV and no neighbors, so UV DC is midpoint.
    AV1 CfL uses Q3 downsample/mean then signed Round2(alpha*AC,6).
    """
    q3 = [2 * sum(planes[0][(2 * y + dy) * width + 2 * x + dx] for dy in range(2) for dx in range(2))
          for y in range(4) for x in range(4)]
    mean = (sum(q3) + 8) >> 4
    predictions = []
    for alpha in alphas:
        values = []
        for value in q3:
            product = alpha * (value - mean)
            adjustment = ((abs(product) + 32) >> 6) * (-1 if product < 0 else 1)
            values.append((1 << (depth - 1)) + adjustment)
        predictions.append(values)
    return {"scope": "first8x8 block; prediction-only coverage from decoded luma/alpha, not a reference oracle",
        "unclipped_ranges": [[min(p), max(p)] for p in predictions],
        "below_zero_counts": [sum(value < 0 for value in p) for p in predictions],
        "above_maximum_counts": [sum(value >= 1 << depth for value in p) for p in predictions]}


def constructed_sub8(target: tuple[int, int]) -> tuple[bytes, dict[str, object]]:
    """Three bounded q0 owner fixtures; all luma TX4x4 carry two AC levels.

    This is complete syntax construction, not modified libaom output. Nonowner
    blocks write only Y; the owner writes CfL mode/alpha then Y, U, V residuals.
    U/V residuals are zero so native chroma directly exercises CfL prediction.
    """
    class CheckedEncoder(arithmetic.MsacEncoder):
        def __init__(self):
            super().__init__()
            self.events = []

        def encode_symbol(self, cdf, symbol):
            self.events.append((cdf.copy(), symbol))
            super().encode_symbol(cdf, symbol)

    enc, tables = CheckedEncoder(), arithmetic.Tables()
    bw, bh = target
    partition = {(4, 4): 3, (4, 8): 2, (8, 4): 1}[target]
    enc.encode_symbol(small.PARTITION8.copy(), partition)
    sign_cdf = arithmetic._parse_go_table("DefaultCflSignCdf")
    alpha_cdfs = arithmetic._parse_go_table("DefaultCflAlphaCdf")
    top_level, left_level, top_dc, left_dc = ([0, 0] for _ in range(4))
    blocks = []
    for y in range(0, 8, bh):
        for x in range(0, 8, bw):
            owner = (bw != 4 or x // 4 % 2 == 1) and (bh != 4 or y // 4 % 2 == 1)
            enc.encode_symbol(tables.skip[0], 0)
            enc.encode_symbol(tables.y_mode[0][0], 0)
            if owner:
                enc.encode_symbol(tables.uv_mode_cfl[0], 13)
                enc.encode_symbol(sign_cdf, 6)  # positive U, negative V.
                enc.encode_symbol(alpha_cdfs[4], 15)  # Ualpha=+16/8.
                enc.encode_symbol(alpha_cdfs[2], 15)  # Valpha=-16/8.
            block = {"origin": [x, y], "dimensions": [bw, bh], "has_chroma": owner,
                "y_mode": 0, "uv_mode": 13 if owner else None, "alpha_numerators": [16, -16] if owner else None,
                "alpha_contexts": [4, 2] if owner else None, "luma_transforms": []}
            for ty in range(y, y + bh, 4):
                for tx in range(x, x + bw, 4):
                    x4, y4 = tx // 4, ty // 4
                    context = arithmetic.txb_skip_ctx_luma(top_level[x4], left_level[y4], target == (4, 4))
                    enc.encode_symbol(tables.txb_skip[0][0][context], 0)
                    dc_context = 2 if top_dc[x4] or left_dc[y4] else 0
                    cumulative, dc_category = arithmetic.encode_leaf_coeffs(enc, tables, 0, 4, 0, {0: 2, 1: 2, 4: 2}, 0, dc_context)
                    top_level[x4] = left_level[y4] = cumulative
                    top_dc[x4] = left_dc[y4] = dc_category
                    block["luma_transforms"].append({"origin": [tx, ty], "size": [4, 4], "inverse_transform": "WHT",
                        "all_zero_context": context, "dc_sign_context": dc_context, "eob": 3,
                        "positive_quantized_levels": [[0, 2], [1, 2], [4, 2]]})
            if owner:
                enc.encode_symbol(tables.txb_skip[0][0][7], 1)  # first U4x4, allzero.
                enc.encode_symbol(tables.txb_skip[0][0][7], 1)  # first V4x4; shared CDF updated by U.
            blocks.append(block)
    tile = enc.finish()
    decoder = arithmetic.MsacDecoder(tile)
    for cdf, symbol in enc.events:
        if decoder.symbol(cdf) != symbol:
            raise RuntimeError("sub8 arithmetic decoder roundtrip failed")
    sequence, frame = small.constructed_headers(8, False)
    stream = arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame + tile)
    return stream, {"provenance": "complete constructed q0 CfL conformance syntax, not libaom encoder output",
        "dimensions": [8, 8], "bit_depth": 10, "target_coding_dimensions": list(target), "partition8": partition,
        "blocks": blocks, "entropy_symbols_checked": len(enc.events), "owner_luma_aggregation": [8, 8],
        "uv_residuals": "one all-zero4x4 U and V; native chroma is CfL prediction", "alpha_numerators": [16, -16],
        "evidence_boundary": "all entropy symbols roundtrip with MsacDecoder; unmodified external decoders validate complete syntax and output"}


def generated_test(records: list[dict[str, object]], directory: Path) -> str:
    text = """/// Generated by scripts/generate-av1-cfl-reference.py.
/// Actual CfL syntax is recorded independently; exact native samples are from
/// unmodified dav1d decoders. Color RGBA follows nearest420 entry conversion.
fn av1_cfl_reference_expand(runs : Array[Int]) -> Array[Int] {
  let result : Array[Int] = []
  for i in 0..<(runs.length() / 2) {
    for _ in 0..<runs[i * 2 + 1] { result.push(runs[i * 2]) }
  }
  result
}

///|
fn av1_cfl_reference_compare(stream : Array[Byte], avif : Array[Byte],
  width : Int, height : Int, depth : Int, runs : Array[Array[Int]]) -> Unit raise {
  let frame = av1_decode_frame_planes(stream).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, depth))
  assert_eq((frame.full_range, frame.matrix_coefficients), (true, 2))
  assert_eq(frame.planes.length(), 3)
  let planes = runs.map(av1_cfl_reference_expand)
  for plane in 0..<3 { assert_eq(av1_frame_crop(frame, plane), planes[plane]) }
  let expected = av1_yuv420_highbd_to_rgba(width, height, planes[0], planes[1], planes[2], depth,
    full_range=true, matrix_coefficients=2).unwrap()
  let raw = av1_decode(stream).unwrap()
  let container = avif_decode_rgba(avif).unwrap()
  assert_eq((raw.width, raw.height, container.width, container.height), (width, height, width, height))
  for y in 0..<height { for x in 0..<width {
    assert_eq(raw.get_pixel(x,y), expected.get_pixel(x,y))
    assert_eq(container.get_pixel(x,y), expected.get_pixel(x,y))
  } }
}
"""
    for record in records:
        text += f'\n///|\ntest "external CfL {record["name"]}" {{\n'
        for variable, field in (("stream", "obu_file"), ("avif", "avif_file")):
            data = (directory / record[field]).read_bytes()
            text += f"let {variable} : Array[Byte] = [" + ",".join(f"b'\\x{x:02X}'" for x in data) + "]\n"
        width, height = record["dimensions"]
        data = (directory / record["reference_file"]).read_bytes()
        if sha256(data) != record["reference_sha256"]:
            raise RuntimeError("canonical native reference hash mismatch")
        planes = helpers.unpack_planes(data, width, height, record["bit_depth"])
        text += "let planes : Array[Array[Int]] = " + json.dumps([rle(plane) for plane in planes]) + "\n"
        text += f'av1_cfl_reference_compare(stream, avif, {width}, {height}, {record["bit_depth"]}, planes)\n}}\n'
    return text


def references(args, name: str, stream: bytes, width: int, height: int, depth: int, scalar) -> dict[str, object]:
    obu_path = args.out / f"{name}.obu"
    assert obu_path.read_bytes() == stream
    pixel_format = "yuv420p" if depth == 8 else f"yuv420p{depth}le"
    reference_path = args.out / f"{name}.reference.yuv"
    decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-xerror", "-y", "-c:v", "libdav1d", "-i", str(obu_path),
              "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(reference_path)]
    decoded = run(decode)
    reference = reference_path.read_bytes()
    planes = helpers.unpack_planes(reference, width, height, depth)
    cli_path = args.out / f"{name}.cli.yuv"
    cli = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_path), "--limit", "1"]
    helpers.run_binary(cli)
    if cli_path.read_bytes() != reference:
        raise RuntimeError(f"{name}: dav1d CLI differs from FFmpeg native samples")
    cli_path.unlink()
    avif_path = args.out / f"{name}.avif"
    wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
    run(wrap)
    avif_native = args.out / f"{name}.avif.native.yuv"
    decode_avif = decode.copy()
    decode_avif[decode_avif.index("-i") + 1], decode_avif[-1] = str(avif_path), str(avif_native)
    run(decode_avif)
    if avif_native.read_bytes() != reference:
        raise RuntimeError(f"{name}: AVIF remux changes samples")
    avif_native.unlink()
    scalar_rgba = mono_helpers.scalar_rgba(avif_path.read_bytes(), scalar)
    scalar_path = args.out / f"{name}.scalar_libavif.rgba"
    scalar_path.write_bytes(scalar_rgba)
    raw_path = args.out / f"{name}.raw_ffmpeg.rgba"
    decode_rgba = decode.copy()
    decode_rgba[decode_rgba.index("-pix_fmt") + 1], decode_rgba[-1] = "rgba", str(raw_path)
    run(decode_rgba)
    raw = raw_path.read_bytes()
    if len(raw) != width * height * 4 or len(scalar_rgba) != len(raw):
        raise RuntimeError(f"{name}: incorrect reference RGBA extent")
    record = {"name": name, "dimensions": [width, height], "bit_depth": depth,
        "sequence_color": {"full_range": True, "matrix_coefficients": 2},
        "native_pixel_format": pixel_format, "native_cli_matches_ffmpeg": True, "avif_native_matches_obu": True,
        "ffmpeg_libdav1d": re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)[0],
        "native_plane_ranges": [[min(p), max(p)] for p in planes],
        "rgba_assertion_contract": "existing av1_yuv420_highbd_to_rgba from exact native planes and decoded range/matrix; nearest420 entry propagation",
        "vendor_rgb_parity_asserted": False, "scalar_rgba_conversion": "actual avifImageYUVToRGB depth8 avoidLibYUV=1",
        "raw_ffmpeg_vs_scalar_differing_bytes": sum(a != b for a, b in zip(raw, scalar_rgba)),
        "commands": {"decode_native": decode, "dav1d_cli": cli, "wrap_avif": wrap, "decode_avif_native": decode_avif, "decode_raw_rgba": decode_rgba}}
    for key, path in (("obu", obu_path), ("avif", avif_path), ("reference", reference_path), ("rgba_reference", scalar_path), ("raw_rgba", raw_path)):
        record[key + "_file"], record[key + "_sha256"] = path.name, sha256(path.read_bytes())
    return record


def append_sub8(args) -> int:
    path = args.out / "manifest.json"
    previous = json.loads(path.read_text(encoding="utf-8"))
    if len(previous["candidates"]) != 14 or len(previous["fixtures"]) != 14:
        raise RuntimeError("bounded sub8 append requires14 stock candidates/references")
    large.verify_existing_artifacts(previous, args.out)
    scalar, _ = mono_helpers.scalar_library(args.libavif_scalar)
    records, ledger = previous["fixtures"].copy(), previous["candidates"].copy()
    for target in ((4, 4), (4, 8), (8, 4)):
        name = f"constructed_10bit_sub8_{target[0]}x{target[1]}_q0"
        stream, syntax = constructed_sub8(target)
        obu_path, syntax_path = args.out / f"{name}.obu", args.out / f"{name}.syntax.json"
        obu_path.write_bytes(stream)
        syntax_path.write_text(json.dumps(syntax, indent=2) + "\n", encoding="utf-8", newline="\n")
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        trace_path = args.out / f"{name}.trace.txt"
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        if trace_value(trace, "base_q_idx") != 0 or trace_value(trace, "high_bitdepth") != 1 or trace_value(trace, "mono_chrome"):
            raise RuntimeError("sub8 constructed q0 header mismatch")
        record = references(args, name, stream, 8, 8, 10, scalar)
        planes = helpers.unpack_planes((args.out / record["reference_file"]).read_bytes(), 8, 8, 10)
        if any(len(set(plane)) == 1 for plane in planes):
            raise RuntimeError("sub8 CfL reference needs nonconstant Y/U/V")
        record.update({"provenance": syntax["provenance"], "target_coding_dimensions": list(target),
            "syntax_file": syntax_path.name, "syntax_sha256": sha256(syntax_path.read_bytes()),
            "trace_file": trace_path.name, "trace_sha256": sha256(trace_path.read_bytes()),
            "actual_cfl_evidence": {"uv_mode": 13, "joint_sign_symbol": 6, "alpha_numerators": [16, -16],
                "owner_origin": next(block["origin"] for block in syntax["blocks"] if block["has_chroma"]),
                "luma_aggregation": [8, 8], "uv_residuals_allzero": True}})
        records.append(record)
        ledger.append({"name": name, "kind": "constructed_sub8_q0", "provenance": syntax["provenance"],
            "target_coding_dimensions": list(target), "obu_file": obu_path.name, "obu_sha256": sha256(stream),
            "syntax_file": syntax_path.name, "syntax_sha256": sha256(syntax_path.read_bytes()), "outcome": "accepted"})
        print(f"{name}: actual owner{record['actual_cfl_evidence']['owner_origin']} alpha[16,-16], native{record['native_plane_ranges']}", flush=True)
    large.verify_existing_artifacts(previous, args.out)
    manifest = previous.copy()
    manifest.update({"scope": "14 stock CfL references plus3 constructed sub8 owner conformance streams", "candidate_limit": 17,
        "candidates": ledger, "fixtures": records, "constructed_scope": {"count": 3, "targets": [[4, 4], [4, 8], [8, 4]],
            "bit_depth": 10, "quantizer": 0, "generation_command": [sys.executable, *sys.argv], "preserved_stock_candidates": 14}})
    manifest.update({"coverage": coverage(records), "support_hashes": support_hashes()})
    formatted = run([args.moonfmt, "-"], input_text=generated_test(records, args.out)).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest["generated_test"], manifest["generated_test_sha256"] = str(args.test), sha256(args.test.read_bytes())
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0


def rectangle_helpers():
    lossy = module("cfl_lossy_helpers", "generate-av1-small-lossy-reference.py")
    # Extend only this privately imported table instance, never the helper file.
    # The exact full scan/context arrays are independently checked against AOM.
    for shape, index in (((8, 32), 15), ((32, 8), 16)):
        lossy.TX_INDEX[shape] = index
        lossy.SCANS[shape] = lossy.go_table(ROOT / "_refs/go-av1/decode/scans_all_gen.go", f"scan_def{shape[0]}x{shape[1]}")
    return lossy


def constructed_rectangle(target: tuple[int, int], edge: bool) -> tuple[bytes, dict[str, object]]:
    lossy = rectangle_helpers()
    bw, bh = target
    size = 24 if edge else 16
    node = 32 if edge else 16
    enc, tables = lossy.CheckedEncoder(), arithmetic.Tables()
    eob_tables = {16: tables.eob_pt_16, 32: arithmetic._parse_go_table("DefaultEobPt32Cdf"),
                  64: tables.eob_pt_64, 256: tables.eob_pt_256}
    partition = 9 if bw < bh else 8
    enc.encode_symbol(tables.partition_w32[0] if edge else small.PARTITION16.copy(), partition)
    sign_cdf, alpha_cdfs = arithmetic._parse_go_table("DefaultCflSignCdf"), arithmetic._parse_go_table("DefaultCflAlphaCdf")
    top_dc, left_dc = [0] * 8, [0] * 8
    blocks = []
    step = min(target)
    for start in range(0, size, step):
        x, y = (start, 0) if bw < bh else (0, start)
        owner = edge or (start // 4) % 2 == 1
        enc.encode_symbol(tables.skip[0], 0)
        enc.encode_symbol(tables.y_mode[0][0], 0)
        if owner:
            enc.encode_symbol(tables.uv_mode_cfl[0], 13)
            enc.encode_symbol(sign_cdf, 6)
            enc.encode_symbol(alpha_cdfs[4], 15)
            enc.encode_symbol(alpha_cdfs[2], 15)
        enc.encode_symbol(tables.txb_skip[tables.qctx(lossy.QINDEX)][lossy.tx_context(bw, bh)][0], 0)
        if not edge:
            enc.encode_symbol(tables.intra_tx_set1[0][0], 1)  # DCT_DCT, SquareUp16.
        # Edge TX SquareUp32 is DCT-only: no transform-type symbol.
        x4, y4, w4, h4 = x // 4, y // 4, bw // 4, bh // 4
        dc_context = 2 if any(top_dc[x4:min(size // 4, x4 + w4)] + left_dc[y4:min(size // 4, y4 + h4)]) else 0
        coefficients = lossy.coefficients(enc, tables, eob_tables, target, 0, dc_context)
        top_dc[x4:x4 + w4], left_dc[y4:y4 + h4] = [2] * w4, [2] * h4
        uv_size = (max(4, bw // 2), max(4, bh // 2))
        if owner:
            context = lossy.tx_context(*uv_size)
            enc.encode_symbol(tables.txb_skip[tables.qctx(lossy.QINDEX)][context][7], 1)
            enc.encode_symbol(tables.txb_skip[tables.qctx(lossy.QINDEX)][context][7], 1)
        blocks.append({"origin": [x, y], "coding_dimensions": list(target), "has_chroma": owner,
            "uv_mode": 13 if owner else None, "alpha_numerators": [16, -16] if owner else None,
            "luma_tx_size": list(target), "uv_tx_size": list(uv_size) if owner else None,
            "luma_tx_type": "DCT_DCT", "luma_tx_type_symbol": None if edge else 1,
            "coefficients": coefficients, "uv_residuals_allzero": owner,
            "luma_tx_beyond_coded_mi": [max(0, x + bw - size), max(0, y + bh - size)]})
    tile = enc.finish()
    decoder = arithmetic.MsacDecoder(tile)
    for cdf, symbol in enc.symbols:
        if decoder.symbol(cdf) != symbol:
            raise RuntimeError("rectangular CfL entropy roundtrip failed")
    sequence, frame = lossy.headers(size, False)
    stream = arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame + tile)
    return stream, {"provenance": "complete constructed q32 CfL rectangle syntax, not encoder output or patched entropy",
        "dimensions": [size, size], "bit_depth": 10, "base_q_idx": lossy.QINDEX, "tx_mode": "LARGEST",
        "target_coding_dimensions": list(target), "partition_node": node, "partition_symbol": partition,
        "partition_name": "VERT_4" if bw < bh else "HORZ_4", "edge": edge, "blocks": blocks,
        "entropy_symbols_checked": len(enc.symbols), "all_cfl_owners": sum(block["has_chroma"] for block in blocks),
        "edge_rule": "32-node half16 exists withinMI24, so HORZ_4/VERT_4 is legal; fourth stripe begins24 and is absent" if edge else None,
        "evidence_boundary": "complete entropy construction/roundtrip, then unmodified dav1d semantics/native validation"}


def extended_stock(args, previous, depth: int, scalar) -> tuple[dict[str, object], dict[str, object]]:
    candidate = {"name": f"stock_{depth}bit_fixed32_64x64", "depth": depth, "width": 64, "height": 64,
                 "coding_size": 32, "alpha_targets": [1.0, -1.0], "kind": "correlated"}
    name = candidate["name"]
    source = b"".join(mono_helpers.pack(plane, depth) for plane in source_planes(candidate))
    source_path, input_path, obu_path = (args.out / f"{name}{suffix}" for suffix in (".source.yuv", ".input.y4m", ".obu"))
    source_path.write_bytes(source)
    format_name = "420" if depth == 8 else f"420p{depth}"
    input_path.write_bytes(f"YUV4MPEG2 W64 H64 F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode() + source)
    # Exact stock controls are inherited from the recorded, validated14-case
    # matrix; only dimensions/depth/partition bounds and paths change.
    changes = {"width": 64, "height": 64, "profile": 2 if depth == 12 else 0, "bit-depth": depth,
               "input-bit-depth": depth, "min-partition-size": 32, "max-partition-size": 32}
    encode = previous["candidates"][0]["encoder_command"].copy()
    encode[0], encode[-2], encode[-1] = args.aomenc, str(obu_path), str(input_path)
    for index, argument in enumerate(encode):
        for key, value in changes.items():
            if argument.startswith(f"--{key}="):
                encode[index] = f"--{key}={value}"
    run(encode)
    stream = obu_path.read_bytes()
    trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
    trace = run(trace_command).stderr
    trace_path = args.out / f"{name}.trace.txt"
    trace_path.write_text(trace, encoding="utf-8", newline="\n")
    fields = {field: trace_value(trace, field) for field in previous["candidates"][0]["header_trace"]}
    if any(fields[field] for field in ("enable_cdef", "enable_filter_intra", "enable_intra_edge_filter", "mono_chrome", "color_description_present_flag")) or fields["tx_mode"] != 1:
        raise RuntimeError("fixed32 candidate has unexpected tools/tx_mode")
    prefix = cfl_prefix(stream, trace, fields, 64, 64, 32)
    entry = {**candidate, "provenance": "untouched libaom encoder output", "encoder_command": encode,
        "header_trace": fields, "actual_prefix": prefix, "outcome": "accepted" if prefix["cfl_selected"] else "CfL not selected"}
    for key, path in (("source", source_path), ("input", input_path), ("obu", obu_path), ("trace", trace_path)):
        entry[key + "_file"], entry[key + "_sha256"] = path.name, sha256(path.read_bytes())
    if not prefix["cfl_selected"]:
        return entry, None
    record = references(args, name, stream, 64, 64, depth, scalar)
    record.update({"provenance": entry["provenance"], "actual_prefix": prefix, "header_trace": fields,
        "coverage_boundary": "first32x32 block CfL/TX32Y/TX16UV proven; complete frame tests CDF/state continuation without a claim all four blocks use CfL"})
    print(f"{name}: actual first32 CfL alpha={prefix['alpha_numerators']}, YTX32/UVTX16", flush=True)
    return entry, record


def edge_prediction_evidence(record, syntax, full_y: list[int], directory: Path) -> dict[str, object]:
    bw, bh = syntax["target_coding_dimensions"]
    uvw, uvh = bw // 2, bh // 2
    actual = helpers.unpack_planes((directory / record["reference_file"]).read_bytes(), 24, 24, 10)
    for y in range(min(24, bh)):
        for x in range(min(24, bw)):
            if actual[0][y * 24 + x] != full_y[y * bw + x]:
                raise RuntimeError("original C first luma TX differs from native dav1d")
    q3 = [2 * sum(full_y[(2 * y + dy) * bw + 2 * x + dx] for dy in range(2) for dx in range(2))
          for y in range(uvh) for x in range(uvw)]
    visible_w, visible_h = min(12, uvw), min(12, uvh)
    padded = [q3[min(y, visible_h - 1) * uvw + min(x, visible_w - 1)] for y in range(uvh) for x in range(uvw)]
    def prediction(values, alpha):
        mean = (sum(values) + len(values) // 2) // len(values)
        result = []
        for value in values:
            product = alpha * (value - mean)
            adjustment = ((abs(product) + 32) >> 6) * (-1 if product < 0 else 1)
            result.append(max(0, min(1023, 512 + adjustment)))
        return result
    differences = []
    for plane, alpha in ((1, 16), (2, -16)):
        complete, early_pad = prediction(q3, alpha), prediction(padded, alpha)
        mismatch = 0
        for y in range(visible_h):
            for x in range(visible_w):
                if complete[y * uvw + x] != actual[plane][y * 12 + x]:
                    raise RuntimeError("full original-C luma CfL prediction differs from native dav1d")
                mismatch += early_pad[y * uvw + x] != complete[y * uvw + x]
        differences.append(mismatch)
    if not any(differences):
        raise RuntimeError("edge fixture does not distinguish complete TX storage from premature Q3 padding")
    path = directory / f"{record['name']}.first_luma_full_tx.u16"
    path.write_bytes(mono_helpers.pack(full_y, 10))
    return {"full_luma_file": path.name, "full_luma_sha256": sha256(path.read_bytes()),
        "luma_tx_size": [bw, bh], "coded_mi_extent": [24, 24], "luma_samples_beyond_mi": bw * bh - min(24, bw) * min(24, bh),
        "original_c_visible_luma_matches_dav1d": True, "full_tx_cfl_visible_chroma_matches_dav1d": True,
        "premature_q3_edge_replication_differing_visible_pixels_uv": differences,
        "oracle_boundary": "original pinned libaom C inverseDCT + normative first-block DC512/CfL; native references remain dual-dav1d binaries"}


def extended_test(records, directory):
    return generated_test(records, directory).replace("av1_cfl_reference_", "av1_cfl_extended_reference_")


def edge_oracle(args) -> tuple[dict[tuple[int, int], list[int]], dict[str, object]]:
    oracle = module("cfl_original_txfm", "generate-av1-transform-reference.py")
    lossy = rectangle_helpers()
    quant_path = ROOT / "_refs/go-av1/decode/quant_gen.go"
    dc = arithmetic._parse_go_table("dcQlookup", quant_path)[1][lossy.QINDEX]
    ac = arithmetic._parse_go_table("acQlookup", quant_path)[1][lossy.QINDEX]
    def dequantized(width, height, depth, stress):
        values = [0] * (width * height)
        for position in lossy.SCANS[width, height][:3]:
            values[position] = 2 * (dc if position == 0 else ac)
        return values
    oracle.coefficients = dequantized
    # The original oracle harness capped each axis16; its256 sample buffers
    # already fit8x32/32x8. Widen only this harness guard, never any C kernel.
    oracle.C_MAIN = oracle.C_MAIN.replace("assert(width <= 16 && height <= 16);", "assert(width <= 32 && height <= 32 && width * height <= 256);")
    cache = Path(tempfile.gettempdir()) / ("pixelforge-aom-transform-" + oracle.REVISION)
    source = oracle.oracle_source(oracle.load_sources(cache))
    cases = [(8, 32, 10, 0, 15, False), (32, 8, 10, 0, 16, False)]
    residuals = oracle.run_oracle(args.cc, source, cases)
    return {case[:2]: [max(0, min(1023, 512 + value)) for value in residual] for case, residual in zip(cases, residuals)}, {
        "revision": oracle.REVISION, "source_hashes": oracle.SOURCE_HASHES, "compiler": args.cc,
        "dc_quantizer": dc, "ac_quantizer": ac, "base_q_idx": lossy.QINDEX,
        "boundary": "original C 2D/1D inverseDCT and existing residual sink; only test-harness shape guard widened to32 witharea<=256; first-block DC512/CfL composed independently"}


def rectangle_prefix(stream, trace, target, edge):
    lossy, tables = rectangle_helpers(), arithmetic.Tables()
    tile, _ = large.frame_tile(stream, trace)
    reader = arithmetic.MsacDecoder(tile)
    partition = reader.symbol(tables.partition_w32[0] if edge else small.PARTITION16.copy())
    if partition != (9 if target[0] < target[1] else 8):
        raise RuntimeError("constructed rectangle partition proof failed")
    if reader.symbol(tables.skip[0]) != 0 or reader.symbol(tables.y_mode[0][0]) != 0:
        raise RuntimeError("constructed rectangle skip/Y mode proof failed")
    result = {"partition_node": 32 if edge else 16, "partition_symbol": partition,
              "coding_dimensions": list(target), "luma_tx_size": list(target), "uv_tx_size": [max(4, target[0] // 2), max(4, target[1] // 2)],
              "tx_size_evidence": "decoded q32/LARGEST header plus decoded coding geometry; TX depth not signaled", "first_has_chroma": edge}
    if edge:
        if reader.symbol(tables.uv_mode_cfl[0]) != 13 or reader.symbol(arithmetic._parse_go_table("DefaultCflSignCdf")) != 6:
            raise RuntimeError("constructed edge CfL mode/sign proof failed")
        alphas = arithmetic._parse_go_table("DefaultCflAlphaCdf")
        if reader.symbol(alphas[4]) != 15 or reader.symbol(alphas[2]) != 15:
            raise RuntimeError("constructed edge alpha proof failed")
        result.update({"uv_mode": 13, "alpha_numerators": [16, -16]})
    context = lossy.tx_context(*target)
    if reader.symbol(tables.txb_skip[tables.qctx(lossy.QINDEX)][context][0]) != 0:
        raise RuntimeError("constructed rectangle coefficient-present proof failed")
    if not edge and reader.symbol(tables.intra_tx_set1[0][0]) != 1:
        raise RuntimeError("constructed rectangle DCT type proof failed")
    eob = tables.eob_pt_256 if edge else tables.eob_pt_64
    if reader.symbol(eob[tables.qctx(lossy.QINDEX)][0][0]) != 2:
        raise RuntimeError("constructed rectangle off-DC EOB proof failed")
    result.update({"eob_pt": 3, "luma_tx_type": "DCT_DCT", "luma_tx_type_signaled": not edge})
    return result


def append_extended(args) -> int:
    path = args.out / "manifest.json"
    previous = json.loads(path.read_text(encoding="utf-8"))
    if len(previous["candidates"]) != 17 or len(previous["fixtures"]) != 17:
        raise RuntimeError("bounded extended append requires the original17 candidates and references")
    large.verify_existing_artifacts(previous, args.out)
    protected = [Path(previous["generated_test"]), ROOT / "av1_cfl_reference_wbtest.mbt"]
    for test in protected:
        if sha256(test.read_bytes()) != previous["generated_test_sha256"]:
            raise RuntimeError("published17 test hash changed")
    scalar, _ = mono_helpers.scalar_library(args.libavif_scalar)
    lossy = rectangle_helpers()
    primary = lossy.verify_primary_sources(args.aom_source)
    records, ledger = previous["fixtures"].copy(), previous["candidates"].copy()
    for depth in (8, 10, 12):
        entry, record = extended_stock(args, previous, depth, scalar)
        ledger.append(entry)
        if record:
            records.append(record)
    full_y, original_c = edge_oracle(args)
    for target, edge in (((4, 16), False), ((16, 4), False), ((8, 32), True), ((32, 8), True)):
        size = 24 if edge else 16
        name = f"constructed_10bit_{'edge' if edge else 'interior'}_{target[0]}x{target[1]}_{size}x{size}_q32"
        stream, syntax = constructed_rectangle(target, edge)
        obu_path, syntax_path, trace_path = (args.out / f"{name}{suffix}" for suffix in (".obu", ".syntax.json", ".trace.txt"))
        if obu_path.exists() and obu_path.read_bytes() != stream:
            raise RuntimeError("existing pilot bytes changed")
        obu_path.write_bytes(stream)
        syntax_path.write_text(json.dumps(syntax, indent=2) + "\n", encoding="utf-8", newline="\n")
        trace = run([args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]).stderr
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        if trace_value(trace, "base_q_idx") != 32 or trace_value(trace, "tx_mode") != 1 or trace_value(trace, "max_frame_width_minus_1") != size - 1:
            raise RuntimeError("constructed rectangle header proof failed")
        prefix = rectangle_prefix(stream, trace, target, edge)
        record = references(args, name, stream, size, size, 10, scalar)
        record.update({"provenance": syntax["provenance"], "target_coding_dimensions": list(target), "edge": edge,
            "first_syntax_prefix": prefix, "syntax_file": syntax_path.name, "syntax_sha256": sha256(syntax_path.read_bytes()),
            "trace_file": trace_path.name, "trace_sha256": sha256(trace_path.read_bytes()), "constructed_cfl_owners": syntax["all_cfl_owners"]})
        if edge:
            evidence = edge_prediction_evidence(record, syntax, full_y[target], args.out)
            record.update({"full_luma_file": evidence["full_luma_file"], "full_luma_sha256": evidence["full_luma_sha256"], "complete_tx_edge_evidence": evidence})
        ledger.append({"name": name, "kind": "constructed_rectangle_q32", "provenance": syntax["provenance"],
            "target_coding_dimensions": list(target), "edge": edge, "obu_file": obu_path.name, "obu_sha256": sha256(stream),
            "syntax_file": syntax_path.name, "syntax_sha256": sha256(syntax_path.read_bytes()), "outcome": "accepted"})
        records.append(record)
        print(f"{name}: YTX{target}, UVTX{prefix['uv_tx_size']}, owners={syntax['all_cfl_owners']}, edge={record.get('complete_tx_edge_evidence',{}).get('premature_q3_edge_replication_differing_visible_pixels_uv')}", flush=True)
    if len(ledger) != 24:
        raise RuntimeError("extended ledger exceeded exactly7 candidates")
    large.verify_existing_artifacts(previous, args.out)
    for test in protected:
        if sha256(test.read_bytes()) != previous["generated_test_sha256"]:
            raise RuntimeError("published17 test changed during extension")
    new_records = records[17:]
    formatted = run([args.moonfmt, "-"], input_text=extended_test(new_records, args.out)).stdout
    args.extended_test.write_text(formatted, encoding="utf-8", newline="\n")
    extra_sources = [ROOT / "scripts/generate-av1-small-lossy-reference.py", ROOT / "scripts/generate-av1-transform-reference.py",
                    ROOT / "_refs/go-av1/decode/quant_gen.go", ROOT / "_refs/go-av1/decode/scans_all_gen.go", ROOT / "_refs/go-av1/decode/scan_gen.go"]
    manifest = previous.copy()
    manifest.update({"scope": "17 preserved CfL fixtures plus7 bounded fixed32/interior/completeTX-edge candidates",
        "candidate_limit": 24, "candidates": ledger, "fixtures": records, "prior_support_hashes": previous["support_hashes"],
        "support_hashes": {**support_hashes(), **{p.relative_to(ROOT).as_posix(): sha256(p.read_bytes()) for p in extra_sources}},
        "extended_scope": {"count": 7, "accepted_count": len(new_records), "preserved_reference_count": 17,
            "stock": "64x64 fixed32, color8/10/12; actual first32 CfL and inferred maximum32Y/16UV transforms",
            "interior": "q32 color10bit4x16/16x4; lossless CfL would be forbidden for these UV residual sizes",
            "edge": "q32 color10bit8x32/32x8 in24x24 frame; legal32-node VERT_4/HORZ_4; Y32 extends8 beyondMI24; UV4x16/16x4",
            "generation_command": [sys.executable, *sys.argv], "primary_rectangle_sources": primary, "original_c_edge_oracle": original_c},
        "extended_test": str(args.extended_test), "extended_test_sha256": sha256(args.extended_test.read_bytes()),
        "coverage": coverage(records),
        "test_status": "original17 published and unchanged; exactly7 extended tests prospective under _refs"})
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-cfl")
    parser.add_argument("--test", type=Path, default=ROOT / "_refs/av1_cfl_reference_wbtest.mbt")
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--append-sub8", action="store_true", help="append exactly3 constructed10bit q0 sub8 owner cases")
    parser.add_argument("--append-extended", action="store_true", help="append exactly7 fixed32/interior/completeTX-edge CfL candidates")
    parser.add_argument("--extended-test", type=Path, default=ROOT / "_refs/av1_cfl_extended_reference_wbtest.mbt")
    parser.add_argument("--cc", default=str(Path.home() / ".moon/bin/internal/tcc.exe"))
    parser.add_argument("--aom-source", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        for record in manifest["candidates"] + manifest["fixtures"]:
            for key, filename in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    if sha256((args.out / filename).read_bytes()) != record[key[:-5] + "_sha256"]:
                        raise RuntimeError(f"artifact hash mismatch: {filename}")
        for candidate in manifest["candidates"]:
            if candidate["provenance"] == "untouched libaom encoder output":
                stream = (args.out / candidate["obu_file"]).read_bytes()
                trace = (args.out / candidate["trace_file"]).read_text(encoding="utf-8")
                prefix = cfl_prefix(stream, trace, candidate["header_trace"], candidate["width"], candidate["height"], candidate.get("coding_size", 8))
                if prefix != candidate["actual_prefix"]:
                    raise RuntimeError("actual stock CfL syntax changed")
                source = b"".join(mono_helpers.pack(plane, candidate["depth"]) for plane in source_planes(candidate))
                if source != (args.out / candidate["source_file"]).read_bytes():
                    raise RuntimeError("stock input pattern regeneration mismatch")
            else:
                stream, syntax = (constructed_rectangle(tuple(candidate["target_coding_dimensions"]), candidate["edge"])
                                  if candidate["kind"] == "constructed_rectangle_q32" else constructed_sub8(tuple(candidate["target_coding_dimensions"])))
                if stream != (args.out / candidate["obu_file"]).read_bytes() or syntax != json.loads((args.out / candidate["syntax_file"]).read_text(encoding="utf-8")):
                    raise RuntimeError("constructed sub8 stream regeneration mismatch")
        for filename, expected in manifest["support_hashes"].items():
            if sha256((ROOT / filename).read_bytes()) != expected:
                raise RuntimeError(f"support source hash mismatch: {filename}")
        base_count = manifest.get("extended_scope", {}).get("preserved_reference_count", len(manifest["fixtures"]))
        formatted = run([args.moonfmt, "-"], input_text=generated_test(manifest["fixtures"][:base_count], args.out)).stdout
        if args.test.read_text(encoding="utf-8") != formatted:
            raise RuntimeError("canonical test output mismatch")
        if "extended_scope" in manifest:
            formatted = run([args.moonfmt, "-"], input_text=extended_test(manifest["fixtures"][base_count:], args.out)).stdout
            if args.extended_test.read_text(encoding="utf-8") != formatted:
                raise RuntimeError("extended canonical test output mismatch")
        print(f"checked {len(manifest['candidates'])} candidates and {len(manifest['fixtures'])} CfL references")
        return 0
    if args.append_sub8:
        return append_sub8(args)
    if args.append_extended:
        return append_extended(args)
    args.out.mkdir(parents=True, exist_ok=True)
    if (args.out / "manifest.json").exists():
        raise RuntimeError("bounded stock matrix already exists; use --check")
    scalar, scalar_version = mono_helpers.scalar_library(args.libavif_scalar)
    enc_version = run([args.aomenc, "--help"])
    dav1d_version = run([args.dav1d, "--version"])
    versions = {"libaom": re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", enc_version.stdout + enc_version.stderr).group(0),
                "ffmpeg": run([args.ffmpeg, "-version"]).stdout.splitlines()[0],
                "dav1d_cli": (dav1d_version.stdout + dav1d_version.stderr).strip(), "scalar_libavif": scalar_version}
    ledger, records = [], []
    for candidate in candidates():
        name, width, height, depth = candidate["name"], candidate["width"], candidate["height"], candidate["depth"]
        planes = source_planes(candidate)
        source = b"".join(mono_helpers.pack(plane, depth) for plane in planes)
        source_path, input_path = args.out / f"{name}.source.yuv", args.out / f"{name}.input.y4m"
        source_path.write_bytes(source)
        format_name = "420" if depth == 8 else f"420p{depth}"
        input_path.write_bytes(f"YUV4MPEG2 W{width} H{height} F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode() + source)
        obu_path = args.out / f"{name}.obu"
        encode = [args.aomenc, "--enable-diagonal-intra=0", "--debug", "--disable-warning-prompt", "--allintra", "--obu", "--i420",
            f"--width={width}", f"--height={height}", f"--profile={2 if depth == 12 else 0}", f"--bit-depth={depth}", f"--input-bit-depth={depth}",
            "--fps=1/1", "--limit=1", "--cpu-used=0", "--threads=1", "--end-usage=q", "--cq-level=30", "--sb-size=64",
            "--tile-columns=0", "--tile-rows=0", "--aq-mode=0", "--deltaq-mode=0", "--enable-chroma-deltaq=0", "--enable-qm=0",
            "--enable-cdef=0", "--enable-restoration=0", "--enable-filter-intra=0", "--enable-intra-edge-filter=0", "--enable-angle-delta=0",
            "--enable-rect-partitions=0", "--enable-1to4-partitions=0", "--enable-ab-partitions=0", "--enable-smooth-intra=1", "--enable-paeth-intra=1",
            "--enable-palette=0", "--enable-flip-idtx=0", "--enable-tx-size-search=0", "--use-intra-default-tx-only=1",
            "--min-partition-size=8", "--max-partition-size=8", "--enable-directional-intra=1", "--enable-cfl-intra=1", "--enable-intrabc=0",
            "--loopfilter-control=0", "-o", str(obu_path), str(input_path)]
        run(encode)
        stream = obu_path.read_bytes()
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        trace_path = args.out / f"{name}.trace.txt"
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        fields = {field: trace_value(trace, field) for field in (
            "disable_cdf_update", "enable_cdef", "enable_filter_intra", "enable_intra_edge_filter", "allow_screen_content_tools",
            "base_q_idx", "color_range", "color_description_present_flag", "mono_chrome", "high_bitdepth", "seq_profile", "reduced_tx_set", "tx_mode")}
        if any(fields[field] for field in ("enable_cdef", "enable_filter_intra", "enable_intra_edge_filter", "mono_chrome")):
            raise RuntimeError(f"{name}: unexpected enabled tool/monochrome")
        if fields["color_range"] != 1 or fields["color_description_present_flag"] != 0 or fields["high_bitdepth"] != (depth > 8) or fields["tx_mode"] != 1:
            raise RuntimeError(f"{name}: unexpected source range/depth/transform mode")
        prefix = cfl_prefix(stream, trace, fields, width, height)
        entry = {**candidate, "provenance": "untouched libaom encoder output", "encoder_command": encode,
                 "header_trace": fields, "actual_prefix": prefix, "outcome": "accepted" if prefix["cfl_selected"] else "CfL not selected"}
        for key, path in (("source", source_path), ("input", input_path), ("obu", obu_path), ("trace", trace_path)):
            entry[key + "_file"], entry[key + "_sha256"] = path.name, sha256(path.read_bytes())
        ledger.append(entry)
        if prefix["cfl_selected"]:
            record = references(args, name, stream, width, height, depth, scalar)
            record.update({"provenance": entry["provenance"], "actual_prefix": prefix, "header_trace": fields})
            native = helpers.unpack_planes((args.out / record["reference_file"]).read_bytes(), width, height, depth)
            record["first_block_prediction"] = first_cfl_prediction_stats(native, width, depth, prefix["alpha_numerators"])
            records.append(record)
        print(f"{name}: {entry['outcome']}, alpha={prefix.get('alpha_numerators')}, contexts={prefix.get('alpha_contexts')}", flush=True)
    manifest = {"scope": "bounded14 stock CfL candidates with actual decoded first-block syntax", "versions": versions,
        "generation_command": [sys.executable, *sys.argv], "candidate_limit": 14, "candidates": ledger, "fixtures": records,
        "cdf_source": "_refs/go-av1/cdf/tables_cfl_gen.go normative DefaultCflSignCdf/DefaultCflAlphaCdf",
        "syntax_source": "https://aomediacodec.github.io/av1-spec/av1-spec.html sections5.11.45 and7.11.5",
        "reference_notes": "native dav1d binaries canonical; color vendor RGBA retained with no parity assertion; production nearest420 conversion used for entry parity",
        "test_status": "prospective under _refs; no MoonBit build", "support_hashes": support_hashes(), "coverage": coverage(records)}
    formatted = run([args.moonfmt, "-"], input_text=generated_test(records, args.out)).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest["generated_test"], manifest["generated_test_sha256"] = str(args.test), sha256(args.test.read_bytes())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
