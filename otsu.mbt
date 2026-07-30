///|
/// Otsu's method: computes a global luma threshold automatically by choosing
/// the value that maximizes the between-class variance of the two pixel
/// groups it splits the histogram into. The whole search is integer/rational
/// (no floating point), so the chosen threshold is exactly reproducible.

///|
/// Builds the 256-bin luma histogram (BT.601 integer weights).
fn Image::luma_histogram(self : Image) -> FixedArray[Int] {
  let hist = FixedArray::make(256, 0)
  let n = self.pixel_count()
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
  hist
}

///|
/// Returns the Otsu threshold in `0..255`: pixels with luma strictly greater
/// than the returned value are the "foreground" class. Chooses the `t` that
/// maximizes the between-class variance `wB*wF*(mB-mF)^2`. Variance is
/// accumulated in `Double` (the textbook formulation) to stay correct on
/// large images where an all-integer product would overflow.
pub fn Image::otsu_threshold(self : Image) -> Int {
  let hist = self.luma_histogram()
  let total = self.pixel_count()
  if total == 0 {
    return 0
  }
  // Total weighted intensity sum (Double to avoid overflow on big images).
  let mut sum_all = 0.0
  for i in 0..<256 {
    sum_all = sum_all + (i * hist[i]).to_double()
  }
  let mut w_b = 0 // count of the background class (luma <= t)
  let mut sum_b = 0.0 // weighted intensity sum of the background class
  let mut best_t = 0
  let mut best_var = -1.0
  for t in 0..<256 {
    w_b = w_b + hist[t]
    if w_b == 0 {
      continue
    }
    let w_f = total - w_b
    if w_f == 0 {
      break
    }
    sum_b = sum_b + (t * hist[t]).to_double()
    let mean_b = sum_b / w_b.to_double()
    let mean_f = (sum_all - sum_b) / w_f.to_double()
    let diff = mean_b - mean_f
    let between = w_b.to_double() * w_f.to_double() * diff * diff
    if between > best_var {
      best_var = between
      best_t = t
    }
  }
  best_t
}

///|
/// Applies Otsu's automatic threshold, returning a binary (black/white)
/// grayscale image. Pixels with luma greater than the computed threshold
/// become white.
pub fn Image::otsu(self : Image) -> Image {
  let t = self.otsu_threshold()
  self.map_rgb(fn(r, g, b) {
    let y = (299 * r + 587 * g + 114 * b) / 1000
    let v = if y > t { 255 } else { 0 }
    (v, v, v)
  })
}
