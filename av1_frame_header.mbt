/// Bounded reduced-still frame header parsing for the first AVIF pixel stage.
///
/// The parser follows the reduced-still ordering from AV1 §5.9.2 and keeps
/// the checked tile-group envelope needed by the intra reconstruction path.

///|
pub(all) struct Av1FrameHeaderInfo {
  header_bytes : Int
  tile_payload : Array[Byte]
  base_q_idx : Int
  tile_cols : Int
  tile_rows : Int
  tile_cols_log2 : Int
  tile_rows_log2 : Int
  /// Size-prefix width for the tile group (0 for the legacy isolated tile).
  tile_size_bytes : Int
  tx_mode_select : Bool
  reduced_tx_set : Bool
  coded_lossless : Bool
  disable_cdf_update : Bool
  allow_screen_content_tools : Bool
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
    out = (out << 1) |
      ((self.data[byte_pos].to_int() >> (7 - (self.bit_pos & 7))) & 1)
    self.bit_pos = self.bit_pos + 1
  }
  Some(out)
}

///|
fn Av1FrameBits::signed(self : Av1FrameBits, count : Int) -> Int? {
  let value = match self.take(count) {
    Some(v) => v
    None => return None
  }
  if (value & (1 << (count - 1))) != 0 {
    Some(value - (1 << count))
  } else {
    Some(value)
  }
}

/// ceil(log2(target / block_size)), matching AV1 tile_log2().
fn av1_tile_log2(block_size : Int, target : Int) -> Int {
  let mut out = 0
  while (block_size << out) < target {
    out = out + 1
  }
  out
}

/// Consume the tile-group header and return the byte-aligned tile data.
///
/// A reduced frame carries a complete tile group in the frame OBU.  A ranged
/// tile group is accepted only when it explicitly covers every tile; partial
/// groups need frame-level state and are kept outside this bounded API.
fn av1_frame_tile_group_payload(
  frame_payload : Array[Byte],
  bit_pos : Int,
  tile_cols : Int,
  tile_rows : Int,
  tile_cols_log2 : Int,
  tile_rows_log2 : Int,
) -> (Int, Array[Byte])? {
  let reader : Av1FrameBits = { data: frame_payload, bit_pos, }
  let tile_count = tile_cols * tile_rows
  if tile_count <= 0 {
    return None
  }
  if tile_count > 1 {
    let has_range = match reader.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if has_range {
      let range_bits = tile_cols_log2 + tile_rows_log2
      if range_bits <= 0 {
        return None
      }
      let start = match reader.take(range_bits) {
        Some(v) => v
        None => return None
      }
      let end = match reader.take(range_bits) {
        Some(v) => v
        None => return None
      }
      if start != 0 || end != tile_count - 1 || start > end {
        return None
      }
    }
  }
  let offset = (reader.bit_pos + 7) / 8
  if offset >= frame_payload.length() {
    return None
  }
  let tile_payload : Array[Byte] = []
  for i in offset..<frame_payload.length() {
    tile_payload.push(frame_payload[i])
  }
  Some((offset, tile_payload))
}

