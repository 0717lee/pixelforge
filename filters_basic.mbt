///|
/// Applies a per-pixel transform to the R, G, B channels while leaving alpha
/// untouched, clamping every result back into `[0, 255]`. This is the shared
/// engine behind the point filters below, so each concrete filter only has to
/// express its channel math.
pub fn Image::map_rgb(
  self : Image,
  transform : (Int, Int, Int) -> (Int, Int, Int),
) -> Image {
  let out = self.copy()
  let n = self.pixel_count()
  for p in 0..<n {
    let base = p * 4
    let r = self.data[base].to_int()
    let g = self.data[base + 1].to_int()
    let b = self.data[base + 2].to_int()
    let (nr, ng, nb) = transform(r, g, b)
    out.data[base] = clamp_byte(nr)
    out.data[base + 1] = clamp_byte(ng)
    out.data[base + 2] = clamp_byte(nb)
    // alpha at (base + 3) is preserved by the initial copy.
  }
  out
}

///|
/// Converts the image to grayscale using the Rec. 601 luma weights
/// (0.299, 0.587, 0.114). The weights are scaled by 1000 so the whole
/// computation stays in integer arithmetic and is bit-for-bit reproducible.
pub fn Image::grayscale(self : Image) -> Image {
  self.map_rgb(fn(r, g, b) {
    let y = (299 * r + 587 * g + 114 * b) / 1000
    (y, y, y)
  })
}

///|
/// Produces the photographic negative by flipping each channel around 255.
pub fn Image::invert(self : Image) -> Image {
  self.map_rgb(fn(r, g, b) { (255 - r, 255 - g, 255 - b) })
}

///|
/// Shifts every channel by `delta` (negative darkens, positive brightens).
/// Out-of-range results saturate at 0 and 255.
pub fn Image::brightness(self : Image, delta : Int) -> Image {
  self.map_rgb(fn(r, g, b) { (r + delta, g + delta, b + delta) })
}

///|
/// Scales contrast around the 128 mid-gray point. `factor > 1.0` boosts
/// contrast, `0.0 < factor < 1.0` flattens it, and `1.0` is a no-op.
pub fn Image::contrast(self : Image, factor : Double) -> Image {
  self.map_rgb(fn(r, g, b) {
    let apply = fn(c : Int) -> Int {
      ((c.to_double() - 128.0) * factor + 128.0).to_int()
    }
    (apply(r), apply(g), apply(b))
  })
}
