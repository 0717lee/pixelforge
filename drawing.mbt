///|
/// Drawing primitives: Bresenham lines, rectangles and midpoint circles
/// (outline + filled). These mutate the image in place — like `set_pixel` —
/// so multiple primitives can be layered cheaply; every write is clipped
/// against the image bounds.

///|
/// Writes one RGBA pixel, silently skipping out-of-bounds coordinates so
/// callers never need to pre-clip.
fn Image::plot(
  self : Image,
  x : Int,
  y : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    return
  }
  self.set_pixel(x, y, r, g, b, a)
}

///|
/// Draws a straight line from `(x0, y0)` to `(x1, y1)` inclusive with the
/// classic integer-only Bresenham algorithm.
pub fn Image::draw_line(
  self : Image,
  x0 : Int,
  y0 : Int,
  x1 : Int,
  y1 : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  let dx = iabs(x1 - x0)
  let dy = -iabs(y1 - y0)
  let sx = if x0 < x1 { 1 } else { -1 }
  let sy = if y0 < y1 { 1 } else { -1 }
  let mut err = dx + dy
  let mut x = x0
  let mut y = y0
  while true {
    self.plot(x, y, r, g, b, a)
    if x == x1 && y == y1 {
      break
    }
    let e2 = err * 2
    if e2 >= dy {
      err = err + dy
      x = x + sx
    }
    if e2 <= dx {
      err = err + dx
      y = y + sy
    }
  }
}

///|
/// Draws the 1-pixel outline of the rectangle with top-left corner
/// `(x, y)` and the given size. Degenerate sizes (< 1) draw nothing.
pub fn Image::draw_rect(
  self : Image,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if w < 1 || h < 1 {
    return
  }
  for i in 0..<w {
    self.plot(x + i, y, r, g, b, a)
    self.plot(x + i, y + h - 1, r, g, b, a)
  }
  for j in 0..<h {
    self.plot(x, y + j, r, g, b, a)
    self.plot(x + w - 1, y + j, r, g, b, a)
  }
}

///|
/// Fills the rectangle with top-left corner `(x, y)` and the given size.
pub fn Image::fill_rect(
  self : Image,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  for j in 0..<h {
    for i in 0..<w {
      self.plot(x + i, y + j, r, g, b, a)
    }
  }
}

///|
/// Draws a circle outline centered at `(cx, cy)` using the midpoint circle
/// algorithm (integer-only, 8-way symmetric). `radius 0` plots one pixel;
/// negative radii draw nothing.
pub fn Image::draw_circle(
  self : Image,
  cx : Int,
  cy : Int,
  radius : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if radius < 0 {
    return
  }
  if radius == 0 {
    self.plot(cx, cy, r, g, b, a)
    return
  }
  let mut x = radius
  let mut y = 0
  let mut err = 1 - radius
  while x >= y {
    self.plot(cx + x, cy + y, r, g, b, a)
    self.plot(cx + y, cy + x, r, g, b, a)
    self.plot(cx - y, cy + x, r, g, b, a)
    self.plot(cx - x, cy + y, r, g, b, a)
    self.plot(cx - x, cy - y, r, g, b, a)
    self.plot(cx - y, cy - x, r, g, b, a)
    self.plot(cx + y, cy - x, r, g, b, a)
    self.plot(cx + x, cy - y, r, g, b, a)
    y = y + 1
    if err < 0 {
      err = err + 2 * y + 1
    } else {
      x = x - 1
      err = err + 2 * (y - x) + 1
    }
  }
}

///|
/// Fills the disk `dx^2 + dy^2 <= radius^2` centered at `(cx, cy)`.
pub fn Image::fill_circle(
  self : Image,
  cx : Int,
  cy : Int,
  radius : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if radius < 0 {
    return
  }
  let rr = radius * radius
  for dy in -radius..<(radius + 1) {
    for dx in -radius..<(radius + 1) {
      if dx * dx + dy * dy <= rr {
        self.plot(cx + dx, cy + dy, r, g, b, a)
      }
    }
  }
}
