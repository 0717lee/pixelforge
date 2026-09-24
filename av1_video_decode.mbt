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
/// Decode a temporal unit and return its first displayed image. All frames in
/// the unit update the reference map. Use av1_video_decode_temporal_unit to
/// receive one presentation per temporal unit, including show-existing. OP0's
/// highest spatial layer actually present is selected independently per unit.
pub fn av1_video_decode_frame(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Image? {
  match
    av1_video_decode_temporal_unit_planes(decoder, data, allow_monochrome~) {
    Some(frames) =>
      if frames.is_empty() {
        None
      } else {
        av1_frame_to_rgba(frames[0])
      }
    None => None
  }
}

///|
/// Decode temporal units in bitstream order, selecting the highest spatial
/// layer actually present in OP0 for each unit. Input may contain several
/// TD-delimited units; an ISOBMFF sample implicitly ends its single unit.
/// Some([]) denotes a valid unit containing only hidden frames or metadata;
/// None denotes malformed syntax or a missing reference.
pub fn av1_video_decode_temporal_unit(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Array[Image]? {
  let frames = match
    av1_video_decode_temporal_unit_planes(decoder, data, allow_monochrome~) {
    Some(value) => value
    None => return None
  }
  let images : Array[Image] = []
  for frame in frames {
    match av1_frame_to_rgba(frame) {
      Some(image) => images.push(image)
      None => return None
    }
  }
  Some(images)
}

///|
/// Native display samples are retained for alpha-track UNORM conversion and
/// container composition; no intermediate eight-bit RGB conversion is needed.
fn av1_video_decode_temporal_unit_planes(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Array[Av1FramePlanes]? {
  match
    av1_decode_obu_planes(data, decoder.map, decoder.sequence, allow_monochrome) {
    Some((sequence, displayed)) => {
      decoder.sequence = Some(sequence)
      Some(displayed)
    }
    None => None
  }
}
