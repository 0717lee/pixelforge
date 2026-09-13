/// Exact AV1 inverse DCT integer transform (AOMedia AV1 §7.13.2.1–3).
///
/// The implementation follows the normative B/H butterfly schedule.  The
/// constants are Cos128_Lookup from the AV1 specification (Q12); all products
/// are evaluated in MoonBit Int and rounded with the specified Round2 rule.
/// This is deliberately a butterfly implementation, rather than a floating
/// point/cosine matrix approximation.  Reference schedule: AOMediaCodec/av1-
/// spec §7.13.2.3 and libaom `av1/common/av1_inv_txfm1d.c` at commit
/// 8e7b6a567df174d795479b92b4ac766d271add73 (AOMedia googlesource).

///| 
pub(all) enum Av1TxType {
  Av1TxDctDct
  Av1TxAdstDct
  Av1TxDctAdst
  Av1TxAdstAdst
  Av1TxFlipadstDct
  Av1TxDctFlipadst
  Av1TxFlipadstFlipadst
  Av1TxAdstFlipadst
  Av1TxFlipadstAdst
  Av1TxIdentityIdentity
  Av1TxIdentityDct
  Av1TxDctIdentity
  Av1TxVerticalDct
  Av1TxHorizontalDct
  Av1TxVerticalAdst
  Av1TxHorizontalAdst
  Av1TxVerticalFlipadst
  Av1TxHorizontalFlipadst
}

/// 2D assembly for IdentityIdentity.  Identity is a scaled 1D transform in
/// AV1; returning the coefficient plane unchanged is therefore incorrect.
fn av1_inverse_identity_identity_2d(
  input : Array[Int],
  width : Int,
  height : Int,
  bit_depth : Int,
) -> Array[Int]? {
  av1_inverse_identity_dct_2d(input, width, height, false, bit_depth~, row_identity=true, col_identity=true)
}

/// Spec inverse ADST4 (7.13.2.6) with the SINPI constants.
fn av1_inv_adst4_1d(in0 : Int, in1 : Int, in2 : Int, in3 : Int) -> Array[Int] {
  let s0 = 1321 * in0
  let s1 = 2482 * in0
  let s2 = 3344 * in1
  let s3 = 3803 * in2
  let s4 = 1321 * in2
  let s5 = 2482 * in3
  let s6 = 3803 * in3
  let a7 = in0 - in2
  let b7 = a7 + in3
  let s0b = s0 + s3 + s5
  let s1b = s1 - s4 - s6
  let s3b = s2
  let s2b = 3344 * b7
  [
    av1_round2(s0b + s3b, 12),
    av1_round2(s1b + s3b, 12),
    av1_round2(s2b, 12),
    av1_round2(s0b + s1b - s3b, 12),
  ]
}

