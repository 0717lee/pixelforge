///|
/// Statistics / tonal-adjustment tests with hand-computed expectations.

///|
test "stats reports exact min/max/mean per channel" {
  // Two pixels: (10, 20, 30) and (50, 80, 90).
  let img = @pixelforge.Image::new(2, 1)
  img.set_pixel(0, 0, b'\x0A', b'\x14', b'\x1E', b'\xFF')
  img.set_pixel(1, 0, b'\x32', b'\x50', b'\x5A', b'\xFF')
  let s = img.stats()
  assert_eq(s.min_r, 10)
  assert_eq(s.max_r, 50)
  assert_eq(s.mean_r, 30) // (10 + 50) / 2
  assert_eq(s.min_g, 20)
  assert_eq(s.max_g, 80)
  assert_eq(s.mean_g, 50) // (20 + 80) / 2
  assert_eq(s.min_b, 30)
  assert_eq(s.max_b, 90)
  assert_eq(s.mean_b, 60) // (30 + 90) / 2
}

///|
test "stats luma matches the integer BT.601 formula" {
  // Single pixel (100, 150, 200): luma = (299*100 + 587*150 + 114*200)/1000.
  let img = single(100, 150, 200, 255)
  let s = img.stats()
  let expect = (299 * 100 + 587 * 150 + 114 * 200) / 1000 // = 140
  assert_eq(s.luma_min, expect)
  assert_eq(s.luma_max, expect)
  assert_eq(s.luma_mean, expect)
}

///|
test "auto_contrast stretches a compressed range toward the full scale" {
  // Gray ramp confined to luma 100..140; after stretching, the darkest
  // pixel should hit 0 and the brightest 255.
  let img = @pixelforge.Image::new(5, 1)
  let vals = [100, 110, 120, 130, 140]
  for x in 0..<5 {
    let v = @pixelforge.clamp_byte(vals[x])
    img.set_pixel(x, 0, v, v, v, b'\xFF')
  }
  let out = img.auto_contrast()
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(4, 0).0.to_int(), 255)
  // Monotonic in between.
  assert_true(out.get_pixel(2, 0).0.to_int() > 0)
  assert_true(out.get_pixel(2, 0).0.to_int() < 255)
}

///|
test "auto_contrast leaves a flat image unchanged" {
  let img = solid(4, 4, 90, 90, 90, 255)
  let out = img.auto_contrast()
  for y in 0..<4 {
    for x in 0..<4 {
      assert_eq(out.get_pixel(x, y).0.to_int(), 90)
    }
  }
}

///|
test "levels maps the input window endpoints to 0 and 255" {
  let img = @pixelforge.Image::new(3, 1)
  img.set_pixel(0, 0, b'\x32', b'\x32', b'\x32', b'\xFF') // 50 (black point)
  img.set_pixel(1, 0, b'\x8C', b'\x8C', b'\x8C', b'\xFF') // 140 (midpoint)
  img.set_pixel(2, 0, b'\xC8', b'\xC8', b'\xC8', b'\xFF') // 200 (white point)
  let out = img.levels(50, 200, 1.0)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(2, 0).0.to_int(), 255)
  // Linear midpoint: (140-50)/(200-50) = 0.6 -> 153.
  assert_eq(out.get_pixel(1, 0).0.to_int(), 153)
}

///|
test "levels gamma > 1 brightens the midtones" {
  let img = single(128, 128, 128, 255)
  let linear = img.levels(0, 255, 1.0).get_pixel(0, 0).0.to_int()
  let brightened = img.levels(0, 255, 2.0).get_pixel(0, 0).0.to_int()
  assert_eq(linear, 128)
  assert_true(brightened > 128)
}
