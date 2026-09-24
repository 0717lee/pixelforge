/// Golden availability flags below were checked by compiling the unchanged
/// libaom has_top_right/has_bottom_left functions and their packed tables at
/// 8e7b6a567df174d795479b92b4ac766d271add73. These cases deliberately disagree
/// with plain raster availability, SB64-stride indexing or unscaled UV sizes.

///|
fn av1_edge_test_counts(
  block : Av1SbBlock,
  tx : Av1TxNode,
  partition : Av1SbPartition,
  plane : Int,
  sb_size : Int,
) -> Av1IntraEdgeCounts {
  av1_intra_edge_counts(
    { row: 0, col: 0, width: 256, height: 256, },
    256,
    256,
    block,
    partition,
    tx,
    plane,
    sb_size,
  ).unwrap()
}

///|
test "directional extensions distinguish SPLIT from mixed vertical partition order" {
  let bottom_left : Av1SbBlock = { row: 8, col: 64, width: 8, height: 8, }
  let bl_tx : Av1TxNode = { row: 8, col: 64, width: 8, height: 8, }
  assert_eq(
    av1_edge_test_counts(bottom_left, bl_tx, Av1SbPartitionSplit, 0, 64).n_topright,
    8,
  )
  assert_eq(
    av1_edge_test_counts(bottom_left, bl_tx, Av1SbPartitionVertA, 0, 64).n_topright,
    0,
  )
  let top_right : Av1SbBlock = { row: 64, col: 8, width: 8, height: 8, }
  let tr_tx : Av1TxNode = { row: 64, col: 8, width: 8, height: 8, }
  assert_eq(
    av1_edge_test_counts(top_right, tr_tx, Av1SbPartitionSplit, 0, 64).n_bottomleft,
    0,
  )
  assert_eq(
    av1_edge_test_counts(top_right, tr_tx, Av1SbPartitionVertB, 0, 64).n_bottomleft,
    8,
  )
}

///|
test "directional SB64 uses the fixed SB128 table stride and TX interior rules" {
  let counts = av1_edge_test_counts(
    { row: 8, col: 8, width: 8, height: 8, },
    { row: 8, col: 8, width: 8, height: 8, },
    Av1SbPartitionSplit,
    0,
    64,
  )
  // A mistaken stride of eight 8x8 blocks selects bit9=1; the normative
  // stride of sixteen selects bit17=0.
  assert_eq(
    (counts.n_top, counts.n_left, counts.n_topright, counts.n_bottomleft),
    (8, 8, 0, 0),
  )
  let block : Av1SbBlock = { row: 16, col: 16, width: 16, height: 16, }
  let left = av1_edge_test_counts(
    block,
    { row: 24, col: 16, width: 8, height: 8, },
    Av1SbPartitionNone,
    0,
    64,
  )
  let right = av1_edge_test_counts(
    block,
    { row: 24, col: 24, width: 8, height: 8, },
    Av1SbPartitionNone,
    0,
    64,
  )
  assert_eq((left.n_topright, left.n_bottomleft), (8, 0))
  assert_eq((right.n_topright, right.n_bottomleft), (0, 0))
}

///|
test "directional 128-axis blocks honor 64-chunk order and the center exception" {
  let block : Av1SbBlock = { row: 0, col: 0, width: 128, height: 128, }
  let top = av1_edge_test_counts(
    block,
    { row: 0, col: 64, width: 32, height: 32, },
    Av1SbPartitionNone,
    0,
    128,
  )
  let bottom = av1_edge_test_counts(
    block,
    { row: 32, col: 64, width: 32, height: 32, },
    Av1SbPartitionNone,
    0,
    128,
  )
  assert_eq(top.n_bottomleft, 32)
  assert_eq(bottom.n_bottomleft, 0)
  let interior = av1_edge_test_counts(
    block,
    { row: 32, col: 32, width: 32, height: 32, },
    Av1SbPartitionNone,
    0,
    128,
  )
  assert_eq(interior.n_topright, 0)
  let center = av1_edge_test_counts(
    block,
    { row: 64, col: 0, width: 64, height: 64, },
    Av1SbPartitionNone,
    0,
    128,
  )
  assert_eq(center.n_topright, 64)
  let uv_center = av1_edge_test_counts(
    block,
    { row: 32, col: 0, width: 32, height: 32, },
    Av1SbPartitionNone,
    1,
    128,
  )
  assert_eq(uv_center.n_topright, 32)
}

