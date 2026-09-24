/// Original dav1d 1.2.1 C oracle; regenerate with scripts/generate-av1-compound-temporal-reference.py.

///|
let av1_compound_temporal_c_oracle : Array[Array[Int]] = [
  [16, -24, -16, 24, 4, 17, -25, -17, 25, 2],
  [16, -24, -16, 24, 6],
  [16, -24, -16, 24, 6],
  [0, 0, 31, -47, 4, 0, 0, 33, -49, 2],
  [
    0, 0, 0, 0, 640, 8, 0, -8, 0, 640, 16, 0, -16, 0, 640, 24, 0, -24, 0, 640, 32,
    0, -32, 0, 640, 40, 0, -40, 0, 644, 48, 0, -48, 0, 640, 56, 0, -56, 0, 640,
  ],
]

///|
test "compound temporal candidate pairs agree with original dav1d C projection and precision" {
  for policy in 0..<5 {
    let grid = av1_compound_temporal_grid()
    let block = av1_temporal_test_block(4, 4, 2, 2)
    block.refs[1] = av1_bwd_ref_frame
    // The frame header sets allow_high_precision_mv to 0 for integer MVs.
    let frame = av1_temporal_test_frame(
      Some(grid),
      policy != 1 && policy != 2,
      if policy == 2 {
        1
      } else {
        0
      },
    )
    let stack = av1_mv_stack_new()
    if policy == 4 {
      stack.count = 8
      for index in 0..<8 {
        av1_stack_set_mv(stack, index, 0, index * 8, 0)
        av1_stack_set_mv(stack, index, 1, -index * 8, 0)
        stack.weights[index] = 640
      }
    }
    for step in 0..<3 {
      let row = if policy == 4 {
        if step == 2 {
          65
        } else {
          40
        }
      } else if step == 2 {
        33
      } else {
        31
      }
      let col = if policy == 4 { 0 } else if step == 2 { -49 } else { -47 }
      let denominator = if policy >= 3 { 1 } else { 2 }
      let first = av1_mv_projection(
        row,
        col,
        if policy == 3 {
          0
        } else {
          1
        },
        denominator,
      )
      let second = av1_mv_projection(
        row,
        col,
        if policy == 3 {
          1
        } else {
          -1
        },
        denominator,
      )
      av1_compound_temporal_put(grid, 2, 2, first, second)
      av1_temporal_sample(stack, block, frame, grid, 0, 0, is_compound=true)
    }
    let expected = av1_compound_temporal_c_oracle[policy]
    assert_eq(stack.count, expected.length() / 5)
    for index in 0..<stack.count {
      assert_eq(
        av1_stack_mv(stack, index, 0),
        (expected[index * 5], expected[index * 5 + 1]),
      )
      assert_eq(
        av1_stack_mv(stack, index, 1),
        (expected[index * 5 + 2], expected[index * 5 + 3]),
      )
      assert_eq(stack.weights[index], expected[index * 5 + 4])
    }
  }
}
