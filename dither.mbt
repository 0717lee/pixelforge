///|
/// Floyd–Steinberg error-diffusion dithering. Quantization error at each
/// pixel is pushed to the not-yet-visited neighbors with the classic
/// weights (7/16 right, 3/16 below-left, 5/16 below, 1/16 below-right), so a
/// small palette still reproduces smooth gradients as stipple patterns.

///|
/// Diffuses `err` from pixel `(x, y)` into the working buffer `buf`
/// (one Int channel per pixel) using the Floyd–Steinberg weights.
fn diffuse(
  buf : Array[Int],
  w : Int,
  h : Int,
  x : Int,
  y : Int,
  err : Int,
) -> Unit {
  if x + 1 < w {
    buf[y * w + x + 1] = buf[y * w + x + 1] + err * 7 / 16
  }
  if y + 1 < h {
    if x > 0 {
      buf[(y + 1) * w + x - 1] = buf[(y + 1) * w + x - 1] + err * 3 / 16
    }
    buf[(y + 1) * w + x] = buf[(y + 1) * w + x] + err * 5 / 16
    if x + 1 < w {
      buf[(y + 1) * w + x + 1] = buf[(y + 1) * w + x + 1] + err * 1 / 16
    }
  }
}

///|
/// Quantizes `v` (0..255) to the nearest of `levels` evenly spaced tones and
/// returns that output value in 0..255.
fn quantize(v : Int, levels : Int) -> Int {
  let step = 255 / (levels - 1)
  let q = (v + step / 2) / step
  let capped = if q > levels - 1 { levels - 1 } else if q < 0 { 0 } else { q }
  capped * 255 / (levels - 1)
}

///|
/// Grayscale Floyd–Steinberg dithering to `levels` tones (clamped to
/// `[2, 256]`). The image is first reduced to luma; error diffuses in a
/// left-to-right, top-to-bottom scan. Output is gray; alpha preserved.
pub fn Image::dither_grayscale(self : Image, levels : Int) -> Image {
  let l = if levels < 2 { 2 } else if levels > 256 { 256 } else { levels }
  let w = self.width
  let h = self.height
  let buf : Array[Int] = Array::make(w * h, 0)
  for p in 0..<(w * h) {
    let base = p * 4
    buf[p] = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
  }
  let out = Image::new(w, h)
  for y in 0..<h {
    for x in 0..<w {
      let old = buf[y * w + x]
      let newv = quantize(old, l)
      diffuse(buf, w, h, x, y, old - newv)
      let b = clamp_byte(newv)
      let base = (y * w + x) * 4
      out.data[base] = b
      out.data[base + 1] = b
      out.data[base + 2] = b
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// 1-bit (black/white) Floyd–Steinberg dithering — the classic newsprint
/// look. Equivalent to `dither_grayscale(2)`.
pub fn Image::dither_mono(self : Image) -> Image {
  self.dither_grayscale(2)
}
