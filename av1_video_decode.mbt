/// Stateful AV1 video decoding, the mount point an AVIF image sequence needs.
///
/// A sequence is a list of items, each one temporal unit. Only the first item
/// has to carry the sequence header, and any item after a key frame predicts
/// from frames stored earlier, so both the parsed sequence and the reference
/// buffer must survive between items. `av1_decode` stays the stateless
/// single-image entry point and shares its reconstruction path with this one.

///|
/// A decoder that keeps presentation state across temporal units.
pub(all) struct Av1VideoDecoder {
  mut sequence : Av1SequenceInfo?
  map : Av1FrameMap
}

///|
/// Create an idle video decoder with an empty reference buffer.
pub fn av1_video_decoder() -> Av1VideoDecoder {
  { sequence: None, map: av1_frame_map(), }
}

///|
/// Decode the next temporal unit and return the image its first frame presents.
/// A unit without its own sequence header reuses the one already latched.
/// Frames that predict from a reference are still refused until motion
/// compensation is wired into the block stage, but their header still updates
/// the reference buffer bookkeeping.
pub fn av1_video_decode_frame(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Image? {
  let sequence = match av1_sequence_info(data) {
    Some(value) => value
    None =>
      match decoder.sequence {
        Some(value) => value
        None => return None
      }
  }
  decoder.sequence = Some(sequence)
  let frames = av1_obu_payloads(data, 6)
  if frames.length() == 0 {
    return None
  }
  match
    av1_decode_frame_planes(data, allow_monochrome~, map=decoder.map, sequence~) {
    Some(planes) => av1_frame_to_rgba(planes)
    None => None
  }
}
