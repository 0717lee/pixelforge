/// Variable-transform syntax probes. Payloads below were synthesized with
/// scripts/craft_av1_fixture.py's od_ec MsacEncoder and explicit normative
/// context/symbol sequences. They are not complete AV1 tile fixtures.

///|
fn av1_vartx_test_neighbors(block : Av1TxNode) -> Av1VarTxNeighbors {
  av1_vartx_neighbors(
    block,
    Array::make(block.width / 4, 64),
    Array::make(block.height / 4, 64),
  ).unwrap()
}

///|
test "vartx all 21 context rows use size square-up and smaller neighbours" {
  let cdfs = av1_vartx_cdf_state()
  let defaults = [
    28581, 23846, 20847, 24315, 18196, 12133, 18791, 10887, 11005, 27179, 20004,
    11281, 26549, 19308, 14224, 28015, 21546, 14400, 28165, 22401, 16088,
  ]
  for
    sizes in [
      (64, 64, 0),
      (64, 32, 3),
      (32, 32, 6),
      (32, 16, 9),
      (16, 16, 12),
      (16, 8, 15),
      (8, 8, 18),
    ] {
    let (block_size, tx_size, base) = sizes
    let block : Av1TxNode = {
      row: 8,
      col: 12,
      width: block_size,
      height: block_size,
    }
    let node : Av1TxNode = { row: 8, col: 12, width: tx_size, height: tx_size, }
    for edges in [(64, 64, 0), (4, 64, 1), (64, 4, 1), (4, 4, 2)] {
      let (above, left, offset) = edges
      let neighbors = av1_vartx_neighbors(
        block,
        Array::make(block_size / 4, above),
        Array::make(block_size / 4, left),
      ).unwrap()
      let context = av1_txfm_split_context(neighbors, node).unwrap()
      assert_eq(context, base + offset)
      assert_eq(cdfs.rows[context], [defaults[context], 32768, 0])
    }
  }
}

///|
test "vartx rectangle orientation does not add a context class" {
  for size in [(32, 16), (16, 32), (32, 8), (8, 32)] {
    let (width, height) = size
    let block : Av1TxNode = { row: 0, col: 0, width, height, }
    assert_eq(
      av1_txfm_split_context(av1_vartx_test_neighbors(block), block),
      Some(6),
    )
  }
  // A 128-pixel coding block still uses the 64-pixel maximum square class.
  let block : Av1TxNode = { row: 0, col: 0, width: 128, height: 128, }
  let neighbors = av1_vartx_test_neighbors(block)
  assert_eq(
    av1_txfm_split_context(neighbors, { row: 0, col: 0, width: 64, height: 64, }),
    Some(0),
  )
}

///|
test "vartx leaf recording supplies exact top-left sibling dimensions" {
  let block : Av1TxNode = { row: 8, col: 12, width: 32, height: 32, }
  let neighbors = av1_vartx_test_neighbors(block)
  let tr : Av1TxNode = { row: 8, col: 28, width: 16, height: 16, }
  let bl : Av1TxNode = { row: 24, col: 12, width: 16, height: 16, }
  let br : Av1TxNode = { row: 24, col: 28, width: 16, height: 16, }
  assert_true(av1_txfm_split_context(neighbors, tr) is None)
  for offset in [(0, 0), (0, 8), (8, 0), (8, 8)] {
    let (dy, dx) = offset
    assert_true(
      av1_vartx_record(neighbors, {
        row: 8 + dy,
        col: 12 + dx,
        width: 8,
        height: 8,
      }),
    )
  }
  assert_eq(neighbors.tx_width[3 * neighbors.cols + 3], 8)
  assert_eq(neighbors.tx_height[3 * neighbors.cols + 3], 8)
  assert_eq(av1_txfm_split_context(neighbors, tr), Some(10))
  assert_eq(av1_txfm_split_context(neighbors, bl), Some(10))
  assert_true(av1_vartx_record(neighbors, tr))
  assert_true(av1_vartx_record(neighbors, bl))
  assert_eq(av1_txfm_split_context(neighbors, br), Some(9))
}

///|
test "vartx edge lookup uses the current position and resolved skipped dimensions" {
  let block : Av1TxNode = { row: 8, col: 8, width: 32, height: 32, }
  let above = [8, 64, 64, 64, 32, 4, 4, 4]
  let left = Array::make(8, 128)
  let neighbors = av1_vartx_neighbors(block, above, left).unwrap()
  // The skipped inter left neighbour's coding-block height is 128; only the
  // top-left above width (8), rather than the maximum across this edge, counts.
  assert_eq(av1_txfm_split_context(neighbors, block), Some(7))
  above[0] = 64
  left[0] = 4
  assert_eq(av1_txfm_split_context(neighbors, block), Some(7))
  assert_true(
    av1_vartx_record(neighbors, { row: 8, col: 8, width: 16, height: 16, }),
  )
  assert_eq(
    av1_txfm_split_context(neighbors, {
      row: 8,
      col: 24,
      width: 16,
      height: 16,
    }),
    Some(9),
  )
}

