///|
/// Bounded coefficient decoder for 32x32 and 64x64 DCT_DCT transform blocks.
///
/// AV1 addresses coefficients in the adjusted 32x32 domain for 64x64
/// transforms. This helper keeps the entropy walk stateful (the caller may
/// pass an existing MSAC decoder) and deliberately caps every variable length
/// loop so malformed tile payloads return `None` instead of running forever.
let av1_coeff_ctx_offsets_32 : Array[Array[Int]] = [
  [0, 1, 6, 6, 21],
  [1, 6, 6, 21, 21],
  [6, 6, 21, 21, 21],
  [6, 21, 21, 21, 21],
  [21, 21, 21, 21, 21],
]

///|
/// Mutable leaves for one plane/transform context. U and V retain the same
/// instance for the tile; a fresh leaf for each symbol would lose adaptation.
priv struct Av1CoeffContext {
  tx_ctx : Int
  eob : Array[Int]
  extra : Array[Array[Int]]
  base_eob : Array[Array[Int]]
  base : Array[Array[Int]]
  br : Array[Array[Int]]
  sign : Array[Int]
}

///|
fn av1_coeff_context(
  base_q_idx : Int,
  tx_ctx : Int,
  plane : Int,
) -> Av1CoeffContext {
  let qctx = av1_dc_q_context(base_q_idx)
  let extra : Array[Array[Int]] = []
  let base_eob : Array[Array[Int]] = []
  let base : Array[Array[Int]] = []
  let br : Array[Array[Int]] = []
  for i in 0..<9 {
    extra.push(av1_coeff_eob_extra_default(qctx, tx_ctx, plane, i))
  }
  for i in 0..<4 {
    base_eob.push(av1_coeff_base_eob_default(qctx, tx_ctx, plane, i))
  }
  for i in 0..<42 {
    base.push(av1_coeff_base_default(qctx, tx_ctx, plane, i))
  }
  for i in 0..<21 {
    br.push(av1_coeff_br_default(qctx, 3, plane, i))
  }
  {
    tx_ctx,
    eob: av1_coeff_eob1024_default(qctx, plane),
    extra,
    base_eob,
    base,
    br,
    sign: av1_coeff_dc_sign_default(qctx, plane, 0),
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
fn av1_coeff_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
/// Coeff-base context from §8.3, get_coeff_base_ctx, for 32x32 DCT_DCT.
fn av1_coeff_base_ctx_32(
  quant : Array[Int],
  pos : Int,
  c : Int,
  is_eob : Bool,
) -> Int {
  if is_eob {
    if c == 0 {
      return 0
    }
    if c <= 128 {
      return 1
    }
    if c <= 256 {
      return 2
    }
    return 3
  }
  let row = pos >> 5
  let col = pos & 31
  let refs : Array[Array[Int]] = [[0, 1], [1, 0], [1, 1], [0, 2], [2, 0]]
  let mut mag = 0
  for delta in refs {
    let rr = row + delta[0]
    let cc = col + delta[1]
    if rr < 32 && cc < 32 {
      let v = av1_coeff_abs(quant[(rr << 5) + cc])
      mag = mag + (if v < 3 { v } else { 3 })
    }
  }
  let ctx = if (mag + 1) >> 1 < 4 { (mag + 1) >> 1 } else { 4 }
  if row == 0 && col == 0 {
    return 0
  }
  ctx +
  av1_coeff_ctx_offsets_32[if row < 4 { row } else { 4 }][if col < 4 {
    col
  } else {
    4
  }]
}

///|
/// Coeff-br context from §8.3, get_coeff_br_ctx, for 32x32 DCT_DCT.
fn av1_coeff_br_ctx_32(quant : Array[Int], pos : Int) -> Int {
  let row = pos >> 5
  let col = pos & 31
  let refs : Array[Array[Int]] = [[0, 1], [1, 0], [1, 1]]
  let mut mag = 0
  for delta in refs {
    let rr = row + delta[0]
    let cc = col + delta[1]
    if rr < 32 && cc < 32 {
      let v = quant[(rr << 5) + cc]
      mag = mag + (if v < 15 { v } else { 15 })
    }
  }
  let m = if (mag + 1) >> 1 < 6 { (mag + 1) >> 1 } else { 6 }
  if pos == 0 {
    return m
  }
  if row < 2 && col < 2 {
    m + 7
  } else {
    m + 14
  }
}

///|
/// Decode a square DCT_DCT block whose all_zero flag has already been read.
/// Both transform sizes code an adjusted 32x32 region; the result is padded
/// to the full transform size expected by av1_inverse_dct_2d.
fn av1_decode_coeffs_square_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  bit_depth? : Int = 8,
) -> Array[Int]? {
  if base_q_idx < 0 ||
    base_q_idx > 255 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    (context.tx_ctx != 3 && context.tx_ctx != 4) {
    return None
  }
  let eob_pt = decoder.symbol(context.eob) + 1
  if eob_pt < 1 || eob_pt > 11 {
    return None
  }
  let mut eob = eob_pt
  if eob_pt >= 2 {
    eob = (1 << (eob_pt - 2)) + 1
  }
  if eob_pt >= 3 {
    let shift = eob_pt - 3
    if decoder.symbol(context.extra[shift]) == 1 {
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

  let scan = av1_coeff_scan_32()
  let quant : Array[Int] = Array::make(1024, 0)
  for ci in 0..<eob {
    let c = eob - 1 - ci
    let pos = scan[c]
    let ctx = av1_coeff_base_ctx_32(quant, pos, c, c == eob - 1)
    let level = if c == eob - 1 {
      decoder.symbol(context.base_eob[ctx]) + 1
    } else {
      decoder.symbol(context.base[ctx])
    }
    let mut value = level
    if value > 2 {
      let mut done = false
      for _ in 0..<4 {
        if !done {
          let br = decoder.symbol(context.br[av1_coeff_br_ctx_32(quant, pos)])
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

  for c in 0..<eob {
    let pos = scan[c]
    let mut sign = 0
    if quant[pos] != 0 {
      sign = if c == 0 { decoder.symbol(context.sign) } else { decoder.bool() }
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
    }
    if decoder.symbol_max_bits < -14 {
      return None
    }
  }
  let dc_q = av1_dc_quant(bit_depth, base_q_idx)
  let ac_q = av1_ac_quant(bit_depth, base_q_idx)
  let side = if context.tx_ctx == 4 { 64 } else { 32 }
  let denom = if context.tx_ctx == 4 { 4L } else { 2L }
  let out : Array[Int] = Array::make(side * side, 0)
  for i in 0..<1024 {
    let q = if i == 0 { dc_q } else { ac_q }
    let v = quant[i].to_int64() * q.to_int64()
    let magnitude = ((if v < 0 { -v } else { v }) & 0xFFFFFFL) / denom
    let signed = (if v < 0 { -magnitude } else { magnitude }).to_int()
    let limit = 1 << (7 + bit_depth)
    out[(i >> 5) * side + (i & 31)] = av1_clip(-limit, limit - 1, signed)
  }
  Some(out)
}

///|
/// Compatibility probe for callers that already consumed the luma syntax.
fn av1_decode_coeffs_64x64_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  plane : Int,
) -> Array[Int]? {
  if base_q_idx < 0 || base_q_idx > 255 || (plane != 0 && plane != 1) {
    return None
  }
  av1_decode_coeffs_square_with_decoder(
    decoder,
    base_q_idx,
    av1_coeff_context(base_q_idx, 4, plane),
  )
}

///|
/// Standalone coefficient-entropy probe. This starts at eob_pt, after the
/// caller has removed tile/block syntax and the transform all_zero flag.
pub fn av1_decode_coeffs_64x64(
  tile_payload : Array[Byte],
  base_q_idx : Int,
  plane : Int,
) -> Array[Int]? {
  if tile_payload.length() == 0 {
    return None
  }
  match
    av1_decode_coeffs_64x64_with_decoder(
      av1_msac_new(tile_payload, false),
      base_q_idx,
      plane,
    ) {
    Some(value) => {
      let out : Array[Int] = Array::make(1024, 0)
      for r in 0..<32 {
        for c in 0..<32 {
          out[r * 32 + c] = value[r * 64 + c]
        }
      }
      Some(out)
    }
    None => None
  }
}

///|
test "64x64 coefficient helper bounds malformed EOB" {
  assert_eq(av1_decode_coeffs_64x64([], 32, 0), None)
  assert_eq(av1_decode_coeffs_64x64([b'\xFF', b'\xFF', b'\xFF'], 32, 0), None)
}

///|
test "64x64 scan starts with AV1 diagonal order" {
  let scan = av1_coeff_scan_32()
  assert_eq(scan[0], 0)
  assert_eq(scan[1], 1)
  assert_eq(scan[2], 32)
  assert_eq(scan[3], 64)
  assert_eq(scan[4], 33)
  assert_eq(scan.length(), 1024)
}

///|
test "64x64 coefficient helper decodes a minimal EOB stream" {
  let coeffs = av1_decode_coeffs_64x64([b'\x00', b'\x00'], 33, 0).unwrap()
  assert_eq(coeffs.length(), 1024)
  assert_eq(coeffs[0], 8)
  assert_eq(coeffs[1], 0)
}

///|