///|
/// Spec inverse ADST8/ADST16 (7.13.2.7-8): input permutation, B/H butterflies
/// with Round2(x, 12), output permutation with sign flips. Scale-preserving.
fn av1_inverse_adst_1d(input : Array[Int], n : Int, clamp_bits : Int) -> Array[Int]? {
  let count = 1 << n
  if (n != 3 && n != 4) || input.length() != count { return None }
  let t = input.copy()
  let copy = t.copy()
  for i in 0..<count {
    let idx = if i % 2 == 1 { i - 1 } else { count - i - 1 }
    t[i] = copy[idx]
  }
  if n == 3 {
    for i in 0..<4 { av1_bfly(t, 2 * i, 2 * i + 1, 60 - 16 * i, 1) }
    for i in 0..<4 { av1_had(t, i, 4 + i, 0, clamp_bits) }
    for i in 0..<2 { av1_bfly(t, 4 + 3 * i, 5 + i, 48 - 32 * i, 1) }
    for i in 0..<2 { for j in 0..<2 { av1_had(t, 4 * j + i, 2 + 4 * j + i, 0, clamp_bits) } }
    for i in 0..<2 { av1_bfly(t, 2 + 4 * i, 3 + 4 * i, 32, 1) }
  } else {
    for i in 0..<8 { av1_bfly(t, 2 * i, 2 * i + 1, 62 - 8 * i, 1) }
    for i in 0..<8 { av1_had(t, i, 8 + i, 0, clamp_bits) }
    for i in 0..<2 {
      av1_bfly(t, 8 + 2 * i, 9 + 2 * i, 56 - 32 * i, 1)
      av1_bfly(t, 13 + 2 * i, 12 + 2 * i, 8 + 32 * i, 1)
    }
    for i in 0..<4 { for j in 0..<2 { av1_had(t, 8 * j + i, 4 + 8 * j + i, 0, clamp_bits) } }
    for i in 0..<2 { for j in 0..<2 { av1_bfly(t, 4 + 8 * j + 3 * i, 5 + 8 * j + i, 48 - 32 * i, 1) } }
    for i in 0..<2 { for j in 0..<4 { av1_had(t, 4 * j + i, 2 + 4 * j + i, 0, clamp_bits) } }
    for i in 0..<4 { av1_bfly(t, 2 + 4 * i, 3 + 4 * i, 32, 1) }
  }
  let out = t.copy()
  let bits = n
  for i in 0..<count {
    let a = (i >> 3) & 1
    let b = ((i >> 2) & 1) ^ ((i >> 3) & 1)
    let c = ((i >> 1) & 1) ^ ((i >> 2) & 1)
    let d = (i & 1) ^ ((i >> 1) & 1)
    let idx = ((d << 3) | (c << 2) | (b << 1) | a) >> (4 - bits)
    out[i] = if i % 2 == 1 { -t[idx] } else { t[idx] }
  }
  Some(out)
}

///|
/// FLIPADST variant: the ADST output written in reverse order.
fn av1_inverse_flipadst_1d(input : Array[Int], n : Int, clamp_bits : Int) -> Array[Int]? {
  let count = 1 << n
  if (n < 2 || n > 4) || input.length() != count { return None }
  let out = if n == 2 {
    av1_inv_adst4_1d(input[0], input[1], input[2], input[3])
  } else {
    match av1_inverse_adst_1d(input, n, clamp_bits) {
      Some(v) => v
      None => return None
    }
  }
  let flipped : Array[Int] = []
  for i in 0..<count {
    flipped.push(out[count - 1 - i])
  }
  Some(flipped)
}

///|
/// Row shift from the spec Transform_Row_Shift table (square transforms).
fn av1_adst_row_shift(side : Int) -> Int {
  if side == 4 {
    0
  } else if side == 8 {
    1
  } else {
    2
  }
}

///|
/// 2D inverse transform assembly for the ADST family (AV1 spec 7.13.3):
/// rows scaled by Round2(T, rowShift) and clamped, then columns scaled by
/// Round2(T, 4). The 1D passes are scale-preserving; this assembly provides
/// the size normalisation that the 1D functions intentionally omit.
fn av1_inverse_adst_2d(
  input : Array[Int],
  width : Int,
  height : Int,
  row_adst : Bool,
  col_adst : Bool,
  row_flip : Bool,
  col_flip : Bool,
  bit_depth? : Int = 8,
) -> Array[Int]? {
  if (width != 4 && width != 8 && width != 16 && width != 32) ||
    (height != 4 && height != 8 && height != 16 && height != 32) ||
    input.length() != width * height || bit_depth < 8 || bit_depth > 16 {
    return None
  }
  let row_n = if width == 4 {
    2
  } else if width == 8 {
    3
  } else if width == 16 {
    4
  } else {
    5
  }
  let col_n = if height == 4 {
    2
  } else if height == 8 {
    3
  } else if height == 16 {
    4
  } else {
    5
  }
  let row_shift = av1_adst_row_shift(width)
  let row_clamp = bit_depth + 8
  let col_clamp = if bit_depth + 6 > 16 { bit_depth + 6 } else { 16 }
  let col_shift = 4
  let clamp_lo : Int64 = -(1L << (col_clamp - 1))
  let clamp_hi : Int64 = (1L << (col_clamp - 1)) - 1L
  let temp : Array[Int] = Array::make(width * height, 0)
  for y in 0..<height {
    let row : Array[Int] = []
    for x in 0..<width {
      row.push(input[y * width + x])
    }
    let v = if row_adst {
      if row_flip {
        av1_inverse_flipadst_1d(row, row_n, row_clamp)
      } else if row_n == 2 {
        Some(av1_inv_adst4_1d(row[0], row[1], row[2], row[3]))
      } else {
        av1_inverse_adst_1d(row, row_n, row_clamp)
      }
    } else {
      av1_inverse_dct(row, row_n, row_clamp)
    }
    let values = match v {
      Some(x) => x
      None => return None
    }
    for x in 0..<width {
      temp[y * width + x] = av1_round2(values[x], row_shift)
    }
  }
  for i in 0..<(width * height) {
    let v = temp[i].to_int64()
    temp[i] = if v < clamp_lo {
      clamp_lo.to_int()
    } else if v > clamp_hi {
      clamp_hi.to_int()
    } else {
      temp[i]
    }
  }
  let out : Array[Int] = Array::make(width * height, 0)
  for x in 0..<width {
    let col : Array[Int] = []
    for y in 0..<height {
      col.push(temp[y * width + x])
    }
    let v = if col_adst {
      if col_flip {
        av1_inverse_flipadst_1d(col, col_n, col_clamp)
      } else if col_n == 2 {
        Some(av1_inv_adst4_1d(col[0], col[1], col[2], col[3]))
      } else {
        av1_inverse_adst_1d(col, col_n, col_clamp)
      }
    } else {
      av1_inverse_dct(col, col_n, col_clamp)
    }
    let values = match v {
      Some(x) => x
      None => return None
    }
    for y in 0..<height {
      out[y * width + x] = av1_round2(values[y], col_shift)
    }
  }
  Some(out)
}

