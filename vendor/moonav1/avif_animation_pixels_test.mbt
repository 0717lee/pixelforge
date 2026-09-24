///|
test "animation samples decode in descriptor order" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00',
    b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46',
    b'\x02', b'\x28',
  ]
  let result = avif_decode_animation_samples(1000, [0, 10], [10, 10], [
    sample, sample,
  ]).unwrap()
  assert_eq(result.frames.length(), 2)
  assert_eq(result.frames[1].timestamp, 10)
  assert_eq(result.frames[0].image.get_pixel(0, 0).3, b'\xFF')
  assert_true(avif_animation_frame_at(result, 0) is Some(_))
  assert_true(avif_animation_frame_at(result, 25) is Some(_))
  assert_true(avif_animation_frame_at(result, -1) is None)
}
