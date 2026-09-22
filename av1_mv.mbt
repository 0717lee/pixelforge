/// Inter-block motion-vector candidate derivation (AV1 §7.10.2).
///
/// The candidate stack is a pure function of the blocks already decoded around
/// the current one and reads no bitstream syntax. Its output decides both the
/// entropy contexts used by the inter mode tree and the predictor a NEWMV
/// residual is added to, so the scan order, the weights and the weight-based
/// sort are all normative.

///|
/// Inter block modes, continuing the intra numbering of AV1 §6.10.24. The
/// values are the indices into the mode CDFs, so they are bitstream-visible.
let av1_mode_nearest_mv : Int = 13

///|
let av1_mode_near_mv : Int = 14

///|
let av1_mode_global_mv : Int = 15

///|
let av1_mode_new_mv : Int = 16

///|
let av1_mode_nearest_nearest_mv : Int = 17

///|
let av1_mode_near_near_mv : Int = 18

///|
let av1_mode_nearest_new_mv : Int = 19

///|
let av1_mode_new_nearest_mv : Int = 20

///|
let av1_mode_near_new_mv : Int = 21

///|
let av1_mode_new_near_mv : Int = 22

///|
let av1_mode_global_global_mv : Int = 23

///|
let av1_mode_new_new_mv : Int = 24

///|
/// `MAX_REF_MV_STACK_SIZE`.
let av1_ref_mv_stack_size : Int = 8

///|
/// `REF_CAT_LEVEL`: the weight that marks a candidate found next to the block.
let av1_ref_cat_level : Int = 640

///|
/// `MV_BORDER`, in eighth-pel, added to the block's own extent when clamping.
let av1_mv_border : Int = 128

///|
/// Per-4x4 motion state of one frame. Every tile shares it: the candidate scans
/// read neighbours decoded earlier in raster order, including the row above.
pub(all) struct Av1MotionField {
  cols : Int
  rows : Int
  /// 4x4 extents of the block covering each unit, so a scan steps over a whole
  /// neighbour block rather than re-reading the same vector.
  width4 : Array[Int]
  height4 : Array[Int]
  y_modes : Array[Int]
  is_inter : Array[Bool]
  written : Array[Bool]
  /// Skip and skip-mode flags, which the transform-size contexts read back.
  skips : Array[Int]
  skip_modes : Array[Int]
  /// Luma transform extents and the two subpel filter choices, so a later block
  /// can measure this one's neighbours.
  tx_width : Array[Int]
  tx_height : Array[Int]
  /// Luma transform types, which a chroma transform of an inter block inherits.
  tx_types : Array[Int]
  interp_v : Array[Int]
  interp_h : Array[Int]
  /// Two reference names and two motion vectors per unit, interleaved by unit.
  refs : Array[Int]
  mv_rows : Array[Int]
  mv_cols : Array[Int]
  /// The compound symbols each block read (`compound_idx` / `comp_group_idx`),
  /// which the next compound block's contexts add up.
  compound_idxs : Array[Int]
  comp_group_idxs : Array[Int]
}

///|
/// An empty motion field. Intra blocks leave `is_inter` false, which is what the
/// candidate scans test before considering a neighbour at all.
pub fn av1_motion_field(cols : Int, rows : Int) -> Av1MotionField {
  let size = cols * rows
  {
    cols,
    rows,
    width4: Array::make(size, 1),
    height4: Array::make(size, 1),
    y_modes: Array::make(size, av1_intra_frame),
    is_inter: Array::make(size, false),
    written: Array::make(size, false),
    skips: Array::make(size, 0),
    skip_modes: Array::make(size, 0),
    tx_width: Array::make(size, 4),
    tx_height: Array::make(size, 4),
    tx_types: Array::make(size, 0),
    interp_v: Array::make(size, av1_interp_eighttap),
    interp_h: Array::make(size, av1_interp_eighttap),
    refs: Array::make(size * 2, av1_intra_frame),
    mv_rows: Array::make(size * 2, 0),
    mv_cols: Array::make(size * 2, 0),
    compound_idxs: Array::make(size, 0),
    comp_group_idxs: Array::make(size, 0),
  }
}

///|
fn av1_field_unit(field : Av1MotionField, row : Int, col : Int) -> Int {
  row * field.cols + col
}

