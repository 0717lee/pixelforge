/// A real libaom 10-bit reduced-still sample with qindex zero.
test "10-bit qindex zero tile decodes" {
  let d : Array[Byte] = [b'\x12',b'\x00',b'\x0A',b'\x06',b'\x18',b'\x15',b'\x7F',b'\xFD',b'\xA8',b'\x08',b'\x32',b'\x0B',b'\x10',b'\x00',b'\x00',b'\x00',b'\x4B',b'\x18',b'\x0D',b'\xE4',b'\xBF',b'\xFF',b'\xA0']
  let image = av1_decode(d).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "12-bit qindex zero tile decodes" {
  let d : Array[Byte] = [b'\x12',b'\x00',b'\x0A',b'\x06',b'\x58',b'\x15',b'\x7F',b'\xFD',b'\xAC',b'\x61',b'\x32',b'\x0B',b'\x10',b'\x00',b'\x00',b'\x00',b'\x4B',b'\x17',b'\xDD',b'\x21',b'\x4B',b'\xFF',b'\xFA']
  let image = av1_decode(d).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "complex 10-bit residual stream is rejected safely" {
  let d : Array[Byte] = [b'\x12',b'\x00',b'\x0A',b'\x06',b'\x18',b'\x15',b'\x7F',b'\xFD',b'\xA8',b'\x08',b'\x32',b'\x0C',b'\x10',b'\x00',b'\x00',b'\x00',b'\x4B',b'\x17',b'\xC0',b'\xF1',b'\xB4',b'\xCB',b'\xFF',b'\xFA']
  assert_true(av1_decode(d) is None)
}
