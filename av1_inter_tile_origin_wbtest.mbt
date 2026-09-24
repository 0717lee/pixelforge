///|
test "inter transform types record inside the tile's frame origin" {
  let info = av1_inter_regression_info(tile_row=4, tile_col=4)
  let state = av1_intra_state(16, 16, 100, 10, false, false, false, false)
  info.field.tx_types[0] = 10
  let decoder = av1_msac_new([0x00, 0x00, 0x00, 0x00], true)
  let kind = av1_inter_luma_tx_type(decoder, state, info, 8, 8, 0, 0)
  assert_true(kind is Av1TxIdentityIdentity)
  for row in 4..<6 {
    for col in 4..<6 {
      assert_eq(info.field.tx_types[row * info.field.cols + col], 9)
    }
  }
  assert_eq(info.field.tx_types[0], 10)
}

///|
test "inter chroma inherits the transform at its frame-relative origin" {
  let info = av1_inter_regression_info(tile_row=4, tile_col=4)
  let state = av1_intra_state(16, 16, 100, 10, false, false, false, false)
  let current = av1_inter_block(4, 4, 4, 4, 6, false, false)
  info.field.tx_types[4 * info.field.cols + 4] = 9
  info.field.tx_types[6 * info.field.cols + 6] = 10
  assert_true(
    av1_inter_chroma_tx_type(state, info, current, 4, 4, 0, 0)
    is Av1TxIdentityIdentity,
  )
  assert_true(
    av1_inter_chroma_tx_type(state, info, current, 4, 4, 4, 4)
    is Av1TxVerticalDct,
  )
}