///|
/// Record one decoded block over its 4x4 footprint. The specification writes
/// this before transform sizing and before prediction, so a block's own entries
/// are already visible when motion compensation reads them back.
pub fn av1_motion_field_store(
  field : Av1MotionField,
  row : Int,
  col : Int,
  width4 : Int,
  height4 : Int,
  y_mode : Int,
  refs : Array[Int],
  mv_rows : Array[Int],
  mv_cols : Array[Int],
  skip? : Int = 0,
  skip_mode? : Int = 0,
  interp? : Array[Int] = [],
  compound_idx? : Int = 0,
  comp_group_idx? : Int = 0,
) -> Unit {
  for r = row; r < row + height4 && r < field.rows; r = r + 1 {
    for c = col; c < col + width4 && c < field.cols; c = c + 1 {
      let unit = av1_field_unit(field, r, c)
      field.width4[unit] = width4
      field.height4[unit] = height4
      field.y_modes[unit] = y_mode
      field.is_inter[unit] = refs[0] > av1_intra_frame
      field.written[unit] = true
      field.skips[unit] = skip
      field.skip_modes[unit] = skip_mode
      field.compound_idxs[unit] = compound_idx
      field.comp_group_idxs[unit] = comp_group_idx
      if interp.length() >= 2 {
        field.interp_v[unit] = interp[0]
        field.interp_h[unit] = interp[1]
      }
      field.refs[unit * 2] = refs[0]
      field.refs[unit * 2 + 1] = refs[1]
      field.mv_rows[unit * 2] = mv_rows[0]
      field.mv_cols[unit * 2] = mv_cols[0]
      field.mv_rows[unit * 2 + 1] = mv_rows[1]
      field.mv_cols[unit * 2 + 1] = mv_cols[1]
    }
  }
}

///|
/// Record the luma transform extents of one block over its 4x4 footprint. The
/// transform-size contexts of later blocks measure neighbours against these
/// (AV1 §8.3, get_above_tx_width and get_left_tx_height).
fn av1_motion_field_store_tx(
  field : Av1MotionField,
  row : Int,
  col : Int,
  width4 : Int,
  height4 : Int,
  tx_width : Int,
  tx_height : Int,
) -> Unit {
  for r = row; r < row + height4 && r < field.rows; r = r + 1 {
    for c = col; c < col + width4 && c < field.cols; c = c + 1 {
      let unit = av1_field_unit(field, r, c)
      field.tx_width[unit] = tx_width
      field.tx_height[unit] = tx_height
    }
  }
}

///|
/// get_above_tx_width( row, col ) (AV1 §9.3.4): the transform width of the unit
/// above one position. `block_row` is the top MI row of the coding block being
/// sized, and a skipped inter block sitting on that edge reports its own block
/// width, because it coded no residual to subdivide. An unavailable edge reports
/// the largest possible width.
fn av1_above_tx_width(
  field : Av1MotionField,
  block_row : Int,
  row : Int,
  col : Int,
  avail_u : Bool,
) -> Int {
  if row <= 0 || col < 0 || col >= field.cols {
    return 64
  }
  let unit = (row - 1) * field.cols + col
  if row == block_row {
    if !avail_u {
      return 64
    }
    if field.skips[unit] != 0 && field.is_inter[unit] {
      return field.width4[unit] * 4
    }
  }
  field.tx_width[unit]
}

///|
/// get_left_tx_height( row, col ), the vertical twin of the above (AV1 §9.3.4).
fn av1_left_tx_height(
  field : Av1MotionField,
  block_col : Int,
  row : Int,
  col : Int,
  avail_l : Bool,
) -> Int {
  if row < 0 || row >= field.rows || col <= 0 {
    return 64
  }
  let unit = row * field.cols + (col - 1)
  if col == block_col {
    if !avail_l {
      return 64
    }
    if field.skips[unit] != 0 && field.is_inter[unit] {
      return field.height4[unit] * 4
    }
  }
  field.tx_height[unit]
}

///|
/// The frame-level state the candidate derivation reads. Naming it explicitly
/// keeps the derivation independent of the rest of the frame frame.
pub(all) struct Av1MvFrame {
  allow_high_precision_mv : Bool
  /// Temporal motion-vector projection is a separate stage; a frame that asks
  /// for it is refused rather than derived from an incomplete candidate list.
  use_ref_frame_mvs : Bool
  force_integer_mv : Int
  /// `is_motion_mode_switchable` gates the per-block `use_obmc` / `motion_mode`
  /// symbol of AV1 §5.11.27.
  is_motion_mode_switchable : Bool
  /// `allow_warped_motion` picks the three-symbol `motion_mode` branch over the
  /// binary `use_obmc` one.
  allow_warped_motion : Bool
  gm_type : Array[Int]
  gm_params : Array[Array[Int]]
  ref_frame_sign_bias : Array[Int]
  /// Coded frame dimensions, which `is_scaled` compares against each stored
  /// reference (AV1 §5.11.26: a reference is scaled when its visible extent
  /// differs from the current frame's).
  frame_width : Int
  frame_height : Int
  /// The 8x8 temporal grid this frame needs, or `None` when the frame does not
  /// set `use_ref_frame_mvs`.
  temporal : Av1MotionFieldGrid?
}

///|
/// Project a parsed frame header onto what motion derivation needs. A frame
/// that sets `use_ref_frame_mvs` also carries the 8x8 grid its temporal scan
/// reads; `av1_inter_frame_of` supplies it.
pub fn av1_mv_frame_of(
  hf : Av1FrameHeaderInfo,
  temporal? : Av1MotionFieldGrid? = None,
) -> Av1MvFrame {
  {
    allow_high_precision_mv: hf.allow_high_precision_mv,
    use_ref_frame_mvs: hf.use_ref_frame_mvs,
    force_integer_mv: hf.force_integer_mv,
    is_motion_mode_switchable: hf.is_motion_mode_switchable,
    allow_warped_motion: hf.allow_warped_motion,
    gm_type: hf.gm_type,
    gm_params: hf.gm_params,
    ref_frame_sign_bias: hf.ref_frame_sign_bias,
    frame_width: hf.frame_width,
    frame_height: hf.frame_height,
    temporal,
  }
}

