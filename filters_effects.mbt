///|
/// Gamma correction through a 256-entry lookup table:
/// `out = 255 * (c / 255) ^ (1 / value)`. `value > 1` lifts midtones,
/// `0 < value < 1` deepens them, and `1.0` is an exact identity. A
/// non-positive `value` falls back to the identity.
pub fn Image::gamma(self : Image, value : Double) -> Image {
  let g = if value <= 0.0 { 1.0 } else { value }
  let inv = 1.0 / g
  let lut = FixedArray::make(256, 0)
  for i in 0..<256 {
    let normalized = i.to_double() / 255.0
    lut[i] = (@math.pow(normalized, inv) * 255.0 + 0.5).to_int()
  }
  self.map_rgb(fn(r, g, b) { (lut[r], lut[g], lut[b]) })
}

///|
/// Vignette: darkens pixels toward the corners while leaving the geometric
/// center untouched. `strength` in `[0, 1]` is the fraction of light removed
/// at the far corners; the falloff follows the squared distance from center.
pub fn Image::vignette(self : Image, strength : Double) -> Image {
  let s = if strength < 0.0 {
    0.0
  } else if strength > 1.0 {
    1.0
  } else {
    strength
  }
  let out = self.copy()
  let cx = (self.width - 1).to_double() / 2.0
  let cy = (self.height - 1).to_double() / 2.0
  let max_d2 = cx * cx + cy * cy
  if max_d2 <= 0.0 {
    return out
  }
  for y in 0..<self.height {
    for x in 0..<self.width {
      let dx = x.to_double() - cx
      let dy = y.to_double() - cy
      let factor = 1.0 - s * (dx * dx + dy * dy) / max_d2
      let base = (y * self.width + x) * 4
      out.data[base] = clamp_byte(
        (out.data[base].to_int().to_double() * factor + 0.5).to_int(),
      )
      out.data[base + 1] = clamp_byte(
        (out.data[base + 1].to_int().to_double() * factor + 0.5).to_int(),
      )
      out.data[base + 2] = clamp_byte(
        (out.data[base + 2].to_int().to_double() * factor + 0.5).to_int(),
      )
    }
  }
  out
}
