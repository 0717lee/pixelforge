/// A real libaom 10-bit reduced-still OBU stream (64x64, yuv420p10le).
/// The source was encoded as a constant limited-range gray frame and decoded
/// with libdav1d to Y=504, U=512, V=512.  This verifies the complete coded
/// sample path rather than only synthetic neutral entropy bytes.
test "external libaom 10-bit constant sample" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD',
    b'\xA8', b'\x08', b'\x32', b'\x0B', b'\x10', b'\x00', b'\x00', b'\x00',
    b'\x4B', b'\x18', b'\x0D', b'\xE4', b'\xBF', b'\xFF', b'\xA0',
  ]
  let sequence = av1_sequence_info(stream).unwrap()
  assert_eq(sequence.bit_depth, 10)
  let image = av1_decode(stream).unwrap()
  // 10-bit limited-range Y=504 is exactly 8-bit Y=126; BT.601 conversion
  // yields the same neutral RGB value as libdav1d's 10-bit output.
  assert_eq(image.get_pixel(0, 0), (b'\x80', b'\x80', b'\x80', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x80', b'\x80', b'\x80', b'\xFF'))
}
