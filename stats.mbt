///|
/// Image statistics and tonal adjustments. `stats` summarizes the image
/// (per-channel range and mean plus a luma mean) with exact integer
/// accumulation; `auto_contrast` and `levels` are the two most common tonal
/// remaps built on top of it. All brightness math stays integer except the
/// optional gamma exponent, which uses `@math.pow`.

///|
/// Per-channel and luma summary of an image. Means are rounded to the
/// nearest integer. The fields are read-only (`pub`): the struct is a
/// result type, so keeping construction internal lets it gain fields later
/// without breaking downstream code.
pub struct Stats {
  min_r : Int
  max_r : Int
  mean_r : Int
  min_g : Int
  max_g : Int
  mean_g : Int
  min_b : Int
  max_b : Int
  mean_b : Int
  luma_min : Int
  luma_max : Int
  luma_mean : Int
}

///|
/// Computes per-channel min/max/mean and the luma min/max/mean over all
/// pixels. For the maximum 100-megapixel image the largest channel sum is
/// `255 * 1e8 ~= 2.55e10`, which exceeds 32-bit range, so the accumulators
/// are `Int64`.
pub fn Image::stats(self : Image) -> Stats {
  let n = self.pixel_count()
  // Degenerate (empty) image: return an all-zero, self-consistent summary
  // instead of the sentinel min=255 / max=0 the scan would otherwise leave.
  if n == 0 {
    return {
      min_r: 0,
      max_r: 0,
      mean_r: 0,
      min_g: 0,
      max_g: 0,
      mean_g: 0,
      min_b: 0,
      max_b: 0,
      mean_b: 0,
      luma_min: 0,
      luma_max: 0,
      luma_mean: 0,
    }
  }
  let mut mnr = 255
  let mut mxr = 0
  let mut mng = 255
  let mut mxg = 0
  let mut mnb = 255
  let mut mxb = 0
  let mut mnl = 255
  let mut mxl = 0
  let mut sr = 0L
  let mut sg = 0L
  let mut sb = 0L
  let mut sl = 0L
  for p in 0..<n {
    let base = p * 4
    let r = self.data[base].to_int()
    let g = self.data[base + 1].to_int()
    let b = self.data[base + 2].to_int()
    let l = (299 * r + 587 * g + 114 * b) / 1000
    if r < mnr {
      mnr = r
    }
    if r > mxr {
      mxr = r
    }
    if g < mng {
      mng = g
    }
    if g > mxg {
      mxg = g
    }
    if b < mnb {
      mnb = b
    }
    if b > mxb {
      mxb = b
    }
    if l < mnl {
      mnl = l
    }
    if l > mxl {
      mxl = l
    }
    sr = sr + r.to_int64()
    sg = sg + g.to_int64()
    sb = sb + b.to_int64()
    sl = sl + l.to_int64()
  }
  let denom = if n == 0 { 1L } else { n.to_int64() }
  let mean = fn(s : Int64) -> Int { ((s + denom / 2L) / denom).to_int() }
  {
    min_r: mnr,
    max_r: mxr,
    mean_r: mean(sr),
    min_g: mng,
    max_g: mxg,
    mean_g: mean(sg),
    min_b: mnb,
    max_b: mxb,
    mean_b: mean(sb),
    luma_min: mnl,
    luma_max: mxl,
    luma_mean: mean(sl),
  }
}

///|
/// Auto-contrast: linearly stretches the luma range `[luma_min, luma_max]`
/// to the full `[0, 255]`, applying the same scale to every channel so hues
/// are preserved. A flat image (min == max) is returned unchanged.
pub fn Image::auto_contrast(self : Image) -> Image {
  let s = self.stats()
  let lo = s.luma_min
  let hi = s.luma_max
  if hi <= lo {
    return self.copy()
  }
  let span = hi - lo
  let half = span / 2
  self.map_rgb(fn(r, g, b) {
    (
      ((r - lo) * 255 + half) / span,
      ((g - lo) * 255 + half) / span,
      ((b - lo) * 255 + half) / span,
    )
  })
}

///|
/// Levels adjustment: maps the input window `[black, white]` onto `[0, 255]`
/// with an optional midtone `gamma` (1.0 = linear; > 1 brightens midtones).
/// Values are clamped, so inputs at or below `black` become 0 and inputs at
/// or above `white` become 255. `white` is clamped to stay above `black`.
pub fn Image::levels(
  self : Image,
  black : Int,
  white : Int,
  gamma : Double,
) -> Image {
  let b0 = if black < 0 { 0 } else if black > 254 { 254 } else { black }
  let w0 = if white <= b0 { b0 + 1 } else if white > 255 { 255 } else { white }
  let span = (w0 - b0).to_double()
  let inv_gamma = if gamma <= 0.0 { 1.0 } else { 1.0 / gamma }
  // Precompute the 256-entry lookup table once.
  let lut = FixedArray::make(256, 0)
  for i in 0..<256 {
    let t = if i <= b0 {
      0.0
    } else if i >= w0 {
      1.0
    } else {
      (i - b0).to_double() / span
    }
    let adjusted = @math.pow(t, inv_gamma)
    lut[i] = clamp_byte((adjusted * 255.0 + 0.5).to_int()).to_int()
  }
  self.map_rgb(fn(r, g, b) { (lut[r], lut[g], lut[b]) })
}
