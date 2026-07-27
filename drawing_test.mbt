///|
/// Drawing primitive tests with exact pixel-count and geometry checks.

///|
/// Counts pixels whose red channel equals `value`.
fn count_red(img : @pixelforge.Image, value : Int) -> Int {
  let mut n = 0
  for y in 0..<img.height {
    for x in 0..<img.width {
      if img.get_pixel(x, y).0.to_int() == value {
        n = n + 1
      }
    }
  }
  n
}

///|
test "draw_line covers exact pixels for horizontal, vertical and diagonal" {
  let img = solid(8, 8, 0, 0, 0, 255)
  img.draw_line(1, 2, 6, 2, b'\xC8', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red(img, 200), 6) // 6 pixels on the horizontal run
  for x in 1..<7 {
    assert_eq(img.get_pixel(x, 2).0.to_int(), 200)
  }
  // A perfect diagonal visits exactly one pixel per column.
  let diag = solid(8, 8, 0, 0, 0, 255)
  diag.draw_line(0, 0, 7, 7, b'\x64', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red(diag, 100), 8)
  for i in 0..<8 {
    assert_eq(diag.get_pixel(i, i).0.to_int(), 100)
  }
}

///|
test "draw_rect outlines and fill_rect fills the exact area" {
  let img = solid(10, 10, 0, 0, 0, 255)
  img.draw_rect(2, 3, 5, 4, b'\xFF', b'\x00', b'\x00', b'\xFF')
  // Perimeter of a 5x4 rect = 2*(5+4) - 4 corners = 14 pixels.
  assert_eq(count_red(img, 255), 14)
  assert_eq(img.get_pixel(2, 3).0.to_int(), 255) // corner
  assert_eq(img.get_pixel(6, 6).0.to_int(), 255) // opposite corner
  assert_eq(img.get_pixel(4, 5).0.to_int(), 0) // interior untouched
  let filled = solid(10, 10, 0, 0, 0, 255)
  filled.fill_rect(2, 3, 5, 4, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red(filled, 255), 20) // 5 * 4
}

///|
test "circle primitives respect radius and symmetry" {
  let img = solid(16, 16, 0, 0, 0, 255)
  img.draw_circle(8, 8, 5, b'\xFF', b'\x00', b'\x00', b'\xFF')
  // The four axis-aligned extremes are always on the outline.
  assert_eq(img.get_pixel(13, 8).0.to_int(), 255)
  assert_eq(img.get_pixel(3, 8).0.to_int(), 255)
  assert_eq(img.get_pixel(8, 13).0.to_int(), 255)
  assert_eq(img.get_pixel(8, 3).0.to_int(), 255)
  assert_eq(img.get_pixel(8, 8).0.to_int(), 0) // center stays empty
  // Filled disk of radius 2 covers exactly 13 pixels (1+3+5+3+1... by rows:
  // dy=-2:1, dy=-1:3, dy=0:5, dy=1:3, dy=2:1 = 13).
  let disk = solid(9, 9, 0, 0, 0, 255)
  disk.fill_circle(4, 4, 2, b'\x64', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red(disk, 100), 13)
}

///|
test "primitives clip silently at image borders" {
  let img = solid(4, 4, 0, 0, 0, 255)
  // Everything below extends past the 4x4 canvas; nothing may trap or wrap.
  img.draw_line(-3, -3, 7, 7, b'\xFF', b'\x00', b'\x00', b'\xFF')
  img.draw_rect(-2, -2, 10, 10, b'\xFF', b'\x00', b'\x00', b'\xFF')
  img.fill_circle(3, 3, 5, b'\xFF', b'\x00', b'\x00', b'\xFF')
  // The whole 4x4 canvas ends up red, and only these 16 pixels exist.
  assert_eq(count_red(img, 255), 16)
}
