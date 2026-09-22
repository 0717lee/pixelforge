/// Temporal scan (AV1 §7.10.2.5) and temporal sample (§7.10.2.6), driven
/// directly on a synthetic 8x8 grid.
///
/// `inter_temporalmv_64x64` is a real stream whose only reference is a key
/// frame, so its projected grid holds no usable vector and the fixture pins the
/// scan's `zero_mv_context` and nothing else. The candidate push, the weight-2
/// merge, the precision lowering, the stride and the same-superblock extension
/// are pinned here instead, on grids that do hold vectors.

///|
/// A frame that asks for a temporal scan over the given grid.
fn av1_temporal_test_frame(
  grid : Av1MotionFieldGrid?,
  allow_high_precision_mv : Bool,
  force_integer_mv : Int,
) -> Av1MvFrame {
  {
    allow_high_precision_mv,
    use_ref_frame_mvs: true,
    force_integer_mv,
    is_motion_mode_switchable: false,
    allow_warped_motion: false,
    gm_type: Array::make(av1_total_refs_per_frame, av1_gm_identity),
    gm_params: Array::make(av1_total_refs_per_frame, av1_identity_gm_params()),
    ref_frame_sign_bias: Array::make(av1_total_refs_per_frame, 0),
    // Unused by the temporal scan: it reads no stored reference.
    frame_width: 0,
    frame_height: 0,
    temporal: grid,
  }
}

///|
/// A grid over `w8` * `h8` cells whose LAST slot holds the given vectors, keyed
/// by `y8 * w8 + x8`. Every other cell is `av1_mv_invalid`.
fn av1_temporal_test_grid(
  w8 : Int,
  h8 : Int,
  vectors : Array[(Int, Int, (Int, Int))],
) -> Av1MotionFieldGrid {
  let rows = Array::make(w8 * h8, av1_mv_invalid)
  let cols = Array::make(w8 * h8, av1_mv_invalid)
  for vector in vectors {
    let index = vector.0 * w8 + vector.1
    rows[index] = vector.2.0
    cols[index] = vector.2.1
  }
  { refs: [av1_last_frame], mv_rows: [rows], mv_cols: [cols], w8, h8, }
}

///|
/// A block at the given MI position with `refs[0]` naming LAST, so the scan
/// reads slot 0 of the grid.
fn av1_temporal_test_block(
  mi_row : Int,
  mi_col : Int,
  width4 : Int,
  height4 : Int,
) -> Av1MvBlock {
  {
    mi_row,
    mi_col,
    width4,
    height4,
    block_width: width4 * 4,
    block_height: height4 * 4,
    refs: [av1_last_frame, av1_none_frame],
    tile_row_start: 0,
    tile_row_end: 16,
    tile_col_start: 0,
    tile_col_end: 16,
  }
}

///|
test "temporal scan pushes the own cell's vector with weight 2" {
  // A 8x8 block: bw4 = bh4 = 2, so the in-block loop visits exactly the block's
  // own cell and the three extension offsets fall on invalid cells.
  let grid = av1_temporal_test_grid(8, 8, [(2, 2, (24, -16))])
  let stack = av1_mv_stack_new()
  guard av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  ) else {
    fail("temporal scan refused a single-reference frame")
  }
  assert_eq(stack.count, 1)
  assert_eq(av1_stack_mv(stack, 0, 0), (24, -16))
  assert_eq(stack.weights[0], 2)
  // The own cell sets ZeroMvContext to 1, and the vector is 24 rows away from
  // the zero global motion vector, so the comparison keeps it at 1.
  assert_eq(stack.zero_mv_context, 1)
}

///|
test "temporal scan resets zero_mv_context for a small own-cell vector" {
  let grid = av1_temporal_test_grid(8, 8, [(2, 2, (8, 4))])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 1)
  // Both components are inside 16 of the global vector, so the context drops
  // back to 0.
  assert_eq(stack.zero_mv_context, 0)
}

///|
test "temporal scan skips a cell no projection reached" {
  // The grid exists but no projection wrote any of the four cells this block
  // probes ((2,2) own, (3,1), (3,3) and (2,3) outside it), so every lookup
  // returns on the invalid marker and nothing is pushed.
  let grid = av1_temporal_test_grid(8, 8, [(0, 0, (40, 40))])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 0)
  // The context is set before the lookup, so an unreached cell still selects the
  // zero-mv branch.
  assert_eq(stack.zero_mv_context, 1)
}

///|
test "temporal scan merges a repeated vector into one weighted candidate" {
  // The own cell (2,2) and the (bh4,-2) extension cell (3,1) hold the same
  // vector, so the second visit adds weight instead of a stack entry.
  let grid = av1_temporal_test_grid(8, 8, [(2, 2, (24, -16)), (3, 1, (24, -16))])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 1)
  assert_eq(stack.weights[0], 4)
}