///|
test "directional edge counts obey tile gates and coded MI clipping" {
  // The top-right superblock was decoded, but it is in another tile.
  let tile : Av1SbBlock = { row: 0, col: 0, width: 64, height: 128, }
  let edge = av1_intra_edge_counts(
    tile,
    256,
    256,
    { row: 64, col: 56, width: 8, height: 8, },
    Av1SbPartitionNone,
    { row: 64, col: 56, width: 8, height: 8, },
    0,
    64,
  ).unwrap()
  assert_eq((edge.n_top, edge.n_topright), (8, 0))
  // A complete TX can extend beyond the coded plane, while its reference
  // count remains the number of real samples before edge replication.
  let partial = av1_intra_edge_counts(
    { row: 0, col: 0, width: 24, height: 24, },
    24,
    24,
    { row: 0, col: 0, width: 32, height: 32, },
    Av1SbPartitionNone,
    { row: 16, col: 16, width: 16, height: 16, },
    0,
    64,
  ).unwrap()
  assert_eq(
    (partial.n_top, partial.n_left, partial.n_topright, partial.n_bottomleft),
    (8, 8, 0, 0),
  )
  // A visible 9x9 image has a 16x16 MI rectangle: these are eight samples.
  let padded = av1_intra_edge_counts(
    { row: 0, col: 0, width: 16, height: 16, },
    16,
    16,
    { row: 8, col: 8, width: 8, height: 8, },
    Av1SbPartitionNone,
    { row: 8, col: 8, width: 8, height: 8, },
    0,
    64,
  ).unwrap()
  assert_eq((padded.n_top, padded.n_left), (8, 8))
}

///|
test "directional chroma uses scaled block tables and original owner MI" {
  // Each case has a different flag if the original four-axis bsize table
  // is used instead of the normative expanded chroma table.
  for
    example in [
      (4, 4, 12, 20, 4, 4, 4, 0),
      (4, 8, 8, 36, 4, 4, 4, 4),
      (8, 4, 12, 16, 4, 4, 4, 0),
      (4, 16, 32, 36, 4, 8, 4, 8),
      (16, 4, 20, 32, 8, 4, 8, 4),
    ] {
    let (bw, bh, row, col, tw, th, tr, bl) = example
    let counts = av1_edge_test_counts(
      { row, col, width: bw, height: bh, },
      { row: row / 8 * 4, col: col / 8 * 4, width: tw, height: th, },
      Av1SbPartitionNone,
      1,
      64,
    )
    assert_eq((counts.n_topright, counts.n_bottomleft), (tr, bl))
  }
  let tile : Av1SbBlock = { row: 64, col: 64, width: 64, height: 64, }
  let owner : Av1SbBlock = { row: 68, col: 68, width: 4, height: 4, }
  let counts = av1_intra_edge_counts(
    tile,
    128,
    128,
    owner,
    Av1SbPartitionNone,
    { row: 32, col: 32, width: 4, height: 4, },
    1,
    64,
  ).unwrap()
  assert_eq((counts.n_top, counts.n_left), (0, 0))
  assert_eq(
    av1_intra_edge_neighbor_indices(tile, owner, 0),
    Some((Some(1), Some(16))),
  )
  assert_eq(av1_intra_edge_neighbor_indices(tile, owner, 1), Some((None, None)))
  assert_true(
    av1_intra_edge_counts(
      tile,
      128,
      128,
      { row: 64, col: 64, width: 4, height: 4, },
      Av1SbPartitionNone,
      { row: 32, col: 32, width: 4, height: 4, },
      1,
      64,
    )
    is None,
  )
}

///|
test "directional smooth context uses plane-specific neighboring coding blocks" {
  let tile : Av1SbBlock = { row: 64, col: 64, width: 64, height: 64, }
  let block : Av1SbBlock = { row: 76, col: 76, width: 4, height: 4, }
  assert_eq(
    av1_intra_edge_neighbor_indices(tile, block, 0),
    Some((Some(35), Some(50))),
  )
  assert_eq(
    av1_intra_edge_neighbor_indices(tile, block, 1),
    Some((Some(19), Some(49))),
  )
  let y_modes = Array::make(256, AV1_INTRA_DC)
  let uv_modes = Array::make(256, AV1_INTRA_DC)
  y_modes[35] = AV1_INTRA_SMOOTH
  assert_eq(
    av1_intra_edge_neighbor_smooth(tile, block, 0, y_modes, uv_modes),
    Some(true),
  )
  assert_eq(
    av1_intra_edge_neighbor_smooth(tile, block, 1, y_modes, uv_modes),
    Some(false),
  )
  y_modes[35] = AV1_INTRA_DC
  uv_modes[19] = AV1_INTRA_SMOOTH_V
  assert_eq(
    av1_intra_edge_neighbor_smooth(tile, block, 0, y_modes, uv_modes),
    Some(false),
  )
  assert_eq(
    av1_intra_edge_neighbor_smooth(tile, block, 1, y_modes, uv_modes),
    Some(true),
  )
  let inter = Array::make(256, false)
  inter[19] = true
  assert_eq(
    av1_intra_edge_neighbor_smooth(
      tile,
      block,
      1,
      y_modes,
      uv_modes,
      inter=Some(inter),
    ),
    Some(false),
  )
  uv_modes[49] = AV1_INTRA_SMOOTH_H
  assert_eq(
    av1_intra_edge_neighbor_smooth(
      tile,
      block,
      1,
      y_modes,
      uv_modes,
      inter=Some(inter),
    ),
    Some(true),
  )
  // No external coding-block neighbours exist at this tile corner, even if
  // an earlier TX inside the current coding block already used SMOOTH.
  assert_eq(
    av1_intra_edge_neighbor_smooth(
      { row: 0, col: 0, width: 16, height: 16, },
      { row: 0, col: 0, width: 16, height: 16, },
      0,
      Array::make(16, AV1_INTRA_SMOOTH),
      Array::make(16, AV1_INTRA_SMOOTH),
    ),
    Some(false),
  )
}
