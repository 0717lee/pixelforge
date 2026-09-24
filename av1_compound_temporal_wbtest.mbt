///|
fn av1_compound_temporal_grid() -> Av1MotionFieldGrid {
  {
    refs: [1, 2, 3, 4, 5, 6, 7],
    mv_rows: Array::makei(7, _ => Array::make(64, av1_mv_invalid)),
    mv_cols: Array::makei(7, _ => Array::make(64, av1_mv_invalid)),
    w8: 8,
    h8: 8,
  }
}

///|
fn av1_compound_temporal_put(
  grid : Av1MotionFieldGrid,
  row : Int,
  col : Int,
  first : (Int, Int),
  second : (Int, Int),
) -> Unit {
  let index = row * grid.w8 + col
  grid.mv_rows[0][index] = first.0
  grid.mv_cols[0][index] = first.1
  grid.mv_rows[4][index] = second.0
  grid.mv_cols[4][index] = second.1
}

///|
test "compound temporal scan preserves pair order and merges only complete matching pairs" {
  let grid = av1_compound_temporal_grid()
  av1_compound_temporal_put(grid, 2, 2, (24, -16), (40, -8))
  av1_compound_temporal_put(grid, 3, 1, (24, -16), (40, -8))
  av1_compound_temporal_put(grid, 3, 3, (24, -16), (41, -8))
  av1_compound_temporal_put(grid, 2, 3, (-16, 16), (16, 16))
  let block = av1_temporal_test_block(4, 4, 2, 2)
  block.refs[1] = av1_bwd_ref_frame
  let stack = av1_mv_stack_new()
  assert_true(
    av1_temporal_scan(
      stack,
      block,
      av1_temporal_test_frame(Some(grid), true, 0),
      true,
    ),
  )
  assert_eq(stack.count, 3)
  assert_eq(av1_stack_mv(stack, 0, 0), (24, -16))
  assert_eq(av1_stack_mv(stack, 0, 1), (40, -8))
  assert_eq(av1_stack_mv(stack, 1, 0), (24, -16))
  assert_eq(av1_stack_mv(stack, 1, 1), (41, -8))
  assert_eq(av1_stack_mv(stack, 2, 0), (-16, 16))
  assert_eq(av1_stack_mv(stack, 2, 1), (16, 16))
  assert_eq([stack.weights[0], stack.weights[1], stack.weights[2]], [4, 2, 2])
  assert_eq(stack.zero_mv_context, 1)
}

///|
test "compound temporal precision and zero context consider both reference lists" {
  let grid = av1_compound_temporal_grid()
  let block = av1_temporal_test_block(4, 4, 2, 2)
  block.refs[1] = av1_bwd_ref_frame
  av1_compound_temporal_put(grid, 2, 2, (7, -3), (-19, 5))
  let stack = av1_mv_stack_new()
  assert_true(
    av1_temporal_scan(
      stack,
      block,
      av1_temporal_test_frame(Some(grid), false, 0),
      true,
    ),
  )
  assert_eq(av1_stack_mv(stack, 0, 0), (6, -2))
  assert_eq(av1_stack_mv(stack, 0, 1), (-18, 4))
  assert_eq(stack.zero_mv_context, 1)
  av1_compound_temporal_put(grid, 2, 2, (7, -3), (-7, 5))
  let nearby = av1_mv_stack_new()
  assert_true(
    av1_temporal_scan(
      nearby,
      block,
      av1_temporal_test_frame(Some(grid), false, 1),
      true,
    ),
  )
  assert_eq(av1_stack_mv(nearby, 0, 0), (8, 0))
  assert_eq(av1_stack_mv(nearby, 0, 1), (-8, 8))
  assert_eq(nearby.zero_mv_context, 0)
  grid.mv_rows[4][2 * 8 + 2] = av1_mv_invalid
  let missing = av1_mv_stack_new()
  assert_true(
    av1_temporal_scan(
      missing,
      block,
      av1_temporal_test_frame(Some(grid), true, 0),
      true,
    ),
  )
  assert_eq(missing.count, 0)
  assert_eq(missing.zero_mv_context, 1)
}

///|
test "compound temporal candidate can merge into a full stack without exceeding capacity" {
  let grid = av1_compound_temporal_grid()
  av1_compound_temporal_put(grid, 2, 2, (40, 0), (-40, 0))
  let block = av1_temporal_test_block(4, 4, 2, 2)
  block.refs[1] = av1_bwd_ref_frame
  let stack = av1_mv_stack_new()
  for index in 0..<8 {
    av1_stack_set_mv(stack, index, 0, index * 8, 0)
    av1_stack_set_mv(stack, index, 1, -index * 8, 0)
    stack.weights[index] = 640
  }
  stack.count = 8
  assert_true(
    av1_temporal_scan(
      stack,
      block,
      av1_temporal_test_frame(Some(grid), true, 0),
      true,
    ),
  )
  assert_eq(stack.count, 8)
  assert_eq(stack.weights[5], 642)
  av1_compound_temporal_put(grid, 2, 2, (40, 0), (-41, 0))
  assert_true(
    av1_temporal_scan(
      stack,
      block,
      av1_temporal_test_frame(Some(grid), true, 0),
      true,
    ),
  )
  assert_eq(stack.count, 8)
  assert_eq(stack.weights[5], 642)
}

///|
test "compound temporal projection derives opposite list distances with signed rounding" {
  let base = av1_mc_test_frame(Array::make(64 * 64, 100), 64, 64, 32, 32, 8, 0)
  let vectors = Array::make(16 * 16 * 2, 0)
  for index in 0..<(16 * 16) {
    vectors[index * 2] = 31
    vectors[index * 2 + 1] = -47
  }
  let saved_hints = Array::make(8, 0)
  saved_hints[av1_alt_ref_frame] = 1
  let source : Av1RefFrame = {
    ..base,
    frame_type: av1_inter_frame,
    order_hint: 2,
    mi_cols: 16,
    mi_rows: 16,
    mf_refs: Array::make(16 * 16, av1_last_frame),
    mf_mvs: vectors,
    saved_order_hints: saved_hints,
  }
  let refs : Array[Av1RefFrame?] = Array::make(8, None)
  refs[av1_last_frame] = Some(source)
  let hints = Array::make(8, 0)
  hints[av1_last_frame] = 2
  hints[av1_golden_frame] = 5
  hints[av1_bwd_ref_frame] = 4
  let grid = av1_motion_field_estimation(
    mfe_test_sequence(),
    3,
    hints,
    refs,
    16,
    16,
  )
  let block = av1_temporal_test_block(4, 4, 2, 2)
  block.refs[1] = av1_bwd_ref_frame
  let stack = av1_mv_stack_new()
  assert_true(
    av1_temporal_scan(
      stack,
      block,
      av1_temporal_test_frame(Some(grid), true, 0),
      true,
    ),
  )
  assert_eq(stack.count, 1)
  assert_eq(av1_stack_mv(stack, 0, 0), (16, -24))
  assert_eq(av1_stack_mv(stack, 0, 1), (-16, 24))
  assert_eq(stack.weights[0], 8)
}
