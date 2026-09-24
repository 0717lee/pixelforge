/// Partition-tree geometry and context checks.

///|
test "128 superblock at a 64x64 frame edge forces split" {
  let node = av1_partition_node(0, 0, 128, 64, 64)
  assert_false(node.has_rows())
  assert_false(node.has_cols())
  assert_true(node.edge_forces_split())
  let children = av1_partition_children(node, Av1SbPartitionSplit)
  assert_eq(children.length(), 1)
  assert_eq(children[0].row, 0)
  assert_eq(children[0].col, 0)
  assert_eq((children[0].width, children[0].height), (64, 64))
}

///|
test "partition context follows above and left smaller-neighbour flags" {
  // 64 pixels is four MI log2 steps (16 MI units); 32 is one step smaller.
  assert_eq(av1_partition_context(64, None, None), 0)
  assert_eq(av1_partition_context(64, Some(32), None), 1)
  assert_eq(av1_partition_context(64, None, Some(32)), 2)
  assert_eq(av1_partition_context(64, Some(32), Some(32)), 3)
  assert_eq(av1_partition_context(64, Some(64), Some(64)), 0)
}

///|
test "horizontal and vertical children stop at frame edges" {
  let horizontal = av1_partition_node(0, 0, 64, 64, 96)
  let h = av1_partition_children(horizontal, Av1SbPartitionHorz)
  assert_eq(h.length(), 2)
  assert_eq(h[1].row, 32)
  let vertical = av1_partition_node(0, 0, 64, 96, 64)
  let v = av1_partition_children(vertical, Av1SbPartitionVert)
  assert_eq(v.length(), 2)
  assert_eq(v[1].col, 32)
}

///|
test "extended partition geometry emits three and four rectangular blocks" {
  let node = av1_partition_node(0, 0, 64, 64, 64)
  let ha = av1_partition_children(node, Av1SbPartitionHorzA)
  let vb = av1_partition_children(node, Av1SbPartitionVertB)
  assert_eq(ha.length(), 3)
  assert_eq(vb.length(), 3)
  assert_eq((ha[1].row, ha[1].col), (0, 32))
  assert_eq((vb[2].row, vb[2].col), (32, 32))
  let h4 = av1_partition_children(node, Av1SbPartitionHorz4)
  let v4 = av1_partition_children(node, Av1SbPartitionVert4)
  assert_eq(h4.length(), 4)
  assert_eq(v4.length(), 4)
  assert_eq((h4[3].row, h4[3].width, h4[3].height), (48, 64, 16))
  assert_eq((v4[3].col, v4[3].width, v4[3].height), (48, 16, 64))
}

///|
test "partition leaf walker preserves raster order across extended nodes" {
  let root = av1_partition_node(0, 0, 64, 64, 64)
  let leaves = av1_partition_leaves(root, [Av1SbPartitionHorz]).unwrap()
  assert_eq(leaves.length(), 2)
  assert_eq((leaves[0].row, leaves[0].col), (0, 0))
  assert_eq((leaves[1].row, leaves[1].col), (32, 0))
  assert_true(
    av1_partition_leaves(root, [
      Av1SbPartitionHorz,
      Av1SbPartitionNone,
      Av1SbPartitionNone,
    ])
    is None,
  )
}

///|
test "MSAC partition fixture decodes NONE and recursive SPLIT" {
  let none = av1_decode_partition_leaves([b'\x40'], 64, 64).unwrap()
  assert_eq(none.length(), 1)
  assert_eq(
    (none[0].row, none[0].col, none[0].width, none[0].height),
    (0, 0, 64, 64),
  )
  // Crafted with scripts/craft_av1_fixture.py's od_ec encoder: W64 SPLIT
  // followed by four W32 NONE symbols.  The walker must consume the same
  // adaptive CDF rows and return four raster-ordered 32x32 leaves.
  let split = av1_decode_partition_leaves([b'\xB6'], 64, 64).unwrap()
  assert_eq(split.length(), 4)
  assert_eq(
    (split[0].row, split[0].col, split[0].width, split[0].height),
    (0, 0, 32, 32),
  )
  assert_eq(
    (split[1].row, split[1].col, split[1].width, split[1].height),
    (0, 32, 32, 32),
  )
  assert_eq(
    (split[2].row, split[2].col, split[2].width, split[2].height),
    (32, 0, 32, 32),
  )
  assert_eq(
    (split[3].row, split[3].col, split[3].width, split[3].height),
    (32, 32, 32, 32),
  )
}

