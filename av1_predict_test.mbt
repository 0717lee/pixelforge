///|
test "av1 yuv420 reconstruction converts neutral black and white" {
  let black = av1_yuv420_to_rgba(2, 2, [b'\x10', b'\x10', b'\x10', b'\x10'], [b'\x80'], [b'\x80']).unwrap()
  assert_eq(black.get_pixel(0, 0), (b'\x00', b'\x00', b'\x00', b'\xFF'))
  let white = av1_yuv420_to_rgba(2, 2, [b'\xEB', b'\xEB', b'\xEB', b'\xEB'], [b'\x80'], [b'\x80']).unwrap()
  assert_eq(white.get_pixel(1, 1), (b'\xFF', b'\xFF', b'\xFF', b'\xFF'))
}

///|
test "av1 yuv420 reconstruction rejects malformed planes" {
  assert_true(av1_yuv420_to_rgba(2, 2, [b'\x10'], [b'\x80'], [b'\x80']) is None)
  assert_true(av1_yuv420_to_rgba(3, 2, [], [], []) is None)
}
