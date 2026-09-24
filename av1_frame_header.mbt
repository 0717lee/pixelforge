/// Bounded reduced-still frame header parsing for the first AVIF pixel stage.
///
/// The parser follows the reduced-still ordering from AV1 §5.9.2 and keeps
/// the checked tile-group envelope needed by the intra reconstruction path.

///|
///|
/// `MAX_SEGMENTS`: how many segment ids a frame may assign.
pub let av1_segments : Int = 8

///|
/// `SEG_LVL_MAX`: the eight per-segment features.
pub let av1_segment_levels : Int = 8

///|
/// `SEG_LVL_REF_FRAME`: features at or above it set `SegIdPreSkip`.
pub let av1_seg_level_ref_frame : Int = 5

///|
/// `SEG_LVL_ALT_Q`: the one per-segment feature this decoder applies. It only
/// shifts the block's quantizer index, so the residual reading applies it with
/// no further plumbing. Every other level changes the loop filter, the block's
/// reference or its prediction mode, and the block stage refuses a frame that
/// enables one (see `av1_inter_frame_supported`).
pub let av1_seg_level_alt_q : Int = 0

///|
/// The parsed `segmentation_params` (AV1 §6.10.9). `enabled` without a map
/// update or an active feature changes nothing about the decode.
pub(all) struct Av1SegmentationParams {
  enabled : Bool
  update_map : Bool
  temporal_update : Bool
  update_data : Bool
  feature_enabled : Array[Array[Bool]]
  feature_data : Array[Array[Int]]
  seg_id_pre_skip : Bool
  last_active_seg_id : Int
}

///|
/// `MAX_LOOP_FILTER` as the segment feature table needs it (AV1 §6.10.9).
fn av1_segmentation_loop_filter_limit(sequence : Av1SequenceInfo) -> Int {
  ignore(sequence)
  63
}