///|
test "MSAC partition fixtures decode HORZ and VERT children" {
  // MsacEncoder: one W64/ctx0 HORZ, with no child partition symbols.
  let horizontal = av1_decode_partition_leaves([b'\xa4'], 64, 64).unwrap()
  assert_eq(horizontal.length(), 2)
  assert_eq((horizontal[1].row, horizontal[1].col), (32, 0))
  // MsacEncoder: one W64/ctx0 VERT, with no child partition symbols.
  let vertical = av1_decode_partition_leaves([b'\xac'], 64, 64).unwrap()
  assert_eq(vertical.length(), 2)
  assert_eq((vertical[1].row, vertical[1].col), (0, 32))
}

///|
// Every geometry row follows AV1 decode_partition / Partition_Subsize.
// The offsets below are independent expected rectangles for a 64x64 root.
test "partition geometry covers each parent with exact syntax-order rectangles" {
  let root = av1_partition_node(8, 12, 64, 128, 128)
  let cases : Array[(Av1SbPartition, Array[(Int, Int, Int, Int)])] = [
    (Av1SbPartitionNone, [(0, 0, 64, 64)]),
    (Av1SbPartitionHorz, [(0, 0, 64, 32), (32, 0, 64, 32)]),
    (Av1SbPartitionVert, [(0, 0, 32, 64), (0, 32, 32, 64)]),
    (
      Av1SbPartitionSplit,
      [(0, 0, 32, 32), (0, 32, 32, 32), (32, 0, 32, 32), (32, 32, 32, 32)],
    ),
    (Av1SbPartitionHorzA, [(0, 0, 32, 32), (0, 32, 32, 32), (32, 0, 64, 32)]),
    (Av1SbPartitionHorzB, [(0, 0, 64, 32), (32, 0, 32, 32), (32, 32, 32, 32)]),
    (Av1SbPartitionVertA, [(0, 0, 32, 32), (32, 0, 32, 32), (0, 32, 32, 64)]),
    (Av1SbPartitionVertB, [(0, 0, 32, 64), (0, 32, 32, 32), (32, 32, 32, 32)]),
    (
      Av1SbPartitionHorz4,
      [(0, 0, 64, 16), (16, 0, 64, 16), (32, 0, 64, 16), (48, 0, 64, 16)],
    ),
    (
      Av1SbPartitionVert4,
      [(0, 0, 16, 64), (0, 16, 16, 64), (0, 32, 16, 64), (0, 48, 16, 64)],
    ),
  ]
  for case in cases {
    let (partition, expected) = case
    let blocks = av1_partition_children(root, partition)
    assert_eq(blocks.length(), expected.length())
    let coverage = Array::make(16 * 16, 0)
    for i in 0..<blocks.length() {
      let block = blocks[i]
      assert_eq(
        (block.row - 8, block.col - 12, block.width, block.height),
        expected[i],
      )
      let y4 = (block.row - 8) / 4
      let x4 = (block.col - 12) / 4
      for y in y4..<(y4 + block.height / 4) {
        for x in x4..<(x4 + block.width / 4) {
          coverage[y * 16 + x] = coverage[y * 16 + x] + 1
        }
      }
    }
    for count in coverage {
      assert_eq(count, 1)
    }
  }
}

