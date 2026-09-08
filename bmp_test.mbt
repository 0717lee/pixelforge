///|
/// BMP codec tests: exact header layout, padded-row sizing, 24/32-bit round
/// trips and malformed-input rejection.

///|
test "bmp_encode 24-bit header and padded size are exact" {
  // 3x2 at 24bpp: stride = 12 (9 data + 3 pad), total = 54 + 24 = 78.
  let img = solid(3, 2, 10, 20, 30, 255)
  let bytes = bmp_encode(img, false)
  assert_eq(bytes.length(), 78)
  assert_eq(bytes[0].to_int(), 66) // 'B'
  assert_eq(bytes[1].to_int(), 77) // 'M'
  assert_eq(bytes[28].to_int(), 24) // bpp
  // First stored pixel is bottom-left, BGR order.
  assert_eq(bytes[54].to_int(), 30)
  assert_eq(bytes[55].to_int(), 20)
  assert_eq(bytes[56].to_int(), 10)
}

///|
test "bmp round-trips 32-bit RGBA losslessly" {
  let img = @pixelforge.Image::new(5, 4)
  for y in 0..<4 {
    for x in 0..<5 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 50),
        @pixelforge.clamp_byte(y * 60),
        @pixelforge.clamp_byte(x * y * 13),
        @pixelforge.clamp_byte(40 + x + y),
      )
    }
  }
  let decoded = bmp_decode(bmp_encode(img, true)).unwrap()
  assert_eq(decoded.width, 5)
  assert_eq(decoded.height, 4)
  for i in 0..<(5 * 4 * 4) {
    assert_eq(decoded.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "bmp 24-bit round trip preserves color and forces opaque alpha" {
  let img = single(200, 100, 50, 77)
  let decoded = bmp_decode(bmp_encode(img, false)).unwrap()
  let (r, g, b, a) = decoded.get_pixel(0, 0)
  assert_eq(r.to_int(), 200)
  assert_eq(g.to_int(), 100)
  assert_eq(b.to_int(), 50)
  assert_eq(a.to_int(), 255) // alpha dropped by 24-bit encoding
}

///|
test "bmp_decode rejects malformed input" {
  assert_true(bmp_decode([]) is None)
  let junk : Array[Byte] = []
  for i in 0..<60 {
    junk.push((i % 250).to_byte())
  }
  assert_true(bmp_decode(junk) is None)
  // Truncated pixel data: keep the valid header, cut the payload short.
  let bytes = bmp_encode(solid(8, 8, 1, 2, 3, 255), true)
  let cut : Array[Byte] = []
  for i in 0..<60 {
    cut.push(bytes[i])
  }
  assert_true(bmp_decode(cut) is None)
}

///|
/// Header fields that are outside the supported uncompressed BMP subset must
/// be rejected before any pixel reads. Keep the payload from a valid file so
/// these cases exercise the parameter checks rather than truncation handling.
test "bmp_decode rejects unsupported parameters and dimensions" {
  let good = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)

  let bad_bpp = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)
  bad_bpp[28] = b'\x10' // 16-bit, outside the supported 24/32-bit subset.
  bad_bpp[29] = b'\x00'
  assert_true(bmp_decode(bad_bpp) is None)

  let bad_compression = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)
  bad_compression[30] = b'\x01' // BI_RLE8, unsupported by this decoder.
  assert_true(bmp_decode(bad_compression) is None)

  let bad_offset = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)
  bad_offset[10] = b'\x00'
  bad_offset[11] = b'\x00'
  bad_offset[12] = b'\x00'
  bad_offset[13] = b'\x00'
  assert_true(bmp_decode(bad_offset) is None)

  let zero_width = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)
  for i in 18..<22 {
    zero_width[i] = b'\x00'
  }
  assert_true(bmp_decode(zero_width) is None)

  let zero_height = bmp_encode(solid(2, 2, 1, 2, 3, 255), true)
  for i in 22..<26 {
    zero_height[i] = b'\x00'
  }
  assert_true(bmp_decode(zero_height) is None)

  // A valid top-down orientation with a negative height must remain accepted.
  let top_down = good
  top_down[22] = b'\xFE'
  top_down[23] = b'\xFF'
  top_down[24] = b'\xFF'
  top_down[25] = b'\xFF'
  assert_true(bmp_decode(top_down) is Some(_))
}
