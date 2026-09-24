///|
/// Bounded AVIF grid and animation metadata extraction.
///
/// This module only parses ISO BMFF structure and returns item/sample extents.
/// It never invokes a browser codec or an external decoder.  Pixel reconstruction
/// remains in the AV1 pipeline; callers can feed the returned extents to it.
pub struct AvifGridTile {
  item_id : Int
  extents : Array[AvifGridExtent]
}

///|
pub struct AvifGridExtent {
  offset : Int
  length : Int
  construction_method : Int
}

///|
pub struct AvifGridDescriptor {
  item_id : Int
  rows : Int
  columns : Int
  output_width : Int
  output_height : Int
  tiles : Array[AvifGridTile]
}

///|
pub struct AvifAnimationFrame {
  index : Int
  offset : Int
  length : Int
  timestamp : Int
  duration : Int
  timescale : Int
}

///|
pub struct AvifAnimationDescriptor {
  timescale : Int
  frames : Array[AvifAnimationFrame]
}

///|
/// A successfully decoded animation sample with its track timing.
pub struct AvifAnimationPixelFrame {
  index : Int
  timestamp : Int
  duration : Int
  timescale : Int
  image : Image
}

///|
/// Decoded animation samples. Samples are supplied in the order returned by
/// `avif_animation_descriptor`; each sample is passed to the pure AV1 decoder.
pub struct AvifAnimationPixels {
  timescale : Int
  frames : Array[AvifAnimationPixelFrame]
}

///|
/// Decode an ordered set of AV1 animation samples using the native decoder.
/// A malformed or unsupported sample rejects the whole sequence so callers do
/// not accidentally present a partial animation.
pub fn avif_decode_animation_frames(
  descriptor : AvifAnimationDescriptor,
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  if descriptor.timescale <= 0 ||
    descriptor.frames.length() == 0 ||
    descriptor.frames.length() != samples.length() {
    return None
  }
  let frames : Array[AvifAnimationPixelFrame] = []
  // One stateful decoder for the whole sequence: later items may omit the
  // sequence header, and every item may predict from an earlier frame.
  let video = av1_video_decoder()
  let mut expected_timestamp = 0
  for i in 0..<samples.length() {
    let timing = descriptor.frames[i]
    // AVIF image sequences are presented in decode order. Reject malformed
    // timing tables instead of silently attaching pixels to the wrong frame.
    if timing.index != i ||
      timing.timescale != descriptor.timescale ||
      timing.timestamp != expected_timestamp ||
      timing.duration <= 0 {
      return None
    }
    let displayed = match
      av1_video_decode_temporal_unit(video, samples[i], allow_monochrome=true) {
      Some(value) => value
      None => return None
    }
    // A BMFF sample is one temporal unit with one presentation time. Decode
    // every hidden/reference frame, but require one presented image for it.
    if displayed.length() != 1 {
      return None
    }
    let image = displayed[0]
    frames.push({
      index: timing.index,
      timestamp: timing.timestamp,
      duration: timing.duration,
      timescale: timing.timescale,
      image,
    })
    // Guard the cumulative presentation timestamp against signed overflow.
    // A wrapped value would make subsequent monotonicity checks meaningless
    // and could select an incorrect frame during playback.
    let next_timestamp = expected_timestamp + timing.duration
    if next_timestamp < expected_timestamp {
      return None
    }
    expected_timestamp = next_timestamp
  }
  Some({ timescale: descriptor.timescale, frames, })
}

///|
/// Convenience entrypoint for callers that already extracted sample timing
/// tables. The arrays must match the sample order and length.
pub fn avif_decode_animation_samples(
  timescale : Int,
  timestamps : Array[Int],
  durations : Array[Int],
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  if timescale <= 0 ||
    timestamps.length() != samples.length() ||
    durations.length() != samples.length() ||
    samples.length() == 0 {
    return None
  }
  let frames : Array[AvifAnimationFrame] = []
  for i in 0..<samples.length() {
    frames.push({
      index: i,
      offset: 0,
      length: samples[i].length(),
      timestamp: timestamps[i],
      duration: durations[i],
      timescale,
    })
  }
  avif_decode_animation_frames({ timescale, frames, }, samples)
}

///|
/// Extract sample payloads from the selected primary animation track.
pub fn avif_animation_sample_payloads(
  data : Array[Byte],
) -> (AvifAnimationDescriptor, Array[Array[Byte]])? {
  let descriptor = match avif_animation_descriptor(data) {
    Some(value) => value
    None => return None
  }
  let samples : Array[Array[Byte]] = []
  for frame in descriptor.frames {
    if frame.offset < 0 ||
      frame.length < 0 ||
      frame.offset > data.length() - frame.length {
      return None
    }
    let sample : Array[Byte] = []
    for i in frame.offset..<(frame.offset + frame.length) {
      sample.push(data[i])
    }
    samples.push(sample)
  }
  Some((descriptor, samples))
}

