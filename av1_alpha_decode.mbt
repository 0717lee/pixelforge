/// Pure MoonBit monochrome reconstruction. Entropy, prediction,
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
  let (frame, _stripe_store, _cdfs) = match
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
/// Decode the first displayed monochrome frame through shared AV1 reconstruction.
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
  let frame = match avif_decode_alpha_frame(data) {
    Some(value) => value
    None => return None
  }
  Some(
    av1_alpha_samples_to_bytes(av1_alpha_full_samples(frame), frame.bit_depth),
  )
}

///|
/// Expand limited alpha in its original precision before UNORM narrowing.
/// libavif's read path applies this independently of the color item's range.
fn av1_alpha_full_samples(frame : Av1FramePlanes) -> Array[Int] {
  let samples = av1_frame_crop(frame, 0)
  if frame.full_range {
    return samples
  }
  let maximum = (1 << frame.bit_depth) - 1
  let black = 16 << (frame.bit_depth - 8)
  let span = 219 << (frame.bit_depth - 8)
  samples.map(fn(value) {
    let expanded = ((value - black) * maximum + span / 2) / span
    if expanded < 0 {
      0
    } else if expanded > maximum {
      maximum
    } else {
      expanded
    }
  })
}

///|
fn avif_decode_alpha_frame(data : Array[Byte]) -> Av1FramePlanes? {
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
    return Some(frame)
  }
  let payload = match avif_alpha_item_payload(data) {
    Some(value) => value
    None => return None
  }
  // Sequence dimensions are maxima. Check the selected frame's actual
  // dimensions below, after honoring this auxiliary item's layer selectors.
  let sequence = match av1_sequence_info(payload) {
    Some(value) => value
    None => return None
  }
  if sequence.width < descriptor.width ||
    sequence.height < descriptor.height ||
    sequence.bit_depth != descriptor.bit_depth ||
    !sequence.monochrome {
    return None
  }
  let (operating_point, spatial_layer) = match
    avif_item_layer_selection(data, descriptor.item_id) {
    Some(value) => value
    None => return None
  }
  let frame = match
    av1_decode_frame_planes(
      payload,
      allow_monochrome=true,
      operating_point~,
      spatial_layer~,
    ) {
    Some(value) => value
    None => return None
  }
  // The auxiliary item dimensions are authoritative at the container
  // boundary.  Reject a stream whose sequence header decodes to another
  // size instead of returning a plausible but misaligned plane.
  if descriptor.width <= 0 ||
    descriptor.height <= 0 ||
    frame.width != descriptor.width ||
    frame.height != descriptor.height ||
    frame.bit_depth != descriptor.bit_depth ||
    frame.planes.length() != 1 {
    return None
  }
  Some(frame)
}

///|
/// Decode a primary AVIF image and compose its validated auxiliary alpha item.
/// A valid image without an alpha item keeps the existing opaque result; an
/// alpha item that cannot be decoded is reported as `None` rather than dropped.
pub fn avif_decode_rgba(data : Array[Byte]) -> Image? {
  let alpha_descriptor = avif_alpha_descriptor_checked(data) catch {
    _ => return None
  }
  let frame = match avif_decode_frame(data) {
    Some(value) => value
    None => return None
  }
  match alpha_descriptor {
    None => av1_frame_to_rgba(frame)
    Some(descriptor) => {
      if descriptor.width != frame.width || descriptor.height != frame.height {
        return None
      }
      let alpha = match avif_decode_alpha_frame(data) {
        Some(value) => value
        None => return None
      }
      av1_frame_with_alpha(frame, alpha, descriptor.premultiplied)
    }
  }
}

///|
/// Produce straight RGBA using libavif's nearest-chroma conversion contract.
/// Standard matrices use its RGB8 unpremultiply path. Identity at high depth
/// and YCgCo retain native alpha through matrix conversion and final rounding.
fn av1_frame_with_alpha(
  color : Av1FramePlanes,
  alpha : Av1FramePlanes,
  premultiplied : Bool,
) -> Image? {
  if alpha.width != color.width ||
    alpha.height != color.height ||
    alpha.bit_depth != color.bit_depth ||
    alpha.planes.length() != 1 {
    return None
  }
  let native = av1_alpha_full_samples(alpha)
  let bytes = av1_alpha_samples_to_bytes(native, alpha.bit_depth)
  let matrix = color.matrix_coefficients
  let monochrome = color.planes.length() == 1
  let fused = premultiplied &&
    (
      color.color_primaries == 10 ||
      !(matrix == 1 ||
      matrix == 2 ||
      matrix == 4 ||
      matrix == 5 ||
      matrix == 6 ||
      matrix == 7 ||
      matrix == 9 ||
      matrix == 12 ||
      (matrix == 0 && color.bit_depth == 8 && color.full_range))
    )
  let converted = if fused {
    av1_yuv_highbd_to_rgba_core(
      color.width,
      color.height,
      av1_frame_crop(color, 0),
      if monochrome {
        []
      } else {
        av1_frame_crop(color, 1)
      },
      if monochrome {
        []
      } else {
        av1_frame_crop(color, 2)
      },
      color.bit_depth,
      subsampling_x=color.sub_x == 1,
      subsampling_y=color.sub_y == 1,
      full_range=color.full_range,
      matrix_coefficients=color.matrix_coefficients,
      color_primaries=color.color_primaries,
      transfer_characteristics=color.transfer_characteristics,
      native_alpha=Some(native),
      monochrome~,
    )
  } else {
    av1_frame_to_rgba(color)
  }
  let image = match converted {
    Some(value) => value
    None => return None
  }
  for i in 0..<bytes.length() {
    let coverage = bytes[i].to_int()
    if premultiplied && !fused {
      for channel in 0..<3 {
        let value = image.data[i * 4 + channel].to_int()
        image.data[i * 4 + channel] = if coverage == 0 {
          b'\x00'
        } else {
          clamp_byte((value * 255 + coverage / 2) / coverage)
        }
      }
    }
    image.data[i * 4 + 3] = bytes[i]
  }
  Some(image)
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
