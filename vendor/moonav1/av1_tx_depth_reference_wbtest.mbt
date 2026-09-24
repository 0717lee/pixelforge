/// Intra tx_depth syntax probes. Payloads were generated with the existing
/// scripts/craft_av1_fixture.py MsacEncoder and the reference tables in
/// _refs/go-av1/cdf/tables_txsize_gen.go. These are isolated entropy symbols,
/// not complete AV1 tile or frame fixtures.

///|
test "intra tx depth default CDFs include all four geometry categories" {
  let state = av1_tx_depth_state()
  assert_eq(state.cdf8, [
    [19968, 32768, 0],
    [19968, 32768, 0],
    [24320, 32768, 0],
  ])
  assert_eq(state.cdf16, [
    [12272, 30172, 32768, 0],
    [12272, 30172, 32768, 0],
    [18677, 30848, 32768, 0],
  ])
  assert_eq(state.cdf32, [
    [12986, 15180, 32768, 0],
    [12986, 15180, 32768, 0],
    [24302, 25602, 32768, 0],
  ])
  assert_eq(state.cdf64, [
    [5782, 11475, 32768, 0],
    [5782, 11475, 32768, 0],
    [16803, 22759, 32768, 0],
  ])
}

///|
test "intra tx depth categories match Max_Tx_Depth for every coding block" {
  // The complete 22-entry block table, in the reference block-enum order.
  for
    case in [
      (4, 4, 0),
      (4, 8, 1),
      (8, 4, 1),
      (8, 8, 1),
      (8, 16, 2),
      (16, 8, 2),
      (16, 16, 2),
      (16, 32, 3),
      (32, 16, 3),
      (32, 32, 3),
      (32, 64, 4),
      (64, 32, 4),
      (64, 64, 4),
      (64, 128, 4),
      (128, 64, 4),
      (128, 128, 4),
      (4, 16, 2),
      (16, 4, 2),
      (8, 32, 3),
      (32, 8, 3),
      (16, 64, 4),
      (64, 16, 4),
    ] {
    let (width, height, category) = case
    assert_eq(av1_tx_depth_category(width, height), Some(category))
  }
}

///|
test "intra tx depth reference symbols include 8x8 split and 16x16 depth two" {
  let cases : Array[(Int, Int, Byte)] = [
    (8, 0, b'\x40'),
    (8, 1, b'\xa0'),
    (16, 0, b'\x20'),
    (16, 1, b'\xc0'),
    (16, 2, b'\xf8'),
    (32, 0, b'\x20'),
    (32, 1, b'\x68'),
    (32, 2, b'\xc0'),
    (64, 0, b'\x10'),
    (64, 1, b'\x30'),
    (64, 2, b'\xc0'),
  ]
  for case in cases {
    let (side, expected, payload) = case
    let decoder = av1_msac_new([payload], true)
    let before = (
      decoder.symbol_value,
      decoder.symbol_range,
      decoder.symbol_max_bits,
    )
    assert_eq(
      av1_decode_tx_depth_with_state(decoder, av1_tx_depth_state(), side, 0),
      Some(expected),
    )
    assert_false(
      (decoder.symbol_value, decoder.symbol_range, decoder.symbol_max_bits) ==
      before,
    )
  }
  let decoder = av1_msac_new([b'\xff'], true)
  let before = (
    decoder.bit_pos,
    decoder.symbol_value,
    decoder.symbol_range,
    decoder.symbol_max_bits,
  )
  assert_eq(
    av1_decode_tx_depth_for_block(decoder, av1_tx_depth_state(), 4, 4, 0),
    Some(0),
  )
  assert_eq(
    (
      decoder.bit_pos,
      decoder.symbol_value,
      decoder.symbol_range,
      decoder.symbol_max_bits,
    ),
    before,
  )
}

