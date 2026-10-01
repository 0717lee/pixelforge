///|
/// Drawing primitives: Bresenham lines, rectangles and midpoint circles
/// (outline + filled). These mutate the image in place — like `set_pixel` —
/// so multiple primitives can be layered cheaply; every write is clipped
/// against the image bounds.

///|
fn drawing_span(start : Int64, end : Int64, limit : Int) -> (Int, Int) {
  let bound = limit.to_int64()
  let lo = if start < 0 {
    0
  } else if start > bound {
    limit
  } else {
    start.to_int()
  }
  let hi = if end < 0 { 0 } else if end > bound { limit } else { end.to_int() }
  (lo, hi)
}

///|
fn Image::plot_wide(
  self : Image,
  x : Int64,
  y : Int64,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if x >= 0 && y >= 0 && x < self.width.to_int64() && y < self.height.to_int64() {
    self.set_pixel(x.to_int(), y.to_int(), r, g, b, a)
  }
}

///|
fn Image::fill_rect_wide(
  self : Image,
  x : Int64,
  y : Int64,
  w : Int64,
  h : Int64,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if w <= 0 || h <= 0 {
    return
  }
  let (x0, x1) = drawing_span(x, x + w, self.width)
  let (y0, y1) = drawing_span(y, y + h, self.height)
  for py in y0..<y1 {
    for px in x0..<x1 {
      self.set_pixel(px, py, r, g, b, a)
    }
  }
}

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
  let ax = x0.to_int64()
  let ay = y0.to_int64()
  let bx = x1.to_int64()
  let by = y1.to_int64()
  let sx = if ax < bx { 1L } else { -1L }
  let sy = if ay < by { 1L } else { -1L }
  let dx = (bx - ax) * sx
  let dy = (by - ay) * sy
  if dx == 0 && dy == 0 {
    self.plot(x0, y0, r, g, b, a)
    return
  }
  // Closed-form Bresenham positions preserve the original raster phase when
  // skipping off-canvas steps. UInt64 holds products of two 32-bit spans.
  if dx >= dy {
    let (lo, hi) = drawing_span(
      if ax < bx {
        ax
      } else {
        bx
      },
      (if ax > bx { ax } else { bx }) + 1,
      self.width,
    )
    for x in lo..<hi {
      let k = (x.to_int64() - ax) * sx
      let step = ((
        k.reinterpret_as_uint64() * dy.reinterpret_as_uint64() +
        (dx / 2).reinterpret_as_uint64()
      ) /
      dx.reinterpret_as_uint64()).reinterpret_as_int64()
      self.plot_wide(x.to_int64(), ay + sy * step, r, g, b, a)
    }
  } else {
    let (lo, hi) = drawing_span(
      if ay < by {
        ay
      } else {
        by
      },
      (if ay > by { ay } else { by }) + 1,
      self.height,
    )
    for y in lo..<hi {
      let k = (y.to_int64() - ay) * sy
      let step = ((
        k.reinterpret_as_uint64() * dx.reinterpret_as_uint64() +
        (dy / 2).reinterpret_as_uint64()
      ) /
      dy.reinterpret_as_uint64()).reinterpret_as_int64()
      self.plot_wide(ax + sx * step, y.to_int64(), r, g, b, a)
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
  let xx = x.to_int64()
  let yy = y.to_int64()
  let ww = w.to_int64()
  let hh = h.to_int64()
  self.fill_rect_wide(xx, yy, ww, 1, r, g, b, a)
  self.fill_rect_wide(xx, yy + hh - 1, ww, 1, r, g, b, a)
  self.fill_rect_wide(xx, yy, 1, hh, r, g, b, a)
  self.fill_rect_wide(xx + ww - 1, yy, 1, hh, r, g, b, a)
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
  self.fill_rect_wide(
    x.to_int64(),
    y.to_int64(),
    w.to_int64(),
    h.to_int64(),
    r,
    g,
    b,
    a,
  )
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
  let rr = radius.to_int64() * radius.to_int64()
  let xx = cx.to_int64()
  let yy = cy.to_int64()
  let rad = radius.to_int64()
  let (y0, y1) = drawing_span(yy - rad, yy + rad + 1, self.height)
  for y in y0..<y1 {
    let dy = y.to_int64() - yy
    let dx = circle_round_sqrt(rr - dy * dy)
    self.plot_wide(xx - dx, y.to_int64(), r, g, b, a)
    self.plot_wide(xx + dx, y.to_int64(), r, g, b, a)
  }
  let (x0, x1) = drawing_span(xx - rad, xx + rad + 1, self.width)
  for x in x0..<x1 {
    let dx = x.to_int64() - xx
    let dy = circle_round_sqrt(rr - dx * dx)
    self.plot_wide(x.to_int64(), yy - dy, r, g, b, a)
    self.plot_wide(x.to_int64(), yy + dy, r, g, b, a)
  }
}

///|
fn circle_round_sqrt(value : Int64) -> Int64 {
  let mut lo = 0L
  let mut hi = 2147483647L
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if mid * mid <= value {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  if value - lo * lo > lo {
    lo + 1
  } else {
    lo
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
  let rad = radius.to_int64()
  let rr = rad * rad
  let (x0, x1) = drawing_span(
    cx.to_int64() - rad,
    cx.to_int64() + rad + 1,
    self.width,
  )
  let (y0, y1) = drawing_span(
    cy.to_int64() - rad,
    cy.to_int64() + rad + 1,
    self.height,
  )
  for y in y0..<y1 {
    let dy = y.to_int64() - cy.to_int64()
    for x in x0..<x1 {
      let dx = x.to_int64() - cx.to_int64()
      if dx * dx + dy * dy <= rr {
        self.set_pixel(x, y, r, g, b, a)
      }
    }
  }
}
