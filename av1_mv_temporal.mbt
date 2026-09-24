/// Temporal scan (AV1 §7.10.2.5) and temporal sample (§7.10.2.6): the motion
/// vectors that `motion_field_estimation` projected onto this frame's 8x8 grid
/// are looked up at the block's own cells and at three offsets just outside the
/// block, and pushed onto the candidate stack with weight 2.
///
/// The scan runs after the near-neighbour weighting and before the corner scan,
/// and only when the frame sets `use_ref_frame_mvs`. It is also the stage that
/// decides `zero_mv_context`: the block's own cell sets it to 1, and the
/// comparison against the global motion vector may set it back to 0.

///|
/// Scan the block's own cells, then the three offsets outside the block that
/// stay inside the same 64x64 superblock (§7.10.2.5).
///
/// Compound entries are complete vector pairs: both reference projections must
/// be present before either vector can contribute to the candidate stack.
fn av1_temporal_scan(
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  is_compound : Bool,
) -> Bool {
  let grid = match frame.temporal {
    Some(value) => value
    None => return false
  }
  let bw4 = block.width4
  let bh4 = block.height4
  let step_w4 = if bw4 >= 16 { 4 } else { 2 }
  let step_h4 = if bh4 >= 16 { 4 } else { 2 }
  let row_limit = if bh4 < 16 { bh4 } else { 16 }
  let col_limit = if bw4 < 16 { bw4 } else { 16 }
  let mut delta_row = 0
  while delta_row < row_limit {
    let mut delta_col = 0
    while delta_col < col_limit {
      av1_temporal_sample(
        stack,
        block,
        frame,
        grid,
        delta_row,
        delta_col,
        is_compound~,
      )
      delta_col = delta_col + step_w4
    }
    delta_row = delta_row + step_h4
  }
  // A block of at least 8x8 and less than 64x64 also probes the cells just
  // below it and to its right, as long as those stay in its own superblock.
  let allow_extension = bh4 >= 2 && bh4 < 16 && bw4 >= 2 && bw4 < 16
  if allow_extension {
    let offsets : Array[(Int, Int)] = [(bh4, -2), (bh4, bw4), (bh4 - 2, bw4)]
    for offset in offsets {
      if av1_tpl_sb_border(block, offset.0, offset.1) {
        av1_temporal_sample(
          stack,
          block,
          frame,
          grid,
          offset.0,
          offset.1,
          is_compound~,
        )
      }
    }
  }
  true
}

///|
/// Does the offset stay inside the block's own 64x64 superblock? Both axes are
/// checked against the 16 MI units of a superblock.
fn av1_tpl_sb_border(
  block : Av1MvBlock,
  delta_row : Int,
  delta_col : Int,
) -> Bool {
  let row = (block.mi_row & 15) + delta_row
  let col = (block.mi_col & 15) + delta_col
  row >= 0 && row < 16 && col >= 0 && col < 16
}

///|
/// Look up the projected vector at one offset and push it onto the stack
/// (§7.10.2.6). A compound pair is merged only when both list vectors match;
/// sharing the first vector alone does not make two candidates identical.
fn av1_temporal_sample(
  stack : Av1MvStack,
  block : Av1MvBlock,
  frame : Av1MvFrame,
  grid : Av1MotionFieldGrid,
  delta_row : Int,
  delta_col : Int,
  is_compound? : Bool = false,
) -> Unit {
  let mv_row = (block.mi_row + delta_row) | 1
  let mv_col = (block.mi_col + delta_col) | 1
  if !av1_mv_inside(block, mv_row, mv_col) {
    return
  }
  let x8 = mv_col >> 1
  let y8 = mv_row >> 1
  if x8 < 0 || y8 < 0 || x8 >= grid.w8 || y8 >= grid.h8 {
    return
  }
  if delta_row == 0 && delta_col == 0 {
    stack.zero_mv_context = 1
  }
  let slot = block.refs[0] - av1_last_frame
  if slot < 0 || slot >= grid.mv_rows.length() {
    return
  }
  let index = y8 * grid.w8 + x8
  let cand_row = grid.mv_rows[slot][index]
  let cand_col = grid.mv_cols[slot][index]
  if cand_row == av1_mv_invalid {
    return
  }
  // The grid holds projected vectors, which carry one more bit of precision
  // than the frame is allowed to signal.
  let candidate = av1_lower_mv_precision(cand_row, cand_col, frame)
  let other = if is_compound {
    let other_slot = block.refs[1] - av1_last_frame
    if other_slot < 0 || other_slot >= grid.mv_rows.length() {
      return
    }
    let other_row = grid.mv_rows[other_slot][index]
    let other_col = grid.mv_cols[other_slot][index]
    if other_row == av1_mv_invalid {
      return
    }
    av1_lower_mv_precision(other_row, other_col, frame)
  } else {
    (0, 0)
  }
  if delta_row == 0 && delta_col == 0 {
    if (candidate.0 - stack.global_rows[0]).abs() >= 16 ||
      (candidate.1 - stack.global_cols[0]).abs() >= 16 ||
      (
        is_compound &&
        (
          (other.0 - stack.global_rows[1]).abs() >= 16 ||
          (other.1 - stack.global_cols[1]).abs() >= 16
        )
      ) {
      stack.zero_mv_context = 1
    } else {
      stack.zero_mv_context = 0
    }
  }
  for idx in 0..<stack.count {
    if av1_stack_mv(stack, idx, 0) == candidate &&
      (!is_compound || av1_stack_mv(stack, idx, 1) == other) {
      stack.weights[idx] = stack.weights[idx] + 2
      return
    }
  }
  if stack.count < av1_ref_mv_stack_size {
    av1_stack_set_mv(stack, stack.count, 0, candidate.0, candidate.1)
    if is_compound {
      av1_stack_set_mv(stack, stack.count, 1, other.0, other.1)
    }
    stack.weights[stack.count] = 2
    stack.count = stack.count + 1
  }
}
