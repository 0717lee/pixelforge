///|
test "thumbnail fits landscape portrait and square bounds" {
  for
    (w, h, bw, bh, ew, eh) in [
      (8, 4, 4, 4, 4, 2),
      (4, 8, 4, 4, 2, 4),
      (8, 8, 3, 5, 3, 3),
      (8, 4, 20, 1, 2, 1),
      (7, 5, 3, 3, 3, 2),
    ] {
    let output = @pixelforge.Image::new(w, h).thumbnail(bw, bh)
    assert_eq((output.width, output.height), (ew, eh))
  }
}

///|
test "thumbnail samples centers and preserves the source" {
  let source = @pixelforge.Image::new(4, 2)
  for y in 0..<2 {
    for x in 0..<4 {
      let value = (y * 100 + x * 20).to_byte()
      source.set_pixel(x, y, value, value, value, b'\xFF')
    }
  }
  let output = source.thumbnail(2, 2)
  assert_eq((output.width, output.height), (2, 1))
  // Means of the two 2x2 blocks: (0+20+100+120)/4 and (40+60+140+160)/4.
  assert_eq(output.get_pixel(0, 0), (b'\x3C', b'\x3C', b'\x3C', b'\xFF'))
  assert_eq(output.get_pixel(1, 0), (b'\x64', b'\x64', b'\x64', b'\xFF'))
  assert_eq(source.get_pixel(3, 1).0, b'\xA0')
}

///|
test "thumbnail never enlarges and always owns its buffer" {
  let source = @pixelforge.Image::new(2, 1)
  source.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\x40')
  for bounds in [(10, 10), (2, 1), (2147483647, 2147483647)] {
    let output = source.thumbnail(bounds.0, bounds.1)
    assert_eq((output.width, output.height), (2, 1))
    assert_eq(output.data, source.data)
    output.set_pixel(0, 0, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
    assert_eq(source.get_pixel(0, 0), (b'\x10', b'\x20', b'\x30', b'\x40'))
  }
}

///|
test "thumbnail handles long strips and wide ratio arithmetic" {
  for
    (w, h, bw, bh, ew, eh) in [
      (50000, 1, 40000, 50000, 40000, 1),
      (1, 50000, 50000, 40000, 1, 40000),
      (50000, 1, 1, 2147483647, 1, 1),
      (1, 50000, 2147483647, 1, 1, 1),
    ] {
    let output = @pixelforge.Image::new(w, h).thumbnail(bw, bh)
    assert_eq((output.width, output.height), (ew, eh))
  }
}

///|
test "thumbnail clamps bounds and preserves empty image dimensions" {
  let output = @pixelforge.Image::new(3, 2).thumbnail(0, -1)
  assert_eq((output.width, output.height), (1, 1))
  for (w, h) in [(0, 0), (0, 7), (9, 0)] {
    let empty = @pixelforge.Image::new(w, h).thumbnail(2, 2)
    assert_eq((empty.width, empty.height), (w, h))
    assert_eq(empty.data.length(), 0)
  }
}
