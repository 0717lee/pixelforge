/// The warped-motion fit: the least-squares solve of the two affine rows, the
/// translation pin, and the shear/affine conversion. Every expected matrix here
/// comes from a Python port of libdav1d's `warpmv.c` over the same samples, so
/// the two implementations are pinned against each other rather than against a
/// hand-computed answer.

///|
fn warpmv_affine_fit_case(
  pts : Array[Int],
  count : Int,
  bw4 : Int,
  bh4 : Int,
  bx4 : Int,
  by4 : Int,
  mv_row : Int,
  mv_col : Int,
  expected : Array[Int],
) -> Unit raise {
  let matrix : Array[Int] = [0, 0, 0, 0, 0, 0]
  let singular = av1_warp_find_affine_int(
    pts, count, bw4, bh4, mv_row, mv_col, matrix, bx4, by4,
  )
  assert_eq(singular, false)
  assert_eq(matrix, expected)
}

///|
test "warpmv affine fit matches libdav1d over random sample sets" {
  // case 0: 5 samples over a 4x8 block of 4x4 units
  warpmv_affine_fit_case(
    [
      -224, -592, -220, -564, 416, 544, 420, 581, 704, 1264, 709, 1287, 1216, 32,
      1226, 54, 992, 496, 1006, 528,
    ],
    5,
    4,
    8,
    5,
    3,
    30,
    11,
    [92596, 249243, 65546, -102, -244, 65651],
  )
  // case 1: 3 samples over a 4x16 block of 4x4 units
  warpmv_affine_fit_case(
    [576, -336, 624, -331, -32, 384, 18, 387, 1136, -96, 1180, -89],
    3,
    4,
    16,
    8,
    5,
    10,
    48,
    [417384, 79886, 65187, -207, -144, 65686],
  )
  // case 2: 6 samples over a 16x2 block of 4x4 units
  warpmv_affine_fit_case(
    [
      560, -128, 525, -64, -320, -480, -355, -426, 1024, 464, 996, 524, 16, 1056,
      -26, 1117, 416, -64, 380, -12, 1088, 688, 1061, 741,
    ],
    6,
    16,
    2,
    6,
    3,
    60,
    -34,
    [-303173, 498415, 66055, -260, -121, 65520],
  )
  // case 3: 5 samples over a 16x16 block of 4x4 units
  warpmv_affine_fit_case(
    [
      416, 1168, 453, 1074, -400, -96, -356, -189, 304, 304, 350, 222, -528, -128,
      -488, -208, 512, 896, 555, 808,
    ],
    5,
    16,
    16,
    1,
    8,
    -86,
    43,
    [363946, -683309, 65886, -380, 278, 65045],
  )
  // case 4: 6 samples over a 8x2 block of 4x4 units
  warpmv_affine_fit_case(
    [
      800, 768, 725, 840, 1168, -432, 1085, -367, 928, 224, 842, 285, 96, 1056, 18,
      1120, 624, 896, 550, 959, 544, 64, 471, 134,
    ],
    6,
    8,
    2,
    5,
    1,
    69,
    -79,
    [-646335, 574362, 65462, 251, -240, 65434],
  )
  // case 5: 4 samples over a 4x8 block of 4x4 units
  warpmv_affine_fit_case(
    [
      352, -144, 395, -179, 224, -448, 265, -480, -208, 1024, -168, 987, 1152, 832,
      1195, 788,
    ],
    4,
    4,
    8,
    1,
    9,
    -36,
    46,
    [385228, -274077, 65343, -123, -276, 65187],
  )
  // case 6: 5 samples over a 4x16 block of 4x4 units
  warpmv_affine_fit_case(
    [
      -400, -160, -405, -182, 1248, 1040, 1254, 1028, 48, -624, 48, -642, -464, -144,
      -462, -164, -96, 464, -100, 457,
    ],
    5,
    4,
    16,
    6,
    9,
    -14,
    1,
    [-1468, -149131, 65893, -21, -69, 66082],
  )
  // case 7: 5 samples over a 16x2 block of 4x4 units
  warpmv_affine_fit_case(
    [
      1200, 16, 1261, -17, 512, 1024, 574, 994, 384, 336, 445, 314, -480, 1120, -419,
      1095, -368, -320, -307, -345,
    ],
    5,
    16,
    2,
    4,
    2,
    -29,
    60,
    [487049, -225940, 65611, 86, -279, 65671],
  )
  // case 8: 8 samples over a 8x2 block of 4x4 units
  warpmv_affine_fit_case(
    [
      224, 560, 149, 486, 912, -96, 839, -181, 624, -80, 549, -155, 928, 592, 849,
      513, -288, 272, -362, 198, -304, -352, -385, -423, 784, 192, 699, 119, 1152,
      -288, 1078, -372,
    ],
    8,
    8,
    2,
    5,
    0,
    -77,
    -79,
    [-650566, -620791, 65633, 1, -303, 65740],
  )
  // case 9: 4 samples over a 4x16 block of 4x4 units
  warpmv_affine_fit_case(
    [
      -448, 352, -482, 266, 576, -352, 548, -438, -32, 80, -66, -5, 96, 832, 63,
      750,
    ],
    4,
    4,
    16,
    3,
    11,
    -84,
    -27,
    [-224268, -716845, 65947, -63, 193, 65870],
  )
  // case 10: 4 samples over a 8x8 block of 4x4 units
  warpmv_affine_fit_case(
    [
      816, 336, 726, 348, 16, -304, -71, -292, 192, 400, 101, 422, -608, 1088, -703,
      1109,
    ],
    4,
    8,
    8,
    1,
    8,
    17,
    -89,
    [-710971, 134828, 65520, -379, -239, 65727],
  )
  // case 11: 3 samples over a 4x4 block of 4x4 units
  warpmv_affine_fit_case(
    [-384, 688, -356, 664, 352, 480, 385, 456, -48, 640, -21, 621],
    3,
    4,
    4,
    3,
    4,
    -22,
    33,
    [272463, -179374, 65901, -394, -29, 65523],
  )
}

