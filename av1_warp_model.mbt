/// The warped-motion least-squares fit and the shear/affine conversion, plus
/// the 1/64-pel warp filter table, transcribed from libdav1d (`warpmv.c` and
/// `tables.c`) and AV1 7.11.3.5 / 7.11.3.8.
///
/// A block that selects LOCALWARP estimates a warp model from the motion
/// vectors of the already-decoded neighbours above and to the left of it, and
/// predicts each sample through that model rather than through a single
/// motion vector. Both halves live here: the fit (`av1_warp_find_affine_int`,
/// `av1_warp_shear_params`) and the model the prediction half consumes
/// (`matrix` with its four `abcd` terms).

///|
/// `div_lut` from libdav1d: a precomputed reciprocal per unit of the divisor's
/// remainder, so the 64x64 least-squares solve needs no division.
let av1_warp_div_lut : Array[Int] = [
  16384, 16320, 16257, 16194, 16132, 16070, 16009, 15948,
  15888, 15828, 15768, 15709, 15650, 15592, 15534, 15477,
  15420, 15364, 15308, 15252, 15197, 15142, 15087, 15033,
  14980, 14926, 14873, 14821, 14769, 14717, 14665, 14614,
  14564, 14513, 14463, 14413, 14364, 14315, 14266, 14218,
  14170, 14122, 14075, 14028, 13981, 13935, 13888, 13843,
  13797, 13752, 13707, 13662, 13618, 13574, 13530, 13487,
  13443, 13400, 13358, 13315, 13273, 13231, 13190, 13148,
  13107, 13066, 13026, 12985, 12945, 12906, 12866, 12827,
  12788, 12749, 12710, 12672, 12633, 12596, 12558, 12520,
  12483, 12446, 12409, 12373, 12336, 12300, 12264, 12228,
  12193, 12157, 12122, 12087, 12053, 12018, 11984, 11950,
  11916, 11882, 11848, 11815, 11782, 11749, 11716, 11683,
  11651, 11619, 11586, 11555, 11523, 11491, 11460, 11429,
  11398, 11367, 11336, 11305, 11275, 11245, 11215, 11185,
  11155, 11125, 11096, 11067, 11038, 11009, 10980, 10951,
  10923, 10894, 10866, 10838, 10810, 10782, 10755, 10727,
  10700, 10673, 10645, 10618, 10592, 10565, 10538, 10512,
  10486, 10460, 10434, 10408, 10382, 10356, 10331, 10305,
  10280, 10255, 10230, 10205, 10180, 10156, 10131, 10107,
  10082, 10058, 10034, 10010, 9986, 9963, 9939, 9916,
  9892, 9869, 9846, 9823, 9800, 9777, 9754, 9732,
  9709, 9687, 9664, 9642, 9620, 9598, 9576, 9554,
  9533, 9511, 9489, 9468, 9447, 9425, 9404, 9383,
  9362, 9341, 9321, 9300, 9279, 9259, 9239, 9218,
  9198, 9178, 9158, 9138, 9118, 9098, 9079, 9059,
  9039, 9020, 9001, 8981, 8962, 8943, 8924, 8905,
  8886, 8867, 8849, 8830, 8812, 8793, 8775, 8756,
  8738, 8720, 8702, 8684, 8666, 8648, 8630, 8613,
  8595, 8577, 8560, 8542, 8525, 8508, 8490, 8473,
  8456, 8439, 8422, 8405, 8389, 8372, 8355, 8339,
  8322, 8306, 8289, 8273, 8257, 8240, 8224, 8208,
  8192,
]