///|
/// Parse and decode all animation samples from a self-contained BMFF buffer.
pub fn avif_decode_animation(data : Array[Byte]) -> AvifAnimationPixels? {
  let (color, alpha) = match ga_animation_tracks(data) {
    Some(value) => value
    None => return None
  }
  let color_planes = match ga_animation_decode_track(data, color) {
    Some(value) => value
    None => return None
  }
  let alpha_planes = match alpha {
    None => []
    Some(track) => {
      if track.descriptor.frames.length() != color.descriptor.frames.length() {
        return None
      }
      // Compare media times exactly, including tracks using different scales.
      for i in 0..<track.descriptor.frames.length() {
        let a = track.descriptor.frames[i]
        let c = color.descriptor.frames[i]
        if a.timestamp.to_int64() * c.timescale.to_int64() !=
          c.timestamp.to_int64() * a.timescale.to_int64() ||
          a.duration.to_int64() * c.timescale.to_int64() !=
          c.duration.to_int64() * a.timescale.to_int64() {
          return None
        }
      }
      match ga_animation_decode_track(data, track) {
        Some(value) => value
        None => return None
      }
    }
  }
  let frames : Array[AvifAnimationPixelFrame] = []
  for i in 0..<color_planes.length() {
    let native = color_planes[i]
    let colored = av1_frame_apply_nclx(
      native,
      color.nclx_primaries,
      color.nclx_transfer,
      color.nclx_matrix,
      color.nclx_full_range,
    )
    let converted = match alpha {
      None => av1_frame_to_rgba(colored)
      Some(track) =>
        av1_frame_with_alpha(
          colored,
          alpha_planes[i],
          color.premultiplied_by.contains(track.id),
        )
    }
    let image = match converted {
      Some(value) => value
      None => return None
    }
    let timing = color.descriptor.frames[i]
    frames.push({
      index: i,
      timestamp: timing.timestamp,
      duration: timing.duration,
      timescale: timing.timescale,
      image,
    })
  }
  Some({ timescale: color.descriptor.timescale, frames, })
}

///|
/// Decode an AVIF sequence and select the image visible at `timestamp` in
/// track timescale units.  The full sequence is validated before selection;
/// malformed timing or pixel samples therefore cannot produce a partial frame.
pub fn avif_decode_animation_frame(
  data : Array[Byte],
  timestamp : Int,
) -> Image? {
  let animation = match avif_decode_animation(data) {
    Some(value) => value
    None => return None
  }
  avif_animation_frame_at(animation, timestamp)
}

///|
/// Select the frame visible at a media timestamp. Playback loops at the
/// track duration; negative timestamps are rejected.
pub fn avif_animation_frame_at(
  animation : AvifAnimationPixels,
  timestamp : Int,
) -> Image? {
  if timestamp < 0 || animation.timescale <= 0 || animation.frames.length() == 0 {
    return None
  }
  let mut total = 0
  for frame in animation.frames {
    if frame.duration <= 0 {
      return None
    }
    let next_total = total + frame.duration
    if next_total < total {
      return None
    }
    total = next_total
  }
  if total <= 0 {
    return None
  }
  let t = timestamp % total
  for frame in animation.frames {
    if t < frame.timestamp + frame.duration {
      return Some(frame.image)
    }
  }
  Some(animation.frames[animation.frames.length() - 1].image)
}

/// Timing metadata must describe the same ordered sequence as the samples.
/// Accepting an out-of-order table would render valid pixels at the wrong
/// presentation time, which is especially hard to diagnose in a player.
/// This regression stays beside the private record fields so it can construct
/// an intentionally malformed descriptor without widening the public API.

///|
test "animation decoder rejects noncontiguous timing tables" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00',
    b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46',
    b'\x02', b'\x28',
  ]
  let descriptor : AvifAnimationDescriptor = {
    timescale: 1000,
    frames: [
      {
        index: 0,
        offset: 0,
        length: sample.length(),
        timestamp: 0,
        duration: 10,
        timescale: 1000,
      },
      {
        index: 1,
        offset: 0,
        length: sample.length(),
        timestamp: 20,
        duration: 10,
        timescale: 1000,
      },
    ],
  }
  assert_true(
    avif_decode_animation_frames(descriptor, [sample, sample]) is None,
  )
}

