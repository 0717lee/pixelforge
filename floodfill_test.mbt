///|
/// Flood fill tests: bounded regions fill exactly, borders stop the fill,
/// tolerance widens the matched region, and out-of-bounds seeds are safe.

///|
test "flood fill recolors a bounded region and stops at the border" {
  // A 7x7 white field split by a black vertical wall at x = 3. Filling the
  // left half must not cross the wall.
  let img = solid(7, 7, 255, 255, 255, 255)
  for y in 0..<7 {
    img.set_pixel(3, y, b'\x00', b'\x00', b'\x00', b'\xFF')
  }
  let out = img.flood_fill(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF', 0)
  // Left of the wall: red.
  for y in 0..<7 {
    for x in 0..<3 {
      assert_eq(out.get_pixel(x, y).0.to_int(), 255)
      assert_eq(out.get_pixel(x, y).1.to_int(), 0)
    }
  }
  // The wall stays black.
  assert_eq(out.get_pixel(3, 0).0.to_int(), 0)
  // Right of the wall: untouched white.
  for y in 0..<7 {
    for x in 4..<7 {
      let (r, g, b, _) = out.get_pixel(x, y)
      assert_eq(r.to_int(), 255)
      assert_eq(g.to_int(), 255)
      assert_eq(b.to_int(), 255)
    }
  }
}

///|
test "flood fill with tolerance 0 only matches exact colors" {
  // Checkerboard of 100 and 105; tolerance 0 fills just the seed's shade.
  let img = @pixelforge.Image::new(4, 4)
  for y in 0..<4 {
    for x in 0..<4 {
      let v : Byte = if (x + y) % 2 == 0 { b'\x64' } else { b'\x69' } // 100 / 105
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  // Seed (0,0) is 100; only the 8 same-parity cells match — but they touch
  // only at corners, so 4-connectivity fills exactly the seed cell.
  let out = img.flood_fill(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF', 0)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 255)
  // Diagonal neighbor of the same shade is not 4-connected: unchanged.
  assert_eq(out.get_pixel(1, 1).0.to_int(), 100)
  // Orthogonal neighbor is the other shade: unchanged.
  assert_eq(out.get_pixel(1, 0).0.to_int(), 105)
}

///|
test "flood fill tolerance merges near colors into one region" {
  // Same checkerboard; tolerance 10 lets 100 and 105 count as one region,
  // so the whole 4x4 image fills.
  let img = @pixelforge.Image::new(4, 4)
  for y in 0..<4 {
    for x in 0..<4 {
      let v : Byte = if (x + y) % 2 == 0 { b'\x64' } else { b'\x69' }
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let out = img.flood_fill(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF', 10)
  for y in 0..<4 {
    for x in 0..<4 {
      assert_eq(out.get_pixel(x, y).0.to_int(), 255)
      assert_eq(out.get_pixel(x, y).1.to_int(), 0)
    }
  }
}

///|
test "flood fill of a uniform image repaints everything" {
  let img = solid(10, 10, 30, 60, 90, 255)
  let out = img.flood_fill(5, 5, b'\x0A', b'\x14', b'\x1E', b'\xFF', 0)
  for y in 0..<10 {
    for x in 0..<10 {
      let (r, g, b, _) = out.get_pixel(x, y)
      assert_eq(r.to_int(), 10)
      assert_eq(g.to_int(), 20)
      assert_eq(b.to_int(), 30)
    }
  }
}

///|
test "out-of-bounds seed returns an unchanged copy" {
  let img = solid(4, 4, 200, 100, 50, 255)
  let out = img.flood_fill(99, 99, b'\x00', b'\x00', b'\x00', b'\xFF', 0)
  for i in 0..<(4 * 4 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}
