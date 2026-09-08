///|
/// Deterministic image-quality metrics for comparing two RGBA images.
///
/// `mse` and `psnr` compare all four stored channels (R, G, B and A) with
/// equal weight. `luma_mse` and `ssim` use the integer Rec.601 luma
/// `floor((299R + 587G + 114B) / 1000)` and ignore alpha. All metrics require
/// equal image dimensions and abort on malformed backing buffers. Empty,
/// equal-sized images are supported: MSE is zero and SSIM is one.

///|
/// Checks the shape and backing-buffer invariants shared by all metrics.
fn metric_pixel_count(a : Image, b : Image) -> Int {
  if a.width != b.width || a.height != b.height {
    abort("image metrics require equal dimensions")
  }
  let expected = checked_buffer_len(a.width, a.height)
  if a.data.length() != expected || b.data.length() != expected {
    abort("image metrics require valid RGBA backing buffers")
  }
  expected / 4
}

///|
/// Mean squared error over all RGBA channels. The result is in channel-value
/// squared units, in the range `[0, 65025]` for valid 8-bit images.
pub fn Image::mse(self : Image, other : Image) -> Double {
  let n = metric_pixel_count(self, other)
  if n == 0 {
    return 0.0
  }
  let mut sum = 0L
  for p in 0..<n {
    let base = p * 4
    for c in 0..<4 {
      let delta = self.data[base + c].to_int() - other.data[base + c].to_int()
      let d = delta.to_int64()
      sum = sum + d * d
    }
  }
  sum.to_double() / (n * 4).to_double()
}

///|
/// Peak signal-to-noise ratio in decibels, derived from RGBA `mse` with a
/// peak channel value of 255. Identical images return positive infinity.
pub fn Image::psnr(self : Image, other : Image) -> Double {
  let error = self.mse(other)
  if error == 0.0 {
    return @double.infinity
  }
  10.0 * @math.log10(65025.0 / error)
}

///|
/// Mean squared error over Rec.601 luma only. Alpha is intentionally ignored.
pub fn Image::luma_mse(self : Image, other : Image) -> Double {
  let n = metric_pixel_count(self, other)
  if n == 0 {
    return 0.0
  }
  let mut sum = 0L
  for p in 0..<n {
    let base = p * 4
    let la = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
    let lb = (
        299 * other.data[base].to_int() +
        587 * other.data[base + 1].to_int() +
        114 * other.data[base + 2].to_int()
      ) /
      1000
    let d = (la - lb).to_int64()
    sum = sum + d * d
  }
  sum.to_double() / n.to_double()
}

///|
/// Global structural similarity (SSIM) over Rec.601 luma.
///
/// This implementation uses one population-statistics window covering the
/// complete image (there is no sliding-window padding or border policy), and
/// the standard constants `K1 = 0.01`, `K2 = 0.03`, `L = 255`. Alpha is
/// ignored. The result is clamped to `[-1, 1]` to absorb tiny floating-point
/// overshoots at the theoretical bounds.
pub fn Image::ssim(self : Image, other : Image) -> Double {
  let n = metric_pixel_count(self, other)
  if n == 0 {
    return 1.0
  }
  let mut sum_a = 0L
  let mut sum_b = 0L
  let mut sum_aa = 0L
  let mut sum_bb = 0L
  let mut sum_ab = 0L
  for p in 0..<n {
    let base = p * 4
    let a = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
    let b = (
        299 * other.data[base].to_int() +
        587 * other.data[base + 1].to_int() +
        114 * other.data[base + 2].to_int()
      ) /
      1000
    let ai = a.to_int64()
    let bi = b.to_int64()
    sum_a = sum_a + ai
    sum_b = sum_b + bi
    sum_aa = sum_aa + ai * ai
    sum_bb = sum_bb + bi * bi
    sum_ab = sum_ab + ai * bi
  }
  let count = n.to_double()
  let mean_a = sum_a.to_double() / count
  let mean_b = sum_b.to_double() / count
  let mut variance_a = sum_aa.to_double() / count - mean_a * mean_a
  let mut variance_b = sum_bb.to_double() / count - mean_b * mean_b
  let covariance = sum_ab.to_double() / count - mean_a * mean_b
  // Rounding can make the variance of a constant image a tiny negative value.
  if variance_a < 0.0 {
    variance_a = 0.0
  }
  if variance_b < 0.0 {
    variance_b = 0.0
  }
  let c1 = 6.5025 // (0.01 * 255)^2
  let c2 = 58.5225 // (0.03 * 255)^2
  let numerator = (2.0 * mean_a * mean_b + c1) * (2.0 * covariance + c2)
  let denominator = (mean_a * mean_a + mean_b * mean_b + c1) *
    (variance_a + variance_b + c2)
  let value = numerator / denominator
  if value < -1.0 {
    -1.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}
