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

///|
/// A derived warp model: the fitted matrix plus the four coefficients the
/// prediction consumes. A model this decoder cannot represent (a shear, or a
/// singular fit) is not built at all - the block then decodes with its own
/// motion vector, which is what AV1 specifies for an identity model.
pub(all) struct Av1WarpModel {
  matrix : Array[Int]
  coefficients : Array[Int]
}

///|
/// One neighbour's 4x4 extent, read from the motion field's own record of the
/// block that covers that unit.
fn av1_warp_block_extent(
  field : Av1MotionField,
  row : Int,
  col : Int,
) -> (Int, Int) {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    (0, 0)
  } else {
    let unit = row * field.cols + col
    (field.width4[unit], field.height4[unit])
  }
}

///|
/// Whether the neighbour at that unit names exactly this list.
fn av1_warp_matches(
  field : Av1MotionField,
  row : Int,
  col : Int,
  ref : Int,
) -> Bool {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    false
  } else {
    let unit = row * field.cols + col
    // The second reference is NONE for a single-reference neighbour.
    field.refs[unit * 2] == ref && field.refs[unit * 2 + 1] == -1
  }
}

///|
/// `find_matching_ref` (AV1 7.10.4.3): the mask of 4x4 positions along this
/// block's top and left edges whose neighbour predicts from the same reference,
/// which is what the warp estimator draws its samples from. Bit 32 of each mask
/// marks the top-left and top-right corners.
///
/// `mi_row`/`mi_col` are the block's 4x4 position in the frame, `bw4`/`bh4` its
/// extent and `w4`/`h4` the extents the masks may not step past (the block's own
/// for luma, the plane's for chroma).
fn av1_warp_matching_masks(
  field : Av1MotionField,
  mi_row : Int,
  mi_col : Int,
  bw4 : Int,
  bh4 : Int,
  w4 : Int,
  h4 : Int,
  have_left : Bool,
  have_top : Bool,
  ref_name : Int,
) -> (Int, Int) {
  let mut top_mask = 0
  let mut left_mask = 0
  let mut count = 0
  let mut have_topleft = have_top && have_left
  let mut have_top_right = have_top
  if have_top {
    if av1_warp_matches(field, mi_row - 1, mi_col, ref_name) {
      top_mask = top_mask | 1
      count = 1
    }
    let (aw4_start, _) = av1_warp_block_extent(field, mi_row - 1, mi_col)
    let mut aw4 = aw4_start
    if aw4 >= bw4 {
      // The neighbour is at least as wide as this block. When it is wider, its
      // own offset inside that neighbour decides whether the top-left corner
      // is really this block's, and whether it reaches past the right edge.
      let off = mi_col & (aw4 - 1)
      if off != 0 {
        have_topleft = false
      }
      if aw4 - off <= bw4 {
        // The neighbour does not reach past this block's right edge.
        have_top_right = false
      }
    } else {
      let mut mask = 1 << aw4
      let mut x = aw4
      while x < w4 {
        if av1_warp_matches(field, mi_row - 1, mi_col + x, ref_name) {
          top_mask = top_mask | mask
          count = count + 1
          if count >= 8 {
            return (top_mask, left_mask)
          }
        }
        let (next, _) = av1_warp_block_extent(field, mi_row - 1, mi_col + x)
        aw4 = next
        mask = mask << aw4
        x = x + aw4
      }
    }
  }
  if have_left {
    if av1_warp_matches(field, mi_row, mi_col - 1, ref_name) {
      left_mask = left_mask | 1
      count = count + 1
      if count >= 8 {
        return (top_mask, left_mask)
      }
    }
    let (_, lh4_start) = av1_warp_block_extent(field, mi_row, mi_col - 1)
    let mut lh4 = lh4_start
    if lh4 >= bh4 {
      if (mi_row & (lh4 - 1)) != 0 {
        have_topleft = false
      }
    } else {
      let mut mask = 1 << lh4
      let mut y = lh4
      while y < h4 {
        if av1_warp_matches(field, mi_row + y, mi_col - 1, ref_name) {
          left_mask = left_mask | mask
          count = count + 1
          if count >= 8 {
            return (top_mask, left_mask)
          }
        }
        let (_, next) = av1_warp_block_extent(field, mi_row + y, mi_col - 1)
        lh4 = next
        mask = mask << lh4
        y = y + lh4
      }
    }
  }
  if have_topleft && av1_warp_matches(field, mi_row - 1, mi_col - 1, ref_name) {
    left_mask = left_mask | (1 << 32)
    count = count + 1
    if count >= 8 {
      return (top_mask, left_mask)
    }
  }
  if have_top_right && av1_warp_matches(field, mi_row - 1, mi_col + bw4, ref_name) {
    top_mask = top_mask | (1 << 32)
  }
  (top_mask, left_mask)
}

