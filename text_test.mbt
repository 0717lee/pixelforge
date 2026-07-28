///|
/// Bitmap font tests: exact per-glyph pixel counts, scaling arithmetic,
/// pen advance, case folding and border clipping.

///|
/// Counts pixels whose red channel equals `value` (local copy for this
/// blackbox test file).
fn count_red_px(img : @pixelforge.Image, value : Int) -> Int {
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
test "glyph I has exactly 11 pixels at scale 1" {
  // I rows: 01110 + 5 x 00100 + 01110 = 3 + 5 + 3 = 11 set bits.
  let img = solid(8, 9, 0, 0, 0, 255)
  img.draw_char(1, 1, 'I', 1, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red_px(img, 255), 11)
  // Top bar spans columns 2..4 of the glyph cell at (1,1).
  assert_eq(img.get_pixel(2, 1).0.to_int(), 255)
  assert_eq(img.get_pixel(3, 1).0.to_int(), 255)
  assert_eq(img.get_pixel(4, 1).0.to_int(), 255)
  assert_eq(img.get_pixel(1, 1).0.to_int(), 0)
}

///|
test "scale multiplies glyph pixels by scale squared" {
  // '-' is a single 5-pixel row; at scale 3 it covers 5*3*3 = 45 pixels.
  let img = solid(20, 25, 0, 0, 0, 255)
  img.draw_char(1, 1, '-', 3, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red_px(img, 255), 45)
}

///|
test "draw_text advances 6 columns per character" {
  let img = solid(16, 9, 0, 0, 0, 255)
  img.draw_text(1, 1, "II", 1, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(count_red_px(img, 255), 22)
  // Second 'I' top bar starts 6 columns right of the first: (1+6+1, 1).
  assert_eq(img.get_pixel(8, 1).0.to_int(), 255)
  // The spacing column between glyphs stays empty.
  for y in 0..<9 {
    assert_eq(img.get_pixel(6, y).0.to_int(), 0)
  }
}

///|
test "lowercase renders identically to uppercase" {
  let upper = solid(8, 9, 0, 0, 0, 255)
  let lower = solid(8, 9, 0, 0, 0, 255)
  upper.draw_char(1, 1, 'E', 1, b'\xFF', b'\x00', b'\x00', b'\xFF')
  lower.draw_char(1, 1, 'e', 1, b'\xFF', b'\x00', b'\x00', b'\xFF')
  for i in 0..<(8 * 9 * 4) {
    assert_eq(upper.data[i].to_int(), lower.data[i].to_int())
  }
}

///|
test "unknown glyphs render as a 20-pixel box and text clips at borders" {
  let img = solid(8, 9, 0, 0, 0, 255)
  img.draw_char(1, 1, '@', 1, b'\xFF', b'\x00', b'\x00', b'\xFF')
  // Box: 5 top + 5 bottom + 2 x 5 side rows = 20 set bits.
  assert_eq(count_red_px(img, 255), 20)
  // Clipping: drawing far off-canvas must neither trap nor wrap.
  let edge = solid(4, 4, 0, 0, 0, 255)
  edge.draw_text(-3, -2, "HI", 2, b'\xFF', b'\x00', b'\x00', b'\xFF')
  edge.draw_text(3, 3, "0", 5, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_true(count_red_px(edge, 255) <= 16)
}
