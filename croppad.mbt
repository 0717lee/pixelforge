///|
/// Cropping and padding: the two size-changing operations that book-end most
/// pipelines. Both work on whole pixels and preserve every channel exactly,
/// so `crop` after a matching `pad` round-trips an image bit-for-bit.

///|
/// Extracts the `w` x `h` rectangle whose top-left corner is `(x, y)`. The
/// requested rectangle is clamped to the source bounds, so the result is
/// never larger than the overlap with the image; out-of-range or empty
/// requests yield a 1x1 transparent image. Pixels are copied verbatim.
pub fn Image::crop(self : Image, x : Int, y : Int, w : Int, h : Int) -> Image {
  if w <= 0 || h <= 0 {
    return Image::new(1, 1)
  }
  // Clamp the rectangle to the image.
  let x0 = if x < 0 { 0 } else if x > self.width { self.width } else { x }
  let y0 = if y < 0 { 0 } else if y > self.height { self.height } else { y }
  let x1_raw = x.to_int64() + w.to_int64()
  let y1_raw = y.to_int64() + h.to_int64()
  let x1 = if x1_raw < x0.to_int64() {
    x0
  } else if x1_raw > self.width.to_int64() {
    self.width
  } else {
    x1_raw.to_int()
  }
  let y1 = if y1_raw < y0.to_int64() {
    y0
  } else if y1_raw > self.height.to_int64() {
    self.height
  } else {
    y1_raw.to_int()
  }
  let cw = x1 - x0
  let ch = y1 - y0
  if cw <= 0 || ch <= 0 {
    return Image::new(1, 1) // empty selection -> 1x1 transparent
  }
  let out = Image::new(cw, ch)
  for row in 0..<ch {
    for col in 0..<cw {
      let src = ((y0 + row) * self.width + (x0 + col)) * 4
      let dst = (row * cw + col) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}

///|
/// Surrounds the image with borders of the given thickness (in pixels),
/// filled with the color `(r, g, b, a)`. Negative border widths are treated
/// as zero. The result is `(left+width+right) x (top+height+bottom)`.
/// Aborts if a resulting dimension exceeds Int range or the image pixel limit.
pub fn Image::pad(
  self : Image,
  left : Int,
  top : Int,
  right : Int,
  bottom : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Image {
  let l = if left < 0 { 0 } else { left }
  let t = if top < 0 { 0 } else { top }
  let ri = if right < 0 { 0 } else { right }
  let bo = if bottom < 0 { 0 } else { bottom }
  let wide_width = l.to_int64() + self.width.to_int64() + ri.to_int64()
  let wide_height = t.to_int64() + self.height.to_int64() + bo.to_int64()
  if wide_width > 2147483647L || wide_height > 2147483647L {
    abort("Image::pad: dimensions exceed Int range")
  }
  let nw = wide_width.to_int()
  let nh = wide_height.to_int()
  let out = Image::new(nw, nh)
  // Fill everything with the border color first.
  for p in 0..<(nw * nh) {
    let base = p * 4
    out.data[base] = r
    out.data[base + 1] = g
    out.data[base + 2] = b
    out.data[base + 3] = a
  }
  // Blit the original into place.
  for y in 0..<self.height {
    for x in 0..<self.width {
      let src = (y * self.width + x) * 4
      let dst = ((t + y) * nw + (l + x)) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}
