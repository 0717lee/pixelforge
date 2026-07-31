///|
/// Bicubic resize tests: identity, flat-field invariance, interpolation
/// smoothness versus nearest-neighbor, and size clamping.

///|
test "bicubic same-size resize is an identity" {
  // Center-aligned sampling puts every sample exactly on a source pixel,
  // where Catmull-Rom weights collapse to (0, 1, 0, 0) — exact copy.
  let img = @pixelforge.Image::new(5, 4)
  for y in 0..<4 {
    for x in 0..<5 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 47),
        @pixelforge.clamp_byte(y * 61),
        @pixelforge.clamp_byte((x * y * 13 + 9) % 256),
        @pixelforge.clamp_byte(200 - x),
      )
    }
  }
  let out = img.resize_bicubic(5, 4)
  for i in 0..<(5 * 4 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "bicubic keeps a flat field unchanged at any scale" {
  let img = solid(6, 6, 88, 144, 21, 255)
  for dims in [(3, 3), (12, 12), (7, 5)] {
    let (nw, nh) = dims
    let out = img.resize_bicubic(nw, nh)
    assert_eq(out.width, nw)
    assert_eq(out.height, nh)
    for y in 0..<nh {
      for x in 0..<nw {
        let (r, g, b, a) = out.get_pixel(x, y)
        assert_eq(r.to_int(), 88)
        assert_eq(g.to_int(), 144)
        assert_eq(b.to_int(), 21)
        assert_eq(a.to_int(), 255)
      }
    }
  }
}

///|
test "bicubic upscale of a step is smoother than nearest-neighbor" {
  // A hard 0|255 step upscaled 4x: nearest keeps only {0, 255}, bicubic
  // must produce at least one intermediate value across the transition.
  let img = @pixelforge.Image::new(4, 1)
  img.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  img.set_pixel(1, 0, b'\x00', b'\x00', b'\x00', b'\xFF')
  img.set_pixel(2, 0, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  img.set_pixel(3, 0, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let cubic = img.resize_bicubic(16, 1)
  let mut has_mid = false
  for x in 0..<16 {
    let v = cubic.get_pixel(x, 0).0.to_int()
    if v > 10 && v < 245 {
      has_mid = true
    }
  }
  assert_true(has_mid)
  // Endpoints stay at the extremes.
  assert_eq(cubic.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(cubic.get_pixel(15, 0).0.to_int(), 255)
}

///|
test "bicubic clamps degenerate target sizes to 1x1" {
  let img = solid(4, 4, 50, 60, 70, 255)
  let out = img.resize_bicubic(0, -3)
  assert_eq(out.width, 1)
  assert_eq(out.height, 1)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 50)
}
