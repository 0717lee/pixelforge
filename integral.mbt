///|
/// Summed-area table (integral image) and a constant-time box blur built on
/// it. The SAT stores, at `(x, y)`, the sum of all pixels in the rectangle
/// from the origin to `(x, y)` inclusive, so any axis-aligned rectangle sum
/// is four table lookups regardless of size — making the mean filter O(1)
/// per pixel for any radius. Sums use `Int64` so large images never overflow.

///|
/// A summed-area table for one image: `(width+1) x (height+1)` per channel,
/// with a zero first row/column so rectangle queries need no bounds checks.
pub(all) struct Integral {
  width : Int
  height : Int
  // Channel-major: sat[c] is a (w+1)*(h+1) prefix-sum plane.
  sat : Array[Int64]
}

///|
/// Builds the summed-area table over the R, G and B channels.
pub fn Image::integral_image(self : Image) -> Integral {
  let w = self.width
  let h = self.height
  let stride = w + 1
  let plane = stride * (h + 1)
  let sat = Array::make(plane * 3, 0L)
  for c in 0..<3 {
    let off = c * plane
    for y in 1..<(h + 1) {
      let mut row_sum = 0L
      for x in 1..<(w + 1) {
        let px = self.data[((y - 1) * w + (x - 1)) * 4 + c].to_int().to_int64()
        row_sum = row_sum + px
        sat[off + y * stride + x] = sat[off + (y - 1) * stride + x] + row_sum
      }
    }
  }
  { width: w, height: h, sat }
}

///|
/// Sum of channel `c` over the inclusive rectangle `[x0, x1] x [y0, y1]`
/// (0-based pixel coordinates). Uses the standard four-corner SAT formula.
pub fn Integral::rect_sum(
  self : Integral,
  c : Int,
  x0 : Int,
  y0 : Int,
  x1 : Int,
  y1 : Int,
) -> Int64 {
  let stride = self.width + 1
  let off = c * stride * (self.height + 1)
  // Convert inclusive pixel coords to SAT (shifted by +1) corners.
  let a = off + y0 * stride + x0
  let b = off + y0 * stride + (x1 + 1)
  let cc = off + (y1 + 1) * stride + x0
  let d = off + (y1 + 1) * stride + (x1 + 1)
  self.sat[d] - self.sat[b] - self.sat[cc] + self.sat[a]
}

///|
/// Box blur (uniform mean) of the given `radius` using the integral image,
/// so each output pixel costs a constant number of lookups no matter how
/// large the window. `radius <= 0` returns a copy; the window is clamped to
/// the image at the borders. Alpha is preserved.
pub fn Image::box_blur(self : Image, radius : Int) -> Image {
  if radius <= 0 {
    return self.copy()
  }
  let w = self.width
  let h = self.height
  let sat = self.integral_image()
  let out = Image::new(w, h)
  for y in 0..<h {
    let y0 = if y - radius < 0 { 0 } else { y - radius }
    let y1 = if y + radius >= h { h - 1 } else { y + radius }
    for x in 0..<w {
      let x0 = if x - radius < 0 { 0 } else { x - radius }
      let x1 = if x + radius >= w { w - 1 } else { x + radius }
      let count = ((x1 - x0 + 1) * (y1 - y0 + 1)).to_int64()
      let base = (y * w + x) * 4
      for c in 0..<3 {
        let s = sat.rect_sum(c, x0, y0, x1, y1)
        // Rounded mean: (s + count/2) / count.
        out.data[base + c] = clamp_byte(((s + count / 2L) / count).to_int())
      }
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}
