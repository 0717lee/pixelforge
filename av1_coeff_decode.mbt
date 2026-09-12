///|
/// Bounded coefficient decoder for square AV1 transform blocks.
///
/// AV1 addresses 32x32 and 64x64 coefficients in the adjusted 32x32 domain.
/// This module keeps the entropy walk stateful (the caller may pass an
/// existing MSAC decoder) and deliberately caps every variable length loop so
/// malformed tile payloads return `None` instead of running forever.

///|
/// One decoded transform leaf: dequantised coefficients plus the entropy
/// context updates required by the AV1 level/dc-sign neighbour model.
priv struct Av1LeafCoeffs {
  coeffs : Array[Int]
  cul_level : Int
  dc_category : Int
}

///|
/// Mutable leaves for one plane/transform context. U and V retain the same
/// instance for the tile; a fresh leaf for each symbol would lose adaptation.
/// The CDF rows are stored per transform-size context so one instance serves
/// leaves of every size (AV1 default_coeff_* tables are indexed by
/// txSzCtx 0..4).
priv struct Av1CoeffContext {
  mut tx_ctx : Int
  plane : Int
  eob : Array[Int]
  extra : Array[Array[Array[Int]]]
  base_eob : Array[Array[Array[Int]]]
  base : Array[Array[Array[Int]]]
  br : Array[Array[Array[Int]]]
  sign : Array[Array[Int]]
}

///|
fn av1_coeff_context(
  base_q_idx : Int,
  tx_ctx : Int,
  plane : Int,
) -> Av1CoeffContext {
  let qctx = av1_dc_q_context(base_q_idx)
  let extra : Array[Array[Array[Int]]] = []
  let base_eob : Array[Array[Array[Int]]] = []
  let base : Array[Array[Array[Int]]] = []
  let br : Array[Array[Array[Int]]] = []
  let sign : Array[Array[Int]] = []
  for tx in 0..<5 {
    let extra_rows : Array[Array[Int]] = []
    let base_eob_rows : Array[Array[Int]] = []
    let base_rows : Array[Array[Int]] = []
    for i in 0..<9 {
      extra_rows.push(av1_coeff_eob_extra_default(qctx, tx, plane, i))
    }
    for i in 0..<4 {
      base_eob_rows.push(av1_coeff_base_eob_default(qctx, tx, plane, i))
    }
    for i in 0..<42 {
      base_rows.push(av1_coeff_base_default(qctx, tx, plane, i))
    }
    extra.push(extra_rows)
    base_eob.push(base_eob_rows)
    base.push(base_rows)
  }
  for tx in 0..<4 {
    let br_rows : Array[Array[Int]] = []
    for i in 0..<21 {
      br_rows.push(av1_coeff_br_default(qctx, tx, plane, i))
    }
    br.push(br_rows)
  }
  for i in 0..<3 {
    sign.push(av1_coeff_dc_sign_default(qctx, plane, i))
  }
  {
    tx_ctx,
    plane,
    eob: av1_coeff_eob1024_default(qctx, plane),
    extra,
    base_eob,
    base,
    br,
    sign,
  }
}

///|
/// AV1 default diagonal scan for the adjusted 32x32 coefficient domain.
fn av1_coeff_scan_32() -> Array[Int] {
  let out : Array[Int] = []
  for d in 0..<63 {
    let lo = if d < 32 { 0 } else { d - 31 }
    let hi = if d < 32 { d } else { 31 }
    if (d & 1) == 0 {
      let mut r = hi
      while r >= lo {
        out.push((r << 5) + (d - r))
        r = r - 1
      }
    } else {
      let mut r = lo
      while r <= hi {
        out.push((r << 5) + (d - r))
        r = r + 1
      }
    }
  }
  out
}

///|
/// Transform scan classes: the default diagonal, or the 1D vertical and
/// horizontal scans selected by V_/H_ transform types (AV1 spec §5.11.34).
const AV1_SCAN_DEFAULT : Int = 0
const AV1_SCAN_VERT : Int = 1
const AV1_SCAN_HORZ : Int = 2