///|
/// `dav1d_mc_warp_filter`: eight taps per 1/64-pel phase, for the range
/// [-1, 1.5). Only the [0, 1) rows are reachable from a clamped phase.
let av1_warp_filters : Array[Array[Int]] = [
  [0, 0, 127, 1, 0, 0, 0, 0],
  [0, -1, 127, 2, 0, 0, 0, 0],
  [1, -3, 127, 4, -1, 0, 0, 0],
  [1, -4, 126, 6, -2, 1, 0, 0],
  [1, -5, 126, 8, -3, 1, 0, 0],
  [1, -6, 125, 11, -4, 1, 0, 0],
  [1, -7, 124, 13, -4, 1, 0, 0],
  [2, -8, 123, 15, -5, 1, 0, 0],
  [2, -9, 122, 18, -6, 1, 0, 0],
  [2, -10, 121, 20, -6, 1, 0, 0],
  [2, -11, 120, 22, -7, 2, 0, 0],
  [2, -12, 119, 25, -8, 2, 0, 0],
  [3, -13, 117, 27, -8, 2, 0, 0],
  [3, -13, 116, 29, -9, 2, 0, 0],
  [3, -14, 114, 32, -10, 3, 0, 0],
  [3, -15, 113, 35, -10, 2, 0, 0],
  [3, -15, 111, 37, -11, 3, 0, 0],
  [3, -16, 109, 40, -11, 3, 0, 0],
  [3, -16, 108, 42, -12, 3, 0, 0],
  [4, -17, 106, 45, -13, 3, 0, 0],
  [4, -17, 104, 47, -13, 3, 0, 0],
  [4, -17, 102, 50, -14, 3, 0, 0],
  [4, -17, 100, 52, -14, 3, 0, 0],
  [4, -18, 98, 55, -15, 4, 0, 0],
  [4, -18, 96, 58, -15, 3, 0, 0],
  [4, -18, 94, 60, -16, 4, 0, 0],
  [4, -18, 91, 63, -16, 4, 0, 0],
  [4, -18, 89, 65, -16, 4, 0, 0],
  [4, -18, 87, 68, -17, 4, 0, 0],
  [4, -18, 85, 70, -17, 4, 0, 0],
  [4, -18, 82, 73, -17, 4, 0, 0],
  [4, -18, 80, 75, -17, 4, 0, 0],
  [4, -18, 78, 78, -18, 4, 0, 0],
  [4, -17, 75, 80, -18, 4, 0, 0],
  [4, -17, 73, 82, -18, 4, 0, 0],
  [4, -17, 70, 85, -18, 4, 0, 0],
  [4, -17, 68, 87, -18, 4, 0, 0],
  [4, -16, 65, 89, -18, 4, 0, 0],
  [4, -16, 63, 91, -18, 4, 0, 0],
  [4, -16, 60, 94, -18, 4, 0, 0],
  [3, -15, 58, 96, -18, 4, 0, 0],
  [4, -15, 55, 98, -18, 4, 0, 0],
  [3, -14, 52, 100, -17, 4, 0, 0],
  [3, -14, 50, 102, -17, 4, 0, 0],
  [3, -13, 47, 104, -17, 4, 0, 0],
  [3, -13, 45, 106, -17, 4, 0, 0],
  [3, -12, 42, 108, -16, 3, 0, 0],
  [3, -11, 40, 109, -16, 3, 0, 0],
  [3, -11, 37, 111, -15, 3, 0, 0],
  [2, -10, 35, 113, -15, 3, 0, 0],
  [3, -10, 32, 114, -14, 3, 0, 0],
  [2, -9, 29, 116, -13, 3, 0, 0],
  [2, -8, 27, 117, -13, 3, 0, 0],
  [2, -8, 25, 119, -12, 2, 0, 0],
  [2, -7, 22, 120, -11, 2, 0, 0],
  [1, -6, 20, 121, -10, 2, 0, 0],
  [1, -6, 18, 122, -9, 2, 0, 0],
  [1, -5, 15, 123, -8, 2, 0, 0],
  [1, -4, 13, 124, -7, 1, 0, 0],
  [1, -4, 11, 125, -6, 1, 0, 0],
  [1, -3, 8, 126, -5, 1, 0, 0],
  [1, -2, 6, 126, -4, 1, 0, 0],
  [0, -1, 4, 127, -3, 1, 0, 0],
  [0, 0, 2, 127, -1, 0, 0, 0],
  [0, 0, 0, 127, 1, 0, 0, 0],
  [0, 0, -1, 127, 2, 0, 0, 0],
  [0, 1, -3, 127, 4, -2, 1, 0],
  [0, 1, -5, 127, 6, -2, 1, 0],
  [0, 2, -6, 126, 8, -3, 1, 0],
  [-1, 2, -7, 126, 11, -4, 2, -1],
  [-1, 3, -8, 125, 13, -5, 2, -1],
  [-1, 3, -10, 124, 16, -6, 3, -1],
  [-1, 4, -11, 123, 18, -7, 3, -1],
  [-1, 4, -12, 122, 20, -7, 3, -1],
  [-1, 4, -13, 121, 23, -8, 3, -1],
  [-2, 5, -14, 120, 25, -9, 4, -1],
  [-1, 5, -15, 119, 27, -10, 4, -1],
  [-1, 5, -16, 118, 30, -11, 4, -1],
  [-2, 6, -17, 116, 33, -12, 5, -1],
  [-2, 6, -17, 114, 35, -12, 5, -1],
  [-2, 6, -18, 113, 38, -13, 5, -1],
  [-2, 7, -19, 111, 41, -14, 6, -2],
  [-2, 7, -19, 110, 43, -15, 6, -2],
  [-2, 7, -20, 108, 46, -15, 6, -2],
  [-2, 7, -20, 106, 49, -16, 6, -2],
  [-2, 7, -21, 104, 51, -16, 7, -2],
  [-2, 7, -21, 102, 54, -17, 7, -2],
  [-2, 8, -21, 100, 56, -18, 7, -2],
  [-2, 8, -22, 98, 59, -18, 7, -2],
  [-2, 8, -22, 96, 62, -19, 7, -2],
  [-2, 8, -22, 94, 64, -19, 7, -2],
  [-2, 8, -22, 91, 67, -20, 8, -2],
  [-2, 8, -22, 89, 69, -20, 8, -2],
  [-2, 8, -22, 87, 72, -21, 8, -2],
  [-2, 8, -21, 84, 74, -21, 8, -2],
  [-2, 8, -22, 82, 77, -21, 8, -2],
  [-2, 8, -21, 79, 79, -21, 8, -2],
  [-2, 8, -21, 77, 82, -22, 8, -2],
  [-2, 8, -21, 74, 84, -21, 8, -2],
  [-2, 8, -21, 72, 87, -22, 8, -2],
  [-2, 8, -20, 69, 89, -22, 8, -2],
  [-2, 8, -20, 67, 91, -22, 8, -2],
  [-2, 7, -19, 64, 94, -22, 8, -2],
  [-2, 7, -19, 62, 96, -22, 8, -2],
  [-2, 7, -18, 59, 98, -22, 8, -2],
  [-2, 7, -18, 56, 100, -21, 8, -2],
  [-2, 7, -17, 54, 102, -21, 7, -2],
  [-2, 7, -16, 51, 104, -21, 7, -2],
  [-2, 6, -16, 49, 106, -20, 7, -2],
  [-2, 6, -15, 46, 108, -20, 7, -2],
  [-2, 6, -15, 43, 110, -19, 7, -2],
  [-2, 6, -14, 41, 111, -19, 7, -2],
  [-1, 5, -13, 38, 113, -18, 6, -2],
  [-1, 5, -12, 35, 114, -17, 6, -2],
  [-1, 5, -12, 33, 116, -17, 6, -2],
  [-1, 4, -11, 30, 118, -16, 5, -1],
  [-1, 4, -10, 27, 119, -15, 5, -1],
  [-1, 4, -9, 25, 120, -14, 5, -2],
  [-1, 3, -8, 23, 121, -13, 4, -1],
  [-1, 3, -7, 20, 122, -12, 4, -1],
  [-1, 3, -7, 18, 123, -11, 4, -1],
  [-1, 3, -6, 16, 124, -10, 3, -1],
  [-1, 2, -5, 13, 125, -8, 3, -1],
  [-1, 2, -4, 11, 126, -7, 2, -1],
  [0, 1, -3, 8, 126, -6, 2, 0],
  [0, 1, -2, 6, 127, -5, 1, 0],
  [0, 1, -2, 4, 127, -3, 1, 0],
  [0, 0, 0, 2, 127, -1, 0, 0],
  [0, 0, 0, 1, 127, 0, 0, 0],
  [0, 0, 0, -1, 127, 2, 0, 0],
  [0, 0, 1, -3, 127, 4, -1, 0],
  [0, 0, 1, -4, 126, 6, -2, 1],
  [0, 0, 1, -5, 126, 8, -3, 1],
  [0, 0, 1, -6, 125, 11, -4, 1],
  [0, 0, 1, -7, 124, 13, -4, 1],
  [0, 0, 2, -8, 123, 15, -5, 1],
  [0, 0, 2, -9, 122, 18, -6, 1],
  [0, 0, 2, -10, 121, 20, -6, 1],
  [0, 0, 2, -11, 120, 22, -7, 2],
  [0, 0, 2, -12, 119, 25, -8, 2],
  [0, 0, 3, -13, 117, 27, -8, 2],
  [0, 0, 3, -13, 116, 29, -9, 2],
  [0, 0, 3, -14, 114, 32, -10, 3],
  [0, 0, 3, -15, 113, 35, -10, 2],
  [0, 0, 3, -15, 111, 37, -11, 3],
  [0, 0, 3, -16, 109, 40, -11, 3],
  [0, 0, 3, -16, 108, 42, -12, 3],
  [0, 0, 4, -17, 106, 45, -13, 3],
  [0, 0, 4, -17, 104, 47, -13, 3],
  [0, 0, 4, -17, 102, 50, -14, 3],
  [0, 0, 4, -17, 100, 52, -14, 3],
  [0, 0, 4, -18, 98, 55, -15, 4],
  [0, 0, 4, -18, 96, 58, -15, 3],
  [0, 0, 4, -18, 94, 60, -16, 4],
  [0, 0, 4, -18, 91, 63, -16, 4],
  [0, 0, 4, -18, 89, 65, -16, 4],
  [0, 0, 4, -18, 87, 68, -17, 4],
  [0, 0, 4, -18, 85, 70, -17, 4],
  [0, 0, 4, -18, 82, 73, -17, 4],
  [0, 0, 4, -18, 80, 75, -17, 4],
  [0, 0, 4, -18, 78, 78, -18, 4],
  [0, 0, 4, -17, 75, 80, -18, 4],
  [0, 0, 4, -17, 73, 82, -18, 4],
  [0, 0, 4, -17, 70, 85, -18, 4],
  [0, 0, 4, -17, 68, 87, -18, 4],
  [0, 0, 4, -16, 65, 89, -18, 4],
  [0, 0, 4, -16, 63, 91, -18, 4],
  [0, 0, 4, -16, 60, 94, -18, 4],
  [0, 0, 3, -15, 58, 96, -18, 4],
  [0, 0, 4, -15, 55, 98, -18, 4],
  [0, 0, 3, -14, 52, 100, -17, 4],
  [0, 0, 3, -14, 50, 102, -17, 4],
  [0, 0, 3, -13, 47, 104, -17, 4],
  [0, 0, 3, -13, 45, 106, -17, 4],
  [0, 0, 3, -12, 42, 108, -16, 3],
  [0, 0, 3, -11, 40, 109, -16, 3],
  [0, 0, 3, -11, 37, 111, -15, 3],
  [0, 0, 2, -10, 35, 113, -15, 3],
  [0, 0, 3, -10, 32, 114, -14, 3],
  [0, 0, 2, -9, 29, 116, -13, 3],
  [0, 0, 2, -8, 27, 117, -13, 3],
  [0, 0, 2, -8, 25, 119, -12, 2],
  [0, 0, 2, -7, 22, 120, -11, 2],
  [0, 0, 1, -6, 20, 121, -10, 2],
  [0, 0, 1, -6, 18, 122, -9, 2],
  [0, 0, 1, -5, 15, 123, -8, 2],
  [0, 0, 1, -4, 13, 124, -7, 1],
  [0, 0, 1, -4, 11, 125, -6, 1],
  [0, 0, 1, -3, 8, 126, -5, 1],
  [0, 0, 1, -2, 6, 126, -4, 1],
  [0, 0, 0, -1, 4, 127, -3, 1],
  [0, 0, 0, 0, 2, 127, -1, 0],
  [0, 0, 0, 0, 2, 127, -1, 0],
]

