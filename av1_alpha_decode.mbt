/// Pure MoonBit reduced-still monochrome AV1 alpha reconstruction.
///
/// This stage handles one 32x32 or 64x64 DCT_DCT tile with 8-bit samples. It returns
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
  allow_screen_content_tools? : Bool = false,
  bit_depth? : Int = 8,
) -> Array[Byte]? {
  if (width != 32 && width != 64) || width != height ||
    base_q_idx < 0 || base_q_idx > 255 || tile_payload.length() == 0 ||
    tile_payload.length() > 255 {
    return None
  }
  if bit_depth != 8 && bit_depth != 10 && bit_depth != 12 { return None }
  if width == 64 {
    match av1_decode_alpha_split_tile(tile_payload, base_q_idx, allow_screen_content_tools, bit_depth) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  let decoder = av1_msac_new(tile_payload, true)
  let partition : Array[Int] = if width == 64 {
    [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0]
  } else {
    [18462, 20920, 23124, 27647, 28227, 29049, 29519, 30178, 31544, 32768, 0]
  }
  let skip : Array[Int] = [31671, 32768, 0]
  let y_mode : Array[Int] = [15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093, 30466, 32768, 0]
  if decoder.symbol(partition) != 0 || decoder.symbol(skip) != 0 || decoder.symbol(y_mode) != 0 {
    return None
  }
  if allow_screen_content_tools && decoder.symbol([32309, 32768, 0]) != 0 {
    return None
  }
  let all_zero = decoder.symbol(av1_alpha_luma_zero(base_q_idx))
  let side = width
  let mut residual : Array[Int] = Array::make(side * side, 0)
  if all_zero == 0 {
    let coeffs = match av1_decode_coeffs_square_with_decoder(
      decoder,
      base_q_idx,
      av1_coeff_context(base_q_idx, if width == 64 { 4 } else { 3 }, 0),
      bit_depth=bit_depth,
    ) {
      Some(value) => value
      None => return None
    }
    residual = match av1_inverse_dct_2d(coeffs, side, side, bit_depth) {
      Some(value) => value
      None => return None
    }
  } else if all_zero != 1 {
    return None
  }
  let out : Array[Byte] = []
  let neutral = 1 << (bit_depth - 1)
  let shift = bit_depth - 8
  for i in 0..<(side * side) {
    out.push(clamp_byte((neutral + residual[i]) >> shift))
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
  if !sequence.monochrome || sequence.width != sequence.height ||
    (sequence.width != 32 && sequence.width != 64) ||
    (sequence.bit_depth != 8 && sequence.bit_depth != 10 && sequence.bit_depth != 12) {
    return None
  }
  let frames = av1_obu_payloads(data, 6)
  if frames.length() == 0 { return None }
  let frame = match av1_parse_stage1_frame(frames[0], sequence, allow_monochrome=true, allow_highbd=true) {
    Some(value) => value
    None => return None
  }
  av1_decode_alpha_tile(
    sequence.width,
    sequence.height,
    frame.tile_payload,
    frame.base_q_idx,
    use_128x128_superblock=sequence.use_128x128_superblock,
    allow_screen_content_tools=frame.allow_screen_content_tools,
    bit_depth=sequence.bit_depth,
  )
}

fn av1_decode_alpha_split_tile(
  tile_payload : Array[Byte],
  base_q_idx : Int,
  allow_screen_content_tools : Bool,
  bit_depth : Int,
) -> Array[Byte]? {
  let decoder = av1_msac_new(tile_payload, true)
  if decoder.symbol(av1_split_partition_cdf(false)) != 3 { return None }
  let neutral = 1 << (bit_depth - 1)
  let shift = bit_depth - 8
  let plane : Array[Int] = Array::make(64 * 64, neutral)
  let context = av1_coeff_context(base_q_idx, 3, 0)
  for child in 0..<4 {
    if decoder.symbol(av1_split_skip_cdf()) != 0 { return None }
    if decoder.symbol(av1_split_y_mode_cdf()) != 0 { return None }
    if allow_screen_content_tools && decoder.symbol([32309, 32768, 0]) != 0 {
      return None
    }
    let all_zero = decoder.symbol(av1_split_luma_zero(base_q_idx))
    let residual = if all_zero == 1 {
      Array::make(32 * 32, 0)
    } else if all_zero == 0 {
      let coeffs = match av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, context, bit_depth=bit_depth) {
        Some(value) => value
        None => return None
      }
      match av1_inverse_dct_2d(coeffs, 32, 32, bit_depth) {
        Some(value) => value
        None => return None
      }
    } else { return None }
    let ox = (child % 2) * 32
    let oy = (child / 2) * 32
    for y in 0..<32 { for x in 0..<32 {
      plane[(oy + y) * 64 + ox + x] = neutral + residual[y * 32 + x]
    }}
  }
  let out : Array[Byte] = []
  for value in plane { out.push(clamp_byte(value >> shift)) }
  Some(out)
}

/// Decode the validated auxiliary alpha item from a complete AVIF container.
/// The result is a row-major 8-bit alpha plane for the supported 64x64 stage.
pub fn avif_decode_alpha(data : Array[Byte]) -> Array[Byte]? {
  let descriptor = match avif_alpha_item_descriptor(data) {
    Some(value) => value
    None => return None
  }
  let payload = match avif_alpha_item_payload(data) {
    Some(value) => value
    None => return None
  }
  // Keep the auxiliary item's declared geometry and bit depth tied to the
  // sequence header carried by its AV1 payload.  Without this check a valid
  // payload could be attached to a mismatched alpha descriptor and only fail
  // later as an opaque pixel-length error.
  let sequence = match av1_sequence_info(payload) {
    Some(value) => value
    None => return None
  }
  if sequence.width != descriptor.width || sequence.height != descriptor.height ||
    sequence.bit_depth != descriptor.bit_depth || !sequence.monochrome {
    return None
  }
  let alpha = match av1_decode_alpha(payload) {
    Some(value) => value
    None => return None
  }
  // The auxiliary item dimensions are authoritative at the container
  // boundary.  Reject a stream whose sequence header decodes to another
  // size instead of returning a plausible but misaligned plane.
  if descriptor.width <= 0 || descriptor.height <= 0 ||
    alpha.length() != descriptor.width * descriptor.height {
    return None
  }
  Some(alpha)
}

/// Decode a primary AVIF image and compose its validated auxiliary alpha item.
/// A valid image without an alpha item keeps the existing opaque result; an
/// alpha item that cannot be decoded is reported as `None` rather than dropped.
pub fn avif_decode_rgba(data : Array[Byte]) -> Image? {
  let image = match avif_decode(data) {
    Some(value) => value
    None => return None
  }
  let alpha_descriptor = avif_alpha_item_descriptor(data)
  match alpha_descriptor {
    None => Some(image)
    Some(_) => {
      let alpha = match avif_decode_alpha(data) {
        Some(value) => value
        None => return None
      }
      av1_apply_alpha(image, alpha)
    }
  }
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
