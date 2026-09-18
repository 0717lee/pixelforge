/// AV1 reference-frame management: the eight decoded-frame slots, the seven
/// named references that index them, and the per-slot header state that
/// `frame_size_with_refs`, `load_previous` and skip-mode derivation inherit
/// (AV1 §7.20, §7.21).
///
/// Pixels are held at native bit depth in the same `Av1FramePlanes` layout the
/// in-loop filters produce, after superres upscaling, because motion vectors
/// address the upscaled reference.

///|
/// AV1 §3, §6.4.2 and §6.10.24 symbols.
let av1_refs_per_frame : Int = 7

///|
let av1_total_refs_per_frame : Int = 8

///|
let av1_num_ref_frames : Int = 8

///|
let av1_primary_ref_none : Int = 7

///|
let av1_all_ref_frames_mask : Int = 0xff

///|
let av1_none_frame : Int = -1

///|
let av1_intra_frame : Int = 0

///|
let av1_last_frame : Int = 1

///|
let av1_last2_frame : Int = 2

///|
let av1_last3_frame : Int = 3

///|
let av1_golden_frame : Int = 4

///|
let av1_bwd_ref_frame : Int = 5

///|
let av1_alt_ref2_frame : Int = 6

///|
let av1_alt_ref_frame : Int = 7

///|
let av1_key_frame : Int = 0

///|
let av1_inter_frame : Int = 1

///|
let av1_intra_only_frame : Int = 2

///|
let av1_switch_frame : Int = 3

///|
let av1_gm_identity : Int = 0

///|
let av1_gm_translation : Int = 1

///|
let av1_gm_rot_zoom : Int = 2

///|
let av1_gm_affine : Int = 3

///|
let av1_warped_model_prec_bits : Int = 16

///|
/// The identity warp model from AV1 §7.20: the two diagonal coefficients carry
/// the `1 << WARPEDMODEL_PREC_BITS` bias every consumer subtracts.
fn av1_identity_gm_params() -> Array[Int] {
  [0, 0, 1 << av1_warped_model_prec_bits, 0, 0, 1 << av1_warped_model_prec_bits]
}

///|
/// One decoded picture in the reference buffer. Geometry is flattened out of
/// the private `Av1FramePlanes` layout so this stays a describable public type.
pub(all) struct Av1RefFrame {
  /// Native bit-depth samples in the MI-padded coding layout; the stride of
  /// plane zero is `coded_width`, chroma strides follow from `sub_x`.
  planes : Array[Array[Int]]
  coded_width : Int
  coded_height : Int
  /// Visible extent. Motion vectors address `width`/`height`, which are the
  /// post-superres dimensions (AV1 §7.18).
  width : Int
  height : Int
  sub_x : Int
  sub_y : Int
  bit_depth : Int
  /// Entropy-coded width before superres, needed by the reference-scaling and
  /// `frame_size_with_refs` derivations.
  frame_width : Int
  upscaled_width : Int
  frame_height : Int
  render_width : Int
  render_height : Int
  order_hint : Int
  frame_type : Int
  frame_id : Int
  /// Per-reference-list order hints inherited by the next frame (§5.9.3).
  order_hints : Array[Int]
  gm_params : Array[Array[Int]]
  loop_filter_ref_deltas : Array[Int]
  loop_filter_mode_deltas : Array[Int]
}

///|
/// The eight-slot reference buffer plus the derived slot metadata the frame
/// header reads before any pixels exist.
pub(all) struct Av1FrameMap {
  slots : Array[Av1RefFrame?]
  /// `ref_frame_idx` projections and presence, indexed by slot.
  valid : Array[Bool]
  order_hints : Array[Int]
  frame_types : Array[Int]
  frame_ids : Array[Int]
  upscaled_widths : Array[Int]
  frame_widths : Array[Int]
  frame_heights : Array[Int]
  render_widths : Array[Int]
  render_heights : Array[Int]
  saved_gm_params : Array[Array[Array[Int]]]
  saved_loop_filter_ref_deltas : Array[Array[Int]]
  saved_loop_filter_mode_deltas : Array[Array[Int]]
  current_frame_id : Int
}

