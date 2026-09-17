/// AV1 normative horizontal super-resolution. Phase uses visible plane widths;
/// tap availability includes reconstructed MI padding. The same phase advances
/// across a complete row, independent of coding-tile boundaries.

///|
let av1_superres_filters : Array[Array[Int]] = [
  [0, 0, 0, 128, 0, 0, 0, 0],
  [0, 0, -1, 128, 2, -1, 0, 0],
  [0, 1, -3, 127, 4, -2, 1, 0],
  [0, 1, -4, 127, 6, -3, 1, 0],
  [0, 2, -6, 126, 8, -3, 1, 0],
  [0, 2, -7, 125, 11, -4, 1, 0],
  [-1, 2, -8, 125, 13, -5, 2, 0],
  [-1, 3, -9, 124, 15, -6, 2, 0],
  [-1, 3, -10, 123, 18, -6, 2, -1],
  [-1, 3, -11, 122, 20, -7, 3, -1],
  [-1, 4, -12, 121, 22, -8, 3, -1],
  [-1, 4, -13, 120, 25, -9, 3, -1],
  [-1, 4, -14, 118, 28, -9, 3, -1],
  [-1, 4, -15, 117, 30, -10, 4, -1],
  [-1, 5, -16, 116, 32, -11, 4, -1],
  [-1, 5, -16, 114, 35, -12, 4, -1],
  [-1, 5, -17, 112, 38, -12, 4, -1],
  [-1, 5, -18, 111, 40, -13, 5, -1],
  [-1, 5, -18, 109, 43, -14, 5, -1],
  [-1, 6, -19, 107, 45, -14, 5, -1],
  [-1, 6, -19, 105, 48, -15, 5, -1],
  [-1, 6, -19, 103, 51, -16, 5, -1],
  [-1, 6, -20, 101, 53, -16, 6, -1],
  [-1, 6, -20, 99, 56, -17, 6, -1],
  [-1, 6, -20, 97, 58, -17, 6, -1],
  [-1, 6, -20, 95, 61, -18, 6, -1],
  [-2, 7, -20, 93, 64, -18, 6, -2],
  [-2, 7, -20, 91, 66, -19, 6, -1],
  [-2, 7, -20, 88, 69, -19, 6, -1],
  [-2, 7, -20, 86, 71, -19, 6, -1],
  [-2, 7, -20, 84, 74, -20, 7, -2],
  [-2, 7, -20, 81, 76, -20, 7, -1],
  [-2, 7, -20, 79, 79, -20, 7, -2],
  [-1, 7, -20, 76, 81, -20, 7, -2],
  [-2, 7, -20, 74, 84, -20, 7, -2],
  [-1, 6, -19, 71, 86, -20, 7, -2],
  [-1, 6, -19, 69, 88, -20, 7, -2],
  [-1, 6, -19, 66, 91, -20, 7, -2],
  [-2, 6, -18, 64, 93, -20, 7, -2],
  [-1, 6, -18, 61, 95, -20, 6, -1],
  [-1, 6, -17, 58, 97, -20, 6, -1],
  [-1, 6, -17, 56, 99, -20, 6, -1],
  [-1, 6, -16, 53, 101, -20, 6, -1],
  [-1, 5, -16, 51, 103, -19, 6, -1],
  [-1, 5, -15, 48, 105, -19, 6, -1],
  [-1, 5, -14, 45, 107, -19, 6, -1],
  [-1, 5, -14, 43, 109, -18, 5, -1],
  [-1, 5, -13, 40, 111, -18, 5, -1],
  [-1, 4, -12, 38, 112, -17, 5, -1],
  [-1, 4, -12, 35, 114, -16, 5, -1],
  [-1, 4, -11, 32, 116, -16, 5, -1],
  [-1, 4, -10, 30, 117, -15, 4, -1],
  [-1, 3, -9, 28, 118, -14, 4, -1],
  [-1, 3, -9, 25, 120, -13, 4, -1],
  [-1, 3, -8, 22, 121, -12, 4, -1],
  [-1, 3, -7, 20, 122, -11, 3, -1],
  [-1, 2, -6, 18, 123, -10, 3, -1],
  [0, 2, -6, 15, 124, -9, 3, -1],
  [0, 2, -5, 13, 125, -8, 2, -1],
  [0, 1, -4, 11, 125, -7, 2, 0],
  [0, 1, -3, 8, 126, -6, 2, 0],
  [0, 1, -3, 6, 127, -4, 1, 0],
  [0, 1, -2, 4, 127, -3, 1, 0],
  [0, 0, -1, 2, 128, -1, 0, 0],
]

///|
/// Q14 step and initial phase from the normative integer equations. Division
/// of negative values truncates toward zero, including the error correction.
/// The caller handles equal-width frames without invoking the active scaler.
fn av1_superres_params(
  downscaled_width : Int,
  upscaled_width : Int,
) -> (Int, Int)? {
  if downscaled_width <= 0 ||
    downscaled_width > 65536 ||
    upscaled_width <= downscaled_width ||
    upscaled_width > 65536 ||
    upscaled_width > 2 * downscaled_width {
    return None
  }
  let step = ((downscaled_width << 14) + upscaled_width / 2) / upscaled_width
  let error = upscaled_width * step - (downscaled_width << 14)
  let initial = (
      -((upscaled_width - downscaled_width) << 13) + upscaled_width / 2
    ) /
    upscaled_width +
    128 -
    error / 2
  Some((step, initial & 16383))
}

///|
/// Produce packed visible output rows from strided reconstructed input. Values
/// between `src_available_width` and `src_stride` are storage padding and are
/// never sampled. Available MI pixels beyond `downscaled_width` remain valid
/// filter inputs; only the outer frame edges repeat their last sample.
fn av1_superres_upscale_plane(
  src : Array[Int],
  src_stride : Int,
  src_available_width : Int,
  downscaled_width : Int,
  upscaled_width : Int,
  rows : Int,
  bit_depth : Int,
) -> Array[Int]? {
  let (step, initial) = match
    av1_superres_params(downscaled_width, upscaled_width) {
    Some(value) => value
    None => return None
  }
  if rows <= 0 ||
    rows > 65536 ||
    src_available_width < downscaled_width ||
    src_available_width > 65536 ||
    src_stride < src_available_width ||
    src.length() < src_available_width ||
    rows - 1 > (src.length() - src_available_width) / src_stride ||
    upscaled_width > MAX_IMAGE_PIXELS / rows ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  let maximum = (1 << bit_depth) - 1
  for row in 0..<rows {
    for col in 0..<src_available_width {
      let value = src[row * src_stride + col]
      if value < 0 || value > maximum {
        return None
      }
    }
  }
  let output = Array::make(upscaled_width * rows, 0)
  for row in 0..<rows {
    let mut position = initial - 16384
    for col in 0..<upscaled_width {
      let integer = position >> 14
      let phase = (position & 16383) >> 8
      let filter = av1_superres_filters[phase]
      let mut sum = 0
      for tap in 0..<8 {
        let x = integer + tap - 3
        let x = if x < 0 {
          0
        } else if x >= src_available_width {
          src_available_width - 1
        } else {
          x
        }
        sum = sum + src[row * src_stride + x] * filter[tap]
      }
      output[row * upscaled_width + col] = av1_intra_clip(
        (sum + 64) >> 7,
        bit_depth,
      )
      position = position + step
    }
  }
  Some(output)
}
