///|
/// Horizontal mirror: `dst(x, y) = src(width-1-x, y)`. Each pixel's four
/// channels travel together, so alpha is preserved per pixel.
pub fn Image::flip_horizontal(self : Image) -> Image {
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let src = (y * self.width + (self.width - 1 - x)) * 4
      let dst = (y * self.width + x) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}

///|
/// Vertical mirror: `dst(x, y) = src(x, height-1-y)`.
pub fn Image::flip_vertical(self : Image) -> Image {
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let src = ((self.height - 1 - y) * self.width + x) * 4
      let dst = (y * self.width + x) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}

///|
/// Rotates the image 90° clockwise. The result is `height x width`, so this
/// is a library-level transform and is intentionally not exposed through the
/// fixed-size `apply_filter_id` dispatch.
pub fn Image::rotate90(self : Image) -> Image {
  let out = Image::new(self.height, self.width)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let nx = self.height - 1 - y
      let ny = x
      let src = (y * self.width + x) * 4
      let dst = (ny * out.width + nx) * 4
      out.data[dst] = self.data[src]
      out.data[dst + 1] = self.data[src + 1]
      out.data[dst + 2] = self.data[src + 2]
      out.data[dst + 3] = self.data[src + 3]
    }
  }
  out
}
