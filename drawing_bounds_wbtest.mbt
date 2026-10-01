///|
fn reference_line(
  image : Image,
  ax : Int,
  ay : Int,
  bx : Int,
  by : Int,
) -> Unit {
  let dx = iabs(bx - ax)
  let dy = -iabs(by - ay)
  let sx = if ax < bx { 1 } else { -1 }
  let sy = if ay < by { 1 } else { -1 }
  let mut error = dx + dy
  let mut x = ax
  let mut y = ay
  while true {
    image.plot(x, y, b'\xFF', b'\x00', b'\x00', b'\xFF')
    if x == bx && y == by {
      break
    }
    let twice = error * 2
    if twice >= dy {
      error += dy
      x += sx
    }
    if twice <= dx {
      error += dx
      y += sy
    }
  }
}

///|
test "clipped lines match iterative Bresenham in every octant and direction" {
  for ax in -2..<7 {
    for ay in -2..<7 {
      for bx in -2..<7 {
        for by in -2..<7 {
          let expected = Image::new(5, 5)
          reference_line(expected, ax, ay, bx, by)
          let actual = Image::new(5, 5)
          actual.draw_line(ax, ay, bx, by, b'\xFF', b'\x00', b'\x00', b'\xFF')
          assert_eq(actual.data, expected.data)
        }
      }
    }
  }
}

///|
test "clipped circles match the midpoint reference" {
  for radius in 0..<40 {
    for center in [-3, 0, 4, 10] {
      let expected = Image::new(9, 9)
      let mut x = radius
      let mut y = 0
      let mut err = 1 - radius
      while x >= y {
        for
          (dx, dy) in [
            (x, y),
            (y, x),
            (-y, x),
            (-x, y),
            (-x, -y),
            (-y, -x),
            (y, -x),
            (x, -y),
          ] {
          expected.plot(
            center + dx,
            center + dy,
            b'\xFF',
            b'\x00',
            b'\x00',
            b'\xFF',
          )
        }
        y += 1
        if err < 0 {
          err += 2 * y + 1
        } else {
          x -= 1
          err += 2 * (y - x) + 1
        }
      }
      let actual = Image::new(9, 9)
      actual.draw_circle(
        center, center, radius, b'\xFF', b'\x00', b'\x00', b'\xFF',
      )
      assert_eq(actual.data, expected.data)
    }
  }
}

///|
test "drawing extreme coordinates is bounded by the visible canvas" {
  let image = Image::new(3, 3)
  image.draw_line(
    -2147483648, -2147483648, 2147483647, 2147483647, b'\xFF', b'\x00', b'\x00',
    b'\xFF',
  )
  for y in 0..<3 {
    for x in 0..<3 {
      assert_eq(image.get_pixel(x, y).0.to_int(), if x == y { 255 } else { 0 })
    }
  }
  image.fill_rect(
    -1, -1, 2147483647, 2147483647, b'\x11', b'\x00', b'\x00', b'\xFF',
  )
  assert_eq(image.get_pixel(2, 2).0, b'\x11')
  image.draw_rect(
    2147483647, 2147483647, 2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  )
  assert_eq(image.get_pixel(0, 0).0, b'\x11')
  image.fill_circle(0, 0, 2147483647, b'\x22', b'\x00', b'\x00', b'\xFF')
  assert_eq(image.get_pixel(2, 2).0, b'\x22')
  image.draw_circle(0, 0, 2147483647, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(image.get_pixel(2, 2).0, b'\x22')
  image.draw_text(0, 0, "X", 2147483647, b'\x33', b'\x00', b'\x00', b'\xFF')
  assert_eq(image.get_pixel(2, 2).0, b'\x33')
}