///|
/// The block being predicted, plus the tile bounds that limit the scans.
pub(all) struct Av1MvBlock {
  mi_row : Int
  mi_col : Int
  /// 4x4-unit extent.
  width4 : Int
  height4 : Int
  /// Pixel extent, which sets the clamp margin.
  block_width : Int
  block_height : Int
  /// Reference names per list; `av1_none_frame` when the list is unused.
  refs : Array[Int]
  tile_row_start : Int
  tile_row_end : Int
  tile_col_start : Int
  tile_col_end : Int
}

///|
/// The derived candidate stack and the contexts the inter mode tree consumes.
pub(all) struct Av1MvStack {
  /// Flattened `[index * 2 + list]` pairs of (row, col) in eighth-pel.
  mv_rows : Array[Int]
  mv_cols : Array[Int]
  weights : Array[Int]
  mut count : Int
  mut newmv_count : Int
  mut found_match : Int
  mut close_matches : Int
  mut total_matches : Int
  mut zero_mv_context : Int
  mut newmv_context : Int
  mut refmv_context : Int
  drl_contexts : Array[Int]
  global_rows : Array[Int]
  global_cols : Array[Int]
}

///|
fn av1_mv_stack_new() -> Av1MvStack {
  {
    mv_rows: Array::make(av1_ref_mv_stack_size * 2, 0),
    mv_cols: Array::make(av1_ref_mv_stack_size * 2, 0),
    weights: Array::make(av1_ref_mv_stack_size, 0),
    count: 0,
    newmv_count: 0,
    found_match: 0,
    close_matches: 0,
    total_matches: 0,
    zero_mv_context: 0,
    newmv_context: 0,
    refmv_context: 0,
    drl_contexts: Array::make(av1_ref_mv_stack_size, 0),
    global_rows: Array::make(2, 0),
    global_cols: Array::make(2, 0),
  }
}

///|
fn av1_stack_mv(stack : Av1MvStack, index : Int, list : Int) -> (Int, Int) {
  (stack.mv_rows[index * 2 + list], stack.mv_cols[index * 2 + list])
}

///|
fn av1_stack_set_mv(
  stack : Av1MvStack,
  index : Int,
  list : Int,
  row : Int,
  col : Int,
) -> Unit {
  stack.mv_rows[index * 2 + list] = row
  stack.mv_cols[index * 2 + list] = col
}

///|
fn av1_mv_inside(block : Av1MvBlock, row : Int, col : Int) -> Bool {
  row >= block.tile_row_start &&
  row < block.tile_row_end &&
  col >= block.tile_col_start &&
  col < block.tile_col_end
}

///|
/// Does this mode carry a freshly coded motion vector? How often the answer is
/// yes feeds the new-mv context.
fn av1_mode_has_newmv(mode : Int) -> Bool {
  mode == av1_mode_new_mv ||
  mode == av1_mode_new_nearest_mv ||
  mode == av1_mode_new_near_mv ||
  mode == av1_mode_new_new_mv
}

///|
/// Drop the precision the frame is not allowed to signal (AV1 §7.10.2.10). The
/// two branches round in opposite directions on purpose: forced-integer motion
/// rounds away from zero, dropping only the high-precision bit rounds toward it.
fn av1_lower_mv_precision(
  row : Int,
  col : Int,
  frame : Av1MvFrame,
) -> (Int, Int) {
  if frame.allow_high_precision_mv {
    return (row, col)
  }
  let lower = fn(value : Int) -> Int {
    if frame.force_integer_mv != 0 {
      let magnitude = (value.abs() + 3) >> 3 << 3
      if value > 0 {
        magnitude
      } else {
        -magnitude
      }
    } else if (value & 1) != 0 {
      if value > 0 {
        value - 1
      } else {
        value + 1
      }
    } else {
      value
    }
  }
  (lower(row), lower(col))
}

///|
/// The block's motion implied by the frame-level warp model for one list (AV1
/// §7.10.2.1). Identity and intra references give a zero vector.
fn av1_setup_global_mv(
  list : Int,
  block : Av1MvBlock,
  frame : Av1MvFrame,
) -> (Int, Int) {
  let name = block.refs[list]
  if name <= av1_intra_frame {
    return (0, 0)
  }
  let typ = frame.gm_type[name]
  if typ == av1_gm_identity {
    return (0, 0)
  }
  let params = frame.gm_params[name]
  if typ == av1_gm_translation {
    return (
      params[0] >> (av1_warped_model_prec_bits - 3),
      params[1] >> (av1_warped_model_prec_bits - 3),
    )
  }
  // Rotate-zoom and affine are evaluated at the block centre, then lowered to
  // the precision the frame allows.
  let centre_x = block.mi_col * 4 + block.block_width / 2 - 1
  let centre_y = block.mi_row * 4 + block.block_height / 2 - 1
  let bias = 1 << av1_warped_model_prec_bits
  let xc = (params[2] - bias) * centre_x + params[3] * centre_y + params[0]
  let yc = params[4] * centre_x + (params[5] - bias) * centre_y + params[1]
  let raw = if frame.allow_high_precision_mv {
    (
      av1_mc_round2_signed(yc, av1_warped_model_prec_bits - 3),
      av1_mc_round2_signed(xc, av1_warped_model_prec_bits - 3),
    )
  } else {
    (
      av1_mc_round2_signed(yc, av1_warped_model_prec_bits - 2) * 2,
      av1_mc_round2_signed(xc, av1_warped_model_prec_bits - 2) * 2,
    )
  }
  av1_lower_mv_precision(raw.0, raw.1, frame)
}