///|
/// `apply_sign` from libdav1d: the magnitude with the sign of `value`.
fn av1_warp_apply_sign(value : Int, sign : Int) -> Int {
  if sign < 0 {
    -value
  } else {
    value
  }
}

///|
/// `iclip(v, INT16_MIN, INT16_MAX)` then a sign-preserving rounding to the
/// model's 6-bit coefficient grid.
fn av1_warp_iclip_wmp(v : Int) -> Int {
  let clipped = if v < -32768 {
    -32768
  } else if v > 32767 {
    32767
  } else {
    v
  }
  let magnitude = if clipped < 0 { -clipped } else { clipped }
  av1_warp_apply_sign((magnitude + 32) >> 6, clipped) * (1 << 6)
}

///|
/// `resolve_divisor_32`: the reciprocal multiplier and shift for a 32-bit
/// divisor that is not a power of two.
fn av1_warp_resolve_divisor_32(d : Int) -> (Int, Int) {
  let mut shift = 0
  let mut x = d
  while x > 1 {
    shift = shift + 1
    x = x >> 1
  }
  let e = d - (1 << shift)
  let f = if shift > 8 {
    (e + (1 << (shift - 9))) >> (shift - 8)
  } else {
    e << (8 - shift)
  }
  (av1_warp_div_lut[f], shift + 14)
}

