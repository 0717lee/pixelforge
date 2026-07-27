///|
/// Tests for gamma, vignette and Scharr.

///|
test "gamma 1.0 is an identity" {
  let (r, g, b, a) = single(123, 45, 6, 200).gamma(1.0).get_pixel(0, 0)
  assert_eq(r.to_int(), 123)
  assert_eq(g.to_int(), 45)
  assert_eq(b.to_int(), 6)
  assert_eq(a.to_int(), 200)
}

///|
test "gamma 2.0 lifts midtones and keeps the endpoints" {
  // 255 * sqrt(64/255) = 127.75 -> rounds to 128.
  let out = single(64, 0, 255, 255).gamma(2.0)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 128)
  assert_eq(out.get_pixel(0, 0).1.to_int(), 0)
  assert_eq(out.get_pixel(0, 0).2.to_int(), 255)
}

///|
test "vignette keeps the center and darkens corners by strength" {
  let out = solid(3, 3, 200, 200, 200, 255).vignette(0.5)
  // Center: distance 0 -> unchanged.
  assert_eq(out.get_pixel(1, 1).0.to_int(), 200)
  // Corner: d2 == max_d2 -> factor 0.5 -> 100.
  assert_eq(out.get_pixel(0, 0).0.to_int(), 100)
}

///|
test "scharr finds no edge in a flat field" {
  assert_eq(solid(3, 3, 90, 90, 90, 255).scharr().get_pixel(1, 1).0.to_int(), 0)
}

///|
test "scharr lights up a vertical edge" {
  // Gx = 255 * (3 + 10 + 3) = 4080 -> clamps to 255.
  let img = gray_image(3, 3, [0, 0, 255, 0, 0, 255, 0, 0, 255])
  assert_eq(img.scharr().get_pixel(1, 1).0.to_int(), 255)
}