///|
/// Push one candidate, merging into an existing entry that already holds the
/// same vector (AV1 §7.10.2.5). Sets `found_match` when anything was found.
fn av1_search_stack(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  mv_row : Int,
  mv_col : Int,
  cand_list : Int,
  weight : Int,
) -> Unit {
  let unit = av1_field_unit(field, mv_row, mv_col)
  let mode = field.y_modes[unit]
  let large = field.width4[unit] >= 2 && field.height4[unit] >= 2
  let candidate = if (
      mode == av1_mode_global_mv || mode == av1_mode_global_global_mv
    ) &&
    frame.gm_type[block.refs[0]] > av1_gm_translation &&
    large {
    (stack.global_rows[0], stack.global_cols[0])
  } else {
    (field.mv_rows[unit * 2 + cand_list], field.mv_cols[unit * 2 + cand_list])
  }
  // Precision is lowered on the candidates, never on a decoded MV: the coder
  // already cannot produce an unallowed one.
  let mv = av1_lower_mv_precision(candidate.0, candidate.1, frame)
  if av1_mode_has_newmv(mode) {
    stack.newmv_count = stack.newmv_count + 1
  }
  stack.found_match = 1
  for idx in 0..<stack.count {
    if av1_stack_mv(stack, idx, 0) == mv {
      stack.weights[idx] = stack.weights[idx] + weight
      return
    }
  }
  if stack.count < av1_ref_mv_stack_size {
    av1_stack_set_mv(stack, stack.count, 0, mv.0, mv.1)
    stack.weights[stack.count] = weight
    stack.count = stack.count + 1
  }
}

///|
fn av1_compound_search_stack(
  field : Av1MotionField,
  stack : Av1MvStack,
  frame : Av1MvFrame,
  mv_row : Int,
  mv_col : Int,
  weight : Int,
) -> Unit {
  let unit = av1_field_unit(field, mv_row, mv_col)
  let mode = field.y_modes[unit]
  let first = av1_lower_mv_precision(
    field.mv_rows[unit * 2],
    field.mv_cols[unit * 2],
    frame,
  )
  let second = av1_lower_mv_precision(
    field.mv_rows[unit * 2 + 1],
    field.mv_cols[unit * 2 + 1],
    frame,
  )
  stack.found_match = 1
  for idx in 0..<stack.count {
    if av1_stack_mv(stack, idx, 0) == first &&
      av1_stack_mv(stack, idx, 1) == second {
      stack.weights[idx] = stack.weights[idx] + weight
      if av1_mode_has_newmv(mode) {
        stack.newmv_count = stack.newmv_count + 1
      }
      return
    }
  }
  if stack.count < av1_ref_mv_stack_size {
    av1_stack_set_mv(stack, stack.count, 0, first.0, first.1)
    av1_stack_set_mv(stack, stack.count, 1, second.0, second.1)
    stack.weights[stack.count] = weight
    stack.count = stack.count + 1
  }
  if av1_mode_has_newmv(mode) {
    stack.newmv_count = stack.newmv_count + 1
  }
}

///|
fn av1_add_ref_mv_candidate(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  mv_row : Int,
  mv_col : Int,
  is_compound : Bool,
  weight : Int,
) -> Unit {
  let unit = av1_field_unit(field, mv_row, mv_col)
  if !field.is_inter[unit] {
    return
  }
  if !is_compound {
    // A neighbour may hold this block's reference in either list; each match
    // contributes its own candidate.
    for cand_list = 0; cand_list < 2; cand_list = cand_list + 1 {
      if field.refs[unit * 2 + cand_list] == block.refs[0] {
        av1_search_stack(
          field, stack, block, frame, mv_row, mv_col, cand_list, weight,
        )
      }
    }
  } else if field.refs[unit * 2] == block.refs[0] &&
    field.refs[unit * 2 + 1] == block.refs[1] {
    av1_compound_search_stack(field, stack, frame, mv_row, mv_col, weight)
  }
}