///|
/// Spec inverse identity 1D scaling (7.13.2.11 through 7.13.2.14): the
/// identity transform is NOT a passthrough; it carries the size-dependent
/// sqrt2/2/2sqrt2/4 normalisation.
fn av1_inverse_identity_1d(input : Array[Int], n : Int) -> Array[Int]? {
  let count = 1 << n
  if input.length() != count { return None }
  let out : Array[Int] = []
  if n == 2 {
    for i in 0..<count {
      out.push(av1_round2(input[i] * 5793, 12))
    }
  } else if n == 3 {
    for i in 0..<count {
      out.push(input[i] * 2)
    }
  } else if n == 4 {
    for i in 0..<count {
      out.push(av1_round2(input[i] * 11586, 12))
    }
  } else if n == 5 {
    for i in 0..<count {
      out.push(input[i] * 4)
    }
  } else {
    return None
  }
  Some(out)
}

///|
/// 2D assembly for V_DCT / H_DCT (AV1 spec 7.13.3): one axis is the identity
/// transform, the other the DCT, with the same row/column shift chain as the
/// ADST family. `cols_dct` selects the axis carrying the DCT.
fn av1_inverse_identity_dct_2d(
  input : Array[Int],
  width : Int,
  height : Int,
  cols_dct : Bool,
  bit_depth? : Int = 8,
  row_identity? : Bool = false,
  col_identity? : Bool = false,
) -> Array[Int]? {
  if (width != 4 && width != 8 && width != 16 && width != 32) ||
    (height != 4 && height != 8 && height != 16 && height != 32) ||
    input.length() != width * height || bit_depth < 8 || bit_depth > 16 {
    return None
  }
  let log = fn(size : Int) -> Int {
    if size == 4 {
      2
    } else if size == 8 {
      3
    } else if size == 16 {
      4
    } else {
      5
    }
  }
  let row_n = log(width)
  let col_n = log(height)
  let row_shift = av1_adst_row_shift(width)
  let row_clamp = bit_depth + 8
  let col_clamp = if bit_depth + 6 > 16 { bit_depth + 6 } else { 16 }
  let col_shift = 4
  let clamp_lo : Int64 = -(1L << (col_clamp - 1))
  let clamp_hi : Int64 = (1L << (col_clamp - 1)) - 1L
  let temp : Array[Int] = Array::make(width * height, 0)
      for y in 0..<height {
        let row : Array[Int] = []
    for x in 0..<width {
      row.push(input[y * width + x])
    }
    let row_is_identity = if row_identity { true } else { cols_dct }
    let v = if row_is_identity {
      // V_DCT and IdentityIdentity: rows are the identity transform.
      av1_inverse_identity_1d(row, row_n)
    } else {
      av1_inverse_dct(row, row_n, row_clamp)
    }
    let values = match v {
      Some(x) => x
      None => return None
    }
    for x in 0..<width {
      temp[y * width + x] = av1_round2(values[x], row_shift)
    }
  }
  for i in 0..<(width * height) {
    let v = temp[i].to_int64()
    temp[i] = if v < clamp_lo {
      clamp_lo.to_int()
    } else if v > clamp_hi {
      clamp_hi.to_int()
    } else {
      temp[i]
      }
    }
      let out : Array[Int] = Array::make(width * height, 0)
      for x in 0..<width {
        let col : Array[Int] = []
    for y in 0..<height {
      col.push(temp[y * width + x])
      }
    let col_is_dct = if col_identity { false } else { cols_dct }
    let v = if col_is_dct {
      av1_inverse_dct(col, col_n, col_clamp)
    } else {
      // H_DCT: columns are the identity transform.
      av1_inverse_identity_1d(col, col_n)
    }
    let values = match v {
      Some(x) => x
      None => return None
    }
    for y in 0..<height {
      out[y * width + x] = av1_round2(values[y], col_shift)
    }
    }
  Some(out)
}

