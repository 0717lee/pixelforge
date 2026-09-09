/// Pixel reconstruction primitives shared by the bounded AV1 stage.

/// Converts an 8-bit planar YUV420 frame to PixelForge RGBA using the limited
/// range BT.601 matrix. The AV1 tile decoder can call this after reconstruction;
/// it performs no codec fallback and rejects malformed plane lengths.
pub fn av1_yuv420_to_rgba(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
) -> Image? {
  if width <= 0 || height <= 0 || width % 2 != 0 || height % 2 != 0 {
    return None
  }
  if y.length() != width * height || u.length() != (width / 2) * (height / 2) ||
    v.length() != (width / 2) * (height / 2) {
    return None
  }
  let out = Image::new(width, height)
  for yy in 0..<height {
    for xx in 0..<width {
      let yi = yy * width + xx
      let ci = (yy / 2) * (width / 2) + xx / 2
      let y0 = y[yi].to_int()
      let u0 = u[ci].to_int() - 128
      let v0 = v[ci].to_int() - 128
      let c = y0 - 16
      let r = (298 * c + 409 * v0 + 128) / 256
      let g = (298 * c - 100 * u0 - 208 * v0 + 128) / 256
      let b = (298 * c + 516 * u0 + 128) / 256
      out.set_pixel(xx, yy, clamp_byte(r), clamp_byte(g), clamp_byte(b), b'\xFF')
    }
  }
  Some(out)
}