///|
/// Walk one row of neighbours above or below the block (AV1 §7.10.2.2). The
/// far offsets are shifted by the block's own alignment so that a wide block
/// reaches the same source samples its neighbours were derived from.
fn av1_scan_row(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  delta_row : Int,
  is_compound : Bool,
) -> Unit {
  let mut end4 = block.width4
  let room_cols = field.cols - block.mi_col
  if end4 > room_cols {
    end4 = room_cols
  }
  if end4 > 16 {
    end4 = 16
  }
  let far = delta_row.abs() > 1
  let row_shift = if far { delta_row + (block.mi_row & 1) } else { delta_row }
  let col_shift = if far { 1 - (block.mi_col & 1) } else { 0 }
  let mut i = 0
  while i < end4 {
    let mv_row = block.mi_row + row_shift
    let mv_col = block.mi_col + col_shift + i
    if !av1_mv_inside(block, mv_row, mv_col) {
      break
    }
    let unit = av1_field_unit(field, mv_row, mv_col)
    let mut length = block.width4
    if field.width4[unit] < length {
      length = field.width4[unit]
    }
    if far && length < 2 {
      length = 2
    }
    if block.width4 >= 16 && length < 4 {
      length = 4
    }
    av1_add_ref_mv_candidate(
      field,
      stack,
      block,
      frame,
      mv_row,
      mv_col,
      is_compound,
      length * 2,
    )
    i = i + length
  }
}

///|
/// Walk one column of neighbours to the left or right (AV1 §7.10.2.3).
fn av1_scan_col(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  delta_col : Int,
  is_compound : Bool,
) -> Unit {
  let room = field.rows - block.mi_row
  let mut end4 = block.height4
  if end4 > room {
    end4 = room
  }
  if end4 > 16 {
    end4 = 16
  }
  let far = delta_col.abs() > 1
  let col_shift = if far { delta_col + (block.mi_col & 1) } else { delta_col }
  let row_shift = if far { 1 - (block.mi_row & 1) } else { 0 }
  let mut i = 0
  while i < end4 {
    let mv_row = block.mi_row + row_shift + i
    let mv_col = block.mi_col + col_shift
    if !av1_mv_inside(block, mv_row, mv_col) {
      break
    }
    let unit = av1_field_unit(field, mv_row, mv_col)
    let mut length = block.height4
    if field.height4[unit] < length {
      length = field.height4[unit]
    }
    if far && length < 2 {
      length = 2
    }
    if block.height4 >= 16 && length < 4 {
      length = 4
    }
    av1_add_ref_mv_candidate(
      field,
      stack,
      block,
      frame,
      mv_row,
      mv_col,
      is_compound,
      length * 2,
    )
    i = i + length
  }
}

///|
fn av1_scan_point(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  delta_row : Int,
  delta_col : Int,
  is_compound : Bool,
) -> Unit {
  let mv_row = block.mi_row + delta_row
  let mv_col = block.mi_col + delta_col
  if !av1_mv_inside(block, mv_row, mv_col) {
    return
  }
  let unit = av1_field_unit(field, mv_row, mv_col)
  if !field.written[unit] {
    return
  }
  av1_add_ref_mv_candidate(
    field, stack, block, frame, mv_row, mv_col, is_compound, 4,
  )
}

