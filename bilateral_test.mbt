///|
/// Bilateral filter tests: identity, flat-field invariance, edge
/// preservation compared against a plain Gaussian, and noise smoothing
/// inside a flat region.

///|
test "bilateral(0) is an exact copy" {
  let img = gray_image(4, 1, [10, 200, 30, 90])
  let out = img.bilateral(0, 2.0, 30.0)
  for i in 0..<(4 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "bilateral keeps a flat field unchanged" {
  // All range differences are zero, so this reduces to a normalized
  // spatial average of a constant: exactly the constant.
  let img = solid(8, 6, 120, 60, 200, 255)
  let out = img.bilateral(3, 2.0, 20.0)
  for y in 0..<6 {
    for x in 0..<8 {
      let (r, g, b, a) = out.get_pixel(x, y)
      assert_eq(r.to_int(), 120)
      assert_eq(g.to_int(), 60)
      assert_eq(b.to_int(), 200)
      assert_eq(a.to_int(), 255)
    }
  }
}

///|
test "bilateral preserves a step edge that gaussian smears" {
  // Left half 0, right half 250 (16x8). With a tight range sigma the
  // bilateral output must stay within a few steps of the original at the
  // columns adjacent to the edge, while the same-radius gaussian moves
  // them far toward the middle.
  let img = @pixelforge.Image::new(16, 8)
  for y in 0..<8 {
    for x in 0..<16 {
      let v : Byte = if x < 8 { b'\x00' } else { b'\xFA' }
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let bi = img.bilateral(2, 2.0, 10.0)
  let ga = img.gaussian(2)
  let bi_left = bi.get_pixel(7, 4).0.to_int()
  let bi_right = bi.get_pixel(8, 4).0.to_int()
  let ga_left = ga.get_pixel(7, 4).0.to_int()
  // Bilateral: edge-adjacent pixels barely move.
  assert_true(bi_left <= 5)
  assert_true(bi_right >= 245)
  // Gaussian: the same pixel is dragged well toward the middle.
  assert_true(ga_left >= 60)
}

///|
test "bilateral smooths small noise inside a flat region" {
  // A 90-vs-100 speck is within the range sigma, so it must be pulled
  // toward its neighborhood average.
  let img = solid(9, 9, 100, 100, 100, 255)
  img.set_pixel(4, 4, b'\x5A', b'\x5A', b'\x5A', b'\xFF') // 90
  let out = img.bilateral(2, 2.0, 40.0)
  let v = out.get_pixel(4, 4).0.to_int()
  assert_true(v > 90 && v <= 100)
}
