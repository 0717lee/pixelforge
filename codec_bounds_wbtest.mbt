///|
fn bounds_u32(data : Array[Byte], p : Int, value : Int, little : Bool) -> Unit {
  for i in 0..<4 {
    data[p + (if little { i } else { 3 - i })] = ((value >> (i * 8)) & 255).to_byte()
  }
}

///|
fn bounds_png_crc(data : Array[Byte]) -> Unit {
  bounds_u32(data, 29, crc32(data, 12, 29).to_int(), false)
}

///|
test "codec dimensions cannot wrap the pixel allocation limit" {
  let image = Image::new(1, 1)
  let qoi = qoi_encode(image)
  bounds_u32(qoi, 4, 65536, false)
  bounds_u32(qoi, 8, 65536, false)
  assert_true(qoi_decode(qoi) is None)
  let bmp = bmp_encode(image, true)
  bounds_u32(bmp, 18, 65536, true)
  bounds_u32(bmp, 22, 65536, true)
  assert_true(bmp_decode(bmp) is None)
  let png = png_encode(image)
  bounds_u32(png, 16, 65536, false)
  bounds_u32(png, 20, 65536, false)
  bounds_png_crc(png)
  assert_true(png_decode(png) is None)
  let gif = gif_encode(image)
  for i in 0..<(gif.length() - 9) {
    if gif[i] == b'\x2C' {
      for k in 5..<9 {
        gif[i + k] = b'\xFF'
      }
      break
    }
  }
  assert_true(gif_decode(gif) is None)
  assert_true(gif_decode_all(gif) is None)
}

///|
test "BMP validates planes DIB bounds and pixel offset" {
  let source = bmp_encode(Image::new(1, 1), true)
  for (p, value) in [(14, 2147483647), (14, 56), (10, 2147483647), (26, 0)] {
    let data = source.copy()
    bounds_u32(data, p, value, true)
    assert_true(bmp_decode(data) is None)
  }
}

///|
test "QOI validates end marker colorspace and complete run consumption" {
  let source = qoi_encode(Image::new(1, 1))
  for p in [13, source.length() - 1] {
    let data = source.copy()
    data[p] = b'\x02'
    assert_true(qoi_decode(data) is None)
  }
  let run = Array::makei(14, i => source[i])
  run.push(b'\xC1') // two pixels in a one-pixel image
  for i in 0..<8 {
    run.push(if i == 7 { b'\x01' } else { b'\x00' })
  }
  assert_true(qoi_decode(run) is None)
  run[14] = b'\xC0'
  assert_true(qoi_decode(run) is Some(_))
}

///|
test "PNG rejects overflowing chunk lengths before CRC indexing" {
  let data = png_encode(Image::new(1, 1))
  bounds_u32(data, 8, 2147483647, false)
  assert_true(png_decode(data) is None)
}

///|
test "PNG rejects unsupported IHDR methods even with valid CRC" {
  for p in [26, 27] {
    let data = png_encode(Image::new(1, 1))
    data[p] = b'\x01'
    bounds_png_crc(data)
    assert_true(png_decode(data) is None)
  }
}

///|
test "PNG distinguishes critical chunks and enforces IDAT order" {
  let source = png_encode(Image::new(1, 1))
  for critical in [false, true] {
    let data = Array::makei(33, i => source[i])
    push_chunk(data, [if critical { 65 } else { 97 }, 98, 67, 100], [])
    for i in 33..<source.length() {
      data.push(source[i])
    }
    assert_eq(png_decode(data) is Some(_), !critical)
  }
  let data = Array::makei(source.length() - 12, i => source[i])
  push_chunk(data, [97, 98, 67, 100], [])
  push_chunk(data, [73, 68, 65, 84], [])
  push_chunk(data, [73, 69, 78, 68], [])
  assert_true(png_decode(data) is None)
  let bad_end = Array::makei(source.length() - 12, i => source[i])
  push_chunk(bad_end, [73, 69, 78, 68], [b'\x00'])
  assert_true(png_decode(bad_end) is None)
}

///|
test "zlib bounds stored blocks and length distance expansion" {
  // A stored stream for 'a' and a fixed-Huffman stream for 'aaaaaa'.
  let stored : Array[Byte] = [
    b'\x78', b'\x01', b'\x01', b'\x01', b'\x00', b'\xFE', b'\xFF', b'a', b'\x00',
    b'\x62', b'\x00', b'\x62',
  ]
  let repeated : Array[Byte] = [
    b'\x78', b'\x01', b'\x4B', b'\x04', b'\x03', b'\x00', b'\x07', b'\xFB', b'\x02',
    b'\x47',
  ]
  for (data, expected) in [(stored, 1), (repeated, 6)] {
    assert_true(
      zlib_inflate(data, 0, data.length(), max_output=expected) is Some(_),
    )
    assert_true(
      zlib_inflate(data, 0, data.length(), max_output=expected - 1) is None,
    )
    assert_true(zlib_inflate(data, -1, data.length()) is None)
    assert_true(zlib_inflate(data, 0, data.length() + 1) is None)
  }
}

///|
test "metadata rejects invalid dimensions and truncated JPEG segments" {
  let png = png_encode(Image::new(1, 1))
  bounds_u32(png, 16, 0, false)
  assert_true(image_metadata(png) is None)
  let jpeg : Array[Byte] = [
    b'\xFF', b'\xD8', b'\xFF', b'\xC0', b'\x00', b'\x0B', b'\x08', b'\x00', b'\x02',
    b'\x00', b'\x03', b'\x01', b'\x01', b'\x11', b'\x00',
  ]
  assert_eq(image_metadata(jpeg).unwrap().width, 3)
  for n in 2..<jpeg.length() {
    assert_true(image_metadata(Array::makei(n, i => jpeg[i])) is None)
  }
}
