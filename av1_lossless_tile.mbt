///|
/// Decode ONLY_4X4 residuals for an intra block with zero quantizer deltas.
/// Prediction is reconstructed per transform before the next transform reads
/// its edges. Probability rows are shared between U/V; neighbour levels are
/// separate for each plane.
fn av1_decode_lossless_intra_block(
  decoder : Av1SymbolDecoder,
  width : Int,
  height : Int,
  y_mode : Int,
  uv_mode : Int,
  bit_depth : Int,
  full_range : Bool,
  matrix_coefficients : Int,
) -> Image? {
  let tables = av1_tx_ent_tables(0)
  let y_context = av1_coeff_context(0, 0, 0)
  let uv_context = av1_coeff_context(0, 0, 1)
  let planes : Array[Array[Int]] = []
  for plane in 0..<3 {
    let pw = if plane == 0 { width } else { width / 2 }
    let ph = if plane == 0 { height } else { height / 2 }
    if pw % 4 != 0 || ph % 4 != 0 {
      return None
    }
    let samples = Array::make(pw * ph, 0)
    let above_level = Array::make(pw / 4, 0)
    let left_level = Array::make(ph / 4, 0)
    let above_dc = Array::make(pw / 4, 0)
    let left_dc = Array::make(ph / 4, 0)
    let context = if plane == 0 { y_context } else { uv_context }
    let mode = if plane == 0 { y_mode } else { uv_mode }
    for y4 in 0..<(ph / 4) {
      for x4 in 0..<(pw / 4) {
        let x = x4 * 4
        let y = y4 * 4
        let above : Array[Int] = []
        let left : Array[Int] = []
        for i in 0..<4 {
          if y > 0 {
            above.push(samples[(y - 1) * pw + x + i])
          }
          if x > 0 {
            left.push(samples[(y + i) * pw + x - 1])
          }
        }
        let corner = if x > 0 && y > 0 {
          samples[(y - 1) * pw + x - 1]
        } else {
          0
        }
        let prediction = match
          av1_intra_predict(
            mode,
            4,
            4,
            above,
            left,
            corner,
            bit_depth,
            have_above=y > 0,
            have_left=x > 0,
          ) {
          Some(value) => value
          None => return None
        }
        let whole = pw == 4 && ph == 4
        let skip_context = if plane == 0 {
          av1_txb_skip_ctx_luma(above_level[x4], left_level[y4], whole)
        } else {
          av1_txb_skip_ctx_chroma(
            above_level[x4] > 0,
            left_level[y4] > 0,
            whole,
          )
        }
        let all_zero = decoder.symbol(tables.txb_skip[0][skip_context])
        let residual = if all_zero == 1 {
          above_level[x4] = 0
          left_level[y4] = 0
          above_dc[x4] = 0
          left_dc[y4] = 0
          Array::make(16, 0)
        } else {
          let sign_context = av1_dc_sign_ctx_from(above_dc, left_dc, x4, y4, 1)
          let decoded = match
            av1_decode_coeffs_leaf_with_decoder(
              decoder,
              0,
              context,
              4,
              bit_depth~,
              dc_sign_ctx=sign_context,
            ) {
            Some(value) => value
            None => return None
          }
          above_level[x4] = decoded.cul_level
          left_level[y4] = decoded.cul_level
          above_dc[x4] = decoded.dc_category
          left_dc[y4] = decoded.dc_category
          match
            av1_inverse_dct_2d(decoded.coeffs, 4, 4, bit_depth, lossless=true) {
            Some(value) => value
            None => return None
          }
        }
        for i in 0..<4 {
          for j in 0..<4 {
            samples[(y + i) * pw + x + j] = av1_intra_clip(
              prediction[i * 4 + j] + residual[i * 4 + j],
              bit_depth,
            )
          }
        }
      }
    }
    planes.push(samples)
  }
  if decoder.symbol_max_bits < -14 {
    return None
  }
  av1_yuv420_highbd_to_rgba(
    width,
    height,
    planes[0],
    planes[1],
    planes[2],
    bit_depth,
    full_range~,
    matrix_coefficients~,
  )
}
