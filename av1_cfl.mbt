/// AV1 CfL follows libaom cfl.c/cfl.h and the normative probability defaults
/// at revision 8e7b6a567df174d795479b92b4ac766d271add73.
/// Copyright (c) 2016, Alliance for Open Media. All rights reserved.
/// BSD 2 Clause License and Alliance for Open Media Patent License 1.0:
/// https://www.aomedia.org/license/software and https://www.aomedia.org/license/patent

///|
const AV1_INTRA_CFL : Int = 13

///|
/// The alpha probabilities are tile-local. U and V intentionally share the
/// same six adaptive rows. Reconstructed luma stays in Q3 until the complete
/// chroma prediction footprint has been padded and its rounded mean removed.
priv struct Av1CflState {
  sign : Array[Int]
  alpha : Array[Array[Int]]
  mut alpha_u : Int
  mut alpha_v : Int
  mut store_y : Bool
  mut base_x : Int
  mut base_y : Int
  recon_q3 : Array[Int]
  ac_q3 : Array[Int]
  mut buf_width : Int
  mut buf_height : Int
  mut ac_width : Int
  mut ac_height : Int
  mut ac_ready : Bool
}

///|
fn av1_cfl_state() -> Av1CflState {
  {
    sign: [1418, 2123, 13340, 18405, 26972, 28343, 32294, 32768, 0],
    alpha: [
      [
        7637, 20719, 31401, 32481, 32657, 32688, 32692, 32696, 32700, 32704, 32708,
        32712, 32716, 32720, 32724, 32768, 0,
      ],
      [
        14365, 23603, 28135, 31168, 32167, 32395, 32487, 32573, 32620, 32647, 32668,
        32672, 32676, 32680, 32684, 32768, 0,
      ],
      [
        11532, 22380, 28445, 31360, 32349, 32523, 32584, 32649, 32673, 32677, 32681,
        32685, 32689, 32693, 32697, 32768, 0,
      ],
      [
        26990, 31402, 32282, 32571, 32692, 32696, 32700, 32704, 32708, 32712, 32716,
        32720, 32724, 32728, 32732, 32768, 0,
      ],
      [
        17248, 26058, 28904, 30608, 31305, 31877, 32126, 32321, 32394, 32464, 32516,
        32560, 32576, 32593, 32622, 32768, 0,
      ],
      [
        14738, 21678, 25779, 27901, 29024, 30302, 30980, 31843, 32144, 32413, 32520,
        32594, 32622, 32656, 32660, 32768, 0,
      ],
    ],
    alpha_u: 0,
    alpha_v: 0,
    store_y: false,
    base_x: 0,
    base_y: 0,
    recon_q3: Array::make(32 * 32, 0),
    ac_q3: Array::make(32 * 32, 0),
    buf_width: 0,
    buf_height: 0,
    ac_width: 0,
    ac_height: 0,
    ac_ready: false,
  }
}

///|
/// joint_sign enumerates every U/V zero/negative/positive pair except (0,0).
/// Read U before V: for joint signs 3 and 7 both magnitudes use one CDF row.
fn av1_cfl_read_alphas(decoder : Av1SymbolDecoder, cfl : Av1CflState) -> Bool {
  let joint = decoder.symbol(cfl.sign)
  if joint < 0 || joint > 7 {
    return false
  }
  let sign_u = (joint + 1) / 3
  let sign_v = (joint + 1) % 3
  cfl.alpha_u = 0
  cfl.alpha_v = 0
  if sign_u != 0 {
    let magnitude = decoder.symbol(cfl.alpha[joint - 2]) + 1
    cfl.alpha_u = if sign_u == 1 { -magnitude } else { magnitude }
  }
  if sign_v != 0 {
    let magnitude = decoder.symbol(cfl.alpha[3 * sign_v + sign_u - 3]) + 1
    cfl.alpha_v = if sign_v == 1 { -magnitude } else { magnitude }
  }
  decoder.symbol_max_bits >= -14
}

///|
/// Sub-eight-pixel coding blocks share a buffer rooted at their enclosing
/// 8-pixel luma group. Do not clear it here: preceding non-owner blocks have
/// already stored the luma that the eventual chroma owner needs.
fn av1_cfl_begin_block(
  cfl : Av1CflState,
  block : Av1SbBlock,
  store_y : Bool,
) -> Unit {
  cfl.store_y = store_y
  let sub8 = block.width == 4 || block.height == 4
  cfl.base_x = if sub8 { block.col / 8 * 8 } else { block.col }
  cfl.base_y = if sub8 { block.row / 8 * 8 } else { block.row }
}

