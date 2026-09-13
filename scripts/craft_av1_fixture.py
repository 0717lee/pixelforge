#!/usr/bin/env python3
"""Craft small reduced-still-picture AV1 OBU streams with tx_mode=SELECT.

aomenc keeps emitting tx_mode=LARGEST for still pictures, so the tx-mode
multi-leaf tile path cannot be exercised with encoder-produced fixtures. This
script synthesizes bitstreams instead: an od_ec range encoder (ported from the
go-av1 reference decoder's msac/encoder.go, which itself ports libaom's
od_ec_enc) writes the tile symbols in the exact AV1 spec order, and the
resulting OBU is written as a deterministic fixture for the MoonBit regression
tests. This synthesiser does not invoke an external decoder; run
``scripts/verify-av1-reference.py`` separately when an ffmpeg/libdav1d
cross-check is available.
"""

from __future__ import annotations

import argparse
from pathlib import Path

EC_PROB_SHIFT = 6
EC_MIN_PROB = 4


class MsacEncoder:
    """od_ec range encoder operating on spec-form CDFs (decoder dual)."""

    def __init__(self) -> None:
        self.low = 0
        self.rng = 0x8000
        self.cnt = -9
        self.precarry: list[int] = []
        self.allow_update = True

    def encode_symbol(self, cdf: list[int], symbol: int) -> None:
        n = len(cdf) - 1
        fl = 0x8000 if symbol == 0 else 0x8000 - cdf[symbol - 1]
        fh = 0x8000 - cdf[symbol]
        self._store(fl, fh, n - symbol)
        if self.allow_update:
            update_cdf(cdf, symbol, n)

    def _store(self, fl: int, fh: int, nms: int) -> None:
        r = self.rng
        u = (((r >> 8) * (fl >> EC_PROB_SHIFT)) >> (7 - EC_PROB_SHIFT)) + EC_MIN_PROB * nms
        if fl >= 0x8000:
            u = r
        v = (((r >> 8) * (fh >> EC_PROB_SHIFT)) >> (7 - EC_PROB_SHIFT)) + EC_MIN_PROB * (nms - 1)
        # Go computes newRng as uint16: emulate the modulo-65536 wraparound.
        new_rng = (u - v) & 0xFFFF
        low = ((r - u) + self.low) & 0xFFFFFFFF
        c = self.cnt
        d = 16 - new_rng.bit_length()
        s = c + d
        if s >= 0:
            c += 16
            m = (1 << c) - 1
            if s >= 8:
                self.precarry.append((low >> c) & 0xFFFF)
                low &= m
                c -= 8
                m >>= 8
            self.precarry.append((low >> c) & 0xFFFF)
            s = c + d - 24
            low &= m
        self.low = (low << d) & 0xFFFFFFFF
        self.rng = (new_rng << d) & 0xFFFF
        self.cnt = s

    def write_bool(self, bit: int) -> None:
        save = self.allow_update
        self.allow_update = False
        self.encode_symbol(EQUI_CDF, bit)
        self.allow_update = save

    def finish(self) -> bytes:
        low = self.low
        c = self.cnt
        s = 10 + c
        m = 0x3FFF
        ev = (((low + m) & ~m) | (m + 1)) & 0xFFFFFFFF
        if s > 0:
            n = (1 << (c + 16)) - 1
            while True:
                self.precarry.append((ev >> (c + 16)) & 0xFFFF)
                ev &= n
                s -= 8
                c -= 8
                n >>= 8
                if s <= 0:
                    break
        out = bytearray(len(self.precarry))
        carry = 0
        for i in range(len(self.precarry) - 1, -1, -1):
            carry += self.precarry[i]
            out[i] = carry & 0xFF
            carry >>= 8
        return bytes(out)


def update_cdf(cdf: list[int], symbol: int, n: int) -> None:
    rate = 3
    if cdf[n] > 15:
        rate += 1
    if cdf[n] > 31:
        rate += 1
    logn = max(0, n.bit_length() - 1)
    rate += logn if logn < 2 else 2
    target = 0
    for i in range(n - 1):
        if i == symbol:
            target = 1 << 15
        if target < cdf[i]:
            cdf[i] -= (cdf[i] - target) >> rate
        else:
            cdf[i] += (target - cdf[i]) >> rate
    if cdf[n] < 32:
        cdf[n] += 1


