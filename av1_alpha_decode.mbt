/// Pure MoonBit reduced-still monochrome reconstruction. Entropy, prediction,
/// transforms and frame filtering share the color decoder's native-depth path.

///|
/// Match libavif's UNORM alpha conversion: round(src * dstMax / srcMax).
/// This preserves both endpoints and low alpha values at 10/12-bit depth.
/// Reference: libavif v1.4.2 src/alpha.c, avifReformatAlpha.
fn av1_alpha_samples_to_bytes(
  samples : Array[Int],
  bit_depth : Int,
) -> Array[Byte] {
  let maximum = (1 << bit_depth) - 1
  samples.map(fn(value) { ((value * 255 + maximum / 2) / maximum).to_byte() })
}

///|
/// Decode a complete monochrome intra tile, including AC, lossless transforms
/// and supported intra modes. Frame filters run before quantizing alpha to eight bits.
/// Width is coded; optional upscaled_width is applied before alpha conversion.
pub fn av1_decode_alpha_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  use_128x128_superblock? : Bool = false,
  allow_screen_content_tools? : Bool = false,
  bit_depth? : Int = 8,
  disable_cdf_update? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
  restoration? : Av1RestorationConfig? = None,
  upscaled_width? : Int = 0,
  quant_deltas? : Av1QuantDeltas = {
    y_dc: 0,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  },
) -> Array[Byte]? {
  let (frame, _stripe_store) = match
    av1_decode_tile_planes(
      width,
      height,
      [0, width],
      [0, height],
      tile_payload,
      0,
      base_q_idx,
      disable_cdf_update,
      allow_screen_content_tools,
      true,
      2,
      use_128x128_superblock,
      bit_depth,
      reduced_tx_set,
      enable_filter_intra,
      tx_mode_select,
      cdef,
      monochrome=true,
      enable_intra_edge_filter~,
      loop_filter~,
      restoration~,
      upscaled_width~,
      quant_deltas~,
    ) {
    Some(value) => value
    None => return None
  }
  Some(av1_alpha_samples_to_bytes(av1_frame_crop(frame, 0), frame.bit_depth))
}

///|
/// Decode a monochrome OBU frame through shared intra traversal and filters.
/// Alpha represents coverage, so its final conversion always uses full UNORM.
pub fn av1_decode_alpha(data : Array[Byte]) -> Array[Byte]? {
  let frame = match av1_decode_frame_planes(data, allow_monochrome=true) {
    Some(value) => value
    None => return None
  }
  if frame.planes.length() != 1 {
    return None
  }
  Some(av1_alpha_samples_to_bytes(av1_frame_crop(frame, 0), frame.bit_depth))
}

///|
/// Decode the validated auxiliary alpha item from a complete AVIF container.
/// The result is a row-major 8-bit alpha plane, rounded from its native depth.
pub fn avif_decode_alpha(data : Array[Byte]) -> Array[Byte]? {
  let descriptor = match avif_alpha_item_descriptor(data) {
    Some(value) => value
    None => return None
  }
  if avif_grid_descriptor_for_item(data, Some(descriptor.item_id)) is Some(grid) {
    let frame = match avif_decode_grid_frame(data, grid) {
      Some(value) => value
      None => return None
    }
    if frame.planes.length() != 1 ||
      frame.width != descriptor.width ||
      frame.height != descriptor.height ||
      frame.bit_depth != descriptor.bit_depth {
      return None
    }
    return Some(
      av1_alpha_samples_to_bytes(av1_frame_crop(frame, 0), frame.bit_depth),
    )
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
  if sequence.width != descriptor.width ||
    sequence.height != descriptor.height ||
    sequence.bit_depth != descriptor.bit_depth ||
    !sequence.monochrome {
    return None
  }
  let alpha = match av1_decode_alpha(payload) {
    Some(value) => value
    None => return None
  }
  // The auxiliary item dimensions are authoritative at the container
  // boundary.  Reject a stream whose sequence header decodes to another
  // size instead of returning a plausible but misaligned plane.
  if descriptor.width <= 0 ||
    descriptor.height <= 0 ||
    alpha.length() != descriptor.width * descriptor.height {
    return None
  }
  Some(alpha)
}

///|
/// Decode a primary AVIF image and compose its validated auxiliary alpha item.
/// A valid image without an alpha item keeps the existing opaque result; an
/// alpha item that cannot be decoded is reported as `None` rather than dropped.
pub fn avif_decode_rgba(data : Array[Byte]) -> Image? {
  let alpha_descriptor = avif_alpha_descriptor_checked(data) catch {
    _ => return None
  }
  let image = match avif_decode(data) {
    Some(value) => value
    None => return None
  }
  match alpha_descriptor {
    None => Some(image)
    Some(descriptor) => {
      if descriptor.width != image.width || descriptor.height != image.height {
        return None
      }
      let alpha = match avif_decode_alpha(data) {
        Some(value) => value
        None => return None
      }
      av1_apply_alpha(image, alpha)
    }
  }
}

///|
/// Compose a decoded alpha plane onto an RGBA image without changing RGB.
pub fn av1_apply_alpha(image : Image, alpha : Array[Byte]) -> Image? {
  if alpha.length() != image.width * image.height {
    return None
  }
  let out = Image::new(image.width, image.height)
  for y in 0..<image.height {
    for x in 0..<image.width {
      let p = image.get_pixel(x, y)
      out.set_pixel(x, y, p.0, p.1, p.2, alpha[y * image.width + x])
    }
  }
  Some(out)
}