/// Dispatch a coded transform type. DCT_DCT and lossless WHT are implemented;
/// other AV1 transform types remain explicit unsupported boundaries.
pub fn av1_inverse_transform_2d(
  tx_type : Av1TxType,
  dequant : Array[Int],
  width : Int,
  height : Int,
  bit_depth : Int,
  lossless? : Bool = false,
) -> Array[Int]? {
  match tx_type {
    Av1TxDctDct => av1_inverse_dct_2d(dequant, width, height, bit_depth, lossless~)
    Av1TxAdstDct => av1_inverse_adst_2d(dequant, width, height, true, false, false, false, bit_depth~)
    Av1TxDctAdst => av1_inverse_adst_2d(dequant, width, height, false, true, false, false, bit_depth~)
    Av1TxAdstAdst => av1_inverse_adst_2d(dequant, width, height, true, true, false, false, bit_depth~)
    Av1TxFlipadstDct => av1_inverse_adst_2d(dequant, width, height, true, false, true, false, bit_depth~)
    Av1TxDctFlipadst => av1_inverse_adst_2d(dequant, width, height, false, true, false, true, bit_depth~)
    Av1TxFlipadstFlipadst => av1_inverse_adst_2d(dequant, width, height, true, true, true, true, bit_depth~)
    Av1TxAdstFlipadst => av1_inverse_adst_2d(dequant, width, height, true, true, false, true, bit_depth~)
    Av1TxFlipadstAdst => av1_inverse_adst_2d(dequant, width, height, true, true, true, false, bit_depth~)
    Av1TxIdentityIdentity => av1_inverse_identity_identity_2d(dequant, width, height, bit_depth)
    Av1TxIdentityDct => av1_inverse_identity_dct_2d(dequant, width, height, false, bit_depth~)
    Av1TxDctIdentity => av1_inverse_identity_dct_2d(dequant, width, height, true, bit_depth~)
    Av1TxVerticalDct => av1_inverse_identity_dct_2d(dequant, width, height, true, bit_depth~)
    Av1TxHorizontalDct => av1_inverse_identity_dct_2d(dequant, width, height, false, bit_depth~)
    Av1TxVerticalAdst => av1_inverse_adst_2d(dequant, width, height, false, true, false, false, bit_depth~)
    Av1TxHorizontalAdst => av1_inverse_adst_2d(dequant, width, height, true, false, false, false, bit_depth~)
    Av1TxVerticalFlipadst => av1_inverse_adst_2d(dequant, width, height, false, true, false, true, bit_depth~)
    Av1TxHorizontalFlipadst => av1_inverse_adst_2d(dequant, width, height, true, false, true, false, bit_depth~)
  }
}

