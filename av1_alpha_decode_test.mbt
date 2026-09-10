///|
test "monochrome alpha OBU reaches pure pixel decoder" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE',
    b'\x04', b'\x40', b'\x32', b'\x06', b'\x15', b'\x00', b'\x00', b'\x01',
    b'\x00', b'\x44',
  ]
  let alpha = av1_decode_alpha(stream).unwrap()
  assert_eq(alpha.length(), 4096)
  assert_eq(alpha[0], b'\x80')
  assert_eq(alpha[4095], b'\x80')
  assert_true(avif_decode_alpha([b'\x00']) is None)
}