///|
test "partition implied decisions consume no sequence entries" {
  let four = av1_partition_node(0, 0, 4, 8, 8)
  let leaves = av1_partition_leaves(four, []).unwrap()
  assert_eq((leaves[0].width, leaves[0].height), (4, 4))
  assert_true(av1_partition_leaves(four, [Av1SbPartitionNone]) is None)
  let eight = av1_partition_node(0, 0, 8, 8, 8)
  assert_eq(
    av1_partition_leaves(eight, [Av1SbPartitionSplit]).unwrap().length(),
    4,
  )
  let forced = av1_partition_node(0, 0, 128, 64, 64)
  let leaves = av1_partition_leaves(forced, [Av1SbPartitionNone]).unwrap()
  assert_eq((leaves[0].width, leaves[0].height), (64, 64))
  assert_true(
    av1_partition_leaves(forced, [Av1SbPartitionSplit, Av1SbPartitionNone])
    is None,
  )
  let root = av1_partition_node(0, 0, 64, 64, 64)
  for
    partition in [
      Av1SbPartitionHorz,
      Av1SbPartitionVert,
      Av1SbPartitionHorzA,
      Av1SbPartitionHorzB,
      Av1SbPartitionVertA,
      Av1SbPartitionVertB,
      Av1SbPartitionHorz4,
      Av1SbPartitionVert4,
    ] {
    assert_eq(
      av1_partition_leaves(root, [partition]).unwrap().length(),
      av1_partition_children(root, partition).length(),
    )
  }
}

///|
test "partition neighbor context uses above width and left height" {
  let neighbors = av1_partition_neighbor_state(
    { row: 0, col: 0, width: 64, height: 64, },
    64,
    64,
  ).unwrap()
  let node = av1_partition_node(16, 16, 16, 64, 64)
  assert_true(av1_partition_neighbor_context(neighbors, node) is None)
  // Height 8 above and width 8 to the left must not affect the context.
  assert_true(
    av1_partition_record_block(neighbors, {
      row: 8,
      col: 16,
      width: 16,
      height: 8,
    }),
  )
  assert_true(
    av1_partition_record_block(neighbors, {
      row: 16,
      col: 8,
      width: 8,
      height: 16,
    }),
  )
  assert_eq(av1_partition_neighbor_context(neighbors, node), Some(0))
  assert_true(
    av1_partition_record_block(neighbors, {
      row: 0,
      col: 16,
      width: 8,
      height: 16,
    }),
  )
  assert_true(
    av1_partition_record_block(neighbors, {
      row: 16,
      col: 0,
      width: 16,
      height: 8,
    }),
  )
  assert_eq(av1_partition_neighbor_context(neighbors, node), Some(3))
  let tile = av1_partition_neighbor_state(
    { row: 64, col: 64, width: 64, height: 64, },
    128,
    128,
  ).unwrap()
  assert_eq(
    av1_partition_neighbor_context(
      tile,
      av1_partition_node(64, 64, 64, 128, 128),
    ),
    Some(0),
  )
  assert_true(
    av1_partition_neighbor_context(tile, av1_partition_node(0, 0, 64, 128, 128))
    is None,
  )
}

///|
test "partition callback consumes leaf syntax before the next partition" {
  // MsacEncoder transcript:
  // W64 ctx0 SPLIT; W32 ctx0 HORZ; leaf bits 1,0;
  // W32 ctx2 NONE; leaf bit 1; W32 ctx0 NONE; leaf bit 0;
  // W32 ctx0 NONE; leaf bit 1. This is a synthetic syntax-order probe.
  let decoder = av1_msac_new([b'\xd2', b'\xc0', b'\x80'], true)
  let cdfs = av1_partition_cdf_state()
  let neighbors = av1_partition_neighbor_state(
    { row: 0, col: 0, width: 64, height: 64, },
    64,
    64,
  ).unwrap()
  let blocks : Array[(Int, Int, Int, Int)] = []
  let bits : Array[Int] = []
  let partitions_seen : Array[Int] = []
  let previous_size : Array[Int] = []
  assert_true(
    av1_walk_partition_tree(
      decoder,
      cdfs,
      neighbors,
      av1_partition_node(0, 0, 64, 64, 64),
      fn(reader, block) {
        blocks.push((block.row, block.col, block.width, block.height))
        previous_size.push(
          neighbors.block_widths[block.row / 4 * 16 + block.col / 4],
        )
        partitions_seen.push(cdfs.w32[0][10] + cdfs.w32[2][10])
        bits.push(reader.bool())
        true
      },
    ),
  )
  assert_eq(blocks, [
    (0, 0, 32, 16),
    (16, 0, 32, 16),
    (0, 32, 32, 32),
    (32, 0, 32, 32),
    (32, 32, 32, 32),
  ])
  assert_eq(bits, [1, 0, 1, 0, 1])
  assert_eq(partitions_seen, [1, 1, 2, 3, 4])
  assert_eq(previous_size, [-1, -1, -1, -1, -1])
  assert_eq(cdfs.w64[0], [
    19508, 20874, 22357, 29666, 29928, 30339, 30594, 30950, 31756, 32768, 1,
  ])
  assert_eq(cdfs.w32[0], [
    18801, 21995, 23998, 28112, 28638, 29386, 29813, 30412, 31654, 32768, 3,
  ])
  assert_eq(cdfs.w32[2], [
    6851, 9751, 10771, 24801, 25638, 26739, 27249, 27689, 32069, 32768, 1,
  ])
  assert_eq(neighbors.block_heights[0], 16)
  assert_eq(neighbors.block_heights[15 * 16 + 15], 32)
}