///|
/// Default scan for square transforms below 32x32; larger squares share the
/// adjusted 32x32 default regardless of class (64x64 is DCT-only for intra).
fn av1_coeff_scan_square(side : Int, scan_class : Int) -> Array[Int] {
  if scan_class == AV1_SCAN_VERT {
    let out : Array[Int] = []
    for k in 0..<(side * side) {
      out.push((k % side) * side + k / side)
    }
    return out
  }
  if scan_class == AV1_SCAN_HORZ {
    let out : Array[Int] = []
    for k in 0..<(side * side) {
      out.push(k)
    }
    return out
  }
  if side == 4 {
    return av1_scan_default_4.copy()
  }
  if side == 8 {
    return av1_scan_default_8.copy()
  }
  if side == 16 {
    return av1_scan_default_16.copy()
  }
  av1_coeff_scan_32()
}

///|
fn av1_coeff_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
/// Coeff-base context from §8.3, get_coeff_base_ctx, for the adjusted 32x32
/// domain. `side` is 32 for both 32x32 and 64x64 transforms; `size_row`
/// selects the position-offset table row (0=4x4 .. 4=64x64).
fn av1_coeff_base_ctx_square(
  quant : Array[Int],
  pos : Int,
  c : Int,
  is_eob : Bool,
  side : Int,
  size_row : Int,
  scan_class : Int,
) -> Int {
  let area = side * side
  if is_eob {
    if c == 0 {
      return 0
    }
    if c <= area / 8 {
      return 1
    }
    if c <= area / 4 {
      return 2
    }
    return 3
  }
  let log2_side = if side == 2 {
    1
  } else if side == 4 {
    2
  } else if side == 8 {
    3
  } else if side == 16 {
    4
  } else {
    5
  }
  let row = pos >> log2_side
  let col = pos - (row << log2_side)
  let refs : Array[Array[Int]] = [[0, 1], [1, 0], [1, 1], [0, 2], [2, 0]]
  let mut mag = 0
  for delta in refs {
    let rr = row + delta[0]
    let cc = col + delta[1]
    if rr < side && cc < side {
      let v = av1_coeff_abs(quant[(rr << log2_side) + cc])
      mag = mag + (if v < 3 { v } else { 3 })
    }
  }
  let ctx = if (mag + 1) >> 1 < 4 { (mag + 1) >> 1 } else { 4 }
  if scan_class != AV1_SCAN_DEFAULT {
    // 1D scans replace the 2D position offsets with a small positional ladder.
    let idx = if scan_class == AV1_SCAN_VERT { row } else { col }
    let ladder = if idx < 2 { idx } else { 2 }
    return ctx + 26 + 5 * ladder
  }
  if row == 0 && col == 0 {
    return 0
  }
  ctx +
  av1_coeff_base_ctx_offset[size_row][if row < 4 { row } else { 4 }][if col < 4 {
    col
  } else {
    4
  }]
}

///|
/// Coeff-br context from §8.3, get_coeff_br_ctx, for square transforms.
fn av1_coeff_br_ctx_square(
  quant : Array[Int],
  pos : Int,
  side : Int,
  scan_class : Int,
) -> Int {
  let log2_side = if side == 2 {
    1
  } else if side == 4 {
    2
  } else if side == 8 {
    3
  } else if side == 16 {
    4
  } else {
    5
  }
  let row = pos >> log2_side
  let col = pos - (row << log2_side)
  let refs : Array[Array[Int]] = [[0, 1], [1, 0], [1, 1]]
  let mut mag = 0
  for delta in refs {
    let rr = row + delta[0]
    let cc = col + delta[1]
    if rr < side && cc < side {
      let v = quant[(rr << log2_side) + cc]
      mag = mag + (if v < 15 { v } else { 15 })
    }
  }
  let m = if (mag + 1) >> 1 < 6 { (mag + 1) >> 1 } else { 6 }
  if pos == 0 {
    return m
  }
  if scan_class != AV1_SCAN_DEFAULT {
    let boundary = if scan_class == AV1_SCAN_VERT { row } else { col }
    if boundary == 0 {
      m + 7
    } else {
      m + 14
    }
  } else if row < 2 && col < 2 {
    m + 7
  } else {
    m + 14
  }
}

