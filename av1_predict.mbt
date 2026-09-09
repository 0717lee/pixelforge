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
  av1_yuv420_to_rgba_color(width, height, y, u, v, full_range=false, matrix_coefficients=6)
}

/// Converts 8-bit planar YUV420 using the AV1 color range flag.
pub fn av1_yuv420_to_rgba_range(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
) -> Image? {
  av1_yuv420_to_rgba_color(width, height, y, u, v, full_range=full_range, matrix_coefficients=6)
}

/// Converts 8-bit planar YUV420 using color range and AV1 matrix coefficients.
/// Matrix 1 uses BT.709; matrices 5, 6, and 2 use the BT.601-family constants.
pub fn av1_yuv420_to_rgba_color(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  if width <= 0 || height <= 0 {
    return None
  }
  let chroma_width = (width + 1) / 2
  let chroma_height = (height + 1) / 2
  if y.length() != width * height ||
    u.length() != chroma_width * chroma_height ||
    v.length() != chroma_width * chroma_height {
    return None
  }
  let out = Image::new(width, height)
  for yy in 0..<height {
    for xx in 0..<width {
      let yi = yy * width + xx
      let ci = (yy / 2) * chroma_width + xx / 2
      let y0 = y[yi].to_int()
      let u0 = u[ci].to_int() - 128
      let v0 = v[ci].to_int() - 128
      let bt709 = matrix_coefficients == 1
      let (r, g, b) = if full_range && bt709 {
        (
          (256 * y0 + 402 * v0 + 128) / 256,
          (256 * y0 - 48 * u0 - 120 * v0 + 128) / 256,
          (256 * y0 + 475 * u0 + 128) / 256,
        )
      } else if full_range {
        (
          (256 * y0 + 359 * v0 + 128) / 256,
          (256 * y0 - 88 * u0 - 183 * v0 + 128) / 256,
          (256 * y0 + 454 * u0 + 128) / 256,
        )
      } else if bt709 {
        let c = y0 - 16
        (
          (298 * c + 459 * v0 + 128) / 256,
          (298 * c - 55 * u0 - 136 * v0 + 128) / 256,
          (298 * c + 541 * u0 + 128) / 256,
        )
      } else {
        let c = y0 - 16
        (
          (298 * c + 409 * v0 + 128) / 256,
          (298 * c - 100 * u0 - 208 * v0 + 128) / 256,
          (298 * c + 516 * u0 + 128) / 256,
        )
      }
      out.set_pixel(xx, yy, clamp_byte(r), clamp_byte(g), clamp_byte(b), b'\xFF')
    }
  }
  Some(out)
}
