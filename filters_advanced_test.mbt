///|
/// Deterministic tests for the advanced filters. Reuses the `single`, `solid`
/// and `gray_image` fixtures defined in the other blackbox test files.

///|
test "sepia applies the warm-tone matrix and keeps alpha" {
  // r=(393*100+769*150+189*200)/1000=192, g=171, b=133
  let (r, g, b, a) = single(100, 150, 200, 255).sepia().get_pixel(0, 0)
  assert_eq(r.to_int(), 192)
  assert_eq(g.to_int(), 171)
  assert_eq(b.to_int(), 133)
  assert_eq(a.to_int(), 255)
}

///|
test "threshold splits pixels at the luma level" {
  // luma(100,150,200) = 140 >= 128 -> white
  let (bright, _, _, _) = single(100, 150, 200, 255)
    .threshold(128)
    .get_pixel(0, 0)
  assert_eq(bright.to_int(), 255)
  // luma(10,10,10) = 10 < 128 -> black
  let (dark, _, _, _) = single(10, 10, 10, 255).threshold(128).get_pixel(0, 0)
  assert_eq(dark.to_int(), 0)
}

///|
test "pixelate averages a block into one color" {
  // One 2-wide block over [0, 100] -> (0+100)/2 = 50 for both cells.
  let out = gray_image(2, 1, [0, 100]).pixelate(2)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 50)
  assert_eq(out.get_pixel(1, 0).0.to_int(), 50)
}

///|
test "pixelate leaves a flat field unchanged" {
  let (r, g, b, _) = solid(3, 3, 120, 60, 30, 255).pixelate(2).get_pixel(0, 0)
  assert_eq(r.to_int(), 120)
  assert_eq(g.to_int(), 60)
  assert_eq(b.to_int(), 30)
}

///|
test "median removes a salt-and-pepper spike" {
  // Center 250 surrounded by 10s: median of the 3x3 window is 10.
  let img = gray_image(3, 3, [10, 10, 10, 10, 250, 10, 10, 10, 10])
  assert_eq(img.median().get_pixel(1, 1).0.to_int(), 10)
}

///|
test "median leaves a flat field unchanged" {
  assert_eq(
    solid(3, 3, 77, 77, 77, 255).median().get_pixel(1, 1).0.to_int(),
    77,
  )
}

///|
test "histogram equalization stretches the tonal range to full black/white" {
  // Lumas {50,50,200}: cdf_min=2, denom=1 -> 50 maps to 0, 200 maps to 255.
  let eq = gray_image(3, 1, [50, 50, 200]).histogram_equalize()
  assert_eq(eq.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(eq.get_pixel(2, 0).0.to_int(), 255)
}