///|
/// `derive_warpmv` (AV1 7.11.3.5): collect the sample pairs the masks point at,
/// drop the ones whose motion differs from this block's own by more than the
/// size-scaled threshold, fit the affine rows and convert the result into the
/// prediction's coefficients. Returns None when the model the fit produces is
/// one the prediction cannot represent, which the caller decodes as identity
/// and therefore predicts with the block's own motion vector.
fn av1_warp_derive(
  field : Av1MotionField,
  mi_row : Int,
  mi_col : Int,
  bw4 : Int,
  bh4 : Int,
  w4 : Int,
  h4 : Int,
  have_left : Bool,
  have_top : Bool,
  ref_name : Int,
  mv_row : Int,
  mv_col : Int,
) -> Av1WarpModel? {
  let (top_mask, left_mask) = av1_warp_matching_masks(
    field, mi_row, mi_col, bw4, bh4, w4, h4, have_left, have_top, ref_name,
  )
  let pts : Array[Int] = Array::make(8 * 4, 0)
  let mut count = 0
  let widths : Array[Int] = Array::make(8, 0)
  let heights : Array[Int] = Array::make(8, 0)
  let rows : Array[Int] = Array::make(8, 0)
  let cols : Array[Int] = Array::make(8, 0)
  let add = fn(
    delta_row : Int,
    delta_col : Int,
    step_row : Int,
    step_col : Int,
    row : Int,
    col : Int,
  ) -> Unit {
    if count >= 8 {
      return
    }
    let unit = if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
      -1
    } else {
      row * field.cols + col
    }
    if unit < 0 {
      return
    }
    let (bw, bh) = (field.width4[unit], field.height4[unit])
    let in_x = 16 * (2 * delta_col + step_col * bw) - 8
    let in_y = 16 * (2 * delta_row + step_row * bh) - 8
    pts[count * 4] = in_x
    pts[count * 4 + 1] = in_y
    pts[count * 4 + 2] = in_x + field.mv_cols[unit * 2]
    pts[count * 4 + 3] = in_y + field.mv_rows[unit * 2]
    rows[count] = row
    cols[count] = col
    widths[count] = bw
    heights[count] = bh
    count = count + 1
  }
  if top_mask == 1 && (left_mask >> 32) == 0 {
    let (aw4, _) = av1_warp_block_extent(field, mi_row - 1, mi_col)
    let off = mi_col & (aw4 - 1)
    add(-off, 0, 1, -1, mi_row - 1, mi_col)
  } else {
    let mut off = 0
    let mut xmask = top_mask & 0xFFFFFFFF
    while xmask != 0 {
      let tz = av1_warp_lowest_bit(xmask)
      off = off + tz
      xmask = xmask >> tz
      add(off, 0, 1, -1, mi_row - 1, mi_col + off)
      xmask = xmask >> 1
    }
  }
  if left_mask == 1 {
    let (_, lh4) = av1_warp_block_extent(field, mi_row, mi_col - 1)
    let off = mi_row & (lh4 - 1)
    add(0, -off, -1, 1, mi_row - off, mi_col - 1)
  } else {
    let mut off = 0
    let mut ymask = left_mask & 0xFFFFFFFF
    while ymask != 0 {
      let tz = av1_warp_lowest_bit(ymask)
      off = off + tz
      ymask = ymask >> tz
      add(0, off, -1, 1, mi_row + off, mi_col - 1)
      ymask = ymask >> 1
    }
  }
  if (left_mask >> 32) != 0 {
    add(0, 0, -1, -1, mi_row - 1, mi_col - 1)
  }
  if (top_mask >> 32) != 0 {
    add(0, bw4, 1, -1, mi_row - 1, mi_col + bw4)
  }
  if count == 0 {
    return None
  }
  // The threshold scales with the larger block axis, and a sample whose
  // displacement differs from this block's own by more is replaced by the
  // last sample that stays inside it (AV1 7.11.3.5).
  let larger = if bw4 > bh4 { bw4 } else { bh4 }
  let clipped = if larger < 4 {
    4
  } else if larger > 28 {
    28
  } else {
    larger
  }
  let thresh = 4 * clipped
  let mvd : Array[Int] = Array::make(count, 0)
  let mut kept = 0
  for i in 0..<count {
    let dx = pts[i * 4 + 2] - pts[i * 4]
    let dy = pts[i * 4 + 3] - pts[i * 4 + 1]
    let a = if dx - mv_col < 0 { mv_col - dx } else { dx - mv_col }
    let b = if dy - mv_row < 0 { mv_row - dy } else { dy - mv_row }
    if a + b > thresh {
      mvd[i] = -1
    } else {
      mvd[i] = a + b
      kept = kept + 1
    }
  }
  let mut kept = kept
  if kept == 0 {
    kept = 1
    mvd[0] = 0
  } else {
    // Compact the kept samples to the front by swapping from the tail.
    let mut i = 0
    let mut j = count - 1
    let mut k = 0
    while k < count - kept {
      while i < count && mvd[i] != -1 {
        i = i + 1
      }
      while j > i && mvd[j] == -1 {
        j = j - 1
      }
      if i >= j {
        break
      }
      mvd[i] = mvd[j]
      for t in 0..<4 {
        let value = pts[j * 4 + t]
        pts[j * 4 + t] = pts[i * 4 + t]
        pts[i * 4 + t] = value
      }
      i = i + 1
      j = j - 1
      k = k + 1
    }
  }
  let matrix : Array[Int] = [0, 0, 0, 0, 0, 0]
  if av1_warp_find_affine_int(
    pts, kept, bw4, bh4, mv_row, mv_col, matrix, mi_col, mi_row,
  ) {
    return None
  }
  let coefficients : Array[Int] = [0, 0, 0, 0]
  if av1_warp_shear_params(matrix, coefficients) {
    return None
  }
  Some({ matrix, coefficients })
}

