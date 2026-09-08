///|
/// Local adaptive thresholding based on the integer BT.601 luma channel.
///
/// The window around each pixel is clipped to the image bounds, so pixels at
/// an edge use the smaller rectangle that is actually available.  Results
/// are binary grayscale pixels (0 or 255); alpha is copied unchanged.

///|
/// Builds summed-area tables for luma and luma squared.  Luma is kept as an
/// integer in `0..255`; the largest possible square sum for a 100 MP image
/// still fits in Int64.
fn Image::adaptive_prefix(self : Image) -> (Array[Int64], Array[Int64]) {
  let w = self.width
  let h = self.height
  let stride = w + 1
  let plane = stride * (h + 1)
  let sums = Array::make(plane, 0L)
  let squares = Array::make(plane, 0L)
  for y in 1..<(h + 1) {
    let mut row_sum = 0L
    let mut row_square = 0L
    for x in 1..<(w + 1) {
      let base = ((y - 1) * w + (x - 1)) * 4
      let r = self.data[base].to_int()
      let g = self.data[base + 1].to_int()
      let b = self.data[base + 2].to_int()
      let l = (299 * r + 587 * g + 114 * b) / 1000
      let ll = l.to_int64()
      row_sum = row_sum + ll
      row_square = row_square + ll * ll
      let i = y * stride + x
      sums[i] = sums[(y - 1) * stride + x] + row_sum
      squares[i] = squares[(y - 1) * stride + x] + row_square
    }
  }
  (sums, squares)
}

///|
/// Returns the sum over an inclusive rectangle in a summed-area table.
fn adaptive_rect_sum(
  sat : Array[Int64],
  stride : Int,
  x0 : Int,
  y0 : Int,
  x1 : Int,
  y1 : Int,
) -> Int64 {
  let a = y0 * stride + x0
  let b = y0 * stride + x1 + 1
  let c = (y1 + 1) * stride + x0
  let d = (y1 + 1) * stride + x1 + 1
  sat[d] - sat[b] - sat[c] + sat[a]
}

///|
/// Applies Sauvola local thresholding.
///
/// `radius` defines a square window of `(2 * radius + 1)` pixels.  Nonpositive
/// radii use the single pixel at the current coordinate.  `k` is clamped to
/// `[0, 1]`, and nonpositive `dynamic_range` uses `1`; the latter keeps invalid
/// host input deterministic instead of dividing by zero.  The threshold is
/// `mean * (1 + k * (stddev / dynamic_range - 1))`.
pub fn Image::sauvola(
  self : Image,
  radius : Int,
  k : Double,
  dynamic_range : Int,
) -> Image {
  let w = self.width
  let h = self.height
  let out = self.copy()
  let n = self.pixel_count()
  if n == 0 {
    return out
  }
  let r = if radius < 0 { 0 } else { radius }
  let k0 = if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }
  let dynamic = if dynamic_range <= 0 { 1 } else { dynamic_range }
  let dynamic_d = dynamic.to_double()
  let (sums, squares) = self.adaptive_prefix()
  let stride = w + 1
  for y in 0..<h {
    let y0 = if y < r { 0 } else { y - r }
    let y1 = if r >= h - y - 1 { h - 1 } else { y + r }
    for x in 0..<w {
      let x0 = if x < r { 0 } else { x - r }
      let x1 = if r >= w - x - 1 { w - 1 } else { x + r }
      let count = ((x1 - x0 + 1) * (y1 - y0 + 1)).to_int64()
      let mean = adaptive_rect_sum(sums, stride, x0, y0, x1, y1).to_double() /
        count.to_double()
      let second = adaptive_rect_sum(squares, stride, x0, y0, x1, y1).to_double() /
        count.to_double()
      let variance = if second > mean * mean { second - mean * mean } else { 0.0 }
      let stddev = variance.sqrt()
      let threshold = mean * (1.0 + k0 * (stddev / dynamic_d - 1.0))
      let base = (y * w + x) * 4
      let r0 = self.data[base].to_int()
      let g0 = self.data[base + 1].to_int()
      let b0 = self.data[base + 2].to_int()
      let l = (299 * r0 + 587 * g0 + 114 * b0) / 1000
      let value : Byte = if l.to_double() > threshold { b'\xFF' } else { b'\x00' }
      out.data[base] = value
      out.data[base + 1] = value
      out.data[base + 2] = value
    }
  }
  out
}

///|
/// Applies a local mean threshold.  `bias` is subtracted from the local
/// mean, so a positive bias makes foreground detection more permissive.
/// It is clamped to `[-255, 255]`, the useful luma range, to keep extreme
/// host values deterministic. Window clipping and alpha handling match
/// `sauvola`.
pub fn Image::adaptive_mean(self : Image, radius : Int, bias : Int) -> Image {
  let w = self.width
  let h = self.height
  let out = self.copy()
  let n = self.pixel_count()
  if n == 0 {
    return out
  }
  let r = if radius < 0 { 0 } else { radius }
  let bias0 = if bias < -255 { -255 } else if bias > 255 { 255 } else { bias }
  let (sums, _) = self.adaptive_prefix()
  let stride = w + 1
  for y in 0..<h {
    let y0 = if y < r { 0 } else { y - r }
    let y1 = if r >= h - y - 1 { h - 1 } else { y + r }
    for x in 0..<w {
      let x0 = if x < r { 0 } else { x - r }
      let x1 = if r >= w - x - 1 { w - 1 } else { x + r }
      let count = ((x1 - x0 + 1) * (y1 - y0 + 1)).to_int64()
      let sum = adaptive_rect_sum(sums, stride, x0, y0, x1, y1)
      let mean = ((sum + count / 2L) / count).to_int()
      let threshold = mean - bias0
      let base = (y * w + x) * 4
      let r0 = self.data[base].to_int()
      let g0 = self.data[base + 1].to_int()
      let b0 = self.data[base + 2].to_int()
      let l = (299 * r0 + 587 * g0 + 114 * b0) / 1000
      let value : Byte = if l > threshold { b'\xFF' } else { b'\x00' }
      out.data[base] = value
      out.data[base + 1] = value
      out.data[base + 2] = value
    }
  }
  out
}
