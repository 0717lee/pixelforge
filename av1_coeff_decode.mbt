///|
/// Bounded coefficient decoder for a single 64x64 DCT_DCT transform block.
///
/// AV1 addresses coefficients in the adjusted 32x32 domain for 64x64
/// transforms.  This helper keeps the entropy walk stateful (the caller may
/// pass an existing MSAC decoder) and deliberately caps every variable length
/// loop so malformed tile payloads return `None` instead of running forever.
let av1_coeff_ctx_offsets_32 : Array[Array[Int]] = [
  [0, 1, 6, 6, 0],
  [1, 6, 6, 21, 0],
  [6, 6, 21, 21, 0],
  [6, 21, 21, 21, 0],
  [0, 0, 0, 0, 0],
]

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
/// Decode a 64x64 DCT_DCT coefficient block using an existing tile decoder.
/// `plane` is 0 for luma and 1 for either chroma plane.  `base_q_idx` must be
/// the already selected (and clamped) 8-bit quantizer index.  The returned
/// array is adjusted 32x32, row-major, dequantized with the 8-bit quantizer.
fn av1_decode_coeffs_64x64_with_decoder(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  plane : Int,
) -> Array[Int]? {
  if base_q_idx < 0 || base_q_idx > 255 || (plane != 0 && plane != 1) {
    return None
  }
  let qctx = av1_dc_q_context(base_q_idx)
  let eob_cdf = av1_coeff_eob1024_default(qctx, plane)
  let eob_pt = decoder.symbol(eob_cdf) + 1
  if eob_pt < 1 || eob_pt > 11 {
    return None
  }
  let mut eob = eob_pt
  if eob_pt >= 2 {
    eob = (1 << (eob_pt - 2)) + 1
  }
  if eob_pt >= 3 {
    let shift = eob_pt - 3
    let extra_cdf = av1_coeff_eob_extra_default(qctx, 4, plane, shift)
    if decoder.symbol(extra_cdf) == 1 {
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
      decoder.symbol(av1_coeff_base_eob_default(qctx, 4, plane, ctx)) + 1
    } else {
      decoder.symbol(av1_coeff_base_default(qctx, 4, plane, ctx))
    }
    let mut value = level
    if value > 2 {
      let mut done = false
      for _ in 0..<4 {
        if !done {
          let br = decoder.symbol(
            av1_coeff_br_default(
              qctx,
              3,
              plane,
              av1_coeff_br_ctx_32(quant, pos),
            ),
          )
          value = value + br
          if br < 3 {
            done = true
          }
        }
      }
    }
    if value > 65535 {
      return None
    }
    quant[pos] = value
  }

  let mut cul = 0
  for c in 0..<eob {
    let pos = scan[c]
    let mut sign = 0
    if quant[pos] != 0 {
      sign = if c == 0 {
        decoder.symbol(av1_coeff_dc_sign_default(qctx, plane, 0))
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
        let mut code = 1
        for _ in 0..<(length - 1) {
          code = (code << 1) | decoder.bool()
        }
        quant[pos] = code + 14
      }
      if sign == 1 {
        quant[pos] = -quant[pos]
      }
    }
    cul = cul + av1_coeff_abs(quant[pos])
  }
  let q = av1_dc_quant_8(base_q_idx)
  let out : Array[Int] = Array::make(1024, 0)
  for i in 0..<1024 {
    let v = quant[i] * q
    out[i] = (av1_coeff_abs(v) & 0xFFFFFF) / 4 * (if v < 0 { -1 } else { 1 })
  }
  Some(out)
}

///|
/// Standalone probe that creates a fresh decoder for a complete tile payload.
pub fn av1_decode_coeffs_64x64(
  tile_payload : Array[Byte],
  base_q_idx : Int,
  plane : Int,
) -> Array[Int]? {
  if tile_payload.length() == 0 {
    return None
  }
  av1_decode_coeffs_64x64_with_decoder(
    av1_msac_new(tile_payload, false),
    base_q_idx,
    plane,
  )
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
