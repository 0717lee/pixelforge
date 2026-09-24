/// Minimal AV1 `show_existing_frame` envelope parsing.
///
/// This parser deliberately stops at the uncompressed-header envelope.  It
/// validates the fields needed to display a previously decoded reference
/// frame, but it does not claim to decode inter prediction or reference
/// pixels.  The reduced-still parser remains in `av1_frame_header.mbt` and is
/// intentionally independent from this API.

///|
/// Sequence-level syntax needed by `show_existing_frame` (§5.9.2).
pub(all) struct Av1ShowExistingFrameConfig {
  /// Whether decoder model information is present in the active sequence.
  decoder_model_info_present : Bool
  /// `equal_picture_interval` from the operating point timing parameters.
  equal_picture_interval : Bool
  /// `frame_presentation_time` width minus one (§5.9.31).
  frame_presentation_time_length_minus_1 : Int
  /// Whether frame IDs are present in the sequence header.
  frame_id_numbers_present : Bool
  /// `additional_frame_id_length_minus_1` from the sequence header.
  additional_frame_id_len_minus1 : Int
  /// `delta_frame_id_length_minus_2` from the sequence header.
  delta_frame_id_length_minus2 : Int
  /// The current reference-frame type for each of the eight map slots.
  /// Supplying fewer than eight entries is rejected so an encoded map index
  /// can never silently address an absent slot.
  reference_frame_types : Array[Int]
}

///|
/// Parsed fields from an AV1 `show_existing_frame` header.
///
/// `frame_presentation_time` and `display_frame_id` are optional because the
/// corresponding sequence features are optional.  `reference_frame_type` is
/// metadata from the caller's reference-frame state; it does not decode any
/// pixels.
pub(all) struct Av1ShowExistingFrameEnvelope {
  show_existing_frame : Bool
  frame_to_show_map_idx : Int
  reference_frame_type : Int
  frame_presentation_time : Int64?
  display_frame_id : Int?
  header_bits : Int
  header_bytes : Int
}

///|
/// Parse the minimal `show_existing_frame` prefix of an AV1 frame header.
///
/// The first bit must be one.  The parser then consumes the three-bit map
/// index, the conditional temporal-point timing field, and the conditional
/// frame ID, rejecting truncation, invalid field widths, and map indices for
/// which the supplied reference state has no slot.  Remaining frame-header
/// syntax is intentionally outside this envelope and is not interpreted.
pub fn av1_parse_show_existing_frame(
  frame_payload : Array[Byte],
  config : Av1ShowExistingFrameConfig,
) -> Av1ShowExistingFrameEnvelope? {
  if config.reference_frame_types.length() < 8 {
    return None
  }
  let reader : Av1FrameBits = { data: frame_payload, bit_pos: 0, }
  let show_existing_frame = match reader.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if !show_existing_frame {
    // This API is intentionally scoped to the reference-display branch.  A
    // regular frame header must be parsed by the full frame-state path.
    return None
  }
  let frame_to_show_map_idx = match reader.take(3) {
    Some(v) => v
    None => return None
  }
  if frame_to_show_map_idx < 0 ||
    frame_to_show_map_idx >= config.reference_frame_types.length() {
    return None
  }

  let mut frame_presentation_time : Int64? = None
  if config.decoder_model_info_present && !config.equal_picture_interval {
    let count = config.frame_presentation_time_length_minus_1 + 1
    if count < 1 || count > 32 {
      return None
    }
    frame_presentation_time = match av1_frame_timing_value(reader, count) {
      Some(v) => Some(v)
      None => return None
    }
  }

  let mut display_frame_id : Int? = None
  if config.frame_id_numbers_present {
    if config.additional_frame_id_len_minus1 < 0 ||
      config.delta_frame_id_length_minus2 < 0 {
      return None
    }
    let count = config.additional_frame_id_len_minus1 +
      config.delta_frame_id_length_minus2 +
      3
    if count < 3 || count > 16 {
      return None
    }
    display_frame_id = match reader.take(count) {
      Some(v) => Some(v)
      None => return None
    }
  }
  Some({
    show_existing_frame,
    frame_to_show_map_idx,
    reference_frame_type: config.reference_frame_types[frame_to_show_map_idx],
    frame_presentation_time,
    display_frame_id,
    header_bits: reader.bit_pos,
    header_bytes: (reader.bit_pos + 7) / 8,
  })
}

///|
/// Timing syntax is unsigned and may use all 32 bits. Read bounded halves and
/// widen before combining so values above 2^31-1 stay positive on every target.
fn av1_frame_timing_value(reader : Av1FrameBits, count : Int) -> Int64? {
  if count < 1 || count > 32 {
    return None
  }
  if count <= 16 {
    return reader.take(count).map(value => value.to_int64())
  }
  let high = match reader.take(count - 16) {
    Some(value) => value
    None => return None
  }
  let low = match reader.take(16) {
    Some(value) => value
    None => return None
  }
  Some((high.to_int64() << 16) | low.to_int64())
}

///|
/// Explicitly named alias for callers that prefer the envelope terminology.
pub fn av1_parse_show_existing_frame_envelope(
  frame_payload : Array[Byte],
  config : Av1ShowExistingFrameConfig,
) -> Av1ShowExistingFrameEnvelope? {
  av1_parse_show_existing_frame(frame_payload, config)
}