///|
test "transform dispatch preserves DCT_DCT and rejects unimplemented ADST" {
  let input = Array::make(16, 0)
  assert_true(av1_inverse_transform_2d(Av1TxDctDct, input, 4, 4, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxAdstDct, input, 4, 4, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxFlipadstDct, input, 4, 4, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxAdstAdst, Array::make(64, 0), 8, 8, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxIdentityIdentity, Array::make(32, 0), 4, 8, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxDctAdst, Array::make(32, 0), 4, 8, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxAdstDct, Array::make(32, 0), 8, 4, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxVerticalDct, Array::make(32, 0), 4, 8, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxHorizontalAdst, Array::make(32, 0), 8, 4, 8) is Some(_))
}

/// Nonzero regression coverage for axis-specific FLIPADST dispatch.  A
/// flip must be applied inside the corresponding 1D transform axis; flipping
/// a completed 2D DCT image produces a different result for non-symmetric
/// coefficients.
test "flipadst dispatch applies the flip on the selected axis" {
  let input : Array[Int] = [3, -2, 1, 0, 4, 5, -1, 2, 0, 1, 2, -3, 6, 0, -2, 1]
  let expected_row = av1_inverse_adst_2d(input, 4, 4, true, false, true, false, bit_depth=8).unwrap()
  let actual_row = av1_inverse_transform_2d(Av1TxFlipadstDct, input, 4, 4, 8).unwrap()
  for i in 0..<16 { assert_eq(actual_row[i], expected_row[i]) }
  let expected_col = av1_inverse_adst_2d(input, 4, 4, false, true, false, true, bit_depth=8).unwrap()
  let actual_col = av1_inverse_transform_2d(Av1TxDctFlipadst, input, 4, 4, 8).unwrap()
  for i in 0..<16 { assert_eq(actual_col[i], expected_col[i]) }
  let expected_vertical = av1_inverse_adst_2d(input, 4, 4, false, true, false, true, bit_depth=8).unwrap()
  let actual_vertical = av1_inverse_transform_2d(Av1TxVerticalFlipadst, input, 4, 4, 8).unwrap()
  for i in 0..<16 { assert_eq(actual_vertical[i], expected_vertical[i]) }
  let expected_horizontal = av1_inverse_adst_2d(input, 4, 4, true, false, true, false, bit_depth=8).unwrap()
  let actual_horizontal = av1_inverse_transform_2d(Av1TxHorizontalFlipadst, input, 4, 4, 8).unwrap()
  for i in 0..<16 { assert_eq(actual_horizontal[i], expected_horizontal[i]) }
}

test "identity transform applies normative 1D scaling and validates shapes" {
  let scaled = av1_inverse_identity_1d([2, 0, 0, 0], 2).unwrap()
  assert_eq(scaled[0], 3)
  let input : Array[Int] = Array::make(16, 0)
  input[0] = 4096
  let out = av1_inverse_transform_2d(Av1TxIdentityIdentity, input, 4, 4, 8).unwrap()
  assert_true(out[0] != input[0])
  assert_true(av1_inverse_transform_2d(Av1TxIdentityDct, Array::make(8, 0), 4, 4, 8) is None)
  assert_true(av1_inverse_transform_2d(Av1TxDctIdentity, Array::make(8, 0), 4, 4, 8) is None)
  assert_true(av1_inverse_transform_2d(Av1TxIdentityDct, Array::make(1024, 0), 32, 32, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxDctIdentity, Array::make(1024, 0), 32, 32, 8) is Some(_))
  assert_true(av1_inverse_transform_2d(Av1TxIdentityIdentity, Array::make(16, 0), 4, 4, 7) is None)
}

///|
let av1_cos128_lookup : Array[Int] = [
  4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036,
  4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822,
  3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461,
  3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967,
  2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359,
  2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660,
  1567, 1474, 1380, 1285, 1189, 1092, 995, 897,
  799, 700, 601, 501, 401, 301, 201, 101, 0,
]

/// AV1 cos128(angle), with angles reduced modulo 256 (Q12).
fn av1_cos128(angle : Int) -> Int {
  let a = angle & 255
  if a <= 64 {
    av1_cos128_lookup[a]
  } else if a <= 128 {
    -av1_cos128_lookup[128 - a]
  } else if a <= 192 {
    -av1_cos128_lookup[a - 128]
  } else {
    av1_cos128_lookup[256 - a]
  }
}

fn av1_sin128(angle : Int) -> Int {
  av1_cos128(angle - 64)
}

