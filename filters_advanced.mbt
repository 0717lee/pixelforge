///|
/// Smaller of two integers, kept local so the block/window filters stay
/// dependency-free.
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Sepia tone: the classic warm photographic look, using the widely used
/// Microsoft sepia coefficients scaled by 1000 for exact integer math.
pub fn Image::sepia(self : Image) -> Image {
  self.map_rgb(fn(r, g, b) {
    let nr = (393 * r + 769 * g + 189 * b) / 1000
    let ng = (349 * r + 686 * g + 168 * b) / 1000
    let nb = (272 * r + 534 * g + 131 * b) / 1000
    (nr, ng, nb)
  })
}

///|
/// Binary threshold: pixels whose luma is at least `level` become white, the
/// rest black. Useful for masks and high-contrast stylization.
pub fn Image::threshold(self : Image, level : Int) -> Image {
  self.map_rgb(fn(r, g, b) {
    let y = (299 * r + 587 * g + 114 * b) / 1000
    let v = if y >= level { 255 } else { 0 }
    (v, v, v)
  })
}

///|
/// Pixelate (mosaic): replaces each `block` x `block` tile with its average
/// color. Edge tiles are clipped to the image bounds.
pub fn Image::pixelate(self : Image, block : Int) -> Image {
  let size = if block < 1 { 1 } else { block }
  let out = Image::new(self.width, self.height)
  let blocks_y = (self.height + size - 1) / size
  let blocks_x = (self.width + size - 1) / size
  for byi in 0..<blocks_y {
    for bxi in 0..<blocks_x {
      let y0 = byi * size
      let x0 = bxi * size
      let y1 = imin(y0 + size, self.height)
      let x1 = imin(x0 + size, self.width)
      let mut sr = 0
      let mut sg = 0
      let mut sb = 0
      let mut count = 0
      for y in y0..<y1 {
        for x in x0..<x1 {
          let base = (y * self.width + x) * 4
          sr = sr + self.data[base].to_int()
          sg = sg + self.data[base + 1].to_int()
          sb = sb + self.data[base + 2].to_int()
          count = count + 1
        }
      }
      let ar = clamp_byte(sr / count)
      let ag = clamp_byte(sg / count)
      let ab = clamp_byte(sb / count)
      for y in y0..<y1 {
        for x in x0..<x1 {
          let base = (y * self.width + x) * 4
          out.data[base] = ar
          out.data[base + 1] = ag
          out.data[base + 2] = ab
          out.data[base + 3] = self.data[base + 3]
        }
      }
    }
  }
  out
}

///|
/// Median of the 3x3 neighborhood for one channel, via a tiny insertion sort.
/// The median is robust to outliers, which is what makes it good at removing
/// salt-and-pepper noise without the blurring a mean filter causes.
fn median_channel(img : Image, x : Int, y : Int, ch : Int) -> Byte {
  let vals = FixedArray::make(9, 0)
  let mut k = 0
  for dy in -1..<2 {
    for dx in -1..<2 {
      let sx = clamp_coord(x + dx, img.width)
      let sy = clamp_coord(y + dy, img.height)
      vals[k] = img.data[(sy * img.width + sx) * 4 + ch].to_int()
      k = k + 1
    }
  }
  for i in 1..<9 {
    let v = vals[i]
    let mut j = i - 1
    while j >= 0 && vals[j] > v {
      vals[j + 1] = vals[j]
      j = j - 1
    }
    vals[j + 1] = v
  }
  clamp_byte(vals[4])
}

///|
/// 3x3 median filter applied independently to R, G and B; alpha is preserved.
pub fn Image::median(self : Image) -> Image {
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let base = (y * self.width + x) * 4
      out.data[base] = median_channel(self, x, y, 0)
      out.data[base + 1] = median_channel(self, x, y, 1)
      out.data[base + 2] = median_channel(self, x, y, 2)
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// Histogram equalization on luma: spreads the tonal range to maximize global
/// contrast. Builds the luma histogram, integrates it into a CDF, then remaps
/// every pixel through the normalized CDF. Output is grayscale.
pub fn Image::histogram_equalize(self : Image) -> Image {
  let n = self.pixel_count()
  let hist = FixedArray::make(256, 0)
  for p in 0..<n {
    let base = p * 4
    let y = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
    hist[y] = hist[y] + 1
  }
  let cdf = FixedArray::make(256, 0)
  let mut acc = 0
  for i in 0..<256 {
    acc = acc + hist[i]
    cdf[i] = acc
  }
  let mut cdf_min = 0
  for i in 0..<256 {
    if cdf[i] != 0 {
      cdf_min = cdf[i]
      break
    }
  }
  let denom = n - cdf_min
  let lut = FixedArray::make(256, 0)
  for i in 0..<256 {
    lut[i] = if denom <= 0 { i } else { (cdf[i] - cdf_min) * 255 / denom }
  }
  self.map_rgb(fn(r, g, b) {
    let y = (299 * r + 587 * g + 114 * b) / 1000
    let e = lut[y]
    (e, e, e)
  })
}
