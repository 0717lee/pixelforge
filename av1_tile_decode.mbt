/// First executable AV1 tile milestone.
///
/// This module intentionally accepts one very small, fully specified subset:
/// a 32x32 or 64x64 reduced-still key frame, one tile, DC intra prediction,
/// and single-DC residuals. Entropy
/// symbols are decoded from the tile with the stateful MSAC reader. Other
/// streams return None and remain eligible for later tile/transform milestones.

/// Decode one EOB=1 DC coefficient from the stateful tile reader. `tx_ctx`
/// selects the transform size context (3 for 32x32, 4 for 64x64), while
/// `ptype` selects luma (0) or chroma (1). The result is a signed sample
/// offset from the intra DC level 128.
fn av1_decode_single_dc(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  tx_ctx : Int,
  ptype : Int,
) -> Int? {
  if (tx_ctx != 3 && tx_ctx != 4) || (ptype != 0 && ptype != 1) {
    return None
  }
  if decoder.symbol(av1_dc_eob1024_cdf(base_q_idx, ptype)) != 0 {
    return None
  }
  let mut level = decoder.symbol(av1_dc_base_eob_dc_cdf(base_q_idx, tx_ctx, ptype)) + 1
  let br = av1_dc_br_cdf(base_q_idx, ptype)
  let mut complete = false
  for _ in 0..<4 {
    if complete { continue }
    let extra = decoder.symbol(br)
    level = level + extra
    if extra < 3 { complete = true }
  }
  if level > 14 {
    let mut length = 0
    let mut terminated = false
    while length < 32 && !terminated {
      length = length + 1
      terminated = decoder.bool() == 1
    }
    if !terminated { return None }
    let mut code = 1
    for _ in 0..<(length - 1) {
      code = (code << 1) | decoder.bool()
    }
    level = code + 14
  }
  if level > 65535 { return None }
  let sign = decoder.symbol(av1_dc_sign_cdf(base_q_idx, ptype))
  let dequant = level * av1_dc_quant_8(base_q_idx) / 4
  let magnitude = if tx_ctx == 4 {
    (dequant * 12 + 32) / 64
  } else {
    (dequant * 8 + 16) / 32
  }
  Some(if sign == 1 { -magnitude } else { magnitude })
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
) -> Image? {
  if (width != 32 && width != 64) ||
    width != height ||
    base_q_idx <= 0 ||
    base_q_idx > 255 ||
    tile_payload.length() == 0 ||
    tile_payload.length() > 4 {
    return None
  }
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
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
    if base_q_idx <= 20 { [6308, 32768, 0] } else if base_q_idx <= 60 { [26584, 32768, 0] } else if base_q_idx <= 120 { [28573, 32768, 0] } else { [31539, 32768, 0] }
  } else {
    if base_q_idx <= 20 { [17920, 32768, 0] } else if base_q_idx <= 60 { [26726, 32768, 0] } else if base_q_idx <= 120 { [30669, 32768, 0] } else { [31671, 32768, 0] }
  }
  let chroma_zero : Array[Int] = if width == 64 {
    if base_q_idx <= 20 { [1366, 32768, 0] } else if base_q_idx <= 60 { [5583, 32768, 0] } else if base_q_idx <= 120 { [5124, 32768, 0] } else { [4656, 32768, 0] }
  } else {
    if base_q_idx <= 20 { [3778, 32768, 0] } else if base_q_idx <= 60 { [4215, 32768, 0] } else if base_q_idx <= 120 { [3648, 32768, 0] } else { [3440, 32768, 0] }
  }
  if decoder.symbol(partition) != 0 ||
    decoder.symbol(skip) != 0 ||
    decoder.symbol(y_mode) != 0 ||
    decoder.symbol(uv_mode) != 0 {
    return None
  }
  let luma_all_zero = decoder.symbol(luma_zero)
  let mut luma_value = 128
  if luma_all_zero == 0 {
    if width != 64 { return None }
    let residual = match av1_decode_single_dc(decoder, base_q_idx, 4, 0) {
      Some(value) => value
      None => return None
    }
    luma_value = 128 + residual
  } else if luma_all_zero != 1 {
    return None
  }
  let cu = decoder.symbol(chroma_zero)
  let cv = decoder.symbol(chroma_zero)
  if (cu != 0 && cu != 1) || (cv != 0 && cv != 1) { return None }
  let mut u_value = 128
  if cu == 0 {
    let residual = match av1_decode_single_dc(decoder, base_q_idx, 3, 1) {
      Some(value) => value
      None => return None
    }
    u_value = u_value + residual
  }
  let mut v_value = 128
  if cv == 0 {
    let residual = match av1_decode_single_dc(decoder, base_q_idx, 3, 1) {
      Some(value) => value
      None => return None
    }
    v_value = v_value + residual
  }
  let y : Array[Byte] = []
  let u : Array[Byte] = []
  let v : Array[Byte] = []
  let luma = clamp_byte(luma_value)
  for _ in 0..<(width * height) {
    y.push(luma)
  }
  for _ in 0..<(width / 2 * (height / 2)) {
    u.push(clamp_byte(u_value))
    v.push(clamp_byte(v_value))
  }
  av1_yuv420_to_rgba_color(width, height, y, u, v, full_range=full_range, matrix_coefficients=matrix_coefficients)
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
  if
    seq.matrix_coefficients != 1 &&
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
      )
  }
}

///|
test "single DC helper decodes a chroma coefficient" {
  let decoder = av1_msac_new([b'\x00', b'\x00'], false)
  let residual = av1_decode_single_dc(decoder, 33, 3, 1).unwrap()
  assert_eq(residual, 2)
}
