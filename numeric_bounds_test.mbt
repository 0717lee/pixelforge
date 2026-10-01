///|
test "pixelate accepts maximal block size on a small image" {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\x40')
  image.set_pixel(1, 0, b'\x64', b'\x64', b'\x64', b'\xFF')
  let output = image.pixelate(2147483647)
  assert_eq(output.get_pixel(0, 0), (b'\x32', b'\x32', b'\x32', b'\x40'))
  assert_eq(output.get_pixel(1, 0).3, b'\xFF')
}

///|
test "large image averages and histogram normalization do not wrap" {
  let n = 8500000
  let image = @pixelforge.Image::from_bytes(
    n,
    1,
    FixedArray::make(n * 4, b'\xFF'),
  )
  image.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  let equalized = image.histogram_equalize()
  assert_eq(equalized.get_pixel(n - 1, 0).0, b'\xFF')
  assert_eq(equalized.get_pixel(0, 0).0, b'\x00')
  let average = image.pixelate(n)
  assert_eq(average.get_pixel(n - 1, 0).0, b'\xFE')
}

///|
test "long distance gradients normalize their far endpoint to white" {
  let n = 3000000
  let image = @pixelforge.Image::from_bytes(
    n,
    1,
    FixedArray::make(n * 4, b'\xFF'),
  )
  image.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  let output = image.distance_transform(128)
  assert_eq(output.get_pixel(0, 0).0, b'\x00')
  assert_eq(output.get_pixel(n - 1, 0).0, b'\xFF')
}

///|
test "panic kernel dimensions cannot overflow to a valid weight count" {
  ignore(@pixelforge.Kernel::new(2147483647, [1.0], 1.0, 0.0))
}

///|
test "panic convolution validates directly constructed kernels" {
  ignore(
    @pixelforge.Image::new(1, 1).convolve({
      size: 1,
      weights: [1.0],
      divisor: 0.0,
      bias: 0.0,
    }),
  )
}

///|
test "affine inversion rejects nonfinite coefficients and overflowed inverses" {
  for value in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(@pixelforge.Affine::translation(value, 0.0).invert() is None)
    assert_true(@pixelforge.Affine::scaling(value, 1.0).invert() is None)
  }
  let large = @pixelforge.Affine::scaling(1.0e308, 1.0e308)
  assert_true(large.invert() is None)
  let image = @pixelforge.Image::new(2, 2)
  image.set_pixel(0, 0, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  assert_eq(
    image.translate(1.0e100, 1.0e100).data,
    FixedArray::make(16, b'\x00'),
  )
}
