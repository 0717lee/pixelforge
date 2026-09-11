/// A real libaom 10-bit reduced-still sample with qindex zero.
test "10-bit qindex zero tile decodes" {
  let d : Array[Byte] = [b'\x12',b'\x00',b'\x0A',b'\x06',b'\x18',b'\x15',b'\x7F',b'\xFD',b'\xA8',b'\x08',b'\x32',b'\x0B',b'\x10',b'\x00',b'\x00',b'\x00',b'\x4B',b'\x18',b'\x0D',b'\xE4',b'\xBF',b'\xFF',b'\xA0']
  let image = av1_decode(d).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}
