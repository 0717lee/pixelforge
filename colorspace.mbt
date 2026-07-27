///|
/// Wraps a hue angle into `[0, 360)`.
fn wrap_hue(h : Double) -> Double {
  h - 360.0 * ifloor(h / 360.0).to_double()
}

///|
/// Converts 8-bit RGB to HSV: hue in degrees `[0, 360)`, saturation and value
/// in `[0, 1]`.
pub fn rgb_to_hsv(r : Int, g : Int, b : Int) -> (Double, Double, Double) {
  let rf = r.to_double() / 255.0
  let gf = g.to_double() / 255.0
  let bf = b.to_double() / 255.0
  let mut mx = rf
  if gf > mx {
    mx = gf
  }
  if bf > mx {
    mx = bf
  }
  let mut mn = rf
  if gf < mn {
    mn = gf
  }
  if bf < mn {
    mn = bf
  }
  let d = mx - mn
  let h = if d == 0.0 {
    0.0
  } else if mx == rf {
    wrap_hue(60.0 * (gf - bf) / d)
  } else if mx == gf {
    60.0 * ((bf - rf) / d + 2.0)
  } else {
    60.0 * ((rf - gf) / d + 4.0)
  }
  let s = if mx == 0.0 { 0.0 } else { d / mx }
  (h, s, mx)
}

///|
/// Converts HSV (hue in degrees, saturation/value in `[0, 1]`) back to 8-bit
/// RGB using the standard sector decomposition.
pub fn hsv_to_rgb(h : Double, s : Double, v : Double) -> (Int, Int, Int) {
  let hh = wrap_hue(h) / 60.0
  let c = v * s
  let mod2 = hh - 2.0 * ifloor(hh / 2.0).to_double()
  let diff = if mod2 - 1.0 < 0.0 { 1.0 - mod2 } else { mod2 - 1.0 }
  let x = c * (1.0 - diff)
  let sector = ifloor(hh)
  let (r1, g1, b1) = match sector {
    0 => (c, x, 0.0)
    1 => (x, c, 0.0)
    2 => (0.0, c, x)
    3 => (0.0, x, c)
    4 => (x, 0.0, c)
    _ => (c, 0.0, x)
  }
  let m = v - c
  (
    ((r1 + m) * 255.0 + 0.5).to_int(),
    ((g1 + m) * 255.0 + 0.5).to_int(),
    ((b1 + m) * 255.0 + 0.5).to_int(),
  )
}

///|
/// Converts 8-bit RGB to BT.601 full-range YCbCr (all components 0..255).
pub fn rgb_to_ycbcr(r : Int, g : Int, b : Int) -> (Int, Int, Int) {
  let rf = r.to_double()
  let gf = g.to_double()
  let bf = b.to_double()
  let y = 0.299 * rf + 0.587 * gf + 0.114 * bf
  let cb = 128.0 - 0.168736 * rf - 0.331264 * gf + 0.5 * bf
  let cr = 128.0 + 0.5 * rf - 0.418688 * gf - 0.081312 * bf
  (
    clamp_byte((y + 0.5).to_int()).to_int(),
    clamp_byte((cb + 0.5).to_int()).to_int(),
    clamp_byte((cr + 0.5).to_int()).to_int(),
  )
}

///|
/// Converts BT.601 full-range YCbCr back to 8-bit RGB.
pub fn ycbcr_to_rgb(y : Int, cb : Int, cr : Int) -> (Int, Int, Int) {
  let yf = y.to_double()
  let cbf = cb.to_double() - 128.0
  let crf = cr.to_double() - 128.0
  (
    clamp_byte((yf + 1.402 * crf + 0.5).to_int()).to_int(),
    clamp_byte((yf - 0.344136 * cbf - 0.714136 * crf + 0.5).to_int()).to_int(),
    clamp_byte((yf + 1.772 * cbf + 0.5).to_int()).to_int(),
  )
}

///|
/// Scales saturation in HSV space: `factor > 1` makes colors more vivid,
/// `0` fully desaturates (equivalent brightness-preserving grayscale in V).
pub fn Image::saturate(self : Image, factor : Double) -> Image {
  let f = if factor < 0.0 { 0.0 } else { factor }
  self.map_rgb(fn(r, g, b) {
    let (h, s, v) = rgb_to_hsv(r, g, b)
    let ns = if s * f > 1.0 { 1.0 } else { s * f }
    hsv_to_rgb(h, ns, v)
  })
}

///|
/// Rotates every pixel's hue by `degrees` around the HSV color wheel while
/// keeping saturation and value untouched.
pub fn Image::hue_rotate(self : Image, degrees : Double) -> Image {
  self.map_rgb(fn(r, g, b) {
    let (h, s, v) = rgb_to_hsv(r, g, b)
    hsv_to_rgb(h + degrees, s, v)
  })
}