/// AV1 Round2(x,n): add half an ulp and arithmetic shift right.
fn av1_round2(x : Int, n : Int) -> Int {
  if n == 0 {
    x
  } else {
    ((x.to_int64() + (1L << (n - 1))) >> n).to_int()
  }
}

fn av1_clip(lo : Int, hi : Int, x : Int) -> Int {
  if x < lo { lo } else if x > hi { hi } else { x }
}

fn av1_brev(bits : Int, value : Int) -> Int {
  let mut out = 0
  for i in 0..<bits {
    out = out | (((value >> i) & 1) << (bits - 1 - i))
  }
  out
}

fn av1_bfly(t : Array[Int], a : Int, b : Int, angle : Int, flip : Int) -> Unit {
  let ca = av1_cos128(angle)
  let sa = av1_sin128(angle)
  // libaom's half_btf widens products to int64 before Round2.  Keep the
  // public coefficient API as Int while matching that overflow-safe path.
  let x : Int64 = t[a].to_int64() * ca.to_int64() - t[b].to_int64() * sa.to_int64()
  let y : Int64 = t[a].to_int64() * sa.to_int64() + t[b].to_int64() * ca.to_int64()
  let xx = ((x + 2048L) >> 12).to_int()
  let yy = ((y + 2048L) >> 12).to_int()
  if flip == 1 { t[a] = yy; t[b] = xx } else { t[a] = xx; t[b] = yy }
}

fn av1_had(t : Array[Int], a0 : Int, b0 : Int, flip : Int, bits : Int) -> Unit {
  let a = if flip == 1 { b0 } else { a0 }
  let b = if flip == 1 { a0 } else { b0 }
  let lo : Int64 = -(1L << (bits - 1))
  let hi : Int64 = (1L << (bits - 1)) - 1L
  let x = t[a].to_int64()
  let y = t[b].to_int64()
  let sum = if x + y < lo { lo } else if x + y > hi { hi } else { x + y }
  let diff = if x - y < lo { lo } else if x - y > hi { hi } else { x - y }
  t[a] = sum.to_int()
  t[b] = diff.to_int()
}

