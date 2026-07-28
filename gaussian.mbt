///|
/// Separable Gaussian blur with arbitrary radius.
///
/// Uses binomial-coefficient weights (`C(2r, k)`, the discrete Gaussian):
/// integer, exactly normalized by `4^r`, and separable — a horizontal then a
/// vertical 1D pass replace the O(k²) 2D convolution with O(2k) work per
/// pixel. At radius 1 the weights are `[1, 2, 1]`, the same kernel as
/// `Kernel::gaussian_blur()`.

///|
/// Builds the binomial weight row `C(2r, 0) .. C(2r, 2r)` via Pascal's rule.
fn binomial_weights(radius : Int) -> Array[Double] {
  let n = 2 * radius + 1
  let w : Array[Double] = Array::make(n, 1.0)
  for row in 1..<n {
    // In-place Pascal update, right to left.
    for k = row - 1; k >= 1; k = k - 1 {
      w[k] = w[k] + w[k - 1]
    }
  }
  w
}

///|
/// One 1D blur pass. `horizontal` selects the axis; out-of-bounds taps
/// clamp to the edge. RGB channels are blurred, alpha is preserved.
fn Image::blur_pass(
  self : Image,
  weights : Array[Double],
  norm : Double,
  horizontal : Bool,
) -> Image {
  let radius = weights.length() / 2
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let mut sr = 0.0
      let mut sg = 0.0
      let mut sb = 0.0
      for k in 0..<weights.length() {
        let off = k - radius
        let sx = if horizontal { clamp_coord(x + off, self.width) } else { x }
        let sy = if horizontal { y } else { clamp_coord(y + off, self.height) }
        let base = (sy * self.width + sx) * 4
        let w = weights[k]
        sr = sr + self.data[base].to_int().to_double() * w
        sg = sg + self.data[base + 1].to_int().to_double() * w
        sb = sb + self.data[base + 2].to_int().to_double() * w
      }
      let base = (y * self.width + x) * 4
      out.data[base] = clamp_byte((sr / norm + 0.5).to_int())
      out.data[base + 1] = clamp_byte((sg / norm + 0.5).to_int())
      out.data[base + 2] = clamp_byte((sb / norm + 0.5).to_int())
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// Gaussian blur with the given radius (clamped to `[0, 32]`; radius 0 is a
/// plain copy). Two separable binomial passes — for radius `r` this equals
/// convolving with the `(2r+1)²` discrete Gaussian, but costs O(r) per
/// pixel instead of O(r²).
pub fn Image::gaussian(self : Image, radius : Int) -> Image {
  if radius <= 0 {
    return self.copy()
  }
  let r = if radius > 32 { 32 } else { radius }
  let weights = binomial_weights(r)
  let mut norm = 1.0
  for _ in 0..<r {
    norm = norm * 4.0
  }
  self.blur_pass(weights, norm, true).blur_pass(weights, norm, false)
}
