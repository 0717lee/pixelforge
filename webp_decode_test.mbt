///|
fn webp_decode_test_image() -> Image {
  let image = Image::new(7, 3)
  for y in 0..<3 {
    for x in 0..<7 {
      let i = x + y * 7
      image.set_pixel(
        x,
        y,
        ((i * 37 + 11) % 256).to_byte(),
        ((i * 71 + 29) % 256).to_byte(),
        ((i * 19 + 101) % 256).to_byte(),
        if i % 4 == 0 { b'\x80' } else { b'\xFF' },
      )
    }
  }
  image
}

///|
test "webp_decode round-trips the lossless external encoder" {
  let source = webp_decode_test_image()
  let encoded = webp_encode(source)
  let decoded = webp_decode(encoded).unwrap()
  assert_eq((decoded.width, decoded.height), (source.width, source.height))
  for i in 0..<source.data.length() {
    assert_eq(decoded.data[i], source.data[i])
  }
}

///|
test "webp_decode round-trips color-cache friendly pixels" {
  let source = Image::new(32, 8)
  for y in 0..<source.height {
    for x in 0..<source.width {
      if (x + y) % 3 == 0 {
        source.set_pixel(x, y, b'\x12', b'\xA0', b'\xF0', b'\xFF')
      } else {
        source.set_pixel(x, y, b'\x12', b'\xA0', b'\xF0', b'\xFF')
      }
    }
  }
  let encoded = webp_encode(source)
  let decoded = webp_decode(encoded).unwrap()
  assert_eq(decoded.data, source.data)
}

///|
test "webp_decode rejects non-lossless and truncated containers" {
  let source = webp_decode_test_image()
  let encoded = webp_encode(source)
  let truncated : Array[Byte] = []
  for i in 0..<(encoded.length() - 1) { truncated.push(encoded[i]) }
  assert_true(webp_decode(truncated) is None)
  let bad = encoded.copy()
  bad[12] = b'V'
  bad[13] = b'P'
  bad[14] = b'8'
  bad[15] = b' '
  assert_true(webp_decode(bad) is None)
}