/// In-place inverse DCT schedule for n=2..6 (length 4,8,16,32,64).
fn av1_inverse_dct_in_place(t : Array[Int], n : Int, clamp_bits : Int) -> Unit {
  let copy = t.copy()
  let count = 1 << n
  for i in 0..<count { t[i] = copy[av1_brev(n, i)] }
  if n == 6 {
    for i in 0..<16 { av1_bfly(t, 32 + i, 63 - i, 63 - 4 * av1_brev(4, i), 0) }
  }
  if n >= 5 {
    for i in 0..<8 { av1_bfly(t, 16 + i, 31 - i, 6 + (av1_brev(3, 7 - i) << 3), 0) }
  }
  if n == 6 { for i in 0..<16 { av1_had(t, 32 + i * 2, 33 + i * 2, i & 1, clamp_bits) } }
  if n >= 4 {
    for i in 0..<4 { av1_bfly(t, 8 + i, 15 - i, 12 + (av1_brev(2, 3 - i) << 4), 0) }
  }
  if n >= 5 { for i in 0..<8 { av1_had(t, 16 + 2 * i, 17 + 2 * i, i & 1, clamp_bits) } }
  if n == 6 {
    for i in 0..<4 { for j in 0..<2 { av1_bfly(t, 62 - i * 4 - j, 33 + i * 4 + j, 60 - 16 * av1_brev(2, i) + 64 * j, 1) } }
  }
  if n >= 3 { for i in 0..<2 { av1_bfly(t, 4 + i, 7 - i, 56 - 32 * i, 0) } }
  if n >= 4 { for i in 0..<4 { av1_had(t, 8 + 2 * i, 9 + 2 * i, i & 1, clamp_bits) } }
  if n >= 5 {
    for i in 0..<2 { for j in 0..<2 { av1_bfly(t, 30 - 4 * i - j, 17 + 4 * i + j, 24 + (j << 6) + ((1 - i) << 5), 1) } }
  }
  if n == 6 {
    for i in 0..<8 { for j in 0..<2 { av1_had(t, 32 + i * 4 + j, 35 + i * 4 - j, i & 1, clamp_bits) } }
  }
  for i in 0..<2 { av1_bfly(t, 2 * i, 2 * i + 1, 32 + 16 * i, 1 - i) }
  if n >= 3 { for i in 0..<2 { av1_had(t, 4 + 2 * i, 5 + 2 * i, i, clamp_bits) } }
  if n >= 4 { for i in 0..<2 { av1_bfly(t, 14 - i, 9 + i, 48 + 64 * i, 1) } }
  if n >= 5 {
    for i in 0..<4 { for j in 0..<2 { av1_had(t, 16 + 4 * i + j, 19 + 4 * i - j, i & 1, clamp_bits) } }
  }
  if n == 6 {
    for i in 0..<2 { for j in 0..<4 { av1_bfly(t, 61 - i * 8 - j, 34 + i * 8 + j, 56 - i * 32 + (j >> 1) * 64, 1) } }
  }
  for i in 0..<2 { av1_had(t, i, 3 - i, 0, clamp_bits) }
  if n >= 3 { av1_bfly(t, 6, 5, 32, 1) }
  if n >= 4 {
    for i in 0..<2 { for j in 0..<2 { av1_had(t, 8 + 4 * i + j, 11 + 4 * i - j, i, clamp_bits) } }
  }
  if n >= 5 { for i in 0..<4 { av1_bfly(t, 29 - i, 18 + i, 48 + (i >> 1) * 64, 1) } }
  if n == 6 {
    for i in 0..<4 { for j in 0..<4 { av1_had(t, 32 + 8 * i + j, 39 + 8 * i - j, i & 1, clamp_bits) } }
  }
  if n >= 3 { for i in 0..<4 { av1_had(t, i, 7 - i, 0, clamp_bits) } }
  if n >= 4 { for i in 0..<2 { av1_bfly(t, 13 - i, 10 + i, 32, 1) } }
  if n >= 5 {
    for i in 0..<2 { for j in 0..<4 { av1_had(t, 16 + i * 8 + j, 23 + i * 8 - j, i, clamp_bits) } }
  }
  if n == 6 {
    for i in 0..<8 {
      let angle = if i >= 4 { 112 } else { 48 }
      av1_bfly(t, 59 - i, 36 + i, angle, 1)
    }
  }
  if n >= 4 { for i in 0..<8 { av1_had(t, i, 15 - i, 0, clamp_bits) } }
  if n >= 5 { for i in 0..<4 { av1_bfly(t, 27 - i, 20 + i, 32, 1) } }
  if n == 6 {
    for i in 0..<8 { av1_had(t, 32 + i, 47 - i, 0, clamp_bits); av1_had(t, 48 + i, 63 - i, 1, clamp_bits) }
  }
  if n >= 5 { for i in 0..<16 { av1_had(t, i, 31 - i, 0, clamp_bits) } }
  if n == 6 {
    for i in 0..<8 { av1_bfly(t, 55 - i, 40 + i, 32, 1) }
    for i in 0..<32 { av1_had(t, i, 63 - i, 0, clamp_bits) }
  }
}

/// Exact AV1 inverse DCT. `n` is log2(length), and `clamp_bits` is the
/// intermediate range `r` from §7.13.2.3 (normally BitDepth+8 or +6).
pub fn av1_inverse_dct(input : Array[Int], n : Int, clamp_bits : Int) -> Array[Int]? {
  if n < 2 || n > 6 || input.length() != (1 << n) || clamp_bits < 2 || clamp_bits > 32 { return None }
  let out = input.copy()
  av1_inverse_dct_in_place(out, n, clamp_bits)
  Some(out)
}

/// Exact DC-only specialization. It uses the same normative butterfly path,
/// making the result bit-identical to a block with all AC coefficients zero.
pub fn av1_inverse_dct_dc(dc : Int, n : Int, clamp_bits : Int) -> Array[Int]? {
  if n < 2 || n > 6 { return None }
  let input : Array[Int] = Array::make(1 << n, 0)
  input[0] = dc
  av1_inverse_dct(input, n, clamp_bits)
}

