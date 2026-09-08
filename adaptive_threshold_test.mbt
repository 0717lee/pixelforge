///|
/// Local adaptive threshold tests use small hand-computable luma patterns so
/// edge clipping and the alpha invariant remain observable.

///|
test "sauvola uses clipped windows and preserves alpha" {
  let img = @pixelforge.Image::new(5, 1)
  let values = [20, 20, 200, 200, 200]
  for x in 0..<5 {
    let v = @pixelforge.clamp_byte(values[x])
    img.set_pixel(x, 0, v, v, v, if x == 0 { b'\x2A' } else { b'\xFF' })
  }
  // k=0 makes Sauvola equal the local mean, avoiding floating-point
  // sensitivity while still exercising the radius-one edge windows.
  let out = img.sauvola(1, 0.0, 128)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(1, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(2, 0).0.to_int(), 255)
  assert_eq(out.get_pixel(4, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(0, 0).3.to_int(), 42)
}

///|
test "sauvola keeps a flat field in one class" {
  let img = @pixelforge.Image::new(3, 2)
  for y in 0..<2 {
    for x in 0..<3 {
      img.set_pixel(x, y, b'\x80', b'\x80', b'\x80', b'\xA5')
    }
  }
  // With k=0 the threshold is exactly the flat-field mean, so strict
  // foreground comparison puts every equal pixel in the background class.
  let out = img.sauvola(1, 0.0, 128)
  for y in 0..<2 {
    for x in 0..<3 {
      assert_eq(out.get_pixel(x, y).0.to_int(), 0)
      assert_eq(out.get_pixel(x, y).3.to_int(), 165)
    }
  }
}

///|
test "sauvola handles a single pixel and invalid parameters" {
  let img = @pixelforge.Image::new(1, 1)
  img.set_pixel(0, 0, b'\x64', b'\x64', b'\x64', b'\x7B')
  // Negative radius, k above one, and zero dynamic range are normalized.
  let out = img.sauvola(-3, 4.0, 0)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 255)
  assert_eq(out.get_pixel(0, 0).1.to_int(), 255)
  assert_eq(out.get_pixel(0, 0).2.to_int(), 255)
  assert_eq(out.get_pixel(0, 0).3.to_int(), 123)
}

///|
test "adaptive mean threshold separates a local bright run" {
  let img = @pixelforge.Image::new(5, 1)
  let values = [20, 20, 200, 200, 200]
  for x in 0..<5 {
    let v = @pixelforge.clamp_byte(values[x])
    img.set_pixel(x, 0, v, v, v, b'\xFF')
  }
  let out = img.adaptive_mean(1, 0)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(1, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(2, 0).0.to_int(), 255)
  assert_eq(out.get_pixel(3, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(4, 0).0.to_int(), 0)
}
