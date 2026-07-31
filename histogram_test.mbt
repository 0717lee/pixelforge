///|
/// Histogram API tests with hand-counted expectations.

///|
test "histogram bins sum to the pixel count" {
  let img = @pixelforge.Image::new(7, 5)
  for y in 0..<5 {
    for x in 0..<7 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 36),
        @pixelforge.clamp_byte(y * 51),
        @pixelforge.clamp_byte((x + y) * 20),
        b'\xFF',
      )
    }
  }
  let luma = img.histogram_luma()
  let (hr, hg, hb) = img.histogram_rgb()
  let mut sl = 0
  let mut sr = 0
  let mut sg = 0
  let mut sb = 0
  for i in 0..<256 {
    sl = sl + luma[i]
    sr = sr + hr[i]
    sg = sg + hg[i]
    sb = sb + hb[i]
  }
  assert_eq(sl, 35)
  assert_eq(sr, 35)
  assert_eq(sg, 35)
  assert_eq(sb, 35)
}

///|
test "flat image concentrates every histogram in one bin" {
  let img = solid(6, 4, 37, 142, 209, 255)
  let luma = img.histogram_luma()
  let (hr, hg, hb) = img.histogram_rgb()
  assert_eq(hr[37], 24)
  assert_eq(hg[142], 24)
  assert_eq(hb[209], 24)
  // Luma of (37,142,209) = (299*37+587*142+114*209)/1000 = 118.
  let expect_luma = (299 * 37 + 587 * 142 + 114 * 209) / 1000
  assert_eq(luma[expect_luma], 24)
  // Every other bin is empty.
  for i in 0..<256 {
    if i != 37 {
      assert_eq(hr[i], 0)
    }
    if i != expect_luma {
      assert_eq(luma[i], 0)
    }
  }
}

///|
test "hand-counted mixed image lands in the right bins" {
  // Three pixels: red 10 twice, red 200 once.
  let img = @pixelforge.Image::new(3, 1)
  img.set_pixel(0, 0, b'\x0A', b'\x00', b'\x00', b'\xFF')
  img.set_pixel(1, 0, b'\x0A', b'\x00', b'\x00', b'\xFF')
  img.set_pixel(2, 0, b'\xC8', b'\x00', b'\x00', b'\xFF')
  let (hr, hg, _) = img.histogram_rgb()
  assert_eq(hr[10], 2)
  assert_eq(hr[200], 1)
  assert_eq(hg[0], 3)
}

///|
test "histogram_luma agrees with the equalization pipeline's binning" {
  // The public luma histogram must match what Otsu sees: a bimodal image
  // has exactly two occupied bins at the expected positions.
  let img = @pixelforge.Image::new(4, 2)
  for y in 0..<2 {
    for x in 0..<4 {
      let v : Byte = if x < 2 { b'\x28' } else { b'\xD2' } // 40 / 210
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let h = img.histogram_luma()
  assert_eq(h[40], 4)
  assert_eq(h[210], 4)
}
