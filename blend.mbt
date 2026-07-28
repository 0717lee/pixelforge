///|
/// Layer compositing: Porter-Duff source-over with the common separable
/// blend modes, in pure integer math (channel values and alphas both live
/// in 0..255, divisions by 255 are rounded).

///|
/// Separable blend modes applied per channel before alpha compositing.
pub(all) enum BlendMode {
  Normal
  Multiply
  Screen
  Overlay
  Darken
  Lighten
  Difference
  Add
}

///|
/// Rounded division by 255, the workhorse of 8-bit compositing.
fn div255(v : Int) -> Int {
  (v + 127) / 255
}

///|
/// B(cb, cs) for one channel: backdrop and source in, blended value out.
fn blend_channel(mode : BlendMode, cb : Int, cs : Int) -> Int {
  match mode {
    Normal => cs
    Multiply => div255(cb * cs)
    Screen => 255 - div255((255 - cb) * (255 - cs))
    Overlay =>
      if cb < 128 {
        div255(2 * cb * cs)
      } else {
        255 - div255(2 * (255 - cb) * (255 - cs))
      }
    Darken => if cb < cs { cb } else { cs }
    Lighten => if cb > cs { cb } else { cs }
    Difference => iabs(cb - cs)
    Add => if cb + cs > 255 { 255 } else { cb + cs }
  }
}

///|
/// Composites `top` over `self` (source-over) with the given blend mode.
/// Both images must have identical dimensions (aborts otherwise).
///
/// Per pixel, following the W3C compositing model:
/// the source color is first mixed toward `B(cb, cs)` by the backdrop
/// alpha, then source-over composited:
/// `ao = as + ab*(1-as)` and `co = (as*cs' + (1-as)*ab*cb) / ao`.
pub fn Image::composite(self : Image, top : Image, mode : BlendMode) -> Image {
  if self.width != top.width || self.height != top.height {
    abort("Image::composite: images must have identical dimensions")
  }
  let out = Image::new(self.width, self.height)
  for p in 0..<self.pixel_count() {
    let base = p * 4
    let ab = self.data[base + 3].to_int()
    let as_ = top.data[base + 3].to_int()
    // (1-as)*ab, the backdrop's remaining contribution.
    let ab_left = div255((255 - as_) * ab)
    let ao = as_ + ab_left
    out.data[base + 3] = clamp_byte(ao)
    for c in 0..<3 {
      let cb = self.data[base + c].to_int()
      let cs = top.data[base + c].to_int()
      // Mix the blend result toward plain source by backdrop coverage.
      let mixed = div255((255 - ab) * cs + ab * blend_channel(mode, cb, cs))
      let v = if ao == 0 {
        0
      } else {
        (as_ * mixed + ab_left * cb + ao / 2) / ao
      }
      out.data[base + c] = clamp_byte(v)
    }
  }
  out
}
