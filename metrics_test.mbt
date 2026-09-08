///|
/// Image quality metric tests use hand-computed channel and luma values.

///|
test "mse includes alpha and averages four channels" {
  let a = single(0, 0, 0, 0)
  let b = single(10, 20, 30, 40)
  // (10^2 + 20^2 + 30^2 + 40^2) / 4 = 750.
  assert_eq(a.mse(b), 750.0)
}

///|
test "mse reaches the 8-bit channel boundary" {
  let black = single(0, 0, 0, 0)
  let white = single(255, 255, 255, 255)
  assert_eq(black.mse(white), 65025.0)
}

///|
test "luma_mse follows integer Rec.601 and ignores alpha" {
  let a = single(0, 0, 0, 0)
  let b = single(10, 20, 30, 255)
  // luma(b) = floor((2990 + 11740 + 3420) / 1000) = 18.
  assert_eq(a.luma_mse(b), 324.0)
}

///|
test "identical images have zero error, infinite psnr, and unit ssim" {
  let a = single(80, 120, 200, 37)
  assert_eq(a.mse(a), 0.0)
  assert_true(a.psnr(a).is_pos_inf())
  assert_eq(a.luma_mse(a), 0.0)
  assert_eq(a.ssim(a), 1.0)
}

///|
test "psnr matches the standard 10 log10 formula" {
  let a = single(0, 0, 0, 0)
  let b = single(10, 20, 30, 40)
  let expected = 10.0 * @math.log10(65025.0 / 750.0)
  let actual = a.psnr(b)
  assert_true((actual - expected) * (actual - expected) < 1.0e-24)
}

///|
test "ssim is low for black versus white and ignores alpha" {
  let black = single(0, 0, 0, 0)
  let white = single(255, 255, 255, 255)
  // For two constant luma windows, the variance and covariance terms cancel;
  // the expected value is C1 / (255^2 + C1), approximately 0.0001.
  let expected = 6.5025 / (65025.0 + 6.5025)
  let actual = black.ssim(white)
  assert_true((actual - expected) * (actual - expected) < 1.0e-24)
  // Alpha-only changes do not affect luma SSIM.
  let alpha_only = single(0, 0, 0, 255)
  assert_eq(black.luma_mse(alpha_only), 0.0)
  assert_eq(black.ssim(alpha_only), 1.0)
}

///|
test "ssim uses population variance over the complete image" {
  let a = @pixelforge.Image::new(2, 1)
  let b = @pixelforge.Image::new(2, 1)
  a.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  a.set_pixel(1, 0, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  b.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  b.set_pixel(1, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  // This is a finite, bounded score; the global window must not return NaN
  // for a two-pixel image with one nonzero variance term.
  let value = a.ssim(b)
  assert_true(value >= -1.0 && value <= 1.0)
}

///|
test "empty equal-sized images have identity metrics" {
  let a = @pixelforge.Image::new(0, 0)
  let b = @pixelforge.Image::new(0, 0)
  assert_eq(a.mse(b), 0.0)
  assert_true(a.psnr(b).is_pos_inf())
  assert_eq(a.ssim(b), 1.0)
}
