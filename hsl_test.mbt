///|
/// HSL tests: primary-color reference values, 8-bit round trips, gray
/// invariance and lightness adjustment behavior.

///|
test "rgb_to_hsl on primaries and white matches reference values" {
  // Pure red: H=0, S=1, L=0.5.
  let (h, s, l) = rgb_to_hsl(255, 0, 0)
  assert_eq(h.to_int(), 0)
  assert_eq((s * 100.0).to_int(), 100)
  assert_eq((l * 100.0).to_int(), 50)
  // Pure green / blue hues.
  assert_eq(rgb_to_hsl(0, 255, 0).0.to_int(), 120)
  assert_eq(rgb_to_hsl(0, 0, 255).0.to_int(), 240)
  // White: L=1, S=0.
  let (_, sw, lw) = rgb_to_hsl(255, 255, 255)
  assert_eq((sw * 100.0).to_int(), 0)
  assert_eq((lw * 100.0).to_int(), 100)
}

///|
test "hsl round-trips 8-bit colors exactly" {
  let samples = [
    (255, 0, 0),
    (0, 255, 0),
    (0, 0, 255),
    (255, 255, 0),
    (12, 200, 99),
    (128, 128, 128),
    (0, 0, 0),
    (255, 255, 255),
    (37, 142, 209),
    (250, 128, 114),
  ]
  for i in 0..<samples.length() {
    let (r, g, b) = samples[i]
    let (h, s, l) = rgb_to_hsl(r, g, b)
    let (r2, g2, b2) = hsl_to_rgb(h, s, l)
    assert_eq(r2, r)
    assert_eq(g2, g)
    assert_eq(b2, b)
  }
}

///|
test "grays keep zero saturation and exact lightness" {
  for v in [0, 64, 128, 200, 255] {
    let (_, s, l) = rgb_to_hsl(v, v, v)
    assert_eq((s * 1000.0).to_int(), 0)
    // L = v/255 exactly.
    let (r2, g2, b2) = hsl_to_rgb(0.0, s, l)
    assert_eq(r2, v)
    assert_eq(g2, v)
    assert_eq(b2, v)
  }
}

///|
test "adjust_lightness lightens toward white and darkens toward black" {
  let img = single(200, 50, 50, 255)
  // +1 lightness saturates to pure white regardless of hue.
  let white = img.adjust_lightness(1.0).get_pixel(0, 0)
  assert_eq(white.0.to_int(), 255)
  assert_eq(white.1.to_int(), 255)
  assert_eq(white.2.to_int(), 255)
  // -1 lightness collapses to black.
  let black = img.adjust_lightness(-1.0).get_pixel(0, 0)
  assert_eq(black.0.to_int(), 0)
  assert_eq(black.1.to_int(), 0)
  assert_eq(black.2.to_int(), 0)
  // A small positive delta brightens every channel without reordering.
  let (r, g, b, _) = img.adjust_lightness(0.2).get_pixel(0, 0)
  assert_true(r.to_int() > 200)
  assert_true(g.to_int() > 50)
  assert_true(r.to_int() > g.to_int())
  assert_eq(g.to_int(), b.to_int()) // symmetric channels stay symmetric
}

///|
test "adjust_lightness(0) is an exact copy and alpha is preserved" {
  let img = single(120, 88, 33, 77)
  let same = img.adjust_lightness(0.0)
  for i in 0..<4 {
    assert_eq(same.data[i].to_int(), img.data[i].to_int())
  }
  assert_eq(img.adjust_lightness(0.3).get_pixel(0, 0).3.to_int(), 77)
}
