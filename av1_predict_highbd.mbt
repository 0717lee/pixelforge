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
/// Chroma uses nearest-neighbour replication. Output is source-primary,
/// source-transfer nonlinear RGB, clipped and rounded once to RGBA8. There
/// is no display tone mapping or gamut conversion, except that XYZ primaries
/// (10) are explicitly converted to BT.709/sRGB. Unspecified matrix (2) uses
/// the AVIF/libavif BT.601 default; matrices needing primaries or a transfer
/// reject unspecified metadata rather than guessing those parameters.
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
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
) -> Image? {
  av1_yuv_highbd_to_rgba_core(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
    subsampling_x~,
    subsampling_y~,
    full_range~,
    matrix_coefficients~,
    color_primaries~,
    transfer_characteristics~,
  )
}

///|
/// The native-alpha path is used where libavif fuses unpremultiplication into
/// its floating-point matrix conversion, before narrowing the color channels.
fn av1_yuv_highbd_to_rgba_core(
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
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
  native_alpha? : Array[Int]? = None,
  monochrome? : Bool = false,
) -> Image? {
  if (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    (subsampling_y && !subsampling_x) ||
    (matrix_coefficients == 0 && (subsampling_x || subsampling_y)) ||
    !av1_color_supported(
      matrix_coefficients, color_primaries, transfer_characteristics,
    ) {
    return None
  }
  let sub_x = if subsampling_x { 1 } else { 0 }
  let sub_y = if subsampling_y { 1 } else { 0 }
  let cw = (width + (1 << sub_x) - 1) >> sub_x
  let ch = (height + (1 << sub_y) - 1) >> sub_y
  if y.length() != width * height ||
    (!monochrome && (u.length() != cw * ch || v.length() != cw * ch)) {
    return None
  }
  // Keep coded precision through the matrix conversion. Narrowing each
  // plane first loses limited-range offsets and adds a second rounding step.
  let scale = 1 << (bit_depth - 8)
  let max_value = (1 << bit_depth) - 1
  if native_alpha is Some(alpha) {
    if alpha.length() != width * height {
      return None
    }
    for value in alpha {
      if value < 0 || value > max_value {
        return None
      }
    }
  }
  let clamp_sample = fn(sample : Int) -> Double {
    if sample < 0 {
      0.0
    } else if sample > max_value {
      max_value.to_double()
    } else {
      sample.to_double()
    }
  }
  let out = Image::new(width, height)
  let black = if full_range { 0.0 } else { (16 * scale).to_double() }
  let midpoint = (128 * scale).to_double()
  let luma_range = if full_range {
    max_value.to_double()
  } else {
    (219 * scale).to_double()
  }
  // YCgCo operates on quantized RGB channels (H.273 equations 27-29,
  // 51-57): undo its signed differences before the RGB range expansion.
  // This is equivalent to a chroma denominator of 219, not YCbCr's 224.
  let chroma_range = if full_range {
    max_value.to_double()
  } else if matrix_coefficients == 8 {
    (219 * scale).to_double()
  } else {
    (224 * scale).to_double()
  }
  // The libavif slow identity/YCgCo path uses float32 LUT entries, matrix
  // operations and alpha division. Keeping those rounding boundaries matters
  // at exact half-channel ties after unpremultiplication (for example 212.5).
  let scalar_float = native_alpha is Some(_) &&
    (matrix_coefficients == 0 || matrix_coefficients == 8)
  let normalize = fn(sample : Int, bias : Double, span : Double) -> Double {
    if scalar_float {
      ((Float::from_double(clamp_sample(sample)) - Float::from_double(bias)) /
      Float::from_double(span)).to_double()
    } else {
      (clamp_sample(sample) - bias) / span
    }
  }
  let to_byte = fn(value : Double) -> Byte {
    let clamped = if value < 0.0 {
      0.0
    } else if value > 1.0 {
      1.0
    } else {
      value
    }
    if scalar_float {
      (Float::from_double(clamped) * 255.0 + 0.5).to_int().to_byte()
    } else {
      (clamped * 255.0 + 0.5).to_int().to_byte()
    }
  }
  for yy in 0..<height {
    for xx in 0..<width {
      let yi = yy * width + xx
      let ci = (yy >> sub_y) * cw + (xx >> sub_x)
      let y0 = normalize(y[yi], black, luma_range)
      let (r, g, b) = if monochrome {
        (y0, y0, y0)
      } else if matrix_coefficients == 0 {
        // Identity stores G in Y, B in U and R in V; all three are RGB-range
        // components, so neither chroma centering nor 224 scaling applies.
        (
          normalize(v[ci], black, luma_range),
          y0,
          normalize(u[ci], black, luma_range),
        )
      } else if scalar_float && matrix_coefficients == 8 {
        let yy = Float::from_double(y0)
        let cg = Float::from_double(normalize(u[ci], midpoint, chroma_range))
        let co = Float::from_double(normalize(v[ci], midpoint, chroma_range))
        let t = yy - cg
        ((t + co).to_double(), (yy + cg).to_double(), (t - co).to_double())
      } else {
        match
          av1_color_rgb(
            y0,
            (clamp_sample(u[ci]) - midpoint) / chroma_range,
            (clamp_sample(v[ci]) - midpoint) / chroma_range,
            matrix_coefficients,
            color_primaries,
            transfer_characteristics,
          ) {
          Some(rgb) => rgb
          None => return None
        }
      }
      let (r, g, b) = match native_alpha {
        None => (r, g, b)
        Some(alpha) => {
          let coverage = if scalar_float {
            (Float::from_int(alpha[yi]) / Float::from_int(max_value)).to_double()
          } else {
            alpha[yi].to_double() / max_value.to_double()
          }
          let straight = fn(value : Double) -> Double {
            if coverage == 0.0 || value <= 0.0 {
              0.0
            } else {
              let clamped = if value > 1.0 { 1.0 } else { value }
              let result = if scalar_float {
                (Float::from_double(clamped) / Float::from_double(coverage)).to_double()
              } else {
                clamped / coverage
              }
              if result > 1.0 {
                1.0
              } else {
                result
              }
            }
          }
          (straight(r), straight(g), straight(b))
        }
      }
      let (r, g, b) = if color_primaries == 10 {
        match av1_color_xyz_to_srgb(r, g, b, transfer_characteristics) {
          Some(rgb) => rgb
          None => return None
        }
      } else {
        (r, g, b)
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
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
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
    color_primaries~,
    transfer_characteristics~,
  )
}