///|
/// An empty reference buffer. Every slot starts invalid with identity motion
/// and neutral loop-filter deltas, matching `setup_past_independence`.
pub fn av1_frame_map() -> Av1FrameMap {
  {
    slots: Array::make(av1_num_ref_frames, None),
    valid: Array::make(av1_num_ref_frames, false),
    order_hints: Array::make(av1_num_ref_frames, 0),
    frame_types: Array::make(av1_num_ref_frames, av1_key_frame),
    frame_ids: Array::make(av1_num_ref_frames, 0),
    upscaled_widths: Array::make(av1_num_ref_frames, 0),
    frame_widths: Array::make(av1_num_ref_frames, 0),
    frame_heights: Array::make(av1_num_ref_frames, 0),
    render_widths: Array::make(av1_num_ref_frames, 0),
    render_heights: Array::make(av1_num_ref_frames, 0),
    saved_gm_params: Array::make(
      av1_num_ref_frames,
      Array::make(av1_total_refs_per_frame, av1_identity_gm_params()),
    ),
    saved_loop_filter_ref_deltas: Array::make(
      av1_num_ref_frames,
      av1_default_loop_filter_ref_deltas(),
    ),
    saved_loop_filter_mode_deltas: Array::make(av1_num_ref_frames, [0, 0]),
    current_frame_id: 0,
  }
}

///|
/// The §7.20 default reference loop-filter deltas, indexed by reference name.
fn av1_default_loop_filter_ref_deltas() -> Array[Int] {
  [1, 0, 0, 0, -1, 0, -1, -1]
}

///|
/// Invalidates every slot. A showing key frame must not leave stale references
/// behind (AV1 §7.20).
fn av1_frame_map_invalidate(map : Av1FrameMap) -> Unit {
  for i in 0..<av1_num_ref_frames {
    map.slots[i] = None
    map.valid[i] = false
    map.order_hints[i] = 0
    map.frame_ids[i] = 0
    map.upscaled_widths[i] = 0
    map.frame_widths[i] = 0
    map.frame_heights[i] = 0
    map.render_widths[i] = 0
    map.render_heights[i] = 0
    map.frame_types[i] = av1_key_frame
    map.saved_gm_params[i] = Array::make(
      av1_total_refs_per_frame,
      av1_identity_gm_params(),
    )
    map.saved_loop_filter_ref_deltas[i] = av1_default_loop_filter_ref_deltas()
    map.saved_loop_filter_mode_deltas[i] = [0, 0]
  }
}

///|
/// The signed circular distance between two order hints (AV1 §5.9.3). Zero is
/// returned when the sequence disables order hints, which makes every sign bias
/// forward.
pub fn av1_relative_dist(sequence : Av1SequenceInfo, a : Int, b : Int) -> Int {
  if !sequence.enable_order_hint {
    return 0
  }
  let diff = a - b
  let m = 1 << (sequence.order_hint_bits - 1)
  (diff & (m - 1)) - (diff & m)
}

///|
/// Derives the seven reference indices from `last_frame_idx` and
/// `gold_frame_idx` when `frame_refs_short_signaling` is set (AV1 §6.10.24).
/// Slots are ranked by their projected distance from the current frame,
/// backwards references first for the alternate references, then forwards for
/// the remaining golden-tier names.
fn av1_set_frame_refs(
  sequence : Av1SequenceInfo,
  map : Av1FrameMap,
  order_hint : Int,
  last_frame_idx : Int,
  gold_frame_idx : Int,
  ref_frame_idx : Array[Int],
) -> Unit {
  for i in 0..<av1_refs_per_frame {
    ref_frame_idx[i] = -1
  }
  ref_frame_idx[av1_last_frame - av1_last_frame] = last_frame_idx
  ref_frame_idx[av1_golden_frame - av1_last_frame] = gold_frame_idx
  let used = Array::make(av1_num_ref_frames, false)
  used[last_frame_idx] = true
  used[gold_frame_idx] = true
  // Project every slot onto a 0..2*h axis with the current frame at the
  // midpoint, so "earlier" and "later" become plain comparisons.
  let cur = 1 << (sequence.order_hint_bits - 1)
  let shifted : Array[Int] = Array::makei(av1_num_ref_frames, i => {
    cur + av1_relative_dist(sequence, map.order_hints[i], order_hint)
  })
  // Picks the latest (earliest) slot on the requested side of the current
  // frame, skipping slots already bound to a named reference.
  let find = fn(backward : Bool, earliest : Bool) -> Int {
    let mut picked = -1
    let mut best = 0
    for i in 0..<av1_num_ref_frames {
      let hint = shifted[i]
      if used[i] {
        continue
      }
      if backward && hint < cur {
        continue
      }
      if !backward && hint >= cur {
        continue
      }
      if picked < 0 || (earliest && hint < best) || (!earliest && hint >= best) {
        picked = i
        best = hint
      }
    }
    picked
  }
  let alt_ref = find(true, false)
  if alt_ref >= 0 {
    ref_frame_idx[av1_alt_ref_frame - av1_last_frame] = alt_ref
    used[alt_ref] = true
  }
  // The two remaining backward slots take the earliest leftovers in order.
  for name in [av1_bwd_ref_frame, av1_alt_ref2_frame] {
    let picked = find(true, true)
    if picked >= 0 {
      ref_frame_idx[name - av1_last_frame] = picked
      used[picked] = true
    }
  }
  for
    name in [
      av1_last2_frame, av1_last3_frame, av1_bwd_ref_frame, av1_alt_ref2_frame, av1_alt_ref_frame,
    ] {
    if ref_frame_idx[name - av1_last_frame] < 0 {
      let picked = find(false, false)
      if picked >= 0 {
        ref_frame_idx[name - av1_last_frame] = picked
        used[picked] = true
      }
    }
  }
  // Any name still unbound falls back to the earliest slot overall.
  let mut fallback = -1
  let mut earliest = 0
  for i in 0..<av1_num_ref_frames {
    if fallback < 0 || shifted[i] < earliest {
      fallback = i
      earliest = shifted[i]
    }
  }
  for i in 0..<av1_refs_per_frame {
    if ref_frame_idx[i] < 0 {
      ref_frame_idx[i] = fallback
    }
  }
}