///|
/// `resolve_divisor_64`: the same for the 64-bit determinant. The determinant
/// of the normal equations exceeds 32 bits for an eight-sample fit, so the
/// divisor arrives as an Int64 and the products stay in Int64.
fn av1_warp_resolve_divisor_64(d : Int64) -> (Int, Int) {
  let mut shift = 0
  let mut x = d
  while x > 1L {
    shift = shift + 1
    x = x >> 1
  }
  let e = d - (1L << shift)
  let f = if shift > 8 {
    ((e + (1L << (shift - 9))) >> (shift - 8)).to_int()
  } else {
    (e << (8 - shift)).to_int()
  }
  (av1_warp_div_lut[f], shift + 14)
}

///|
/// `dav1d_get_shear_params`: fill the four prediction coefficients from a
/// fitted matrix, and report whether the model is a pure shear that the
/// prediction cannot represent. A shear is decoded as identity.
fn av1_warp_shear_params(
  matrix : Array[Int],
  coefficients : Array[Int],
) -> Bool {
  if matrix[2] <= 0 {
    return true
  }
  coefficients[0] = av1_warp_iclip_wmp(matrix[2] - 0x10000)
  coefficients[1] = av1_warp_iclip_wmp(matrix[3])
  let (y, shift) = av1_warp_resolve_divisor_32(
    if matrix[2] < 0 { -matrix[2] } else { matrix[2] },
  )
  let y = av1_warp_apply_sign(y, matrix[2])
  let rnd = (1 << shift) >> 1
  // `mat[4] * 0x10000 * y` overflows 32 bits for a large gamma, and so does
  // `mat[3] * mat[4] * y`, so both products run in Int64.
  let v1 = matrix[4].to_int64() * 0x10000L * y.to_int64()
  let magnitude = if v1 < 0L { -v1 } else { v1 }
  coefficients[2] = av1_warp_iclip_wmp(
    av1_warp_apply_sign(
      ((magnitude + rnd.to_int64()) >> shift).to_int(),
      if v1 < 0L { -1 } else { 1 },
    ),
  )
  let v2 = matrix[3].to_int64() * matrix[4].to_int64() * y.to_int64()
  let magnitude2 = if v2 < 0L { -v2 } else { v2 }
  coefficients[3] = av1_warp_iclip_wmp(
    matrix[5] -
    av1_warp_apply_sign(
      ((magnitude2 + rnd.to_int64()) >> shift).to_int(),
      if v2 < 0L { -1 } else { 1 },
    ) -
    0x10000,
  )
  let a0 = if coefficients[0] < 0 { -coefficients[0] } else { coefficients[0] }
  let a1 = if coefficients[1] < 0 { -coefficients[1] } else { coefficients[1] }
  let a2 = if coefficients[2] < 0 { -coefficients[2] } else { coefficients[2] }
  let a3 = if coefficients[3] < 0 { -coefficients[3] } else { coefficients[3] }
  (4 * a0 + 7 * a1 >= 0x10000) || (4 * a2 + 4 * a3 >= 0x10000)
}

