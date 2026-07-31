///|
/// Bicubic resize using the Catmull-Rom spline: each output pixel blends a
/// 4x4 source neighborhood with cubic weights, giving noticeably smoother
/// results than bilinear on photographic content while staying local. Uses
/// the same center-aligned sampling and clamp-to-edge policy as the other
/// resizers, so a same-size resize stays an identity up to rounding.

///|
/// Catmull-Rom kernel weight for the four taps around fractional offset
/// `t` in [0, 1): returns the weights of taps at offsets -1, 0, +1, +2.
fn catmull_weights(t : Double) -> (Double, Double, Double, Double) {
  let t2 = t * t
  let t3 = t2 * t
  // Standard Catmull-Rom (a = -0.5) expanded per tap.
  let w0 = -0.5 * t3 + t2 - 0.5 * t
  let w1 = 1.5 * t3 - 2.5 * t2 + 1.0
  let w2 = -1.5 * t3 + 2.0 * t2 + 0.5 * t
  let w3 = 0.5 * t3 - 0.5 * t2
  (w0, w1, w2, w3)
}

///|
/// Bicubic (Catmull-Rom) resize to `new_width` x `new_height` (both clamped
/// to at least 1). All four channels including alpha are interpolated; the
/// cubic can overshoot near edges, so results are clamped back to 0..255.
pub fn Image::resize_bicubic(
  self : Image,
  new_width : Int,
  new_height : Int,
) -> Image {
  let w = if new_width < 1 { 1 } else { new_width }
  let h = if new_height < 1 { 1 } else { new_height }
  let out = Image::new(w, h)
  for y in 0..<h {
    let fy = (y.to_double() + 0.5) * self.height.to_double() / h.to_double() -
      0.5
    let y0 = ifloor(fy)
    let ty = fy - y0.to_double()
    let (wy0, wy1, wy2, wy3) = catmull_weights(ty)
    let sy = [
      clamp_coord(y0 - 1, self.height),
      clamp_coord(y0, self.height),
      clamp_coord(y0 + 1, self.height),
      clamp_coord(y0 + 2, self.height),
    ]
    let wy = [wy0, wy1, wy2, wy3]
    for x in 0..<w {
      let fx = (x.to_double() + 0.5) * self.width.to_double() / w.to_double() -
        0.5
      let x0 = ifloor(fx)
      let tx = fx - x0.to_double()
      let (wx0, wx1, wx2, wx3) = catmull_weights(tx)
      let sx = [
        clamp_coord(x0 - 1, self.width),
        clamp_coord(x0, self.width),
        clamp_coord(x0 + 1, self.width),
        clamp_coord(x0 + 2, self.width),
      ]
      let wx = [wx0, wx1, wx2, wx3]
      let dst = (y * w + x) * 4
      for c in 0..<4 {
        let mut acc = 0.0
        for j in 0..<4 {
          let mut row = 0.0
          for i in 0..<4 {
            row = row +
              self.data[(sy[j] * self.width + sx[i]) * 4 + c]
              .to_int()
              .to_double() *
              wx[i]
          }
          acc = acc + row * wy[j]
        }
        out.data[dst + c] = clamp_byte((acc + 0.5).to_int())
      }
    }
  }
  out
}
