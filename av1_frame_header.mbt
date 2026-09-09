/// Bounded reduced-still frame header parsing for the first AVIF pixel stage.
///
/// The parser accepts one intra frame with one uniformly spaced tile and
/// rejects inter prediction, segmentation, restoration and other syntax that
/// the stage-one tile reader does not yet reconstruct.

///|
pub(all) struct Av1FrameHeaderInfo {
  header_bytes : Int
  tile_payload : Array[Byte]
  base_q_idx : Int
  tile_cols : Int
  tile_rows : Int
}

///|
priv struct Av1FrameBits {
  data : Array[Byte]
  mut bit_pos : Int
}

///|
fn Av1FrameBits::take(self : Av1FrameBits, count : Int) -> Int? {
  if count < 0 || count > 31 || self.bit_pos + count > self.data.length() * 8 {
    return None
  }
  let mut out = 0
  for _ in 0..<count {
    let byte_pos = self.bit_pos >> 3
    out = (out << 1) | ((self.data[byte_pos].to_int() >> (7 - (self.bit_pos & 7))) & 1)
    self.bit_pos = self.bit_pos + 1
  }
  Some(out)
}

///|
fn Av1FrameBits::signed(self : Av1FrameBits, count : Int) -> Int? {
  let value = match self.take(count) { Some(v) => v; None => return None }
  if (value & (1 << (count - 1))) != 0 { Some(value - (1 << count)) } else { Some(value) }
}

/// Parses the supported reduced-still frame envelope and returns its tile bytes.
pub fn av1_parse_stage1_frame(
  frame_payload : Array[Byte],
  sequence : Av1SequenceInfo,
) -> Av1FrameHeaderInfo? {
  if sequence.profile != 0 || sequence.bit_depth != 8 || sequence.monochrome ||
    !sequence.subsampling_x || !sequence.subsampling_y || sequence.use_128x128_superblock {
    return None
  }
  let r : Av1FrameBits = { data: frame_payload, bit_pos: 0 }
  // reduced_still_picture_header implies KEY_FRAME + show_frame.
  if r.take(1) is None { return None } // disable_cdf_update
  let allow_tools = match r.take(1) { Some(v) => v == 1; None => return None }
  if allow_tools && r.take(1) is None { return None } // force_integer_mv
  if r.take(1) is None { return None } // render_and_frame_size_different
  // With screen-content tools selected, an intra frame signals allow_intrabc
  // after the render-size syntax when the upscaled and frame widths match.
  if allow_tools && r.take(1) is None { return None }
  // 64x64 and smaller stage-one images have one superblock row/column.
  let mi_cols = 2 * ((sequence.width + 7) / 8)
  let mi_rows = 2 * ((sequence.height + 7) / 8)
  let sb_cols = (mi_cols + 15) / 16
  let sb_rows = (mi_rows + 15) / 16
  let uniform = match r.take(1) { Some(v) => v == 1; None => return None }
  if !uniform || sb_cols > 1 || sb_rows > 1 { return None }
  let base_q_idx = match r.take(8) { Some(v) => v; None => return None }
  let mut delta_y = 0
  let mut delta_u = 0
  let mut delta_ua = 0
  if (match r.take(1) { Some(v) => v == 1; None => return None }) {
    delta_y = match r.signed(7) { Some(v) => v; None => return None }
  }
  if (match r.take(1) { Some(v) => v == 1; None => return None }) {
    delta_u = match r.signed(7) { Some(v) => v; None => return None }
  }
  if (match r.take(1) { Some(v) => v == 1; None => return None }) {
    delta_ua = match r.signed(7) { Some(v) => v; None => return None }
  }
  if (match r.take(1) { Some(v) => v == 1; None => return None }) {
    if r.take(8) is None || r.take(4) is None || r.take(4) is None { return None }
  }
  if base_q_idx > 0 {
    let delta_q_present = match r.take(1) { Some(v) => v == 1; None => return None }
    if delta_q_present {
      if r.take(2) is None { return None } // delta_q_res
      let delta_lf_present = match r.take(1) { Some(v) => v == 1; None => return None }
      if delta_lf_present {
        if r.take(2) is None || r.take(1) is None { return None }
      }
    }
  }
  let coded_lossless = base_q_idx == 0 && delta_y == 0 && delta_u == 0 && delta_ua == 0
  let segmentation_enabled = match r.take(1) { Some(v) => v == 1; None => return None }
  if segmentation_enabled { return None }
  if !coded_lossless {
    let lf0 = match r.take(6) { Some(v) => v; None => return None }
    let lf1 = match r.take(6) { Some(v) => v; None => return None }
    if lf0 != 0 || lf1 != 0 { return None }
    if sequence.enable_cdef {
      if r.take(2) is None { return None }
      let cdef_bits = match r.take(2) { Some(v) => v; None => return None }
      for _ in 0..<(1 << cdef_bits) {
        if r.take(4) is None || r.take(2) is None || r.take(4) is None || r.take(2) is None { return None }
      }
    }
    if sequence.enable_restoration {
      for _ in 0..<3 {
        let lr = match r.take(2) { Some(v) => v; None => return None }
        if lr != 0 { return None }
      }
    }
    if r.take(1) is None { return None } // tx_mode_select
  }
  if r.take(1) is None { return None } // reduced_tx_set
  let offset = (r.bit_pos + 7) / 8
  if offset < 0 || offset > frame_payload.length() { return None }
  let tile_payload : Array[Byte] = []
  for i in offset..<frame_payload.length() { tile_payload.push(frame_payload[i]) }
  Some({ header_bytes: offset, tile_payload, base_q_idx, tile_cols: 1, tile_rows: 1 })
}
