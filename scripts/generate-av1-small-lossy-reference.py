#!/usr/bin/env python3
"""Construct exactly eight q32 small-rectangle AV1 conformance references.

These are complete syntax constructions, not encoder output or entropy patches.
Color/mono 10-bit x 4x8/8x4/4x16/16x4 use their rectangular maximum transforms,
DCT_DCT, and two off-DC coefficients in every Y/UV transform. Both unmodified
dav1d CLI and FFmpeg/libdav1d must agree on every native sample; AVIF remux must
preserve them. Canonical binary references are hashed, without manifest RLE.
The prospective MoonBit tests stay under _refs; this script never runs Moon.
"""

from __future__ import annotations

import argparse
import ast
import importlib.util
import itertools
import json
import os
import re
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("small_lossy_helpers", Path(__file__).with_name("generate-av1-small-block-reference.py"))
assert spec is not None and spec.loader is not None
small = importlib.util.module_from_spec(spec)
spec.loader.exec_module(small)
arithmetic, mono_helpers = small.arithmetic, small.mono_helpers
run, sha256 = small.run, small.sha256
TARGETS = ((4, 8), (8, 4), (4, 16), (16, 4))
QINDEX = 32
TX_INDEX = {(4, 4): 0, (4, 8): 5, (8, 4): 6, (4, 16): 13, (16, 4): 14}
AOM_REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"


def go_table(path: Path, name: str):
    source = path.read_text(encoding="utf-8")
    match = re.search(r"var\s+" + re.escape(name) + r"\s*=\s*[^\{]+(\{[^\n]+\})", source)
    if match is None:
        raise RuntimeError(f"missing normative table {name} in {path}")
    return ast.literal_eval(match.group(1).replace("{", "[").replace("}", "]"))


SCANS = {shape: go_table(ROOT / "_refs/go-av1/decode/scans_all_gen.go", f"scan_def{shape[0]}x{shape[1]}") for shape in TX_INDEX}
BASE_OFFSETS = go_table(ROOT / "_refs/go-av1/decode/scan_gen.go", "coeffBaseCtxOffset")


def aom_cdf_table(path: Path, name: str):
    source = path.read_text(encoding="utf-8")
    match = re.search(r"\b" + re.escape(name) + r"\b[^=]+?=\s*\{", source)
    if match is None:
        raise RuntimeError(f"missing libaom CDF {name}")
    start, depth = match.end() - 1, 0
    for end in range(start, len(source)):
        depth += int(source[end] == "{") - int(source[end] == "}")
        if depth == 0:
            break
    value = re.sub(r"/\*.*?\*/|//[^\n]*", "", source[start:end + 1], flags=re.S)
    # Macro arguments are ascending cumulative probabilities; libaom stores
    # their complements, while the arithmetic helper consumes ascending CDFs.
    value = re.sub(r"AOM_CDF\d+\(([^)]*)\)", lambda match: match[1] + ",32768,0", value)
    value = re.sub(r"(\d+)\s*\*\s*(\d+)", lambda match: str(int(match[1]) * int(match[2])), value)
    return ast.literal_eval(value.replace("{", "[").replace("}", "]"))


