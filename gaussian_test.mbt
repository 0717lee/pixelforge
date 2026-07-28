///|
/// Separable Gaussian tests: identity, flat-field invariance, impulse
/// response symmetry, and radius-1 agreement with the 3x3 kernel.

///|
test "gaussian(0) is an exact copy" {
  let img = gray_image(4, 1, [10, 200, 30, 90])
  let out = img.gaussian(0)
  for i in 0..<(4 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "gaussian keeps a flat field unchanged for any radius" {
  // Binomial weights are exactly normalized, so a constant image must be a
  // fixed point at every radius.
  let img = solid(9, 7, 77, 130, 201, 255)
  for r in [1, 2, 5, 12] {
    let out = img.gaussian(r)
    for y in 0..<7 {
      for x in 0..<9 {
        let (pr, pg, pb, pa) = out.get_pixel(x, y)
        assert_eq(pr.to_int(), 77)
        assert_eq(pg.to_int(), 130)
        assert_eq(pb.to_int(), 201)
        assert_eq(pa.to_int(), 255)
      }
    }
  }
}

///|
test "gaussian impulse response is symmetric and peaks at the center" {
  let img = solid(11, 11, 0, 0, 0, 255)
  img.set_pixel(5, 5, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let out = img.gaussian(3)
  let center = out.get_pixel(5, 5).0.to_int()
  assert_true(center > 0)
  for d in 1..<4 {
    let right = out.get_pixel(5 + d, 5).0.to_int()
    let left = out.get_pixel(5 - d, 5).0.to_int()
    let down = out.get_pixel(5, 5 + d).0.to_int()
    let up = out.get_pixel(5, 5 - d).0.to_int()
    // 4-fold symmetry and radial decay.
    assert_eq(right, left)
    assert_eq(down, up)
    assert_eq(right, down)
    assert_true(right < center)
  }
  // Energy stays inside the (2r+1) support: beyond it, exact zero.
  assert_eq(out.get_pixel(5 + 4, 5).0.to_int(), 0)
}

///|
test "gaussian(1) agrees with the 3x3 gaussian kernel within rounding" {
  // radius 1 = [1,2,1] twice, i.e. the same [1,2,1;2,4,2;1,2,1]/16 kernel;
  // only the per-pass rounding may differ, so allow at most 1 step.
  let img = @pixelforge.Image::new(7, 6)
  for y in 0..<6 {
    for x in 0..<7 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 37),
        @pixelforge.clamp_byte(y * 45),
        @pixelforge.clamp_byte((x * y * 23 + 11) % 256),
        b'\xFF',
      )
    }
  }
  let sep = img.gaussian(1)
  let full = img.convolve(@pixelforge.Kernel::gaussian_blur())
  for i in 0..<(7 * 6 * 4) {
    let d = sep.data[i].to_int() - full.data[i].to_int()
    assert_true(d >= -1 && d <= 1)
  }
}
