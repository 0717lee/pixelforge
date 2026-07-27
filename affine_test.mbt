///|
/// Affine transform tests: exact matrix algebra checks plus image-level
/// invariants (identity, integer translation, 90-degree parity with
/// rotate90, fractional blending).

///|
test "affine constructors map points as documented" {
  let (tx, ty) = @pixelforge.Affine::translation(3.0, -2.0).apply(1.0, 1.0)
  assert_eq(tx, 4.0)
  assert_eq(ty, -1.0)
  let (sx, sy) = @pixelforge.Affine::scaling(2.0, 3.0).apply(4.0, 5.0)
  assert_eq(sx, 8.0)
  assert_eq(sy, 15.0)
  let (hx, hy) = @pixelforge.Affine::shear(0.5, 0.0).apply(2.0, 4.0)
  assert_eq(hx, 4.0) // x + 0.5*y
  assert_eq(hy, 4.0)
}

///|
test "affine composition and inverse round-trip a point" {
  let t = @pixelforge.Affine::rotation(30.0)
    .then(@pixelforge.Affine::translation(5.0, -7.0))
    .then(@pixelforge.Affine::scaling(2.0, 0.5))
  let (fx, fy) = t.apply(3.0, 4.0)
  let (bx, by) = t.invert().unwrap().apply(fx, fy)
  assert_true((bx - 3.0) * (bx - 3.0) < 1.0e-18)
  assert_true((by - 4.0) * (by - 4.0) < 1.0e-18)
  // A collapsed axis is not invertible.
  assert_true(@pixelforge.Affine::scaling(0.0, 1.0).invert() is None)
}

///|
test "identity affine copies the image exactly" {
  let img = gray_image(4, 2, [10, 60, 110, 160, 210, 240, 5, 90])
  let out = img.affine(@pixelforge.Affine::identity())
  for i in 0..<(4 * 2 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "integer translation shifts pixels exactly and vacates transparently" {
  let img = solid(4, 3, 50, 100, 150, 255)
  let out = img.translate(2.0, 1.0)
  // Shifted region: exact copy.
  let (r, g, b, a) = out.get_pixel(3, 2)
  assert_eq(r.to_int(), 50)
  assert_eq(g.to_int(), 100)
  assert_eq(b.to_int(), 150)
  assert_eq(a.to_int(), 255)
  // Vacated top row and left columns: fully transparent.
  assert_eq(out.get_pixel(0, 0).3.to_int(), 0)
  assert_eq(out.get_pixel(1, 2).3.to_int(), 0)
  assert_eq(out.get_pixel(3, 0).3.to_int(), 0)
}

///|
test "rotate(90) matches rotate90 on a square image" {
  let img = @pixelforge.Image::new(5, 5)
  for y in 0..<5 {
    for x in 0..<5 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 40),
        @pixelforge.clamp_byte(y * 40),
        @pixelforge.clamp_byte((x + y) * 20),
        b'\xFF',
      )
    }
  }
  let by_affine = img.rotate(90.0)
  let by_exact = img.rotate90()
  for i in 0..<(5 * 5 * 4) {
    assert_eq(by_affine.data[i].to_int(), by_exact.data[i].to_int())
  }
}

///|
test "half-pixel translation blends neighbors equally" {
  // Row [0, 100]: shifting right by 0.5 samples x=1 from source x=0.5,
  // the exact midpoint => (0 + 100) / 2 = 50.
  let img = gray_image(2, 1, [0, 100])
  let out = img.translate(0.5, 0.0)
  assert_eq(out.get_pixel(1, 0).0.to_int(), 50)
}
