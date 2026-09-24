///|
test "intra blocks in an inter frame publish NONE second reference and geometry" {
  let state = av1_intra_state(32, 32, 0, 8, false, false, false, false)
  let info = av1_inter_regression_info()
  let current = av1_inter_block(2, 2, 2, 2, 3, true, true)
  current.skip = 1
  let block : Av1SbBlock = { row: 8, col: 8, width: 8, height: 8, }
  let decoder = av1_msac_new([0, 0, 0, 0, 0, 0, 0, 0], true)
  assert_true(
    av1_intra_in_inter_block(decoder, state, info, current, block, 3, true),
  )
  for row in 2..<4 {
    for col in 2..<4 {
      let unit = row * info.field.cols + col
      assert_true(info.field.written[unit])
      assert_false(info.field.is_inter[unit])
      assert_eq(info.field.refs[unit * 2], av1_intra_frame)
      assert_eq(info.field.refs[unit * 2 + 1], av1_none_frame)
      assert_eq(info.field.skips[unit], 1)
      assert_eq((info.field.width4[unit], info.field.height4[unit]), (2, 2))
      assert_eq((info.field.tx_width[unit], info.field.tx_height[unit]), (4, 4))
    }
  }
  let following = av1_inter_block(4, 2, 2, 2, 3, true, false)
  assert_eq(av1_comp_mode_ctx(info, following), 0)
}

///|
test "masked compound context saturates two ALTREF neighbours to row five" {
  let info = av1_inter_regression_info()
  for position in [(1, 2), (2, 1)] {
    av1_motion_field_store(
      info.field,
      position.0,
      position.1,
      1,
      1,
      av1_mode_nearest_mv,
      [av1_alt_ref_frame, av1_none_frame],
      [0, 0],
      [0, 0],
    )
  }
  let block = av1_inter_block(2, 2, 2, 2, 3, true, true)
  block.ref_frame = av1_last_frame
  block.ref_frame1 = av1_alt_ref_frame
  assert_eq(av1_comp_group_idx_ctx(info, block), 5)
  let decoder = av1_msac_new([0, 0, 0, 0, 0, 0, 0, 0], true)
  assert_true(av1_read_compound_type(decoder, info, block))
  assert_eq(info.cdfs.comp_group_idx[5][2], 1)
}

///|
test "large rectangular chroma inherits only DCT or identity from inter set three" {
  for code in 0..<16 {
    assert_eq(
      av1_inter_tx_type_in_set(3, av1_tx_type_of_code(code)),
      code == 0 || code == 9,
    )
  }
  let state = av1_intra_state(64, 64, 128, 10, false, false, false, true)
  let info = av1_inter_regression_info()
  let current = av1_inter_block(0, 0, 16, 4, 21, false, false)
  info.field.tx_types[0] = av1_tx_type_code(Av1TxVerticalDct)
  assert_true(
    av1_inter_chroma_tx_type(state, info, current, 32, 8, 0, 0) is Av1TxDctDct,
  )
  info.field.tx_types[0] = av1_tx_type_code(Av1TxIdentityIdentity)
  assert_true(
    av1_inter_chroma_tx_type(state, info, current, 32, 8, 0, 0)
    is Av1TxIdentityIdentity,
  )
}