///|
/// The extra search used when the neighbourhood yielded fewer than two
/// candidates (AV1 §7.10.2.12). A single-reference block falls back to any
/// inter neighbour's vector, sign-flipped when it looks the other way in time,
/// and finally to the global-motion vector.
fn av1_extra_search(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  is_compound : Bool,
) -> Bool? {
  let mut w4 = block.width4
  if w4 > 16 {
    w4 = 16
  }
  let room_cols = field.cols - block.mi_col
  if w4 > room_cols {
    w4 = room_cols
  }
  let mut h4 = block.height4
  if h4 > 16 {
    h4 = 16
  }
  let room_rows = field.rows - block.mi_row
  if h4 > room_rows {
    h4 = room_rows
  }
  let num4x4 = if w4 < h4 { w4 } else { h4 }
  for pass in 0..<2 {
    let mut idx = 0
    while idx < num4x4 && stack.count < 2 {
      let mv_row = if pass == 0 { block.mi_row - 1 } else { block.mi_row + idx }
      let mv_col = if pass == 0 { block.mi_col + idx } else { block.mi_col - 1 }
      if !av1_mv_inside(block, mv_row, mv_col) {
        break
      }
      let unit = av1_field_unit(field, mv_row, mv_col)
      av1_add_extra_mv_candidate(field, stack, block, frame, unit, is_compound)
      idx = idx +
        (if pass == 0 { field.width4[unit] } else { field.height4[unit] })
    }
  }
  if !is_compound {
    for idx = stack.count; idx < 2; idx = idx + 1 {
      av1_stack_set_mv(
        stack,
        idx,
        0,
        stack.global_rows[0],
        stack.global_cols[0],
      )
    }
    return Some(true)
  }
  if stack.count >= 2 {
    return Some(true)
  }
  // The compound extended search (§7.10.2.12). Four scratch slots per list:
  // slots 0 and 1 take the candidates that share this block's references, the
  // global motion fills whatever is left of them, and slots 2 and 3 take the
  // candidates named by some other reference, sign-corrected for whichever
  // list they are being pushed onto. The merge then folds slot 2 (and 3 when
  // it exists) underneath a short same-reference list.
  let ext_rows = Array::make(8, 0)
  let ext_cols = Array::make(8, 0)
  let counts = Array::make(4, 0)
  let sz4 = if w4 < h4 { w4 } else { h4 }
  let mut idx = 0
  while idx < sz4 {
    let mv_row = block.mi_row - 1
    let mv_col = block.mi_col + idx
    if !av1_mv_inside(block, mv_row, mv_col) {
      break
    }
    let unit = av1_field_unit(field, mv_row, mv_col)
    av1_add_compound_extended(ext_rows, ext_cols, counts, field, block, frame, unit)
    idx = idx + field.width4[unit]
  }
  idx = 0
  while idx < sz4 {
    let mv_row = block.mi_row + idx
    let mv_col = block.mi_col - 1
    if !av1_mv_inside(block, mv_row, mv_col) {
      break
    }
    let unit = av1_field_unit(field, mv_row, mv_col)
    av1_add_compound_extended(ext_rows, ext_cols, counts, field, block, frame, unit)
    idx = idx + field.height4[unit]
  }
  for list in 0..<2 {
    let mut m = counts[list]
    if m >= 2 {
      continue
    }
    let diff = counts[list + 2]
    if diff != 0 {
      av1_ext_move(ext_rows, ext_cols, m + 0, list, m + 0, list, ext_rows, ext_cols)
      // diff[0] is slot 2 when list is 0 and slot 2 when list is 1; the list
      // picks the field, so a single move covers both.
      m = m + 1
      if m == 2 {
        continue
      }
      if diff == 2 {
        av1_ext_move(ext_rows, ext_cols, m + 0, list, 3, list, ext_rows, ext_cols)
        continue
      }
    }
    while m < 2 {
      let global = if list == 0 {
        (stack.global_rows[0], stack.global_cols[0])
      } else {
        (stack.global_rows[1], stack.global_cols[1])
      }
      ext_rows[(m) * 2 + list] = global.0
      ext_cols[(m) * 2 + list] = global.1
      m = m + 1
    }
  }
  // The merged candidates land right after the entries already on the stack,
  // so a one-entry stack is topped up and an empty one is filled from zero.
  let base = stack.count
  for slot in 0..<2 {
    av1_stack_set_mv(
      stack,
      base + slot,
      0,
      ext_rows[slot * 2 + 0],
      ext_cols[slot * 2 + 0],
    )
    av1_stack_set_mv(
      stack,
      base + slot,
      1,
      ext_rows[slot * 2 + 1],
      ext_cols[slot * 2 + 1],
    )
    stack.weights[base + slot] = 2
  }
  if base == 1 &&
    av1_stack_mv(stack, 0, 0) == av1_stack_mv(stack, 1, 0) &&
    av1_stack_mv(stack, 0, 1) == av1_stack_mv(stack, 1, 1) {
    av1_stack_set_mv(stack, 1, 0, ext_rows[1 * 2 + 0], ext_cols[1 * 2 + 0])
    av1_stack_set_mv(stack, 1, 1, ext_rows[1 * 2 + 1], ext_cols[1 * 2 + 1])
  }
  stack.count = 2
  Some(true)
}

///|
/// One compound extended candidate: fold the neighbour's two lists into the
/// same-reference and different-reference scratch slots (§7.10.2.12). The
/// different-reference slot takes the vector sign-corrected for the list it is
/// pushed onto, which is what makes a vector from a third reference usable by
/// either side of this block's pair.
fn av1_add_compound_extended(
  ext_rows : Array[Int],
  ext_cols : Array[Int],
  counts : Array[Int],
  field : Av1MotionField,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  unit : Int,
) -> Unit {
  // counts: 0 and 1 are the same-reference slots for each list, 2 and 3 the
  // different-reference ones.
  for n in 0..<2 {
    let cand_ref = field.refs[unit * 2 + n]
    if cand_ref <= av1_intra_frame {
      break
    }
    let cand_row = field.mv_rows[unit * 2 + n]
    let cand_col = field.mv_cols[unit * 2 + n]
    if cand_ref == block.refs[0] {
      if counts[0] < 2 {
        av1_ext_slot(ext_rows, ext_cols, counts[0], 0, cand_row, cand_col)
        counts[0] = counts[0] + 1
      }
      if counts[3] < 2 {
        let bias = frame.ref_frame_sign_bias[block.refs[1]] !=
          frame.ref_frame_sign_bias[cand_ref]
        av1_ext_slot(
          ext_rows,
          ext_cols,
          counts[3] + 2,
          1,
          if bias {
            -cand_row
          } else {
            cand_row
          },
          if bias {
            -cand_col
          } else {
            cand_col
          },
        )
        counts[3] = counts[3] + 1
      }
    } else if cand_ref == block.refs[1] {
      if counts[1] < 2 {
        av1_ext_slot(ext_rows, ext_cols, counts[1], 1, cand_row, cand_col)
        counts[1] = counts[1] + 1
      }
      if counts[2] < 2 {
        let bias = frame.ref_frame_sign_bias[block.refs[0]] !=
          frame.ref_frame_sign_bias[cand_ref]
        av1_ext_slot(
          ext_rows,
          ext_cols,
          counts[2] + 2,
          0,
          if bias {
            -cand_row
          } else {
            cand_row
          },
          if bias {
            -cand_col
          } else {
            cand_col
          },
        )
        counts[2] = counts[2] + 1
      }
    } else {
      let bias0 = frame.ref_frame_sign_bias[block.refs[0]] !=
        frame.ref_frame_sign_bias[cand_ref]
      if counts[2] < 2 {
        av1_ext_slot(
          ext_rows,
          ext_cols,
          counts[2] + 2,
          0,
          if bias0 {
            -cand_row
          } else {
            cand_row
          },
          if bias0 {
            -cand_col
          } else {
            cand_col
          },
        )
        counts[2] = counts[2] + 1
      }
      let bias1 = frame.ref_frame_sign_bias[block.refs[1]] !=
        frame.ref_frame_sign_bias[cand_ref]
      if counts[3] < 2 {
        av1_ext_slot(
          ext_rows,
          ext_cols,
          counts[3] + 2,
          1,
          if bias1 {
            -cand_row
          } else {
            cand_row
          },
          if bias1 {
            -cand_col
          } else {
            cand_col
          },
        )
        counts[3] = counts[3] + 1
      }
    }
  }
}