///|
test "partition callback failure stops before the next block or symbol" {
  let decoder = av1_msac_new([b'\xd2', b'\xc0', b'\x80'], true)
  let cdfs = av1_partition_cdf_state()
  let neighbors = av1_partition_neighbor_state(
    { row: 0, col: 0, width: 64, height: 64, },
    64,
    64,
  ).unwrap()
  let bits : Array[Int] = []
  assert_false(
    av1_walk_partition_tree(
      decoder,
      cdfs,
      neighbors,
      av1_partition_node(0, 0, 64, 64, 64),
      fn(reader, _) {
        bits.push(reader.bool())
        false
      },
    ),
  )
  assert_eq(bits, [1])
  assert_eq(cdfs.w32[0][10], 1)
  assert_eq(cdfs.w32[2][10], 0)
  assert_eq(neighbors.block_widths[0], -1)
  // The second leaf's marker remains the very next symbol.
  assert_eq(decoder.bool(), 0)
}

///|
test "partition CDF and neighbor state persist across superblocks" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  let cdfs = av1_partition_cdf_state()
  let neighbors = av1_partition_neighbor_state(
    { row: 0, col: 0, width: 128, height: 64, },
    128,
    64,
  ).unwrap()
  let blocks : Array[Av1SbBlock] = []
  for col in [0, 64] {
    assert_true(
      av1_walk_partition_tree(
        decoder,
        cdfs,
        neighbors,
        av1_partition_node(0, col, 64, 128, 64),
        fn(_, block) {
          blocks.push(block)
          true
        },
      ),
    )
  }
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[1].col, 64)
  assert_eq(cdfs.w64[0][10], 2)
  assert_eq(neighbors.block_widths[31], 64)
  assert_eq(av1_partition_cdf_state().w64[0][10], 0)
}

///|
test "partition-only extended entropy probes terminate without child NONE symbols" {
  // Each payload was encoded from one W64/ctx0 symbol using MsacEncoder.
  let cases : Array[(Byte, Av1SbPartition)] = [
    (b'\xe7', Av1SbPartitionHorzA),
    (b'\xeb', Av1SbPartitionHorzB),
    (b'\xed', Av1SbPartitionVertA),
    (b'\xef', Av1SbPartitionVertB),
    (b'\xf2', Av1SbPartitionHorz4),
    (b'\xfc', Av1SbPartitionVert4),
  ]
  for case in cases {
    let (payload, partition) = case
    let blocks = av1_decode_partition_leaves([payload], 64, 64).unwrap()
    let expected = av1_partition_children(
      av1_partition_node(0, 0, 64, 64, 64),
      partition,
    )
    assert_eq(blocks.length(), expected.length())
    for i in 0..<blocks.length() {
      let a = blocks[i]
      let b = expected[i]
      assert_eq(
        (a.row, a.col, a.width, a.height),
        (b.row, b.col, b.width, b.height),
      )
    }
  }
}

