#!/usr/bin/env python3
"""Reproduce isolated palette-color entropy tests, never complete AV1 frames.

The existing od_ec MsacEncoder writes normative literal/symbol transcripts.
Pinned original AOM CDFs supply every probability; MsacDecoder replays every
operation and verifies the marker and final CDFs. --show prints complete
operation ledgers. --check compares the published WB without writing files.
Generation updates only the selected WB; no Moon builds or AV1 encoders run.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("palette_msac_writer", ROOT / "scripts/craft_av1_fixture.py")
MSAC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MSAC)
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
SOURCE_HASHES = {
    "av1/common/entropymode.c": "13c47672c1e00d77de9b47b5cf7915cf2569a62369bba35dec3ddb5f43f85e24",
    "av1/decoder/decodemv.c": "86fb66757d52ea259eaf4bb654cdee0973daf4797601b892591d55754b8f34ed",
    "av1/common/pred_common.c": "027a67e686ca5f4340bd11b6a55007d64993c1f6c68b5857927e52746c486636",
    "av1/common/pred_common.h": "b9a37cf7fa5df8e7b37214167b6bfb0bace352d331a1b28c7289d9879f4a9c4c",
}


def braced(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def tables(directory):
    source = {}
    for name, digest in SOURCE_HASHES.items():
        data = subprocess.run(["git", "-C", str(directory), "show", f"{REVISION}:{name}"],
                              capture_output=True, check=True).stdout
        assert hashlib.sha256(data).hexdigest() == digest, name
        assert (directory / name).read_bytes().replace(b"\r\n", b"\n") == data, name
        source[name] = data.decode()
    result = {}
    for key in ("y_mode", "uv_mode", "y_size", "uv_size"):
        body = braced(source["av1/common/entropymode.c"], "default_palette_" + key + "_cdf")
        rows = [[int(v.strip()) for v in values.split(",")] + [32768, 0]
                for _, values in re.findall(r"AOM_CDF(\d+)\(([^)]+)\)", body)]
        result[key] = [rows[i:i + 3] for i in range(0, len(rows), 3)] if key == "y_mode" else rows
    assert [len(result[k]) for k in ("y_mode", "uv_mode", "y_size", "uv_size")] == [7, 2, 7, 7]
    return result


class Transcript:
    def __init__(self, name, defaults, adaptive=True):
        self.name, self.adaptive = name, adaptive
        self.defaults, self.cdfs = copy.deepcopy(defaults), copy.deepcopy(defaults)
        self.writer = MSAC.MsacEncoder()
        self.writer.allow_update = adaptive
        self.operations = []

    def symbol(self, key, indexes, value):
        cdf = self.cdfs[key]
        for index in indexes:
            cdf = cdf[index]
        self.operations.append({"kind": "symbol", "cdf": key, "indexes": indexes,
                                "before": cdf.copy(), "value": value})
        self.writer.encode_symbol(cdf, value)

    def literal(self, value, bits, label="literal"):
        assert 0 <= value < 1 << bits
        self.operations.append({"kind": "literal", "bits": bits, "value": value, "label": label})
        for shift in range(bits - 1, -1, -1):
            self.writer.write_bool((value >> shift) & 1)

    def ns(self, value, n):
        assert 1 <= n <= 8 and 0 <= value < n
        if n == 1:
            return
        width, minimum = n.bit_length(), (1 << n.bit_length()) - n
        if value < minimum:
            self.literal(value, width - 1, f"ns({n},{value})")
        else:
            self.literal((value + minimum) >> 1, width - 1, f"ns({n},{value}) prefix")
            self.literal((value + minimum) & 1, 1, f"ns({n},{value}) suffix")

    def marker(self, value=0xA5):
        self.literal(value, 8, "trailing marker")

    def finish(self):
        data = self.writer.finish()
        decoder = MSAC.MsacDecoder(data, self.adaptive)
        cdfs = copy.deepcopy(self.defaults)
        for operation in self.operations:
            if operation["kind"] == "symbol":
                cdf = cdfs[operation["cdf"]]
                for index in operation["indexes"]:
                    cdf = cdf[index]
                assert cdf == operation["before"]
                actual = decoder.symbol(cdf)
            else:
                actual = 0
                for _ in range(operation["bits"]):
                    actual = (actual << 1) | decoder.bool()
            assert actual == operation["value"], (self.name, operation, actual)
        assert cdfs == self.cdfs and decoder.symbol_max_bits >= -14
        self.data = data
        self.end_bits = decoder.symbol_max_bits
        return self


def symbol_y(t, context, count, bsize=0):
    t.symbol("y_mode", [bsize, context], 1)
    t.symbol("y_size", [bsize], count - 2)


def symbol_uv(t, context, count, bsize=0):
    t.symbol("uv_mode", [context], 1)
    t.symbol("uv_size", [bsize], count - 2)


def y_pair(t, first=10, second=20, depth=8):
    t.literal(first, depth, "first Y")
    t.literal(0, 2, "Y bits minus min_bits")
    t.literal(second - first - 1, depth - 3, "Y delta minus1")


def construct(defaults):
    result = {}

    def save(t):
        result[t.name] = t.finish()

    t = Transcript("literal", defaults)
    t.literal(0, 0, "zero-width literal")
    for depth, value in ((8, 0xA6), (10, 0x2D5), (12, 0xB39)):
        t.literal(value, depth)
    t.marker()
    save(t)
    t = Transcript("ns", defaults)
    for n in range(1, 9):
        for value in range(n):
            t.ns(value, n)
            t.marker(0x40 + n * 8 + value)
    save(t)
    for depth in (8, 10, 12):
        maximum = (1 << depth) - 1
        t = Transcript(f"y_clamp_{depth}", defaults)
        symbol_y(t, 0, 4)
        t.literal(maximum - 3, depth, "first Y")
        t.literal(0, 2, "Y min_bits")
        t.literal(0, depth - 3, "Y delta1")
        t.literal(1, 1, "Y delta2 shrunk to1bit")
        t.literal(0, 0, "Y delta1 at range0 clamps to maximum")
        t.marker()
        save(t)
        t = Transcript(f"uv_raw_{depth}", defaults)
        symbol_uv(t, 0, 4)
        t.literal(maximum - 2, depth, "first U")
        t.literal(0, 2, "U min_bits")
        t.literal(0, depth - 3, "U delta0")
        t.literal(3, 2, "U delta3 clamps")
        t.literal(0, 0, "U delta0 at range1")
        t.literal(0, 1, "V raw mode")
        for value in (0, maximum, (1 << (depth - 1)) + 1, 17):
            t.literal(value, depth, "raw V")
        t.marker()
        save(t)
        t = Transcript(f"v_wrap_{depth}", defaults)
        symbol_uv(t, 0, 4)
        t.literal(5, depth, "first U")
        t.literal(0, 2, "U min_bits")
        for _ in range(3):
            t.literal(0, depth - 3, "repeated U delta0")
        t.literal(1, 1, "V delta mode")
        t.literal(0, 2, "V min_bits")
        t.literal(maximum - 2, depth, "first V")
        t.literal(5, depth - 4, "positive V delta")
        t.literal(0, 1, "positive V sign")
        t.literal(5, depth - 4, "negative V delta")
        t.literal(1, 1, "negative V sign")
        t.literal(0, depth - 4, "zero V delta has no sign bit")
        t.marker()
        save(t)
    t = Transcript("all_y_cache", defaults)
    symbol_y(t, 1, 2)
    t.literal(1, 1, "cache5 selected")
    t.literal(1, 1, "cache15 selected; stop before25/35")
    t.marker()
    save(t)
    t = Transcript("partial_y_cache", defaults)
    symbol_y(t, 2, 4)
    for bit in (1, 0, 0, 1):
        t.literal(bit, 1, "cache5,15,25,35 selection")
    y_pair(t)
    t.marker()
    save(t)
    t = Transcript("partial_u_cache", defaults)
    symbol_uv(t, 0, 4)
    for bit in (1, 0, 1):
        t.literal(bit, 1, "cache8,18,30 selection")
    t.literal(10, 8, "first uncached U")
    t.literal(0, 2, "U min_bits")
    t.literal(0, 5, "repeated uncached U")
    t.literal(0, 1, "raw V")
    for value in (1, 2, 3, 4):
        t.literal(value, 8)
    t.marker()
    save(t)
    t = Transcript("all_u_cache", defaults)
    symbol_uv(t, 0, 2)
    t.literal(1, 1, "cache8 selected")
    t.literal(1, 1, "cache18 selected; stop before30")
    t.literal(0, 1, "V raw still required when U is fully cached")
    t.literal(23, 8)
    t.literal(42, 8)
    t.marker()
    save(t)
    t = Transcript("combined", defaults)
    symbol_y(t, 0, 2)
    y_pair(t)
    symbol_uv(t, 1, 2)
    t.literal(30, 8, "first U")
    t.literal(0, 2, "U min_bits")
    t.literal(0, 5, "repeat U")
    t.literal(1, 1, "V delta mode")
    t.literal(0, 2, "V min_bits")
    t.literal(250, 8, "first V")
    t.literal(11, 4, "V positive wrap")
    t.literal(0, 1, "positive sign")
    t.marker()
    save(t)
    for adaptive in (True, False):
        t = Transcript("blocks_adaptive" if adaptive else "blocks_frozen", defaults, adaptive)
        symbol_y(t, 0, 2)
        y_pair(t)
        t.marker(0xA1)
        for context, marker in ((1, 0xA2), (1, 0xA3), (2, 0xA4)):
            symbol_y(t, context, 2)
            t.literal(1, 1, "cache10 selected")
            t.literal(1, 1, "cache20 selected")
            t.marker(marker)
        t.symbol("y_mode", [0, 2], 0)
        t.marker(0xA5)
        symbol_y(t, 0, 2)
        y_pair(t, 30, 40)
        t.marker(0xA6)
        save(t)
    t = Transcript("marker_only", defaults)
    t.marker()
    save(t)
    t = Transcript("geometry_pair", defaults)
    symbol_y(t, 0, 2)
    y_pair(t)
    t.marker()
    save(t)
    t = Transcript("long_y", defaults)
    symbol_y(t, 0, 8)
    t.literal(100, 12, "first Y")
    t.literal(0, 2, "Y min_bits")
    for _ in range(7):
        t.literal(0, 9, "Y delta1")
    t.marker()
    save(t)
    return result


def byte_array(data):
    return "[" + ", ".join(f"b'\\x{value:02x}'" for value in data) + "]"


def test(name, body):
    return f'\n///|\ntest "palette colors {name}" {{\n{body}\n}}\n'


def state_decoder(t, cols=8, rows=8):
    return f"  let state = av1_palette_state({cols}, {rows})\n  let decoder = av1_msac_new({byte_array(t.data)}, {str(t.adaptive).lower()})\n"


def read_call(block, depth=8, ymode=0, uvmode=0, chroma=False, screen=True):
    return f"av1_palette_read_colors(decoder, state, {block}, {depth}, {ymode}, {uvmode}, {str(chroma).lower()}, {str(screen).lower()})"


BLOCK0 = "{ row: 0, col: 0, width: 8, height: 8 }"
BLOCK8 = "{ row: 8, col: 8, width: 8, height: 8 }"


def render(defaults, ts):
    parts = ["/// Isolated palette colors/literal/ns transcripts generated by\n",
             "/// scripts/generate-av1-palette-colors-reference.py using scripts/craft_av1_fixture.py\n",
             f"/// MsacEncoder and pinned AOM {REVISION} CDFs.\n",
             "/// The generator replays all operations through MsacDecoder and checks\n",
             "/// final CDFs and trailing markers. These are not complete AV1 fixtures.\n"]
    parts.append(test("default mode and size CDFs match original AOM", "  let state = av1_palette_state(8, 8)\n" +
                      "\n".join(f"  assert_eq(state.{key}, {values})" for key, values in defaults.items())))
    t = ts["literal"]
    body = state_decoder(t) + "  let before = (decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits)\n"
    body += "  assert_eq(av1_palette_literal(decoder, 0), 0)\n  assert_eq((decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits), before)\n"
    for depth, value in ((8, 0xA6), (10, 0x2D5), (12, 0xB39)):
        body += f"  assert_eq(av1_palette_literal(decoder, {depth}), {value})\n"
    body += "  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n  assert_true(decoder.allow_update)\n  assert_eq(state.y_mode[0][0], [31676, 32768, 0])"
    parts.append(test("nonadaptive literal native bit widths and zero count", body))
    t = ts["ns"]
    body = f"  let decoder = av1_msac_new({byte_array(t.data)}, true)\n"
    body += "  for n in 1..<9 {\n    for value in 0..<n {\n      assert_eq(av1_palette_ns(decoder, n), Some(value))\n      assert_eq(av1_palette_literal(decoder, 8), 0x40 + n * 8 + value)\n    }\n  }\n"
    body += "  let before = (decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits)\n  for n in [0, 9] { assert_eq(av1_palette_ns(decoder, n), None) }\n  assert_eq((decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits), before)"
    parts.append(test("ns every value for1 through8 preserves next marker", body))
    for kind, title in (("y_clamp", "Y plus1 shrinking range and clamp"),
                        ("uv_raw", "U zero delta and clamp V raw native values"),
                        ("v_wrap", "V signed wrap and zero delta omits sign")):
        body = ""
        for depth in (8, 10, 12):
            t, maximum = ts[f"{kind}_{depth}"], (1 << depth) - 1
            body += "  {\n" + state_decoder(t)
            body += f"  assert_true({read_call(BLOCK0, depth, 0 if kind == 'y_clamp' else 1, 0, kind != 'y_clamp')})\n"
            if kind == "y_clamp":
                expected = [maximum - 3, maximum - 2, maximum, maximum]
                body += f"  assert_eq(state.y_colors, {expected})\n  assert_eq(state.u_colors, [])\n  assert_eq(state.v_colors, [])\n"
                body += f"  for index in [0, 1, 8, 9] {{ assert_eq(state.y_neighbors[index], {expected}) }}\n"
            else:
                expected_u = [maximum - 2, maximum - 2, maximum, maximum] if kind == "uv_raw" else [5, 5, 5, 5]
                expected_v = [0, maximum, (1 << (depth - 1)) + 1, 17] if kind == "uv_raw" else [maximum - 2, 2, maximum - 2, maximum - 2]
                body += f"  assert_eq(state.y_colors, [])\n  assert_eq(state.u_colors, {expected_u})\n  assert_eq(state.v_colors, {expected_v})\n"
            body += "  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n  }\n"
        parts.append(test(title, body))
    body = "  let state = av1_palette_state(8, 32)\n"
    body += "  state.y_neighbors[10] = [10, 30, 50]\n  state.y_neighbors[17] = [20, 30, 40]\n  state.u_neighbors[10] = [4, 4, 9]\n  state.u_neighbors[17] = [1, 4, 10]\n"
    body += f"  assert_eq(av1_palette_cache(state, {BLOCK8}, 0), [10, 20, 30, 40, 50])\n  assert_eq(av1_palette_cache(state, {BLOCK8}, 1), [1, 4, 9, 10])\n  assert_eq(av1_palette_mode_context(state, {BLOCK8}), 2)\n"
    body += "  state.y_neighbors[122] = [10, 30, 50]\n  state.y_neighbors[129] = [20, 30, 40]\n  state.u_neighbors[122] = [4, 9]\n  state.u_neighbors[129] = [1, 10]\n"
    block = "{ row: 64, col: 8, width: 8, height: 8 }"
    body += f"  assert_eq(av1_palette_cache(state, {block}, 0), [20, 30, 40])\n  assert_eq(av1_palette_cache(state, {block}, 1), [1, 10])\n  assert_eq(av1_palette_mode_context(state, {block}), 2)"
    parts.append(test("cache merge unique and64pixel boundary preserves mode context", body))
    for key, title, setup, expected in (
        ("all_y_cache", "all Y cached stops reading flags at requested count", "  state.y_neighbors[17] = [5, 15, 25, 35]\n", [5, 15]),
        ("partial_y_cache", "partial Y cache merges selected and transmitted lists", "  state.y_neighbors[10] = [5, 25]\n  state.y_neighbors[17] = [15, 25, 35]\n", [5, 10, 20, 35])):
        body = state_decoder(ts[key]) + setup + f"  assert_true({read_call(BLOCK8)})\n  assert_eq(state.y_colors, {expected})\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)"
        parts.append(test(title, body))
    for key, expected_u, expected_v in (("partial_u_cache", [8, 10, 10, 30], [1, 2, 3, 4]),
                                        ("all_u_cache", [8, 18], [23, 42])):
        body = state_decoder(ts[key]) + "  state.u_neighbors[17] = [8, 18, 30]\n"
        body += f"  assert_true({read_call(BLOCK8, ymode=1, chroma=True)})\n  assert_eq(state.u_colors, {expected_u})\n  assert_eq(state.v_colors, {expected_v})\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)"
        parts.append(test(key + " still decodes V after sorted U merge", body))
    body = state_decoder(ts["combined"]) + f"  assert_true({read_call(BLOCK0, chroma=True)})\n"
    body += "  assert_eq(state.y_colors, [10, 20])\n  assert_eq(state.u_colors, [30, 30])\n  assert_eq(state.v_colors, [250, 5])\n"
    body += f"  assert_eq(state.uv_mode[1], {ts['combined'].cdfs['uv_mode'][1]})\n  assert_eq(state.uv_mode[0], [32461, 32768, 0])\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)"
    parts.append(test("UV palette mode uses Y palette present context", body))
    for key in ("blocks_adaptive", "blocks_frozen"):
        t = ts[key]
        body = state_decoder(t)
        for index, (row, col) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
            block = f"{{ row: {row}, col: {col}, width: 8, height: 8 }}"
            body += f"  assert_true({read_call(block)})\n  assert_eq(state.y_colors, [10, 20])\n  assert_eq(av1_palette_literal(decoder, 8), {0xA1 + index})\n"
        body += "  let old_colors = state.y_colors\n  let old_neighbor = state.y_neighbors[10]\n"
        body += f"  assert_true({read_call(BLOCK8)})\n  assert_eq(state.y_colors, [])\n  for index in [18, 19, 26, 27] {{ assert_eq(state.y_neighbors[index], []) }}\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n"
        block = "{ row: 16, col: 8, width: 8, height: 8 }"
        body += f"  assert_true({read_call(block)})\n  assert_eq(state.y_colors, [30, 40])\n  assert_eq(old_colors, [10, 20])\n  assert_eq(old_neighbor, [10, 20])\n  assert_eq(av1_palette_literal(decoder, 8), 0xa6)\n"
        for field in ("y_mode", "y_size", "uv_mode", "uv_size"):
            body += f"  assert_eq(state.{field}, {t.cdfs[field]})\n"
        parts.append(test(key + " context0 1 2 and nonpalette clearing preserve prior refs", body))
    body = "  for kind in 0..<4 {\n" + state_decoder(ts["marker_only"], 40, 40)
    body += "  state.y_colors = [10, 20]\n  state.u_colors = [30, 40]\n  state.v_colors = [50, 60]\n  state.y_neighbors[0] = [10, 20]\n  state.u_neighbors[0] = [30, 40]\n"
    body += "  let block : Av1SbBlock = { row: 0, col: 0, width: if kind == 2 { 4 } else if kind == 3 { 128 } else { 8 }, height: if kind == 3 { 64 } else { 8 } }\n"
    body += "  let before = (decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits)\n"
    body += "  assert_true(av1_palette_read_colors(decoder, state, block, 8, if kind == 1 { 1 } else { 0 }, if kind == 1 { 1 } else { 0 }, true, kind != 0))\n"
    body += "  assert_eq((decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits), before)\n  assert_eq(state.y_colors, [])\n  assert_eq(state.u_colors, [])\n  assert_eq(state.v_colors, [])\n  assert_eq(state.y_neighbors[0], [])\n  assert_eq(state.u_neighbors[0], [])\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n  }"
    parts.append(test("legal noneligible or gated blocks clear colors without consuming syntax", body))
    body = "  for shape in [(4, 16), (16, 4), (8, 8)] {\n" + state_decoder(ts["geometry_pair"], 3, 3)
    body += "  let (width, height) = shape\n  let block : Av1SbBlock = { row: 8, col: 8, width, height }\n"
    body += f"  assert_true({read_call('block')})\n  assert_eq(state.y_colors, [10, 20])\n  assert_eq(state.y_neighbors[8], [10, 20])\n  assert_eq(state.y_neighbors.length(), 9)\n  for index in 0..<8 {{ assert_eq(state.y_neighbors[index], []) }}\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n  }}"
    parts.append(test("4x16 16x4 eligibility and edge footprint clip to MI bounds", body))
    body = "  let invalid_blocks : Array[Av1SbBlock] = [\n    { row: -4, col: 0, width: 8, height: 8 },\n    { row: 0, col: 2, width: 8, height: 8 },\n    { row: 32, col: 0, width: 8, height: 8 },\n    { row: 0, col: 32, width: 8, height: 8 },\n    { row: 0, col: 0, width: 12, height: 8 },\n  ]\n  for block in invalid_blocks {\n" + state_decoder(ts["geometry_pair"])
    body += "  let before = (decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits)\n"
    body += f"  assert_false({read_call('block')})\n  assert_eq((decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits), before)\n  }}\n"
    body += "  for depth in [0, 7, 9, 11, 13] {\n" + state_decoder(ts["geometry_pair"]) + f"  assert_false({read_call(BLOCK0, 'depth')})\n  }}\n"
    body += "  for mode in [-1, 13] {\n" + state_decoder(ts["geometry_pair"]) + f"  assert_false({read_call(BLOCK0, ymode='mode')})\n  }}"
    parts.append(test("malformed geometry depth and mode rejected", body))
    body = state_decoder(ts["long_y"]) + f"  assert_true({read_call(BLOCK0, 12)})\n  assert_eq(state.y_colors, [100, 101, 102, 103, 104, 105, 106, 107])\n  assert_eq(av1_palette_literal(decoder, 8), 0xa5)\n"
    body += f"  let truncated = av1_msac_new({byte_array(ts['long_y'].data[:1])}, true)\n  assert_false(av1_palette_read_colors(truncated, av1_palette_state(8, 8), {BLOCK0}, 12, 0, 0, false, true))"
    parts.append(test("truncated long palette rejects entropy padding overflow", body))
    return "".join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--test", type=Path, default=ROOT / "av1_palette_colors_wbtest.mbt")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args()
    defaults = tables(args.source_dir)
    transcripts = construct(defaults)
    output = args.test
    generated = subprocess.run([args.moonfmt, "-"], input=render(defaults, transcripts),
                               capture_output=True, text=True, check=True).stdout
    if args.check:
        assert output.read_text(encoding="utf-8") == generated, "palette colors WB changed"
    elif not args.show:
        output.write_text(generated, encoding="utf-8", newline="\n")
    if args.show:
        print(json.dumps({"source_sha256": SOURCE_HASHES,
                          "writer_sha256": hashlib.sha256((ROOT / "scripts/craft_av1_fixture.py").read_bytes()).hexdigest(),
                          "transcripts": [{"name": t.name, "adaptive": t.adaptive, "hex": t.data.hex(),
                                           "operations": t.operations, "final_cdfs": t.cdfs,
                                           "end_symbol_max_bits": t.end_bits} for t in transcripts.values()]}, indent=2))
    else:
        print(f"Verified{len(transcripts)} exact entropy transcripts; generated{generated.count(chr(10) + 'test ')} WB tests")
        for t in transcripts.values():
            print(t.name, t.data.hex(), "end_bits", t.end_bits)
        print("WB SHA256", hashlib.sha256(generated.encode()).hexdigest())


if __name__ == "__main__":
    main()
