#!/usr/bin/env python3
"""Directional AV1 tile wiring fixtures with canonical external native pixels.

Bounded stock matrix:8/10/12-bit x four directional textures,32x32 fixed16.
Bounded construction matrix:8 explicit partition/mode/angle context streams.
Stock flags alone do not prove mode coverage. All expected planes come from
two unmodified dav1d decoders and must survive AVIF remux. Tests stay in _refs.
"""

# The entropy-only reader adapts go-av1's normative decoder/table definitions.
# BSD 2-Clause License
# Copyright (c) 2026, Oleksandr Zhabotynskyi
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


cfl = module("directional_tile_helpers", "generate-av1-cfl-reference.py")
small, arithmetic = cfl.small, cfl.arithmetic
large = small.large
run, sha256, trace_value = cfl.run, cfl.sha256, cfl.trace_value


# Independent entropy-only reader; normative Go tables, no MoonBit decoder state.
Y_CONTEXT = (0, 1, 2, 3, 4, 4, 4, 4, 3, 0, 1, 2, 0)
UV_TX_TYPE = (0, 1, 2, 0, 3, 1, 2, 2, 1, 3, 1, 2, 3)
INTRA_SET2 = (9, 0, 3, 1, 2)
INTRA_SET1 = (9, 0, 10, 11, 3, 1, 2)


class UnsupportedStock(ValueError):
    pass


def field(trace: str, name: str, default=None) -> int:
    values = re.findall(r"\b" + re.escape(name) + r"\s+[^=\n]*=\s*(-?\d+)", trace)
    if values:
        return int(values[-1])
    if default is not None:
        return default
    raise UnsupportedStock(f"missing header field: {name}")


def header_fields(trace: str) -> dict[str, int]:
    names = ("seq_profile", "high_bitdepth", "mono_chrome", "max_frame_width_minus_1",
             "max_frame_height_minus_1", "base_q_idx", "tx_mode", "reduced_tx_set",
             "allow_screen_content_tools", "disable_cdf_update", "enable_filter_intra",
             "enable_cdef", "enable_restoration", "segmentation_enabled", "delta_q_present",
             "tile_cols_log2", "tile_rows_log2")
    fields = {name: field(trace, name) for name in names}
    fields["twelve_bit"] = field(trace, "twelve_bit", 0)
    fields["subsampling_x"] = field(trace, "subsampling_x", 1)
    fields["subsampling_y"] = field(trace, "subsampling_y", 1)
    fields["allow_intrabc"] = field(trace, "allow_intrabc", 0)
    fields["frame_type"] = field(trace, "frame_type", 0)
    fields["bit_depth"] = 8 if not fields["high_bitdepth"] else 12 if fields["twelve_bit"] else 10
    expected = {"mono_chrome": 0, "max_frame_width_minus_1": 31, "max_frame_height_minus_1": 31,
                "tx_mode": 1, "enable_filter_intra": 0, "enable_cdef": 0, "enable_restoration": 0,
                "segmentation_enabled": 0, "delta_q_present": 0, "tile_cols_log2": 0,
                "tile_rows_log2": 0, "subsampling_x": 1, "subsampling_y": 1,
                "allow_intrabc": 0, "frame_type": 0}
    for name, value in expected.items():
        if fields[name] != value:
            raise UnsupportedStock(f"header {name}={fields[name]}, requires {value}")
    if fields["base_q_idx"] <= 0:
        raise UnsupportedStock("reader requires nonlossless base_q_idx > 0")
    loop_levels = re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]*=\s*(\d+)", trace)
    if not loop_levels or any(int(value) for value in loop_levels):
        raise UnsupportedStock("reader requires explicitly disabled loop-filter levels")
    return fields


class Reader(arithmetic.MsacDecoder):
    def __init__(self, tile: bytes, allow_update: bool):
        super().__init__(tile, allow_update)
        self.symbol_count = 0
        self.where = "tile start"

    def symbol(self, cdf):
        value = super().symbol(cdf)
        self.symbol_count += 1
        if self.symbol_max_bits < -14:
            raise UnsupportedStock(f"{self.where}: entropy exceeded allowed 14 padding bits")
        return value

    def finish(self) -> dict[str, int]:
        # AV1 exit_symbol: real bit position minus the remaining lookahead.
        trailing = self.bit_pos - min(15, self.symbol_max_bits + 15)
        total = len(self.data) * 8
        if trailing < 0 or trailing >= total:
            raise UnsupportedStock(f"invalid tile trailing-bit position {trailing}/{total}")
        bit = lambda offset: (self.data[offset >> 3] >> (7 - (offset & 7))) & 1
        if bit(trailing) != 1 or any(bit(i) for i in range(trailing + 1, total)):
            raise UnsupportedStock(f"complete square-block decode did not reach conforming tile trailing bits at {trailing}/{total}")
        return {"symbols": self.symbol_count, "physical_bit_position": self.bit_pos,
                "symbol_max_bits": self.symbol_max_bits, "trailing_bit_position": trailing,
                "tile_bits": total}