///|
/// The index of the lowest set bit, i.e. the count of trailing zeros.
fn av1_warp_lowest_bit(value : Int) -> Int {
  if value == 0 {
    0
  } else {
    let mut out = 0
    let mut x = value
    while (x & 1) == 0 {
      out = out + 1
      x = x >> 1
    }
    out
  }
}

///|
/// The intermediate rounding shift of the two-pass warp filter: four for 8 and
/// 10-bit references, two for 12-bit ones (AV1 7.11.3.8).
fn av1_warp_intermediate_bits(bit_depth : Int) -> Int {
  if bit_depth >= 12 {
    2
  } else {
    4
  }
}

///|
/// The warp filter row for one 1/64-pel phase. `phase` is the subpel offset in
/// 1/65536 units, and the low bits below 1/64-pel are dropped, which is what
/// libdav1d's `dav1d_mc_warp_filter[64 + ((x + 512) >> 10)]` does.
fn av1_warp_filter(phase : Int) -> Array[Int] {
  let index = 64 + ((phase + 512) >> 10)
  if index < 0 {
    av1_warp_filters[0]
  } else if index >= av1_warp_filters.length() {
    av1_warp_filters[av1_warp_filters.length() - 1]
  } else {
    av1_warp_filters[index]
  }
}

///|
/// `warp_affine_8x8`: one 8x8 (or narrower) chunk of a warped prediction.
/// The horizontal pass filters fifteen rows into a scratch buffer with the
/// model's per-row phase, and the vertical pass reads it with the per-column
/// phase, clipping once at the end (AV1 7.11.3.8). Samples past the frame are
/// clamped, which is the same replication libdav1d's `emu_edge` produces.
fn av1_warp_affine_chunk(
  samples : Array[Int],
  stride : Int,
  origin_x : Int,
  origin_y : Int,
  last_x : Int,
  last_y : Int,
  limit : Int,
  coefficients : Array[Int],
  mx : Int,
  my : Int,
  width : Int,
  bit_depth : Int,
) -> Array[Int] {
  let intermediate_bits = av1_warp_intermediate_bits(bit_depth)
  let mut round_shift = 7 - intermediate_bits
  if round_shift < 0 {
    round_shift = 0
  }
  let bias = (1 << round_shift) >> 1
  let mid : Array[Int] = Array::make(15 * 8, 0)
  let mut row_mx = mx
  for row in 0..<15 {
    let source_y = if origin_y + row - 3 < 0 {
      0
    } else if origin_y + row - 3 > last_y {
      last_y
    } else {
      origin_y + row - 3
    }
    let mut tmx = row_mx
    for column in 0..<width {
      let filter = av1_warp_filter(tmx)
      let mut sum = bias
      for tap in 0..<8 {
        let source_x = if origin_x + tap - 3 < 0 {
          0
        } else if origin_x + tap - 3 > last_x {
          last_x
        } else {
          origin_x + tap - 3
        }
        sum = sum + filter[tap] * samples[source_y * stride + source_x]
      }
      mid[row * 8 + column] = sum >> round_shift
      tmx = tmx + coefficients[0]
    }
    row_mx = row_mx + coefficients[1]
  }
  let bias2 = (1 << (7 + intermediate_bits)) >> 1
  let out : Array[Int] = Array::make(8 * width, 0)
  let mut row_my = my
  for row in 0..<8 {
    let mut tmy = row_my
    for column in 0..<width {
      let filter = av1_warp_filter(tmy)
      let mut sum = bias2
      for tap in 0..<8 {
        sum = sum + filter[tap] * mid[(row + tap) * 8 + column]
      }
      let value = sum >> (7 + intermediate_bits)
      out[row * width + column] = if value < 0 {
        0
      } else if value > limit {
        limit
      } else {
        value
      }
      tmy = tmy + coefficients[2]
    }
    row_my = row_my + coefficients[3]
  }
  out
}