///|
/// Decode a square block whose all_zero flag has already been read. Both
/// 32x32 and 64x64 code an adjusted 32x32 region; the result is padded to the
/// full transform size expected by the inverse transform stage. Smaller
/// squares decode in their own domain with class-selected scans.
fn av1_decode_coeffs_leaf_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  side : Int,
  bit_depth? : Int = 8,
  scan_class? : Int = AV1_SCAN_DEFAULT,
  dc_sign_ctx? : Int = 0,
) -> Av1LeafCoeffs? {
  if base_q_idx < 0 || base_q_idx > 255 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    (context.tx_ctx != 0 && context.tx_ctx != 1 && context.tx_ctx != 2 &&
    context.tx_ctx != 3 && context.tx_ctx != 4) {
    return None
  }
  let large = side == 32 || side == 64
  let domain = if large { 32 } else { side }
  let area = domain * domain
  if scan_class != AV1_SCAN_DEFAULT && large && side == 64 {
    return None
  }
  // End-of-block position by transform-area class (AV1 spec §5.11.39).
  let log2_domain = if domain == 4 {
    2
  } else if domain == 8 {
    3
  } else if domain == 16 {
    4
  } else {
    5
  }
  let mut eob = 0
  if large {
    let eob_pt = decoder.symbol(context.eob) + 1
    if eob_pt < 1 || eob_pt > 11 {
      return None
    }
    eob = eob_pt
    if eob_pt >= 2 {
      eob = (1 << (eob_pt - 2)) + 1
    }
    if eob_pt >= 3 {
      let shift = eob_pt - 3
      if decoder.symbol(context.extra[context.tx_ctx][shift]) == 1 {
        eob = eob + (1 << shift)
      }
      let hi = if eob_pt - 2 > 0 { eob_pt - 2 } else { 0 }
      if hi > 1 {
        for i in 1..<hi {
          if decoder.bool() == 1 {
            eob = eob + (1 << (hi - 1 - i))
          }
        }
      }
    }
    if eob < 1 || eob > 1024 {
      return None
    }
  } else {
    let multisize = log2_domain + log2_domain - 4
    let kind = multisize
    let pt_ctx = if scan_class == AV1_SCAN_DEFAULT { 0 } else { 1 }
    let eob_pt = decoder.symbol(
        av1_coeff_eob_small_default(
          kind, av1_dc_q_context(base_q_idx), context.plane, pt_ctx,
        ),
      ) +
      1
    if eob_pt < 1 || eob_pt > 11 {
      return None
    }
    eob = eob_pt
    if eob_pt >= 2 {
      eob = (1 << (eob_pt - 2)) + 1
    }
    if eob_pt >= 3 {
      let shift = eob_pt - 3
      if decoder.symbol(context.extra[context.tx_ctx][shift]) == 1 {
        eob = eob + (1 << shift)
      }
      let hi = eob_pt - 2
      if hi > 1 {
        for i in 1..<hi {
          if decoder.bool() == 1 {
            eob = eob + (1 << (hi - 1 - i))
          }
        }
      }
    }
    if eob < 1 || eob > area {
      return None
    }
  }
  let scan = if large {
    av1_coeff_scan_32()
  } else {
    av1_coeff_scan_square(domain, scan_class)
  }
  let size_row = if domain == 4 {
    0
  } else if domain == 8 {
    1
  } else if domain == 16 {
    2
  } else if side == 64 {
    4
  } else {
    3
  }
  let quant : Array[Int] = Array::make(area, 0)
  for ci in 0..<eob {
    let c = eob - 1 - ci
    let pos = scan[c]
    let ctx = av1_coeff_base_ctx_square(
      quant, pos, c, c == eob - 1, domain, size_row, scan_class,
    )
    let mut value = if c == eob - 1 {
      let v0 = decoder.symbol(context.base_eob[context.tx_ctx][ctx]) + 1
      v0
    } else {
      let v0 = decoder.symbol(context.base[context.tx_ctx][ctx])
      v0
    }
    if value > 2 {
      let mut done = false
      for _ in 0..<4 {
        if !done {
          let br = decoder.symbol(
            context.br[if context.tx_ctx > 3 { 3 } else { context.tx_ctx }][
              av1_coeff_br_ctx_square(quant, pos, domain, scan_class)
            ],
          )
          value = value + br
          if br < 3 {
            done = true
          }
        }
      }
    }
    if decoder.symbol_max_bits < -14 {
      return None
    }
    quant[pos] = value
  }
  let mut cul_level = 0
  let mut dc_category = 0
  for c in 0..<eob {
    let pos = scan[c]
    let mut sign = 0
    if quant[pos] != 0 {
      sign = if c == 0 {
        decoder.symbol(context.sign[dc_sign_ctx])
      } else {
        decoder.bool()
      }
      if quant[pos] > 14 {
        let mut length = 0
        let mut terminated = false
        while length < 32 && !terminated {
          length = length + 1
          terminated = decoder.bool() == 1
        }
        if !terminated || length == 0 {
          return None
        }
        let mut code = 1L
        for _ in 0..<(length - 1) {
          code = (code << 1) | decoder.bool().to_int64()
        }
        quant[pos] = ((code + 14L) & 0xFFFFFL).to_int()
      }
      if sign == 1 {
        quant[pos] = -quant[pos]
      }
      if pos == 0 && quant[pos] != 0 {
        dc_category = if sign == 1 { 1 } else { 2 }
      }
    }
    cul_level = cul_level + av1_coeff_abs(quant[pos])
    if decoder.symbol_max_bits < -14 {
      return None
    }
  }
  cul_level = if cul_level > 63 { 63 } else { cul_level }
  let dc_q = av1_dc_quant(bit_depth, base_q_idx)
  let ac_q = av1_ac_quant(bit_depth, base_q_idx)
  let denom : Int64 = if context.tx_ctx == 4 { 4L } else { 2L }
  let out : Array[Int] = Array::make(side * side, 0)
  if large {
    for i in 0..<1024 {
      let q = if i == 0 { dc_q } else { ac_q }
      let v = quant[i].to_int64() * q.to_int64()
      let magnitude = ((if v < 0 { -v } else { v }) & 0xFFFFFFL) / denom
      let signed = (if v < 0 { -magnitude } else { magnitude }).to_int()
      let limit = 1 << (7 + bit_depth)
      out[(i >> 5) * side + (i & 31)] = av1_clip(-limit, limit - 1, signed)
    }
  } else {
    for i in 0..<area {
      let q = if i == 0 { dc_q } else { ac_q }
      let v = quant[i].to_int64() * q.to_int64()
      let magnitude = ((if v < 0 { -v } else { v }) & 0xFFFFFFL) / denom
      let signed = (if v < 0 { -magnitude } else { magnitude }).to_int()
      let limit = 1 << (7 + bit_depth)
      out[(i >> log2_domain) * side + (i & (domain - 1))] = av1_clip(
        -limit, limit - 1, signed,
      )
    }
  }
  Some({ coeffs: out, cul_level, dc_category })
}

///|
/// Legacy wrapper returning only the dequantised coefficients.
fn av1_decode_coeffs_square_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  bit_depth? : Int = 8,
) -> Array[Int]? {
  match
    av1_decode_coeffs_leaf_with_decoder(
      decoder,
      base_q_idx,
      context,
      if context.tx_ctx == 4 { 64 } else { 32 },
      bit_depth~,
    ) {
    Some(leaf) => Some(leaf.coeffs)
    None => None
  }
}

///|
/// Legacy wrapper for small blocks returning only the coefficients.
fn av1_decode_coeffs_small_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  side : Int,
  bit_depth? : Int = 8,
  scan_class? : Int = AV1_SCAN_DEFAULT,
) -> Array[Int]? {
  match
    av1_decode_coeffs_leaf_with_decoder(
      decoder, base_q_idx, context, side, bit_depth~, scan_class~,
    ) {
    Some(leaf) => Some(leaf.coeffs)
    None => None
  }
}
