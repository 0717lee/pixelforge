///|
/// PNG codec black-box tests: compact fixed-Huffman output, lossless round
/// trips and malformed-input rejection.

///|
test "png_encode emits a compact, spec-shaped file for a 1x1 image" {
  let img = single(10, 20, 30, 40)
  let bytes = png_encode(img)
  // The encoder emits a spec-valid compact scanline stream.
  assert_true(bytes.length() <= 73)
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
test "png round-trips a 128x128 image through fixed Huffman coding" {
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

///|
/// Chunk framing and required-stream checks must fail closed even when the
/// signature and most of the encoded image are otherwise valid.
test "png_decode rejects missing chunks and invalid IHDR bounds" {
  let good = png_encode(solid(2, 2, 9, 8, 7, 255))

  // A complete signature without an IHDR is not a PNG image.
  let signature_only : Array[Byte] = []
  for i in 0..<8 {
    signature_only.push(good[i])
  }
  assert_true(png_decode(signature_only) is None)

  // Remove the terminal IEND chunk while preserving all preceding bytes.
  let no_iend : Array[Byte] = []
  for i in 0..<(good.length() - 12) {
    no_iend.push(good[i])
  }
  assert_true(png_decode(no_iend) is None)

  // An oversized chunk length must be rejected before indexing its CRC.
  let oversized = png_encode(solid(1, 1, 1, 2, 3, 255))
  oversized[8] = b'\x00'
  oversized[9] = b'\x00'
  oversized[10] = b'\x03'
  oversized[11] = b'\xE8' // 1000-byte IHDR payload, beyond this file.
  assert_true(png_decode(oversized) is None)

  // Zero dimensions are invalid even though the chunk bytes remain present.
  let zero_dimension = png_encode(solid(1, 1, 1, 2, 3, 255))
  for i in 16..<24 {
    zero_dimension[i] = b'\x00'
  }
  assert_true(png_decode(zero_dimension) is None)
}

///|
/// Tiny hand-built stored-DEFLATE PNGs exercise the non-RGBA color types.
test "png_decode expands grayscale and grayscale-alpha" {
  let gray : Array[Byte] = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 0, 0, 0, 0, 58, 126, 155, 85,
    0, 0, 0, 13, 73, 68, 65, 84, 120, 1, 1, 2, 0, 253, 255, 0, 77,
    0, 79, 0, 78, 64, 71, 211, 184, 0, 0, 0, 0, 73, 69, 78, 68, 174,
    66, 96, 130,
  ]
  let g = png_decode(gray).unwrap()
  assert_eq(g.get_pixel(0, 0), (b'M', b'M', b'M', b'\xFF'))
  let ga : Array[Byte] = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 4, 0, 0, 0, 181, 28, 12, 2,
    0, 0, 0, 14, 73, 68, 65, 84, 120, 1, 1, 3, 0, 252, 255, 0, 88,
    123, 1, 46, 0, 212, 186, 72, 42, 55, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
  ]
  let ga_img = png_decode(ga).unwrap()
  assert_eq(ga_img.get_pixel(0, 0), (b'X', b'X', b'X', b'{'))
}

///|
test "png_decode expands indexed palette and tRNS" {
  let indexed : Array[Byte] = [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 3, 0, 0, 0, 40, 203, 52, 187,
    0, 0, 0, 6, 80, 76, 84, 69, 10, 20, 30, 200, 150, 100, 211, 34,
    196, 98, 0, 0, 0, 2, 116, 82, 78, 83, 255, 64, 147, 107, 113, 218,
    0, 0, 0, 13, 73, 68, 65, 84, 120, 1, 1, 2, 0, 253, 255, 0, 1,
    0, 3, 0, 2, 219, 174, 31, 239, 0, 0, 0, 0, 73, 69, 78, 68, 174,
    66, 96, 130,
  ]
  let img = png_decode(indexed).unwrap()
  assert_eq(img.get_pixel(0, 0), (b'\xC8', b'\x96', b'd', b'\x40'))
}
