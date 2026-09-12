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
  bit_depth? : Int = 8,
) -> Int? {
  if (tx_ctx != 3 && tx_ctx != 4) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
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
  let dq = ((level * av1_dc_quant(bit_depth, base_q_idx)) & 0xFFFFFF) / denom
  let signed = if sign == 1 { -dq } else { dq }
  let side = if tx_ctx == 4 { 64 } else { 32 }
  let coeffs : Array[Int] = Array::make(side * side, 0)
  coeffs[0] = signed
  match av1_inverse_dct_2d(coeffs, side, side, bit_depth) {
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
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
) -> Image? {
  if (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    (bit_depth != 8 && width != 64) ||
    // High-bit-depth streams with larger residual payloads require the
    // remaining AC/partition syntax; reject them until that state machine is
    // implemented rather than returning a falsely neutral image.
    (bit_depth != 8 && tile_payload.length() > 8) ||
    (width != 32 && width != 64) ||
    (use_128x128_superblock && width != 64) ||
    width != height ||
    base_q_idx < 0 ||
    base_q_idx > 255 ||
    tile_payload.length() == 0 ||
    tile_payload.length() > (if width == 64 { 255 } else { 64 }) {
    return None
  }
  // Try the bounded four-child SPLIT path before the legacy single-block path.
  // A failed probe leaves no shared decoder state, so normal tiles continue.
  if width == 64 && bit_depth == 8 && !tx_mode_select {
    match
      av1_decode_split_tile_64x64(
        tile_payload,
        base_q_idx,
        disable_cdf_update~,
        full_range~,
        matrix_coefficients~,
        use_128x128_superblock~,
        allow_screen_content_tools~,
      ) {
      Some(image) => return Some(image)
      None => ()
    }
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
  if decoder.symbol(partition) != 0 || decoder.symbol(skip) != 0 {
    return None
  }
  let y_mode_symbol = decoder.symbol(y_mode)
  let uv_mode_symbol = decoder.symbol(uv_mode)
  if uv_mode_symbol != 0 {
    return None
  }
  if allow_screen_content_tools {
    let palette_y : Array[Int] = if width == 64 {
      [32450, 32768, 0]
    } else {
      [32309, 32768, 0]
    }
    if y_mode_symbol == 0 && decoder.symbol(palette_y) != 0 {
      return None
    }
    if decoder.symbol([32461, 32768, 0]) != 0 {
      return None
    }
  }
  if tx_mode_select {
    let leaves = match av1_decode_tx_tree(
      decoder,
      { row: 0, col: 0, width, height },
      0,
    ) {
      Some(value) => value
      None => return None
    }
    // The legacy reconstruction path can consume one transform block only;
    // multi-leaf coefficient assembly is the next traversal stage.
    if leaves.length() != 1 { return None }
  }
  let y_prediction = match
    av1_intra_predict(
      y_mode_symbol,
      width,
      height,
      [],
      [],
      0,
      bit_depth,
      have_above=false,
      have_left=false,
    ) {
    Some(value) => value
    None => return None
  }
  let luma_all_zero = decoder.symbol(luma_zero)
  let mut y_residual : Array[Int] = Array::make(width * height, 0)
  if luma_all_zero == 0 {
    if tx_mode_select {
      let tx_type = match av1_decode_intra_tx_type(decoder, width, width == 16) {
        Some(value) => value
        None => return None
      }
      match tx_type {
        Av1TxDctDct => ()
        _ => return None
      }
    }
    if width != 64 {
      return None
    }
    let coefficients = match
      av1_decode_coeffs_square_with_decoder(
        decoder,
        base_q_idx,
        y_coeff,
        bit_depth~,
      ) {
      Some(value) => value
      None => return None
    }
    y_residual = match av1_inverse_dct_2d(coefficients, 64, 64, bit_depth) {
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
        av1_decode_coeffs_square_with_decoder(
          decoder,
          base_q_idx,
          uv_coeff,
          bit_depth~,
        ) {
        Some(value) => value
        None => return None
      }
      u_residual = match av1_inverse_dct_2d(coefficients, 32, 32, bit_depth) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(
        decoder, base_q_idx, 3, uv_dc, bit_depth~,
      ) {
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
        av1_decode_coeffs_square_with_decoder(
          decoder,
          base_q_idx,
          uv_coeff,
          bit_depth~,
        ) {
        Some(value) => value
        None => return None
      }
      v_residual = match av1_inverse_dct_2d(coefficients, 32, 32, bit_depth) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(
        decoder, base_q_idx, 3, uv_dc, bit_depth~,
      ) {
        Some(value) => value
        None => return None
      }
      v_residual = Array::make(chroma_size * chroma_size, residual)
    }
  } else if cv != 1 {
    return None
  }
  let y : Array[Int] = []
  let u : Array[Int] = []
  let v : Array[Int] = []
  let neutral = 1 << (bit_depth - 1)
  for i in 0..<y_residual.length() {
    y.push(y_prediction[i] + y_residual[i])
  }
  for i in 0..<(chroma_size * chroma_size) {
    u.push(neutral + u_residual[i])
    v.push(neutral + v_residual[i])
  }
  av1_yuv420_highbd_to_rgba(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
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
  let header = av1_parse_stage1_frame(frames[0], seq, allow_highbd=true)
  match header {
    None => None
    Some(frame) =>
      av1_decode_dc_tile(
        seq.width,
        seq.height,
        frame.tile_payload,
        frame.base_q_idx,
        disable_cdf_update=frame.disable_cdf_update,
        allow_screen_content_tools=frame.allow_screen_content_tools,
        full_range=seq.full_range,
        matrix_coefficients=seq.matrix_coefficients,
        use_128x128_superblock=seq.use_128x128_superblock,
        bit_depth=seq.bit_depth,
        tx_mode_select=frame.tx_mode_select,
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
        allow_screen_content_tools=value.allow_screen_content_tools,
        full_range=value.full_range,
        matrix_coefficients=value.matrix_coefficients,
        use_128x128_superblock=value.use_128x128_superblock,
        bit_depth=value.bit_depth,
        tx_mode_select=value.tx_mode_select,
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