///|
/// `dav1d_set_affine_mv2d`: pin the model's translation so the block's centre
/// predicts exactly the block's own motion vector.
fn av1_warp_affine_mv2d(
  matrix : Array[Int],
  bw4 : Int,
  bh4 : Int,
  mv_row : Int,
  mv_col : Int,
  bx4 : Int,
  by4 : Int,
) -> Unit {
  let rsuy = 2 * bh4 - 1
  let rsux = 2 * bw4 - 1
  let isuy = by4 * 4 + rsuy
  let isux = bx4 * 4 + rsux
  let v0 = mv_col * 0x2000 - (isux * (matrix[2] - 0x10000) + isuy * matrix[3])
  let v1 = mv_row * 0x2000 - (isux * matrix[4] + isuy * (matrix[5] - 0x10000))
  matrix[0] = if v0 < -0x800000 {
    -0x800000
  } else if v0 > 0x7fffff {
    0x7fffff
  } else {
    v0
  }
  matrix[1] = if v1 < -0x800000 {
    -0x800000
  } else if v1 > 0x7fffff {
    0x7fffff
  } else {
    v1
  }
}

///|
/// `get_mult_shift_ndiag` / `get_mult_shift_diag`: one solved coefficient.
/// The product of a normal-equation entry and the reciprocal exceeds 32 bits,
/// so `px` arrives as an Int64.
fn av1_warp_mult_shift_ndiag(px : Int64, idet : Int, shift : Int) -> Int {
  let v1 = px * idet.to_int64()
  let magnitude = if v1 < 0L { -v1 } else { v1 }
  let v2 = av1_warp_apply_sign(
    ((magnitude + ((1L << shift) >> 1)) >> shift).to_int(),
    if v1 < 0L { -1 } else { 1 },
  )
  if v2 < -0x1fff {
    -0x1fff
  } else if v2 > 0x1fff {
    0x1fff
  } else {
    v2
  }
}

