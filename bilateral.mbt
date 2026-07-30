///|
/// Bilateral filter: edge-preserving smoothing. Each output pixel is a
/// normalized weighted average of its neighborhood where the weight is the
/// product of a spatial Gaussian (distance) and a range Gaussian (luma
/// difference) — flat regions are smoothed like a blur, while pixels
/// across a strong edge get near-zero weight and the edge stays sharp.

///|
/// Applies the bilateral filter with the given neighborhood `radius`,
/// spatial sigma (pixels) and range sigma (luma steps, 0..255 scale).
/// `radius <= 0` returns a copy; non-positive sigmas are clamped to a
/// small positive value. Alpha is preserved.
pub fn Image::bilateral(
  self : Image,
  radius : Int,
  sigma_space : Double,
  sigma_range : Double,
) -> Image {
  if radius <= 0 {
    return self.copy()
  }
  let r = if radius > 16 { 16 } else { radius }
  let ss = if sigma_space <= 0.0 { 0.1 } else { sigma_space }
  let sr = if sigma_range <= 0.0 { 0.1 } else { sigma_range }
  // Precompute the guide luma (integer BT.601 weights, like grayscale).
  let n = self.pixel_count()
  let luma : Array[Int] = Array::make(n, 0)
  for p in 0..<n {
    let base = p * 4
    luma[p] = (
        self.data[base].to_int() * 299 +
        self.data[base + 1].to_int() * 587 +
        self.data[base + 2].to_int() * 114
      ) /
      1000
  }
  // Spatial weights depend only on (dx, dy): precompute the (2r+1)^2 grid.
  let side = 2 * r + 1
  let spatial : Array[Double] = Array::make(side * side, 0.0)
  for dy in -r..<(r + 1) {
    for dx in -r..<(r + 1) {
      let d2 = (dx * dx + dy * dy).to_double()
      spatial[(dy + r) * side + (dx + r)] = @math.exp(-d2 / (2.0 * ss * ss))
    }
  }
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let center = luma[y * self.width + x]
      let mut wsum = 0.0
      let mut sr_acc = 0.0
      let mut sg_acc = 0.0
      let mut sb_acc = 0.0
      for dy in -r..<(r + 1) {
        for dx in -r..<(r + 1) {
          let sx = clamp_coord(x + dx, self.width)
          let sy = clamp_coord(y + dy, self.height)
          let q = sy * self.width + sx
          let dl = (luma[q] - center).to_double()
          let w = spatial[(dy + r) * side + (dx + r)] *
            @math.exp(-(dl * dl) / (2.0 * sr * sr))
          let base = q * 4
          wsum = wsum + w
          sr_acc = sr_acc + self.data[base].to_int().to_double() * w
          sg_acc = sg_acc + self.data[base + 1].to_int().to_double() * w
          sb_acc = sb_acc + self.data[base + 2].to_int().to_double() * w
        }
      }
      let base = (y * self.width + x) * 4
      out.data[base] = clamp_byte((sr_acc / wsum + 0.5).to_int())
      out.data[base + 1] = clamp_byte((sg_acc / wsum + 0.5).to_int())
      out.data[base + 2] = clamp_byte((sb_acc / wsum + 0.5).to_int())
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}
