///|
/// Otsu threshold tests: the chosen value separates the two classes of a
/// bimodal image, binarization is exact, and degenerate inputs are handled.

///|
test "otsu_threshold lands between the two peaks of a bimodal image" {
  // Half the pixels at luma 50, half at luma 200 -> threshold in (50, 200).
  let img = @pixelforge.Image::new(10, 10)
  for y in 0..<10 {
    for x in 0..<10 {
      let v : Byte = if x < 5 { b'\x32' } else { b'\xC8' } // 50 / 200
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let t = img.otsu_threshold()
  assert_true(t >= 50 && t < 200)
}

///|
test "otsu binarizes a bimodal image into exactly two clusters" {
  let img = @pixelforge.Image::new(8, 8)
  for y in 0..<8 {
    for x in 0..<8 {
      let v : Byte = if (x + y) % 2 == 0 { b'\x28' } else { b'\xDC' } // 40 / 220
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let out = img.otsu()
  // Every pixel ends up pure black or white, and both classes are present.
  let mut blacks = 0
  let mut whites = 0
  for y in 0..<8 {
    for x in 0..<8 {
      let v = out.get_pixel(x, y).0.to_int()
      assert_true(v == 0 || v == 255)
      if v == 0 {
        blacks = blacks + 1
      } else {
        whites = whites + 1
      }
    }
  }
  assert_eq(blacks, 32)
  assert_eq(whites, 32)
}

///|
test "otsu separates a dark background from a bright square" {
  // 12x12 background at luma 30 with a 4x4 bright (luma 210) square.
  let img = solid(12, 12, 30, 30, 30, 255)
  for y in 4..<8 {
    for x in 4..<8 {
      img.set_pixel(x, y, b'\xD2', b'\xD2', b'\xD2', b'\xFF')
    }
  }
  let t = img.otsu_threshold()
  assert_true(t >= 30 && t < 210)
  let out = img.otsu()
  // The square is foreground (white); the surrounding background is black.
  assert_eq(out.get_pixel(5, 5).0.to_int(), 255)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 0)
  assert_eq(out.get_pixel(11, 11).0.to_int(), 0)
}

///|
test "otsu on a flat image does not crash and yields a single class" {
  let img = solid(6, 6, 128, 128, 128, 255)
  let t = img.otsu_threshold()
  // Only one populated bin: every pixel falls on the same side.
  let out = img.otsu()
  let first = out.get_pixel(0, 0).0.to_int()
  for y in 0..<6 {
    for x in 0..<6 {
      assert_eq(out.get_pixel(x, y).0.to_int(), first)
    }
  }
  assert_true(t >= 0 && t <= 255)
}