///|
/// Write one scratch slot's list field.
fn av1_ext_slot(
  ext_rows : Array[Int],
  ext_cols : Array[Int],
  slot : Int,
  list : Int,
  row : Int,
  col : Int,
) -> Unit {
  ext_rows[slot * 2 + list] = row
  ext_cols[slot * 2 + list] = col
}

///|
/// Copy one scratch slot's list field over another's.
fn av1_ext_move(
  ext_rows : Array[Int],
  ext_cols : Array[Int],
  to_slot : Int,
  to_list : Int,
  from_slot : Int,
  from_list : Int,
  _rows : Array[Int],
  _cols : Array[Int],
) -> Unit {
  ext_rows[to_slot * 2 + to_list] = ext_rows[from_slot * 2 + from_list]
  ext_cols[to_slot * 2 + to_list] = ext_cols[from_slot * 2 + from_list]
}

///|
fn av1_add_extra_mv_candidate(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  unit : Int,
  is_compound : Bool,
) -> Unit {
  if is_compound {
    return
  }
  for cand_list in 0..<2 {
    let cand_ref = field.refs[unit * 2 + cand_list]
    if cand_ref <= av1_intra_frame {
      continue
    }
    let mut row = field.mv_rows[unit * 2 + cand_list]
    let mut col = field.mv_cols[unit * 2 + cand_list]
    if frame.ref_frame_sign_bias[cand_ref] !=
      frame.ref_frame_sign_bias[block.refs[0]] {
      row = -row
      col = -col
    }
    let mut found = false
    for idx in 0..<stack.count {
      if av1_stack_mv(stack, idx, 0) == (row, col) {
        found = true
      }
    }
    if !found && stack.count < av1_ref_mv_stack_size {
      av1_stack_set_mv(stack, stack.count, 0, row, col)
      stack.weights[stack.count] = 2
      stack.count = stack.count + 1
    }
  }
}

///|
/// Bubble one range of the stack into descending weight order (AV1 §7.10.2.11).
/// Swaps happen only on a strict `<`, so equal weights keep their discovery
/// order; that tie behaviour is part of the normative candidate list.
fn av1_sort_mv_stack(
  stack : Av1MvStack,
  start : Int,
  end : Int,
  is_compound : Bool,
) -> Unit {
  let lists = if is_compound { 2 } else { 1 }
  let mut stop = end
  while stop > start {
    let mut new_end = start
    for idx = start + 1; idx < stop; idx = idx + 1 {
      if stack.weights[idx - 1] < stack.weights[idx] {
        let weight = stack.weights[idx - 1]
        stack.weights[idx - 1] = stack.weights[idx]
        stack.weights[idx] = weight
        for list in 0..<lists {
          let a = av1_stack_mv(stack, idx - 1, list)
          let b = av1_stack_mv(stack, idx, list)
          av1_stack_set_mv(stack, idx - 1, list, b.0, b.1)
          av1_stack_set_mv(stack, idx, list, a.0, a.1)
        }
        new_end = idx
      }
    }
    stop = new_end
  }
}

///|
/// Clamp one component to what this block may legally reach (AV1 §7.10.2.13).
/// The window is measured from the block's own edges, so it widens with size.
fn av1_clamp_mv(
  value : Int,
  unit : Int,
  extent : Int,
  frame_units : Int,
  border : Int,
) -> Int {
  let to_start = -(unit * 4 * 8)
  let to_end = (frame_units - extent - unit) * 4 * 8
  av1_mc_clip(to_start - border, to_end + border, value)
}

