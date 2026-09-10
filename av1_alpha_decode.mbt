/// Pure MoonBit reduced-still monochrome AV1 alpha reconstruction.
///
/// This stage handles one 64x64 DCT_DCT tile with 8-bit samples. It returns
/// the decoded alpha plane; auxiliary-item extraction remains in
/// `avif_auxiliary.mbt` and composition is intentionally a later step.

fn av1_alpha_luma_zero(q : Int) -> Array[Int] {
  if q <= 20 { [6308, 32768, 0] }
  else if q <= 60 { [26584, 32768, 0] }
  else if q <= 120 { [28573, 32768, 0] }
  else { [31539, 32768, 0] }
}

pub fn av1_decode_alpha_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  use_128x128_superblock? : Bool = false,
) -> Array[Byte]? {
  if width != 64 || height != 64 || base_q_idx <= 0 || base_q_idx > 255 ||
    tile_payload.length() == 0 || tile_payload.length() > 64 {
    return None
  }
  let decoder = av1_msac_new(tile_payload, true)
  let partition : Array[Int] = [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0]
  let skip : Array[Int] = [31671, 32768, 0]
  let y_mode : Array[Int] = [15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093, 30466, 32768, 0]
  if decoder.symbol(partition) != 0 || decoder.symbol(skip) != 0 || decoder.symbol(y_mode) != 0 {
    return None
  }
  let all_zero = decoder.symbol(av1_alpha_luma_zero(base_q_idx))
  let mut residual : Array[Int] = Array::make(4096, 0)
  if all_zero == 0 {
    let coeffs = match av1_decode_coeffs_square_with_decoder(
      decoder,
      base_q_idx,
      av1_coeff_context(base_q_idx, 4, 0),
    ) {
      Some(value) => value
      None => return None
    }
    residual = match av1_inverse_dct_2d(coeffs, 64, 64, 8) {
      Some(value) => value
      None => return None
    }
  } else if all_zero != 1 {
    return None
  }
  let out : Array[Byte] = []
  for i in 0..<4096 {
    out.push(clamp_byte(128 + residual[i]))
  }
  let _ = use_128x128_superblock
  Some(out)
}

/// Decode the first monochrome alpha AV1 frame from a raw OBU stream.
pub fn av1_decode_alpha(data : Array[Byte]) -> Array[Byte]? {
  let sequence = match av1_sequence_info(data) {
    Some(value) => value
    None => return None
  }
  if !sequence.monochrome || sequence.width != 64 || sequence.height != 64 {
    return None
  }
  let frames = av1_obu_payloads(data, 6)
  if frames.length() == 0 { return None }
  let frame = match av1_parse_stage1_frame(frames[0], sequence, allow_monochrome=true) {
    Some(value) => value
    None => return None
  }
  av1_decode_alpha_tile(
    sequence.width,
    sequence.height,
    frame.tile_payload,
    frame.base_q_idx,
    use_128x128_superblock=sequence.use_128x128_superblock,
  )
}

/// Decode the validated auxiliary alpha item from a complete AVIF container.
/// The result is a row-major 8-bit alpha plane for the supported 64x64 stage.
pub fn avif_decode_alpha(data : Array[Byte]) -> Array[Byte]? {
  let payload = match avif_alpha_item_payload(data) {
    Some(value) => value
    None => return None
  }
  av1_decode_alpha(payload)
}

/// Compose a decoded alpha plane onto an RGBA image without changing RGB.
pub fn av1_apply_alpha(image : Image, alpha : Array[Byte]) -> Image? {
  if alpha.length() != image.width * image.height { return None }
  let out = Image::new(image.width, image.height)
  for y in 0..<image.height {
    for x in 0..<image.width {
      let p = image.get_pixel(x, y)
      out.set_pixel(x, y, p.0, p.1, p.2, alpha[y * image.width + x])
    }
  }
  Some(out)
}