///|
/// Parses a reduced-still frame envelope and returns its entropy-coded tile
/// group. Unsupported syntax is rejected before any bytes are exposed to the
/// reconstruction stage.
pub fn av1_parse_stage1_frame(
  frame_payload : Array[Byte],
  sequence : Av1SequenceInfo,
  allow_monochrome? : Bool = false,
  allow_highbd? : Bool = false,
) -> Av1FrameHeaderInfo? {
  if (
      sequence.profile != 0 &&
      !(allow_highbd && sequence.profile == 2 &&
        (sequence.bit_depth == 10 || sequence.bit_depth == 12))
    ) ||
    (sequence.bit_depth != 8 && !allow_highbd) ||
    (sequence.monochrome && !allow_monochrome) ||
    (
      (!sequence.subsampling_x || !sequence.subsampling_y) &&
      !sequence.monochrome
    ) ||
    !sequence.reduced_still_picture_header ||
    sequence.separate_uv_delta_q ||
    sequence.film_grain_params_present {
    return None
  }
  let r : Av1FrameBits = { data: frame_payload, bit_pos: 0, }
  let disable_cdf_update = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  let allow_tools = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  // Screen-content tools are accepted when force-integer-MV and intrabc
  // remain disabled; the tile path still requires intra prediction only.
  if allow_tools && r.take(1) is None {
    return None
  } // force_integer_mv
  if sequence.enable_superres {
    let use_superres = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if use_superres {
      return None
    }
  }
  let render_different = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if render_different {
    if r.take(16) is None || r.take(16) is None {
      return None
    }
    return None
  }
  if allow_tools {
    let allow_intrabc = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if allow_intrabc {
      return None
    }
  }

  let mi_cols = 2 * ((sequence.width + 7) / 8)
  let mi_rows = 2 * ((sequence.height + 7) / 8)
  let sb_shift = if sequence.use_128x128_superblock { 5 } else { 4 }
  let sb_cols = (mi_cols + (1 << sb_shift) - 1) >> sb_shift
  let sb_rows = (mi_rows + (1 << sb_shift) - 1) >> sb_shift
  if sb_cols <= 0 || sb_rows <= 0 {
    return None
  }
  let uniform = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if !uniform {
    // Non-uniform spacing uses ns() coding and needs a bounded range reader;
    // reject it explicitly instead of guessing tile boundaries.
    return None
  }

  // AV1 §5.9.15 tile_info(). The limits are expressed in superblocks and
  // match the profile-independent maxima from §3. Tiles are uniformly spaced
  // in this reduced parser, but non-power-of-two frame dimensions still use
  // ceil(sb_count / 2^log2) for the final tile.
  let sb_size = sb_shift + 2
  let max_tile_width_sb = 4096 >> sb_size
  let max_tile_area_sb = (4096 * 2304) >> (2 * sb_size)
  let min_log2_tile_cols = av1_tile_log2(max_tile_width_sb, sb_cols)
  let bounded_cols = if sb_cols < 64 { sb_cols } else { 64 }
  let bounded_rows = if sb_rows < 64 { sb_rows } else { 64 }
  let max_log2_tile_cols = av1_tile_log2(1, bounded_cols)
  let max_log2_tile_rows = av1_tile_log2(1, bounded_rows)
  let total_sb = sb_cols * sb_rows
  let min_log2_tiles = {
    let area_log2 = av1_tile_log2(max_tile_area_sb, total_sb)
    if min_log2_tile_cols > area_log2 { min_log2_tile_cols } else { area_log2 }
  }
  if min_log2_tile_cols > max_log2_tile_cols {
    return None
  }
  let mut tile_cols_log2 = min_log2_tile_cols
  while tile_cols_log2 < max_log2_tile_cols {
    let more = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if !more {
      break
    }
    tile_cols_log2 = tile_cols_log2 + 1
  }
  let min_log2_tile_rows = {
    let value = min_log2_tiles - tile_cols_log2
    if value > 0 { value } else { 0 }
  }
  if min_log2_tile_rows > max_log2_tile_rows {
    return None
  }
  let mut tile_rows_log2 = min_log2_tile_rows
  while tile_rows_log2 < max_log2_tile_rows {
    let more = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if !more {
      break
    }
    tile_rows_log2 = tile_rows_log2 + 1
  }
  let tile_width_sb =
    (sb_cols + (1 << tile_cols_log2) - 1) >> tile_cols_log2
  let tile_height_sb =
    (sb_rows + (1 << tile_rows_log2) - 1) >> tile_rows_log2
  let tile_cols = (sb_cols + tile_width_sb - 1) / tile_width_sb
  let tile_rows = (sb_rows + tile_height_sb - 1) / tile_height_sb
  if tile_cols <= 0 || tile_rows <= 0 || tile_cols > 64 || tile_rows > 64 {
    return None
  }
  let mut tile_size_bytes = 0
  if tile_cols_log2 > 0 || tile_rows_log2 > 0 {
    if r.take(tile_cols_log2 + tile_rows_log2) is None {
      return None
    }
    tile_size_bytes = match r.take(2) {
      Some(v) => v + 1
      None => return None
    }
  }

  let base_q_idx = match r.take(8) {
    Some(v) => v
    None => return None
  }
  let mut delta_y = 0
  let mut delta_u = 0
  let mut delta_ua = 0
  if (match r.take(1) {
      Some(v) => v == 1
      None => return None
    }) {
    delta_y = match r.signed(7) {
      Some(v) => v
      None => return None
    }
  }
  if (match r.take(1) {
      Some(v) => v == 1
      None => return None
    }) {
    delta_u = match r.signed(7) {
      Some(v) => v
      None => return None
    }
  }
  if (match r.take(1) {
      Some(v) => v == 1
      None => return None
    }) {
    delta_ua = match r.signed(7) {
      Some(v) => v
      None => return None
    }
  }
  if delta_y != 0 || delta_u != 0 || delta_ua != 0 {
    return None
  }
  let using_qmatrix = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if using_qmatrix {
    if r.take(4) is None || r.take(4) is None || r.take(4) is None {
      return None
    }
    return None
  }

  let segmentation_enabled = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if segmentation_enabled {
    return None
  }
  if base_q_idx > 0 {
    let delta_q_present = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if delta_q_present {
      if r.take(2) is None {
        return None
      }
      let delta_lf_present = match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
      if delta_lf_present && (r.take(2) is None || r.take(1) is None) {
        return None
      }
      return None
    }
  }

  let coded_lossless = base_q_idx == 0
  if !coded_lossless {
    let lf0 = match r.take(6) {
      Some(v) => v
      None => return None
    }
    let lf1 = match r.take(6) {
      Some(v) => v
      None => return None
    }
    if lf0 != 0 || lf1 != 0 {
      return None
    }
    if r.take(3) is None {
      return None
    }
    let delta_enabled = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if delta_enabled {
      let delta_update = match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
      if delta_update {
        return None
      }
    }
    if sequence.enable_cdef {
      if r.take(2) is None {
        return None
      }
      let cdef_bits = match r.take(2) {
        Some(v) => v
        None => return None
      }
      if cdef_bits != 0 {
        return None
      } // requires per-block cdef_idx literals
      for _ in 0..<(1 << cdef_bits) {
        let yp = match r.take(4) {
          Some(v) => v
          None => return None
        }
        let ys = match r.take(2) {
          Some(v) => v
          None => return None
        }
        let up = match r.take(4) {
          Some(v) => v
          None => return None
        }
        let us = match r.take(2) {
          Some(v) => v
          None => return None
        }
        if yp != 0 || ys != 0 || up != 0 || us != 0 {
          return None
        }
      }
    }
    if sequence.enable_restoration {
      for _ in 0..<3 {
        let lr_type = match r.take(2) {
          Some(v) => v
          None => return None
        }
        if lr_type != 0 {
          return None
        }
      }
    }
    let tx_mode_select = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    // reduced_tx_set follows tx_mode for intra still frames (AV1 §5.9.24).
    let reduced_tx_set = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    let (offset, tile_payload) = match av1_frame_tile_group_payload(
      frame_payload,
      r.bit_pos,
      tile_cols,
      tile_rows,
      tile_cols_log2,
      tile_rows_log2,
    ) {
      Some(value) => value
      None => return None
    }
    Some({
      header_bytes: offset,
      tile_payload,
      base_q_idx,
      tile_cols,
      tile_rows,
      tile_cols_log2,
      tile_rows_log2,
      tile_size_bytes,
      tx_mode_select,
      reduced_tx_set,
      coded_lossless,
      disable_cdf_update,
      allow_screen_content_tools: allow_tools,
    })
  } else {
    if r.take(1) is None {
      return None
    }
    let (offset, tile_payload) = match av1_frame_tile_group_payload(
      frame_payload,
      r.bit_pos,
      tile_cols,
      tile_rows,
      tile_cols_log2,
      tile_rows_log2,
    ) {
      Some(value) => value
      None => return None
    }
    Some({
      header_bytes: offset,
      tile_payload,
      base_q_idx,
      tile_cols,
      tile_rows,
      tile_cols_log2,
      tile_rows_log2,
      tile_size_bytes,
      tx_mode_select: false,
      reduced_tx_set: false,
      coded_lossless,
      disable_cdf_update,
      allow_screen_content_tools: allow_tools,
    })
  }
}

/// Return validated tile payload slices for a parsed frame header. The frame
/// parser has already consumed the optional tile-group range header; this
/// boundary applies the checked size-prefix handling to the remaining bytes.
pub fn av1_frame_tile_payloads(
  frame : Av1FrameHeaderInfo,
) -> Array[Av1TilePayload]? {
  av1_extract_tile_payloads(
    frame.tile_payload,
    frame.tile_cols,
    frame.tile_rows,
    frame.tile_size_bytes,
  )
}