///|
pub(all) struct Av1FrameHeaderInfo {
  /// Visible entropy-coded width, before superres horizontal upscaling.
  frame_width : Int
  upscaled_width : Int
  /// Entropy-coded height. A general header can override the sequence maximum
  /// (AV1 5.9.6), so nothing downstream may assume `sequence.height`.
  frame_height : Int
  /// Eight disables superres; active denominators are nine through sixteen.
  superres_denom : Int
  header_bytes : Int
  tile_payload : Array[Byte]
  base_q_idx : Int
  quant_matrix : Av1QuantMatrix?
  delta_lf_res : Int
  delta_lf_multi : Bool
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
  /// Tile whose adapted CDF rows become the frame-end probability context.
  context_update_tile_id : Int
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
  /// `delta_q_params` (AV1 §6.10.10): whether each superblock codes its own
  /// quantizer delta, and the log2 scale those deltas carry.
  delta_q_present : Bool
  delta_q_res : Int
  /// `delta_lf_params`: whether each superblock also codes loop-filter deltas.
  /// A frame that sets it is refused, because the per-superblock loop-filter
  /// level table is not implemented.
  delta_lf_present : Bool
  /// Parsed segmentation_params; None is impossible once parsed (an absent
  /// segmentation is the empty struct).
  segmentation : Av1SegmentationParams
  /// Frame classification (AV1 §6.8.2): 0 key, 1 inter, 2 intra-only, 3 switch.
  frame_type : Int
  frame_is_intra : Bool
  show_frame : Bool
  show_existing_frame : Bool
  /// Slot of the buffered frame a show-existing frame displays.
  frame_to_show_map_idx : Int
  error_resilient : Bool
  /// Whether the frame may serve as a reference for display-order decisions
  /// (AV1 §5.9.2). Only a hidden frame signals it.
  showable_frame : Bool
  /// §7.21: when set, the entropy-coded frame contexts are not carried over to
  /// the next tile group, so every tile starts from the frame-level snapshot.
  disable_frame_end_update_cdf : Bool
  /// 0/1 when signalled, 2 (`av1_select_integer_mv`) when the sequence fixes it.
  force_integer_mv : Int
  current_frame_id : Int
  order_hint : Int
  /// `primary_ref_frame`; `av1_primary_ref_none` selects a fresh frame context.
  primary_ref_frame : Int
  /// Eight-bit `refresh_frame_flags` mask over the reference buffer slots.
  refresh_frame_flags : Int
  /// Slot index for each of the seven named references, `LAST` first.
  ref_frame_idx : Array[Int]
  /// Per-reference-name order hints and forward/backward sign bias (§5.9.3).
  order_hints : Array[Int]
  ref_frame_sign_bias : Array[Int]
  allow_high_precision_mv : Bool
  /// 0..3 select a fixed filter set, 4 means the block signals its own.
  interpolation_filter : Int
  is_motion_mode_switchable : Bool
  use_ref_frame_mvs : Bool
  allow_warped_motion : Bool
  reference_select : Bool
  skip_mode_present : Bool
  /// The two ordered references a skip-mode block copies its motion from.
  skip_mode_frame : Array[Int]
  /// Global motion type and six-tap warp model per reference name (§5.9.24).
  gm_type : Array[Int]
  gm_params : Array[Array[Int]]
  /// Warp models inherited from the primary reference by `load_previous`.
  prev_gm_params : Array[Array[Int]]
  mut loop_filter_ref_deltas : Array[Int]
  mut loop_filter_mode_deltas : Array[Int]
  allow_intrabc : Bool
  render_width : Int
  render_height : Int
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
/// The seed precedes the INTER-only update flag. An inherited parameter set
/// names one of this frame's reference slots, and retains the new frame's seed.
/// Intra and SWITCH frames always code a complete parameter set.
fn av1_parse_film_grain_params(
  reader : Av1FrameBits,
  monochrome : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
  frame_type? : Int = av1_key_frame,
  map? : Av1FrameMap? = None,
  ref_frame_idx? : Array[Int] = [],
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
    if frame_type == av1_inter_frame {
      let update = match reader.take(1) {
        Some(value) => value == 1
        None => return None
      }
      if !update {
        let slot = match reader.take(3) {
          Some(value) => value
          None => return None
        }
        let state = match map {
          Some(value) => value
          None => return None
        }
        if !state.valid[slot] || !ref_frame_idx.contains(slot) {
          return None
        }
        let stored = state.saved_film_grain[slot].unwrap_or(
          av1_frame_grain_empty(),
        )
        let copied = av1_frame_grain_copy(stored)
        return Some({ ..copied, apply_grain: true, grain_seed, })
      }
    }
    num_y_points = match reader.take(4) {
      Some(v) => v
      None => return None
    }
    if num_y_points > 14 {
      return None
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
      if point_y_value.length() > 0 &&
        point_y_value[point_y_value.length() - 1] >= value {
        return None
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
        return None
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
        if point_cb_value.length() > 0 &&
          point_cb_value[point_cb_value.length() - 1] >= value {
          return None
        }
        point_cb_value.push(value)
        point_cb_scaling.push(scaling)
      }
      num_cr_points = match reader.take(4) {
        Some(v) => v
        None => return None
      }
      if num_cr_points > 10 {
        return None
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
        if point_cr_value.length() > 0 &&
          point_cr_value[point_cr_value.length() - 1] >= value {
          return None
        }
        point_cr_value.push(value)
        point_cr_scaling.push(scaling)
      }
    }
    if subsampling_x &&
      subsampling_y &&
      (num_cb_points == 0) != (num_cr_points == 0) {
      return None
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
/// Everything `frame_header()` establishes before `tile_info()`: the frame
/// class, the reference list, the motion-tool flags and the frame geometry.
/// A reduced still-picture header is the degenerate case where most of these
/// are derived rather than signalled (AV1 §5.9.2).
priv struct Av1FramePrefix {
  mut disable_cdf_update : Bool
  mut allow_screen_content_tools : Int
  mut force_integer_mv : Int
  mut frame_type : Int
  mut frame_is_intra : Bool
  mut show_frame : Bool
  mut show_existing_frame : Bool
  mut frame_to_show_map_idx : Int
  mut error_resilient : Bool
  mut current_frame_id : Int
  mut order_hint : Int
  mut primary_ref_frame : Int
  mut refresh_frame_flags : Int
  ref_frame_idx : Array[Int]
  order_hints : Array[Int]
  ref_frame_sign_bias : Array[Int]
  mut allow_high_precision_mv : Bool
  mut interpolation_filter : Int
  mut is_motion_mode_switchable : Bool
  mut use_ref_frame_mvs : Bool
  mut allow_intrabc : Bool
  mut upscaled_width : Int
  mut frame_width : Int
  mut frame_height : Int
  mut superres_denom : Int
  mut render_width : Int
  mut render_height : Int
  /// `frame_size_override_flag`, needed again by `frame_size_with_refs`.
  mut frame_size_override_flag : Int
  mut showable_frame : Bool
  mut disable_frame_end_update_cdf : Bool
  mut loop_filter_ref_deltas : Array[Int]
  mut loop_filter_mode_deltas : Array[Int]
  mut prev_gm_params : Array[Array[Int]]
}

///|
/// `frame_size()` plus `superres_params()` (AV1 §5.9.6, §5.9.8). The coded
/// width shrinks under active superres while `upscaled_width` keeps the
/// resolution motion vectors address.
fn av1_frame_prefix_size(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
  sequence : Av1SequenceInfo,
) -> Bool {
  let override_size = prefix.frame_size_override_flag == 1
  let (width, height) = if override_size {
    let w = match r.take(sequence.frame_width_bits_minus_1 + 1) {
      Some(v) => v + 1
      None => return false
    }
    let h = match r.take(sequence.frame_height_bits_minus_1 + 1) {
      Some(v) => v + 1
      None => return false
    }
    (w, h)
  } else {
    (sequence.width, sequence.height)
  }
  av1_frame_prefix_superres(r, prefix, sequence, width, height)
}

///|
/// A frame inherits display geometry, never the preceding frame's coded width.
/// Both explicit and reference-derived sizes read a fresh superres denominator.
/// libaom and dav1d clamp the coded width to min(16, UpscaledWidth), including
/// legal active-superres streams whose small display width stays unchanged.
fn av1_frame_prefix_superres(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
  sequence : Av1SequenceInfo,
  upscaled : Int,
  height : Int,
) -> Bool {
  let denom = if sequence.enable_superres {
    let use_superres = match r.take(1) {
      Some(v) => v == 1
      None => return false
    }
    if use_superres {
      match r.take(3) {
        Some(value) => value + 9
        None => return false
      }
    } else {
      8
    }
  } else {
    8
  }
  if upscaled <= 0 || height <= 0 || upscaled > 65536 || height > 65536 {
    return false
  }
  let minimum = if upscaled < 16 { upscaled } else { 16 }
  let rounded = (upscaled * 8 + denom / 2) / denom
  let coded = if rounded < minimum { minimum } else { rounded }
  prefix.upscaled_width = upscaled
  prefix.frame_width = coded
  prefix.frame_height = height
  prefix.superres_denom = denom
  true
}

///|
/// `render_size()` (AV1 §5.9.9). Render dimensions only affect display, so a
/// frame may carry them without any downstream stage consuming them.
fn av1_frame_prefix_render_size(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
) -> Bool {
  let different = match r.take(1) {
    Some(v) => v == 1
    None => return false
  }
  if different {
    let w = match r.take(16) {
      Some(v) => v
      None => return false
    }
    let h = match r.take(16) {
      Some(v) => v
      None => return false
    }
    prefix.render_width = w + 1
    prefix.render_height = h + 1
  } else {
    prefix.render_width = prefix.upscaled_width
    prefix.render_height = prefix.frame_height
  }
  true
}

///|
/// `inter_refs()` and `frame_size_with_refs()` (AV1 §5.9.2, §5.9.7). Fills the
/// seven named-reference slot indices and derives the per-reference order
/// hints and sign biases the block stage compares against.
fn av1_frame_prefix_inter_refs(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
  sequence : Av1SequenceInfo,
  map : Av1FrameMap,
) -> Bool {
  let mut short_signaling = false
  if sequence.enable_order_hint {
    short_signaling = match r.take(1) {
      Some(v) => v == 1
      None => return false
    }
    if short_signaling {
      let last = match r.take(3) {
        Some(v) => v
        None => return false
      }
      let gold = match r.take(3) {
        Some(v) => v
        None => return false
      }
      av1_set_frame_refs(
        sequence,
        map,
        prefix.order_hint,
        last,
        gold,
        prefix.ref_frame_idx,
      )
    }
  }
  for i in 0..<av1_refs_per_frame {
    if !short_signaling {
      let slot = match r.take(3) {
        Some(v) => v
        None => return false
      }
      prefix.ref_frame_idx[i] = slot
    }
    if sequence.frame_id_numbers_present {
      let (diff_len, id_len) = match av1_frame_id_lengths(sequence) {
        Some(value) => value
        None => return false
      }
      let delta = match r.take(diff_len) {
        Some(value) => value + 1
        None => return false
      }
      let slot = prefix.ref_frame_idx[i]
      let mask = (1 << id_len) - 1
      let expected = (prefix.current_frame_id - delta) & mask
      if !map.valid[slot] || map.frame_ids[slot] != expected {
        return false
      }
    }
  }
  // A reference-sized frame inherits the full geometry of the first slot that
  // declares itself present.
  let mut inherited = false
  if prefix.frame_size_override_flag == 1 && !prefix.error_resilient {
    for i in 0..<av1_refs_per_frame {
      let found = match r.take(1) {
        Some(v) => v == 1
        None => return false
      }
      if found {
        let slot = prefix.ref_frame_idx[i]
        if !map.valid[slot] ||
          !av1_frame_prefix_superres(
            r,
            prefix,
            sequence,
            map.upscaled_widths[slot],
            map.frame_heights[slot],
          ) {
          return false
        }
        prefix.render_width = map.render_widths[slot]
        prefix.render_height = map.render_heights[slot]
        inherited = true
        break
      }
    }
    if !inherited {
      if !av1_frame_prefix_size(r, prefix, sequence) {
        return false
      }
      if !av1_frame_prefix_render_size(r, prefix) {
        return false
      }
    }
  } else {
    if !av1_frame_prefix_size(r, prefix, sequence) {
      return false
    }
    if !av1_frame_prefix_render_size(r, prefix) {
      return false
    }
  }
  prefix.allow_high_precision_mv = if prefix.force_integer_mv != 0 {
    false
  } else {
    match r.take(1) {
      Some(v) => v == 1
      None => return false
    }
  }
  // `interpolation_filter`: a switchable frame lets each block pick, otherwise
  // the three-bit selection is fixed for the whole frame (AV1 §5.9.11).
  let switchable = match r.take(1) {
    Some(v) => v == 1
    None => return false
  }
  prefix.interpolation_filter = if switchable {
    4
  } else {
    match r.take(2) {
      Some(v) => v
      None => return false
    }
  }
  prefix.is_motion_mode_switchable = match r.take(1) {
    Some(v) => v == 1
    None => return false
  }
  prefix.use_ref_frame_mvs = if prefix.error_resilient ||
    !sequence.enable_ref_frame_mvs {
    false
  } else {
    match r.take(1) {
      Some(v) => v == 1
      None => return false
    }
  }
  for i in 0..<av1_refs_per_frame {
    let ref_frame = av1_last_frame + i
    let hint = map.order_hints[prefix.ref_frame_idx[i]]
    prefix.order_hints[ref_frame] = hint
    prefix.ref_frame_sign_bias[ref_frame] = if av1_relative_dist(
        sequence,
        hint,
        prefix.order_hint,
      ) >
      0 {
      1
    } else {
      0
    }
  }
  true
}

///|
/// Reads `frame_header()` up to (but excluding) `tile_info()`. `map` carries the
/// reference buffer state the general grammar reads and updates; a reduced
/// still-picture sequence needs none of it.
fn av1_parse_frame_prefix(
  r : Av1FrameBits,
  sequence : Av1SequenceInfo,
  map : Av1FrameMap?,
  temporal_id? : Int = 0,
  spatial_id? : Int = 0,
) -> Av1FramePrefix? {
  let prefix : Av1FramePrefix = {
    disable_cdf_update: false,
    allow_screen_content_tools: 0,
    // §5.9.2: a frame that does not signal it means "integer MV not forced".
    // The sequence-level SELECT value (2) never reaches this field.
    force_integer_mv: 0,
    frame_type: av1_key_frame,
    frame_is_intra: true,
    show_frame: true,
    show_existing_frame: false,
    frame_to_show_map_idx: 0,
    error_resilient: false,
    current_frame_id: 0,
    order_hint: 0,
    primary_ref_frame: av1_primary_ref_none,
    refresh_frame_flags: av1_all_ref_frames_mask,
    ref_frame_idx: Array::make(av1_refs_per_frame, 0),
    order_hints: Array::make(av1_total_refs_per_frame, 0),
    ref_frame_sign_bias: Array::make(av1_total_refs_per_frame, 0),
    allow_high_precision_mv: false,
    interpolation_filter: 4,
    is_motion_mode_switchable: false,
    use_ref_frame_mvs: false,
    allow_intrabc: false,
    upscaled_width: sequence.width,
    frame_width: sequence.width,
    frame_height: sequence.height,
    superres_denom: 8,
    render_width: sequence.width,
    render_height: sequence.height,
    frame_size_override_flag: 0,
    showable_frame: true,
    disable_frame_end_update_cdf: sequence.reduced_still_picture_header,
    loop_filter_ref_deltas: av1_default_loop_filter_ref_deltas(),
    loop_filter_mode_deltas: [0, 0],
    prev_gm_params: Array::make(
      av1_total_refs_per_frame,
      av1_identity_gm_params(),
    ),
  }
  let id_len = if sequence.frame_id_numbers_present {
    match av1_frame_id_lengths(sequence) {
      Some((_, value)) => value
      None => return None
    }
  } else {
    0
  }
  if !sequence.reduced_still_picture_header {
    let show_existing = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if show_existing {
      prefix.show_existing_frame = true
      prefix.frame_to_show_map_idx = match r.take(3) {
        Some(v) => v
        None => return None
      }
      if sequence.decoder_model_info_present &&
        !sequence.equal_picture_interval &&
        av1_frame_timing_value(
          r,
          sequence.frame_presentation_time_length_minus_1 + 1,
        )
        is None {
        return None
      }
      if sequence.frame_id_numbers_present {
        let display_id = match r.take(id_len) {
          Some(value) => value
          None => return None
        }
        let state = match map {
          Some(value) => value
          None => return None
        }
        let slot = prefix.frame_to_show_map_idx
        if !state.valid[slot] || state.frame_ids[slot] != display_id {
          return None
        }
        prefix.current_frame_id = display_id
      }
      // The remaining fields keep their reduced-still defaults; a
      // show-existing frame carries no new syntax, so the caller resolves it
      // against the reference buffer instead of decoding tiles.
      match map {
        Some(state) =>
          prefix.frame_type = state.frame_types[prefix.frame_to_show_map_idx]
        None => return None
      }
      prefix.show_frame = true
      return Some(prefix)
    }
    prefix.frame_type = match r.take(2) {
      Some(v) => v
      None => return None
    }
    prefix.frame_is_intra = prefix.frame_type == av1_key_frame ||
      prefix.frame_type == av1_intra_only_frame
    prefix.show_frame = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if prefix.show_frame &&
      sequence.decoder_model_info_present &&
      !sequence.equal_picture_interval &&
      av1_frame_timing_value(
        r,
        sequence.frame_presentation_time_length_minus_1 + 1,
      )
      is None {
      return None
    }
    prefix.showable_frame = if prefix.show_frame {
      // A shown frame is showable unless it is a key frame; only a hidden
      // frame says so explicitly (AV1 §5.9.2).
      prefix.frame_type != av1_key_frame
    } else {
      match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
    }
    prefix.error_resilient = if prefix.frame_type == av1_switch_frame ||
      (prefix.frame_type == av1_key_frame && prefix.show_frame) {
      true
    } else {
      match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
    }
  }
  // A showing key frame invalidates every buffered reference (AV1 §7.20).
  if prefix.frame_type == av1_key_frame && prefix.show_frame {
    match map {
      Some(state) => av1_frame_map_invalidate(state)
      None => ()
    }
  }
  prefix.disable_cdf_update = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  prefix.allow_screen_content_tools = if sequence.seq_force_screen_content_tools ==
    av1_select_screen_content_tools {
    match r.take(1) {
      Some(v) => v
      None => return None
    }
  } else {
    sequence.seq_force_screen_content_tools
  }
  if prefix.allow_screen_content_tools != 0 {
    prefix.force_integer_mv = if sequence.seq_force_integer_mv ==
      av1_select_integer_mv {
      match r.take(1) {
        Some(v) => v
        None => return None
      }
    } else {
      sequence.seq_force_integer_mv
    }
  }
  if prefix.frame_is_intra {
    prefix.force_integer_mv = 1
  }
  prefix.current_frame_id = if sequence.frame_id_numbers_present {
    match r.take(id_len) {
      Some(v) => v
      None => return None
    }
  } else {
    0
  }
  if sequence.frame_id_numbers_present {
    let state = match map {
      Some(value) => value
      None => return None
    }
    let (diff_len, _) = av1_frame_id_lengths(sequence).unwrap()
    if state.has_frame_id &&
      !(prefix.frame_type == av1_key_frame && prefix.show_frame) {
      let modulus = 1 << id_len
      let advance = (prefix.current_frame_id + modulus - state.current_frame_id) &
        (modulus - 1)
      if advance == 0 || advance >= modulus / 2 {
        return None
      }
    }
    av1_frame_mark_refs(state, prefix.current_frame_id, diff_len, id_len)
  }
  prefix.frame_size_override_flag = if prefix.frame_type == av1_switch_frame {
    1
  } else if sequence.reduced_still_picture_header {
    0
  } else {
    match r.take(1) {
      Some(v) => v
      None => return None
    }
  }
  if sequence.order_hint_bits > 0 {
    prefix.order_hint = match r.take(sequence.order_hint_bits) {
      Some(v) => v
      None => return None
    }
  }
  prefix.primary_ref_frame = if prefix.frame_is_intra || prefix.error_resilient {
    av1_primary_ref_none
  } else {
    match r.take(3) {
      Some(v) => v
      None => return None
    }
  }
  if sequence.decoder_model_info_present {
    let present = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if present {
      // Only operating points with their own decoder model and this OBU's
      // actual temporal/spatial layer code a buffer-removal timestamp.
      for op in 0..<=sequence.operating_points_cnt_minus_1 {
        let idc = sequence.operating_point_idc[op]
        let needed = sequence.decoder_model_present_for_this_op[op] &&
          (
            idc == 0 ||
            (
              ((idc >> temporal_id) & 1) == 1 &&
              ((idc >> (spatial_id + 8)) & 1) == 1
            )
          )
        if needed &&
          av1_frame_timing_value(
            r,
            sequence.buffer_removal_time_length_minus_1 + 1,
          )
          is None {
          return None
        }
      }
    }
  }
  prefix.refresh_frame_flags = if prefix.frame_type == av1_switch_frame ||
    (prefix.frame_type == av1_key_frame && prefix.show_frame) {
    av1_all_ref_frames_mask
  } else {
    match r.take(8) {
      Some(v) => v
      None => return None
    }
  }
  if !prefix.frame_is_intra ||
    prefix.refresh_frame_flags != av1_all_ref_frames_mask {
    if prefix.error_resilient && sequence.enable_order_hint {
      for _ in 0..<av1_num_ref_frames {
        if r.take(sequence.order_hint_bits) is None {
          return None
        } // ref_order_hint
      }
    }
  }
  if prefix.frame_is_intra {
    if !av1_frame_prefix_size(r, prefix, sequence) {
      return None
    }
    if !av1_frame_prefix_render_size(r, prefix) {
      return None
    }
    if prefix.allow_screen_content_tools != 0 && prefix.superres_denom == 8 {
      prefix.allow_intrabc = match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
    }
  } else {
    match map {
      Some(state) =>
        if !av1_frame_prefix_inter_refs(r, prefix, sequence, state) {
          return None
        }
      None => return None
    }
  }
  prefix.disable_frame_end_update_cdf = if sequence.reduced_still_picture_header ||
    prefix.disable_cdf_update {
    true
  } else {
    match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
  }
  // `setup_past_independence` versus `load_previous` (AV1 §7.20, §7.21). The
  // frame context a non-erasable frame inherits covers the warp models and the
  // loop-filter deltas, both of which the block stage reads per reference.
  if prefix.primary_ref_frame == av1_primary_ref_none {
    prefix.loop_filter_ref_deltas = av1_default_loop_filter_ref_deltas()
    prefix.loop_filter_mode_deltas = [0, 0]
  } else {
    match map {
      Some(state) => {
        let slot = prefix.ref_frame_idx[prefix.primary_ref_frame]
        prefix.loop_filter_ref_deltas = Array::copy(
          state.saved_loop_filter_ref_deltas[slot],
        )
        prefix.loop_filter_mode_deltas = Array::copy(
          state.saved_loop_filter_mode_deltas[slot],
        )
        prefix.prev_gm_params = Array::makei(av1_total_refs_per_frame, i => {
          Array::copy(state.saved_gm_params[slot][i])
        })
      }
      None => return None
    }
  }
  Some(prefix)
}

///|
/// Raw-bit `decode_subexp_with_ref` (AV1 §5.9.27). The global-motion
/// parameters use this non-arithmetic coder, distinct from the MSAC variant in
/// `av1_msac.mbt`.
fn av1_bits_decode_subexp(r : Av1FrameBits, num_syms : Int) -> Int? {
  let k = 3
  let mut i = 0
  let mut mk = 0
  let mut done = false
  let mut out : Int? = None
  while !done {
    let b2 = if i == 0 { k } else { k + i - 1 }
    let a = 1 << b2
    if num_syms <= mk + 3 * a {
      out = match r.ns(num_syms - mk) {
        Some(v) => Some(v + mk)
        None => None
      }
      done = true
    } else {
      match r.take(1) {
        Some(1) => {
          i = i + 1
          mk = mk + a
        }
        Some(_) => {
          out = match r.take(b2) {
            Some(v) => Some(v + mk)
            None => None
          }
          done = true
        }
        None => {
          out = None
          done = true
        }
      }
    }
  }
  out
}

///|
fn av1_bits_decode_signed_subexp_with_ref(
  r : Av1FrameBits,
  low : Int,
  high : Int,
  reference : Int,
) -> Int? {
  let mx = high - low
  let v = match av1_bits_decode_subexp(r, mx) {
    Some(value) => value
    None => return None
  }
  let shifted = reference - low
  let x = if shifted << 1 <= mx {
    av1_msac_inverse_recenter(shifted, v)
  } else {
    mx - 1 - av1_msac_inverse_recenter(mx - 1 - shifted, v)
  }
  Some(x + low)
}

///|
/// One decoded warp coefficient, re-expressed in `WARPEDMODEL_PREC_BITS`
/// precision. The diagonal entries add the identity bias back.
fn av1_frame_global_param(
  r : Av1FrameBits,
  typ : Int,
  idx : Int,
  prev : Array[Int],
  allow_high_precision_mv : Bool,
) -> Int? {
  let mut abs_bits = 12
  let mut prec_bits = 15
  if idx < 2 {
    if typ == av1_gm_translation {
      // A pure translation codes one bit less range and precision when the
      // frame does not allow quarter-pel motion vectors.
      let hp = if allow_high_precision_mv { 0 } else { 1 }
      abs_bits = 9 - hp
      prec_bits = 3 - hp
    } else {
      abs_bits = 12
      prec_bits = 6
    }
  }
  let prec_diff = av1_warped_model_prec_bits - prec_bits
  let bias = if idx % 3 == 2 { 1 << av1_warped_model_prec_bits } else { 0 }
  let sub_ = if idx % 3 == 2 { 1 << prec_bits } else { 0 }
  let mx = 1 << abs_bits
  let base = (prev[idx] >> prec_diff) - sub_
  let delta = match
    av1_bits_decode_signed_subexp_with_ref(r, -mx, mx + 1, base) {
    Some(value) => value
    None => return None
  }
  Some((delta << prec_diff) + bias)
}

///|
/// `global_motion_params()` (AV1 §5.9.24). Each reference carries a warp model
/// coded as deltas against the model `load_previous` inherited.
fn av1_frame_global_motion(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
) -> (Array[Int], Array[Array[Int]])? {
  let gm_type = Array::make(av1_total_refs_per_frame, av1_gm_identity)
  let gm_params = Array::makei(av1_total_refs_per_frame, _ => {
    av1_identity_gm_params()
  })
  if prefix.frame_is_intra {
    return Some((gm_type, gm_params))
  }
  let read_param = fn(idx : Int, name : Int) -> Int? {
    av1_frame_global_param(
      r,
      gm_type[name],
      idx,
      prefix.prev_gm_params[name],
      prefix.allow_high_precision_mv,
    )
  }
  for name = av1_last_frame; name <= av1_alt_ref_frame; name = name + 1 {
    let mut typ = av1_gm_identity
    if (match r.take(1) {
        Some(v) => v == 1
        None => return None
      }) {
      if (match r.take(1) {
          Some(v) => v == 1
          None => return None
        }) {
        typ = av1_gm_rot_zoom
      } else if (match r.take(1) {
          Some(v) => v == 1
          None => return None
        }) {
        typ = av1_gm_translation
      } else {
        typ = av1_gm_affine
      }
    }
    gm_type[name] = typ
    let indices = if typ == av1_gm_affine {
      [2, 3, 4, 5]
    } else if typ == av1_gm_rot_zoom {
      [2, 3]
    } else {
      []
    }
    for idx in indices {
      match read_param(idx, name) {
        Some(value) => gm_params[name][idx] = value
        None => return None
      }
    }
    if typ == av1_gm_rot_zoom {
      // A rot-zoom model is a scaled rotation, so the second row follows.
      gm_params[name][4] = -gm_params[name][3]
      gm_params[name][5] = gm_params[name][2]
    }
    if typ >= av1_gm_translation {
      for idx in [0, 1] {
        match read_param(idx, name) {
          Some(value) => gm_params[name][idx] = value
          None => return None
        }
      }
    }
  }
  Some((gm_type, gm_params))
}

///|
/// `skip_mode_params()` (AV1 §5.9.22). A frame may declare that every block
/// copies its motion from a fixed pair of ordered references, which removes
/// per-block motion syntax entirely.
fn av1_frame_skip_mode(
  r : Av1FrameBits,
  prefix : Av1FramePrefix,
  sequence : Av1SequenceInfo,
  reference_select : Bool,
) -> (Bool, Array[Int])? {
  let frames = [av1_last_frame, av1_last_frame]
  let mut allowed = false
  if !prefix.frame_is_intra && reference_select && sequence.enable_order_hint {
    let dist = fn(hint : Int) -> Int {
      av1_relative_dist(sequence, hint, prefix.order_hint)
    }
    let mut forward_idx = -1
    let mut forward_hint = 0
    let mut backward_idx = -1
    let mut backward_hint = 0
    for i in 0..<av1_refs_per_frame {
      let hint = prefix.order_hints[av1_last_frame + i]
      let d = dist(hint)
      if d < 0 {
        if forward_idx < 0 || dist(hint) > dist(forward_hint) {
          forward_idx = i
          forward_hint = hint
        }
      } else if d > 0 {
        if backward_idx < 0 || dist(hint) < dist(backward_hint) {
          backward_idx = i
          backward_hint = hint
        }
      }
    }
    // Pair the closest earlier/later references. With no later reference,
    // pair the closest earlier reference with the next distinct earlier one.
    let mut second_idx = -1
    let mut second_hint = 0
    if forward_idx >= 0 && backward_idx < 0 {
      for i in 0..<av1_refs_per_frame {
        let hint = prefix.order_hints[av1_last_frame + i]
        if dist(hint) < dist(forward_hint) {
          if second_idx < 0 || dist(hint) > dist(second_hint) {
            second_idx = i
            second_hint = hint
          }
        }
      }
    }
    let pair = if forward_idx < 0 {
      None
    } else if backward_idx >= 0 {
      Some((forward_idx, backward_idx))
    } else if second_idx >= 0 {
      Some((forward_idx, second_idx))
    } else {
      None
    }
    match pair {
      Some((a, b)) => {
        allowed = true
        let lo = if a < b { a } else { b }
        let hi = if a < b { b } else { a }
        frames[0] = av1_last_frame + lo
        frames[1] = av1_last_frame + hi
      }
      None => ()
    }
  }
  if !allowed {
    Some((false, frames))
  } else {
    match r.take(1) {
      Some(v) => Some((v == 1, frames))
      None => None
    }
  }
}

///|
/// Parses a frame header and returns its entropy-coded tile group. Unsupported
/// syntax is rejected before any bytes are exposed to the reconstruction
/// stage. A general (non reduced-still) sequence reads and updates the
/// reference buffer, so `map` is required for one.
pub fn av1_parse_stage1_frame(
  frame_payload : Array[Byte],
  sequence : Av1SequenceInfo,
  allow_monochrome? : Bool = false,
  allow_highbd? : Bool = false,
  map? : Av1FrameMap,
  frame_header_obu? : Bool = false,
  tile_groups? : Array[Array[Byte]] = [],
  temporal_id? : Int = 0,
  spatial_id? : Int = 0,
) -> Av1FrameHeaderInfo? {
  // Profile and bit-depth pairing from AV1 section 6.4.1: profiles 0 and 1
  // are 8/10-bit, profile 2 also allows 12-bit. Chroma subsampling is not a
  // gate: the color config already fixed it from the profile, and every
  // plane geometry below is parameterised by it.
  let profile_ok = if sequence.profile == 0 || sequence.profile == 1 {
    sequence.bit_depth == 8 || sequence.bit_depth == 10
  } else {
    sequence.profile == 2
  }
  if sequence.width <= 0 ||
    sequence.width > 65536 ||
    sequence.height <= 0 ||
    sequence.height > 65536 ||
    sequence.width > MAX_IMAGE_PIXELS / sequence.height ||
    !profile_ok ||
    (sequence.bit_depth != 8 && !allow_highbd) ||
    (sequence.monochrome && !allow_monochrome) {
    return None
  }
  if !sequence.reduced_still_picture_header && map is None {
    return None
  }
  let r : Av1FrameBits = { data: frame_payload, bit_pos: 0, }
  let prefix = match
    av1_parse_frame_prefix(r, sequence, map, temporal_id~, spatial_id~) {
    Some(value) => value
    None => return None
  }
  if prefix.show_existing_frame {
    // A buffered frame carries no tile data: the caller resolves the envelope
    // against the reference buffer instead of decoding a second time.
    return None
  }
  let disable_cdf_update = prefix.disable_cdf_update
  let allow_tools = prefix.allow_screen_content_tools != 0
  let superres_denom = prefix.superres_denom
  let upscaled_width = prefix.upscaled_width
  let frame_width = prefix.frame_width
  let frame_height = prefix.frame_height

  let mi_cols = 2 * ((frame_width + 7) / 8)
  let mi_rows = 2 * ((frame_height + 7) / 8)
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
  let mut context_update_tile_id = 0
  if tile_cols_log2 > 0 || tile_rows_log2 > 0 {
    context_update_tile_id = match r.take(tile_cols_log2 + tile_rows_log2) {
      Some(value) => value
      None => return None
    }
    if context_update_tile_id >= tile_cols * tile_rows {
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

  let quant_matrix = if using_qmatrix {
    // qm_y and qm_u are present even for monochrome; qm_v is conditional.
    let y = match r.take(4) {
      Some(v) => v
      None => return None
    }
    let u = match r.take(4) {
      Some(v) => v
      None => return None
    }
    let v = if sequence.separate_uv_delta_q {
      match r.take(4) {
        Some(v) => v
        None => return None
      }
    } else {
      u
    }
    Some(Av1QuantMatrix::{ y, u, v, })
  } else {
    None
  }

  let segmentation = match
    av1_parse_segmentation_params(
      r,
      prefix.primary_ref_frame,
      av1_segmentation_loop_filter_limit(sequence),
      inherited=av1_segmentation_primary(
        map,
        prefix.primary_ref_frame,
        prefix.ref_frame_idx,
      ),
    ) {
    Some(value) => value
    None => return None
  }
  // A frame that writes the segment map applies each feature per block. What
  // this decoder can decode is narrow and deliberate: the map must be coded in
  // the frame itself (no temporal prediction, no inherited feature data, so
  // nothing has to be carried across frames), and the only feature it may
  // enable is ALT_Q, which shifts the block's quantizer index and is applied
  // where the residual reads it. Every other level changes the loop filter,
  // the block's reference frame or its prediction mode, and a frame that maps
  // no block at all still inherits per-block features - all refused whole
  // rather than decoded with the segmentation silently dropped.
  if segmentation.enabled && !av1_segmentation_supported(segmentation) {
    return None
  }
  // `delta_q_params` (AV1 §6.10.10). The per-superblock quantizer delta is
  // implemented: the tile reads one symbol at each superblock origin and the
  // residual dequantises with that superblock's index. The per-superblock
  // loop-filter deltas are not, so a frame that signals them is refused whole
  // after their bits are consumed - the entropy stream stays in sync for the
  // next frame either way.
  let mut delta_q_present = false
  let mut delta_q_res = 0
  let mut delta_lf_present = false
  let mut delta_lf_res = 0
  let mut delta_lf_multi = false
  if base_q_idx > 0 {
    delta_q_present = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if delta_q_present {
      delta_q_res = match r.take(2) {
        Some(v) => v
        None => return None
      }
      if !prefix.allow_intrabc {
        delta_lf_present = match r.take(1) {
          Some(v) => v == 1
          None => return None
        }
      }
      if delta_lf_present {
        // Actual delta values occur in the tile entropy stream, not this header.
        delta_lf_res = match r.take(2) {
          Some(v) => v
          None => return None
        }
        delta_lf_multi = match r.take(1) {
          Some(v) => v == 1
          None => return None
        }
      }
    }
  }

  // CodedLossless is the AND of all eight LosslessArray entries. Segment
  // ALT_Q participates; superblock delta-Q does not (AV1 5.9.14).
  let coded_lossless = av1_frame_coded_lossless(
    base_q_idx, quant_deltas, segmentation,
  )
  let loop_filter = if coded_lossless || prefix.allow_intrabc {
    None
  } else {
    match
      av1_parse_loop_filter_config(
        r,
        sequence.monochrome,
        ref_deltas=prefix.loop_filter_ref_deltas,
        mode_deltas=prefix.loop_filter_mode_deltas,
      ) {
      Some(config) => Some(config)
      None => return None
    }
  }
  let cdef = if !coded_lossless && !prefix.allow_intrabc && sequence.enable_cdef {
    match av1_parse_cdef_config(r, sequence.monochrome) {
      Some(config) => Some(config)
      None => return None
    }
  } else {
    None
  }
  // Superres changes samples even when every transform is lossless. Such a
  // frame still carries restoration syntax, unlike an all-lossless frame.
  let all_lossless = coded_lossless && superres_denom == 8
  let restoration : Av1RestorationConfig? = if !all_lossless &&
    !prefix.allow_intrabc &&
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
  // reference_select (AV1 5.9.21) only exists for a frame with references, and
  // it gates skip_mode, which is the only way a whole frame can be coded
  // without per-block motion syntax.
  let reference_select = if prefix.frame_is_intra {
    false
  } else {
    match r.take(1) {
      Some(value) => value == 1
      None => return None
    }
  }
  let (skip_mode_present, skip_mode_frame) = match
    av1_frame_skip_mode(r, prefix, sequence, reference_select) {
    Some(value) => value
    None => return None
  }
  let allow_warped_motion = if prefix.frame_is_intra ||
    prefix.error_resilient ||
    !sequence.enable_warped_motion {
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
  let (gm_type, gm_params) = match av1_frame_global_motion(r, prefix) {
    Some(value) => value
    None => return None
  }
  // A hidden frame that cannot be shown has no film-grain syntax.
  let film_grain : Av1FilmGrainParams? = if sequence.film_grain_params_present &&
    (prefix.show_frame || prefix.showable_frame) {
    match
      av1_parse_film_grain_params(
        r,
        sequence.monochrome,
        sequence.subsampling_x,
        sequence.subsampling_y,
        frame_type=prefix.frame_type,
        map~,
        ref_frame_idx=prefix.ref_frame_idx,
      ) {
      Some(params) => Some(params)
      None => return None
    }
  } else {
    None
  }
  let (offset, tile_payload) = if frame_header_obu {
    if !av1_obu_trailing_bits(frame_payload, r.bit_pos) {
      return None
    }
    let payload = match
      av1_assemble_tile_groups(
        tile_groups,
        tile_cols,
        tile_rows,
        tile_cols_log2 + tile_rows_log2,
        tile_size_bytes,
      ) {
      Some(value) => value
      None => return None
    }
    tile_size_bytes = if tile_cols * tile_rows > 1 { 4 } else { 0 }
    (frame_payload.length(), payload)
  } else {
    match
      av1_frame_tile_group_payload(
        frame_payload,
        r.bit_pos,
        tile_cols,
        tile_rows,
      ) {
      Some(value) => value
      None => return None
    }
  }
  Some({
    frame_width,
    upscaled_width,
    frame_height,
    superres_denom,
    header_bytes: offset,
    tile_payload,
    base_q_idx,
    quant_matrix,
    delta_lf_res,
    delta_lf_multi,
    tile_cols,
    tile_rows,
    tile_cols_log2,
    tile_rows_log2,
    tile_col_starts_sb,
    tile_row_starts_sb,
    tile_size_bytes,
    context_update_tile_id,
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
    delta_q_present,
    delta_q_res,
    delta_lf_present,
    segmentation,
    frame_type: prefix.frame_type,
    frame_is_intra: prefix.frame_is_intra,
    show_frame: prefix.show_frame,
    show_existing_frame: prefix.show_existing_frame,
    frame_to_show_map_idx: prefix.frame_to_show_map_idx,
    error_resilient: prefix.error_resilient,
    showable_frame: prefix.showable_frame,
    disable_frame_end_update_cdf: prefix.disable_frame_end_update_cdf,
    force_integer_mv: prefix.force_integer_mv,
    current_frame_id: prefix.current_frame_id,
    order_hint: prefix.order_hint,
    primary_ref_frame: prefix.primary_ref_frame,
    refresh_frame_flags: prefix.refresh_frame_flags,
    ref_frame_idx: prefix.ref_frame_idx,
    order_hints: prefix.order_hints,
    ref_frame_sign_bias: prefix.ref_frame_sign_bias,
    allow_high_precision_mv: prefix.allow_high_precision_mv,
    interpolation_filter: prefix.interpolation_filter,
    is_motion_mode_switchable: prefix.is_motion_mode_switchable,
    use_ref_frame_mvs: prefix.use_ref_frame_mvs,
    allow_warped_motion,
    reference_select,
    skip_mode_present,
    skip_mode_frame,
    gm_type,
    gm_params,
    prev_gm_params: prefix.prev_gm_params,
    loop_filter_ref_deltas: prefix.loop_filter_ref_deltas,
    loop_filter_mode_deltas: prefix.loop_filter_mode_deltas,
    allow_intrabc: prefix.allow_intrabc,
    render_width: prefix.render_width,
    render_height: prefix.render_height,
  })
}

///|
/// `Segmentation_Feature_Bits`, `Segmentation_Feature_Signed` and
/// `Segmentation_Feature_Max` (AV1 §6.10.9): the eight segment levels.
let av1_segmentation_feature_bits : Array[Int] = [8, 6, 6, 6, 6, 3, 0, 0]

///|
let av1_segmentation_feature_signed : Array[Int] = [1, 1, 1, 1, 1, 0, 0, 0]

///|
/// `MAX_LOOP_FILTER` is 63 for eight-bit streams and 255 when the frame is
/// high bit depth (AV1 §6.10.9 note); the caller passes its own limit.
fn av1_parse_segmentation_params(
  r : Av1FrameBits,
  primary_ref_frame : Int,
  max_loop_filter : Int,
  inherited? : Av1SegmentationParams? = None,
) -> Av1SegmentationParams? {
  let enabled = match r.take(1) {
    Some(v) => v == 1
    None => return None
  }
  if !enabled {
    return Some(av1_segmentation_empty())
  }
  let mut update_map = true
  let mut temporal_update = false
  let mut update_data = true
  if primary_ref_frame != av1_primary_ref_none {
    update_map = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
    if update_map {
      temporal_update = match r.take(1) {
        Some(v) => v == 1
        None => return None
      }
    }
    update_data = match r.take(1) {
      Some(v) => v == 1
      None => return None
    }
  }
  let feature_enabled = Array::makei(av1_segments, _ => {
    Array::make(av1_segment_levels, false)
  })
  let feature_data = Array::makei(av1_segments, _ => {
    Array::make(av1_segment_levels, 0)
  })
  if update_data {
    let limit = [
      255, max_loop_filter, max_loop_filter, max_loop_filter, max_loop_filter, 7,
      0, 0,
    ]
    for i in 0..<av1_segments {
      for j in 0..<av1_segment_levels {
        let on = match r.take(1) {
          Some(v) => v == 1
          None => return None
        }
        feature_enabled[i][j] = on
        if !on {
          continue
        }
        let bits = av1_segmentation_feature_bits[j]
        if bits == 0 {
          continue
        }
        let signed = av1_segmentation_feature_signed[j] == 1
        let value = if signed {
          match Av1FrameBits::signed(r, bits + 1) {
            Some(v) => v
            None => return None
          }
        } else {
          match r.take(bits) {
            Some(v) => v
            None => return None
          }
        }
        let bottom = if signed { -limit[j] } else { 0 }
        feature_data[i][j] = if value < bottom {
          bottom
        } else if value > limit[j] {
          limit[j]
        } else {
          value
        }
      }
    }
  }
  if !update_data {
    let previous = match inherited {
      Some(value) => value
      None => av1_segmentation_empty()
    }
    for i in 0..<av1_segments {
      for j in 0..<av1_segment_levels {
        feature_enabled[i][j] = previous.feature_enabled[i][j]
        feature_data[i][j] = previous.feature_data[i][j]
      }
    }
  }
  let mut seg_id_pre_skip = false
  let mut last_active = 0
  for i in 0..<av1_segments {
    for j in 0..<av1_segment_levels {
      if feature_enabled[i][j] {
        last_active = i
        if j >= av1_seg_level_ref_frame {
          seg_id_pre_skip = true
        }
      }
    }
  }
  Some({
    enabled,
    update_map,
    temporal_update,
    update_data,
    feature_enabled,
    feature_data,
    seg_id_pre_skip,
    last_active_seg_id: last_active,
  })
}

///|
/// Validate all eight segment feature ranges. Quantization, four loop-filter
/// deltas, forced references, skip and global motion each have tile consumers.
pub fn av1_segmentation_features_supported(
  segmentation : Av1SegmentationParams,
) -> Bool {
  if segmentation.feature_enabled.length() != 8 ||
    segmentation.feature_data.length() != 8 {
    return false
  }
  for i in 0..<av1_segments {
    if segmentation.feature_enabled[i].length() != 8 ||
      segmentation.feature_data[i].length() != 8 {
      return false
    }
    for j in 0..<av1_segment_levels {
      if !segmentation.feature_enabled[i][j] {
        continue
      }
      let value = segmentation.feature_data[i][j]
      let max = if j == 0 {
        255
      } else if j < 5 {
        63
      } else if j == 5 {
        7
      } else {
        0
      }
      let min = if j < 5 { -max } else { 0 }
      if value < min || value > max {
        return false
      }
    }
  }
  true
}

///|
/// Frame parsing resolves inherited feature tables from the primary reference;
/// tile decoding resolves unchanged or temporally predicted segment maps from
/// the saved frame state. This check validates the resulting feature data.
pub fn av1_segmentation_supported(segmentation : Av1SegmentationParams) -> Bool {
  if !segmentation.enabled {
    return true
  }
  av1_segmentation_features_supported(segmentation)
}

///|
fn av1_segmentation_empty() -> Av1SegmentationParams {
  {
    enabled: false,
    update_map: false,
    temporal_update: false,
    update_data: false,
    feature_enabled: Array::makei(av1_segments, _ => {
      Array::make(av1_segment_levels, false)
    }),
    feature_data: Array::makei(av1_segments, _ => {
      Array::make(av1_segment_levels, 0)
    }),
    seg_id_pre_skip: false,
    last_active_seg_id: -1,
  }
}

///|
/// Apply SEG_LVL_ALT_Q to a supplied base index (AV1 get_qindex). Callers
/// supply the frame base for syntax, or the current SB index for dequant.
fn av1_segment_qindex(
  base_q_idx : Int,
  segmentation : Av1SegmentationParams,
  segment_id : Int,
) -> Int {
  if !segmentation.enabled ||
    segment_id < 0 ||
    segment_id >= av1_segments ||
    !segmentation.feature_enabled[segment_id][av1_seg_level_alt_q] {
    return base_q_idx
  }
  let value = base_q_idx +
    segmentation.feature_data[segment_id][av1_seg_level_alt_q]
  if value < 0 {
    0
  } else if value > 255 {
    255
  } else {
    value
  }
}

///|
fn av1_frame_coded_lossless(
  base_q_idx : Int,
  quant_deltas : Av1QuantDeltas,
  segmentation : Av1SegmentationParams,
) -> Bool {
  if !av1_quant_deltas_lossless(quant_deltas) {
    return false
  }
  for segment_id in 0..<av1_segments {
    if av1_segment_qindex(base_q_idx, segmentation, segment_id) != 0 {
      return false
    }
  }
  true
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
