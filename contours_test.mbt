fn contour_test_image() -> @pixelforge.Image {
  let image = @pixelforge.Image::new(5, 4)
  // Two bright components: a 2x2 square and an isolated pixel.
  image.set_pixel(1, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image.set_pixel(2, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image.set_pixel(1, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image.set_pixel(2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image.set_pixel(4, 3, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image
}

test "contours returns row-major boundary pixels by component" {
  let contours = contour_test_image().contours(0)
  assert_eq(contours.length(), 2)
  assert_eq(contours[0].length(), 4)
  assert_eq(contours[0][0].x, 1)
  assert_eq(contours[0][0].y, 1)
  assert_eq(contours[0][1].x, 2)
  assert_eq(contours[0][1].y, 1)
  assert_eq(contours[0][2].x, 1)
  assert_eq(contours[0][2].y, 2)
  assert_eq(contours[0][3].x, 2)
  assert_eq(contours[0][3].y, 2)
  assert_eq(contours[1].length(), 1)
  assert_eq(contours[1][0].x, 4)
  assert_eq(contours[1][0].y, 3)
}

test "contours uses strict luma threshold and handles empty input" {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\x01', b'\x01', b'\x01', b'\xFF')
  image.set_pixel(1, 0, b'\x02', b'\x02', b'\x02', b'\xFF')
  assert_eq(image.contours(1).length(), 1)
  assert_eq(image.contours(2).length(), 0)
  assert_eq(@pixelforge.Image::new(0, 0).contours(0).length(), 0)
}
