/// First executable AV1 tile milestone.
///
/// This module intentionally accepts one very small, fully specified subset:
/// a 32x32 or 64x64 reduced-still key frame, one tile, DC intra prediction,
/// with square DCT_DCT residuals. Entropy
/// symbols are decoded from the tile with the stateful MSAC reader. Other
/// streams return None and remain eligible for later tile/transform milestones.

///|
/// Mutable CDF state for one transform context. UV blocks share one context
/// for the tile, as required by the AV1 symbol update process.
priv struct Av1DcContext {
  eob : Array[Int]
  base : Array[Int]
  br : Array[Int]
  sign : Array[Int]
}

///|
/// Decode an EOB=1 DC coefficient and run the exact integer inverse DCT.
fn av1_decode_single_dc(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  tx_ctx : Int,
  context : Av1DcContext,
) -> Int? {
  if tx_ctx != 3 && tx_ctx != 4 {
    return None
  }
  if decoder.symbol(context.eob) != 0 {
    return None
  }
  let mut level = decoder.symbol(context.base) + 1
  if level > 2 {
    let mut complete = false
    for _ in 0..<4 {
      if complete {
        continue
      }
      let extra = decoder.symbol(context.br)
      level = level + extra
      if extra < 3 {
        complete = true
      }
    }
  }
  let sign = decoder.symbol(context.sign)
  if level > 14 {
    let mut length = 0
    let mut terminated = false
    while length < 32 && !terminated {
      length = length + 1
      terminated = decoder.bool() == 1
    }
    if !terminated {
      return None
    }
    let mut code = 1
    for _ in 0..<(length - 1) {
      code = (code << 1) | decoder.bool()
    }
    level = code + 14
  }
  if level > 65535 {
    return None
  }
  let denom = if tx_ctx == 4 { 4 } else { 2 }
  let dq = ((level * av1_dc_quant_8(base_q_idx)) & 0xFFFFFF) / denom
  let signed = if sign == 1 { -dq } else { dq }
  let side = if tx_ctx == 4 { 64 } else { 32 }
  let coeffs : Array[Int] = Array::make(side * side, 0)
  coeffs[0] = signed
  match av1_inverse_dct_2d(coeffs, side, side, 8) {
    Some(residual) => Some(residual[0])
    None => None
  }
}

///|
pub fn av1_decode_dc_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
) -> Image? {
  if (width != 32 && width != 64) ||
    (use_128x128_superblock && width != 64) ||
    width != height ||
    base_q_idx <= 0 ||
    base_q_idx > 255 ||
    tile_payload.length() == 0 ||
    tile_payload.length() > 64 {
    return None
  }
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  let y_coeff = av1_coeff_context(base_q_idx, 4, 0)
  let uv_coeff = av1_coeff_context(base_q_idx, 3, 1)
  let uv_dc = Av1DcContext::{
    eob: av1_dc_eob1024_cdf(base_q_idx, 1),
    base: av1_dc_base_eob_dc_cdf(base_q_idx, 3, 1),
    br: av1_dc_br_cdf(base_q_idx, 1),
    sign: av1_dc_sign_cdf(base_q_idx, 1),
  }
  // A 64x64 frame with the 128x128 sequence tool reaches the
  // child 64x64 partition node at the frame edge, so W64 CDF applies.
  let partition : Array[Int] = if width == 64 {
    [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0]
  } else {
    [18462, 20920, 23124, 27647, 28227, 29049, 29519, 30178, 31544, 32768, 0]
  }
  let skip : Array[Int] = [31671, 32768, 0]
  let y_mode : Array[Int] = [
    15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093,
    30466, 32768, 0,
  ]
  let uv_mode : Array[Int] = [
    22631, 24152, 25378, 25661, 25986, 26520, 27055, 27923, 28244, 30059, 30941,
    31961, 32768, 0,
  ]
  let luma_zero : Array[Int] = if width == 64 {
    if base_q_idx <= 20 {
      [6308, 32768, 0]
    } else if base_q_idx <= 60 {
      [26584, 32768, 0]
    } else if base_q_idx <= 120 {
      [28573, 32768, 0]
    } else {
      [31539, 32768, 0]
    }
  } else if base_q_idx <= 20 {
    [17920, 32768, 0]
  } else if base_q_idx <= 60 {
    [26726, 32768, 0]
  } else if base_q_idx <= 120 {
    [30669, 32768, 0]
  } else {
    [31671, 32768, 0]
  }
  let chroma_zero : Array[Int] = if width == 64 {
    if base_q_idx <= 20 {
      [1366, 32768, 0]
    } else if base_q_idx <= 60 {
      [5583, 32768, 0]
    } else if base_q_idx <= 120 {
      [5124, 32768, 0]
    } else {
      [4656, 32768, 0]
    }
  } else if base_q_idx <= 20 {
    [3778, 32768, 0]
  } else if base_q_idx <= 60 {
    [4215, 32768, 0]
  } else if base_q_idx <= 120 {
    [3648, 32768, 0]
  } else {
    [3440, 32768, 0]
  }
  if decoder.symbol(partition) != 0 ||
    decoder.symbol(skip) != 0 ||
    decoder.symbol(y_mode) != 0 ||
    decoder.symbol(uv_mode) != 0 {
    return None
  }
  let luma_all_zero = decoder.symbol(luma_zero)
  let mut y_residual : Array[Int] = Array::make(width * height, 0)
  if luma_all_zero == 0 {
    if width != 64 {
      return None
    }
    let coefficients = match
      av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, y_coeff) {
      Some(value) => value
      None => return None
    }
    y_residual = match av1_inverse_dct_2d(coefficients, 64, 64, 8) {
      Some(value) => value
      None => return None
    }
  } else if luma_all_zero != 1 {
    return None
  }
  let cu = decoder.symbol(chroma_zero)
  let chroma_size = width / 2
  let mut u_residual : Array[Int] = Array::make(chroma_size * chroma_size, 0)
  if cu == 0 {
    if width == 64 {
      let coefficients = match
        av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, uv_coeff) {
        Some(value) => value
        None => return None
      }
      u_residual = match av1_inverse_dct_2d(coefficients, 32, 32, 8) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(decoder, base_q_idx, 3, uv_dc) {
        Some(value) => value
        None => return None
      }
      u_residual = Array::make(chroma_size * chroma_size, residual)
    }
  } else if cu != 1 {
    return None
  }
  let cv = decoder.symbol(chroma_zero)
  let mut v_residual : Array[Int] = Array::make(chroma_size * chroma_size, 0)
  if cv == 0 {
    if width == 64 {
      let coefficients = match
        av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, uv_coeff) {
        Some(value) => value
        None => return None
      }
      v_residual = match av1_inverse_dct_2d(coefficients, 32, 32, 8) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(decoder, base_q_idx, 3, uv_dc) {
        Some(value) => value
        None => return None
      }
      v_residual = Array::make(chroma_size * chroma_size, residual)
    }
  } else if cv != 1 {
    return None
  }
  let y : Array[Byte] = []
  let u : Array[Byte] = []
  let v : Array[Byte] = []
  for residual in y_residual {
    y.push(clamp_byte(128 + residual))
  }
  for i in 0..<(chroma_size * chroma_size) {
    u.push(clamp_byte(128 + u_residual[i]))
    v.push(clamp_byte(128 + v_residual[i]))
  }
  av1_yuv420_to_rgba_color(
    width,
    height,
    y,
    u,
    v,
    full_range~,
    matrix_coefficients~,
  )
}

