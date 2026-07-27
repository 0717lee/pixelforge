///|
/// Resize tests on strips small enough to verify sample positions by hand.

///|
test "resize_nearest doubles a strip by repeating pixels" {
  let r = gray_image(2, 1, [0, 100]).resize_nearest(4, 1)
  assert_eq(r.width, 4)
  assert_eq(r.height, 1)
  assert_eq(r.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(r.get_pixel(1, 0).0.to_int(), 0)
  assert_eq(r.get_pixel(2, 0).0.to_int(), 100)
  assert_eq(r.get_pixel(3, 0).0.to_int(), 100)
}

///|
test "resize_bilinear interpolates the midpoint" {
  // Center-aligned sampling of [0, 100] at 3 columns: edges clamp, middle
  // lands exactly halfway -> 50.
  let r = gray_image(2, 1, [0, 100]).resize_bilinear(3, 1)
  assert_eq(r.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(r.get_pixel(1, 0).0.to_int(), 50)
  assert_eq(r.get_pixel(2, 0).0.to_int(), 100)
}

///|
test "resize_bilinear at the same size is an identity" {
  let r = gray_image(2, 2, [10, 20, 30, 40]).resize_bilinear(2, 2)
  assert_eq(r.get_pixel(0, 0).0.to_int(), 10)
  assert_eq(r.get_pixel(1, 0).0.to_int(), 20)
  assert_eq(r.get_pixel(0, 1).0.to_int(), 30)
  assert_eq(r.get_pixel(1, 1).0.to_int(), 40)
}

///|
test "resize clamps degenerate target sizes to 1x1" {
  let r = gray_image(2, 1, [40, 60]).resize_nearest(0, 0)
  assert_eq(r.width, 1)
  assert_eq(r.height, 1)
}
