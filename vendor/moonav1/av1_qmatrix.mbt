/// AV1 inverse quantization matrices (AV1 sections 5.9.14 and 7.12.3).

///|
/// Per-plane matrix levels signalled by quantization_params. Levels 0..14
/// select the normative inverse matrix; level 15 selects uniform weights.
/// U and V select independently from the common chroma matrix family.
pub(all) struct Av1QuantMatrix {
  y : Int
  u : Int
  v : Int
} derive(Eq, Debug)

///|
fn av1_quant_matrix_valid(matrix : Av1QuantMatrix?) -> Bool {
  match matrix {
    None => true
    Some(matrix) =>
      matrix.y >= 0 &&
      matrix.y <= 15 &&
      matrix.u >= 0 &&
      matrix.u <= 15 &&
      matrix.v >= 0 &&
      matrix.v <= 15
  }
}

///|
/// LosslessArray is derived from the nominal segment qindex and all five
/// plane deltas, independently of the superblock delta-Q. Its caller passes
/// that flag explicitly; an effective qindex of zero alone is insufficient.
fn av1_qmatrix_level(
  matrix : Av1QuantMatrix?,
  plane : Int,
  tx_type : Av1TxType,
  lossless : Bool,
) -> Int {
  if lossless {
    return 15
  }
  match tx_type {
    Av1TxDctDct
    | Av1TxAdstDct
    | Av1TxDctAdst
    | Av1TxAdstAdst
    | Av1TxFlipadstDct
    | Av1TxDctFlipadst
    | Av1TxFlipadstFlipadst
    | Av1TxAdstFlipadst
    | Av1TxFlipadstAdst => ()
    _ => return 15
  }
  match matrix {
    None => 15
    Some(matrix) =>
      if plane == 0 {
        matrix.y
      } else if plane == 1 {
        matrix.u
      } else {
        matrix.v
      }
  }
}

///|
/// Fetch a row-major coefficient weight in the adjusted transform domain.
/// The generated square tables keep the lower triangle; 16x16 samples every
/// second row/column of 32x32. Rectangles keep their wider orientation and
/// transpose on lookup. This is the normative Qm_Offset layout expressed
/// without duplicating transposed matrices or expanding their 64-wide tails.
fn av1_qmatrix_weight(
  level : Int,
  plane : Int,
  width : Int,
  height : Int,
  pos : Int,
) -> Int {
  if level == 15 {
    return 32
  }
  let width = if width > 32 { 32 } else { width }
  let height = if height > 32 { 32 } else { height }
  let row = pos / width
  let col = pos % width
  let matrix_index = level * 2 + (if plane == 0 { 0 } else { 1 })
  if width == height {
    let step = if width == 16 { 2 } else { 1 }
    let r = row * step
    let c = col * step
    let hi = if r > c { r } else { c }
    let lo = if r > c { c } else { r }
    let index = hi * (hi + 1) / 2 + lo
    let data = if width == 4 {
      av1_qmatrix_4x4_t[matrix_index]
    } else if width == 8 {
      av1_qmatrix_8x8_t[matrix_index]
    } else {
      av1_qmatrix_32x32_t[matrix_index]
    }
    return data[index].to_int()
  }
  let wide = if width > height { width } else { height }
  let short = if width > height { height } else { width }
  let index = if width > height { pos } else { col * wide + row }
  let data = if wide == 8 {
    av1_qmatrix_8x4[matrix_index]
  } else if wide == 16 && short == 4 {
    av1_qmatrix_16x4[matrix_index]
  } else if wide == 16 {
    av1_qmatrix_16x8[matrix_index]
  } else if short == 8 {
    av1_qmatrix_32x8[matrix_index]
  } else {
    av1_qmatrix_32x16[matrix_index]
  }
  data[index].to_int()
}

///|
/// AV1 scales the scalar quantizer before multiplying by the coefficient.
/// The largest product (29247 * 255) fits in Int for every supported depth.
fn av1_qmatrix_quant(q : Int, weight : Int) -> Int {
  (q * weight + 16) >> 5
}

///|
/// Section 7.12.1: the denominator depends on original transform area, not
/// adjusted coefficient area. In particular, 16x64/64x16 use 2, not 4.
fn av1_dequant_denom(width : Int, height : Int) -> Int64 {
  let area = width * height
  if area > 1024 {
    4L
  } else if area > 256 {
    2L
  } else {
    1L
  }
}
