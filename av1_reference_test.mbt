///|
/// External libaom OBU fixtures. Expected planes are independently decoded
/// with libdav1d and recorded in tests/fixtures/av1/manifest.json.
fn av1_reference_constant(y : Byte, u : Byte, v : Byte) -> Image {
  av1_yuv420_to_rgba_color(
    64,
    64,
    Array::make(4096, y),
    Array::make(1024, u),
    Array::make(1024, v),
  ).unwrap()
}

///|
test "external libaom dc_zero_q30" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x06', b'\x17', b'\x80', b'\x00', b'\x00', b'\x40', b'\x2E',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\x80', b'\x80', b'\x80')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom dc_y_low_q10" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x0A', b'\x12', b'\x80', b'\x00', b'\x00', b'\x40', b'\x00',
    b'\xEB', b'\xC8', b'\xE2', b'\x40',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\x40', b'\x80', b'\x80')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom dc_y_high_q50" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x09', b'\x1C', b'\x80', b'\x00', b'\x00', b'\x40', b'\x0A',
    b'\x01', b'\x99', b'\x88',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\xC0', b'\x80', b'\x80')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom dc_u_low_q10" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x0A', b'\x12', b'\x80', b'\x00', b'\x00', b'\x40', b'\x29',
    b'\x02', b'\xEA', b'\x15', b'\x78',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\x80', b'\x40', b'\x80')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom dc_v_high_q30" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x0A', b'\x17', b'\x80', b'\x00', b'\x00', b'\x40', b'\x2D',
    b'\x2C', b'\x06', b'\x74', b'\xC0',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\x80', b'\x80', b'\xC0')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom dc_yuv_mixed_q50" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x0E', b'\x1C', b'\x80', b'\x00', b'\x00', b'\x40', b'\x0A',
    b'\x05', b'\xAE', b'\x32', b'\xEA', b'\xB4', b'\x04', b'\xDD', b'\x60',
  ]
  let actual = av1_decode(stream).unwrap()
  let expected = av1_reference_constant(b'\x60', b'\xA0', b'\x40')
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
test "external libaom AC cosine luma" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x00',
    b'\x08', b'\x32', b'\x0A', b'\x45', b'\xE0', b'\x00', b'\x00', b'\x10', b'\x05',
    b'\x39', b'\xA3', b'\x7B', b'\x80',
  ]
  let actual = av1_decode(stream).unwrap()
  let row : Array[Byte] = [
    b'\x8A', b'\x8A', b'\x8A', b'\x8A', b'\x8A', b'\x8A', b'\x8A', b'\x89', b'\x89',
    b'\x89', b'\x89', b'\x89', b'\x88', b'\x88', b'\x88', b'\x87', b'\x87', b'\x87',
    b'\x86', b'\x86', b'\x85', b'\x85', b'\x85', b'\x84', b'\x84', b'\x83', b'\x83',
    b'\x82', b'\x82', b'\x81', b'\x81', b'\x80', b'\x80', b'\x7F', b'\x7F', b'\x7E',
    b'\x7E', b'\x7D', b'\x7D', b'\x7C', b'\x7C', b'\x7C', b'\x7B', b'\x7B', b'\x7A',
    b'\x7A', b'\x79', b'\x79', b'\x79', b'\x78', b'\x78', b'\x78', b'\x78', b'\x77',
    b'\x77', b'\x77', b'\x77', b'\x76', b'\x76', b'\x76', b'\x76', b'\x76', b'\x76',
    b'\x76',
  ]
  let y_plane : Array[Byte] = []
  for _ in 0..<64 {
    for value in row {
      y_plane.push(value)
    }
  }
  let expected = av1_yuv420_to_rgba_color(
    64,
    64,
    y_plane,
    Array::make(1024, b'\x80'),
    Array::make(1024, b'\x80'),
  ).unwrap()
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(actual.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}