///|
test "vartx entropy walk records leaves before sibling CDF selection" {
  // (ctx,symbol): (6,1), (9,1), (10,0), (10,0), (9,0).
  // The four depth-2 8x8 leaves consume no split symbols.
  let block : Av1TxNode = { row: 0, col: 0, width: 32, height: 32, }
  let cdfs = av1_vartx_cdf_state()
  let neighbors = av1_vartx_test_neighbors(block)
  let leaves = av1_decode_tx_partition_tree_with_decoder(
    av1_msac_new([b'\xee'], true),
    cdfs,
    neighbors,
    block,
    2,
  ).unwrap()
  assert_eq(leaves.length(), 7)
  let expected = [
    (0, 0, 8, 2),
    (0, 8, 8, 2),
    (8, 0, 8, 2),
    (8, 8, 8, 2),
    (0, 16, 16, 1),
    (16, 0, 16, 1),
    (16, 16, 16, 1),
  ]
  for i in 0..<leaves.length() {
    let leaf = leaves[i]
    assert_eq(
      (leaf.node.row, leaf.node.col, leaf.node.width, leaf.depth),
      expected[i],
    )
    assert_eq(leaf.node.height, leaf.node.width)
  }
  assert_eq(cdfs.rows[6], [17617, 32768, 1])
  assert_eq(cdfs.rows[9], [25936, 32768, 2])
  assert_eq(cdfs.rows[10], [21548, 32768, 2])
  assert_eq(cdfs.rows[11], [11281, 32768, 0])
  assert_eq(neighbors.tx_width[0], 8)
  assert_eq(neighbors.tx_width[7 * neighbors.cols + 7], 16)
}

///|
test "vartx repeated split CDF stays adaptive and can be disabled" {
  // (ctx,symbol): (0,1), then (3,0) four times.
  let block : Av1TxNode = { row: 0, col: 0, width: 64, height: 64, }
  for adaptive in [true, false] {
    let cdfs = av1_vartx_cdf_state()
    let leaves = av1_decode_tx_partition_tree_with_decoder(
      av1_msac_new([b'\xe4'], adaptive),
      cdfs,
      av1_vartx_test_neighbors(block),
      block,
      2,
    ).unwrap()
    assert_eq(leaves.length(), 4)
    for leaf in leaves {
      assert_eq((leaf.node.width, leaf.node.height, leaf.depth), (32, 32, 1))
    }
    assert_eq(
      cdfs.rows[0],
      if adaptive {
        [26795, 32768, 1]
      } else {
        [28581, 32768, 0]
      },
    )
    assert_eq(
      cdfs.rows[3],
      if adaptive {
        [26237, 32768, 4]
      } else {
        [24315, 32768, 0]
      },
    )
  }
}

///|
test "vartx CDF state survives separate roots and coding blocks" {
  let cdfs = av1_vartx_cdf_state()
  let block : Av1TxNode = { row: 0, col: 0, width: 128, height: 64, }
  let neighbors = av1_vartx_test_neighbors(block)
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  for col in [0, 64] {
    let root : Av1TxNode = { row: 0, col, width: 64, height: 64, }
    let leaves = av1_decode_tx_partition_tree_with_decoder(
      decoder, cdfs, neighbors, root, 2,
    ).unwrap()
    assert_eq(leaves.length(), 1)
  }
  assert_eq(cdfs.rows[0][2], 2)
  let next : Av1TxNode = { row: 64, col: 0, width: 64, height: 64, }
  let leaves = av1_decode_tx_partition_tree_with_decoder(
    decoder,
    cdfs,
    av1_vartx_test_neighbors(next),
    next,
    2,
  ).unwrap()
  assert_eq(leaves.length(), 1)
  assert_eq(cdfs.rows[0][2], 3)
  assert_eq(av1_vartx_cdf_state().rows[0], [28581, 32768, 0])
}

///|
test "vartx rectangular entropy splits follow Split_Tx_Size" {
  // (ctx,symbol): (12,1), (15,1), (15,0), with 4x4 implied leaves.
  for size in [(4, 16), (16, 4)] {
    let (width, height) = size
    let root : Av1TxNode = { row: 12, col: 8, width, height, }
    let leaves = av1_decode_tx_partition_tree_payload([b'\xfa'], root, 2).unwrap()
    assert_eq(leaves.length(), 3)
    for i in 0..<2 {
      assert_eq(
        (leaves[i].node.width, leaves[i].node.height, leaves[i].depth),
        (4, 4, 2),
      )
    }
    assert_eq(
      (leaves[2].node.width, leaves[2].node.height),
      if width > height {
        (8, 4)
      } else {
        (4, 8)
      },
    )
    assert_eq(
      (leaves[1].node.row, leaves[1].node.col),
      if width > height {
        (12, 12)
      } else {
        (16, 8)
      },
    )
    assert_eq(
      (leaves[2].node.row, leaves[2].node.col),
      if width > height {
        (12, 16)
      } else {
        (20, 8)
      },
    )
  }
}

