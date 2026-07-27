///|
/// Color space tests with hand-checked reference values.

///|
test "rgb_to_hsv on primary colors" {
  let (h, s, v) = rgb_to_hsv(255, 0, 0)
  assert_eq(h.to_int(), 0)
  assert_eq((s * 100.0).to_int(), 100)
  assert_eq((v * 100.0).to_int(), 100)
  let (hg, _, _) = rgb_to_hsv(0, 255, 0)
  assert_eq(hg.to_int(), 120)
  let (hb, _, _) = rgb_to_hsv(0, 0, 255)
  assert_eq(hb.to_int(), 240)
}

///|
test "hsv round-trips 8-bit colors" {
  let samples = [
    (255, 0, 0),
    (0, 255, 0),
    (0, 0, 255),
    (255, 255, 0),
    (12, 200, 99),
    (128, 128, 128),
    (0, 0, 0),
    (255, 255, 255),
  ]
  for i in 0..<samples.length() {
    let (r, g, b) = samples[i]
    let (h, s, v) = rgb_to_hsv(r, g, b)
    let (r2, g2, b2) = hsv_to_rgb(h, s, v)
    assert_eq(r2, r)
    assert_eq(g2, g)
    assert_eq(b2, b)
  }
}

///|
test "ycbcr round-trips within one step" {
  // BT.601 full-range round trip is exact up to +-1 per channel.
  let samples = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (12, 200, 99)]
  for i in 0..<samples.length() {
    let (r, g, b) = samples[i]
    let (y, cb, cr) = rgb_to_ycbcr(r, g, b)
    let (r2, g2, b2) = ycbcr_to_rgb(y, cb, cr)
    assert_true(iabs_pub(r2 - r) <= 1)
    assert_true(iabs_pub(g2 - g) <= 1)
    assert_true(iabs_pub(b2 - b) <= 1)
  }
}

///|
/// Local absolute value so the blackbox tests stay self-contained.
fn iabs_pub(v : Int) -> Int {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
test "gray stays gray under ycbcr" {
  let (y, cb, cr) = rgb_to_ycbcr(128, 128, 128)
  assert_eq(y, 128)
  assert_eq(cb, 128)
  assert_eq(cr, 128)
}

///|
test "saturate(0) collapses color to gray, hue_rotate(360) is identity" {
  let img = single(200, 50, 50, 255)
  let gray = img.saturate(0.0).get_pixel(0, 0)
  assert_eq(gray.0.to_int(), gray.1.to_int())
  assert_eq(gray.1.to_int(), gray.2.to_int())
  let same = img.hue_rotate(360.0).get_pixel(0, 0)
  assert_eq(same.0.to_int(), 200)
  assert_eq(same.1.to_int(), 50)
  assert_eq(same.2.to_int(), 50)
}

///|
test "hue_rotate(120) turns red into green" {
  let (r, g, b, _) = single(255, 0, 0, 255).hue_rotate(120.0).get_pixel(0, 0)
  assert_eq(r.to_int(), 0)
  assert_eq(g.to_int(), 255)
  assert_eq(b.to_int(), 0)
}