///|
test "temporal scan lowers the precision of the projected vector" {
  // allow_high_precision_mv = 0: an odd component rounds toward zero, so 25
  // becomes 24 and -3 becomes -2.
  let grid = av1_temporal_test_grid(8, 8, [(2, 2, (25, -3))])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), false, 0),
    false,
  )
  assert_eq(av1_stack_mv(stack, 0, 0), (24, -2))
}

///|
test "temporal scan steps a wide block by four MI units" {
  // bw4 = 16, so stepW4 is 4 and Min(bw4, 16) is 16: four columns are visited.
  // mi_col is 0, so the four probes land on x8 = 0, 2, 4, 6.
  let grid = av1_temporal_test_grid(8, 8, [
    (2, 0, (8, 0)),
    (2, 2, (16, 0)),
    (2, 4, (24, 0)),
    (2, 6, (32, 0)),
  ])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 0, 16, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 4)
  assert_eq(stack.mv_rows, [8, 0, 16, 0, 24, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0])
}

///|
test "temporal scan does not extend a 64-pixel block" {
  // bh4 = bw4 = 16, so allowExtension is false. The only cells holding vectors
  // are the two extension cells a 16x4-probe could reach ((16,16) at y8 8, x8 8
  // and (14,16) at y8 7, x8 8), which a 64x64 block must not visit. The third
  // offset, (16,-2), lands on mvCol -1 and is dropped by the tile bound even
  // when the extension is allowed.
  let grid = av1_temporal_test_grid(16, 16, [(8, 8, (40, 0)), (7, 8, (48, 0))])
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    av1_temporal_test_block(0, 0, 16, 16),
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 0)
}

///|
test "temporal scan stops at the tile's right edge" {
  // The block's last MI column is 15 and the tile ends at 16, so the
  // (bh4, bw4) offset probes mvCol = 17, outside the tile, and the sample is
  // dropped even though the grid holds a vector at that cell. The own cell, at
  // mvCol = 15, is kept.
  let grid = av1_temporal_test_grid(16, 8, [(2, 7, (8, 8)), (3, 8, (24, -16))])
  let block = {
    mi_row: 4,
    mi_col: 15,
    width4: 2,
    height4: 2,
    block_width: 8,
    block_height: 8,
    refs: [av1_last_frame, av1_none_frame],
    tile_row_start: 0,
    tile_row_end: 16,
    tile_col_start: 0,
    tile_col_end: 16,
  }
  let stack = av1_mv_stack_new()
  let _ = av1_temporal_scan(
    stack,
    block,
    av1_temporal_test_frame(Some(grid), true, 0),
    false,
  )
  assert_eq(stack.count, 1)
  assert_eq(av1_stack_mv(stack, 0, 0), (8, 8))
}

///|
test "temporal scan's superblock bound rejects the offsets around the block" {
  // The extension offsets are only probed when they stay inside the block's own
  // 64x64 superblock, so (bh4, -2) in front of a block at MI column 0 maps to
  // column -2 and is rejected, while the same offset one unit in is accepted.
  let corner = av1_temporal_test_block(0, 0, 2, 2)
  assert_eq(av1_tpl_sb_border(corner, 2, -2), false)
  assert_eq(av1_tpl_sb_border(av1_temporal_test_block(0, 2, 2, 2), 2, -2), true)
  // A 64-pixel block's own extension row is 16 MI units, which never fits.
  assert_eq(
    av1_tpl_sb_border(av1_temporal_test_block(0, 0, 16, 16), 16, 16),
    false,
  )
  assert_eq(av1_tpl_sb_border(corner, 2, 2), true)
}

///|
test "temporal scan refuses a frame that carries no grid" {
  // A frame that sets use_ref_frame_mvs without a projected grid cannot run the
  // scan; the caller refuses the frame rather than decoding with a candidate
  // list that lost its temporal half.
  let stack = av1_mv_stack_new()
  let ok = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(None, true, 0),
    false,
  )
  assert_eq(ok, false)
  assert_eq(stack.count, 0)
}

///|
test "temporal scan refuses a compound block" {
  // The second list of the temporal sample process is not implemented, and
  // compound prediction is refused with reference_select at the frame gate, so
  // the scan reports the refusal instead of dropping half the candidates.
  let grid = av1_temporal_test_grid(8, 8, [(2, 2, (24, -16))])
  let stack = av1_mv_stack_new()
  let ok = av1_temporal_scan(
    stack,
    av1_temporal_test_block(4, 4, 2, 2),
    av1_temporal_test_frame(Some(grid), true, 0),
    true,
  )
  assert_eq(ok, false)
  assert_eq(stack.count, 0)
}
