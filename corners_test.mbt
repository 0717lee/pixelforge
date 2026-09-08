///|
fn corners_test_image() -> @pixelforge.Image {
  let image = @pixelforge.Image::new(7, 7)
  // A bright square on dark background has strong responses at its corners.
  image.fill_rect(2, 2, 3, 3, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image
}

///|
test "harris corners finds strongest square corners" {
  let corners = corners_test_image().harris_corners(1.0, 8)
  assert_true(corners.length() > 0)
  assert_true(corners.length() <= 8)
  // The strongest response is deterministic and must lie in the square's
  // one-pixel neighbourhood rather than on the flat interior.
  assert_true(corners[0].x >= 1 && corners[0].x <= 5)
  assert_true(corners[0].y >= 1 && corners[0].y <= 5)
  assert_true(corners[0].response > 1.0)
}

///|
test "harris corners handles threshold and degenerate images" {
  let flat = @pixelforge.Image::new(4, 4)
  assert_eq(flat.harris_corners(0.0, 4).length(), 0)
  assert_eq(flat.harris_corners(-1.0, 0).length(), 0)
  assert_eq(@pixelforge.Image::new(0, 0).harris_corners(0.0, 4).length(), 0)
}