EQUI_CDF = [1 << 14, 1 << 15, 0]


class BitWriter:
    def __init__(self) -> None:
        self.bits: list[int] = []

    def f(self, value: int, n: int) -> None:
        for i in range(n - 1, -1, -1):
            self.bits.append((value >> i) & 1)

    def trailing(self) -> None:
        self.bits.append(1)
        while len(self.bits) % 8:
            self.bits.append(0)

    def to_bytes(self) -> bytes:
        out = bytearray()
        for i in range(0, len(self.bits), 8):
            byte = 0
            for bit in self.bits[i : i + 8]:
                byte = (byte << 1) | bit
            out.append(byte)
        return bytes(out)


def leb128(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def obu(obu_type: int, payload: bytes) -> bytes:
    return bytes([obu_type << 3 | 0x02]) + leb128(len(payload)) + payload


def sequence_header(width: int, height: int, profile: int = 0, bit_depth: int = 8) -> bytes:
    w = width - 1
    h = height - 1
    width_bits = max(1, w.bit_length())
    height_bits = max(1, h.bit_length())
    bw = BitWriter()
    if profile not in (0, 2):
        raise ValueError("crafted fixtures support profile 0 or 2")
    if bit_depth not in (8, 10, 12):
        raise ValueError("crafted fixtures support 8/10/12-bit")
    if profile == 0 and bit_depth != 8:
        raise ValueError("profile 0 is 8-bit only")
    bw.f(profile, 3)  # seq_profile
    bw.f(1, 1)  # still_picture
    bw.f(1, 1)  # reduced_still_picture_header
    # The reduced path implies timing info, operating points and seq_tier.
    bw.f(0, 5)  # seq_level_idx[0]
    bw.f(width_bits - 1, 4)  # frame_width_bits_minus_1
    bw.f(height_bits - 1, 4)  # frame_height_bits_minus_1
    bw.f(w, width_bits)  # max_frame_width_minus_1
    bw.f(h, height_bits)  # max_frame_height_minus_1
    bw.f(0, 1)  # use_128x128_superblock
    bw.f(0, 1)  # enable_filter_intra
    bw.f(0, 1)  # enable_intra_edge_filter
    bw.f(0, 1)  # enable_superres
    bw.f(0, 1)  # enable_cdef
    bw.f(0, 1)  # enable_restoration
    high = 1 if bit_depth >= 10 else 0
    bw.f(high, 1)  # high_bitdepth
    if profile == 2 and high:
        bw.f(1 if bit_depth == 12 else 0, 1)  # twelve_bit
    bw.f(0, 1)  # mono_chrome
    bw.f(0, 1)  # color_description_present_flag
    bw.f(0, 1)  # color_range
    if profile == 2 and bit_depth == 12:
        bw.f(1, 1)  # subsampling_x
        bw.f(1, 1)  # subsampling_y
        bw.f(0, 2)  # chroma_sample_position
    elif profile == 2 and bit_depth == 10:
        bw.f(1, 1)  # subsampling_x
        bw.f(0, 1)  # subsampling_y
    elif profile == 0:
        bw.f(0, 2)  # chroma_sample_position (4:2:0)
    bw.f(0, 1)  # separate_uv_delta_q
    bw.f(0, 1)  # film_grain_params_present
    bw.trailing()
    return bw.to_bytes()


def frame_header(base_q_idx: int, tx_mode_select: int, reduced_tx_set: int) -> bytes:
    bw = BitWriter()
    bw.f(0, 1)  # disable_cdf_update
    bw.f(0, 1)  # allow_screen_content_tools
    bw.f(0, 1)  # render_and_frame_size_different
    bw.f(1, 1)  # uniform_tile_spacing_flag
    bw.f(base_q_idx, 8)  # base_q_idx
    bw.f(0, 1)  # delta_q_y_dc delta_coded
    bw.f(0, 1)  # delta_q_u_dc delta_coded
    bw.f(0, 1)  # delta_q_u_ac delta_coded
    bw.f(0, 1)  # using_qmatrix
    bw.f(0, 1)  # segmentation_enabled
    bw.f(0, 1)  # delta_q_present (base_q_idx > 0)
    bw.f(0, 6)  # loop_filter_level[0]
    bw.f(0, 6)  # loop_filter_level[1]
    bw.f(0, 3)  # loop_filter_sharpness
    bw.f(0, 1)  # loop_filter_delta_enabled
    bw.f(tx_mode_select, 1)  # tx_mode_select
    bw.f(reduced_tx_set, 1)  # reduced_tx_set
    # byte_alignment() before the tile group: zero padding, the trailing one
    # belongs after the tile data at the end of the OBU payload.
    while len(bw.bits) % 8:
        bw.bits.append(0)
    return bw.to_bytes()


def build_obu(
    width: int,
    height: int,
    base_q_idx: int,
    tile: bytes,
    tx_mode_select: int = 1,
    reduced_tx_set: int = 0,
    profile: int = 0,
    bit_depth: int = 8,
) -> bytes:
    stream = bytearray()
    stream += obu(2, b"")  # temporal delimiter
    stream += obu(1, sequence_header(width, height, profile, bit_depth))
    frame = frame_header(base_q_idx, tx_mode_select, reduced_tx_set) + tile
    stream += obu(6, frame)  # OBU_FRAME
    return bytes(stream)


# ---------------------------------------------------------------------------
# CDF tables extracted from the go-av1 reference decoder (spec defaults).
# ---------------------------------------------------------------------------

import re

_CDF_ROOT = Path(__file__).resolve().parent.parent / "_refs" / "go-av1" / "cdf"


def _parse_go_table(name: str, path: Path | None = None):
    if path is None:
        for candidate in sorted(_CDF_ROOT.glob("*.go")):
            if f"var {name} =" in candidate.read_text():
                path = candidate
                break
        if path is None:
            raise RuntimeError(f"CDF table {name} not found")
    src = path.read_text()
    start = src.index(f"var {name} = ")
    j = src.index("{", start)
    depth = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                text = src[j : k + 1]
                break
    tokens = re.findall(r"\d+|[{}]", text)

    def helper(idx):
        assert tokens[idx] == "{"
        out = []
        idx += 1
        while True:
            tok = tokens[idx]
            if tok == "{":
                sub, idx = helper(idx)
                out.append(sub)
            elif tok == "}":
                return out, idx + 1
            else:
                out.append(int(tok))
                idx += 1

    tree, _ = helper(0)
    return tree


def _flatten_cdf(row: list[int]) -> list[int]:
    """go-av1 rows end at 32768; the MSAC symbol reader also needs the
    trailing 0 count slot used by the MoonBit decoder."""
    out = list(row)
    if out[-1] != 0:
        out.append(0)
    return out


def _deep_copy(value):
    if isinstance(value, list):
        return [_deep_copy(x) for x in value]
    return value


class Tables:
    """Spec-default CDFs, loaded from the go-av1 generated tables.

    Each instance owns private copies: the encoder adapts CDFs in place, so
    shared tables would leak adaptation between crafted streams.
    """

    def __init__(self) -> None:
        self.partition_w64 = _deep_copy(_parse_go_table("DefaultPartitionW64Cdf"))
        self.partition_w32 = _deep_copy(_parse_go_table("DefaultPartitionW32Cdf"))
        self.skip = _deep_copy(_parse_go_table("DefaultSkipCdf"))
        self.y_mode = _deep_copy(_parse_go_table("DefaultIntraFrameYModeCdf"))
        self.uv_mode = _deep_copy(_parse_go_table("DefaultUvModeCflNotAllowedCdf"))
        self.uv_mode_cfl = _deep_copy(_parse_go_table("DefaultUvModeCflAllowedCdf"))
        self.txb_skip = _deep_copy(_parse_go_table("DefaultTxbSkipCdf"))
        self.coeff_base = _deep_copy(_parse_go_table("DefaultCoeffBaseCdf"))
        self.coeff_base_eob = _deep_copy(_parse_go_table("DefaultCoeffBaseEobCdf"))
        self.coeff_br = _deep_copy(_parse_go_table("DefaultCoeffBrCdf"))
        self.dc_sign = _deep_copy(_parse_go_table("DefaultDcSignCdf"))
        self.eob_extra = _deep_copy(_parse_go_table("DefaultEobExtraCdf"))
        self.eob_pt_16 = _deep_copy(_parse_go_table("DefaultEobPt16Cdf"))
        self.eob_pt_64 = _deep_copy(_parse_go_table("DefaultEobPt64Cdf"))
        self.eob_pt_256 = _deep_copy(_parse_go_table("DefaultEobPt256Cdf"))
        self.eob_pt_1024 = _deep_copy(_parse_go_table("DefaultEobPt1024Cdf"))
        self.tx64 = _deep_copy(_parse_go_table("DefaultTx64x64Cdf"))
        self.tx32 = _deep_copy(_parse_go_table("DefaultTx32x32Cdf"))
        self.tx16 = _deep_copy(_parse_go_table("DefaultTx16x16Cdf"))
        self.intra_tx_set1 = _deep_copy(_parse_go_table("DefaultIntraTxTypeSet1Cdf"))
        self.intra_tx_set2 = _deep_copy(_parse_go_table("DefaultIntraTxTypeSet2Cdf"))

    @staticmethod
    def qctx(base_q_idx: int) -> int:
        if base_q_idx <= 20:
            return 0
        if base_q_idx <= 60:
            return 1
        if base_q_idx <= 120:
            return 2
        return 3


# ---------------------------------------------------------------------------
# Tile symbol crafting (mirrors the MoonBit decoder's entropy walk).
# ---------------------------------------------------------------------------

def build_scan(side: int, scan_class: int) -> list[int]:
    if scan_class == 1:  # vertical: column-major
        return [(k % side) * side + k // side for k in range(side * side)]
    if scan_class == 2:  # horizontal: row-major
        return list(range(side * side))
    # default diagonal (AV1 default scan for squares below 32x32)
    if side == 4:
        return [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15]
    scan = []
    for total in range(side * 2 - 1):
        lo = max(0, total - (side - 1))
        hi = min(total, side - 1)
        rng = range(hi, lo - 1, -1) if total % 2 == 0 else range(lo, hi + 1)
        for c in rng:
            scan.append((total - c) * side + c)
    return scan


def tx_size_ctx(side: int) -> int:
    return min(4, {4: 0, 8: 1, 16: 2, 32: 3}.get(side, 4))


def coeff_base_ctx(quant, pos, c, is_eob, side, scan_class):
    area = side * side
    if is_eob:
        if c == 0:
            return 0
        if c <= area // 8:
            return 1
        if c <= area // 4:
            return 2
        return 3
    row, col = divmod(pos, side)
    mag = 0
    for dr, dc in ((0, 1), (1, 0), (1, 1), (0, 2), (2, 0)):
        rr, cc = row + dr, col + dc
        if rr < side and cc < side:
            mag += min(abs(quant[rr * side + cc]), 3)
    ctx = min((mag + 1) >> 1, 4)
    if scan_class != 0:
        idx = row if scan_class == 1 else col
        return ctx + 26 + 5 * min(idx, 2)
    if row == 0 and col == 0:
        return 0
    offsets = [
        [[0, 1, 6, 6, 0], [1, 6, 6, 21, 0], [6, 6, 21, 21, 0], [6, 21, 21, 21, 0], [0, 0, 0, 0, 0]],
        [[0, 1, 6, 6, 21], [1, 6, 6, 21, 21], [6, 6, 21, 21, 21], [6, 21, 21, 21, 21], [21, 21, 21, 21, 21]],
    ]
    table = offsets[0] if side == 4 else offsets[1]
    return ctx + table[min(row, 4)][min(col, 4)]


def txb_skip_ctx_luma(top: int, left: int, whole: bool) -> int:
    if whole:
        return 0
    if top == 0 and left == 0:
        return 1
    if top == 0 or left == 0:
        return 3 if max(top, left) > 3 else 2
    if max(top, left) <= 3:
        return 4
    if min(top, left) <= 3:
        return 5
    return 6


class LeafPlan:
    """Residual plan for one luma leaf or chroma plane block."""

    def __init__(self, zero=True, tx_symbol=None, levels=None, scan_class=0):
        self.zero = zero
        self.tx_symbol = tx_symbol  # intra_tx_type symbol index (None = no symbol)
        self.levels = levels or {}  # domain position -> unsigned level (1..3)
        self.scan_class = scan_class


def encode_leaf_coeffs(enc, T, base_q_idx, side, plane, levels, scan_class, dc_sign_ctx=0):
    qctx = T.qctx(base_q_idx)
    domain = 32 if side >= 32 else side
    tx_sz_ctx = tx_size_ctx(side)
    scan = build_scan(domain, scan_class)
    covered = [p for p in scan if p in levels and levels[p] > 0]
    assert covered, "leaf needs at least one coefficient"
    eob = scan.index(covered[-1]) + 1
    for p in scan[:eob]:
        assert p in levels, f"level map must cover scan prefix, missing {p}"
    # eob_pt symbol
    pt_ctx = 0 if scan_class == 0 else 1
    eob_pt = {1: 1, 2: 2, 3: 3, 5: 3}[eob]
    if domain == 4:
        enc.encode_symbol(T.eob_pt_16[qctx][plane][pt_ctx], eob_pt - 1)
    elif domain == 8:
        enc.encode_symbol(T.eob_pt_64[qctx][plane][pt_ctx], eob_pt - 1)
    elif domain == 16:
        enc.encode_symbol(T.eob_pt_256[qctx][plane][pt_ctx], eob_pt - 1)
    else:
        enc.encode_symbol(T.eob_pt_1024[qctx][plane], eob_pt - 1)
    if eob_pt >= 3:
        extra = {3: 0, 5: 1}[eob]
        enc.encode_symbol(T.eob_extra[qctx][tx_sz_ctx][plane][eob_pt - 3], extra)
    # levels, descending scan order
    quant = [0] * (domain * domain)
    for p, lvl in levels.items():
        quant[p] = lvl
    for c in range(eob - 1, -1, -1):
        pos = scan[c]
        lvl = quant[pos]
        ctx = coeff_base_ctx(quant, pos, c, c == eob - 1, domain, scan_class)
        if c == eob - 1:
            enc.encode_symbol(T.coeff_base_eob[qctx][tx_sz_ctx][plane][ctx], lvl - 1)
        else:
            enc.encode_symbol(T.coeff_base[qctx][tx_sz_ctx][plane][ctx], min(lvl, 3))
        assert lvl <= 3, "crafted fixtures keep levels in the base range"
    # signs, ascending scan order
    for c in range(eob):
        pos = scan[c]
        if quant[pos] != 0:
            if c == 0:
                enc.encode_symbol(T.dc_sign[qctx][plane][dc_sign_ctx], 0)  # positive
            else:
                enc.write_bool(0)
    cul = sum(levels.values())
    dc_cat = 2 if levels.get(0, 0) > 0 else 0
    return cul, dc_cat


def craft_tile(T, base_q_idx, width, tx_depth, leaf_plans, chroma_plans):
    """leaf_plans/chroma_plans follow raster/plane order."""
    enc = MsacEncoder()
    enc.allow_update = True
    qctx = T.qctx(base_q_idx)
    enc.encode_symbol(T.partition_w64[0] if width == 64 else T.partition_w32[0], 0)
    enc.encode_symbol(T.skip[0], 0)
    enc.encode_symbol(T.y_mode[0][0], 0)  # DC_PRED
    # CFL is available for blocks up to 32x32, which selects a different
    # uv_mode CDF table (AV1 spec uv_mode()).
    uv_cdf = T.uv_mode[0] if width > 32 else T.uv_mode_cfl[0]
    enc.encode_symbol(uv_cdf, 0)  # DC_PRED (row indexed by luma mode)
    tx_depth_cdf = T.tx64[0] if width == 64 else T.tx32[0]
    enc.encode_symbol(tx_depth_cdf, tx_depth)
    leaves = []
    side = width >> tx_depth
    count = 1 << (2 * tx_depth)
    assert len(leaf_plans) == count
    units = width // 4
    above_level = [0] * units
    left_level = [0] * units
    above_dc = [0] * units
    left_dc = [0] * units
    for index, plan in enumerate(leaf_plans):
        # The tx tree recursion visits each quadrant's children before the
        # next quadrant, so the leaf position decodes two bits per level.
        px = py = 0
        region = width
        for level in range(tx_depth):
            region >>= 1
            sub = (index >> (2 * (tx_depth - 1 - level))) & 3
            px += (sub % 2) * region
            py += (sub // 2) * region
        x4, y4 = px // 4, py // 4
        w4 = side // 4
        top = max(above_level[x4 : x4 + w4])
        left = max(left_level[y4 : y4 + w4])
        ctx = txb_skip_ctx_luma(top, left, side == width)
        zero = enc.encode_symbol(T.txb_skip[qctx][tx_size_ctx(side)][ctx], 0 if not plan.zero else 1)
        if not plan.zero:
            if plan.tx_symbol is not None:
                if side == 16:
                    enc.encode_symbol(T.intra_tx_set2[2][0], plan.tx_symbol)
                elif side == 8:
                    enc.encode_symbol(T.intra_tx_set1[1][0], plan.tx_symbol)
                elif side == 4:
                    enc.encode_symbol(T.intra_tx_set1[0][0], plan.tx_symbol)
                # 32x32/64x64 leaves are DCT-only for intra: no symbol
            plane = 0
            # dc_sign context mirrors the decoder's neighbour dc categories.
            score = 0
            for i in range(w4):
                for val in (above_dc[x4 + i], left_dc[y4 + i]):
                    if val == 1:
                        score -= 1
                    elif val == 2:
                        score += 1
            dsc = 1 if score < 0 else (2 if score > 0 else 0)
            cul, dc_cat = encode_leaf_coeffs(
                enc, T, base_q_idx, side, plane, plan.levels, plan.scan_class, dsc
            )
            for i in range(w4):
                above_level[x4 + i] = cul
                above_dc[x4 + i] = dc_cat
                left_level[y4 + i] = cul
                left_dc[y4 + i] = dc_cat
    # chroma: one transform per plane at the plane maximum
    chroma_side = width // 2
    for plane, plan in zip((1, 2), chroma_plans):
        ctx = 7  # whole plane, no neighbours
        enc.encode_symbol(T.txb_skip[qctx][tx_size_ctx(chroma_side)][ctx], 0 if not plan.zero else 1)
        if not plan.zero:
            encode_leaf_coeffs(
                enc, T, base_q_idx, chroma_side, plane, plan.levels, plan.scan_class
            )
    return enc.finish()


def fixture_plans_flat(width, tx_depth):
    """Fixture A/B-style plans: leaf 0 carries a single DC coefficient."""
    count = 1 << (2 * tx_depth)
    plans = []
    for i in range(count):
        if i == 0:
            plans.append(LeafPlan(zero=False, tx_symbol=1 if tx_depth > 1 else None, levels={0: 1}))
        else:
            plans.append(LeafPlan(zero=True))
    return plans


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("tests/fixtures/av1"))
    ap.add_argument("--check", action="store_true", help="print hex only")
    args = ap.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    # One fresh Tables per stream: crafting adapts CDFs in place, so reuse
    # would leak adaptation between streams.
    def fresh():
        return Tables()

    streams = {}

    # A: 64x64, tx_depth 1 -> four 32x32 leaves (DCT-only), one DC residual.
    streams["txsel_depth1_64"] = build_obu(
        64, 64, 120, craft_tile(fresh(), 120, 64, 1, fixture_plans_flat(64, 1), [LeafPlan(), LeafPlan()]),
    )

    # B: 64x64, tx_depth 2 -> sixteen 16x16 leaves; the first three leaves
    # carry set2 transform types (DCT_DCT, ADST_ADST, ADST_DCT).
    plans_b = [LeafPlan(zero=True) for _ in range(16)]
    plans_b[0] = LeafPlan(zero=False, tx_symbol=1, levels={0: 1})
    plans_b[1] = LeafPlan(zero=False, tx_symbol=2, levels={0: 2})
    plans_b[2] = LeafPlan(zero=False, tx_symbol=3, levels={0: 1})
    streams["txsel_depth2_16x16_txtype"] = build_obu(
        64, 64, 120, craft_tile(fresh(), 120, 64, 2, plans_b, [LeafPlan(), LeafPlan()]),
    )

    # C: 32x32, tx_depth 2 -> four 8x8 leaves from TX_SET_INTRA_1 with the
    # V_DCT and H_DCT 1D scan classes.
    plans_c = [LeafPlan(zero=True) for _ in range(16)]
    plans_c[0] = LeafPlan(zero=False, tx_symbol=1, levels={0: 1})
    plans_c[1] = LeafPlan(zero=False, tx_symbol=2, levels={0: 1, 8: 1}, scan_class=1)
    plans_c[2] = LeafPlan(zero=False, tx_symbol=3, levels={0: 1, 1: 1}, scan_class=2)
    streams["txsel_32_depth2_1dscan"] = build_obu(
        32, 32, 120, craft_tile(fresh(), 120, 32, 2, plans_c, [LeafPlan(), LeafPlan()]),
    )

    # D: profile 2 12-bit tx_mode=SELECT stream with a non-neutral luma DC.
    # This exercises the highbd tx-tree, dequantisation and RGBA assembly path.
    streams["txsel_highbd12_dc"] = build_obu(
        64,
        64,
        120,
        craft_tile(
            fresh(),
            120,
            64,
            1,
            [LeafPlan(zero=False, levels={0: 1})]
            + [LeafPlan(zero=True) for _ in range(3)],
            [LeafPlan(), LeafPlan()],
        ),
        profile=2,
        bit_depth=12,
    )


    for name, data in streams.items():
        if args.check:
            print(name, data.hex())
        else:
            (out / f"{name}.obu").write_bytes(data)
            print(f"wrote {out / (name + '.obu')} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


# ---------------------------------------------------------------------------
# Reference MSAC decoder (ported from go-av1 msac.go) for round-trip checks.
# ---------------------------------------------------------------------------

class MsacDecoder:
    """Reference MSAC decoder ported from go-av1 msac.go (round-trip checks)."""

    def __init__(self, data: bytes, allow_update: bool = True) -> None:
        self.data = data
        self.bit_pos = 0
        self.allow_update = allow_update
        num_bits = min(len(data) * 8, 15)
        buf = self._read_bits(num_bits)
        padded_buf = buf << (15 - num_bits)
        self.symbol_value = ((1 << 15) - 1) ^ padded_buf
        self.symbol_range = 1 << 15
        self.symbol_range = 1 << 15
        self.symbol_max_bits = len(data) * 8 - 15

    def _read_bits(self, n: int) -> int:
        v = 0
        for _ in range(n):
            byte_pos = self.bit_pos >> 3
            bit = 0
            if byte_pos < len(self.data):
                bit = (self.data[byte_pos] >> (7 - (self.bit_pos & 7))) & 1
            v = (v << 1) | bit
            self.bit_pos += 1
        return v

    def symbol(self, cdf) -> int:
        n = len(cdf) - 1
        cur = self.symbol_range
        prev = 0
        symbol = -1
        while True:
            symbol += 1
            prev = cur
            f = (1 << 15) - cdf[symbol]
            cur = ((self.symbol_range >> 8) * (f >> EC_PROB_SHIFT)) >> (7 - EC_PROB_SHIFT)
            cur += EC_MIN_PROB * (n - symbol - 1)
            if self.symbol_value >= cur:
                break
        self.symbol_range = prev - cur
        self.symbol_value -= cur
        self._renorm()
        if self.allow_update:
            update_cdf(cdf, symbol, n)
        return symbol

    def bool(self) -> int:
        save = self.allow_update
        self.allow_update = False
        v = self.symbol(EQUI_CDF)
        self.allow_update = save
        return v

    def _renorm(self) -> None:
        b = 15 - (self.symbol_range.bit_length() - 1)
        self.symbol_range <<= b
        num_bits = b
        maxb = self.symbol_max_bits
        if num_bits > maxb:
            num_bits = max(0, maxb)
        new_data = self._read_bits(num_bits)
        padded = new_data << (b - num_bits)
        self.symbol_value = (padded ^ (((self.symbol_value + 1) << b) - 1)) & 0xFFFFFFFF
        self.symbol_max_bits -= b
