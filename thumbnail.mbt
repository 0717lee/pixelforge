///|
/// Fits an image inside the given bounds without cropping or enlarging it.
/// Uses alpha-weighted bilinear sampling and preserves the aspect ratio to integer-pixel
/// precision: the shorter dimension is rounded down, with a minimum of one.
/// Bounds are clamped to at least one. Empty images retain their dimensions.
/// Always returns an independent buffer, including when no resize is needed.
pub fn Image::thumbnail(
  self : Image,
  max_width : Int,
  max_height : Int,
) -> Image {
  if self.width == 0 || self.height == 0 {
    return self.copy()
  }
  let w = if max_width < 1 { 1 } else { max_width }
  let h = if max_height < 1 { 1 } else { max_height }
  if self.width <= w && self.height <= h {
    return self.copy()
  }
  // Compare scale ratios using wide integers, avoiding overflow for long
  // images and large bounds without relying on floating-point rounding.
  if w.to_int64() * self.height.to_int64() <=
    h.to_int64() * self.width.to_int64() {
    let scaled_height = (self.height.to_int64() *
    w.to_int64() /
    self.width.to_int64()).to_int()
    self.resize_bilinear(
      w,
      if scaled_height < 1 {
        1
      } else {
        scaled_height
      },
      alpha_weighted=true,
    )
  } else {
    let scaled_width = (self.width.to_int64() *
    h.to_int64() /
    self.height.to_int64()).to_int()
    self.resize_bilinear(
      if scaled_width < 1 {
        1
      } else {
        scaled_width
      },
      h,
      alpha_weighted=true,
    )
  }
}