///|
/// Store the complete clipped reconstruction of one luma TX, including its
/// samples beyond the frame MI rectangle. 4:2:0 retains fractional precision
/// as Q3 = 2 * (Y00 + Y01 + Y10 + Y11), without an intermediate average.
fn av1_cfl_store_tx(
  cfl : Av1CflState,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  reconstruction : Array[Int],
) -> Bool {
  let col = (x - cfl.base_x) / 2
  let row = (y - cfl.base_y) / 2
  let store_width = width / 2
  let store_height = height / 2
  if x < cfl.base_x ||
    y < cfl.base_y ||
    width < 4 ||
    height < 4 ||
    width > 32 ||
    height > 32 ||
    width % 2 != 0 ||
    height % 2 != 0 ||
    reconstruction.length() != width * height ||
    col + store_width > 32 ||
    row + store_height > 32 {
    return false
  }
  if col == 0 && row == 0 {
    cfl.buf_width = store_width
    cfl.buf_height = store_height
  } else {
    if col + store_width > cfl.buf_width {
      cfl.buf_width = col + store_width
    }
    if row + store_height > cfl.buf_height {
      cfl.buf_height = row + store_height
    }
  }
  cfl.ac_ready = false
  for j in 0..<store_height {
    for i in 0..<store_width {
      let offset = 2 * j * width + 2 * i
      cfl.recon_q3[(row + j) * 32 + col + i] = (
          reconstruction[offset] +
          reconstruction[offset + 1] +
          reconstruction[offset + width] +
          reconstruction[offset + width + 1]
        ) <<
        1
    }
  }
  true
}

///|
/// Pad Q3 columns first, then rows, matching cfl_pad. Only after padding is
/// the rounded mean computed over the complete UV transform footprint.
fn av1_cfl_prepare(cfl : Av1CflState, width : Int, height : Int) -> Bool {
  if width < 4 ||
    height < 4 ||
    width > 32 ||
    height > 32 ||
    (width & (width - 1)) != 0 ||
    (height & (height - 1)) != 0 ||
    cfl.buf_width <= 0 ||
    cfl.buf_height <= 0 {
    return false
  }
  if cfl.ac_ready && cfl.ac_width == width && cfl.ac_height == height {
    return true
  }
  if cfl.buf_width < width {
    for row in 0..<cfl.buf_height {
      let last = cfl.recon_q3[row * 32 + cfl.buf_width - 1]
      for col in cfl.buf_width..<width {
        cfl.recon_q3[row * 32 + col] = last
      }
    }
    cfl.buf_width = width
  }
  if cfl.buf_height < height {
    for row in cfl.buf_height..<height {
      for col in 0..<width {
        cfl.recon_q3[row * 32 + col] = cfl.recon_q3[(row - 1) * 32 + col]
      }
    }
    cfl.buf_height = height
  }
  let count = width * height
  let mut sum = count / 2
  for row in 0..<height {
    for col in 0..<width {
      sum = sum + cfl.recon_q3[row * 32 + col]
    }
  }
  let mean = sum / count
  for row in 0..<height {
    for col in 0..<width {
      cfl.ac_q3[row * 32 + col] = cfl.recon_q3[row * 32 + col] - mean
    }
  }
  cfl.ac_width = width
  cfl.ac_height = height
  cfl.ac_ready = true
  true
}

///|
/// Round the Q6 product symmetrically, with half ties away from zero.
fn av1_cfl_scaled_luma(alpha_q3 : Int, ac_q3 : Int) -> Int {
  let product = alpha_q3 * ac_q3
  if product < 0 {
    -((-product + 32) >> 6)
  } else {
    (product + 32) >> 6
  }
}

///|
/// CfL adjusts an ordinary DC prediction. Clip this prediction before the
/// caller adds its chroma residual, which has a separate reconstruction clip.
fn av1_cfl_predict(
  cfl : Av1CflState,
  prediction : Array[Int],
  width : Int,
  height : Int,
  alpha_q3 : Int,
  bit_depth : Int,
) -> Bool {
  if prediction.length() != width * height ||
    alpha_q3 < -16 ||
    alpha_q3 > 16 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    !av1_cfl_prepare(cfl, width, height) {
    return false
  }
  for row in 0..<height {
    for col in 0..<width {
      let i = row * width + col
      prediction[i] = av1_intra_clip(
        prediction[i] + av1_cfl_scaled_luma(alpha_q3, cfl.ac_q3[row * 32 + col]),
        bit_depth,
      )
    }
  }
  true
}
