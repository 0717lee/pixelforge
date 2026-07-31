///|
/// HSL color space: the "lightness" cousin of HSV. Hue is shared with HSV;
/// lightness places white at L=1 and black at L=0 with pure colors at
/// L=0.5, which makes symmetric lighten/darken operations natural. The
/// conversions mirror the existing HSV implementations so 8-bit round
/// trips are exact.

///|
/// Converts 8-bit RGB to HSL: hue in degrees `[0, 360)`, saturation and
/// lightness in `[0, 1]`.
pub fn rgb_to_hsl(r : Int, g : Int, b : Int) -> (Double, Double, Double) {
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
  let l = (mx + mn) / 2.0
  let h = if d == 0.0 {
    0.0
  } else if mx == rf {
    wrap_hue(60.0 * (gf - bf) / d)
  } else if mx == gf {
    60.0 * ((bf - rf) / d + 2.0)
  } else {
    60.0 * ((rf - gf) / d + 4.0)
  }
  let s = if d == 0.0 {
    0.0
  } else if l < 0.5 {
    d / (mx + mn)
  } else {
    d / (2.0 - mx - mn)
  }
  (h, s, l)
}

///|
/// Converts HSL (hue in degrees, saturation/lightness in `[0, 1]`) back to
/// 8-bit RGB using the standard chroma/sector decomposition.
pub fn hsl_to_rgb(h : Double, s : Double, l : Double) -> (Int, Int, Int) {
  let ld = if l - 0.5 < 0.0 { 0.5 - l } else { l - 0.5 }
  let c = (1.0 - 2.0 * ld) * s
  let hh = wrap_hue(h) / 60.0
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
  let m = l - c / 2.0
  (
    ((r1 + m) * 255.0 + 0.5).to_int(),
    ((g1 + m) * 255.0 + 0.5).to_int(),
    ((b1 + m) * 255.0 + 0.5).to_int(),
  )
}

///|
/// Shifts every pixel's HSL lightness by `delta` (in `[-1, 1]`), clamping
/// the result into `[0, 1]`. Positive values lighten toward white while
/// preserving hue; negative values darken toward black. `delta == 0`
/// returns a copy.
pub fn Image::adjust_lightness(self : Image, delta : Double) -> Image {
  if delta == 0.0 {
    return self.copy()
  }
  self.map_rgb(fn(r, g, b) {
    let (h, s, l) = rgb_to_hsl(r, g, b)
    let nl_raw = l + delta
    let nl = if nl_raw < 0.0 {
      0.0
    } else if nl_raw > 1.0 {
      1.0
    } else {
      nl_raw
    }
    hsl_to_rgb(h, s, nl)
  })
}