///|
/// `update_reference_map` (AV1 §7.20). Every slot named by
/// `refresh_frame_flags` starts sharing this picture, its header state and the
/// parameters the next frame may inherit through `load_previous`.
///
/// All refreshed slots deliberately alias one `Av1RefFrame`: a later frame may
/// use any of them as its primary reference and must see identical state.
fn av1_frame_map_update(
  map : Av1FrameMap,
  header : Av1FrameHeaderInfo,
  frame : Av1FramePlanes,
) -> Unit {
  let ref_frame : Av1RefFrame = {
    planes: frame.planes,
    coded_width: frame.coded_width,
    coded_height: av1_partition_coded_extent(frame.height),
    width: frame.width,
    height: frame.height,
    sub_x: frame.sub_x,
    sub_y: frame.sub_y,
    bit_depth: frame.bit_depth,
    frame_width: header.frame_width,
    upscaled_width: header.upscaled_width,
    frame_height: header.frame_height,
    render_width: header.render_width,
    render_height: header.render_height,
    order_hint: header.order_hint,
    frame_type: header.frame_type,
    frame_id: map.current_frame_id,
    order_hints: Array::copy(header.order_hints),
    gm_params: header.gm_params,
    loop_filter_ref_deltas: Array::copy(header.loop_filter_ref_deltas),
    loop_filter_mode_deltas: Array::copy(header.loop_filter_mode_deltas),
  }
  for slot in 0..<av1_num_ref_frames {
    if ((header.refresh_frame_flags >> slot) & 1) == 0 {
      continue
    }
    map.slots[slot] = Some(ref_frame)
    map.valid[slot] = true
    map.order_hints[slot] = header.order_hint
    map.frame_types[slot] = header.frame_type
    map.frame_ids[slot] = map.current_frame_id
    map.upscaled_widths[slot] = header.upscaled_width
    map.frame_widths[slot] = header.frame_width
    map.frame_heights[slot] = header.frame_height
    map.render_widths[slot] = header.render_width
    map.render_heights[slot] = header.render_height
    // §7.21 saves the per-reference warp models and the loop-filter deltas so
    // a following frame can inherit them via primary_ref_frame.
    map.saved_gm_params[slot] = header.gm_params
    map.saved_loop_filter_ref_deltas[slot] = Array::copy(
      header.loop_filter_ref_deltas,
    )
    map.saved_loop_filter_mode_deltas[slot] = Array::copy(
      header.loop_filter_mode_deltas,
    )
  }
}

///|
/// Resolve a show-existing envelope against the buffer. A buffered frame
/// carries no tile data, so this is the whole reconstruction step for it.
pub fn av1_frame_map_show(map : Av1FrameMap, slot : Int) -> Av1RefFrame? {
  if slot < 0 || slot >= av1_num_ref_frames || !map.valid[slot] {
    return None
  }
  map.slots[slot]
}
