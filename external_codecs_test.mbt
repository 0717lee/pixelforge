///|
fn external_codec_image() -> Image {
  let image = Image::new(2, 2)
  image.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  image.set_pixel(1, 0, b'\x00', b'\xFF', b'\x00', b'\xFF')
  image.set_pixel(0, 1, b'\x00', b'\x00', b'\xFF', b'\xFF')
  image.set_pixel(1, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image
}

///|
test "external jpeg adapter encodes and decodes rgba pixels" {
  let encoded = jpeg_encode(external_codec_image(), 90)
  assert_true(encoded.length() > 4)
  assert_eq(encoded[0], b'\xFF')
  assert_eq(encoded[1], b'\xD8')
  let decoded = jpeg_decode(encoded).unwrap()
  assert_eq((decoded.width, decoded.height), (2, 2))
}

///|
test "external webp adapter emits a riff webp container" {
  let encoded = webp_encode(external_codec_image())
  assert_true(encoded.length() > 16)
  assert_eq((encoded[0], encoded[1], encoded[2], encoded[3]), (b'R', b'I', b'F', b'F'))
  assert_eq((encoded[8], encoded[9], encoded[10], encoded[11]), (b'W', b'E', b'B', b'P'))
}