///|
/// Decodes a reduced-still AV1 OBU stream when it matches the first tile
/// milestone. The input is the AV1 item payload extracted from AVIF.
pub fn av1_decode(data : Array[Byte]) -> Image? {
  let sequence = av1_sequence_info(data)
  let seq = match sequence {
    None => return None
    Some(value) => value
  }
  let frames = av1_obu_payloads(data, 6)
  if seq.matrix_coefficients != 1 &&
    seq.matrix_coefficients != 2 &&
    seq.matrix_coefficients != 5 &&
    seq.matrix_coefficients != 6 {
    return None
  }
  if frames.length() == 0 {
    return None
  }
  let header = av1_parse_stage1_frame(frames[0], seq)
  match header {
    None => None
    Some(frame) =>
      av1_decode_dc_tile(
        seq.width,
        seq.height,
        frame.tile_payload,
        frame.base_q_idx,
        disable_cdf_update=frame.disable_cdf_update,
        full_range=seq.full_range,
        matrix_coefficients=seq.matrix_coefficients,
        use_128x128_superblock=seq.use_128x128_superblock,
      )
  }
}

///|
/// Decodes an AVIF container through the same pure MoonBit stage-one tile
/// path. Unsupported profiles, alpha items, and non-DC tiles return None.
pub fn avif_decode(data : Array[Byte]) -> Image? {
  let input = avif_stage1_input(data)
  match input {
    None => None
    Some(value) =>
      av1_decode_dc_tile(
        value.width,
        value.height,
        value.tile_payload,
        value.base_q_idx,
        disable_cdf_update=value.disable_cdf_update,
        full_range=value.full_range,
        matrix_coefficients=value.matrix_coefficients,
        use_128x128_superblock=value.use_128x128_superblock,
      )
  }
}

///|
test "single DC helper decodes a chroma coefficient" {
  let decoder = av1_msac_new([b'\x00', b'\x00'], false)
  let context = Av1DcContext::{
    eob: av1_dc_eob1024_cdf(33, 1),
    base: av1_dc_base_eob_dc_cdf(33, 3, 1),
    br: av1_dc_br_cdf(33, 1),
    sign: av1_dc_sign_cdf(33, 1),
  }
  let residual = av1_decode_single_dc(decoder, 33, 3, context).unwrap()
  assert_eq(residual, 0)
}