class Coefficients:
    def __init__(self, reader: Reader, tables, qindex: int, reduced_tx_set: bool):
        self.reader, self.tables, self.qcontext = reader, tables, tables.qctx(qindex)
        self.reduced_tx_set = reduced_tx_set
        scan_path = ROOT / "_refs/go-av1/decode/scans_all_gen.go"
        self.scans = {side: arithmetic._parse_go_table(f"scan_def{side}x{side}", scan_path) for side in (4, 8, 16)}
        self.offsets = arithmetic._parse_go_table("coeffBaseCtxOffset", ROOT / "_refs/go-av1/decode/scan_gen.go")
        self.above_level = [[0] * size for size in (8, 4, 4)]
        self.left_level = [[0] * size for size in (8, 4, 4)]
        self.above_dc = [[0] * size for size in (8, 4, 4)]
        self.left_dc = [[0] * size for size in (8, 4, 4)]

    def base_context(self, quant, side, tx_context, position, scan_index, eob):
        if eob:
            return 0 if scan_index == 0 else 1 if scan_index <= side * side // 8 else 2 if scan_index <= side * side // 4 else 3
        row, col = divmod(position, side)
        if position == 0:
            return 0
        magnitude = sum(min(quant[(row + dr) * side + col + dc], 3)
                        for dr, dc in ((0, 1), (1, 0), (1, 1), (0, 2), (2, 0))
                        if row + dr < side and col + dc < side)
        return min((magnitude + 1) >> 1, 4) + self.offsets[tx_context][min(row, 4)][min(col, 4)]

    @staticmethod
    def br_context(quant, side, position):
        row, col = divmod(position, side)
        magnitude = sum(min(quant[(row + dr) * side + col + dc], 15)
                        for dr, dc in ((0, 1), (1, 0), (1, 1))
                        if row + dr < side and col + dc < side)
        magnitude = min((magnitude + 1) >> 1, 6)
        return magnitude if position == 0 else magnitude + (7 if row < 2 and col < 2 else 14)

    def update(self, plane, x4, y4, units, level, dc):
        self.above_level[plane][x4:x4 + units] = [level] * units
        self.left_level[plane][y4:y4 + units] = [level] * units
        self.above_dc[plane][x4:x4 + units] = [dc] * units
        self.left_dc[plane][y4:y4 + units] = [dc] * units

    def read(self, plane, x, y, coding_side, skip, y_mode, uv_mode):
        reader, tables = self.reader, self.tables
        side = coding_side if plane == 0 else max(4, coding_side // 2)
        tx_context, ptype = side.bit_length() - 3, int(plane > 0)
        x4, y4, units = x // 4, y // 4, side // 4
        if skip:
            self.update(plane, x4, y4, units, 0, 0)
            return {"plane": plane, "size": [side, side], "skipped_by_block": True, "eob": 0}
        above = self.above_level[plane][x4:x4 + units] + self.above_dc[plane][x4:x4 + units]
        left = self.left_level[plane][y4:y4 + units] + self.left_dc[plane][y4:y4 + units]
        skip_context = 0 if plane == 0 else 7 + int(any(above)) + int(any(left))
        zero = reader.symbol(tables.txb_skip[self.qcontext][tx_context][skip_context])
        result = {"plane": plane, "size": [side, side], "all_zero_context": skip_context, "all_zero": zero}
        if zero:
            self.update(plane, x4, y4, units, 0, 0)
            return {**result, "eob": 0, "tx_type": 0}
        if plane == 0:
            use_set2 = side == 16 or self.reduced_tx_set
            tx_cdfs = tables.intra_tx_set2 if use_set2 else tables.intra_tx_set1
            tx_symbol = reader.symbol(tx_cdfs[tx_context][y_mode])
            tx_type = (INTRA_SET2 if use_set2 else INTRA_SET1)[tx_symbol]
            result["tx_type_symbol"] = tx_symbol
        else:
            tx_type = UV_TX_TYPE[uv_mode]
        if tx_type not in (0, 1, 2, 3):
            raise UnsupportedStock(f"{reader.where}: unsupported identity/1D transform {tx_type}")
        result["tx_type"] = tx_type
        eob_cdf = {4: tables.eob_pt_16, 8: tables.eob_pt_64, 16: tables.eob_pt_256}[side]
        eob_pt = reader.symbol(eob_cdf[self.qcontext][ptype][0]) + 1
        eob = 1 if eob_pt == 1 else (1 << (eob_pt - 2)) + 1
        if eob_pt >= 3:
            shift = eob_pt - 3
            eob += reader.symbol(tables.eob_extra[self.qcontext][tx_context][ptype][shift]) << shift
            for bit_index in range(shift - 1, -1, -1):
                eob += reader.bool() << bit_index
        if eob > side * side:
            raise UnsupportedStock(f"{reader.where}: EOB {eob} exceeds {side}x{side}")
        quant, scan = [0] * (side * side), self.scans[side]
        br_symbols = 0
        for c in range(eob - 1, -1, -1):
            position = scan[c]
            context = self.base_context(quant, side, tx_context, position, c, c == eob - 1)
            if c == eob - 1:
                level = reader.symbol(tables.coeff_base_eob[self.qcontext][tx_context][ptype][context]) + 1
            else:
                level = reader.symbol(tables.coeff_base[self.qcontext][tx_context][ptype][context])
            if level > 2:
                context = self.br_context(quant, side, position)
                for _ in range(4):
                    br = reader.symbol(tables.coeff_br[self.qcontext][tx_context][ptype][context])
                    br_symbols += 1
                    level += br
                    if br < 3:
                        break
            quant[position] = level
        sign_score = sum(-1 if category == 1 else 1 if category == 2 else 0
                         for category in self.above_dc[plane][x4:x4 + units] + self.left_dc[plane][y4:y4 + units])
        dc_context = 1 if sign_score < 0 else 2 if sign_score > 0 else 0
        dc_category, cumulative, golomb_count = 0, 0, 0
        for c in range(eob):
            position = scan[c]
            sign = 0
            if quant[position]:
                sign = reader.symbol(tables.dc_sign[self.qcontext][ptype][dc_context]) if c == 0 else reader.bool()
            if quant[position] > 14:
                length = 0
                while True:
                    length += 1
                    if length > 20:
                        raise UnsupportedStock(f"{reader.where}: Exp-Golomb exceeds 20 bits")
                    if reader.bool():
                        break
                value = 1
                for _ in range(length - 1):
                    value = (value << 1) | reader.bool()
                quant[position] = value + 14
                golomb_count += 1
            if position == 0 and quant[position] > 0:
                dc_category = 1 if sign else 2
            cumulative += quant[position] & 0xFFFFF
        level = min(cumulative, 63)
        self.update(plane, x4, y4, units, level, dc_category)
        return {**result, "eob": eob, "eob_pt": eob_pt, "dc_sign_context": dc_context,
                "dc_category": dc_category, "level_context": level,
                "coeff_br_symbols": br_symbols, "golomb_coefficients": golomb_count}


def read_stock(stream: bytes, trace: str) -> dict[str, object]:
    fields = header_fields(trace)
    tile, header_bytes = large.frame_tile(stream, trace)
    reader = Reader(tile, allow_update=not fields["disable_cdf_update"])
    tables = arithmetic.Tables()
    angles = arithmetic._parse_go_table("DefaultAngleDeltaCdf")
    palette_y = arithmetic._parse_go_table("DefaultPaletteYModeCdf")
    palette_uv = arithmetic._parse_go_table("DefaultPaletteUvModeCdf")
    coeffs = Coefficients(reader, tables, fields["base_q_idx"], bool(fields["reduced_tx_set"]))
    partitions = {32: tables.partition_w32,
                  16: arithmetic._parse_go_table("DefaultPartitionW16Cdf"),
                  8: arithmetic._parse_go_table("DefaultPartitionW8Cdf")}
    y_modes, skips, mi_sizes = ([[0] * 8 for _ in range(8)] for _ in range(3))
    blocks = []
    partition_trace = []

    def block(x, y, side):
        row, col, units = y // 4, x // 4, side // 4
        reader.where = f"block ({x},{y}) {side}x{side} modes"
        owner = side != 4 or (row % 2 == 1 and col % 2 == 1)
        skip_context = (skips[row - 1][col] if row else 0) + (skips[row][col - 1] if col else 0)
        skip = reader.symbol(tables.skip[skip_context])
        above_mode = y_modes[row - 1][col] if row else 0
        left_mode = y_modes[row][col - 1] if col else 0
        y_mode = reader.symbol(tables.y_mode[Y_CONTEXT[above_mode]][Y_CONTEXT[left_mode]])
        y_delta = reader.symbol(angles[y_mode - 1]) - 3 if side >= 8 and 1 <= y_mode <= 8 else 0
        uv_mode, uv_delta = None, 0
        if owner:
            uv_mode = reader.symbol(tables.uv_mode_cfl[y_mode])
            if uv_mode == 13:
                raise UnsupportedStock(f"{reader.where}: CfL selected despite bounded stock scope")
            uv_delta = reader.symbol(angles[uv_mode - 1]) - 3 if side >= 8 and 1 <= uv_mode <= 8 else 0
        if fields["allow_screen_content_tools"] and side >= 8:
            palette_size_context = 2 * (side.bit_length() - 1) - 6
            if y_mode == 0 and reader.symbol(palette_y[palette_size_context][0]):
                raise UnsupportedStock(f"{reader.where}: luma palette selected")
            if owner and uv_mode == 0 and reader.symbol(palette_uv[0]):
                raise UnsupportedStock(f"{reader.where}: chroma palette selected")
        for r in range(row, row + units):
            for c in range(col, col + units):
                y_modes[r][c], skips[r][c], mi_sizes[r][c] = y_mode, skip, side
        uv_side = max(4, side // 2)
        result = {"origin": [x, y], "coding_size": [side, side], "has_chroma": owner, "skip": skip,
                 "skip_context": skip_context, "y_mode_contexts": [Y_CONTEXT[above_mode], Y_CONTEXT[left_mode]],
                 "y_mode": y_mode, "y_delta": y_delta, "uv_mode": uv_mode, "uv_delta": uv_delta,
                 "tx_sizes": [[side, side]] + ([[uv_side, uv_side]] * 2 if owner else []), "transforms": []}
        for plane in range(3 if owner else 1):
            reader.where = f"block ({x},{y}) {side}x{side} plane {plane} coefficients"
            px, py = (x, y) if plane == 0 else ((col >> 1) * 4, (row >> 1) * 4)
            result["transforms"].append(coeffs.read(plane, px, py, side, skip, y_mode, uv_mode))
        blocks.append(result)

    def partition(x, y, side):
        row, col = y // 4, x // 4
        if side == 4:
            block(x, y, side)
            return
        above = int(row > 0 and mi_sizes[row - 1][col] < side)
        left = int(col > 0 and mi_sizes[row][col - 1] < side)
        context = left * 2 + above
        reader.where = f"node ({x},{y}) {side}x{side} partition"
        value = reader.symbol(partitions[side][context])
        partition_trace.append({"origin": [x, y], "size": side, "context": context, "symbol": value})
        if value == 3:
            half = side // 2
            for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
                partition(x + dx, y + dy, half)
        elif value == 0 and side <= 16:
            block(x, y, side)
        else:
            raise UnsupportedStock(f"{reader.where}: unsupported PARTITION symbol {value}; only NONE/SPLIT and leaves<=16 are accepted")

    partition(0, 0, 32)
    end = reader.finish()
    return {"scope": "all square16/8/4 coding blocks and complete per-plane coefficient syntax; entropy only",
            "headers": fields, "frame_header_bytes": header_bytes, "tile_payload_bytes": len(tile),
            "partitions": partition_trace, "blocks": blocks, "entropy_end": end,
            "directional_y_blocks": sum(1 <= b["y_mode"] <= 8 for b in blocks),
            "directional_uv_blocks": sum(b["uv_mode"] is not None and 1 <= b["uv_mode"] <= 8 for b in blocks),
            "nonzero_y_delta_blocks": sum(b["y_delta"] != 0 for b in blocks),
            "nonzero_uv_delta_blocks": sum(b["uv_delta"] != 0 for b in blocks)}



def stock_source(depth, texture):
    slopes = (0.45, -0.35, -1.6, 2.2)
    planes = []
    for plane in range(3):
        size = 32 if plane == 0 else 16
        values = []
        for y in range(size):
            for x in range(size):
                position = (x + slopes[texture] * y) * (1 if plane == 0 else 2) + plane * 2.75
                value = 128 + (68 - plane * 5) * math.sin(position * math.pi / 9) + 17 * math.cos(position * math.pi / 5)
                values.append(max(0, min((1 << depth) - 1, round(value * (1 << (depth - 8))))))
        planes.append(values)
    return planes


def generated_test(records, directory):
    return (cfl.generated_test(records, directory)
        .replace("scripts/generate-av1-cfl-reference.py", "scripts/generate-av1-directional-tile-reference.py")
        .replace("Actual CfL syntax is recorded independently", "Actual partition/mode/angle syntax is recorded separately")
        .replace("av1_cfl_reference_", "av1_directional_tile_reference_")
        .replace("external CfL", "external directional tile"))


def write_manifest(args, manifest):
    formatted = run([args.moonfmt, "-"], input_text=generated_test(manifest["fixtures"], args.out)).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest["generated_test"], manifest["generated_test_sha256"] = str(args.test), sha256(args.test.read_bytes())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")


def stock(args):
    if (args.out / "manifest.json").exists():
        raise RuntimeError("the bounded stock matrix already exists")
    args.out.mkdir(parents=True, exist_ok=True)
    scalar, scalar_version = cfl.mono_helpers.scalar_library(args.libavif_scalar)
    encoder_help=run([args.aomenc,"--help"])
    dav1d_version=run([args.dav1d,"--version"])
    versions={"encoder":re.search(r"AOMedia Project AV1 Encoder[^\r\n]+",encoder_help.stdout+encoder_help.stderr).group(0),
        "dav1d_cli":(dav1d_version.stdout+dav1d_version.stderr).strip(),"ffmpeg":run([args.ffmpeg,"-version"]).stdout.splitlines()[0],
        "scalar_libavif":scalar_version}
    old = json.loads((ROOT / "tests/fixtures/av1-cfl/manifest.json").read_text(encoding="utf-8"))
    ledger, records = [], []
    for depth, texture in itertools.product((8, 10, 12), range(4)):
        name = f"stock_{depth}bit_texture{texture}_32x32"
        source = b"".join(cfl.mono_helpers.pack(plane, depth) for plane in stock_source(depth, texture))
        source_path, input_path, obu_path, trace_path = (args.out / f"{name}{suffix}" for suffix in (".source.yuv", ".input.y4m", ".obu", ".trace.txt"))
        source_path.write_bytes(source)
        format_name = "420" if depth == 8 else f"420p{depth}"
        input_path.write_bytes(f"YUV4MPEG2 W32 H32 F1:1 Ip A1:1 C{format_name} XCOLORRANGE=FULL\nFRAME\n".encode() + source)
        encode = old["candidates"][0]["encoder_command"].copy()
        changes = {"width": 32, "height": 32, "profile": 2 if depth == 12 else 0, "bit-depth": depth,
            "input-bit-depth": depth, "min-partition-size": 16, "max-partition-size": 16,
            "enable-diagonal-intra": 1, "enable-angle-delta": 1, "enable-intra-edge-filter": 1, "enable-cfl-intra": 0}
        encode[0], encode[-2], encode[-1] = args.aomenc, str(obu_path), str(input_path)
        for index, argument in enumerate(encode):
            for key, value in changes.items():
                if argument.startswith(f"--{key}="):
                    encode[index] = f"--{key}={value}"
        run(encode)
        trace = run([args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]).stderr
        trace_path.write_text(trace, encoding="utf-8", newline="\n")
        fields = {field: trace_value(trace, field) for field in ("disable_cdf_update", "base_q_idx", "tx_mode", "reduced_tx_set",
            "allow_screen_content_tools", "enable_cdef", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter",
            "color_range", "color_description_present_flag", "mono_chrome")}
        if fields["enable_intra_edge_filter"] != 1 or fields["tx_mode"] != 1 or fields["color_range"] != 1 or fields["color_description_present_flag"]:
            raise RuntimeError("directional stock sequence controls differ")
        entry = {"name": name, "provenance": "untouched libaom encoder output", "bit_depth": depth,
            "texture": texture, "dimensions": [32, 32], "encoder_partition_bounds": [16,16], "header_trace": fields,
            "encoder_command": encode, "outcome": "native validated; complete mode/delta trace pending"}
        for key, path in (("source", source_path), ("input", input_path), ("obu", obu_path), ("trace", trace_path)):
            entry[key + "_file"], entry[key + "_sha256"] = path.name, sha256(path.read_bytes())
        ledger.append(entry)
        record = cfl.references(args, name, obu_path.read_bytes(), 32, 32, depth, scalar)
        record.update({"provenance": entry["provenance"], "header_trace": fields, "mode_evidence": "pending full independent entropy trace"})
        records.append(record)
        print(f"{name}: complete dual-dav1d and AVIF native equality; mode/delta evidence pending", flush=True)
    versions["ffmpeg_libdav1d"]=records[0]["ffmpeg_libdav1d"]
    write_manifest(args, {"scope": "bounded12 stock directional candidates; actual modes require complete trace","versions":versions,
        "candidate_limit": 12, "scalar_libavif_version": scalar_version, "candidates": ledger, "fixtures": records,
        "generation_command": [sys.executable, *sys.argv], "test_status": "prospective under _refs; no MoonBit build",
        "reference_contract": "canonical native planes; color API RGBA uses established nearest420 converter, vendor RGB retained without parity assertion"})


def headers(width, height, sb128=False, tiles=1, tile_size_bytes=2):
    writer = arithmetic.BitWriter()
    wb, hb = (width - 1).bit_length(), (height - 1).bit_length()
    for value, bits in ((0, 3), (1, 1), (1, 1), (0, 5), (wb - 1, 4), (hb - 1, 4), (width - 1, wb), (height - 1, hb)):
        writer.f(value, bits)
    for value in (int(sb128), 0, 1, 0, 0, 0, 1, 0, 0, 1):
        writer.f(value, 1)  # SB128/filter/edge/superres/CDEF/restoration/highbd/mono/description/fullrange.
    writer.f(0, 2)  # chroma position, profile0 implies420.
    writer.f(0, 1)  # separate_uv_delta_q.
    writer.f(0, 1)  # film grain.
    writer.trailing()
    sequence = writer.to_bytes()
    writer = arithmetic.BitWriter()
    for value in (0, 0, 0, 1):
        writer.f(value, 1)  # adaptive CDF, no screen tools, render size, uniform tiles.
    if tiles == 2:
        assert sb128 and width == 256 and height == 128
        writer.f(1, 1)  # increment tile_cols_log2 from0 to1.
        writer.f(0, 1)  # context_update_tile_id.
        writer.f(tile_size_bytes - 1, 2)
    writer.f(32, 8)
    for _ in range(6):
        writer.f(0, 1)  # Ydc/Udc/Uac delta, qmatrix, segmentation, delta_q_present.
    writer.f(0, 6)
    writer.f(0, 6)
    writer.f(0, 3)
    writer.f(0, 1)
    writer.f(1, 1)  # tx_mode_select.
    writer.f(0, 1)  # reduced_tx_set.
    while len(writer.bits) % 8:
        writer.f(0, 1)
    return sequence, writer.to_bytes()


def block(x, y, width, height, *, y_mode=0, uv_mode=0, y_delta=0, uv_delta=0, tx=8, seed=0):
    return {"origin": [x, y], "dimensions": [width, height], "y_mode": y_mode, "uv_mode": uv_mode,
            "y_delta": y_delta, "uv_delta": uv_delta, "tx": tx, "seed": seed}


def conformance_plans():
    plans = []
    for family, partitions in (("top_right", ("split", "vert_a")), ("bottom_left", ("split", "vert_b"))):
        for partition in partitions:
            leaves = ([block(0,0,8,8,seed=0), block(8,0,8,8,seed=1), block(0,8,8,8,seed=2), block(8,8,8,8,seed=3)] if partition == "split" else
                      [block(0,0,8,8,seed=0), block(0,8,8,8,seed=2), block(8,0,8,16,seed=1)] if partition == "vert_a" else
                      [block(0,0,8,16,seed=0), block(8,0,8,8,seed=1), block(8,8,8,8,seed=3)])
            origin = [0, 8] if family == "top_right" else [8, 0]
            for leaf in leaves:
                if leaf["origin"] == origin:
                    leaf.update(y_mode=3 if family == "top_right" else 7, uv_mode=3 if family == "top_right" else 7)
            plans.append({"name": f"constructed_{family}_{partition}_16x16", "width": 16, "height": 16,
                "partition": partition, "leaves": leaves, "context_target": {"origin": origin, "availability": family}})
    for smooth_plane in ("y", "uv"):
        leaves = [block(0,0,16,16,seed=0), block(16,0,16,16,seed=1), block(0,16,16,16,seed=2), block(16,16,16,16,y_mode=1,uv_mode=1,y_delta=-3,uv_delta=-3,seed=3)]
        for leaf in leaves[1:3]:
            leaf[smooth_plane + "_mode"] = 9
        plans.append({"name": f"constructed_smooth_{smooth_plane}_32x32", "width": 32, "height": 32,
            "partition": "split32", "leaves": leaves, "context_target": {"origin": [16,16], "smooth_neighbor_plane": smooth_plane,
            "luma_tx_size":[8,8],"uv_tx_size":[8,8],"reason":"UV8 distinguishes type0/type1 upsampling at81 degrees; UV4 would not"}})
    leaves = [block(x,y,4,4,tx=4,seed=(x//4)+3*(y//4)) for y in range(0,32,4) for x in range(0,32,4)]
    for leaf in leaves:
        if leaf["origin"] == [20,12]:
            leaf.update(uv_mode=3)
    plans.append({"name": "constructed_sub8_owner_crop_29x29", "width": 29, "height": 29,
        "partition": "fixed4", "leaves": leaves, "context_target": {"luma_owner_origin": [20,12], "uv_origin": [8,4],
        "availability": "scaled8x8 top-right table differs from unscaled4x4", "visible_crop": [29,29], "coded_mi": [32,32]}})
    plans.append({"name": "constructed_two_tiles_128_chunks_256x128", "width": 256, "height": 128,
        "partition": "root128", "leaves": [block(0,0,128,128,y_mode=3,uv_mode=7,uv_delta=-1,tx=32,seed=0)],
        "context_target": {"actual_coding_block": [128,128], "tile_columns": 2,
        "luma_tx_origins": [[32,32],[32,64]], "availability": "top-right differs across64 chunks; each tile resets neighbors/CDF"}})
    return plans


def constructed_tile(plan, tile_index=0):
    class Checked(arithmetic.MsacEncoder):
        def __init__(self):
            super().__init__()
            self.events = []
        def encode_symbol(self, cdf, symbol):
            self.events.append((cdf.copy(), symbol))
            super().encode_symbol(cdf, symbol)
    enc, tables = Checked(), arithmetic.Tables()
    lossy = cfl.rectangle_helpers()
    eob_tables = {16:tables.eob_pt_16,32:arithmetic._parse_go_table("DefaultEobPt32Cdf"),64:tables.eob_pt_64}
    angle = arithmetic._parse_go_table("DefaultAngleDeltaCdf")
    tx8 = arithmetic._parse_go_table("DefaultTx8x8Cdf")
    partition8 = arithmetic._parse_go_table("DefaultPartitionW8Cdf")
    partition16 = arithmetic._parse_go_table("DefaultPartitionW16Cdf")
    partition32 = arithmetic._parse_go_table("DefaultPartitionW32Cdf")
    partition128 = arithmetic._parse_go_table("DefaultPartitionW128Cdf")
    units = 32
    y_modes = [[0] * units for _ in range(units)]
    uv_modes = [[0] * units for _ in range(units)]
    tx_sizes = [[(0,0)] * units for _ in range(units)]
    block_sizes = [[(0,0)] * units for _ in range(units)]
    top_level, left_level, top_dc, left_dc = ([[0] * units for _ in range(3)] for _ in range(4))
    mode_context = [0,1,2,3,4,4,4,4,3,0,1,2,0]
    recorded = []
    leaves = {tuple(leaf["origin"]): leaf for leaf in plan["leaves"]}

    def emit_block(leaf):
        x,y = leaf["origin"]
        bw,bh = leaf["dimensions"]
        mx,my,w4,h4 = x//4,y//4,bw//4,bh//4
        ym,um = leaf["y_mode"],leaf["uv_mode"]
        has_chroma = (bw != 4 or mx % 2 == 1) and (bh != 4 or my % 2 == 1)
        enc.encode_symbol(tables.skip[0],0)
        above = y_modes[my-1][mx] if my else 0
        left = y_modes[my][mx-1] if mx else 0
        enc.encode_symbol(tables.y_mode[mode_context[above]][mode_context[left]],ym)
        angle_present = (bw,bh) not in ((4,4),(4,8),(8,4))
        if angle_present and 1 <= ym <= 8:
            enc.encode_symbol(angle[ym-1],leaf["y_delta"]+3)
        if has_chroma:
            enc.encode_symbol((tables.uv_mode_cfl if max(bw,bh)<=32 else tables.uv_mode)[ym],um)
            if angle_present and 1 <= um <= 8:
                enc.encode_symbol(angle[um-1],leaf["uv_delta"]+3)
        maxw,maxh = min(64,bw),min(64,bh)
        tx = leaf["tx"]
        depth = 0
        tw,th = maxw,maxh
        while (tw,th) != (tx,tx):
            if tw != th:
                tw=th=min(tw,th)
            else:
                tw//=2; th//=2
            depth+=1
        if (bw,bh)!=(4,4):
            above_width = tx_sizes[my-1][mx][0] if my else 0
            left_height = tx_sizes[my][mx-1][1] if mx else 0
            context = int(above_width>=maxw)+int(left_height>=maxh)
            size = max(maxw,maxh)
            cdfs = tables.tx64 if size==64 else tables.tx32 if size==32 else tables.tx16 if size==16 else tx8
            enc.encode_symbol(cdfs[context],depth)
        else:
            context = None
        for yy in range(my,my+h4):
            for xx in range(mx,mx+w4):
                y_modes[yy][xx],uv_modes[yy][xx]=ym,um
                tx_sizes[yy][xx]=(tx,tx)
                block_sizes[yy][xx]=(bw,bh)
        evidence = {**leaf,"has_chroma":has_chroma,"y_mode_context":[mode_context[above],mode_context[left]],
            "angle_syntax_present":angle_present,"tx_depth":depth,"tx_depth_context":context,"transforms":[]}
        for cy in range(0,bh,64):
            for cx in range(0,bw,64):
                for plane in range(3 if has_chroma else 1):
                    pw,ph = (min(64,bw),min(64,bh)) if plane==0 else (max(4,min(64,bw)//2),max(4,min(64,bh)//2))
                    txw,txh = (tx,tx) if plane==0 else (min(32,max(4,bw//2)),min(32,max(4,bh//2)))
                    bx,by = (x+cx,y+cy) if plane==0 else ((x//8)*4+cx//2,(y//8)*4+cy//2)
                    for oy in range(0,ph,txh):
                        for ox in range(0,pw,txw):
                            px,py=bx+ox,by+oy
                            sx,sy,nw,nh=px//4,py//4,txw//4,txh//4
                            top=top_level[plane][sx:sx+nw]; lhs=left_level[plane][sy:sy+nh]
                            whole = (txw==bw and txh==bh) if plane==0 else txw*txh==max(4,bw//2)*max(4,bh//2)
                            skip_context = arithmetic.txb_skip_ctx_luma(max(top),max(lhs),whole) if plane==0 else 7+int(any(top))+int(any(lhs))+(0 if whole else 3)
                            enc.encode_symbol(tables.txb_skip[1][lossy.tx_context(txw,txh)][skip_context],0)
                            if plane==0 and txw<32:
                                type_cdf=tables.intra_tx_set2[2][ym] if txw==16 else tables.intra_tx_set1[1 if txw==8 else 0][ym]
                                enc.encode_symbol(type_cdf,1)
                            score=sum(-1 if v==1 else 1 if v==2 else 0 for v in top_dc[plane][sx:sx+nw]+left_dc[plane][sy:sy+nh])
                            dc_context=1 if score<0 else 2 if score>0 else 0
                            seed=leaf["seed"]+tile_index+plane+ox//txw+3*(oy//txh)+cx//64+cy//64
                            if txw==txh:
                                scan=arithmetic.build_scan(txw,0)
                                levels={scan[0]:1+seed%2,scan[1]:2,scan[2]:1+(seed//2)%2}
                                cumulative,category=arithmetic.encode_leaf_coeffs(enc,tables,32,txw,int(plane!=0),levels,0,dc_context)
                            else:
                                coef=lossy.coefficients(enc,tables,eob_tables,(txw,txh),1,dc_context)
                                levels=dict(coef["positive_quantized_levels"])
                                cumulative,category=6,2
                            top_level[plane][sx:sx+nw],left_level[plane][sy:sy+nh]=[cumulative]*nw,[cumulative]*nh
                            top_dc[plane][sx:sx+nw],left_dc[plane][sy:sy+nh]=[category]*nw,[category]*nh
                            evidence["transforms"].append({"plane":plane,"origin":[px,py],"size":[txw,txh],
                                "all_zero_context":skip_context,"dc_sign_context":dc_context,"eob":3,"positive_quantized_levels":list(map(list,levels.items()))})
        recorded.append(evidence)

    def emit_square(x,y,size,fixed4=False):
        context = int(y>0 and block_sizes[y//4-1][x//4][0]<size)+2*int(x>0 and block_sizes[y//4][x//4-1][1]<size)
        cdfs=partition32 if size==32 else partition16 if size==16 else partition8
        split = fixed4 or (x,y) not in leaves or leaves[x,y]["dimensions"] != [size,size]
        enc.encode_symbol(cdfs[context],3 if split else 0)
        if split:
            half=size//2
            for dx,dy in ((0,0),(half,0),(0,half),(half,half)):
                if half==4:
                    emit_block(leaves[x+dx,y+dy])
                else:
                    emit_square(x+dx,y+dy,half,fixed4)
        else:
            emit_block(leaves[x,y])

    if plan["partition"]=="fixed4":
        emit_square(0,0,32,True)
    elif plan["partition"]=="root128":
        enc.encode_symbol(partition128[0],0)
        emit_block(plan["leaves"][0])
    elif plan["partition"] in ("split","split32"):
        emit_square(0,0,32 if plan["partition"]=="split32" else 16)
    else:
        enc.encode_symbol(partition16[0],6 if plan["partition"]=="vert_a" else 7)
        for leaf in plan["leaves"]:
            emit_block(leaf)
    tile=enc.finish()
    decoder=arithmetic.MsacDecoder(tile)
    for cdf,symbol in enc.events:
        if decoder.symbol(cdf)!=symbol:
            raise RuntimeError("constructed directional entropy roundtrip failed")
    return tile,{"tile_index":tile_index,"blocks":recorded,"entropy_symbols_checked":len(enc.events)}


def constructed_stream(plan):
    multiple=plan["partition"]=="root128"
    tiles=[]; syntax=[]
    for index in range(2 if multiple else 1):
        payload,evidence=constructed_tile(plan,index)
        tiles.append(payload); syntax.append(evidence)
    sequence,frame=headers(plan["width"],plan["height"],multiple,len(tiles))
    group=(b"\x00"+(len(tiles[0])-1).to_bytes(2,"little")+tiles[0]+tiles[1]) if multiple else tiles[0]
    data=arithmetic.obu(2,b"")+arithmetic.obu(1,sequence)+arithmetic.obu(6,frame+group)
    return data,{"provenance":"complete constructed q32 directional syntax, not encoder output or patched entropy",
        "plan":plan,"bit_depth":10,"base_q_idx":32,"tx_mode":"SELECT","enable_intra_edge_filter":True,"tiles":syntax}


def conformance(args):
    path=args.out/"manifest.json"
    previous=json.loads(path.read_text(encoding="utf-8"))
    if len(previous["candidates"])!=12:
        raise RuntimeError("bounded construction append requires12 stock candidates")
    cfl.large.verify_existing_artifacts(previous,args.out)
    scalar,_=cfl.mono_helpers.scalar_library(args.libavif_scalar)
    ledger,records=previous["candidates"].copy(),previous["fixtures"].copy()
    for plan in conformance_plans():
        name=plan["name"]
        data,syntax=constructed_stream(plan)
        obu_path,syntax_path,trace_path=(args.out/f"{name}{suffix}" for suffix in (".obu",".syntax.json",".trace.txt"))
        obu_path.write_bytes(data)
        syntax_path.write_text(json.dumps(syntax,indent=2)+"\n",encoding="utf-8",newline="\n")
        trace=run([args.ffmpeg,"-hide_banner","-i",str(obu_path),"-c","copy","-bsf:v","trace_headers","-f","null","-"]).stderr
        trace_path.write_text(trace,encoding="utf-8",newline="\n")
        if trace_value(trace,"base_q_idx")!=32 or trace_value(trace,"tx_mode")!=2:
            raise RuntimeError("constructed directional frame header mismatch")
        record=cfl.references(args,name,data,plan["width"],plan["height"],10,scalar)
        record.update({"provenance":syntax["provenance"],"context_target":plan["context_target"],"syntax_file":syntax_path.name,
            "syntax_sha256":sha256(syntax_path.read_bytes()),"trace_file":trace_path.name,"trace_sha256":sha256(trace_path.read_bytes())})
        records.append(record)
        ledger.append({"name":name,"kind":"constructed","provenance":syntax["provenance"],"obu_file":obu_path.name,"obu_sha256":sha256(data),
            "syntax_file":syntax_path.name,"syntax_sha256":sha256(syntax_path.read_bytes()),"outcome":"complete dual-dav1d native/AVIF validation"})
        print(f"{name}: validated, tiles={len(syntax['tiles'])}, bytes={len(data)}",flush=True)
    cfl.large.verify_existing_artifacts(previous,args.out)
    manifest=previous.copy()
    manifest.update({"candidate_limit":20,"candidates":ledger,"fixtures":records,"scope":"12 stock candidates plus8 explicit directional context conformance streams"})
    write_manifest(args,manifest)


def evidence(args):
    path=args.out/"manifest.json"
    manifest=json.loads(path.read_text(encoding="utf-8"))
    byname={record["name"]:record for record in manifest["fixtures"]}
    all_blocks=[]
    for candidate in manifest["candidates"]:
        if candidate.get("kind")=="constructed":
            continue
        trace=(args.out/candidate["trace_file"]).read_text(encoding="utf-8")
        syntax=read_stock((args.out/candidate["obu_file"]).read_bytes(),trace)
        syntax_path=args.out/(candidate["name"]+".syntax.json")
        syntax_path.write_text(json.dumps(syntax,indent=2)+"\n",encoding="utf-8",newline="\n")
        fields={"syntax_file":syntax_path.name,"syntax_sha256":sha256(syntax_path.read_bytes())}
        candidate.update(fields)
        candidate.pop("fixed_coding_size",None)
        candidate.update(encoder_partition_bounds=[16,16],outcome="complete independent mode/delta/coefficient trace and native validation")
        byname[candidate["name"]].update(fields)
        byname[candidate["name"]]["mode_evidence"]="all blocks independently parsed through conforming tile termination"
        all_blocks.extend(syntax["blocks"])
    angles=(0,90,180,45,135,113,157,203,67)
    modes=[]
    for plane in ("y","uv"):
        counts={}
        for block in all_blocks:
            mode,delta=block[plane+"_mode"],block[plane+"_delta"]
            if mode is None:
                continue
            key=(mode,delta)
            counts[key]=counts.get(key,0)+1
        for (mode,delta),count in sorted(counts.items()):
            angle=angles[mode]+3*delta if 1<=mode<=8 else None
            modes.append({"plane":plane,"mode":mode,"delta":delta,"angle":angle,"count":count,
                "zone":None if angle is None else "axial" if angle in (90,180) else "Z1" if angle<90 else "Z2" if angle<180 else "Z3"})
    pairs={}
    for family,other in (("top_right","vert_a"),("bottom_left","vert_b")):
        first=byname[f"constructed_{family}_split_16x16"]
        second=byname[f"constructed_{family}_{other}_16x16"]
        a=cfl.helpers.unpack_planes((args.out/first["reference_file"]).read_bytes(),16,16,10)
        b=cfl.helpers.unpack_planes((args.out/second["reference_file"]).read_bytes(),16,16,10)
        origin=(0,8) if family=="top_right" else (8,0)
        differences=[]
        for plane in range(3):
            scale=1 if plane==0 else 2
            x,y,size,stride=origin[0]//scale,origin[1]//scale,8//scale,16//scale
            differences.append(sum(a[plane][(y+dy)*stride+x+dx]!=b[plane][(y+dy)*stride+x+dx] for dy in range(size) for dx in range(size)))
        if not all(differences):
            raise RuntimeError("partition availability pair is not observably distinct on every plane")
        pairs[family]={"target_origin":list(origin),"native_target_differing_pixels_yuv":differences}
    oracle=module("directional_tile_context_oracle","generate-av1-directional-reference.py")
    cases=[]
    for family in ("y","uv"):
        name=f"constructed_smooth_{family}_32x32"
        record=byname[name]
        planes=cfl.helpers.unpack_planes((args.out/record["reference_file"]).read_bytes(),32,32,10)
        for plane in range(3):
            origin,stride=(16,32) if plane==0 else (8,16)
            above=[planes[plane][(origin-1)*stride+min(stride-1,origin+i)] for i in range(16)]
            left=[planes[plane][min(stride-1,origin+i)*stride+origin-1] for i in range(16)]
            for smooth in (False,True):
                cases.append({"index":len(cases),"name":name,"plane":plane,"native_reference_file":record["reference_file"],
                    "native_tx_origin":[origin,origin],"mode":1,"angle_delta":-3,"tx_size":1,"bit_depth":10,
                    "n_top":8,"n_left":8,"n_topright":8 if plane==0 else 0,"n_bottomleft":-1,"edge_filter":True,
                    "neighbor_smooth":smooth,"corner":planes[plane][(origin-1)*stride+origin-1],"width":8,"height":8,
                    "sample_count":64,"_above":above,"_left":left})
    oracle.edge_inputs=lambda case:(case["_above"],case["_left"])
    source,_=oracle.reference_source(oracle.load_sources(args.aom_source))
    binary,compiler=oracle.run_reference(args.cc,source,cases)
    differences=[]
    for index in range(0,len(cases),2):
        a=cfl.mono_helpers.unpack(binary[index*128:(index+1)*128],64,10)
        b=cfl.mono_helpers.unpack(binary[(index+1)*128:(index+2)*128],64,10)
        count=sum(x!=y for x,y in zip(a,b))
        if count==0:
            raise RuntimeError("SMOOTH plane context fails to distinguish edge-filter type")
        differences.append({"name":cases[index]["name"],"plane":cases[index]["plane"],"different_prediction_pixels":count})
    for case in cases:
        case.pop("_above");case.pop("_left")
    probe_path=args.out/"smooth_context_probes.u16"
    probe_path.write_bytes(binary)
    sources=[Path(__file__),ROOT/"scripts/craft_av1_fixture.py",ROOT/"scripts/generate-av1-small-lossy-reference.py",
        ROOT/"scripts/generate-av1-directional-reference.py",ROOT/"scripts/generate-av1-cfl-reference.py"]
    sources += list((ROOT/"_refs/go-av1/cdf").glob("*.go"))
    sources += [ROOT/"_refs/go-av1/decode/scans_all_gen.go",ROOT/"_refs/go-av1/decode/scan_gen.go"]
    manifest.update({"scope":"12 stock full-entropy traces plus8 explicit directional context conformance streams",
        "stock_mode_coverage":{"coding_blocks":len(all_blocks),"block_sizes":sorted({tuple(b["coding_size"]) for b in all_blocks}),"modes":modes},
        "partition_context_evidence":pairs,
        "smooth_context_evidence":{"source_revision":oracle.REVISION,"source_hashes":oracle.SOURCE_HASHES,"compiler":compiler,
            "binary_file":probe_path.name,"binary_sha256":sha256(binary),"cases":cases,"type0_vs_type1":differences,
            "boundary":"original C directional predictions from actual native neighboring edges; expected full-image pixels remain dav1d references"},
        "support_hashes":{p.relative_to(ROOT).as_posix():sha256(p.read_bytes()) for p in sources},
        "remaining_coverage":"stock traces prove selected modes/deltas; constructed syntax records context geometry. Sub8/128 expected flags are independently documented by the availability oracle; full images have dual-dav1d references."})
    if (args.out/"README.md").exists():
        manifest.update(documentation_file="README.md",documentation_sha256=sha256((args.out/"README.md").read_bytes()))
    write_manifest(args,manifest)
    print(f"validated12 complete stock traces ({len(all_blocks)} blocks), availability pairs and plane-specific original-C type probes")


def check(args):
    manifest=json.loads((args.out/"manifest.json").read_text(encoding="utf-8"))
    if len(manifest["candidates"])!=20 or len(manifest["fixtures"])!=20:
        raise RuntimeError("expected exactly12 stock plus8 construction cases")
    for record in manifest["candidates"]+manifest["fixtures"]:
        for key,name in record.items():
            if key.endswith("_file") and key[:-5]+"_sha256" in record:
                if sha256((args.out/name).read_bytes())!=record[key[:-5]+"_sha256"]:
                    raise RuntimeError(f"artifact hash mismatch: {name}")
    plans={plan["name"]:plan for plan in conformance_plans()}
    for candidate in manifest["candidates"]:
        if candidate.get("kind")=="constructed":
            data,syntax=constructed_stream(plans[candidate["name"]])
            if data!=(args.out/candidate["obu_file"]).read_bytes():
                raise RuntimeError("constructed byte regeneration mismatch")
        else:
            syntax=read_stock((args.out/candidate["obu_file"]).read_bytes(),(args.out/candidate["trace_file"]).read_text(encoding="utf-8"))
            source=b"".join(cfl.mono_helpers.pack(plane,candidate["bit_depth"]) for plane in stock_source(candidate["bit_depth"],candidate["texture"]))
            if source!=(args.out/candidate["source_file"]).read_bytes():
                raise RuntimeError("stock source pattern changed")
        if syntax!=json.loads((args.out/candidate["syntax_file"]).read_text(encoding="utf-8")):
            raise RuntimeError("actual/generated syntax evidence changed")
    for name,expected in manifest["support_hashes"].items():
        if sha256((ROOT/name).read_bytes())!=expected:
            raise RuntimeError(f"source hash mismatch: {name}")
    probe=manifest["smooth_context_evidence"]
    if sha256((args.out/probe["binary_file"]).read_bytes())!=probe["binary_sha256"]:
        raise RuntimeError("original-C context probe changed")
    formatted=run([args.moonfmt,"-"],input_text=generated_test(manifest["fixtures"],args.out)).stdout
    if args.test.read_text(encoding="utf-8")!=formatted:
        raise RuntimeError("canonical test output changed")
    print("checked20 native fixtures,12 complete stock traces,8 constructed streams and canonical tests")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-directional-tile")
    parser.add_argument("--test", type=Path, default=ROOT / "_refs/av1_directional_tile_reference_wbtest.mbt")
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--conformance", action="store_true")
    parser.add_argument("--evidence", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--cc",default=str(Path.home()/".moon/bin/internal/tcc.exe"))
    parser.add_argument("--aom-source",type=Path,default=Path(os.environ.get("TEMP","."))/"aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    args = parser.parse_args()
    check(args) if args.check else evidence(args) if args.evidence else conformance(args) if args.conformance else stock(args)


if __name__ == "__main__":
    main()
