///|
/// The seven inter-intra geometries match dav1d's interintra_allowed_mask.
/// In particular, 4:1 rectangles code no flag before motion mode / transform
/// syntax, even though both dimensions individually lie in 8..32.
test "interintra 4:1 rectangles preserve the next entropy symbol" {
  for shape in [(8, 32), (32, 8)] {
    let (width, height) = shape
    let info = av1_inter_regression_info()
    let index = av1_intra_block_index(width, height).unwrap()
    let block = av1_inter_block(
      0,
      0,
      width / 4,
      height / 4,
      index,
      false,
      false,
    )
    block.ref_frame = av1_last_frame
    let data : Array[Byte] = [0xe3, 0x78, 0x2f, 0x51, 0x89, 0xa4]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    assert_true(av1_read_interintra_mode(decoder, info, block))
    assert_eq(block.interintra, 0)
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "interintra legal geometries retain their coded flag" {
  for
    shape in [
      (8, 8, 0),
      (8, 16, 0),
      (16, 8, 0),
      (16, 16, 1),
      (16, 32, 1),
      (32, 16, 1),
      (32, 32, 2),
    ] {
    let (width, height, context) = shape
    let info = av1_inter_regression_info()
    let index = av1_intra_block_index(width, height).unwrap()
    let block = av1_inter_block(
      0,
      0,
      width / 4,
      height / 4,
      index,
      false,
      false,
    )
    block.ref_frame = av1_last_frame
    let data : Array[Byte] = [0x00, 0x00, 0x00, 0x00]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    assert_eq(expected.symbol(info.cdfs.inter_intra[context].copy()), 0)
    assert_true(av1_read_interintra_mode(decoder, info, block))
    assert_eq(block.interintra, 0)
    av1_inter_regression_entropy(decoder, expected)
  }
}