///|
test "partition validation rejects invalid sizes symbols and tile bounds" {
  for size in [0, 2, 6, 12, 256] {
    let node = av1_partition_node(0, 0, size, 64, 64)
    assert_eq(av1_partition_children(node, Av1SbPartitionNone).length(), 0)
    assert_true(av1_partition_leaves(node, []) is None)
    assert_false(node.edge_forces_split())
  }
  for position in [(-4, 0), (0, -4), (1, 0), (0, 2), (2147483644, 0)] {
    let (row, col) = position
    assert_eq(
      av1_partition_children(
        av1_partition_node(row, col, 8, 64, 64),
        Av1SbPartitionNone,
      ).length(),
      0,
    )
  }
  let four = av1_partition_node(0, 0, 4, 64, 64)
  let eight = av1_partition_node(0, 0, 8, 64, 64)
  let large = av1_partition_node(0, 0, 128, 128, 128)
  assert_eq(av1_partition_children(four, Av1SbPartitionSplit).length(), 0)
  assert_eq(av1_partition_children(eight, Av1SbPartitionHorzA).length(), 0)
  assert_eq(av1_partition_children(eight, Av1SbPartitionHorz4).length(), 0)
  assert_eq(av1_partition_children(large, Av1SbPartitionHorz4).length(), 0)
  assert_eq(av1_partition_children(large, Av1SbPartitionVert4).length(), 0)
  assert_eq(
    av1_partition_children(
      av1_partition_node(0, 0, 64, 64, 24),
      Av1SbPartitionVert,
    ).length(),
    0,
  )
  assert_true(av1_decode_partition_leaves([], 64, 64) is None)
  assert_true(av1_decode_partition_leaves([b'\x40'], 65, 64) is None)
  assert_true(av1_decode_partition_leaves([b'\x40'], 0, 64) is None)
  assert_true(
    av1_partition_neighbor_state(
      { row: 0, col: 0, width: 63, height: 64, },
      64,
      64,
    )
    is None,
  )
  assert_true(
    av1_partition_neighbor_state(
      { row: 0, col: 0, width: 68, height: 64, },
      64,
      64,
    )
    is None,
  )
  assert_true(
    av1_partition_neighbor_state(
      { row: 0, col: 0, width: 64, height: 0, },
      64,
      64,
    )
    is None,
  )
}

///|
test "partition frame edges use padded MI bounds and explicit superblock size" {
  // A visible 1x1 frame still has a 2x2 MI grid. The fixed 64 root is forced
  // through 32 and 16 to an 8x8 node, whose W8/ctx0 NONE fixture is 0x40.
  let blocks = av1_decode_partition_leaves([b'\x40'], 1, 1).unwrap()
  assert_eq(blocks.length(), 1)
  assert_eq((blocks[0].width, blocks[0].height), (8, 8))
  let edge = av1_partition_node(0, 0, 8, 1, 1)
  assert_true(edge.has_rows())
  assert_true(edge.has_cols())
  // Pixels 4..7 are outside the visible image but still inside the MI grid.
  assert_eq(av1_partition_children(edge, Av1SbPartitionSplit).length(), 4)
  let blocks = av1_decode_partition_leaves(
    [b'\x40'],
    128,
    128,
    use_128x128_superblock=true,
  ).unwrap()
  assert_eq((blocks[0].width, blocks[0].height), (128, 128))
  let blocks = av1_decode_partition_leaves(
    [b'\x40'],
    64,
    64,
    use_128x128_superblock=true,
  ).unwrap()
  assert_eq((blocks[0].width, blocks[0].height), (64, 64))
  // frame24x64 uses the W64/ctx0 split_or_vert CDF [23080,32768,0].
  // The synthetic symbol-0 fixture is 0x40, producing one coded 32x64 block.
  let blocks = av1_decode_partition_leaves([b'\x40'], 24, 64).unwrap()
  assert_eq(blocks.length(), 1)
  assert_eq((blocks[0].width, blocks[0].height), (32, 64))
}

///|
test "square transform reconstruction rejects rectangular coding blocks" {
  let plane = Array::make(64 * 64, 128)
  assert_false(
    av1_reconstruct_child(
      plane,
      64,
      64,
      { row: 0, col: 0, width: 32, height: 16, },
      0,
      Array::make(32 * 32, 0),
      32,
    ),
  )
  assert_eq(plane[0], 128)
}
