///|
/// Deterministic noise generators for testing and denoise demos. All
/// randomness comes from a 64-bit LCG seeded by the caller, so a given
/// seed produces the identical image on every backend and every run —
/// keeping the library's reproducibility promise even for "random" ops.

///|
/// 64-bit linear congruential step (Knuth MMIX constants). UInt64
/// arithmetic wraps, which is exactly what an LCG needs.
fn lcg_next(state : UInt64) -> UInt64 {
  state * 6364136223846793005UL + 1442695040888963407UL
}

///|
/// Extracts a uniform value in [0, 1) from the high bits of the state
/// (the low bits of an LCG are weak; the top 24 give a clean mantissa).
fn lcg_uniform(state : UInt64) -> Double {
  ((state >> 40) & 0xFFFFFFUL).to_uint().reinterpret_as_int().to_double() /
  16777216.0
}

///|
/// Adds zero-mean Gaussian noise with standard deviation `sigma` (in luma
/// steps) to R, G and B; alpha is untouched. The normal deviate is the
/// classic CLT approximation (sum of 12 uniforms minus 6), which is
/// branch-free and deterministic. `sigma <= 0` returns a copy.
pub fn Image::add_gaussian_noise(
  self : Image,
  seed : UInt64,
  sigma : Double,
) -> Image {
  if sigma <= 0.0 {
    return self.copy()
  }
  let out = self.copy()
  let n = self.pixel_count()
  let mut state = lcg_next(seed ^ 0x9E3779B97F4A7C15UL)
  for p in 0..<n {
    let base = p * 4
    // One shared deviate per pixel keeps the noise gray (no color fringes).
    let mut acc = 0.0
    for _ in 0..<12 {
      state = lcg_next(state)
      acc = acc + lcg_uniform(state)
    }
    let gauss = acc - 6.0 // ~N(0, 1)
    let scaled = gauss * sigma
    let rounded = if scaled >= 0.0 { scaled + 0.5 } else { scaled - 0.5 }
    let delta = rounded.to_int()
    for c in 0..<3 {
      out.data[base + c] = clamp_byte(self.data[base + c].to_int() + delta)
    }
  }
  out
}

///|
/// Salt-and-pepper noise: each pixel independently becomes pure white
/// ("salt") or pure black ("pepper") with probability `density / 2` each.
/// `density` is clamped into [0, 1]; alpha is preserved. Deterministic
/// for a given seed.
pub fn Image::add_salt_pepper(
  self : Image,
  seed : UInt64,
  density : Double,
) -> Image {
  let d = if density < 0.0 {
    0.0
  } else if density > 1.0 {
    1.0
  } else {
    density
  }
  let out = self.copy()
  if d == 0.0 {
    return out
  }
  let n = self.pixel_count()
  let mut state = lcg_next(seed ^ 0xD1B54A32D192ED03UL)
  for p in 0..<n {
    state = lcg_next(state)
    let u = lcg_uniform(state)
    if u < d {
      let base = p * 4
      let v : Byte = if u < d / 2.0 { b'\x00' } else { b'\xFF' }
      out.data[base] = v
      out.data[base + 1] = v
      out.data[base + 2] = v
    }
  }
  out
}
