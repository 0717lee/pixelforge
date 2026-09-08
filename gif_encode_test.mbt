///|
test "gif_encode round-trips opaque and transparent pixels" {
  let img = @pixelforge.Image::new(2, 1)
  img.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  img.set_pixel(1, 0, b'\x00', b'\x00', b'\x00', b'\x00')
  let encoded = @pixelforge.gif_encode(img)
  let decoded = @pixelforge.gif_decode(encoded).unwrap()
  assert_eq(decoded.width, 2)
  assert_eq(decoded.height, 1)
  assert_eq(decoded.get_pixel(0, 0).0.to_int(), 255)
  assert_eq(decoded.get_pixel(0, 0).3.to_int(), 255)
  assert_eq(decoded.get_pixel(1, 0).3.to_int(), 0)
}