///|
/// A rotation-only model is the case the estimator is meant to find, and its
/// four prediction coefficients must come back as the rotation's scale terms.
test "warpmv shear params convert a pure rotation" {
  // A small rotation about the block centre, in 16-bit fixed point: the
  // diagonal is the identity scale, so the reciprocal exists and the four
  // coefficients are small enough to survive the model's coefficient clip.
  let matrix : Array[Int] = [0, 0, 0x10000, 0x300, -0x300, 0x10000]
  let coefficients : Array[Int] = [0, 0, 0, 0]
  let shear = av1_warp_shear_params(matrix, coefficients)
  // alpha is zero, so the model is a plain rotation: not a shear. beta and
  // gamma carry the rotation and delta the residual shear term.
  assert_eq(coefficients[0], 0)
  assert_eq(coefficients[1], 768)
  assert_eq(coefficients[2], -768)
  assert_eq(coefficients[3], 0)
  assert_eq(shear, false)
}

///|
/// A model whose horizontal terms overflow the prediction's range is reported
/// as a shear, which the caller decodes as identity.
test "warpmv shear params reject an out-of-range model" {
  // alpha is three quarters of the coefficient space, so 4*alpha saturates and
  // the model cannot be represented on the prediction grid.
  let matrix : Array[Int] = [0, 0, 0x50000, 0, 0, 0x10000]
  let coefficients : Array[Int] = [0, 0, 0, 0]
  let shear = av1_warp_shear_params(matrix, coefficients)
  assert_eq(shear, true)
}

///|
/// A non-positive x scale has no reciprocal, so the model is refused rather
/// than divided by.
test "warpmv shear params refuse a negative x scale" {
  let matrix : Array[Int] = [0, 0, -0x10000, 0, 0, 0x10000]
  let coefficients : Array[Int] = [0, 0, 0, 0]
  assert_eq(av1_warp_shear_params(matrix, coefficients), true)
}

///|
/// A sample whose displacement differs from the block's own motion by 256 or
/// more is dropped before the fit, and the fit of the remaining samples is
/// unchanged. The threshold is what keeps a stray neighbour from dragging the
/// warp model away from the block's own motion.
test "warpmv affine fit drops a far sample" {
  let far : Array[Int] = [
    -160, 32, -150, 40, 96, 224, 104, 230, 352, -64, 360, -56, -128, 64, -900, -300,
  ]
  let base : Array[Int] = [
    -160, 32, -150, 40, 96, 224, 104, 230, 352, -64, 360, -56,
  ]
  let matrix : Array[Int] = [0, 0, 0, 0, 0, 0]
  if av1_warp_find_affine_int(far, 4, 8, 8, -16, 24, matrix, 3, 2) {
    fail("warpmv affine fit: sample set reported singular")
  }
  assert_eq(matrix, [100503, 44785, 66292, 3291, -1627, 59800])
}