///|
/// `warp_predict` (AV1 7.11.3.8) for one plane of one block. The block is walked
/// in 8x8 chunks; each chunk's phase comes from the model evaluated at the
/// chunk's centre in luma coordinates and shifted down by the plane's
/// subsampling, exactly as libdav1d's `mc_warp` does. The result is row-major
/// and already clipped, so the caller stores it like any other prediction.
fn av1_warp_predict(
  reference : Av1RefFrame,
  model : Av1WarpModel,
  plane : Int,
  mi_col : Int,
  mi_row : Int,
  plane_x : Int,
  plane_y : Int,
  plane_width : Int,
  plane_height : Int,
) -> Array[Int] {
  let matrix = model.matrix
  let coefficients = model.coefficients
  let (sub_x, sub_y) = if plane == 0 {
    (0, 0)
  } else {
    (reference.sub_x, reference.sub_y)
  }
  let stride = if plane == 0 {
    reference.coded_width
  } else {
    (reference.coded_width + 1) >> reference.sub_x
  }
  // Clamp against the visible reference extent, never the padded allocation.
  let last_x = ((reference.width + sub_x) >> sub_x) - 1
  let last_y = ((reference.height + sub_y) >> sub_y) - 1
  let limit = (1 << reference.bit_depth) - 1
  let samples = reference.planes[plane]
  let out : Array[Int] = Array::make(plane_width * plane_height, 0)
  let mut y = 0
  while y < plane_height {
    let rows = if plane_height - y < 8 { plane_height - y } else { 8 }
    // The chunk centre in luma coordinates, then the model's two rows at it.
    let src_y = mi_row * 4 + ((y + 4) << sub_y)
    let mat3_y = matrix[3].to_int64() * src_y.to_int64() + matrix[0].to_int64()
    let mat5_y = matrix[5].to_int64() * src_y.to_int64() + matrix[1].to_int64()
    let mut x = 0
    while x < plane_width {
      let width = if plane_width - x < 8 { plane_width - x } else { 8 }
      let src_x = mi_col * 4 + ((x + 4) << sub_x)
      let mvx = (matrix[2].to_int64() * src_x.to_int64() + mat3_y) >> sub_x
      let mvy = (matrix[4].to_int64() * src_x.to_int64() + mat5_y) >> sub_y
      let dx = (mvx >> 16).to_int() - 4
      let mx = ((mvx & 0xFFFFL).to_int() - coefficients[0] * 4 -
        coefficients[1] * 7) &
        (-64)
      let dy = (mvy >> 16).to_int() - 4
      let my = ((mvy & 0xFFFFL).to_int() - coefficients[2] * 4 -
        coefficients[3] * 4) &
        (-64)
      let chunk = av1_warp_affine_chunk(
        samples,
        stride,
        dx,
        dy,
        last_x,
        last_y,
        limit,
        coefficients,
        mx,
        my,
        width,
        reference.bit_depth,
      )
      for row in 0..<rows {
        for column in 0..<width {
          out[(y + row) * plane_width + x + column] = chunk[row * width + column]
        }
      }
      x = x + 8
    }
    y = y + 8
  }
  out
}

///|
/// The warp model a frame-level global-motion entry stands for, or None when
/// the model cannot be represented on the prediction grid (a pure shear, or one
/// whose coefficients the grid clips). The matrix is read, never written: the
/// prediction half only reads it.
pub fn av1_warp_from_global_motion(matrix : Array[Int]) -> Av1WarpModel? {
  if matrix.length() < 6 {
    return None
  }
  let coefficients : Array[Int] = [0, 0, 0, 0]
  if av1_warp_shear_params(matrix, coefficients) {
    None
  } else {
    Some({ matrix, coefficients })
  }
}
