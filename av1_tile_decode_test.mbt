///|
test "av1 decodes a real all-zero DC tile to neutral gray" {
  let sequence = av1_sequence_info([b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08']).unwrap()
  let header = av1_parse_stage1_frame([b'\x12', b'\xB0', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00', b'\x2E'], sequence).unwrap()
  assert_eq((header.header_bytes, header.base_q_idx), (8, 43))
  let tile : Array[Byte] = [b'\x2E']
  let image = av1_decode_dc_tile(64, 64, tile, 43).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "av1 decodes the reference flat reduced-still stream end to end" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00',
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
    b'\x32', b'\x09', b'\x12', b'\xB0', b'\x00', b'\x00', b'\x40', b'\x00',
    b'\x00', b'\x00', b'\x2E',
  ]
  let image = av1_decode(stream).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}
