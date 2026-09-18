/// Bounded reduced-still frame header parsing for the first AVIF pixel stage.
///
/// The parser follows the reduced-still ordering from AV1 §5.9.2 and keeps
/// the checked tile-group envelope needed by the intra reconstruction path.

///|
pub(all) struct Av1FrameHeaderInfo {
  /// Visible entropy-coded width, before superres horizontal upscaling.
  frame_width : Int
  upscaled_width : Int
  /// Eight disables superres; active denominators are nine through sixteen.
  superres_denom : Int
  header_bytes : Int
  tile_payload : Array[Byte]
  base_q_idx : Int
  tile_cols : Int
  tile_rows : Int
  tile_cols_log2 : Int
  tile_rows_log2 : Int
  /// Tile boundaries in superblock units, including the terminal boundary.
  /// These arrays preserve non-uniform `tile_info()` geometry for callers that
  /// can place independently-sized tile images. The first element is always
  /// zero and the final element is the superblock count for that axis.
  tile_col_starts_sb : Array[Int]
  tile_row_starts_sb : Array[Int]
  /// Size-prefix width for the tile group (0 for the legacy isolated tile).
  tile_size_bytes : Int
  tx_mode_select : Bool
  reduced_tx_set : Bool
  coded_lossless : Bool
  cdef : Av1CdefConfig?
  loop_filter : Av1LoopFilterConfig?
  /// Loop-restoration modes and unit sizes, or None when the frame omitted
  /// the syntax (all-lossless, disabled sequence tool or intrabc).
  restoration : Av1RestorationConfig?
  disable_cdf_update : Bool
  allow_screen_content_tools : Bool
  /// Film-grain parameters, or None when the sequence omitted the tool.
  film_grain : Av1FilmGrainParams?
  /// Per-plane quantizer deltas from quantization_params.
  quant_deltas : Av1QuantDeltas
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

///|
/// Parse cdef_params after the caller has handled its frame/sequence gates.
/// NumPlanes==1 omits both UV syntax fields from every table entry.
fn av1_parse_cdef_config(
  reader : Av1FrameBits,
  monochrome : Bool,
) -> Av1CdefConfig? {
  let damping = match reader.take(2) {
    Some(value) => value + 3
    None => return None
  }
  let bits = match reader.take(2) {
    Some(value) => value
    None => return None
  }
  let y_primary : Array[Int] = []
  let y_secondary : Array[Int] = []
  let uv_primary : Array[Int] = []
  let uv_secondary : Array[Int] = []
  for _ in 0..<(1 << bits) {
    let primary = match reader.take(4) {
      Some(value) => value
      None => return None
    }
    let secondary = match reader.take(2) {
      Some(value) => value
      None => return None
    }
    y_primary.push(primary)
    y_secondary.push(if secondary == 3 { 4 } else { secondary })
    if !monochrome {
      let primary = match reader.take(4) {
        Some(value) => value
        None => return None
      }
      let secondary = match reader.take(2) {
        Some(value) => value
        None => return None
      }
      uv_primary.push(primary)
      uv_secondary.push(if secondary == 3 { 4 } else { secondary })
    }
  }
  Some({ bits, damping, y_primary, y_secondary, uv_primary, uv_secondary, })
}

///|
/// Parse loop-restoration modes and unit sizes from the uncompressed header,
/// in the AV1 §5.9.11 position between CDEF and tx_mode. Two header bits per
/// actual plane select the mode in Y, U, V order (`00` None, `01` Switchable,
/// `10` Wiener, `11` Sgrproj); monochrome omits UV. When any plane is active
/// the luma unit size follows the superblock size with one bit (SB64) or two
/// bits (SB128 keeps its size above 64, halving only through chroma), and
/// 4:2:0 chroma may halve that size with one final bit. All planes None emits
/// no size bits and receives the implicit U256.
fn av1_parse_restoration_config(
  reader : Av1FrameBits,
  monochrome : Bool,
  use_128x128_superblock : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
) -> Av1RestorationConfig? {
  let num_planes = if monochrome { 1 } else { 3 }
  let modes : Array[Av1RestorationType] = []
  let mut all_none = true
  let mut chroma_none = true
  for plane in 0..<num_planes {
    let mode = match av1_restoration_header_mode(reader) {
      Some(value) => value
      None => return None
    }
    modes.push(mode)
    if mode is Av1RestorationNone {
      continue
    }
    all_none = false
    chroma_none = chroma_none && plane == 0
  }
  let unit_sizes : Array[Int] = []
  if all_none {
    // libaom assigns RESTORATION_UNITSIZE_MAX without signalling any bits.
    for _ in 0..<num_planes {
      unit_sizes.push(256)
    }
  } else {
    let sb_size = if use_128x128_superblock { 128 } else { 64 }
    let mut luma_unit = sb_size
    if sb_size == 64 {
      let bit = match reader.take(1) {
        Some(value) => value
        None => return None
      }
      luma_unit = luma_unit << bit
    }
    if luma_unit > 64 {
      let bit = match reader.take(1) {
        Some(value) => value
        None => return None
      }
      luma_unit = luma_unit << bit
    }
    if !monochrome {
      let s = if subsampling_x && subsampling_y { 1 } else { 0 }
      let uv_unit = if s != 0 && !chroma_none {
        let bit = match reader.take(1) {
          Some(value) => value
          None => return None
        }
        luma_unit >> (bit * s)
      } else {
        luma_unit
      }
      unit_sizes.push(luma_unit)
      unit_sizes.push(uv_unit)
      unit_sizes.push(uv_unit)
    } else {
      unit_sizes.push(luma_unit)
    }
  }
  Some({ modes, unit_sizes, })
}

///|
/// Two header bits map to the internal restoration enum. The integer is not
/// the internal code: `01` is Switchable and `10` is Wiener.
fn av1_restoration_header_mode(reader : Av1FrameBits) -> Av1RestorationType? {
  let first = match reader.take(1) {
    Some(value) => value
    None => return None
  }
  let second = match reader.take(1) {
    Some(value) => value
    None => return None
  }
  if first == 0 {
    Some(
      if second == 0 {
        Av1RestorationNone
      } else {
        Av1RestorationSwitchable
      },
    )
  } else {
    Some(if second == 0 { Av1RestorationWiener } else { Av1RestorationSgrproj })
  }
}

///|
/// ceil(log2(target / block_size)), matching AV1 tile_log2().
fn av1_tile_log2(block_size : Int, target : Int) -> Int {
  let mut out = 0
  while block_size << out < target {
    out = out + 1
  }
  out
}

///|
/// AV1 `ns(n)` descriptor from §4. The result is in [0, n); malformed or
/// truncated input returns None. `n == 1` consumes no bits as required by the
/// descriptor.
fn Av1FrameBits::ns(self : Av1FrameBits, n : Int) -> Int? {
  if n <= 0 {
    return None
  }
  let mut w = 0
  let mut power = 1
  while power < n {
    power = power << 1
    w = w + 1
  }
  // For n=1, w=0 and m=0; the descriptor has a zero-bit payload.
  if w == 0 {
    return Some(0)
  }
  let m = (1 << w) - n
  let value = match self.take(w - 1) {
    Some(v) => v
    None => return None
  }
  if value < m {
    Some(value)
  } else {
    match self.take(1) {
      Some(bit) => Some((value << 1) - m + bit)
      None => None
    }
  }
}

///|
/// Consume the tile-group header and return the byte-aligned tile data.
///
/// OBU_FRAME aligns the frame header before reading the tile-group header.
/// Its tile_start_and_end_present_flag must be zero (AV1 section 6.10.1).
fn av1_frame_tile_group_payload(
  frame_payload : Array[Byte],
  bit_pos : Int,
  tile_cols : Int,
  tile_rows : Int,
) -> (Int, Array[Byte])? {
  let reader : Av1FrameBits = { data: frame_payload, bit_pos, }
  let tile_count = tile_cols * tile_rows
  if tile_count <= 0 {
    return None
  }
  while (reader.bit_pos & 7) != 0 {
    if reader.take(1) != Some(0) {
      return None
    }
  }
  if tile_count > 1 {
    if reader.take(1) != Some(0) {
      return None
    }
  }
  while (reader.bit_pos & 7) != 0 {
    if reader.take(1) != Some(0) {
      return None
    }
  }
  let offset = reader.bit_pos / 8
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
/// Parse film_grain_params (AV1 §5.9.30) after reduced_tx_set.
///
/// Only intra frames reach this path, so `update_grain` is never coded: the
/// whole parameter set is always present. The AR coefficient counts follow the
/// go-av1 reference, which is confirmed by byte alignment on encoder output:
/// luma always carries `2 * lag * (lag + 1)` coefficients, and chroma adds the
/// single centre tap whenever `num_y_points > 0`. See _refs/film_grain_sim.py.
fn av1_parse_film_grain_params(
  reader : Av1FrameBits,
  monochrome : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
) -> Av1FilmGrainParams? {
  let apply_grain = match reader.take(1) {
    Some(v) => v == 1
    None => return None
  }
  let mut grain_seed = 0
  let mut num_y_points = 0
  let point_y_value : Array[Int] = []
  let point_y_scaling : Array[Int] = []
  let mut chroma_scaling_from_luma = false
  let mut num_cb_points = 0
  let point_cb_value : Array[Int] = []
  let point_cb_scaling : Array[Int] = []
  let mut num_cr_points = 0
  let point_cr_value : Array[Int] = []
  let point_cr_scaling : Array[Int] = []
  let mut grain_scaling_minus8 = 0
  let mut ar_coeff_lag = 0
  let ar_coeffs_y : Array[Int] = []
  let ar_coeffs_cb : Array[Int] = []
  let ar_coeffs_cr : Array[Int] = []
  let mut ar_coeff_shift_minus6 = 0
  let mut grain_scale_shift = 0
  let mut cb_mult = 0
  let mut cb_luma_mult = 0
  let mut cb_offset = 0
  let mut cr_mult = 0
  let mut cr_luma_mult = 0
  let mut cr_offset = 0
  let mut overlap_flag = false
  let mut clip_to_restricted_range = false
  if apply_grain {
    grain_seed = match reader.take(16) {
      Some(v) => v
      None => return None
    }
    num_y_points = match reader.take(4) {
      Some(v) => v
      None => return None
    }
    if num_y_points > 14 {
      num_y_points = 14
    }
    for _ in 0..<num_y_points {
      let value = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      let scaling = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      point_y_value.push(value)
      point_y_scaling.push(scaling)
    }
    if !monochrome {
      chroma_scaling_from_luma = match reader.take(1) {
        Some(v) => v == 1
        None => return None
      }
    }
    if monochrome ||
      chroma_scaling_from_luma ||
      (subsampling_x && subsampling_y && num_y_points == 0) {
      num_cb_points = 0
      num_cr_points = 0
    } else {
      num_cb_points = match reader.take(4) {
        Some(v) => v
        None => return None
      }
      if num_cb_points > 10 {
        num_cb_points = 10
      }
      for _ in 0..<num_cb_points {
        let value = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        let scaling = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        point_cb_value.push(value)
        point_cb_scaling.push(scaling)
      }
      num_cr_points = match reader.take(4) {
        Some(v) => v
        None => return None
      }
      if num_cr_points > 10 {
        num_cr_points = 10
      }
      for _ in 0..<num_cr_points {
        let value = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        let scaling = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        point_cr_value.push(value)
        point_cr_scaling.push(scaling)
      }
    }
    grain_scaling_minus8 = match reader.take(2) {
      Some(v) => v
      None => return None
    }
    ar_coeff_lag = match reader.take(2) {
      Some(v) => v
      None => return None
    }
    let num_pos_luma = 2 * ar_coeff_lag * (ar_coeff_lag + 1)
    let num_pos_chroma = if num_y_points > 0 {
      num_pos_luma + 1
    } else {
      num_pos_luma
    }
    if num_y_points > 0 {
      for _ in 0..<num_pos_luma {
        let value = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        ar_coeffs_y.push(value)
      }
    }
    if chroma_scaling_from_luma || num_cb_points > 0 {
      for _ in 0..<num_pos_chroma {
        let value = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        ar_coeffs_cb.push(value)
      }
    }
    if chroma_scaling_from_luma || num_cr_points > 0 {
      for _ in 0..<num_pos_chroma {
        let value = match reader.take(8) {
          Some(v) => v
          None => return None
        }
        ar_coeffs_cr.push(value)
      }
    }
    ar_coeff_shift_minus6 = match reader.take(2) {
      Some(v) => v
      None => return None
    }
    grain_scale_shift = match reader.take(2) {
      Some(v) => v
      None => return None
    }
    if num_cb_points > 0 {
      cb_mult = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      cb_luma_mult = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      cb_offset = match reader.take(9) {
        Some(v) => v
        None => return None
      }
    }
    if num_cr_points > 0 {
      cr_mult = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      cr_luma_mult = match reader.take(8) {
        Some(v) => v
        None => return None
      }
      cr_offset = match reader.take(9) {
        Some(v) => v
        None => return None
      }
    }
    overlap_flag = match reader.take(1) {
      Some(v) => v == 1
      None => return None
    }
    clip_to_restricted_range = match reader.take(1) {
      Some(v) => v == 1
      None => return None
    }
  }
  Some({
    apply_grain,
    grain_seed,
    num_y_points,
    point_y_value,
    point_y_scaling,
    chroma_scaling_from_luma,
    num_cb_points,
    point_cb_value,
    point_cb_scaling,
    num_cr_points,
    point_cr_value,
    point_cr_scaling,
    grain_scaling_minus8,
    ar_coeff_lag,
    ar_coeffs_y,
    ar_coeffs_cb,
    ar_coeffs_cr,
    ar_coeff_shift_minus6,
    grain_scale_shift,
    cb_mult,
    cb_luma_mult,
    cb_offset,
    cr_mult,
    cr_luma_mult,
    cr_offset,
    overlap_flag,
    clip_to_restricted_range,
  })
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
  if sequence.width <= 0 ||
    sequence.width > 65536 ||
    sequence.height <= 0 ||
    sequence.height > 65536 ||
    sequence.width > MAX_IMAGE_PIXELS / sequence.height ||
    (
      sequence.profile != 0 &&
      !(allow_highbd &&
      sequence.profile == 2 &&
      (sequence.bit_depth == 10 || sequence.bit_depth == 12))
    ) ||
    (sequence.bit_depth != 8 && !allow_highbd) ||
    (sequence.monochrome && !allow_monochrome) ||
    (
      (!sequence.subsampling_x || !sequence.subsampling_y) &&
      !sequence.monochrome
    ) ||
    !sequence.reduced_still_picture_header {
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
  let superres_denom = if sequence.enable_superres {
    let use_superres = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if use_superres {
      match r.take(3) {
        Some(value) => value + 9
        None => return None
      }
    } else {
      8
    }
  } else {
    8
  }
  let upscaled_width = sequence.width
  let frame_width = (upscaled_width * 8 + superres_denom / 2) / superres_denom
  // Active superres must increase every plane's visible width (AV1 7.16).
  // Keep the normative formula, including unconstrained level-31 dimensions.
  if superres_denom != 8 &&
    (
      frame_width >= upscaled_width ||
      (
        !sequence.monochrome &&
        (frame_width + 1) / 2 >= (upscaled_width + 1) / 2
      )
    ) {
    return None
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
  if allow_tools && frame_width == upscaled_width {
    let allow_intrabc = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if allow_intrabc {
      return None
    }
  }

  let mi_cols = 2 * ((frame_width + 7) / 8)
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

  // AV1 §5.9.15 tile_info(). The limits are expressed in superblocks and
  // match the profile-independent maxima from §3.
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
    if min_log2_tile_cols > area_log2 {
      min_log2_tile_cols
    } else {
      area_log2
    }
  }
  if min_log2_tile_cols > max_log2_tile_cols {
    return None
  }
  let mut tile_cols_log2 = 0
  let mut tile_rows_log2 = 0
  let mut tile_cols = 0
  let mut tile_rows = 0
  let tile_col_starts_sb : Array[Int] = []
  let tile_row_starts_sb : Array[Int] = []
  if uniform {
    tile_cols_log2 = min_log2_tile_cols
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
      if value > 0 {
        value
      } else {
        0
      }
    }
    if min_log2_tile_rows > max_log2_tile_rows {
      return None
    }
    tile_rows_log2 = min_log2_tile_rows
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
    let tile_width_sb = (sb_cols + (1 << tile_cols_log2) - 1) >> tile_cols_log2
    let tile_height_sb = (sb_rows + (1 << tile_rows_log2) - 1) >> tile_rows_log2
    let mut start_sb = 0
    while start_sb < sb_cols {
      tile_col_starts_sb.push(start_sb)
      start_sb = start_sb + tile_width_sb
    }
    tile_col_starts_sb.push(sb_cols)
    tile_cols = tile_col_starts_sb.length() - 1
    start_sb = 0
    while start_sb < sb_rows {
      tile_row_starts_sb.push(start_sb)
      start_sb = start_sb + tile_height_sb
    }
    tile_row_starts_sb.push(sb_rows)
    tile_rows = tile_row_starts_sb.length() - 1
  } else {
    // Non-uniform spacing codes each tile width with ns(max_width)+1. The
    // widest column bounds the legal tile-area height, as in tile_info().
    let mut widest_tile_sb = 0
    let mut start_sb = 0
    while start_sb < sb_cols {
      tile_col_starts_sb.push(start_sb)
      let remaining = sb_cols - start_sb
      let max_width = if remaining < max_tile_width_sb {
        remaining
      } else {
        max_tile_width_sb
      }
      let width = match r.ns(max_width) {
        Some(v) => v + 1
        None => return None
      }
      if width <= 0 || width > max_width {
        return None
      }
      if width > widest_tile_sb {
        widest_tile_sb = width
      }
      start_sb = start_sb + width
    }
    tile_col_starts_sb.push(sb_cols)
    tile_cols = tile_col_starts_sb.length() - 1
    tile_cols_log2 = av1_tile_log2(1, tile_cols)
    let mut max_area_sb = if min_log2_tiles > 0 {
      total_sb >> (min_log2_tiles + 1)
    } else {
      total_sb
    }
    if max_area_sb < 1 {
      max_area_sb = 1
    }
    let mut max_height_sb = max_area_sb /
      (if widest_tile_sb > 0 { widest_tile_sb } else { 1 })
    if max_height_sb < 1 {
      max_height_sb = 1
    }
    start_sb = 0
    while start_sb < sb_rows {
      tile_row_starts_sb.push(start_sb)
      let remaining = sb_rows - start_sb
      let max_height = if remaining < max_height_sb {
        remaining
      } else {
        max_height_sb
      }
      let height = match r.ns(max_height) {
        Some(v) => v + 1
        None => return None
      }
      if height <= 0 || height > max_height {
        return None
      }
      start_sb = start_sb + height
    }
    tile_row_starts_sb.push(sb_rows)
    tile_rows = tile_row_starts_sb.length() - 1
    tile_rows_log2 = av1_tile_log2(1, tile_rows)
  }
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
  // quantization_params(): the deltas feed the per-plane quantizer index, so
  // they are kept instead of rejected. `separate_uv_delta_q` codes one
  // additional flag and, when set, an independent V delta pair (AV1 5.9.14).
  let mut delta_y = 0
  let mut delta_u = 0
  let mut delta_ua = 0
  let mut delta_vd = 0
  let mut delta_va = 0
  if (match r.take(1) {
      Some(v) => v == 1
      None => return None
    }) {
    delta_y = match r.signed(7) {
      Some(v) => v
      None => return None
    }
  }
  if !sequence.monochrome {
    let mut diff_uv_delta = false
    if sequence.separate_uv_delta_q {
      diff_uv_delta = match r.take(1) {
        Some(v) => v == 1
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
    // Without separate deltas V simply reuses the U pair.
    if diff_uv_delta {
      if (match r.take(1) {
          Some(v) => v == 1
          None => return None
        }) {
        delta_vd = match r.signed(7) {
          Some(v) => v
          None => return None
        }
      }
      if (match r.take(1) {
          Some(v) => v == 1
          None => return None
        }) {
        delta_va = match r.signed(7) {
          Some(v) => v
          None => return None
        }
      }
    } else {
      delta_vd = delta_u
      delta_va = delta_ua
    }
  }
  let quant_deltas : Av1QuantDeltas = {
    y_dc: delta_y,
    u_dc: delta_u,
    u_ac: delta_ua,
    v_dc: delta_vd,
    v_ac: delta_va,
  }
  let using_qmatrix = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if using_qmatrix {
    // qm_y and qm_u are present even for monochrome; qm_v is conditional.
    if r.take(4) is None || r.take(4) is None {
      return None
    }
    if sequence.separate_uv_delta_q && r.take(4) is None {
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

  // CodedLossless also requires every quantizer delta to be zero (AV1 5.9.14),
  // which gates the loop-filter, CDEF, restoration and tx-mode syntax below.
  let coded_lossless = base_q_idx == 0 &&
    av1_quant_deltas_lossless(quant_deltas)
  let loop_filter = if coded_lossless {
    None
  } else {
    match av1_parse_loop_filter_config(r, sequence.monochrome) {
      Some(config) => Some(config)
      None => return None
    }
  }
  let cdef = if !coded_lossless && sequence.enable_cdef {
    match av1_parse_cdef_config(r, sequence.monochrome) {
      Some(config) => Some(config)
      None => return None
    }
  } else {
    None
  }
  // Superres changes samples even when every transform is lossless. Such a
  // frame still carries restoration syntax, unlike an all-lossless frame.
  let all_lossless = coded_lossless && frame_width == upscaled_width
  let restoration : Av1RestorationConfig? = if !all_lossless &&
    sequence.enable_restoration {
    match
      av1_parse_restoration_config(
        r,
        sequence.monochrome,
        sequence.use_128x128_superblock,
        sequence.subsampling_x,
        sequence.subsampling_y,
      ) {
      Some(config) => Some(config)
      None => return None
    }
  } else {
    None
  }
  let tx_mode_select = if coded_lossless {
    false
  } else {
    match r.take(1) {
      Some(value) => value == 1
      None => return None
    }
  }
  // This flag is present for lossless frames too, after the implicit TX mode.
  let reduced_tx_set = match r.take(1) {
    Some(value) => value == 1
    None => return None
  }
  // Reduced-still frames are always shown, so the grain syntax is present
  // whenever the sequence enables the tool (AV1 section 5.9.30).
  let film_grain : Av1FilmGrainParams? = if sequence.film_grain_params_present {
    match
      av1_parse_film_grain_params(
        r,
        sequence.monochrome,
        sequence.subsampling_x,
        sequence.subsampling_y,
      ) {
      Some(params) => Some(params)
      None => return None
    }
  } else {
    None
  }
  let (offset, tile_payload) = match
    av1_frame_tile_group_payload(frame_payload, r.bit_pos, tile_cols, tile_rows) {
    Some(value) => value
    None => return None
  }
  Some({
    frame_width,
    upscaled_width,
    superres_denom,
    header_bytes: offset,
    tile_payload,
    base_q_idx,
    tile_cols,
    tile_rows,
    tile_cols_log2,
    tile_rows_log2,
    tile_col_starts_sb,
    tile_row_starts_sb,
    tile_size_bytes,
    tx_mode_select,
    reduced_tx_set,
    coded_lossless,
    cdef,
    loop_filter,
    restoration,
    disable_cdf_update,
    allow_screen_content_tools: allow_tools,
    film_grain,
    quant_deltas,
  })
}

///|
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
