///|
/// Canny tests built on synthetic step edges where the expected geometry of
/// the detected contour is known exactly.

///|
test "canny finds a thin vertical edge at a step boundary" {
  // Left half black, right half white: expect a thin vertical contour near
  // x = 7..8 and nothing in the flat regions.
  let img = @pixelforge.Image::new(16, 16)
  for y in 0..<16 {
    for x in 0..<16 {
      let v : Byte = if x < 8 { b'\x00' } else { b'\xFF' }
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let edges = img.canny(40, 100)
  for y in 0..<16 {
    // At least one edge pixel inside the transition band on every row.
    let mut hits = 0
    for x in 5..<11 {
      if edges.get_pixel(x, y).0.to_int() == 255 {
        hits = hits + 1
      }
    }
    assert_true(hits >= 1)
    // Flat regions stay clean.
    for x in 0..<4 {
      assert_eq(edges.get_pixel(x, y).0.to_int(), 0)
    }
    for x in 12..<16 {
      assert_eq(edges.get_pixel(x, y).0.to_int(), 0)
    }
  }
}

///|
test "canny output is a strictly binary grayscale map" {
  let img = @pixelforge.Image::new(9, 9)
  for y in 0..<9 {
    for x in 0..<9 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 30),
        @pixelforge.clamp_byte(y * 25),
        @pixelforge.clamp_byte((x + y) * 14),
        b'\xFF',
      )
    }
  }
  let edges = img.canny(30, 80)
  for y in 0..<9 {
    for x in 0..<9 {
      let (r, g, b, _) = edges.get_pixel(x, y)
      assert_true(r.to_int() == 0 || r.to_int() == 255)
      assert_eq(r.to_int(), g.to_int())
      assert_eq(g.to_int(), b.to_int())
    }
  }
}

///|
test "canny reports no edges on flat or low-contrast input" {
  // Perfectly flat image: zero gradient everywhere.
  let flat = solid(12, 12, 90, 90, 90, 255)
  let none = flat.canny(40, 100)
  for y in 0..<12 {
    for x in 0..<12 {
      assert_eq(none.get_pixel(x, y).0.to_int(), 0)
    }
  }
  // A 4-level step is far below the low threshold after smoothing.
  let faint = @pixelforge.Image::new(12, 12)
  for y in 0..<12 {
    for x in 0..<12 {
      let v : Byte = if x < 6 { b'\x64' } else { b'\x68' }
      faint.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let quiet = faint.canny(40, 100)
  for y in 0..<12 {
    for x in 0..<12 {
      assert_eq(quiet.get_pixel(x, y).0.to_int(), 0)
    }
  }
}

///|
test "filter id 20 dispatches to canny" {
  let img = @pixelforge.Image::new(10, 10)
  for y in 0..<10 {
    for x in 0..<10 {
      let v : Byte = if x < 5 { b'\x00' } else { b'\xFF' }
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let via_id = img.apply_filter_id(20, 0.0)
  let direct = img.canny(50, 100)
  for i in 0..<(10 * 10 * 4) {
    assert_eq(via_id.data[i].to_int(), direct.data[i].to_int())
  }
}
