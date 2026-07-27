///|
/// PNG codec black-box tests: exact encoded size, lossless round trips
/// (including the multi-block stored path) and malformed-input rejection.

///|
test "png_encode emits an exact, spec-shaped file for a 1x1 image" {
  // sig(8) + IHDR(25) + IDAT(12 + 2 zlib + 5 stored hdr + 5 raw + 4 adler)
  // + IEND(12) = 73 bytes.
  let img = single(10, 20, 30, 40)
  let bytes = png_encode(img)
  assert_eq(bytes.length(), 73)
  // Signature.
  let sig = [137, 80, 78, 71, 13, 10, 26, 10]
  for i in 0..<8 {
    assert_eq(bytes[i].to_int(), sig[i])
  }
  // IHDR payload: width = height = 1, depth 8, color type 6.
  assert_eq(bytes[19].to_int(), 1) // width LSB
  assert_eq(bytes[23].to_int(), 1) // height LSB
  assert_eq(bytes[24].to_int(), 8) // bit depth
  assert_eq(bytes[25].to_int(), 6) // color type RGBA
}

///|
test "png round-trips a varied RGBA image losslessly" {
  let img = @pixelforge.Image::new(6, 5)
  for y in 0..<5 {
    for x in 0..<6 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 43),
        @pixelforge.clamp_byte(y * 61),
        @pixelforge.clamp_byte(x * y * 19 + 7),
        @pixelforge.clamp_byte(255 - x * 9),
      )
    }
  }
  let decoded = png_decode(png_encode(img)).unwrap()
  assert_eq(decoded.width, 6)
  assert_eq(decoded.height, 5)
  for i in 0..<(6 * 5 * 4) {
    assert_eq(decoded.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "png round-trips a 128x128 image across multiple stored blocks" {
  // Raw scanline data = 128 * (1 + 512) = 65664 bytes > 65535, so the
  // encoder must split the zlib payload into two stored blocks.
  let img = @pixelforge.Image::new(128, 128)
  for y in 0..<128 {
    for x in 0..<128 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 2),
        @pixelforge.clamp_byte(y * 2),
        @pixelforge.clamp_byte((x + y) % 256),
        b'\xFF',
      )
    }
  }
  let decoded = png_decode(png_encode(img)).unwrap()
  for i in 0..<(128 * 128 * 4) {
    assert_eq(decoded.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "png_decode rejects malformed input" {
  assert_true(png_decode([]) is None)
  // Wrong signature.
  let junk : Array[Byte] = []
  for i in 0..<80 {
    junk.push((i % 251).to_byte())
  }
  assert_true(png_decode(junk) is None)
  let good = png_encode(solid(4, 4, 9, 8, 7, 255))
  // Truncated file.
  let cut : Array[Byte] = []
  for i in 0..<40 {
    cut.push(good[i])
  }
  assert_true(png_decode(cut) is None)
  // One corrupted byte inside the IDAT payload must break the chunk CRC.
  let bad : Array[Byte] = []
  for i in 0..<good.length() {
    bad.push(good[i])
  }
  bad[40] = (bad[40].to_int() ^ 255).to_byte()
  assert_true(png_decode(bad) is None)
}
