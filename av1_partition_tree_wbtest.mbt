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
  assert_eq(children[0].size, 64)
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

test "extended partition geometry emits three and four square children" {
  let node = av1_partition_node(0, 0, 64, 64, 64)
  let ha = av1_partition_children(node, Av1SbPartitionHorzA)
  let vb = av1_partition_children(node, Av1SbPartitionVertB)
  assert_eq(ha.length(), 3)
  assert_eq(vb.length(), 3)
  assert_eq((ha[1].row, ha[1].col), (32, 0))
  assert_eq((vb[2].row, vb[2].col), (32, 32))
  let h4 = av1_partition_children(node, Av1SbPartitionHorz4)
  let v4 = av1_partition_children(node, Av1SbPartitionVert4)
  assert_eq(h4.length(), 4)
  assert_eq(v4.length(), 4)
  assert_eq((h4[3].row, h4[3].size), (48, 16))
  assert_eq((v4[3].col, v4[3].size), (48, 16))
}
