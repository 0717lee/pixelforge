///|
test "monochrome alpha OBU reaches pure pixel decoder" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE', b'\x04',
    b'\x40', b'\x32', b'\x06', b'\x15', b'\x00', b'\x00', b'\x01', b'\x00', b'\x44',
  ]
  let alpha = av1_decode_alpha(stream).unwrap()
  assert_eq(alpha.length(), 4096)
  assert_eq(alpha[0], b'\x80')
  assert_eq(alpha[4095], b'\x80')
  assert_true(avif_decode_alpha([b'\x00']) is None)
  assert_true(avif_decode_rgba([b'\x00']) is None)
  let rgb = Image::new(2, 2)
  rgb.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\xFF')
  let composed = av1_apply_alpha(rgb, [b'\x00', b'\x7F', b'\xFF', b'\x40']).unwrap()
  assert_eq(composed.get_pixel(0, 0), (b'\x10', b'\x20', b'\x30', b'\x00'))
  assert_eq(composed.get_pixel(1, 0).3, b'\x7F')
}
