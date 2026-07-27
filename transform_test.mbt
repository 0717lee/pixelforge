///|
/// Geometry transform tests on tiny fixtures where every destination pixel can
/// be located by hand.

///|
test "flip_horizontal mirrors columns" {
  let f = gray_image(2, 1, [10, 20]).flip_horizontal()
  assert_eq(f.get_pixel(0, 0).0.to_int(), 20)
  assert_eq(f.get_pixel(1, 0).0.to_int(), 10)
}

///|
test "flip_vertical mirrors rows" {
  let f = gray_image(1, 2, [10, 20]).flip_vertical()
  assert_eq(f.get_pixel(0, 0).0.to_int(), 20)
  assert_eq(f.get_pixel(0, 1).0.to_int(), 10)
}

///|
test "rotate90 turns a row into a column, clockwise" {
  let r = gray_image(2, 1, [10, 20]).rotate90()
  assert_eq(r.width, 1)
  assert_eq(r.height, 2)
  assert_eq(r.get_pixel(0, 0).0.to_int(), 10)
  assert_eq(r.get_pixel(0, 1).0.to_int(), 20)
}

///|
test "double horizontal flip is identity" {
  let img = gray_image(3, 1, [1, 2, 3])
  let back = img.flip_horizontal().flip_horizontal()
  assert_eq(back.get_pixel(0, 0).0.to_int(), 1)
  assert_eq(back.get_pixel(1, 0).0.to_int(), 2)
  assert_eq(back.get_pixel(2, 0).0.to_int(), 3)
}