///|
test "vartx depth limits and 4x4 leaves do not read split symbols" {
  for case in [(4, 2), (32, 0)] {
    let (size, depth) = case
    let block : Av1TxNode = { row: 0, col: 0, width: size, height: size, }
    let neighbors = av1_vartx_test_neighbors(block)
    let cdfs = av1_vartx_cdf_state()
    let decoder = av1_msac_new([b'\xff', b'\xff'], true)
    let before = (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range)
    let leaves = av1_decode_tx_partition_tree_with_decoder(
      decoder, cdfs, neighbors, block, depth,
    ).unwrap()
    assert_eq(leaves.length(), 1)
    assert_eq(leaves[0].depth, 0)
    assert_eq(
      (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range),
      before,
    )
    assert_eq(neighbors.tx_width[0], size)
    for row in cdfs.rows {
      assert_eq(row[2], 0)
    }
  }
}

///|
test "vartx rejects truncated entropy beyond the allowed padding budget" {
  // (ctx,symbol): (0,1), (3,1), (4,1), (4,1), (5,1).
  // Removing 0x80 still produces split decisions from implicit zero bits,
  // but SymbolMaxBits reaches -15, beyond the normative -14 limit.
  let root : Av1TxNode = { row: 0, col: 0, width: 64, height: 64, }
  let leaves = av1_decode_tx_partition_tree_payload([b'\xff', b'\x80'], root, 2).unwrap()
  assert_eq(leaves.length(), 16)
  for leaf in leaves {
    assert_eq((leaf.node.width, leaf.node.height, leaf.depth), (16, 16, 2))
  }
  assert_true(av1_decode_tx_partition_tree_payload([b'\xff'], root, 2) is None)
  // A one-byte entropy payload is valid when its padding stays in budget.
  assert_eq(
    av1_decode_tx_partition_tree_payload([b'\xe4'], root, 2).unwrap().length(),
    4,
  )
}

///|
test "vartx malformed geometry and state fail before entropy consumption" {
  let root : Av1TxNode = { row: 0, col: 0, width: 32, height: 32, }
  for size in [(0, 8), (6, 8), (12, 12), (4, 32), (64, 4), (128, 128)] {
    let (width, height) = size
    assert_true(
      av1_decode_tx_partition_tree_payload(
        [b'\x00'],
        { row: 0, col: 0, width, height, },
        0,
      )
      is None,
    )
  }
  for
    position in [
      (-4, 0),
      (0, -4),
      (1, 0),
      (0, 2),
      (2147483644, 0),
      (0, 2147483644),
    ] {
    let (row, col) = position
    assert_true(
      av1_decode_tx_partition_tree_payload(
        [b'\x00'],
        { row, col, width: 8, height: 8, },
        0,
      )
      is None,
    )
  }
  assert_true(av1_decode_tx_partition_tree_payload([], root, 2) is None)
  for depth in [-1, 3] {
    assert_true(
      av1_decode_tx_partition_tree_payload([b'\x00'], root, depth) is None,
    )
  }
  assert_true(av1_vartx_neighbors(root, [], Array::make(8, 64)) is None)
  for edge_size in [-1, 0, 3, 6, 256] {
    assert_true(
      av1_vartx_neighbors(root, Array::make(8, edge_size), Array::make(8, 64))
      is None,
    )
  }
  let neighbors = av1_vartx_test_neighbors(root)
  assert_false(
    av1_vartx_record(neighbors, { row: 0, col: 28, width: 8, height: 8, }),
  )
  assert_true(
    av1_txfm_split_context(neighbors, { row: 0, col: 0, width: 4, height: 4, })
    is None,
  )
  let cdfs = av1_vartx_cdf_state()
  let decoder = av1_msac_new([b'\x00', b'\x00'], true)
  let before = (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range)
  assert_true(
    av1_decode_tx_partition_tree_with_decoder(
      decoder,
      cdfs,
      neighbors,
      { row: 0, col: 0, width: 16, height: 16, },
      2,
    )
    is None,
  )
  assert_eq(
    (decoder.bit_pos, decoder.symbol_value, decoder.symbol_range),
    before,
  )
  assert_eq(cdfs.rows[6][2], 0)
  assert_eq(neighbors.tx_width[0], -1)
}
