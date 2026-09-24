///|
/// Row/column transform kind: 0=DCT, 1=ADST, 2=identity.
fn av1_inverse_axis(
  input : Array[Int],
  log_size : Int,
  kind : Int,
  clamp_bits : Int,
) -> Array[Int]? {
  if kind == 0 {
    av1_inverse_dct(input, log_size, clamp_bits)
  } else if kind == 1 {
    if log_size == 2 {
      Some(av1_inv_adst4_1d(input[0], input[1], input[2], input[3]))
    } else {
      av1_inverse_adst_1d(input, log_size, clamp_bits)
    }
  } else if kind == 2 {
    av1_inverse_identity_1d(input, log_size)
  } else {
    None
  }
}

///|
/// AV1 inverse-transform assembly: horizontal rows, inter-stage rounding
/// and clipping, then vertical columns. Rectangular normalization depends
/// on both axes, independently of the selected DCT/ADST/identity kinds.
fn av1_inverse_separable(
  input : Array[Int],
  width : Int,
  height : Int,
  bit_depth : Int,
  row_kind : Int,
  col_kind : Int,
  row_flip : Bool,
  col_flip : Bool,
) -> Array[Int]? {
  let row_shift = match av1_tx_row_shift(width, height) {
    Some(value) => value
    None => return None
  }
  if input.length() != width * height || bit_depth < 8 || bit_depth > 16 {
    return None
  }
  let row_log = av1_msac_floor_log2(width)
  let col_log = av1_msac_floor_log2(height)
  let row_clamp = bit_depth + 8
  let col_clamp = if bit_depth + 6 > 16 { bit_depth + 6 } else { 16 }
  let minimum = -(1 << (col_clamp - 1))
  let maximum = (1 << (col_clamp - 1)) - 1
  let rect_scale = width == 2 * height || height == 2 * width
  let temp = Array::make(width * height, 0)
  for y in 0..<height {
    let row = Array::make(width, 0)
    for x in 0..<width {
      let value = input[y * width + x]
      row[x] = if rect_scale {
        ((value.to_int64() * 2896L + 2048L) >> 12).to_int()
      } else {
        value
      }
    }
    let values = match av1_inverse_axis(row, row_log, row_kind, row_clamp) {
      Some(value) => value
      None => return None
    }
    for x in 0..<width {
      let index = if row_flip { width - 1 - x } else { x }
      temp[y * width + x] = av1_clip(
        minimum,
        maximum,
        av1_round2(values[index], row_shift),
      )
    }
  }
  let output = Array::make(width * height, 0)
  for x in 0..<width {
    let col = Array::make(height, 0)
    for y in 0..<height {
      col[y] = temp[y * width + x]
    }
    let values = match av1_inverse_axis(col, col_log, col_kind, col_clamp) {
      Some(value) => value
      None => return None
    }
    for y in 0..<height {
      let index = if col_flip { height - 1 - y } else { y }
      output[y * width + x] = av1_round2(values[index], 4)
    }
  }
  Some(output)
}
