/// First executable AV1 tile milestone.
///
/// This module intentionally accepts one very small, fully specified subset:
/// a 64x64 reduced-still key frame, one tile, DC intra prediction, and skipped
/// (all-zero) luma/chroma residuals. The entropy symbols are decoded from the
/// tile with the stateful MSAC reader; the uniform 128 sample is the AV1 DC
/// predictor for a frame with no available neighbours. Other streams return
/// None and remain eligible for later tile/transform milestones.

///|
pub fn av1_decode_dc_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
) -> Image? {
  if width != 64 ||
    height != 64 ||
    base_q_idx <= 0 ||
    base_q_idx > 255 ||
    tile_payload.length() == 0 {
    return None
  }
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  let partition : Array[Int] = [
    20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0,
  ]
  let skip : Array[Int] = [31671, 32768, 0]
  let y_mode : Array[Int] = [
    15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093,
    30466, 32768, 0,
  ]
  let uv_mode : Array[Int] = [
    22631, 24152, 25378, 25661, 25986, 26520, 27055, 27923, 28244, 30059, 30941,
    31961, 32768, 0,
  ]
  let luma_zero : Array[Int] = if base_q_idx <= 20 {
    [6308, 32768, 0]
  } else if base_q_idx <= 60 {
    [26584, 32768, 0]
  } else if base_q_idx <= 120 {
    [28573, 32768, 0]
  } else {
    [31539, 32768, 0]
  }
  let chroma_zero : Array[Int] = if base_q_idx <= 20 {
    [1366, 32768, 0]
  } else if base_q_idx <= 60 {
    [5583, 32768, 0]
  } else if base_q_idx <= 120 {
    [5124, 32768, 0]
  } else {
    [4656, 32768, 0]
  }
  if decoder.symbol(partition) != 0 ||
    decoder.symbol(skip) != 0 ||
    decoder.symbol(y_mode) != 0 ||
    decoder.symbol(uv_mode) != 0 ||
    decoder.symbol(luma_zero) != 1 ||
    decoder.symbol(chroma_zero) != 1 ||
    decoder.symbol(chroma_zero) != 1 {
    return None
  }
  let y : Array[Byte] = []
  let u : Array[Byte] = []
  let v : Array[Byte] = []
  for _ in 0..<(width * height) {
    y.push(b'\x80')
  }
  for _ in 0..<(width / 2 * (height / 2)) {
    u.push(b'\x80')
    v.push(b'\x80')
  }
  av1_yuv420_to_rgba(width, height, y, u, v)
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
  if seq.full_range ||
    (
      seq.matrix_coefficients != 2 &&
      seq.matrix_coefficients != 5 &&
      seq.matrix_coefficients != 6
    ) {
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
      )
  }
}