fn av1_tx_row_shift(width : Int, height : Int) -> Int? {
  if width == height {
    if width == 4 { Some(0) } else if width == 8 { Some(1) } else if width == 16 { Some(2) } else if width == 32 || width == 64 { Some(2) } else { None }
  } else if (width == 4 && height == 8) || (width == 8 && height == 4) {
    Some(0)
  } else if (width == 8 && height == 16) || (width == 16 && height == 8) || (width == 16 && height == 32) || (width == 32 && height == 16) || (width == 32 && height == 64) || (width == 64 && height == 32) {
    Some(1)
  } else if (width == 4 && height == 16) || (width == 16 && height == 4) {
    Some(1)
  } else if (width == 8 && height == 32) || (width == 32 && height == 8) || (width == 16 && height == 64) || (width == 64 && height == 16) {
    Some(2)
  }
  else { None }
}

/// 2D DCT_DCT inverse transform (§7.13.3), row-major coefficients/output.
/// Width and height are legal AV1 transform dimensions (4,8,16,32,64).
pub fn av1_inverse_dct_2d(dequant : Array[Int], width : Int, height : Int, bit_depth : Int, lossless? : Bool = false) -> Array[Int]? {
  let row_shift = match av1_tx_row_shift(width, height) { Some(v) => v; None => return None }
  if bit_depth < 8 || bit_depth > 16 || dequant.length() != width * height { return None }
  let logw = if width == 4 { 2 } else if width == 8 { 3 } else if width == 16 { 4 } else if width == 32 { 5 } else { 6 }
  let logh = if height == 4 { 2 } else if height == 8 { 3 } else if height == 16 { 4 } else if height == 32 { 5 } else { 6 }
  let rs = if lossless { 0 } else { row_shift }
  let cs = if lossless { 0 } else { 4 }
  let row_clamp = bit_depth + 8
  let col_clamp = if bit_depth + 6 < 16 { 16 } else { bit_depth + 6 }
  let out : Array[Int] = Array::make(width * height, 0)
  if lossless {
    // AV1 lossless coding uses the 4x4 inverse WHT (§7.13.2.10), with a
    // pre-shift of two bits on rows and no shift on columns.
    if width != 4 || height != 4 { return None }
    for i in 0..<4 {
      let a = dequant[i * 4] >> 2
      let c = dequant[i * 4 + 1] >> 2
      let d = dequant[i * 4 + 2] >> 2
      let b = dequant[i * 4 + 3] >> 2
      let aa = a + c
      let dd = d - b
      let e = (aa - dd) >> 1
      let bb = e - b
      let cc = e - c
      out[i * 4] = aa - bb
      out[i * 4 + 1] = bb
      out[i * 4 + 2] = cc
      out[i * 4 + 3] = dd + cc
    }
    for j in 0..<4 {
      let a = out[j]
      let c = out[4 + j]
      let d = out[8 + j]
      let b = out[12 + j]
      let aa = a + c
      let dd = d - b
      let e = (aa - dd) >> 1
      let bb = e - b
      let cc = e - c
      out[j] = aa - bb
      out[4 + j] = bb
      out[8 + j] = cc
      out[12 + j] = dd + cc
    }
    return Some(out)
  }
  for i in 0..<height {
    let row : Array[Int] = Array::make(1 << logw, 0)
    for j in 0..<width { row[j] = dequant[i * width + j] }
    if !lossless && (logw - logh == 1 || logh - logw == 1) { for j in 0..<width { row[j] = ((row[j].to_int64() * 2896L + 2048L) >> 12).to_int() } }
    let transformed = match av1_inverse_dct(row, logw, row_clamp) { Some(v) => v; None => return None }
    for j in 0..<width { out[i * width + j] = av1_round2(transformed[j], rs) }
  }
  let lo = -(1 << (col_clamp - 1))
  let hi = (1 << (col_clamp - 1)) - 1
  for i in 0..<out.length() { out[i] = av1_clip(lo, hi, out[i]) }
  for j in 0..<width {
    let col : Array[Int] = Array::make(1 << logh, 0)
    for i in 0..<height { col[i] = out[i * width + j] }
    let transformed = match av1_inverse_dct(col, logh, col_clamp) { Some(v) => v; None => return None }
    for i in 0..<height { out[i * width + j] = av1_round2(transformed[i], cs) }
  }
  Some(out)
}
