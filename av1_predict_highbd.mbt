/// High-bit-depth planar YUV420 conversion for the staged AV1 path.
///
/// The public Image type stores 8-bit channels, so samples are normalized
/// after validating the coded bit depth (8..12). Codec reconstruction remains
/// integer-only; this adapter performs no browser or FFI fallback.

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
  if bit_depth < 8 || bit_depth > 12 || width <= 0 || height <= 0 {
    return None
  }
  let cw = (width + 1) / 2
  let ch = (height + 1) / 2
  if y.length() != width * height || u.length() != cw * ch || v.length() != cw * ch {
    return None
  }
  let max_value = (1 << bit_depth) - 1
  let normalize = fn(sample : Int) -> Byte {
    let clamped = if sample < 0 { 0 } else if sample > max_value { max_value } else { sample }
    ((clamped * 255 + (max_value >> 1)) / max_value).to_byte()
  }
  let y8 : Array[Byte] = []
  let u8 : Array[Byte] = []
  let v8 : Array[Byte] = []
  for sample in y { y8.push(normalize(sample)) }
  for sample in u { u8.push(normalize(sample)) }
  for sample in v { v8.push(normalize(sample)) }
  av1_yuv420_to_rgba_color(
    width,
    height,
    y8,
    u8,
    v8,
    full_range~,
    matrix_coefficients~,
  )
}