///|
/// Derive the DRL contexts, clamp every candidate and set the three mode-tree
/// contexts (AV1 §7.10.2.14).
fn av1_stack_contexts(
  field : Av1MotionField,
  stack : Av1MvStack,
  block : Av1MvBlock,
  is_compound : Bool,
  new_count : Int,
) -> Unit {
  for idx in 0..<stack.count {
    let mut z = 0
    if idx + 1 < stack.count {
      if stack.weights[idx] >= av1_ref_cat_level {
        if stack.weights[idx + 1] < av1_ref_cat_level {
          z = 1
        }
      } else {
        z = 2
      }
    }
    stack.drl_contexts[idx] = z
  }
  let lists = if is_compound { 2 } else { 1 }
  let row_border = av1_mv_border + block.block_height * 8
  let col_border = av1_mv_border + block.block_width * 8
  for list in 0..<lists {
    for idx in 0..<stack.count {
      let mv = av1_stack_mv(stack, idx, list)
      av1_stack_set_mv(
        stack,
        idx,
        list,
        av1_clamp_mv(mv.0, block.mi_row, block.height4, field.rows, row_border),
        av1_clamp_mv(mv.1, block.mi_col, block.width4, field.cols, col_border),
      )
    }
  }
  if stack.close_matches == 0 {
    stack.newmv_context = if stack.total_matches < 1 {
      stack.total_matches
    } else {
      1
    }
    stack.refmv_context = stack.total_matches
  } else if stack.close_matches == 1 {
    stack.newmv_context = 3 - (if new_count < 1 { new_count } else { 1 })
    stack.refmv_context = 2 + stack.total_matches
  } else {
    stack.newmv_context = 5 - (if new_count < 1 { new_count } else { 1 })
    stack.refmv_context = 5
  }
}

///|
/// Build the candidate stack and the inter-mode contexts for one block (AV1
/// §7.10.2). Motion-vector reference storage (`use_ref_frame_mvs`) adds a
/// temporal scan between the near weighting and the corner scan; it reads the
/// frame's projected 8x8 grid, and a frame that asks for it without one is
/// refused rather than decoded with a candidate list that lost its temporal
/// half.
pub fn av1_find_mv_stack(
  field : Av1MotionField,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  is_compound : Bool,
) -> Av1MvStack? {
  let stack = av1_mv_stack_new()
  let bw4 = block.width4
  let bh4 = block.height4
  let global = av1_setup_global_mv(0, block, frame)
  stack.global_rows[0] = global.0
  stack.global_cols[0] = global.1
  if is_compound {
    let other = av1_setup_global_mv(1, block, frame)
    stack.global_rows[1] = other.0
    stack.global_cols[1] = other.1
  }
  stack.found_match = 0
  av1_scan_row(field, stack, block, frame, -1, is_compound)
  let mut found_above_match = stack.found_match
  stack.found_match = 0
  av1_scan_col(field, stack, block, frame, -1, is_compound)
  let mut found_left_match = stack.found_match
  stack.found_match = 0
  if (if bw4 > bh4 { bw4 } else { bh4 }) <= 16 {
    av1_scan_point(field, stack, block, frame, -1, bw4, is_compound)
  }
  if stack.found_match == 1 {
    found_above_match = 1
  }
  stack.close_matches = found_above_match + found_left_match
  let num_nearest = stack.count
  let num_new = stack.newmv_count
  for idx in 0..<num_nearest {
    stack.weights[idx] = stack.weights[idx] + av1_ref_cat_level
  }
  stack.zero_mv_context = 0
  stack.found_match = 0
  // A frame that names its references also projects their vectors onto an 8x8
  // grid; the temporal scan reads that grid between the near weighting and the
  // corner scan, and is the stage that decides `zero_mv_context`.
  if frame.use_ref_frame_mvs &&
    !av1_temporal_scan(stack, block, frame, is_compound) {
    return None
  }
  av1_scan_point(field, stack, block, frame, -1, -1, is_compound)
  if stack.found_match == 1 {
    found_above_match = 1
  }
  stack.found_match = 0
  av1_scan_row(field, stack, block, frame, -3, is_compound)
  if stack.found_match == 1 {
    found_above_match = 1
  }
  stack.found_match = 0
  av1_scan_col(field, stack, block, frame, -3, is_compound)
  if stack.found_match == 1 {
    found_left_match = 1
  }
  stack.found_match = 0
  if bh4 > 1 {
    av1_scan_row(field, stack, block, frame, -5, is_compound)
    if stack.found_match == 1 {
      found_above_match = 1
    }
    stack.found_match = 0
  }
  if bw4 > 1 {
    av1_scan_col(field, stack, block, frame, -5, is_compound)
    if stack.found_match == 1 {
      found_left_match = 1
    }
    stack.found_match = 0
  }
  stack.total_matches = found_above_match + found_left_match
  av1_sort_mv_stack(stack, 0, num_nearest, is_compound)
  av1_sort_mv_stack(stack, num_nearest, stack.count, is_compound)
  if stack.count < 2 {
    match av1_extra_search(field, stack, block, frame, is_compound) {
      None => return None
      Some(_) => ()
    }
  }
  av1_stack_contexts(field, stack, block, is_compound, num_new)
  Some(stack)
}
