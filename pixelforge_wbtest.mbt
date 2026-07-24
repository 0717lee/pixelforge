///|
/// Whitebox smoke tests: exercise the pixel buffer layout and clamping helper
/// from inside the package so we validate the core API against the compiler
/// before layering filters on top.
test "image allocation and dimensions" {
  let img = Image::new(3, 2)
  assert_eq(img.width, 3)
  assert_eq(img.height, 2)
  assert_eq(img.pixel_count(), 6)
  assert_eq(img.data.length(), 3 * 2 * 4)
}

///|
test "set_pixel then get_pixel round-trips channels" {
  let img = Image::new(2, 2)
  img.set_pixel(1, 0, b'\x0A', b'\x14', b'\x1E', b'\xFF')
  let (r, g, b, a) = img.get_pixel(1, 0)
  assert_eq(r.to_int(), 10)
  assert_eq(g.to_int(), 20)
  assert_eq(b.to_int(), 30)
  assert_eq(a.to_int(), 255)
}

///|
test "clamp_byte saturates below, above, and passes through inside range" {
  assert_eq(clamp_byte(-5).to_int(), 0)
  assert_eq(clamp_byte(300).to_int(), 255)
  assert_eq(clamp_byte(128).to_int(), 128)
}