///|
test "intra tx depth CDF state adapts across differently shaped blocks" {
  // TX8/ctx0: depth1, depth0; TX16/ctx0: depth2, depth1.
  let decoder = av1_msac_new([b'\xd3'], true)
  let state = av1_tx_depth_state()
  assert_eq(av1_decode_tx_depth_for_block(decoder, state, 8, 8, 0), Some(1))
  assert_eq(av1_decode_tx_depth_for_block(decoder, state, 4, 8, 0), Some(0))
  assert_eq(av1_decode_tx_depth_for_block(decoder, state, 16, 16, 0), Some(2))
  assert_eq(av1_decode_tx_depth_for_block(decoder, state, 4, 16, 0), Some(1))
  assert_eq(state.cdf8[0], [19598, 32768, 2])
  assert_eq(state.cdf16[0], [10786, 28567, 32768, 2])
  assert_eq(state.cdf8[1], [19968, 32768, 0])
  assert_eq(state.cdf16[1], [12272, 30172, 32768, 0])
  assert_eq(av1_tx_depth_state().cdf8[0], [19968, 32768, 0])
}

///|
test "intra tx depth context two uses its own adaptive row" {
  let state = av1_tx_depth_state()
  assert_eq(
    av1_decode_tx_depth_for_block(
      av1_msac_new([b'\xf4'], true),
      state,
      8,
      16,
      2,
    ),
    Some(2),
  )
  assert_eq(state.cdf16[2][3], 1)
  assert_eq(state.cdf16[0][3], 0)
  assert_eq(
    av1_decode_tx_depth_for_block(
      av1_msac_new([b'\xe0'], true),
      state,
      16,
      64,
      2,
    ),
    Some(2),
  )
  assert_eq(state.cdf64[2][3], 1)
  assert_eq(state.cdf64[0][3], 0)
  let frozen = av1_tx_depth_state()
  assert_eq(
    av1_decode_tx_depth_for_block(
      av1_msac_new([b'\xa0'], false),
      frozen,
      8,
      8,
      0,
    ),
    Some(1),
  )
  assert_eq(frozen.cdf8[0], [19968, 32768, 0])
}

///|
test "intra selected transform dimensions follow rectangular Split_Tx_Size" {
  for
    case in [
      (4, 16, 1, 4, 8),
      (4, 16, 2, 4, 4),
      (16, 4, 1, 8, 4),
      (16, 4, 2, 4, 4),
      (8, 16, 1, 8, 8),
      (8, 16, 2, 4, 4),
      (32, 8, 1, 16, 8),
      (32, 8, 2, 8, 8),
      (8, 32, 1, 8, 16),
      (8, 32, 2, 8, 8),
      (16, 64, 1, 16, 32),
      (16, 64, 2, 16, 16),
      (64, 16, 1, 32, 16),
      (64, 16, 2, 16, 16),
      (128, 64, 0, 64, 64),
      (64, 128, 1, 32, 32),
      (128, 128, 2, 16, 16),
    ] {
    let (width, height, depth, tx_width, tx_height) = case
    assert_eq(
      av1_tx_size_from_depth(width, height, depth),
      Some((tx_width, tx_height)),
    )
  }
}

///|
test "intra tx depth two fills a 16x16 block with raster ordered 4x4 leaves" {
  let state = av1_tx_depth_state()
  let leaves = av1_decode_tx_tree_with_state(
    av1_msac_new([b'\xf8'], true),
    state,
    { row: 8, col: 12, width: 16, height: 16, },
    0,
  ).unwrap()
  assert_eq(leaves.length(), 16)
  for i in 0..<16 {
    let leaf = leaves[i]
    assert_eq((leaf.node.row, leaf.node.col), (8 + i / 4 * 4, 12 + i % 4 * 4))
    assert_eq((leaf.node.width, leaf.node.height, leaf.depth), (4, 4, 2))
  }
  assert_eq(state.cdf16[0][3], 1)
}

///|
test "intra rectangular tree decoding tiles the selected long-axis split" {
  for case in [(32, 8, 16, 8), (8, 32, 8, 16)] {
    let (width, height, tx_width, tx_height) = case
    let leaves = av1_decode_tx_tree_with_state(
      av1_msac_new([b'\x68'], true),
      av1_tx_depth_state(),
      { row: 0, col: 0, width, height, },
      0,
    ).unwrap()
    assert_eq(leaves.length(), 2)
    for leaf in leaves {
      assert_eq(
        (leaf.node.width, leaf.node.height, leaf.depth),
        (tx_width, tx_height, 1),
      )
    }
    assert_eq(
      (leaves[1].node.row, leaves[1].node.col),
      if width > height {
        (0, 16)
      } else {
        (16, 0)
      },
    )
  }
  let leaves = av1_decode_tx_tree_with_state(
    av1_msac_new([b'\x10'], true),
    av1_tx_depth_state(),
    { row: 0, col: 0, width: 128, height: 64, },
    0,
  ).unwrap()
  assert_eq(leaves.length(), 2)
  assert_eq(
    (
      leaves[1].node.row,
      leaves[1].node.col,
      leaves[1].node.width,
      leaves[1].node.height,
    ),
    (0, 64, 64, 64),
  )
}

