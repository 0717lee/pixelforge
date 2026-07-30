///|
/// Distance transform tests: background stays black, the interior of a shape
/// is brighter than its rim, the deepest point normalizes to 255, and an
/// all-background image stays entirely black.

///|
test "distance transform keeps background black and peaks inside a shape" {
  // A 9x9 solid white square on... nothing — the border pixels are adjacent
  // to the image edge which is treated as inside, so use a framed shape:
  // white 7x7 interior surrounded by a 1px black border in an 9x9 image.
  let img = solid(9, 9, 0, 0, 0, 255)
  for y in 1..<8 {
    for x in 1..<8 {
      img.set_pixel(x, y, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
    }
  }
  let out = img.distance_transform(128)
  // Background is black.
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  // The center (4,4) is the deepest foreground pixel -> normalized to 255.
  assert_eq(out.get_pixel(4, 4).0.to_int(), 255)
  // A rim pixel just inside the border is dimmer than the center.
  assert_true(out.get_pixel(1, 4).0.to_int() < out.get_pixel(4, 4).0.to_int())
}

///|
test "distance grows monotonically toward the center of a bar" {
  // A 3-pixel-tall white bar (rows 1..3, cols 1..7) on a 9x5 black image.
  // The horizontal center is farther from the black frame than the tip.
  let img = solid(9, 5, 0, 0, 0, 255)
  for y in 1..<4 {
    for x in 1..<8 {
      img.set_pixel(x, y, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
    }
  }
  let out = img.distance_transform(128)
  let tip = out.get_pixel(1, 2).0.to_int() // near the left black edge
  let mid = out.get_pixel(4, 2).0.to_int() // center of the bar
  assert_true(mid > tip)
}

///|
test "distance transform of an all-background image is all black" {
  let img = solid(6, 6, 0, 0, 0, 255)
  let out = img.distance_transform(128)
  for y in 0..<6 {
    for x in 0..<6 {
      assert_eq(out.get_pixel(x, y).0.to_int(), 0)
    }
  }
}

///|
test "a lone foreground pixel maps to the maximum distance" {
  // One white pixel surrounded by black: it is its own deepest point, so it
  // normalizes to 255 (max == its own distance).
  let img = solid(5, 5, 0, 0, 0, 255)
  img.set_pixel(2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let out = img.distance_transform(128)
  assert_eq(out.get_pixel(2, 2).0.to_int(), 255)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
}

///|
test "distance transform preserves alpha" {
  let img = solid(5, 5, 255, 255, 255, 123)
  // fully foreground; center should be brightest, alpha carried through.
  let out = img.distance_transform(128)
  assert_eq(out.get_pixel(2, 2).3.to_int(), 123)
}