def verify_primary_sources(directory: Path) -> dict[str, object]:
    """Compare full scans with libaom's column-major storage and context rule."""
    if run(["git", "-C", str(directory), "rev-parse", "HEAD"]).stdout.strip() != AOM_REVISION:
        raise RuntimeError("libaom primary source revision changed")
    source = (directory / "av1/common/scan.c").read_text(encoding="utf-8")
    checked = []
    for (width, height), scan in SCANS.items():
        match = re.search(rf"default_scan_{width}x{height}\[\d+\]\)\s*=\s*\{{([^}}]+)\}}", source)
        if match is None:
            raise RuntimeError(f"missing libaom scan {width}x{height}")
        aom_scan = list(map(int, re.findall(r"\d+", match.group(1))))
        # libaom stores coefficients at col*height+row; go-av1 uses row*width+col.
        converted = [(position % height) * width + position // height for position in aom_scan]
        if converted != scan:
            raise RuntimeError(f"independent scan disagreement: {width}x{height}")
        for row in range(min(height, 5)):
            for col in range(min(width, 5)):
                offset = (0 if row == col == 0 else 11 if width < height and row < 2
                          else 16 if width > height and col < 2 else 1 if row + col < 2
                          else 6 if row + col < 4 else 21)
                if BASE_OFFSETS[TX_INDEX[width, height]][row][col] != offset:
                    raise RuntimeError(f"independent coeff context offset disagreement: {width,height,row,col}")
        checked.append({"dimensions": [width, height], "scan_prefix": scan[:3], "full_scan_matches_libaom": True,
                        "coeff_base_offsets_match_libaom_algorithm": True})
    tables = arithmetic.Tables()
    comparisons = {"av1_default_txb_skip_cdfs": tables.txb_skip,
        "av1_default_coeff_base_multi_cdfs": tables.coeff_base,
        "av1_default_coeff_base_eob_multi_cdfs": tables.coeff_base_eob,
        "av1_default_eob_extra_cdfs": tables.eob_extra, "av1_default_dc_sign_cdfs": tables.dc_sign,
        "av1_default_eob_multi16_cdfs": tables.eob_pt_16,
        "av1_default_eob_multi32_cdfs": arithmetic._parse_go_table("DefaultEobPt32Cdf"),
        "av1_default_eob_multi64_cdfs": tables.eob_pt_64}
    cdf_checks = []
    for name, expected in comparisons.items():
        if aom_cdf_table(directory / "av1/common/token_cdfs.h", name) != expected:
            raise RuntimeError(f"independent CDF disagreement: {name}")
        cdf_checks.append(name)
    modes = directory / "av1/common/entropymode.c"
    for name, expected in (("default_kf_y_mode_cdf", tables.y_mode), ("default_skip_txfm_cdfs", tables.skip)):
        if aom_cdf_table(modes, name) != expected:
            raise RuntimeError(f"independent CDF disagreement: {name}")
        cdf_checks.append(name)
    if (aom_cdf_table(modes, "default_uv_mode_cdf")[1] != tables.uv_mode_cfl or
            aom_cdf_table(modes, "default_intra_ext_tx_cdf")[1][0] != tables.intra_tx_set1[0]):
        raise RuntimeError("independent UV-mode/intra-TX-type CDF disagreement")
    partitions = aom_cdf_table(modes, "default_partition_cdf")
    if partitions[0] != small.PARTITION8 or partitions[4] != small.PARTITION16:
        raise RuntimeError("independent first partition CDF disagreement")
    cdf_checks += ["default_uv_mode_cdf[CFL_ALLOWED]", "default_intra_ext_tx_cdf[1][TX4x4]",
                   "default_partition_cdf[W8/W16 context0]"]
    return {"revision": AOM_REVISION, "checkout": str(directory), "checks": checked, "cdf_tables_match_libaom": cdf_checks,
            "primary_sources": {name: sha256((directory / name).read_bytes()) for name in (
                "av1/common/scan.c", "av1/common/txb_common.h", "av1/common/blockd.h",
                "av1/common/token_cdfs.h", "av1/common/entropymode.c")},
            "source_urls": [f"https://aomedia.googlesource.com/aom/+/{AOM_REVISION}/av1/common/{name}"
                            for name in ("scan.c", "txb_common.h", "blockd.h", "token_cdfs.h", "entropymode.c")]}


def headers(size: int, monochrome: bool) -> tuple[bytes, bytes]:
    # The sequence syntax is identical to the prior q0 construction. Frame
    # syntax is written afresh: nonlossless adds delta_q, loopfilter and tx_mode.
    sequence, _ = small.constructed_headers(size, monochrome)
    writer = arithmetic.BitWriter()
    for value in (0, 0, 0, 1):
        writer.f(value, 1)  # CDF updates enabled, screen tools off, render size, uniform tiles.
    writer.f(QINDEX, 8)
    writer.f(0, 1)  # delta_q_y_dc.delta_coded
    if not monochrome:
        writer.f(0, 1)  # delta_q_u_dc.delta_coded
        writer.f(0, 1)  # delta_q_u_ac.delta_coded, V inherits U
    writer.f(0, 1)  # using_qmatrix
    writer.f(0, 1)  # segmentation_enabled
    writer.f(0, 1)  # delta_q_present (base_q_idx > 0)
    writer.f(0, 6)  # loop_filter_level[0]
    writer.f(0, 6)  # loop_filter_level[1]; zero levels omit chroma levels
    writer.f(0, 3)  # loop_filter_sharpness
    writer.f(0, 1)  # loop_filter_delta_enabled
    writer.f(0, 1)  # tx_mode_select => TX_MODE_LARGEST, maximum rectangular TX
    writer.f(0, 1)  # reduced_tx_set
    while len(writer.bits) % 8:
        writer.f(0, 1)  # frame-header byte_alignment, not trailing_bits
    return sequence, writer.to_bytes()


class CheckedEncoder(arithmetic.MsacEncoder):
    def __init__(self):
        super().__init__()
        self.symbols = []

    def encode_symbol(self, cdf, symbol):
        self.symbols.append((cdf.copy(), symbol))
        super().encode_symbol(cdf, symbol)


def tx_context(width: int, height: int) -> int:
    square_down = min(width, height).bit_length() - 3
    square_up = max(width, height).bit_length() - 3
    return (square_down + square_up + 1) >> 1


def coeff_context(quant: list[int], width: int, height: int, position: int, scan_index: int, eob: bool) -> int:
    if eob:
        return 0 if scan_index == 0 else 1 if scan_index <= width * height // 8 else 2 if scan_index <= width * height // 4 else 3
    row, col = divmod(position, width)
    if row == col == 0:
        return 0
    magnitude = sum(min(abs(quant[(row + dr) * width + col + dc]), 3)
                    for dr, dc in ((0, 1), (1, 0), (1, 1), (0, 2), (2, 0))
                    if row + dr < height and col + dc < width)
    return min((magnitude + 1) >> 1, 4) + BASE_OFFSETS[TX_INDEX[width, height]][min(row, 4)][min(col, 4)]


def coefficients(enc, tables, eob_tables, shape: tuple[int, int], plane_type: int, dc_context: int) -> dict[str, object]:
    """Normative 2D DCT prefix only: EOB3, positive levels2, no BR/Golomb."""
    width, height = shape
    context = tx_context(width, height)
    qcontext = tables.qctx(QINDEX)
    scan = SCANS[shape]
    enc.encode_symbol(eob_tables[width * height][qcontext][plane_type][0], 2)  # eob_pt=3
    enc.encode_symbol(tables.eob_extra[qcontext][context][plane_type][0], 0)  # EOB3
    quant = [0] * (width * height)
    contexts = []
    for scan_index in (2, 1, 0):
        position = scan[scan_index]
        base_context = coeff_context(quant, width, height, position, scan_index, scan_index == 2)
        cdf = (tables.coeff_base_eob if scan_index == 2 else tables.coeff_base)[qcontext][context][plane_type][base_context]
        enc.encode_symbol(cdf, 1 if scan_index == 2 else 2)
        quant[position] = 2
        contexts.append({"scan_index": scan_index, "position": position, "eob": scan_index == 2,
                         "context": base_context, "level": 2})
    enc.encode_symbol(tables.dc_sign[qcontext][plane_type][dc_context], 0)
    enc.write_bool(0)
    enc.write_bool(0)
    return {"tx_size_context": context, "coefficient_q_context": qcontext, "plane_type": plane_type,
            "eob_table_area": width * height, "eob_pt": 3, "eob_extra": 0, "eob": 3,
            "scan_prefix": scan[:3], "positive_quantized_levels": [[position, 2] for position in scan[:3]],
            "base_contexts_in_decode_order": contexts, "dc_sign_context": dc_context}


def constructed_stream(target: tuple[int, int], monochrome: bool) -> tuple[bytes, dict[str, object]]:
    width, height = target
    size = max(target)
    enc, tables = CheckedEncoder(), arithmetic.Tables()
    eob_tables = {16: tables.eob_pt_16, 32: arithmetic._parse_go_table("DefaultEobPt32Cdf"), 64: tables.eob_pt_64}
    partition = (2 if width == 4 else 1) if size == 8 else (9 if width == 4 else 8)
    enc.encode_symbol((small.PARTITION8 if size == 8 else small.PARTITION16).copy(), partition)
    top_level = [[0] * (size // 4) for _ in range(3)]
    left_level = [[0] * (size // 4) for _ in range(3)]
    top_dc = [[0] * (size // 4) for _ in range(3)]
    left_dc = [[0] * (size // 4) for _ in range(3)]
    blocks = []
    for block_index in range(size // 4):
        x, y = (block_index * 4, 0) if width == 4 else (0, block_index * 4)
        owner = not monochrome and ((x // 4) % 2 == 1 if width == 4 else (y // 4) % 2 == 1)
        enc.encode_symbol(tables.skip[0], 0)
        enc.encode_symbol(tables.y_mode[0][0], 0)  # all neighbors also DC_PRED
        if owner:
            enc.encode_symbol(tables.uv_mode_cfl[0], 0)  # nonlossless small block permits CfL, choose DC
        block = {"origin": [x, y], "dimensions": list(target), "has_chroma": owner,
                 "skip": 0, "y_mode": 0, "uv_mode": 0 if owner else None,
                 "cfl_allowed": True if owner else None, "transforms": []}
        for plane in range(3 if owner else 1):
            tw, th = target if plane == 0 else (max(4, width // 2), max(4, height // 2))
            px, py = (x, y) if plane == 0 else ((x // 8) * 4, (y // 8) * 4)
            x4, y4, w4, h4 = px // 4, py // 4, tw // 4, th // 4
            top = top_level[plane][x4:x4 + w4]
            left = left_level[plane][y4:y4 + h4]
            # Every chosen transform fills its coding-plane residual. Luma is
            # therefore context0; UV is context7 plus above/left nonzero flags.
            skip_context = 0 if plane == 0 else 7 + int(any(top)) + int(any(left))
            enc.encode_symbol(tables.txb_skip[tables.qctx(QINDEX)][tx_context(tw, th)][skip_context], 0)
            if plane == 0:
                # SquareUp<32, SquareDown=4, non-reduced => intra set1 row0.
                enc.encode_symbol(tables.intra_tx_set1[0][0], 1)  # DCT_DCT
            score = sum(-1 if value == 1 else 1 if value == 2 else 0 for value in
                        top_dc[plane][x4:x4 + w4] + left_dc[plane][y4:y4 + h4])
            dc_context = 1 if score < 0 else 2 if score > 0 else 0
            evidence = coefficients(enc, tables, eob_tables, (tw, th), int(plane != 0), dc_context)
            for i in range(w4):
                top_level[plane][x4 + i], top_dc[plane][x4 + i] = 6, 2
            for i in range(h4):
                left_level[plane][y4 + i], left_dc[plane][y4 + i] = 6, 2
            block["transforms"].append({"plane": plane, "origin": [px, py], "size": [tw, th],
                "inverse_transform": "DCT_DCT", "max_transform": True, "tx_depth": 0,
                "all_zero_context": skip_context, "tx_type_symbol": 1 if plane == 0 else None,
                "tx_type_cdf": [1, 0, 0] if plane == 0 else None, **evidence})
        blocks.append(block)
    tile = enc.finish()
    reader = arithmetic.MsacDecoder(tile)
    for cdf, expected in enc.symbols:
        if reader.symbol(cdf) != expected:
            raise RuntimeError("entropy arithmetic roundtrip failed")
    sequence, frame_header = headers(size, monochrome)
    stream = arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame_header + tile)
    return stream, {"provenance": "complete constructed AV1 syntax, not encoder output or patched entropy",
        "base_q_idx": QINDEX, "bit_depth": 10, "monochrome": monochrome, "tx_mode": "LARGEST",
        "target_coding_dimensions": list(target), "partition_symbol": partition,
        "partition_name": {1: "HORZ", 2: "VERT", 8: "HORZ_4", 9: "VERT_4"}[partition], "blocks": blocks,
        "entropy_symbol_count": len(enc.symbols), "entropy_snapshot_sha256": sha256(json.dumps(enc.symbols).encode()),
        "entropy_roundtrip": "CDF snapshot/symbol transcript decoded with independent MsacDecoder dual",
        "frame_header_bytes": len(frame_header), "tile_payload_bytes": len(tile)}


def generated_test(records, directory):
    text = small.generated_test(records, directory)
    return (text.replace("scripts/generate-av1-small-block-reference.py", "scripts/generate-av1-small-lossy-reference.py")
            .replace("Stock libaom fixed4 and explicitly constructed rectangle conformance streams.",
                     "Complete q32 rectangular DCT conformance streams with off-DC coefficients.")
            .replace("av1_small_reference_", "av1_small_lossy_reference_")
            .replace("external small coding block", "external lossy small rectangle"))


def support_hashes():
    paths = [Path(__file__), Path(small.__file__), ROOT / "scripts/craft_av1_fixture.py"]
    paths += [ROOT / "_refs/go-av1" / name for name in (
        "cdf/tables_gen.go", "cdf/tables_coeff_gen.go", "cdf/tables_coeff2_gen.go", "cdf/tables_txeob_gen.go",
        "decode/scans_all_gen.go", "decode/scan_gen.go", "decode/coeffctx.go", "decode/coeff.go", "decode/residual.go", "decode/block.go")]
    return {path.relative_to(ROOT).as_posix(): sha256(path.read_bytes()) for path in paths}


def check(args):
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    cases = [(record["monochrome"], tuple(record["target_coding_dimensions"])) for record in manifest["fixtures"]]
    if cases != list(itertools.product((False, True), TARGETS)) or manifest["support_hashes"] != support_hashes():
        raise RuntimeError("fixture count or construction support hashes changed")
    for record in manifest["fixtures"]:
        for key, name in record.items():
            if key.endswith("_file") and key[:-5] + "_sha256" in record:
                if sha256((args.out / name).read_bytes()) != record[key[:-5] + "_sha256"]:
                    raise RuntimeError(f"artifact hash mismatch: {name}")
        stream, syntax = constructed_stream(tuple(record["target_coding_dimensions"]), record["monochrome"])
        if stream != (args.out / record["obu_file"]).read_bytes() or syntax != json.loads((args.out / record["syntax_file"]).read_text()):
            raise RuntimeError(f"deterministic reconstruction mismatch: {record['name']}")
    target = args.test or Path(manifest["prospective_test"])
    formatted = run([args.moonfmt, "-"], input_text=generated_test(manifest["fixtures"], args.out)).stdout
    if target.read_text(encoding="utf-8") != formatted or sha256(target.read_bytes()) != manifest["prospective_test_sha256"]:
        raise RuntimeError("canonical prospective test mismatch")
    print("checked exactly8 lossy rectangle streams, artifact hashes and canonical prospective tests")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-small-lossy")
    parser.add_argument("--test", type=Path)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--aom-source", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    parser.add_argument("--check", action="store_true", help="check deterministic bytes/hashes/tests without decoding or compiling")
    args = parser.parse_args()
    if args.check:
        check(args)
        return
    primary = verify_primary_sources(args.aom_source)
    scalar, scalar_version = mono_helpers.scalar_library(args.libavif_scalar)
    result = run([args.dav1d, "--version"])
    versions = {"dav1d_cli": (result.stdout + result.stderr).strip(), "scalar_libavif": scalar_version,
                "ffmpeg": run([args.ffmpeg, "-version"]).stdout.splitlines()[0]}
    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for monochrome, target in itertools.product((False, True), TARGETS):
        size = max(target)
        name = f"constructed_{'mono' if monochrome else 'color'}_{size}x{size}_10bit_{target[0]}x{target[1]}_q32"
        stream, syntax = constructed_stream(target, monochrome)
        paths = {key: args.out / (name + suffix) for key, suffix in (
            ("obu", ".obu"), ("avif", ".avif"), ("syntax", ".syntax.json"), ("trace", ".trace.txt"),
            ("reference", ".reference.yuv"), ("rgba_reference", ".scalar_libavif.rgba"), ("raw_rgba", ".raw_ffmpeg.rgba"))}
        paths["obu"].write_bytes(stream)
        paths["syntax"].write_text(json.dumps(syntax, indent=2) + "\n", encoding="utf-8", newline="\n")
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(paths["obu"]), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        paths["trace"].write_text(trace, encoding="utf-8", newline="\n")
        fields = {field: small.trace_value(trace, field) for field in (
            "seq_profile", "high_bitdepth", "mono_chrome", "color_range", "reduced_still_picture_header", "tx_mode",
            "max_frame_width_minus_1", "max_frame_height_minus_1", "use_128x128_superblock", "allow_screen_content_tools",
            "disable_cdf_update", "base_q_idx", "enable_cdef", "enable_restoration", "enable_filter_intra",
            "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled", "delta_q_present", "reduced_tx_set")}
        expected = {field: 0 for field in fields}
        expected.update(high_bitdepth=1, mono_chrome=int(monochrome), color_range=1, reduced_still_picture_header=1,
                        max_frame_width_minus_1=size - 1, max_frame_height_minus_1=size - 1, base_q_idx=QINDEX, tx_mode=1)
        if fields != expected:
            raise RuntimeError(f"{name}: unexpected header fields {fields}")
        prefix = small.first_leaf_prefix(stream, trace, fields, width=size, target=target, lossless=False)
        prefix["ac_evidence"] = f"EOB3 exceeds DC in the first actual {target[0]}x{target[1]} rectangular transform"
        if not prefix["target_coding_proven"] or prefix.get("eob_pt") != 3 or prefix.get("tx_type") != 0:
            raise RuntimeError(f"{name}: independently decoded first partition/TX/AC prefix differs")
        pixel_format = "gray10le" if monochrome else "yuv420p10le"
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-xerror", "-y", "-c:v", "libdav1d", "-i", str(paths["obu"]),
                  "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(paths["reference"])]
        decoded = run(decode)
        versions["ffmpeg_libdav1d"] = re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)[0]
        reference = paths["reference"].read_bytes()
        if len(reference) != size * size * (2 if monochrome else 3):
            raise RuntimeError(f"{name}: native sample count mismatch")
        planes = small.native_planes(reference, 10, monochrome, size, size)
        cli_path = args.out / f"{name}.cli.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(paths["obu"]), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_path), "--limit", "1"]
        small.helpers.run_binary(cli)
        if cli_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: stock dav1d native decoders disagree")
        cli_path.unlink()
        for block in syntax["blocks"]:
            for transform in block["transforms"]:
                plane, (x, y), (tw, th) = transform["plane"], transform["origin"], transform["size"]
                stride = size if plane == 0 else size // 2
                pixels = [planes[plane][(y + dy) * stride + x + dx] for dy in range(th) for dx in range(tw)]
                if len(set(pixels)) <= 1:
                    raise RuntimeError(f"{name}: {plane,x,y,tw,th} lacks visible within-transform AC")
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(paths["obu"]), "-c", "copy", "-frames:v", "1", "-f", "avif", str(paths["avif"])]
        run(wrap)
        avif_reference = args.out / f"{name}.avif.native.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1], decode_avif[-1] = str(paths["avif"]), str(avif_reference)
        run(decode_avif)
        if avif_reference.read_bytes() != reference:
            raise RuntimeError(f"{name}: remuxed AVIF native samples differ")
        avif_reference.unlink()
        rgba = mono_helpers.scalar_rgba(paths["avif"].read_bytes(), scalar)
        if len(rgba) != size * size * 4 or any(value != 255 for value in rgba[3::4]):
            raise RuntimeError(f"{name}: scalar RGBA size or opacity mismatch")
        paths["rgba_reference"].write_bytes(rgba)
        decode_rgba = decode.copy()
        decode_rgba[decode_rgba.index("-pix_fmt") + 1], decode_rgba[-1] = "rgba", str(paths["raw_rgba"])
        run(decode_rgba)
        if len(paths["raw_rgba"].read_bytes()) != len(rgba):
            raise RuntimeError(f"{name}: FFmpeg RGBA size mismatch")
        record = {"name": name, "provenance": syntax["provenance"], "dimensions": [size, size], "bit_depth": 10,
                  "monochrome": monochrome, "base_q_idx": QINDEX, "lossless": False, "target_coding_dimensions": list(target),
                  "actual_prefix": prefix, "header_trace": fields, "native_pixel_format": pixel_format,
                  "native_cli_matches_ffmpeg": True, "avif_native_matches_obu": True,
                  "every_transform_has_off_dc_coefficients_and_native_variation": True,
                  "transform_count": sum(len(block["transforms"]) for block in syntax["blocks"]),
                  "uv_owner_count": sum(block["has_chroma"] for block in syntax["blocks"]),
                  "native_plane_ranges": [[min(plane), max(plane)] for plane in planes],
                  "source_image": None, "source_image_note": "complete syntax construction; references are decoder outputs",
                  "rgba_assertion_contract": "scalar libavif full-range UNORM" if monochrome else "established nearest420 conversion from exact native planes",
                  "vendor_rgb_parity_asserted": monochrome,
                  "raw_ffmpeg_vs_scalar_differing_bytes": sum(a != b for a, b in zip(paths["raw_rgba"].read_bytes(), rgba)),
                  "commands": {"trace": trace_command, "decode_native": decode, "dav1d_cli": cli, "wrap_avif": wrap,
                               "decode_avif_native": decode_avif, "decode_raw_rgba": decode_rgba}}
        for key, path in paths.items():
            record[key + "_file"], record[key + "_sha256"] = path.name, sha256(path.read_bytes())
        records.append(record)
        print(f"accepted {name}: {syntax['partition_name']} maxTX={target}, all {record['transform_count']} transforms contain AC", flush=True)
    if len(records) != 8:
        raise RuntimeError("expected exactly eight fixtures")
    target = args.test or ROOT / "_refs/av1_small_lossy_reference_wbtest.mbt"
    if not target.resolve().is_relative_to((ROOT / "_refs").resolve()):
        raise RuntimeError("tests must remain prospective under _refs")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(run([args.moonfmt, "-"], input_text=generated_test(records, args.out)).stdout, encoding="utf-8", newline="\n")
    manifest = {"scope": "exactly eight complete q32 rectangular DCT conformance constructions", "fixture_count": 8,
                "targets": [list(shape) for shape in TARGETS], "versions": versions, "fixtures": records,
                "primary_source_checks": primary, "support_hashes": support_hashes(),
                "prospective_test": str(target), "prospective_test_sha256": sha256(target.read_bytes()),
                "generation_command": [sys.executable, *sys.argv],
                "specification": "https://aomediacodec.github.io/av1-spec/av1-spec.html",
                "validation_boundary": "normative complete syntax and stock-decoder native samples; no MoonBit build was run"}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
