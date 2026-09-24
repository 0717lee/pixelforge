///|
/// OBMC caps candidates by log2 of the current block's MI extent. A 32-pixel
/// side is eight MIs, so only three of four adjacent eight-pixel blocks blend.
test "OBMC uses at most three neighbours along a 32-pixel side" {
  let (above_state, above_info) = av1_obmc_test_state()
  for col in [0, 2, 4, 6] {
    av1_obmc_test_store(above_info, 3, col, 2, 1, 0, 0)
  }
  let above_block = av1_inter_block(4, 0, 8, 4, 0, true, false)
  above_block.motion_mode = 1
  assert_true(av1_obmc_blend(above_state, above_info, above_block, 0))
  assert_true(above_state.planes[0].pixels[16 * 32] < 200)
  for y in 16..<32 {
    for x in 24..<32 {
      assert_eq(above_state.planes[0].pixels[y * 32 + x], 200)
    }
  }
  let (left_state, left_info) = av1_obmc_test_state()
  for row in [0, 2, 4, 6] {
    av1_obmc_test_store(left_info, row, 3, 1, 2, 0, 0)
  }
  let left_block = av1_inter_block(0, 4, 4, 8, 0, false, true)
  left_block.motion_mode = 1
  assert_true(av1_obmc_blend(left_state, left_info, left_block, 0))
  assert_true(left_state.planes[0].pixels[16] < 200)
  for y in 24..<32 {
    for x in 16..<32 {
      assert_eq(left_state.planes[0].pixels[y * 32 + x], 200)
    }
  }
}

///|
/// The 32x8 luma block owns 16x4 chroma. Its width + height is 20, so above
/// OBMC applies the normative length-two mask: current weights [45, 64].
test "OBMC above contributes to 16x4 chroma" {
  let (state, info) = av1_obmc_test_state()
  av1_obmc_test_store(info, 3, 0, 8, 1, 0, 0)
  let block = av1_inter_block(4, 0, 8, 2, 0, true, false)
  block.motion_mode = 1
  assert_true(av1_obmc_blend(state, info, block, 1))
  for x in 0..<16 {
    let neighbour = 100 + x * 3 % 20
    assert_eq(
      state.planes[1].pixels[8 * 16 + x],
      (45 * 200 + 19 * neighbour + 32) >> 6,
    )
  }
  for y in 9..<12 {
    for x in 0..<16 {
      assert_eq(state.planes[1].pixels[y * 16 + x], 200)
    }
  }
}