///|
fn av1_warp_mult_shift_diag(px : Int64, idet : Int, shift : Int) -> Int {
  let v1 = px * idet.to_int64()
  let magnitude = if v1 < 0L { -v1 } else { v1 }
  let v2 = av1_warp_apply_sign(
    ((magnitude + ((1L << shift) >> 1)) >> shift).to_int(),
    if v1 < 0L { -1 } else { 1 },
  )
  if v2 < 0xe001 {
    0xe001
  } else if v2 > 0x11fff {
    0x11fff
  } else {
    v2
  }
}

///|
/// `dav1d_find_affine_int`: the weighted least-squares fit of the two affine
/// rows from the sample pairs, or true when the system is singular.
/// `pts` is flat, four integers per sample in the order
/// (in-x, in-y, out-x, out-y), and the model is left in `matrix`.
fn av1_warp_find_affine_int(
  pts : Array[Int],
  count : Int,
  bw4 : Int,
  bh4 : Int,
  mv_row : Int,
  mv_col : Int,
  matrix : Array[Int],
  bx4 : Int,
  by4 : Int,
) -> Bool {
  let mut sxx = 0
  let mut sxy = 0
  let mut syy = 0
  let mut bxx = 0
  let mut bxy = 0
  let mut cxx = 0
  let mut cyy = 0
  let rsuy = 2 * bh4 - 1
  let rsux = 2 * bw4 - 1
  let suy = rsuy * 8
  let sux = rsux * 8
  let duy = suy + mv_row
  let dux = sux + mv_col
  for i in 0..<count {
    let in_x = pts[i * 4]
    let in_y = pts[i * 4 + 1]
    let out_x = pts[i * 4 + 2]
    let out_y = pts[i * 4 + 3]
    let dx = out_x - dux
    let dy = out_y - duy
    let sx = in_x - sux
    let sy = in_y - suy
    let delta_x = sx - dx
    let delta_y = sy - dy
    if (if delta_x < 0 { -delta_x } else { delta_x }) < 256 &&
      (if delta_y < 0 { -delta_y } else { delta_y }) < 256 {
      sxx = sxx + ((sx * sx) >> 2) + sx * 2 + 8
      sxy = sxy + ((sx * sy) >> 2) + sx + sy + 4
      syy = syy + ((sy * sy) >> 2) + sy * 2 + 8
      bxx = bxx + ((sx * dx) >> 2) + sx + dx + 8
      bxy = bxy + ((sy * dx) >> 2) + sy + dx + 4
      cxx = cxx + ((sx * dy) >> 2) + sx + dy + 4
      cyy = cyy + ((sy * dy) >> 2) + sy + dy + 8
    }
  }
  // The determinant of the normal equations, and the reciprocal that solves
  // them without a division. Both products exceed 32 bits for a large sample
  // set, so the whole solve runs in Int64 exactly as libdav1d's does.
  let det = sxx.to_int64() * syy.to_int64() - sxy.to_int64() * sxy.to_int64()
  if det == 0L {
    return true
  }
  let abs_det = if det < 0L { -det } else { det }
  let (idet_raw, shift_raw) = av1_warp_resolve_divisor_64(abs_det)
  let idet = av1_warp_apply_sign(idet_raw, if det < 0L { -1 } else { 1 })
  let mut shift = shift_raw - 16
  let mut idet = idet
  if shift < 0 {
    idet = idet << -shift
    shift = 0
  }
  matrix[2] = av1_warp_mult_shift_diag(
    syy.to_int64() * bxx.to_int64() - sxy.to_int64() * bxy.to_int64(),
    idet,
    shift,
  )
  matrix[3] = av1_warp_mult_shift_ndiag(
    sxx.to_int64() * bxy.to_int64() - sxy.to_int64() * bxx.to_int64(),
    idet,
    shift,
  )
  matrix[4] = av1_warp_mult_shift_ndiag(
    syy.to_int64() * cxx.to_int64() - sxy.to_int64() * cyy.to_int64(),
    idet,
    shift,
  )
  matrix[5] = av1_warp_mult_shift_diag(
    sxx.to_int64() * cyy.to_int64() - sxy.to_int64() * cxx.to_int64(),
    idet,
    shift,
  )
  av1_warp_affine_mv2d(matrix, bw4, bh4, mv_row, mv_col, bx4, by4)
  false
}
