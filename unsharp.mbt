///|
/// Unsharp masking: the standard photographic sharpen. A blurred copy is
/// subtracted from the original to isolate high-frequency detail, which is
/// then added back scaled by `amount`. Because it reuses the separable
/// Gaussian, the blur radius controls the scale of the detail enhanced.

///|
/// Sharpens via `out = original + amount * (original - gaussian(radius))`.
/// `radius` selects the detail scale (>= 1; 0 makes the mask empty and thus
/// returns a copy); `amount` scales the enhancement (`amount <= 0` returns a
/// copy). Per-channel result is clamped to `[0, 255]`; alpha is preserved.
pub fn Image::unsharp_mask(
  self : Image,
  radius : Int,
  amount : Double,
) -> Image {
  if radius <= 0 || amount <= 0.0 {
    return self.copy()
  }
  let blurred = self.gaussian(radius)
  let out = Image::new(self.width, self.height)
  let n = self.pixel_count()
  for p in 0..<n {
    let base = p * 4
    for c in 0..<3 {
      let orig = self.data[base + c].to_int()
      let low = blurred.data[base + c].to_int()
      // high-frequency detail = orig - low; add it back, scaled.
      let sharp = orig.to_double() + amount * (orig - low).to_double()
      out.data[base + c] = clamp_byte((sharp + 0.5).to_int())
    }
    out.data[base + 3] = self.data[base + 3]
  }
  out
}
