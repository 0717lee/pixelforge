///|
/// Dithering tests: output uses only palette tones, brightness is roughly
/// preserved on flat regions, and pure black/white are fixed points.

///|
test "dither_mono outputs only pure black and white" {
  let img = @pixelforge.Image::new(12, 12)
  for y in 0..<12 {
    for x in 0..<12 {
      let v = @pixelforge.clamp_byte(x * 20) // horizontal ramp
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let out = img.dither_mono()
  for y in 0..<12 {
    for x in 0..<12 {
      let p = out.get_pixel(x, y).0.to_int()
      assert_true(p == 0 || p == 255)
    }
  }
}

///|
test "dithering preserves average brightness of a flat mid-gray" {
  // A flat 50%-gray field dithered to 1 bit should be about half white
  // pixels, so the mean stays close to 128.
  let img = solid(16, 16, 128, 128, 128, 255)
  let out = img.dither_mono()
  let mut sum = 0
  for y in 0..<16 {
    for x in 0..<16 {
      sum = sum + out.get_pixel(x, y).0.to_int()
    }
  }
  let mean = sum / (16 * 16)
  assert_true(mean >= 108 && mean <= 148) // 128 +/- ~20
}

///|
test "pure black and white images are unchanged by dithering" {
  let black = solid(6, 6, 0, 0, 0, 255)
  let bout = black.dither_mono()
  for y in 0..<6 {
    for x in 0..<6 {
      assert_eq(bout.get_pixel(x, y).0.to_int(), 0)
    }
  }
  let white = solid(6, 6, 255, 255, 255, 255)
  let wout = white.dither_mono()
  for y in 0..<6 {
    for x in 0..<6 {
      assert_eq(wout.get_pixel(x, y).0.to_int(), 255)
    }
  }
}

///|
test "dither_grayscale(4) uses only the four palette tones" {
  // levels=4 -> step 85 -> tones {0, 85, 170, 255}.
  let img = @pixelforge.Image::new(10, 10)
  for y in 0..<10 {
    for x in 0..<10 {
      let v = @pixelforge.clamp_byte((x + y) * 13)
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let out = img.dither_grayscale(4)
  for y in 0..<10 {
    for x in 0..<10 {
      let p = out.get_pixel(x, y).0.to_int()
      assert_true(p == 0 || p == 85 || p == 170 || p == 255)
    }
  }
}

///|
test "dithering preserves alpha" {
  let img = single(120, 120, 120, 77)
  assert_eq(img.dither_mono().get_pixel(0, 0).3.to_int(), 77)
}