///|
test "intra tx depth neighbor lookup samples one MI point instead of edge maximum" {
  let above = av1_tx_traversal_state(64, 64)
  av1_tx_traversal_record(above, { row: 0, col: 0, width: 4, height: 8, })
  av1_tx_traversal_record(above, { row: 0, col: 4, width: 32, height: 8, })
  assert_eq(
    av1_tx_depth_context_for_node(above, {
      row: 8,
      col: 0,
      width: 32,
      height: 32,
    }),
    0,
  )
  let left = av1_tx_traversal_state(64, 64)
  av1_tx_traversal_record(left, { row: 0, col: 0, width: 8, height: 4, })
  av1_tx_traversal_record(left, { row: 4, col: 0, width: 8, height: 32, })
  assert_eq(
    av1_tx_depth_context_for_node(left, {
      row: 0,
      col: 8,
      width: 32,
      height: 32,
    }),
    0,
  )
}

///|
test "intra tx traversal records selected dimensions over the entire coding block" {
  let state = av1_tx_traversal_state(64, 64)
  av1_tx_traversal_record_size(
    state,
    { row: 0, col: 0, width: 32, height: 32, },
    8,
    8,
  )
  for i in 0..<8 {
    assert_eq(state.above_width[i], 8)
    assert_eq(state.left_height[i], 8)
  }
  assert_eq(state.above_width[8], -1)
  assert_eq(state.left_height[8], -1)
  assert_eq(
    av1_tx_depth_context_for_node(state, {
      row: 32,
      col: 28,
      width: 8,
      height: 8,
    }),
    1,
  )
  assert_eq(
    av1_tx_depth_context_for_node(state, {
      row: 28,
      col: 32,
      width: 8,
      height: 8,
    }),
    1,
  )
  let large = av1_tx_traversal_state(256, 256)
  av1_tx_traversal_record(large, { row: 0, col: 64, width: 64, height: 64, })
  av1_tx_traversal_record(large, { row: 64, col: 0, width: 64, height: 64, })
  assert_eq(
    av1_tx_depth_context_for_node(large, {
      row: 64,
      col: 64,
      width: 128,
      height: 128,
    }),
    2,
  )
}

///|
test "intra tx depth malformed geometry depth and context fail before symbol consumption" {
  let decoder = av1_msac_new([b'\xff', b'\xff'], true)
  let state = av1_tx_depth_state()
  let before = (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range)
  for size in [(0, 8), (6, 8), (12, 12), (4, 32), (32, 128), (256, 256)] {
    let (width, height) = size
    assert_true(
      av1_decode_tx_depth_for_block(decoder, state, width, height, 0) is None,
    )
    assert_true(av1_tx_size_from_depth(width, height, 0) is None)
  }
  for context in [-1, 3] {
    assert_true(
      av1_decode_tx_depth_for_block(decoder, state, 16, 16, context) is None,
    )
  }
  for depth in [-1, 3] {
    assert_true(av1_tx_size_from_depth(64, 64, depth) is None)
  }
  assert_true(av1_tx_size_from_depth(4, 4, 1) is None)
  assert_true(av1_tx_size_from_depth(4, 8, 2) is None)
  assert_eq(
    (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range),
    before,
  )
  assert_eq(state.cdf16[0][3], 0)
  let leaves : Array[Av1TxLeaf] = []
  assert_false(
    av1_tx_depth_leaves(
      { row: 1, col: 0, width: 16, height: 16, },
      0,
      0,
      leaves,
    ),
  )
  assert_false(
    av1_tx_depth_leaves(
      { row: 0, col: 0, width: 16, height: 16, },
      3,
      0,
      leaves,
    ),
  )
  assert_eq(leaves.length(), 0)
}
