#!/usr/bin/env python3
"""Generate bounded AV1 palette references and independent entropy evidence.

Canonical pixels come from unmodified dav1d decoders. The Python syntax reader
is a deliberately bounded palette/DC/no-residual tracer, not a pixel oracle.
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


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


lf = module("palette_loop_helpers", "generate-av1-loop-filter-reference.py")
mono, large = lf.mono, lf.large
arithmetic = large.arithmetic
run, sha256, read_hashed, rle = lf.run, lf.sha256, lf.read_hashed, lf.rle


def ceil_log2(value: int) -> int:
    return max(0, value - 1).bit_length()


class PaletteTrace:
    def __init__(self, tile: bytes, width: int, height: int, depth: int, monochrome: bool, qindex: int, sb128: bool = False):
        self.reader = arithmetic.MsacDecoder(tile)
        self.tables = arithmetic.Tables()
        self.depth, self.monochrome, self.qindex = depth, monochrome, qindex
        self.width, self.height = width, height
        self.superblock = 128 if sb128 else 64
        self.mi_width, self.mi_height = (width + 7) // 8 * 2, (height + 7) // 8 * 2
        self.blocks = [[None for _ in range(self.mi_width)] for _ in range(self.mi_height)]
        self.palette_y_mode = arithmetic._parse_go_table("DefaultPaletteYModeCdf")
        self.palette_uv_mode = arithmetic._parse_go_table("DefaultPaletteUvModeCdf")
        self.palette_y_size = arithmetic._parse_go_table("DefaultPaletteYSizeCdf")
        self.palette_uv_size = arithmetic._parse_go_table("DefaultPaletteUvSizeCdf")
        self.map_cdfs = [{size: arithmetic._parse_go_table(f"DefaultPaletteSize{size}{label}ColorCdf") for size in range(2, 9)}
                         for label in ("Y", "Uv")]
        self.partition = {128: arithmetic._parse_go_table("DefaultPartitionW128Cdf"),
                          64: self.tables.partition_w64, 32: self.tables.partition_w32,
                          16: arithmetic._parse_go_table("DefaultPartitionW16Cdf"),
                          8: arithmetic._parse_go_table("DefaultPartitionW8Cdf")}
        self.records = []

    def literal(self, bits: int) -> int:
        value = 0
        for _ in range(bits):
            value = value * 2 + self.reader.bool()
        return value

    def ns(self, count: int) -> int:
        bits = ceil_log2(count)
        split = (1 << bits) - count
        value = self.literal(bits - 1)
        return value if value < split else value * 2 - split + self.literal(1)

    def neighbor(self, x: int, y: int):
        return self.blocks[y][x] if x >= 0 and y >= 0 else None

    def cache(self, x: int, y: int, plane: int) -> list[int]:
        neighbors = [self.neighbor(x - 1, y)]
        if y * 4 % 64:
            neighbors.append(self.neighbor(x, y - 1))
        return sorted(set(value for block in neighbors if block is not None for value in block["colors"][plane]))

    def colors(self, count: int, cache: list[int], plane: int) -> tuple[list[int], dict]:
        cached, flags = [], []
        for value in cache:
            if len(cached) == count:
                break
            selected = self.reader.bool()
            flags.append(selected)
            if selected:
                cached.append(value)
        fresh, widths = [], []
        if len(cached) < count:
            fresh.append(self.literal(self.depth))
        if len(cached) + len(fresh) < count:
            bits = self.depth - 3 + self.literal(2)
            while len(cached) + len(fresh) < count:
                widths.append(bits)
                delta = self.literal(bits) + int(plane == 0)
                fresh.append(min((1 << self.depth) - 1, fresh[-1] + delta))
                remaining = (1 << self.depth) - fresh[-1] - int(plane == 0)
                bits = min(bits, ceil_log2(remaining))
        return sorted(cached + fresh), {"cache": cache, "cache_flags": flags, "cached_colors": cached,
                                       "fresh_colors": fresh, "delta_bit_widths": widths}

    def v_colors(self, count: int) -> tuple[list[int], dict]:
        delta_mode = self.reader.bool()
        if not delta_mode:
            values = [self.literal(self.depth) for _ in range(count)]
            return values, {"delta_mode": False}
        bits = self.depth - 4 + self.literal(2)
        values, deltas, wraps = [self.literal(self.depth)], [], []
        for _ in range(1, count):
            delta = self.literal(bits)
            if delta and self.reader.bool():
                delta = -delta
            value = values[-1] + delta
            wraps.append(value < 0 or value >= 1 << self.depth)
            values.append(value % (1 << self.depth))
            deltas.append(delta)
        return values, {"delta_mode": True, "delta_bits": bits, "signed_deltas": deltas, "wrapped": wraps}

    @staticmethod
    def map_context(grid: list[list[int]], x: int, y: int, count: int) -> tuple[int, list[int]]:
        scores = [0] * count
        if x:
            scores[grid[y][x - 1]] += 2
        if y:
            scores[grid[y - 1][x]] += 2
        if x and y:
            scores[grid[y - 1][x - 1]] += 1
        order = sorted(range(count), key=lambda value: (-scores[value], value))
        ranked = [scores[value] for value in order] + [0] * 3
        code = ranked[0] + 2 * ranked[1] + 2 * ranked[2]
        context = [-1, -1, 0, -1, -1, 4, 3, 2, 1][code]
        if context < 0:
            raise RuntimeError("invalid palette neighbor context")
        return context, order

    def color_map(self, width: int, height: int, visible_width: int, visible_height: int,
                  count: int, plane: int) -> tuple[list[list[int]], dict]:
        grid = [[0] * width for _ in range(height)]
        grid[0][0] = self.ns(count)
        contexts = [0] * 5
        rank_counts = [0] * count
        for diagonal in range(1, visible_width + visible_height - 1):
            for x in range(min(diagonal, visible_width - 1), max(0, diagonal - visible_height + 1) - 1, -1):
                y = diagonal - x
                context, order = self.map_context(grid, x, y, count)
                symbol = self.reader.symbol(self.map_cdfs[plane][count][context])
                grid[y][x] = order[symbol]
                contexts[context] += 1
                rank_counts[symbol] += 1
        for y in range(visible_height):
            grid[y][visible_width:] = [grid[y][visible_width - 1]] * (width - visible_width)
        for y in range(visible_height, height):
            grid[y] = grid[visible_height - 1].copy()
        return grid, {"first_index": grid[0][0], "context_counts": contexts, "rank_counts": rank_counts,
                      "entropy_dimensions": [visible_width, visible_height], "padded_dimensions": [width, height]}

    def block(self, x: int, y: int, size: int, block_height: int | None = None) -> None:
        height = size if block_height is None else block_height
        mx, my = x // 4, y // 4
        above, left = self.neighbor(mx, my - 1), self.neighbor(mx - 1, my)
        skip_context = sum(block["skip"] for block in (above, left) if block is not None)
        skip = self.reader.symbol(self.tables.skip[skip_context])
        # The corpus deliberately disables every non-DC luma/chroma mode.
        y_mode = self.reader.symbol(self.tables.y_mode[0][0])
        has_chroma = not self.monochrome and (size >= 8 or (mx & 1)) and (height >= 8 or (my & 1))
        uv_mode = self.reader.symbol((self.tables.uv_mode_cfl if max(size, height) <= 32 else self.tables.uv_mode)[y_mode]) if has_chroma else None
        if y_mode != 0 or (uv_mode is not None and uv_mode != 0):
            raise RuntimeError(f"non-DC stock block at {x},{y}: {y_mode}/{uv_mode}")
        context = int(math.log2(size * height)) - 6
        mode_context = sum(bool(block["colors"][0]) for block in (above, left) if block is not None)
        enabled_y = self.reader.symbol(self.palette_y_mode[context][mode_context])
        y_size = self.reader.symbol(self.palette_y_size[context]) + 2 if enabled_y else 0
        y_colors, y_evidence = self.colors(y_size, self.cache(mx, my, 0), 0) if y_size else ([], {})
        uv_context = int(y_size > 0)
        enabled_uv = self.reader.symbol(self.palette_uv_mode[uv_context]) if has_chroma else 0
        uv_size = self.reader.symbol(self.palette_uv_size[context]) + 2 if enabled_uv else 0
        u_colors, u_evidence = self.colors(uv_size, self.cache(mx, my, 1), 1) if uv_size else ([], {})
        v_colors, v_evidence = self.v_colors(uv_size) if uv_size else ([], {})
        record = {"x": x, "y": y, "width": size, "height": height, "skip": skip, "has_chroma": bool(has_chroma),
                  "palette_bsize_context": context, "y_mode_context": mode_context, "uv_mode_context": uv_context,
                  "colors": [y_colors, u_colors, v_colors], "y_color_syntax": y_evidence,
                  "u_color_syntax": u_evidence, "v_color_syntax": v_evidence, "maps": [], "map_syntax": []}
        self.records.append(record)
        for plane, count in ((0, y_size), (1, uv_size)):
            if not count:
                record["maps"].append([])
                record["map_syntax"].append({})
                continue
            divisor = 1 if plane == 0 else 2
            extra_x = 2 if plane > 0 and size < 8 else 0
            extra_y = 2 if plane > 0 and height < 8 else 0
            visible_width = min(size, self.mi_width * 4 - x) // divisor + extra_x
            visible_height = min(height, self.mi_height * 4 - y) // divisor + extra_y
            grid, evidence = self.color_map(size // divisor + extra_x, height // divisor + extra_y, visible_width, visible_height, count, plane)
            record["maps"].append(grid)
            record["map_syntax"].append(evidence)
        record["txb_all_zero"] = []
        if not skip:
            for plane in range(3 if has_chroma else 1):
                side = size if plane == 0 else size // 2
                tx_context = int(math.log2(side)) - 2
                zero = self.reader.symbol(self.tables.txb_skip[self.tables.qctx(self.qindex)][tx_context][0 if plane == 0 else 7])
                record["txb_all_zero"].append(zero)
                if not zero:
                    raise RuntimeError(f"nonzero residual after palette at {x},{y}, plane {plane}")
        record["residual_complete"] = True
        for yy in range(my, min(self.mi_height, my + height // 4)):
            for xx in range(mx, min(self.mi_width, mx + size // 4)):
                self.blocks[yy][xx] = record

    def partition_node(self, x: int, y: int, size: int) -> None:
        if x >= self.mi_width * 4 or y >= self.mi_height * 4:
            return
        if size == 4:
            self.block(x, y, size)
            return
        above, left = self.neighbor(x // 4, y // 4 - 1), self.neighbor(x // 4 - 1, y // 4)
        context = int(above is not None and above["width"] < size) + 2 * int(left is not None and left["height"] < size)
        has_rows = y + size // 2 < self.mi_height * 4
        has_cols = x + size // 2 < self.mi_width * 4
        if not has_rows and not has_cols:
            symbol = 3
        elif has_rows and has_cols:
            symbol = self.reader.symbol(self.partition[size][context])
        else:
            raise RuntimeError("bounded tracer does not read a one-axis frame-edge partition")
        if symbol == 0:
            self.block(x, y, size)
        elif symbol == 3:
            half = size // 2
            for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
                self.partition_node(x + dx, y + dy, half)
        elif symbol == 8:
            for offset in range(4):
                self.block(x, y + offset * size // 4, size, size // 4)
        elif symbol == 9:
            for offset in range(4):
                self.block(x + offset * size // 4, y, size // 4, size)
        else:
            raise RuntimeError(f"bounded stock tracer encountered rectangular partition {symbol}")

    def read(self) -> list[dict]:
        for y in range(0, self.mi_height * 4, self.superblock):
            for x in range(0, self.mi_width * 4, self.superblock):
                self.partition_node(x, y, self.superblock)
        return self.records


def screen_planes(depth: int, count: int, monochrome: bool) -> tuple[list[list[int]], dict]:
    scale = 1 << (depth - 8)
    base = ([32, 128, 220], [64, 128, 200], [200, 128, 64]) if count == 3 else (
        [20, 60, 100, 140, 180, 220], [32, 70, 108, 146, 184, 222], [222, 184, 146, 108, 70, 32])
    colors = [[value * scale + (index % scale) for index, value in enumerate(plane)] for plane in base]
    output = []
    for plane in range(1 if monochrome else 3):
        size = 64 if plane == 0 else 32
        output.append([colors[plane][(x // 2 + 3 * (y // 2) + (x // 4) * (y // 4)) % count]
                       for y in range(size) for x in range(size)])
    return output, {"name": f"repeated_{count}_color_screen_cells", "palette_input_values": colors[:len(output)],
                    "color_index": "(x//2 + 3*(y//2) + (x//4)*(y//4)) % color_count on each plane",
                    "coded_depth_precision": "base_value*(1<<(depth-8)) + color_index % (1<<(depth-8)); retains nonzero low bits"}


def trace_stream(data: bytes, header: str, width: int, height: int, depth: int, monochrome: bool) -> dict:
    tile, header_bytes = large.frame_tile(data, header)
    tracer = PaletteTrace(tile, width, height, depth, monochrome, lf.field(header, "base_q_idx"), bool(lf.field(header, "use_128x128_superblock")))
    stop = None
    try:
        tracer.read()
    except RuntimeError as error:
        if not str(error).startswith("nonzero residual after palette"):
            raise
        stop = str(error)
    if not tracer.records or not tracer.records[0]["colors"][0]:
        raise RuntimeError("stock candidate did not select an observable first luma palette")
    return {"scope": "independent MSAC partition/mode/palette/map prefix; only all-zero residual transforms are consumed",
            "complete": stop is None, "stop": stop, "frame_header_bytes": header_bytes,
            "tile_entropy_sha256": sha256(tile), "blocks": tracer.records}


def verify_trace_maps(trace: dict, native: list[list[int]], width: int, height: int) -> int:
    checked = 0
    for block in trace["blocks"]:
        for plane in range(len(native)):
            colors = block["colors"][plane]
            zeros = block["txb_all_zero"]
            if not colors or (not block["skip"] and (plane >= len(zeros) or not zeros[plane])):
                continue
            divisor = 1 if plane == 0 else 2
            stride = (width + divisor - 1) // divisor
            rows = (height + divisor - 1) // divisor
            ox, oy = (block["x"], block["y"]) if plane == 0 else (block["x"] // 8 * 4, block["y"] // 8 * 4)
            grid = block["maps"][0 if plane == 0 else 1]
            for y, row in enumerate(grid):
                for x, index in enumerate(row):
                    if ox + x < stride and oy + y < rows:
                        if colors[index] != native[plane][(oy + y) * stride + ox + x]:
                            raise RuntimeError(f"independent palette map differs from native oracle at {plane}:{ox+x},{oy+y}")
                        checked += 1
    return checked


def generated_test(manifest: dict, base: Path) -> str:
    text = lf.generate_test(manifest, base)
    text = text.replace("av1_loop_filter_reference_compare", "av1_palette_reference_compare")
    text = text.replace("external deblocking", "external palette")
    return text.replace("/// Stock and explicitly reconstructed-filter-header libaom deblock streams.\n/// Native reference pixels are independently",
                        "/// Original stock palette streams with independently read palette prefixes.\n/// Native reference pixels are independently")


CONSTRUCTED_CASES = [
    {"name": "size2_mono10_sb128_row64", "width": 128, "height": 128, "depth": 10, "mono": True, "size": 2, "block": 16, "sb128": True},
    {"name": "size4_color12_odd_padding", "width": 53, "height": 51, "depth": 12, "mono": False, "size": 4, "block": 32},
    {"name": "size5_color10_cache", "width": 64, "height": 64, "depth": 10, "mono": False, "size": 5, "block": 16},
    {"name": "size7_color8_large", "width": 64, "height": 64, "depth": 8, "mono": False, "size": 7, "block": 64},
    {"name": "size8_color12_partial_cache_vwrap", "width": 64, "height": 64, "depth": 12, "mono": False, "size": 8, "block": 16, "vary": True, "v_delta": True},
    {"name": "size2_color10_4x16_owner", "width": 16, "height": 16, "depth": 10, "mono": False, "size": 2, "block": 16, "partition": 9},
    {"name": "size2_color10_16x4_owner", "width": 16, "height": 16, "depth": 10, "mono": False, "size": 2, "block": 16, "partition": 8},
]


class PaletteConstruction(PaletteTrace):
    def __init__(self, case: dict):
        super().__init__(b"", case["width"], case["height"], case["depth"], case["mono"], 120, case.get("sb128", False))
        self.encoder = arithmetic.MsacEncoder()
        self.case = case

    def literal(self, value: int, bits: int) -> None:
        if value < 0 or value >= 1 << bits:
            raise RuntimeError(f"literal {value} does not fit {bits} bits")
        for bit in range(bits - 1, -1, -1):
            self.encoder.write_bool((value >> bit) & 1)

    def uniform(self, value: int, count: int) -> None:
        bits = ceil_log2(count)
        split = (1 << bits) - count
        if value < split:
            self.literal(value, bits - 1)
        else:
            self.literal((value + split) // 2, bits - 1)
            self.literal((value + split) & 1, 1)

    def write_colors(self, values: list[int], cache: list[int], plane: int) -> None:
        remaining, selected = values.copy(), 0
        for value in cache:
            if selected == len(values):
                break
            use = value in remaining
            self.encoder.write_bool(int(use))
            if use:
                remaining.remove(value)
                selected += 1
        if not remaining:
            return
        self.literal(remaining[0], self.depth)
        if len(remaining) > 1:
            self.literal(3, 2)
            bits = self.depth
            for previous, value in zip(remaining, remaining[1:]):
                self.literal(value - previous - int(plane == 0), bits)
                bits = min(bits, ceil_log2((1 << self.depth) - value - int(plane == 0)))

    def palette(self, plane: int) -> list[int]:
        count = self.case["size"]
        maximum = (1 << self.depth) - 1
        scale = 1 << (self.depth - 8)
        values = [(24 + (200 * index // (count - 1))) * scale + index % scale for index in range(count)]
        if plane == 1:
            values = [(32 + (180 * index // (count - 1))) * scale + index % scale for index in range(count)]
        elif plane == 2:
            if self.case.get("v_delta"):
                values = [(maximum - index - 2) if index % 2 == 0 else index * 3 - 1 for index in range(count)]
            else:
                values.reverse()
        if plane < 2 and self.case.get("vary"):
            values[-1] += len(self.records) % 4
        return values

    def write_map(self, width: int, height: int, visible_width: int, visible_height: int,
                  count: int, plane: int) -> list[list[int]]:
        grid = [[(x * 3 + y * 5 + (x // 3) * (y // 2) + len(self.records)) % count for x in range(width)] for y in range(height)]
        self.uniform(grid[0][0], count)
        for diagonal in range(1, visible_width + visible_height - 1):
            for x in range(min(diagonal, visible_width - 1), max(0, diagonal - visible_height + 1) - 1, -1):
                y = diagonal - x
                context, order = self.map_context(grid, x, y, count)
                self.encoder.encode_symbol(self.map_cdfs[plane][count][context], order.index(grid[y][x]))
        for y in range(visible_height):
            grid[y][visible_width:] = [grid[y][visible_width - 1]] * (width - visible_width)
        for y in range(visible_height, height):
            grid[y] = grid[visible_height - 1].copy()
        return grid

    def block(self, x: int, y: int, size: int, block_height: int | None = None) -> None:
        height = size if block_height is None else block_height
        mx, my = x // 4, y // 4
        above, left = self.neighbor(mx, my - 1), self.neighbor(mx - 1, my)
        skip_context = sum(block["skip"] for block in (above, left) if block is not None)
        self.encoder.encode_symbol(self.tables.skip[skip_context], 1)
        self.encoder.encode_symbol(self.tables.y_mode[0][0], 0)
        owner = not self.monochrome and (size >= 8 or (mx & 1)) and (height >= 8 or (my & 1))
        if owner:
            uv_cdf = self.tables.uv_mode_cfl if max(size, height) <= 32 else self.tables.uv_mode
            self.encoder.encode_symbol(uv_cdf[0], 0)
        context = int(math.log2(size * height)) - 6
        mode_context = sum(bool(block["colors"][0]) for block in (above, left) if block is not None)
        count = self.case["size"]
        y_colors = self.palette(0)
        self.encoder.encode_symbol(self.palette_y_mode[context][mode_context], 1)
        self.encoder.encode_symbol(self.palette_y_size[context], count - 2)
        self.write_colors(y_colors, self.cache(mx, my, 0), 0)
        u_colors, v_colors = [], []
        if owner:
            self.encoder.encode_symbol(self.palette_uv_mode[1], 1)
            self.encoder.encode_symbol(self.palette_uv_size[context], count - 2)
            u_colors, v_colors = self.palette(1), self.palette(2)
            self.write_colors(u_colors, self.cache(mx, my, 1), 1)
            delta = self.case.get("v_delta", False)
            self.encoder.write_bool(int(delta))
            if delta:
                self.literal(3, 2)
                self.literal(v_colors[0], self.depth)
                maximum = 1 << self.depth
                for previous, value in zip(v_colors, v_colors[1:]):
                    difference = (value - previous + maximum // 2) % maximum - maximum // 2
                    self.literal(abs(difference), self.depth - 1)
                    if difference:
                        self.encoder.write_bool(int(difference < 0))
            else:
                for value in v_colors:
                    self.literal(value, self.depth)
        maps = []
        for plane in range(2 if owner else 1):
            divisor = 1 if plane == 0 else 2
            extra_x = 2 if plane and size < 8 else 0
            extra_y = 2 if plane and height < 8 else 0
            w, h = size // divisor + extra_x, height // divisor + extra_y
            vw = min(size, self.mi_width * 4 - x) // divisor + extra_x
            vh = min(height, self.mi_height * 4 - y) // divisor + extra_y
            maps.append(self.write_map(w, h, vw, vh, count, plane))
        if not owner:
            maps.append([])
        record = {"x": x, "y": y, "width": size, "height": height, "skip": 1,
                  "colors": [y_colors, u_colors, v_colors], "maps": maps, "has_chroma": bool(owner),
                  "txb_all_zero": [], "residual_complete": True}
        self.records.append(record)
        for yy in range(my, min(self.mi_height, my + height // 4)):
            for xx in range(mx, min(self.mi_width, mx + size // 4)):
                self.blocks[yy][xx] = record

    def partition_node(self, x: int, y: int, size: int) -> None:
        if x >= self.mi_width * 4 or y >= self.mi_height * 4:
            return
        above, left = self.neighbor(x // 4, y // 4 - 1), self.neighbor(x // 4 - 1, y // 4)
        context = int(above is not None and above["width"] < size) + 2 * int(left is not None and left["height"] < size)
        symbol = self.case.get("partition", 0) if size == self.case["block"] else 3
        has_rows = y + size // 2 < self.mi_height * 4
        has_cols = x + size // 2 < self.mi_width * 4
        if has_rows and has_cols:
            self.encoder.encode_symbol(self.partition[size][context], symbol)
        elif has_rows or has_cols or symbol != 3:
            raise RuntimeError("construction requires unsupported frame-edge partition")
        if symbol == 0:
            self.block(x, y, size)
        elif symbol == 3:
            half = size // 2
            for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
                self.partition_node(x + dx, y + dy, half)
        elif symbol == 8:
            for offset in range(4):
                self.block(x, y + offset * size // 4, size, size // 4)
        elif symbol == 9:
            for offset in range(4):
                self.block(x + offset * size // 4, y, size // 4, size)


def constructed_headers(case: dict) -> tuple[bytes, bytes]:
    width, height, depth, monochrome = case["width"], case["height"], case["depth"], case["mono"]
    profile = 2 if depth == 12 else 0
    wb, hb = (width - 1).bit_length(), (height - 1).bit_length()
    bits = arithmetic.BitWriter()
    for value, count in ((profile, 3), (1, 1), (1, 1), (0, 5), (wb - 1, 4), (hb - 1, 4), (width - 1, wb), (height - 1, hb)):
        bits.f(value, count)
    bits.f(int(case.get("sb128", False)), 1)
    bits.f(int(case.get("filter_intra", False)), 1)
    for _ in range(4):
        bits.f(0, 1)
    bits.f(int(depth > 8), 1)
    if profile == 2:
        bits.f(1, 1)
    bits.f(int(monochrome), 1)
    bits.f(0, 1)
    bits.f(1, 1)
    if not monochrome:
        if profile == 2:
            bits.f(1, 1)
            bits.f(1, 1)
        bits.f(0, 2)
        bits.f(0, 1)
    bits.f(0, 1)
    bits.trailing()
    sequence = bits.to_bytes()
    bits = arithmetic.BitWriter()
    for value in (0, 1, 0, 0, 0, 1):
        bits.f(value, 1)  # CDF update, screen tools, integer MV, render size, intrabc, uniform tiles.
    bits.f(120, 8)
    bits.f(0, 1)
    if not monochrome:
        bits.f(0, 1)
        bits.f(0, 1)
    for _ in range(3):
        bits.f(0, 1)  # QM, segmentation, delta Q.
    bits.f(0, 6)
    bits.f(0, 6)
    bits.f(0, 3)
    bits.f(0, 1)
    bits.f(int(case.get("tx_select", False)), 1)
    bits.f(0, 1)
    while len(bits.bits) % 8:
        bits.f(0, 1)
    return sequence, bits.to_bytes()


def construct_stream(case: dict) -> tuple[bytes, list[dict]]:
    writer = PaletteConstruction(case)
    writer.read()
    sequence, frame = constructed_headers(case)
    return arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame + writer.encoder.finish()), writer.records


def interlock_stream(kind: str) -> tuple[bytes, dict]:
    """One complete palette+CfL or palette+FI block, SELECT and six AC leaves."""
    lossy = module("palette_interlock_coefficients", "generate-av1-small-lossy-reference.py")
    case = {"width": 16, "height": 16, "depth": 10, "mono": False, "size": 3,
            "block": 16, "filter_intra": True, "tx_select": True}
    writer = PaletteConstruction(case)
    enc = writer.encoder = lossy.CheckedEncoder()
    tables = writer.tables
    enc.encode_symbol(writer.partition[16][0], 0)
    enc.encode_symbol(tables.skip[0], 0)
    enc.encode_symbol(tables.y_mode[0][0], 0)
    cfl = kind == "y_palette_uv_cfl"
    enc.encode_symbol(tables.uv_mode_cfl[0], 13 if cfl else 0)
    if cfl:
        enc.encode_symbol(arithmetic._parse_go_table("DefaultCflSignCdf"), 6)
        alphas = arithmetic._parse_go_table("DefaultCflAlphaCdf")
        enc.encode_symbol(alphas[4], 7)
        enc.encode_symbol(alphas[2], 7)
    enc.encode_symbol(writer.palette_y_mode[2][0], int(cfl))
    colors, maps = [[], [], []], [[], []]
    if cfl:
        enc.encode_symbol(writer.palette_y_size[2], 1)
        colors[0] = writer.palette(0)
        writer.write_colors(colors[0], [], 0)
    else:
        enc.encode_symbol(writer.palette_uv_mode[0], 1)
        enc.encode_symbol(writer.palette_uv_size[2], 1)
        colors[1], colors[2] = writer.palette(1), writer.palette(2)
        writer.write_colors(colors[1], [], 1)
        enc.write_bool(0)
        for value in colors[2]:
            writer.literal(value, 10)
        enc.encode_symbol(arithmetic._parse_go_table("DefaultFilterIntraCdf")[6], 1)
        enc.encode_symbol(arithmetic._parse_go_table("DefaultFilterIntraModeCdf"), 3)
    if cfl:
        maps[0] = writer.write_map(16, 16, 16, 16, 3, 0)
    else:
        maps[1] = writer.write_map(8, 8, 8, 8, 3, 1)
    # SELECT depth follows the entire palette color-map syntax.
    enc.encode_symbol(tables.tx16[0], 1)
    top_level, left_level, top_dc, left_dc = ([[0] * 4 for _ in range(3)] for _ in range(4))
    transforms = []
    qctx = tables.qctx(120)
    pseudo = 0 if cfl else 6
    for plane in range(3):
        positions = ((0, 0), (8, 0), (0, 8), (8, 8)) if plane == 0 else ((0, 0),)
        for x, y in positions:
            mx, my, units = x // 4, y // 4, 2
            above, left = top_level[plane][mx:mx + units], left_level[plane][my:my + units]
            context = arithmetic.txb_skip_ctx_luma(max(above), max(left), False) if plane == 0 else 7
            enc.encode_symbol(tables.txb_skip[qctx][1][context], 0)
            if plane == 0:
                enc.encode_symbol(tables.intra_tx_set1[1][pseudo], 1)
            score = sum(-1 if value == 1 else 1 if value == 2 else 0 for value in top_dc[plane][mx:mx + units] + left_dc[plane][my:my + units])
            sign_context = 1 if score < 0 else 2 if score > 0 else 0
            scan = arithmetic.build_scan(8, 0)
            levels = {scan[0]: 2, scan[1]: 2, scan[2]: 2}
            cumulative, category = arithmetic.encode_leaf_coeffs(enc, tables, 120, 8, int(plane > 0), levels, 0, sign_context)
            top_level[plane][mx:mx + units] = [cumulative] * units
            left_level[plane][my:my + units] = [cumulative] * units
            top_dc[plane][mx:mx + units] = [category] * units
            left_dc[plane][my:my + units] = [category] * units
            transforms.append({"plane": plane, "origin": [x, y], "size": [8, 8], "eob": 3,
                               "tx_type": 0, "all_zero_context": context, "dc_sign_context": sign_context,
                               "positive_quantized_levels": list(map(list, levels.items()))})
    tile = enc.finish()
    replay = arithmetic.MsacDecoder(tile)
    for cdf, symbol in enc.symbols:
        if replay.symbol(cdf) != symbol:
            raise RuntimeError("interlock arithmetic roundtrip failed")
    sequence, frame = constructed_headers(case)
    data = arithmetic.obu(2, b"") + arithmetic.obu(1, sequence) + arithmetic.obu(6, frame + tile)
    return data, {"kind": kind, "case": case, "y_mode": 0, "uv_mode": 13 if cfl else 0,
                  "cfl_alphas": [8, -8] if cfl else [], "filter_intra_mode": None if cfl else 3,
                  "luma_tx_cdf_mode": pseudo, "palette_colors": colors, "palette_maps": maps,
                  "tx_depth": 1, "transforms": transforms, "arithmetic_roundtrip_symbols": len(enc.symbols)}


def interlock_trace(data: bytes, header: str) -> dict:
    fi = module("palette_interlock_filter_reader", "generate-av1-filter-intra-reference.py")
    tile, header_bytes = large.frame_tile(data, header)
    palette = PaletteTrace(tile, 16, 16, 10, False, 120)
    reader = palette.reader = fi.base.Reader(tile, True)
    tables = palette.tables
    if reader.symbol(palette.partition[16][0]) != 0 or reader.symbol(tables.skip[0]) != 0:
        raise RuntimeError("unexpected interlock partition or skip")
    if reader.symbol(tables.y_mode[0][0]) != 0:
        raise RuntimeError("interlock requires DC base mode")
    uv_mode = reader.symbol(tables.uv_mode_cfl[0])
    alpha_values = []
    if uv_mode == 13:
        signs = reader.symbol(arithmetic._parse_go_table("DefaultCflSignCdf"))
        cdfs = arithmetic._parse_go_table("DefaultCflAlphaCdf")
        u, v = (signs + 1) // 3, (signs + 1) % 3
        for plane, sign in enumerate((u, v)):
            context = signs - 2 if plane == 0 else 3 * v + u - 3
            magnitude = reader.symbol(cdfs[context]) + 1 if sign else 0
            alpha_values.append(magnitude * (-1 if sign == 1 else 1))
    elif uv_mode != 0:
        raise RuntimeError("unexpected interlock UV mode")
    enabled_y = reader.symbol(palette.palette_y_mode[2][0])
    y_size = reader.symbol(palette.palette_y_size[2]) + 2 if enabled_y else 0
    y_colors, _ = palette.colors(y_size, [], 0) if y_size else ([], {})
    enabled_uv = reader.symbol(palette.palette_uv_mode[int(y_size > 0)]) if uv_mode == 0 else 0
    uv_size = reader.symbol(palette.palette_uv_size[2]) + 2 if enabled_uv else 0
    u_colors, _ = palette.colors(uv_size, [], 1) if uv_size else ([], {})
    v_colors, _ = palette.v_colors(uv_size) if uv_size else ([], {})
    filter_mode = None
    if not y_size and reader.symbol(arithmetic._parse_go_table("DefaultFilterIntraCdf")[6]):
        filter_mode = reader.symbol(arithmetic._parse_go_table("DefaultFilterIntraModeCdf"))
    maps = [[], []]
    if y_size:
        maps[0], _ = palette.color_map(16, 16, 16, 16, y_size, 0)
    if uv_size:
        maps[1], _ = palette.color_map(8, 8, 8, 8, uv_size, 1)
    before_depth = reader.symbol_count
    depth = reader.symbol(tables.tx16[0])
    if depth != 1:
        raise RuntimeError("SELECT depth did not follow the complete palette map")
    pseudo = (0, 1, 2, 6, 0)[filter_mode] if filter_mode is not None else 0
    coefficients = fi.base.Coefficients(reader, tables, 120, False)
    transforms = []
    for plane in range(3):
        for x, y in (((0, 0), (8, 0), (0, 8), (8, 8)) if plane == 0 else ((0, 0),)):
            mx, my, units = x // 4, y // 4, 2
            above, left = coefficients.above_level[plane][mx:mx + units], coefficients.left_level[plane][my:my + units]
            context = arithmetic.txb_skip_ctx_luma(max(above), max(left), False) if plane == 0 else 7
            if reader.symbol(tables.txb_skip[2][1][context]):
                raise RuntimeError("interlock transform unexpectedly empty")
            tx_symbol = reader.symbol(tables.intra_tx_set1[1][pseudo]) if plane == 0 else None
            if plane == 0 and tx_symbol != 1:
                raise RuntimeError("interlock did not select DCT_DCT")
            ptype = int(plane > 0)
            eob_pt = reader.symbol(tables.eob_pt_64[2][ptype][0]) + 1
            if eob_pt != 3:
                raise RuntimeError("interlock nonzero AC EOB prefix differs")
            extra = reader.symbol(tables.eob_extra[2][1][ptype][0])
            eob = 3 + extra
            quant, scan = [0] * 64, coefficients.scans[8]
            for index in range(eob - 1, -1, -1):
                position = scan[index]
                ctx = coefficients.base_context(quant, 8, 1, position, index, index == eob - 1)
                if index == eob - 1:
                    quant[position] = reader.symbol(tables.coeff_base_eob[2][1][ptype][ctx]) + 1
                else:
                    quant[position] = reader.symbol(tables.coeff_base[2][1][ptype][ctx])
                if quant[position] > 2:
                    raise RuntimeError("interlock exceeds its base-level coefficient scope")
            score = sum(-1 if value == 1 else 1 if value == 2 else 0 for value in coefficients.above_dc[plane][mx:mx + units] + coefficients.left_dc[plane][my:my + units])
            sign_context = 1 if score < 0 else 2 if score > 0 else 0
            for index in range(eob):
                if quant[scan[index]]:
                    sign = reader.symbol(tables.dc_sign[2][ptype][sign_context]) if index == 0 else reader.bool()
                    if sign:
                        raise RuntimeError("interlock unexpectedly has a negative coefficient")
            coefficients.update(plane, mx, my, units, sum(quant), 2 if quant[0] else 0)
            transforms.append({"plane": plane, "origin": [x, y], "size": [8, 8], "eob": eob,
                               "tx_type": 0, "all_zero_context": context, "dc_sign_context": sign_context,
                               "positive_quantized_levels": [[position, quant[position]] for position in scan[:eob] if quant[position]]})
    return {"scope": "complete independent palette/CfL/FI/map/SELECT/coefficient syntax trace",
            "frame_header_bytes": header_bytes, "uv_mode": uv_mode, "cfl_alphas": alpha_values,
            "filter_intra_mode": filter_mode, "luma_tx_cdf_mode": pseudo,
            "palette_colors": [y_colors, u_colors, v_colors], "palette_maps": maps,
            "symbols_before_tx_depth": before_depth, "tx_depth": depth,
            "transforms": transforms, "entropy_end": reader.finish()}


def interlock_main(args) -> int:
    path = args.out / "interlock-manifest.json"
    if args.check_interlocks:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        for record in manifest["fixtures"]:
            for key, value in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    read_hashed(args.out / value, record[key[:-5] + "_sha256"])
            rebuilt, _ = interlock_stream(record["kind"])
            if sha256(rebuilt) != record["obu_sha256"]:
                raise RuntimeError("palette interlock construction is not reproducible")
            header = read_hashed(args.out / record["header_file"], record["header_sha256"]).decode("utf-8")
            observed = interlock_trace(rebuilt, header)
            recorded = json.loads(read_hashed(args.out / record["entropy_file"], record["entropy_sha256"]))
            if observed != recorded:
                raise RuntimeError("complete palette interlock syntax trace changed")
        source = generated_test(manifest, args.out).replace("av1_palette_reference_compare", "av1_palette_interlock_reference_compare")
        source = source.replace("Original stock palette streams with independently read palette prefixes.", "Complete palette/CfL/FI/SELECT conformance streams with independently read syntax.")
        mono.verify_generated_test(manifest, source, args.moonfmt)
        return 0
    fi = module("palette_interlock_vendor_references", "generate-av1-filter-intra-reference.py")
    scalar, scalar_version = fi.base.cfl.mono_helpers.scalar_library(args.libavif_scalar)
    cli_version = run([args.dav1d, "--version"])
    cli_version = (cli_version.stdout + cli_version.stderr).strip()
    records = []
    for kind in ("y_palette_uv_cfl", "uv_palette_y_filter_intra"):
        name = "interlock_10bit_select_" + kind
        data, intended = interlock_stream(kind)
        obu = args.out / (name + ".obu")
        obu.write_bytes(data)
        header_command = [args.ffmpeg, "-hide_banner", "-i", str(obu), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        header = run(header_command).stderr
        fields = {key: lf.field(header, key) for key in ("base_q_idx", "enable_filter_intra", "allow_screen_content_tools",
                  "tx_mode", "mono_chrome", "color_range", "disable_cdf_update", "allow_intrabc", "enable_cdef", "enable_restoration")}
        if fields != {"base_q_idx": 120, "enable_filter_intra": 1, "allow_screen_content_tools": 1,
                       "tx_mode": 2, "mono_chrome": 0, "color_range": 1, "disable_cdf_update": 0,
                       "allow_intrabc": 0, "enable_cdef": 0, "enable_restoration": 0}:
            raise RuntimeError(f"interlock actual header differs: {fields}")
        observed = interlock_trace(data, header)
        for key in ("uv_mode", "cfl_alphas", "filter_intra_mode", "luma_tx_cdf_mode", "palette_colors", "palette_maps", "tx_depth", "transforms"):
            if observed[key] != intended[key]:
                raise RuntimeError(f"interlock complete syntax differs from construction: {key}")
        record = fi.references(args, name, data, 16, 16, 10, False, scalar)
        native = lf.native_planes(read_hashed(args.out / record["reference_file"], record["reference_sha256"]), 16, 16, 10, False)
        residual_evidence = []
        for transform in observed["transforms"]:
            plane = transform["plane"]
            x, y = transform["origin"]
            stride = 16 if plane == 0 else 8
            pixels = [native[plane][(y + yy) * stride + x + xx] for yy in range(8) for xx in range(8)]
            if len(set(pixels)) < 2:
                raise RuntimeError("interlock nonzero AC produced no within-transform native variation")
            info = {"plane": plane, "origin": [x, y], "unique_native_samples": len(set(pixels))}
            if observed["palette_colors"][plane]:
                colors = observed["palette_colors"][plane]
                grid = observed["palette_maps"][0 if plane == 0 else 1]
                differences = [native[plane][(y + yy) * stride + x + xx] - colors[grid[y + yy][x + xx]] for yy in range(8) for xx in range(8)]
                if len(set(differences)) < 2:
                    raise RuntimeError("interlock palette residual has no observable AC variation")
                info["unique_palette_residual_values"] = len(set(differences))
                info["nonzero_palette_residual_samples"] = sum(value != 0 for value in differences)
            residual_evidence.append(info)
        record.update({"kind": kind, "provenance": "complete deterministic normative header and entropy construction, not encoder output or a payload patch",
                       "header": fields, "trace_complete": True, "syntax_summary": {key: observed[key] for key in
                        ("uv_mode", "cfl_alphas", "filter_intra_mode", "luma_tx_cdf_mode", "tx_depth", "symbols_before_tx_depth", "entropy_end")},
                       "palette_sizes": [len(observed["palette_colors"][plane]) for plane in (0, 1)],
                       "all_six_transforms_eob": [transform["eob"] for transform in observed["transforms"]],
                       "native_residual_evidence": residual_evidence,
                       "arithmetic_roundtrip_symbols": intended["arithmetic_roundtrip_symbols"]})
        record["commands"]["trace_headers"] = header_command
        for key, suffix, content in (("header", ".header.txt", header),
                                      ("entropy", ".entropy.json", json.dumps(observed, indent=2) + "\n")):
            filename = args.out / (name + suffix)
            filename.write_text(content, encoding="utf-8")
            record[key + "_file"], record[key + "_sha256"] = filename.name, sha256(filename.read_bytes())
        records.append(record)
        print(f"verified {name}: palettes={record['palette_sizes']}, six EOB3 transforms, complete syntax/trailing-bit verification", flush=True)
    manifest = {"scope": "exactly two palette/CfL and palette/filter-intra interlocks with SELECT depth1 and six nonzero-AC transforms each",
                "dav1d_cli_version": cli_version, "scalar_libavif_version": scalar_version,
                "candidate_limit": 2, "candidate_count": 2, "fixtures": records,
                "syntax_order": "Y/UV modes and CfL alpha, palette colors, eligible filter-intra flag/mode, complete Y/UV palette maps, SELECT tx_depth, transform coefficients",
                "gate_evidence": "Y palette suppresses FI syntax even with enable_filter_intra=1; UV palette does not suppress Y FI mode3; palette does not suppress luma tx_type syntax",
                "oracle": "full independently derived semantic syntax trace reaches legal trailing bits; unmodified two dav1d builds and AVIF remux supply canonical native pixels",
                "generated_test": str(args.interlock_test)}
    source = generated_test(manifest, args.out).replace("av1_palette_reference_compare", "av1_palette_interlock_reference_compare")
    source = source.replace("Original stock palette streams with independently read palette prefixes.", "Complete palette/CfL/FI/SELECT conformance streams with independently read syntax.")
    generated = run([args.moonfmt, "-"], input_text=source).stdout.encode("utf-8")
    args.interlock_test.parent.mkdir(parents=True, exist_ok=True)
    args.interlock_test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


def constructed_main(args) -> int:
    manifest_path = args.out / "constructed-manifest.json"
    if args.check_constructed:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for record in manifest["fixtures"]:
            for key, value in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    read_hashed(args.out / value, record[key[:-5] + "_sha256"])
            rebuilt, _ = construct_stream(record["construction_case"])
            if sha256(rebuilt) != record["obu_sha256"]:
                raise RuntimeError("constructed palette syntax is not reproducible")
        source = generated_test(manifest, args.out).replace("av1_palette_reference_compare", "av1_palette_constructed_reference_compare")
        source = source.replace("Original stock palette streams", "Complete constructed palette conformance streams")
        mono.verify_generated_test(manifest, source, args.moonfmt)
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    scalar, scalar_version = mono.scalar_library(args.libavif_scalar)
    cli_version = run([args.dav1d, "--version"])
    cli_version = (cli_version.stdout + cli_version.stderr).strip()
    records, decoder_versions = [], set()
    for case in CONSTRUCTED_CASES:
        width, height, depth, monochrome = case["width"], case["height"], case["depth"], case["mono"]
        name = "constructed_" + case["name"]
        data, intended = construct_stream(case)
        paths = {key: args.out / f"{name}.{ext}" for key, ext in (("obu", "obu"), ("header", "header.txt"),
                 ("entropy", "entropy.json"), ("reference", "reference.yuv"), ("avif", "avif"))}
        paths["obu"].write_bytes(data)
        header_command = [args.ffmpeg, "-hide_banner", "-i", str(paths["obu"]), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        header = run(header_command).stderr
        paths["header"].write_text(header, encoding="utf-8")
        fields = {key: lf.field(header, key) for key in ("reduced_still_picture_header", "allow_screen_content_tools",
                  "allow_intrabc", "enable_filter_intra", "enable_intra_edge_filter", "enable_cdef", "enable_restoration",
                  "enable_superres", "use_128x128_superblock", "base_q_idx", "using_qmatrix", "segmentation_enabled",
                  "delta_q_present", "tx_mode", "mono_chrome", "color_range", "disable_cdf_update")}
        expected = {key: 0 for key in fields}
        expected.update({"reduced_still_picture_header": 1, "allow_screen_content_tools": 1, "base_q_idx": 120,
                         "tx_mode": 1, "mono_chrome": int(monochrome), "color_range": 1,
                         "use_128x128_superblock": int(case.get("sb128", False))})
        if fields != expected:
            raise RuntimeError(f"constructed palette header mismatch: {fields}")
        evidence = trace_stream(data, header, width, height, depth, monochrome)
        if not evidence["complete"] or len(evidence["blocks"]) != len(intended):
            raise RuntimeError("independent palette reader did not consume every constructed block")
        for actual, intended_block in zip(evidence["blocks"], intended):
            for key in ("x", "y", "width", "height", "skip", "colors", "maps", "has_chroma"):
                if actual[key] != intended_block[key]:
                    raise RuntimeError(f"constructed palette semantic mismatch: {key}")
        pixel_format = ("gray" if depth == 8 else f"gray{depth}le") if monochrome else ("yuv420p" if depth == 8 else f"yuv420p{depth}le")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-xerror", "-y", "-c:v", "libdav1d", "-i", str(paths["obu"]),
                  "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(paths["reference"])]
        result = run(decode)
        decoder_versions.update(re.findall(r"libdav1d\s+([0-9][^\s]*)", result.stderr))
        reference = paths["reference"].read_bytes()
        native = lf.native_planes(reference, width, height, depth, monochrome)
        checked = verify_trace_maps(evidence, native, width, height)
        if checked != sum(len(plane) for plane in native):
            raise RuntimeError("constructed palette index maps do not account for every native sample")
        evidence["independent_palette_map_samples_checked_against_native"] = checked
        paths["entropy"].write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        temporary = args.out / f"{name}.cli.tmp.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(paths["obu"]), "--demuxer", "section5", "--muxer", "yuv",
               "--output", str(temporary), "--limit", "1", "--inloopfilters", "all"]
        lf.cdef.run_binary(cli)
        if temporary.read_bytes() != reference:
            raise RuntimeError("dual dav1d constructed palette references differ")
        temporary.unlink()
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(paths["obu"]), "-c", "copy", "-frames:v", "1", "-f", "avif", str(paths["avif"])]
        run(wrap)
        remux = decode.copy()
        remux[remux.index("-i") + 1] = str(paths["avif"])
        remux[-1] = str(temporary)
        run(remux)
        if temporary.read_bytes() != reference:
            raise RuntimeError("constructed palette AVIF remux reference differs")
        temporary.unlink()
        record = {"name": name, "dimensions": [width, height], "bit_depth": depth, "monochrome": monochrome,
                  "provenance": "complete deterministic normative syntax construction; not encoder output or an entropy mutation",
                  "construction_case": case, "header": fields, "dual_dav1d_exact": True, "avif_remux_native_exact": True,
                  "trace_complete": True, "trace_block_count": len(evidence["blocks"]), "native_palette_map_samples_checked": checked,
                  "actual_palette_sizes": sorted(set(len(colors) for block in evidence["blocks"] for colors in block["colors"] if colors)),
                  "actual_cache_selections": sum(len(block[key].get("cached_colors", [])) for block in evidence["blocks"] for key in ("y_color_syntax", "u_color_syntax")),
                  "actual_partial_cache_blocks": sum(bool(block["y_color_syntax"].get("cached_colors")) and bool(block["y_color_syntax"].get("fresh_colors")) for block in evidence["blocks"]),
                  "actual_v_wraps": sum(sum(block["v_color_syntax"].get("wrapped", [])) for block in evidence["blocks"]),
                  "actual_padded_maps": sum(bool(info) and info["entropy_dimensions"] != info["padded_dimensions"] for block in evidence["blocks"] for info in block["map_syntax"]),
                  "row64_cache_evidence": [{"x": block["x"], "y": block["y"], "y_mode_context": block["y_mode_context"], "cache": block["y_color_syntax"]["cache"]} for block in evidence["blocks"] if block["y"] == 64],
                  "uv_owner_count": sum(block["has_chroma"] for block in evidence["blocks"]),
                  "commands": {"trace_headers": header_command, "decode": decode, "dav1d_all": cli, "remux": wrap, "decode_avif": remux}}
        record["actual_y_palette_sizes"] = sorted(set(len(block["colors"][0]) for block in evidence["blocks"] if block["colors"][0]))
        record["actual_uv_palette_sizes"] = sorted(set(len(block["colors"][1]) for block in evidence["blocks"] if block["colors"][1]))
        if case.get("sb128"):
            reset = next(block for block in evidence["blocks"] if block["x"] == 0 and block["y"] == 64)
            if reset["y_mode_context"] != 1 or reset["y_color_syntax"]["cache"]:
                raise RuntimeError("constructed SB128 fixture did not observe the independent row64 cache reset")
        if case.get("vary") and record["actual_partial_cache_blocks"] == 0:
            raise RuntimeError("constructed partial color cache reuse was not observed")
        if case.get("v_delta") and record["actual_v_wraps"] == 0:
            raise RuntimeError("constructed V delta wrap was not observed")
        if width == 53 and record["actual_padded_maps"] != 6:
            raise RuntimeError("constructed MI-edge map padding was not observed")
        if case.get("partition") in (8, 9) and record["uv_owner_count"] != 2:
            raise RuntimeError("constructed four-axis UV ownership was not observed")
        if monochrome:
            rgba = mono.scalar_rgba(paths["avif"].read_bytes(), scalar)
            gray = rgba[::4]
            maximum = (1 << depth) - 1
            if gray != bytes((value * 255 + maximum // 2) // maximum for value in native[0]):
                raise RuntimeError("constructed palette scalar mono UNORM differs")
            paths["gray8"] = args.out / f"{name}.gray8.raw"
            paths["gray8"].write_bytes(gray)
        for key, filename in paths.items():
            record[key + "_file"] = filename.name
            record[key + "_sha256"] = sha256(filename.read_bytes())
        records.append(record)
        print(f"verified {name}: blocks={record['trace_block_count']}, palette={case['size']}, partialcache={record['actual_partial_cache_blocks']}, Vwrap={record['actual_v_wraps']}, paddedmaps={record['actual_padded_maps']}", flush=True)
    if len(decoder_versions) != 1:
        raise RuntimeError("missing/inconsistent constructed decoder version")
    manifest = {"scope": "exactly seven deterministic palette conformance streams complementing the frozen stock12 corpus",
                "dav1d_cli_version": cli_version, "ffmpeg_dav1d_version": next(iter(decoder_versions)), "scalar_libavif_version": scalar_version,
                "candidate_limit": 7, "candidate_count": len(records), "fixtures": records,
                "normative_sources": ["AV1 5.11.46-5.11.50 palette modes/colors/cache/tokens", "pinned libaom decodemv.c478-600, detokenize.c25-62, pred_common.c73-115"],
                "oracle_independence": "writer semantic maps and independently read complete syntax both equal unmodified dav1d native planes at every visible sample",
                "generated_test": str(args.constructed_test)}
    source = generated_test(manifest, args.out).replace("av1_palette_reference_compare", "av1_palette_constructed_reference_compare")
    source = source.replace("Original stock palette streams", "Complete constructed palette conformance streams")
    generated = run([args.moonfmt, "-"], input_text=source).stdout.encode("utf-8")
    args.constructed_test.parent.mkdir(parents=True, exist_ok=True)
    args.constructed_test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-palette"))
    parser.add_argument("--test", type=Path, default=Path("_refs/av1_palette_reference_wbtest.mbt"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe") or "ffprobe")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--interlocks", action="store_true")
    parser.add_argument("--check-interlocks", action="store_true")
    parser.add_argument("--interlock-test", type=Path, default=Path("_refs/av1_palette_interlock_reference_wbtest.mbt"))
    parser.add_argument("--constructed", action="store_true")
    parser.add_argument("--check-constructed", action="store_true")
    parser.add_argument("--constructed-test", type=Path, default=Path("_refs/av1_palette_constructed_reference_wbtest.mbt"))
    args = parser.parse_args()
    if args.interlocks or args.check_interlocks:
        return interlock_main(args)
    if args.constructed or args.check_constructed:
        return constructed_main(args)
    path = args.out / "manifest.json"
    if args.check:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        for record in manifest["fixtures"]:
            for key, value in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    read_hashed(args.out / value, record[key[:-5] + "_sha256"])
        mono.verify_generated_test(manifest, generated_test(manifest, args.out), args.moonfmt)
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    templates = json.loads(Path("tests/fixtures/av1-cdef-frame/manifest.json").read_text(encoding="utf-8"))["fixtures"]
    scalar, scalar_version = mono.scalar_library(args.libavif_scalar)
    cli_version = run([args.dav1d, "--version"])
    cli_version = (cli_version.stdout + cli_version.stderr).strip()
    encoder = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", encoder.stdout + encoder.stderr).group(0)
    records, decoder_versions = [], set()
    for depth, monochrome, count in itertools.product((8, 10, 12), (False, True), (3, 6)):
        name = f"{'mono' if monochrome else 'color'}_64x64_{depth}bit_{count}colors"
        paths = {key: args.out / f"{name}.{ext}" for key, ext in (("source", "source.yuv"),
                 ("input", "input.y4m" if monochrome else "input.yuv"), ("obu", "obu"),
                 ("header", "header.txt"), ("entropy", "entropy.json"), ("reference", "reference.yuv"), ("avif", "avif"))}
        input_planes, pattern = screen_planes(depth, count, monochrome)
        raw = b"".join(mono.pack(plane, depth) for plane in input_planes)
        paths["source"].write_bytes(raw)
        if monochrome:
            chroma = "mono" if depth == 8 else f"420p{depth}"
            carrier = raw if depth == 8 else raw + mono.pack([1 << (depth - 1)] * 2048, depth)
            encoded_input = f"YUV4MPEG2 W64 H64 F1:1 Ip A1:1 C{chroma} XCOLORRANGE=FULL\nFRAME\n".encode() + carrier
        else:
            encoded_input = raw
        paths["input"].write_bytes(encoded_input)
        template = next(case for case in templates if case["name"] == f"cdef_64x64_1tile_{depth}bit")
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        encode.insert(1, "--tune-content=screen")
        if monochrome:
            encode.insert(1, "--monochrome")
        for flag, value in {"--enable-palette": 1, "--enable-directional-intra": 0,
                            "--enable-smooth-intra": 0, "--enable-paeth-intra": 0, "--enable-cdef": 0}.items():
            index = next(i for i, argument in enumerate(encode) if argument.startswith(flag + "="))
            encode[index] = f"{flag}={value}"
        encode[encode.index("-o") + 1] = str(paths["obu"])
        encode[encode.index("-o") + 2] = str(paths["input"])
        run(encode)
        header_command = [args.ffmpeg, "-hide_banner", "-i", str(paths["obu"]), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        header = run(header_command).stderr
        paths["header"].write_text(header, encoding="utf-8")
        fields = {key: lf.field(header, key) for key in ("reduced_still_picture_header", "allow_screen_content_tools",
                  "allow_intrabc", "enable_filter_intra", "enable_intra_edge_filter", "enable_cdef", "enable_restoration",
                  "enable_superres", "use_128x128_superblock", "base_q_idx", "using_qmatrix", "segmentation_enabled",
                  "delta_q_present", "tx_mode", "mono_chrome", "color_range", "disable_cdf_update")}
        if fields["allow_screen_content_tools"] != 1 or fields["reduced_still_picture_header"] != 1 or fields["tx_mode"] != 1:
            raise RuntimeError(f"unexpected palette frame setup: {fields}")
        for key in ("allow_intrabc", "enable_filter_intra", "enable_intra_edge_filter", "enable_cdef", "enable_restoration",
                    "enable_superres", "use_128x128_superblock", "using_qmatrix", "segmentation_enabled", "delta_q_present", "disable_cdf_update"):
            if fields[key]:
                raise RuntimeError(f"unsupported feature present: {key}")
        if any(lf.trace_values(header, "loop_filter_level").values()):
            raise RuntimeError("palette corpus unexpectedly enables deblocking")
        pixel_format = ("gray" if depth == 8 else f"gray{depth}le") if monochrome else ("yuv420p" if depth == 8 else f"yuv420p{depth}le")
        probe = [args.ffprobe, "-v", "error", "-show_entries", "stream=width,height,pix_fmt", "-of", "json", str(paths["obu"])]
        if json.loads(run(probe).stdout)["streams"] != [{"width": 64, "height": 64, "pix_fmt": pixel_format}]:
            raise RuntimeError("decoded stream native layout differs")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(paths["obu"]),
                  "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(paths["reference"])]
        decoded = run(decode)
        decoder_versions.update(re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr))
        reference = paths["reference"].read_bytes()
        native = lf.native_planes(reference, 64, 64, depth, monochrome)
        temporary = args.out / f"{name}.cli.tmp.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(paths["obu"]), "--demuxer", "section5", "--muxer", "yuv",
               "--output", str(temporary), "--limit", "1", "--inloopfilters", "all"]
        lf.cdef.run_binary(cli)
        if temporary.read_bytes() != reference:
            raise RuntimeError("dual dav1d palette reference differs")
        temporary.unlink()
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(paths["obu"]), "-c", "copy", "-frames:v", "1", "-f", "avif", str(paths["avif"])]
        run(wrap)
        remux_decode = decode.copy()
        remux_decode[remux_decode.index("-i") + 1] = str(paths["avif"])
        remux_decode[-1] = str(temporary)
        run(remux_decode)
        if temporary.read_bytes() != reference:
            raise RuntimeError("palette AVIF remux native differs")
        temporary.unlink()
        evidence = trace_stream(paths["obu"].read_bytes(), header, 64, 64, depth, monochrome)
        evidence["independent_palette_map_samples_checked_against_native"] = verify_trace_maps(evidence, native, 64, 64)
        paths["entropy"].write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        record = {"name": name, "dimensions": [64, 64], "bit_depth": depth, "monochrome": monochrome,
                  "provenance": "untouched original libaom full stream", "input_pattern": pattern, "header": fields,
                  "dual_dav1d_exact": True, "avif_remux_native_exact": True,
                  "trace_complete": evidence["complete"], "trace_stop": evidence["stop"],
                  "trace_block_count": len(evidence["blocks"]),
                  "actual_palette_sizes": sorted(set(len(colors) for block in evidence["blocks"] for colors in block["colors"] if colors)),
                  "actual_cache_selections": sum(len(block[key].get("cached_colors", [])) for block in evidence["blocks"] for key in ("y_color_syntax", "u_color_syntax")),
                  "native_palette_map_samples_checked": evidence["independent_palette_map_samples_checked_against_native"],
                  "palette_colors_with_nonzero_low_bits": sum(value % (1 << (depth - 8)) != 0 for block in evidence["blocks"] for plane in block["colors"] for value in plane),
                  "commands": {"encode": encode, "trace_headers": header_command, "probe": probe, "decode": decode,
                               "dav1d_all": cli, "remux": wrap, "decode_avif": remux_decode}}
        if monochrome:
            rgba = mono.scalar_rgba(paths["avif"].read_bytes(), scalar)
            gray = rgba[::4]
            maximum = (1 << depth) - 1
            if gray != bytes((value * 255 + maximum // 2) // maximum for value in native[0]):
                raise RuntimeError("palette scalar mono UNORM mismatch")
            paths["gray8"] = args.out / f"{name}.gray8.raw"
            paths["gray8"].write_bytes(gray)
        for key, filename in paths.items():
            record[key + "_file"] = filename.name
            record[key + "_sha256"] = sha256(filename.read_bytes())
        records.append(record)
        print(f"verified {name}: sizes={record['actual_palette_sizes']}, cache={record['actual_cache_selections']}, blocks={record['trace_block_count']}, complete={record['trace_complete']}", flush=True)
    if len(decoder_versions) != 1:
        raise RuntimeError("missing/inconsistent FFmpeg dav1d version")
    manifest = {"scope": "12 stock palette screen-texture candidates, color/mono at8/10/12 bits and two few-color textures",
                "encoder_version": encoder_version, "dav1d_cli_version": cli_version,
                "ffmpeg_dav1d_version": next(iter(decoder_versions)), "scalar_libavif_version": scalar_version,
                "candidate_limit": 12, "candidate_count": len(records), "fixtures": records,
                "syntax_evidence": "independent Python MSAC palette/DC/no-residual prefix using pinned AV1 default CDFs; first nonzero residual stops tracing honestly",
                "pixel_oracle": "unmodified dual dav1d and no-reencode AVIF native references; tracer output is not the pixel oracle",
                "color_rgba_policy": "existing PixelForge nearest420 conversion of independently verified native YUV; no vendor color-RGBA parity claim",
                "generated_test": str(args.test)}
    generated = run([args.moonfmt, "-"], input_text=generated_test(manifest, args.out)).stdout.encode("utf-8")
    args.test.parent.mkdir(parents=True, exist_ok=True)
    args.test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
