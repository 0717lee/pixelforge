/// AV1 §7.11.2 vectors and invariants, 8-bit mode coverage.

///|
test "av1 dc prediction averages both edges and handles availability" {
  let above : Array[Int] = [1, 2, 3, 4]
  let left : Array[Int] = [5, 6, 7, 8]
  let both = av1_intra_predict(AV1_INTRA_DC, 4, 4, above, left, 0, 8).unwrap()
  for value in both {
    assert_eq(value, 5)
  }
  let left_only = av1_intra_predict(
    AV1_INTRA_DC,
    4,
    4,
    [],
    left,
    0,
    8,
    have_above=false,
  ).unwrap()
  for value in left_only {
    assert_eq(value, 7)
  }
  let none = av1_intra_predict(
    AV1_INTRA_DC,
    4,
    4,
    [],
    [],
    0,
    8,
    have_above=false,
    have_left=false,
  ).unwrap()
  for value in none {
    assert_eq(value, 128)
  }
}

///|
test "av1 vertical and horizontal prediction copy edge samples" {
  let above : Array[Int] = [10, 20, 30, 40]
  let left : Array[Int] = [50, 60, 70, 80]
  let vertical = av1_intra_predict(AV1_INTRA_V, 4, 4, above, left, 0, 8).unwrap()
  let horizontal = av1_intra_predict(AV1_INTRA_H, 4, 4, above, left, 0, 8).unwrap()
  assert_eq(vertical, [
    10, 20, 30, 40, 10, 20, 30, 40, 10, 20, 30, 40, 10, 20, 30, 40,
  ])
  assert_eq(horizontal, [
    50, 50, 50, 50, 60, 60, 60, 60, 70, 70, 70, 70, 80, 80, 80, 80,
  ])
}

///|
test "av1 paeth follows tie ordering" {
  let p = av1_intra_predict(
    AV1_INTRA_PAETH,
    4,
    4,
    [100, 100, 100, 100],
    [10, 10, 10, 10],
    20,
    8,
  ).unwrap()
  for value in p {
    assert_eq(value, 100)
  }
  let flat = av1_intra_predict(
    AV1_INTRA_PAETH,
    4,
    4,
    [50, 50, 50, 50],
    [50, 50, 50, 50],
    50,
    8,
  ).unwrap()
  for value in flat {
    assert_eq(value, 50)
  }
}

///|
test "av1 smooth modes match weighted endpoint vectors" {
  let above : Array[Int] = [200, 200, 200, 200]
  let left : Array[Int] = [0, 0, 0, 100]
  let sv = av1_intra_predict(AV1_INTRA_SMOOTH_V, 4, 4, above, left, 0, 8).unwrap()
  assert_eq(sv[0], 200)
  assert_eq(sv[12], 125)
  let sh = av1_intra_predict(AV1_INTRA_SMOOTH_H, 4, 4, above, left, 0, 8).unwrap()
  assert_eq(sh[0], 1)
  assert_eq(sh[3], 150)
  let s = av1_intra_predict(AV1_INTRA_SMOOTH, 4, 4, above, left, 0, 8).unwrap()
  assert_eq(s[0], 100)
  assert_eq(s[15], 150)
}

///|
test "av1 intra prediction validates dimensions and references" {
  assert_true(av1_intra_predict(AV1_INTRA_DC, 2, 4, [], [], 0, 8) is None)
  assert_true(
    av1_intra_predict(AV1_INTRA_DC, 4, 4, [1], [1, 1, 1, 1], 0, 8) is None,
  )
  assert_true(
    av1_intra_predict(99, 4, 4, [1, 1, 1, 1], [1, 1, 1, 1], 0, 8) is None,
  )
}
