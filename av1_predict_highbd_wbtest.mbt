///|
test "highbd yuv conversion validates endpoints and dimensions" {
  let black = av1_yuv420_highbd_to_rgba(
    2,
    2,
    [0, 0, 0, 0],
    [128],
    [128],
    8,
    full_range=true,
  ).unwrap()
  assert_eq(black.get_pixel(0, 0), (b'\x00', b'\x00', b'\x00', b'\xFF'))
  let white = av1_yuv420_highbd_to_rgba(
    2,
    2,
    [1023, 1023, 1023, 1023],
    [512],
    [512],
    10,
    full_range=true,
  ).unwrap()
  assert_eq(white.get_pixel(1, 1), (b'\xFF', b'\xFF', b'\xFF', b'\xFF'))
  assert_true(av1_yuv420_highbd_to_rgba(2, 2, [], [], [], 13) is None)
}