///|
/// Unknown iloc construction methods must fail closed.  In particular, method
/// 2 must not be interpreted as a file-relative extent (method 0).
test "iloc rejects unsupported construction method" {
  let data : Array[Byte] = [
    b'\x01', b'\x00', b'\x00', b'\x00', // version 1 + flags
     b'\x44', b'\x00', // 4-byte offset/length, no base
     b'\x00', b'\x01', // one item
     b'\x00', b'\x01', // item id
     b'\x00', b'\x02', // construction method 2
     b'\x00', b'\x00', // data reference index
     b'\x00', b'\x00', // zero extents
  ]
  let box : GaBox = {
    typ: ga_iloc,
    start: 0,
    payload: 0,
    end: data.length(),
    parent: -1,
  }
  let items : Array[GaItem] = [
    { id: 1, typ: ga_grid, method_id: 0, base: 0, offs: [], lens: [], },
  ]
  let rejected = try {
    ga_parse_iloc(data, box, items)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "iloc resolves idat construction method extents" {
  let data : Array[Byte] = [
    b'\x01', b'\x00', b'\x00', b'\x00', b'\x44', b'\x00', b'\x00', b'\x01', b'\x00',
    b'\x01', b'\x00', b'\x01', // construction method 1
     b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x05', b'\x00',
    b'\x00', b'\x00', b'\x03',
  ]
  let box : GaBox = {
    typ: ga_iloc,
    start: 0,
    payload: 0,
    end: data.length(),
    parent: -1,
  }
  let items : Array[GaItem] = [
    { id: 1, typ: ga_grid, method_id: 0, base: 0, offs: [], lens: [], },
  ]
  ga_parse_iloc(data, box, items)
  assert_eq(items[0].method_id, 1)
  assert_eq(items[0].offs[0], 5)
  assert_eq(items[0].lens[0], 3)
}

///|
priv suberror GridAnimError {
  Invalid
  Unsupported
}

///|
priv struct GaBox {
  typ : Int
  start : Int
  payload : Int
  end : Int
  parent : Int
}

///|
priv struct GaItem {
  id : Int
  typ : Int
  mut method_id : Int
  mut base : Int
  offs : Array[Int]
  lens : Array[Int]
}

///|
priv struct GaAnimationTrack {
  id : Int
  enabled : Bool
  descriptor : AvifAnimationDescriptor
  config_obus : Array[Byte]
  config_depth : Int
  config_monochrome : Bool
  config_width : Int
  config_height : Int
  nclx_primaries : Int?
  nclx_transfer : Int?
  nclx_matrix : Int?
  nclx_full_range : Bool?
  aux_for : Array[Int]
  premultiplied_by : Array[Int]
  is_alpha : Bool
}

///|
fn ga_cstring_matches(
  data : Array[Byte],
  from : Int,
  end : Int,
  value : String,
) -> Bool raise GridAnimError {
  let chars = value.to_array()
  let mut matches = true
  for p in from..<end {
    let byte = ga_u8(data, p, end)
    if byte == 0 {
      return matches && p - from == chars.length()
    }
    if p - from >= chars.length() || byte != chars[p - from].to_int() {
      matches = false
    }
  }
  raise GridAnimError::Invalid
}

///|
fn ga_animation_track(
  data : Array[Byte],
  bs : Array[GaBox],
  trak : GaBox,
  legacy : Bool,
) -> GaAnimationTrack? raise GridAnimError {
  let ti = ga_idx(bs, trak.start)
  let mut id = 1
  let mut enabled = true
  match ga_find(bs, ti, 0x746B6864) { // tkhd
    Some(header) => {
      let version = ga_u8(data, header.payload, header.end)
      if version > 1 {
        raise GridAnimError::Unsupported
      }
      id = ga_u32(
        data,
        header.payload + (if version == 0 { 12 } else { 20 }),
        header.end,
      )
      enabled = (ga_u8(data, header.payload + 3, header.end) & 1) != 0
      if id <= 0 {
        raise GridAnimError::Invalid
      }
    }
    None => if !legacy { raise GridAnimError::Invalid }
  }
  let mdia = match ga_find(bs, ti, ga_mdia) {
    Some(value) => value
    None => raise GridAnimError::Invalid
  }
  let di = ga_idx(bs, mdia.start)
  match ga_find(bs, di, 0x68646C72) { // hdlr
    Some(handler) => {
      let kind = ga_u32(data, handler.payload + 8, handler.end)
      if kind == 0x61757876 { // auxv is never a primary picture.
        enabled = false
      } else if kind != 0x70696374 {
        return None
      }
    }
    None => if !legacy { raise GridAnimError::Invalid }
  }
  let minf = match ga_find(bs, di, ga_minf) {
    Some(value) => value
    None => raise GridAnimError::Invalid
  }
  let stbl = match ga_find(bs, ga_idx(bs, minf.start), ga_stbl) {
    Some(value) => value
    None => raise GridAnimError::Invalid
  }
  let mut config_depth = 0
  let mut config_monochrome = false
  let mut config_width = 0
  let mut config_height = 0
  let mut nclx_primaries : Int? = None
  let mut nclx_transfer : Int? = None
  let mut nclx_matrix : Int? = None
  let mut nclx_full_range : Bool? = None
  let config_obus : Array[Byte] = []
  let mut is_alpha = false
  match ga_find(bs, ga_idx(bs, stbl.start), 0x73747364) { // stsd
    None => if !legacy { raise GridAnimError::Invalid }
    Some(stsd) => {
      if ga_u32(data, stsd.payload, stsd.end) != 0 ||
        ga_u32(data, stsd.payload + 4, stsd.end) != 1 {
        raise GridAnimError::Unsupported
      }
      let entries : Array[GaBox] = []
      ga_walk(data, stsd.payload + 8, stsd.end, -1, entries)
      if entries.length() != 1 || entries[0].typ != 0x61763031 {
        return None
      }
      let entry = entries[0]
      if entry.end - entry.payload < 78 {
        raise GridAnimError::Invalid
      }
      config_width = ga_u16(data, entry.payload + 24, entry.end)
      config_height = ga_u16(data, entry.payload + 26, entry.end)
      if config_width <= 0 || config_height <= 0 {
        raise GridAnimError::Invalid
      }
      let properties : Array[GaBox] = []
      ga_walk(data, entry.payload + 78, entry.end, -1, properties)
      for property in properties {
        if property.typ == 0x636F6C72 &&
          ga_u32(data, property.payload, property.end) == 0x6E636C78 {
          if nclx_primaries is Some(_) {
            raise GridAnimError::Invalid
          }
          nclx_primaries = Some(
            ga_u16(data, property.payload + 4, property.end),
          )
          nclx_transfer = Some(ga_u16(data, property.payload + 6, property.end))
          nclx_matrix = Some(ga_u16(data, property.payload + 8, property.end))
          nclx_full_range = Some(
            (ga_u8(data, property.payload + 10, property.end) & 0x80) != 0,
          )
        }
      }
      let config = match ga_find(properties, -1, 0x61763143) { // av1C
        Some(value) => value
        None => raise GridAnimError::Invalid
      }
      if config.end - config.payload < 4 ||
        ga_u8(data, config.payload, config.end) != 0x81 {
        raise GridAnimError::Invalid
      }
      let flags = ga_u8(data, config.payload + 2, config.end)
      config_depth = if (flags & 0x40) == 0 {
        8
      } else if (flags & 0x20) == 0 {
        10
      } else {
        12
      }
      config_monochrome = (flags & 0x10) != 0
      for p in (config.payload + 4)..<config.end {
        config_obus.push(data[p])
      }
      match ga_find(properties, -1, 0x61757869) { // AuxiliaryTypeInfoBox, auxi
        None => ()
        Some(auxi) => {
          if ga_u32(data, auxi.payload, auxi.end) != 0 {
            raise GridAnimError::Unsupported
          }
          is_alpha = ga_cstring_matches(
            data,
            auxi.payload + 4,
            auxi.end,
            "urn:mpeg:mpegB:cicp:systems:auxiliary:alpha",
          )
        }
      }
    }
  }
  let aux_for : Array[Int] = []
  let premultiplied_by : Array[Int] = []
  match ga_find(bs, ti, 0x74726566) { // tref
    None => ()
    Some(references) => {
      match ga_find(bs, ga_idx(bs, references.start), 0x6175786C) { // auxl
        None => ()
        Some(auxl) => {
          if auxl.end == auxl.payload || (auxl.end - auxl.payload) % 4 != 0 {
            raise GridAnimError::Invalid
          }
          for p = auxl.payload; p < auxl.end; p = p + 4 {
            let master = ga_u32(data, p, auxl.end)
            if master <= 0 || master == id {
              raise GridAnimError::Invalid
            }
            aux_for.push(master)
          }
        }
      }
      match ga_find(bs, ga_idx(bs, references.start), 0x7072656D) { // prem
        None => ()
        Some(prem) => {
          if prem.end == prem.payload || (prem.end - prem.payload) % 4 != 0 {
            raise GridAnimError::Invalid
          }
          for p = prem.payload; p < prem.end; p = p + 4 {
            let auxiliary = ga_u32(data, p, prem.end)
            premultiplied_by.push(auxiliary)
          }
        }
      }
    }
  }
  let descriptor = match ga_animation_track_descriptor(data, bs, trak) {
    Some(value) => value
    None => raise GridAnimError::Invalid
  }
  Some({
    id,
    enabled,
    descriptor,
    config_obus,
    config_depth,
    config_monochrome,
    config_width,
    config_height,
    nclx_primaries,
    nclx_transfer,
    nclx_matrix,
    nclx_full_range,
    aux_for,
    premultiplied_by,
    is_alpha,
  })
}

///|
/// Select by track identity and auxl association, never by physical trak order.
/// If several enabled primary picture tracks exist, the lowest track ID wins.
fn ga_animation_tracks(
  data : Array[Byte],
) -> (GaAnimationTrack, GaAnimationTrack?)? {
  try {
    let bs : Array[GaBox] = []
    ga_walk(data, 0, data.length(), -1, bs)
    let moov = match ga_find(bs, -1, ga_moov) {
      Some(value) => value
      None => return None
    }
    let mi = ga_idx(bs, moov.start)
    let tracks = bs.filter(box => box.parent == mi && box.typ == ga_trak)
    let parsed : Array[GaAnimationTrack] = []
    for track in tracks {
      match ga_animation_track(data, bs, track, tracks.length() == 1) {
        None => ()
        Some(value) => {
          if parsed.any(previous => previous.id == value.id) {
            return None
          }
          parsed.push(value)
        }
      }
    }
    let mut color : GaAnimationTrack? = None
    for track in parsed {
      if track.enabled && track.aux_for.length() == 0 && !track.is_alpha {
        match color {
          None => color = Some(track)
          Some(previous) => if track.id < previous.id { color = Some(track) }
        }
      }
    }
    let color = match color {
      Some(value) => value
      None => return None
    }
    let mut alpha : GaAnimationTrack? = None
    for track in parsed {
      if track.is_alpha && track.aux_for.contains(color.id) {
        if alpha is Some(_) ||
          !track.config_monochrome ||
          track.config_depth != color.config_depth {
          return None
        }
        alpha = Some(track)
      }
    }
    Some((color, alpha))
  } catch {
    _ => None
  }
}

///|
/// Metadata for the selected primary AV1 picture track.
pub fn avif_animation_descriptor(
  data : Array[Byte],
) -> AvifAnimationDescriptor? {
  match ga_animation_tracks(data) {
    Some((color, _)) => Some(color.descriptor)
    None => None
  }
}

///|
fn ga_animation_decode_track(
  data : Array[Byte],
  track : GaAnimationTrack,
) -> Array[Av1FramePlanes]? {
  let decoder = av1_video_decoder()
  let frames : Array[Av1FramePlanes] = []
  let mut expected_timestamp = 0
  let mut sequence_payload : Array[Byte]? = None
  for i in 0..<track.descriptor.frames.length() {
    let timing = track.descriptor.frames[i]
    if timing.index != i ||
      timing.timescale != track.descriptor.timescale ||
      timing.timestamp != expected_timestamp ||
      timing.duration <= 0 {
      return None
    }
    let sample = if i == 0 { track.config_obus.copy() } else { [] }
    for p in timing.offset..<(timing.offset + timing.length) {
      sample.push(data[p])
    }
    for payload in av1_obu_payloads(sample, 1) {
      match sequence_payload {
        None => sequence_payload = Some(payload)
        Some(previous) => if previous != payload { return None }
      }
    }
    let displayed = match
      av1_video_decode_temporal_unit_planes(
        decoder,
        sample,
        allow_monochrome=true,
      ) {
      Some(value) => value
      None => return None
    }
    if displayed.length() != 1 {
      return None
    }
    let frame = displayed[0]
    if track.config_width != 0 {
      let sequence = match decoder.sequence {
        Some(value) => value
        None => return None
      }
      if sequence.width != track.config_width ||
        sequence.height != track.config_height {
        return None
      }
    }
    if track.config_depth != 0 &&
      (
        frame.bit_depth != track.config_depth ||
        (frame.planes.length() == 1) != track.config_monochrome
      ) {
      return None
    }
    frames.push(frame)
    let next = expected_timestamp + timing.duration
    if next < expected_timestamp {
      return None
    }
    expected_timestamp = next
  }
  Some(frames)
}

///|
let ga_meta = 0x6D657461

///|
let ga_iinf = 0x69696E66

///|
let ga_infe = 0x696E6665

///|
let ga_iloc = 0x696C6F63

///|
let ga_idat = 0x69646174

///|
let ga_iref = 0x69726566

///|
let ga_dimg = 0x64696D67

///|
let ga_grid = 0x67726964

///|
let ga_pitm = 0x7069746D

///|
let ga_moov = 0x6D6F6F76

///|
let ga_trak = 0x7472616B

///|
let ga_mdia = 0x6D646961

///|
let ga_minf = 0x6D696E66

///|
let ga_stbl = 0x7374626C

///|
let ga_mdhd = 0x6D646864

///|
let ga_stts = 0x73747473

///|
let ga_stsz = 0x7374737A

///|
let ga_stsc = 0x73747363

///|
let ga_stco = 0x7374636F

///|
let ga_co64 = 0x636F3634

///|
fn ga_u8(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  if p < 0 || p >= e || p >= d.length() {
    raise GridAnimError::Invalid
  }
  d[p].to_int()
}

///|
fn ga_u16(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  ga_u8(d, p, e) * 256 + ga_u8(d, p + 1, e)
}

///|
fn ga_u32(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  ga_u8(d, p, e) * 16777216 +
  ga_u8(d, p + 1, e) * 65536 +
  ga_u8(d, p + 2, e) * 256 +
  ga_u8(d, p + 3, e)
}

///|
fn ga_u64(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  for i in 0..<4 {
    if ga_u8(d, p + i, e) != 0 {
      raise GridAnimError::Unsupported
    }
  }
  if ga_u8(d, p + 4, e) > 127 {
    raise GridAnimError::Unsupported
  }
  ga_u32(d, p + 4, e)
}

///|
fn ga_idx(bs : Array[GaBox], start : Int) -> Int {
  for i in 0..<bs.length() {
    if bs[i].start == start {
      return i
    }
  }
  -1
}

///|
fn ga_find(bs : Array[GaBox], parent : Int, typ : Int) -> GaBox? {
  for b in bs {
    if b.parent == parent && b.typ == typ {
      return Some(b)
    }
  }
  None
}

///|
fn ga_walk(
  d : Array[Byte],
  from : Int,
  to : Int,
  parent : Int,
  out : Array[GaBox],
) -> Unit raise GridAnimError {
  let mut p = from
  while p < to {
    if to - p < 8 {
      raise GridAnimError::Invalid
    }
    let s = ga_u32(d, p, to)
    let typ = ga_u32(d, p + 4, to)
    let mut h = 8
    let mut size = s
    if s == 1 {
      h = 16
      size = ga_u64(d, p + 8, to)
    } else if s == 0 {
      size = to - p
    }
    if size < h || size > to - p {
      raise GridAnimError::Invalid
    }
    let end = p + size
    let payload = p + h
    let bi = out.length()
    out.push({ typ, start: p, payload, end, parent, })
    // FullBox containers carry a four-byte version/flags prefix.
    if typ == ga_meta {
      if end - payload < 4 {
        raise GridAnimError::Invalid
      }
      ga_walk(d, payload + 4, end, bi, out)
    } else if typ == ga_iinf {
      let v = ga_u8(d, payload, end)
      let q = if v == 0 { payload + 6 } else { payload + 8 }
      if q > end {
        raise GridAnimError::Invalid
      }
      ga_walk(d, q, end, bi, out)
    } else if typ == ga_moov ||
      typ == ga_trak ||
      typ == ga_mdia ||
      typ == ga_minf ||
      typ == ga_stbl ||
      typ == 0x74726566 {
      ga_walk(d, payload, end, bi, out)
    }
    p = end
  }
}

///|
fn ga_items(
  d : Array[Byte],
  bs : Array[GaBox],
  meta : GaBox,
) -> Array[GaItem] raise GridAnimError {
  let mi = ga_idx(bs, meta.start)
  let ii = match ga_find(bs, mi, ga_iinf) {
    Some(x) => x
    None => raise GridAnimError::Invalid
  }
  let xi = ga_idx(bs, ii.start)
  let out : Array[GaItem] = []
  for b in bs {
    if b.parent == xi && b.typ == ga_infe {
      let v = ga_u8(d, b.payload, b.end)
      if v != 2 && v != 3 {
        raise GridAnimError::Unsupported
      }
      let id = if v >= 3 {
        ga_u32(d, b.payload + 4, b.end)
      } else {
        ga_u16(d, b.payload + 4, b.end)
      }
      let tp = b.payload + (if v >= 3 { 10 } else { 8 })
      out.push({
        id,
        typ: ga_u32(d, tp, b.end),
        method_id: 0,
        base: 0,
        offs: [],
        lens: [],
      })
    }
  }
  out
}

///|
fn ga_item_idx(xs : Array[GaItem], id : Int) -> Int {
  for i in 0..<xs.length() {
    if xs[i].id == id {
      return i
    }
  }
  -1
}

///|
fn ga_parse_iloc(
  d : Array[Byte],
  b : GaBox,
  xs : Array[GaItem],
) -> Unit raise GridAnimError {
  let p = b.payload
  let v = ga_u8(d, p, b.end)
  if v > 2 {
    raise GridAnimError::Unsupported
  }
  let a = ga_u8(d, p + 4, b.end)
  let os = a >> 4
  let ls = a & 15
  let z = ga_u8(d, p + 5, b.end)
  let bs = z >> 4
  let isz = if v >= 1 { z & 15 } else { 0 }
  if (os != 0 && os != 4 && os != 8) ||
    (ls != 0 && ls != 4 && ls != 8) ||
    (bs != 0 && bs != 4 && bs != 8) {
    raise GridAnimError::Unsupported
  }
  let mut q = p + 6
  let n = if v < 2 { ga_u16(d, q, b.end) } else { ga_u32(d, q, b.end) }
  q = q + (if v < 2 { 2 } else { 4 })
  for _ in 0..<n {
    let id = if v < 2 { ga_u16(d, q, b.end) } else { ga_u32(d, q, b.end) }
    q = q + (if v < 2 { 2 } else { 4 })
    let method_id = if v >= 1 { ga_u16(d, q, b.end) & 15 } else { 0 }
    // ISO BMFF iloc defines construction_method 0 (file) and 1 (idat).
    // Treat all other values as unsupported instead of accidentally treating
    // them as method 0 and reading bytes from the wrong base.
    if method_id != 0 && method_id != 1 {
      raise GridAnimError::Unsupported
    }
    if v >= 1 {
      q = q + 2
    }
    if ga_u16(d, q, b.end) != 0 {
      raise GridAnimError::Unsupported
    }
    q = q + 2
    let base = if bs == 0 {
      0
    } else if bs == 4 {
      ga_u32(d, q, b.end)
    } else {
      ga_u64(d, q, b.end)
    }
    q = q + bs
    let ec = ga_u16(d, q, b.end)
    q = q + 2
    let xi = ga_item_idx(xs, id)
    for _ in 0..<ec {
      if v >= 1 && isz != 0 {
        q = q + isz
      }
      let off = if os == 0 {
        0
      } else if os == 4 {
        ga_u32(d, q, b.end)
      } else {
        ga_u64(d, q, b.end)
      }
      q = q + os
      let len = if ls == 0 {
        0
      } else if ls == 4 {
        ga_u32(d, q, b.end)
      } else {
        ga_u64(d, q, b.end)
      }
      q = q + ls
      if xi >= 0 {
        xs[xi].method_id = method_id
        xs[xi].base = base
        xs[xi].offs.push(off)
        xs[xi].lens.push(len)
      }
    }
  }
}

///|
/// Extract bounded samples from one already-selected track.
fn ga_animation_track_descriptor(
  data : Array[Byte],
  bs : Array[GaBox],
  trak : GaBox,
) -> AvifAnimationDescriptor? {
  try {
    let ti = ga_idx(bs, trak.start)
    let mdia = match ga_find(bs, ti, ga_mdia) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let di = ga_idx(bs, mdia.start)
    let mdhd = match ga_find(bs, di, ga_mdhd) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let ver = ga_u8(data, mdhd.payload, mdhd.end)
    if ver > 1 {
      raise GridAnimError::Unsupported
    }
    let tspos = mdhd.payload + (if ver == 0 { 12 } else { 20 })
    let scale = ga_u32(data, tspos, mdhd.end)
    if scale <= 0 {
      raise GridAnimError::Invalid
    }
    let minf = match ga_find(bs, di, ga_minf) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let ni = ga_idx(bs, minf.start)
    let stbl = match ga_find(bs, ni, ga_stbl) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let si = ga_idx(bs, stbl.start)
    let stsz = match ga_find(bs, si, ga_stsz) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let szp = stsz.payload + 4
    let sample_size = ga_u32(data, szp, stsz.end)
    let count = ga_u32(data, szp + 4, stsz.end)
    if count <= 0 || count > 4096 {
      raise GridAnimError::Unsupported
    }
    let sizes : Array[Int] = []
    if sample_size != 0 {
      for _ in 0..<count {
        sizes.push(sample_size)
      }
    } else {
      for i in 0..<count {
        sizes.push(ga_u32(data, szp + 8 + i * 4, stsz.end))
      }
    }
    let co = match ga_find(bs, si, ga_stco) {
      Some(x) => x
      None =>
        match ga_find(bs, si, ga_co64) {
          Some(x) => x
          None => raise GridAnimError::Invalid
        }
    }
    let cp = co.payload + 4
    let nc = ga_u32(data, cp, co.end)
    // A chunk may contain more than one sample.  The common one-sample-per-
    // chunk layout has `nc == count`; for the compact layout emitted by a
    // number of AVIF writers a single chunk carries the complete sequence.
    // We can resolve that case from the sample sizes without requiring the
    // optional stsc table.  Reject other ambiguous mappings instead of
    // attaching pixels to guessed offsets.
    let stsc = ga_find(bs, si, ga_stsc)
    if nc <= 0 || (stsc is None && nc != count && nc != 1) {
      raise GridAnimError::Unsupported
    }
    // Resolve the standard sample-to-chunk table when present.  A single
    // chunk may contain several samples, and conversely a writer may group
    // multiple samples per chunk; relying on contiguous offsets alone is
    // incorrect for either layout.
    let sample_offsets : Array[Int] = []
    match stsc {
      None =>
        if nc == count {
          for i in 0..<count {
            let op = cp + 4 + i * (if co.typ == ga_stco { 4 } else { 8 })
            sample_offsets.push(
              if co.typ == ga_stco {
                ga_u32(data, op, co.end)
              } else {
                ga_u64(data, op, co.end)
              },
            )
          }
        } else {
          let base = if co.typ == ga_stco {
            ga_u32(data, cp + 4, co.end)
          } else {
            ga_u64(data, cp + 4, co.end)
          }
          let mut delta = 0
          for i in 0..<count {
            sample_offsets.push(base + delta)
            delta = delta + sizes[i]
          }
        }
      Some(table) => {
        let ep = table.payload + 4
        let entries = ga_u32(data, ep, table.end)
        if entries <= 0 || entries > 4096 || table.end - ep < 4 + entries * 12 {
          raise GridAnimError::Invalid
        }
        let first_chunks : Array[Int] = []
        let per_chunk : Array[Int] = []
        for j in 0..<entries {
          let p = ep + 4 + j * 12
          let first_chunk = ga_u32(data, p, table.end)
          let samples_per_chunk = ga_u32(data, p + 4, table.end)
          let description = ga_u32(data, p + 8, table.end)
          if first_chunk <= 0 ||
            samples_per_chunk <= 0 ||
            description != 1 ||
            (j > 0 && first_chunk <= first_chunks[j - 1]) {
            raise GridAnimError::Invalid
          }
          first_chunks.push(first_chunk)
          per_chunk.push(samples_per_chunk)
        }
        let mut sample_index = 0
        for chunk in 1..<(nc + 1) {
          let mut entry = -1
          for j in 0..<entries {
            if first_chunks[j] <= chunk {
              entry = j
            }
          }
          if entry < 0 {
            raise GridAnimError::Invalid
          }
          let chunk_offset = if co.typ == ga_stco {
            ga_u32(data, cp + 4 + (chunk - 1) * 4, co.end)
          } else {
            ga_u64(data, cp + 4 + (chunk - 1) * 8, co.end)
          }
          let mut offset = chunk_offset
          for _ in 0..<per_chunk[entry] {
            if sample_index >= count {
              raise GridAnimError::Invalid
            }
            sample_offsets.push(offset)
            offset = offset + sizes[sample_index]
            sample_index = sample_index + 1
          }
        }
        if sample_index != count {
          raise GridAnimError::Invalid
        }
      }
    }
    let stts = match ga_find(bs, si, ga_stts) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let tp = stts.payload + 4
    let ne = ga_u32(data, tp, stts.end)
    if ne <= 0 || ne > 4096 {
      raise GridAnimError::Unsupported
    }
    let durations : Array[Int] = []
    for i in 0..<ne {
      let c = ga_u32(data, tp + 4 + i * 8, stts.end)
      let dt = ga_u32(data, tp + 8 + i * 8, stts.end)
      if c <= 0 || c > count - durations.length() || dt <= 0 {
        raise GridAnimError::Invalid
      }
      for _ in 0..<c {
        durations.push(dt)
      }
    }
    if durations.length() != count {
      raise GridAnimError::Invalid
    }
    let frames : Array[AvifAnimationFrame] = []
    let mut t = 0
    for i in 0..<count {
      let o = sample_offsets[i]
      let l = sizes[i]
      if o < 0 || l < 0 || o > data.length() - l {
        raise GridAnimError::Invalid
      }
      frames.push({
        index: i,
        offset: o,
        length: l,
        timestamp: t,
        duration: durations[i],
        timescale: scale,
      })
      let next_t = t + durations[i]
      if next_t < t {
        raise GridAnimError::Invalid
      }
      t = next_t
    }
    Some({ timescale: scale, frames, })
  } catch {
    _ => None
  }
}
