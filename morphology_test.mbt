///|
/// Morphology tests: a single bright pixel in a dark field makes every
/// behavior observable pixel-by-pixel.

///|
test "dilate grows a bright pixel into its neighborhood" {
  let img = gray_image(3, 3, [0, 0, 0, 0, 200, 0, 0, 0, 0])
  let d = img.dilate()
  assert_eq(d.get_pixel(0, 0).0.to_int(), 200)
  assert_eq(d.get_pixel(1, 1).0.to_int(), 200)
  assert_eq(d.get_pixel(2, 2).0.to_int(), 200)
}

///|
test "erode removes an isolated bright pixel" {
  let img = gray_image(3, 3, [0, 0, 0, 0, 200, 0, 0, 0, 0])
  assert_eq(img.erode().get_pixel(1, 1).0.to_int(), 0)
}

///|
test "morph_open removes salt noise" {
  let img = gray_image(3, 3, [10, 10, 10, 10, 250, 10, 10, 10, 10])
  assert_eq(img.morph_open().get_pixel(1, 1).0.to_int(), 10)
}

///|
test "morph_close fills a dark pinhole" {
  let img = gray_image(3, 3, [200, 200, 200, 200, 0, 200, 200, 200, 200])
  assert_eq(img.morph_close().get_pixel(1, 1).0.to_int(), 200)
}

///|
test "morphology leaves a flat field unchanged" {
  let img = solid(3, 3, 120, 130, 140, 255)
  assert_eq(img.dilate().get_pixel(1, 1).0.to_int(), 120)
  assert_eq(img.erode().get_pixel(1, 1).1.to_int(), 130)
  assert_eq(img.morph_open().get_pixel(1, 1).2.to_int(), 140)
}
