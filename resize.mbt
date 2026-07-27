///|
/// Floor for `Double` that is also correct for negative inputs (`to_int`
/// truncates toward zero, which would round the wrong way below 0).
fn ifloor(v : Double) -> Int {
  let t = v.to_int()
  if t.to_double() > v {
    t - 1
  } else {
    t
  }
}

///|
/// Nearest-neighbor resize: picks the closest source pixel. Fast and exact,
/// ideal for pixel-art style scaling. Output is `new_width` x `new_height`
/// (both clamped to at least 1).
pub fn Image::resize_nearest(
  self : Image,
  new_width : Int,
  new_height : Int,
) -> Image {
  let w = if new_width < 1 { 1 } else { new_width }
  let h = if new_height < 1 { 1 } else { new_height }
  let out = Image::new(w, h)
  for y in 0..<h {
    for x in 0..<w {
      let src = (y * self.height / h * self.width + x * self.width / w) * 4
      let dst = (y * w + x) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}

///|
/// Bilinear resize: blends the four surrounding source pixels by coverage,
/// using center-aligned sampling with clamp-to-edge, which keeps a same-size
/// resize an exact identity. All four channels (including alpha) are blended.
pub fn Image::resize_bilinear(
  self : Image,
  new_width : Int,
  new_height : Int,
) -> Image {
  let w = if new_width < 1 { 1 } else { new_width }
  let h = if new_height < 1 { 1 } else { new_height }
  let out = Image::new(w, h)
  for y in 0..<h {
    let fy = (y.to_double() + 0.5) * self.height.to_double() / h.to_double() -
      0.5
    let y0 = ifloor(fy)
    let dy = fy - y0.to_double()
    let sy0 = clamp_coord(y0, self.height)
    let sy1 = clamp_coord(y0 + 1, self.height)
    for x in 0..<w {
      let fx = (x.to_double() + 0.5) * self.width.to_double() / w.to_double() -
        0.5
      let x0 = ifloor(fx)
      let dx = fx - x0.to_double()
      let sx0 = clamp_coord(x0, self.width)
      let sx1 = clamp_coord(x0 + 1, self.width)
      let dst = (y * w + x) * 4
      for c in 0..<4 {
        let p00 = self.data[(sy0 * self.width + sx0) * 4 + c]
          .to_int()
          .to_double()
        let p10 = self.data[(sy0 * self.width + sx1) * 4 + c]
          .to_int()
          .to_double()
        let p01 = self.data[(sy1 * self.width + sx0) * 4 + c]
          .to_int()
          .to_double()
        let p11 = self.data[(sy1 * self.width + sx1) * 4 + c]
          .to_int()
          .to_double()
        let top = p00 * (1.0 - dx) + p10 * dx
        let bottom = p01 * (1.0 - dx) + p11 * dx
        out.data[dst + c] = clamp_byte(
          (top * (1.0 - dy) + bottom * dy + 0.5).to_int(),
        )
      }
    }
  }
  out
}
