///|
/// Crop and pad tests: exact sub-rectangle extraction, border filling,
/// clamping of out-of-range requests, and the crop∘pad round trip.

///|
test "crop extracts an exact sub-rectangle" {
  // 4x4 with a unique value per pixel (row*16 + col*4 in red).
  let img = @pixelforge.Image::new(4, 4)
  for y in 0..<4 {
    for x in 0..<4 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(y * 64 + x * 16),
        b'\x00',
        b'\x00',
        b'\xFF',
      )
    }
  }
  let c = img.crop(1, 1, 2, 2)
  assert_eq(c.width, 2)
  assert_eq(c.height, 2)
  assert_eq(c.get_pixel(0, 0).0.to_int(), img.get_pixel(1, 1).0.to_int())
  assert_eq(c.get_pixel(1, 0).0.to_int(), img.get_pixel(2, 1).0.to_int())
  assert_eq(c.get_pixel(1, 1).0.to_int(), img.get_pixel(2, 2).0.to_int())
}

///|
test "crop clamps a rectangle that runs past the edge" {
  let img = solid(5, 5, 10, 20, 30, 255)
  // Ask for 4x4 starting at (3,3): only 2x2 overlaps the image.
  let c = img.crop(3, 3, 4, 4)
  assert_eq(c.width, 2)
  assert_eq(c.height, 2)
  // A fully out-of-range crop degrades to 1x1.
  let empty = img.crop(10, 10, 3, 3)
  assert_eq(empty.width, 1)
  assert_eq(empty.height, 1)
}

///|
test "pad adds colored borders of the right size" {
  let img = solid(3, 2, 200, 100, 50, 255)
  let p = img.pad(2, 1, 4, 3, b'\x00', b'\x00', b'\x00', b'\xFF')
  assert_eq(p.width, 2 + 3 + 4) // 9
  assert_eq(p.height, 1 + 2 + 3) // 6
  // Border corner is black.
  let (br, bg, bb, ba) = p.get_pixel(0, 0)
  assert_eq(br.to_int(), 0)
  assert_eq(bg.to_int(), 0)
  assert_eq(bb.to_int(), 0)
  assert_eq(ba.to_int(), 255)
  // The original sits at offset (left=2, top=1).
  let (r, g, b, _) = p.get_pixel(2, 1)
  assert_eq(r.to_int(), 200)
  assert_eq(g.to_int(), 100)
  assert_eq(b.to_int(), 50)
}

///|
test "crop after a matching pad round-trips the image" {
  let img = @pixelforge.Image::new(5, 4)
  for y in 0..<4 {
    for x in 0..<5 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 40),
        @pixelforge.clamp_byte(y * 50),
        @pixelforge.clamp_byte((x + y) * 20),
        @pixelforge.clamp_byte(200 - x * 5),
      )
    }
  }
  let padded = img.pad(3, 2, 1, 4, b'\x11', b'\x22', b'\x33', b'\x44')
  let back = padded.crop(3, 2, 5, 4)
  assert_eq(back.width, 5)
  assert_eq(back.height, 4)
  for i in 0..<(5 * 4 * 4) {
    assert_eq(back.data[i].to_int(), img.data[i].to_int())
  }
}
