///|
/// Affine transforms: an explicit 2x3 matrix type with the usual
/// constructors (rotation, translation, scaling, shear), composition and
/// inversion, plus `Image::affine` which renders via inverse mapping with
/// bilinear resampling. Pixels sampled outside the source are transparent.

///|
/// Row-major 2x3 affine matrix mapping `(x, y)` to
/// `(a*x + b*y + c, d*x + e*y + f)`.
pub(all) struct Affine {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
}

///|
const PI : Double = 3.141592653589793

///|
/// Identity transform.
pub fn Affine::identity() -> Affine {
  { a: 1.0, b: 0.0, c: 0.0, d: 0.0, e: 1.0, f: 0.0 }
}

///|
/// Translation by `(dx, dy)`.
pub fn Affine::translation(dx : Double, dy : Double) -> Affine {
  { a: 1.0, b: 0.0, c: dx, d: 0.0, e: 1.0, f: dy }
}

///|
/// Scaling about the origin.
pub fn Affine::scaling(sx : Double, sy : Double) -> Affine {
  { a: sx, b: 0.0, c: 0.0, d: 0.0, e: sy, f: 0.0 }
}

///|
/// Rotation about the origin. Positive angles rotate clockwise on screen
/// (y grows downward in image coordinates), matching `rotate90`.
pub fn Affine::rotation(degrees : Double) -> Affine {
  let rad = degrees * PI / 180.0
  let cs = @math.cos(rad)
  let sn = @math.sin(rad)
  { a: cs, b: -sn, c: 0.0, d: sn, e: cs, f: 0.0 }
}

///|
/// Shear: `x' = x + shx*y`, `y' = shy*x + y`.
pub fn Affine::shear(shx : Double, shy : Double) -> Affine {
  { a: 1.0, b: shx, c: 0.0, d: shy, e: 1.0, f: 0.0 }
}

///|
/// Applies the transform to a point.
pub fn Affine::apply(self : Affine, x : Double, y : Double) -> (Double, Double) {
  (self.a * x + self.b * y + self.c, self.d * x + self.e * y + self.f)
}

///|
/// Composition: returns the transform that applies `self` first and `next`
/// second (`next * self` as matrices).
pub fn Affine::then(self : Affine, next : Affine) -> Affine {
  {
    a: next.a * self.a + next.b * self.d,
    b: next.a * self.b + next.b * self.e,
    c: next.a * self.c + next.b * self.f + next.c,
    d: next.d * self.a + next.e * self.d,
    e: next.d * self.b + next.e * self.e,
    f: next.d * self.c + next.e * self.f + next.f,
  }
}

///|
/// Inverse transform, or `None` when the matrix is singular
/// (determinant close to zero) and cannot be inverted.
pub fn Affine::invert(self : Affine) -> Affine? {
  let det = self.a * self.e - self.b * self.d
  if det < 1.0e-12 && det > -1.0e-12 {
    return None
  }
  let ia = self.e / det
  let ib = -self.b / det
  let id = -self.d / det
  let ie = self.a / det
  Some({
    a: ia,
    b: ib,
    c: -(ia * self.c + ib * self.f),
    d: id,
    e: ie,
    f: -(id * self.c + ie * self.f),
  })
}

///|
/// Bilinearly samples the image at a fractional position. Taps that fall
/// outside the image contribute transparent black, so transformed edges
/// fade out instead of smearing.
fn Image::sample_bilinear(
  self : Image,
  fx : Double,
  fy : Double,
) -> (Int, Int, Int, Int) {
  let x0 = ifloor(fx)
  let y0 = ifloor(fy)
  let dx = fx - x0.to_double()
  let dy = fy - y0.to_double()
  let mut r = 0.0
  let mut g = 0.0
  let mut b = 0.0
  let mut a = 0.0
  for j in 0..<2 {
    for i in 0..<2 {
      let sx = x0 + i
      let sy = y0 + j
      if sx < 0 || sx >= self.width || sy < 0 || sy >= self.height {
        continue
      }
      let wx = if i == 0 { 1.0 - dx } else { dx }
      let wy = if j == 0 { 1.0 - dy } else { dy }
      let w = wx * wy
      let base = (sy * self.width + sx) * 4
      r = r + self.data[base].to_int().to_double() * w
      g = g + self.data[base + 1].to_int().to_double() * w
      b = b + self.data[base + 2].to_int().to_double() * w
      a = a + self.data[base + 3].to_int().to_double() * w
    }
  }
  (
    (r + 0.5).to_int(),
    (g + 0.5).to_int(),
    (b + 0.5).to_int(),
    (a + 0.5).to_int(),
  )
}

///|
/// Applies an affine transform, keeping the canvas size. Each output pixel
/// is inverse-mapped into the source and bilinearly sampled; areas with no
/// source coverage become transparent. Aborts on singular transforms.
pub fn Image::affine(self : Image, t : Affine) -> Image {
  let inv = match t.invert() {
    Some(m) => m
    None => abort("Image::affine: transform is singular")
  }
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let (fx, fy) = inv.apply(x.to_double(), y.to_double())
      let (r, g, b, a) = self.sample_bilinear(fx, fy)
      let base = (y * self.width + x) * 4
      out.data[base] = clamp_byte(r)
      out.data[base + 1] = clamp_byte(g)
      out.data[base + 2] = clamp_byte(b)
      out.data[base + 3] = clamp_byte(a)
    }
  }
  out
}

///|
/// Rotates by an arbitrary angle (degrees, clockwise) about the image
/// center on a same-size canvas; uncovered corners become transparent.
pub fn Image::rotate(self : Image, degrees : Double) -> Image {
  let cx = (self.width - 1).to_double() / 2.0
  let cy = (self.height - 1).to_double() / 2.0
  let t = Affine::translation(-cx, -cy)
    .then(Affine::rotation(degrees))
    .then(Affine::translation(cx, cy))
  self.affine(t)
}

///|
/// Translates by a (possibly fractional) offset on a same-size canvas.
pub fn Image::translate(self : Image, dx : Double, dy : Double) -> Image {
  self.affine(Affine::translation(dx, dy))
}
