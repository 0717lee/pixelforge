///|
/// High-bit-depth planar YUV conversion for the staged AV1 path.
///
/// The public Image type stores 8-bit channels; coded 8..12-bit samples are
/// converted with the high-bit-depth matrix and narrowed only for final RGBA
/// storage. Codec reconstruction remains integer-only; this adapter performs
/// no browser or FFI fallback.
///
/// `subsampling_x`/`subsampling_y` select 4:4:4, 4:2:2 or 4:2:0; the defaults
/// keep the historical 4:2:0 behaviour of `av1_yuv420_highbd_to_rgba`.
pub fn av1_yuv_highbd_to_rgba(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  bit_depth : Int,
  subsampling_x? : Bool = true,
  subsampling_y? : Bool = true,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  if bit_depth < 8 || bit_depth > 12 || width <= 0 || height <= 0 {
    return None
  }
  let sub_x = if subsampling_x { 1 } else { 0 }
  let sub_y = if subsampling_y { 1 } else { 0 }
  let cw = (width + (1 << sub_x) - 1) >> sub_x
  let ch = (height + (1 << sub_y) - 1) >> sub_y
  if y.length() != width * height ||
    u.length() != cw * ch ||
    v.length() != cw * ch {
    return None
  }
  // Keep coded precision through the matrix conversion. Narrowing each
  // plane first loses limited-range offsets and adds a second rounding step.
  let scale = 1 << (bit_depth - 8)
  let max_value = (1 << bit_depth) - 1
  let clamp_sample = fn(sample : Int) -> Int {
    if sample < 0 {
      0
    } else if sample > max_value {
      max_value
    } else {
      sample
    }
  }
  let out = Image::new(width, height)
  let round = 128 * scale
  let to_byte = fn(value : Int) -> Byte {
    let clamped = if value < 0 { 0 } else if value > 255 { 255 } else { value }
    clamped.to_byte()
  }
  for yy in 0..<height {
    for xx in 0..<width {
      let yi = yy * width + xx
      let ci = (yy >> sub_y) * cw + (xx >> sub_x)
      let y0 = clamp_sample(y[yi])
      let u0 = clamp_sample(u[ci]) - 128 * scale
      let v0 = clamp_sample(v[ci]) - 128 * scale
      let (r, g, b) = if full_range && matrix_coefficients == 1 {
        (
          (256 * y0 + 402 * v0 + round) / (256 * scale),
          (256 * y0 - 48 * u0 - 120 * v0 + round) / (256 * scale),
          (256 * y0 + 475 * u0 + round) / (256 * scale),
        )
      } else if full_range {
        (
          (256 * y0 + 359 * v0 + round) / (256 * scale),
          (256 * y0 - 88 * u0 - 183 * v0 + round) / (256 * scale),
          (256 * y0 + 454 * u0 + round) / (256 * scale),
        )
      } else {
        let c = y0 - 16 * scale
        if matrix_coefficients == 1 {
          (
            (298 * c + 459 * v0 + round) / (256 * scale),
            (298 * c - 55 * u0 - 136 * v0 + round) / (256 * scale),
            (298 * c + 541 * u0 + round) / (256 * scale),
          )
        } else {
          (
            (298 * c + 409 * v0 + round) / (256 * scale),
            (298 * c - 100 * u0 - 208 * v0 + round) / (256 * scale),
            (298 * c + 516 * u0 + round) / (256 * scale),
          )
        }
      }
      out.set_pixel(xx, yy, to_byte(r), to_byte(g), to_byte(b), b'\xFF')
    }
  }
  Some(out)
}

///|
/// 4:2:0 convenience wrapper over `av1_yuv_highbd_to_rgba`.
pub fn av1_yuv420_highbd_to_rgba(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  bit_depth : Int,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  av1_yuv_highbd_to_rgba(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
    full_range~,
    matrix_coefficients~,
  )
}
