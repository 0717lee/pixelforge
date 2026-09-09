/// Externally derived AV1 inverse DCT vectors. The n=2 vector follows the
/// AOMedia normative B/H schedule (§7.13.2.3; Cos128 Q12 table) and is checked
/// against a scalar translation of libaom av1_idct4 (commit
/// 8e7b6a567df174d795479b92b4ac766d271add73).

///|
test "av1 idct4 matches scalar AV1 schedule vector" {
  match av1_inverse_dct([100, -200, 300, -400], 2, 32) {
    Some(out) => assert_eq(out, [-55, 152, -434, 621])
    None => fail("None")
  }
  assert_eq(av1_inverse_dct([1, 2, 3, 4], 2, 32).unwrap(), [6, -4, 2, 0])
}

///|
test "av1 inverse dct dc is constant for every supported size" {
  for n in 2..<7 {
    let out = av1_inverse_dct_dc(1024, n, 32).unwrap()
    let first = out[0]
    // libaom half_btf(2896, 1024, 2896, 0, 12) = 724.
    assert_eq(first, 724)
    for i in 1..<out.length() { assert_eq(out[i], first) }
  }
}

///|
test "av1 two dimensional dc uses exact signed row and column rounding" {
  // Derived from libaom's Q12 DC half_btf followed by the normative row
  // shift (0/1/2) and column shift (4), including negative half-way ties.
  let sizes = [4, 8, 16, 32, 64]
  let positive = [1, 1, 0, 0, 0]
  let negative = [-1, 0, 0, 0, 0]
  for i in 0..<sizes.length() {
    let size = sizes[i]
    let input = Array::make(size * size, 0)
    input[0] = 31
    let out = av1_inverse_dct_2d(input, size, size, 8).unwrap()
    for value in out { assert_eq(value, positive[i]) }
    input[0] = -31
    let out_negative = av1_inverse_dct_2d(input, size, size, 8).unwrap()
    for value in out_negative { assert_eq(value, negative[i]) }
  }
}

///|
test "av1 64x64 dc residual matches libaom signed dequant fixture" {
  let input = Array::make(64 * 64, 0)
  input[0] = -3587
  let out = av1_inverse_dct_2d(input, 64, 64, 8).unwrap()
  for value in out { assert_eq(value, -28) }
}

///|
test "av1 inverse dct rejects invalid lengths and logarithms" {
  assert_true(av1_inverse_dct([0, 0, 0], 2, 32) is None)
  assert_true(av1_inverse_dct(Array::make(4, 0), 1, 32) is None)
  assert_true(av1_inverse_dct(Array::make(4, 0), 7, 32) is None)
}

///|
test "av1 inverse 2d all zero is zero for square and rectangular blocks" {
  for size in [4, 8, 16, 32, 64] {
    let out = av1_inverse_dct_2d(Array::make(size * size, 0), size, size, 8).unwrap()
    for value in out { assert_eq(value, 0) }
  }
  let rect = av1_inverse_dct_2d(Array::make(4 * 8, 0), 4, 8, 8).unwrap()
  for value in rect { assert_eq(value, 0) }
}

///|
test "av1 lossless inverse wht uses normative row pre-shift" {
  let out = av1_inverse_dct_2d(Array::make(16, 4), 4, 4, 8, lossless=true).unwrap()
  assert_eq(out[0], 4)
  for i in 1..<16 { assert_eq(out[i], 0) }
}
