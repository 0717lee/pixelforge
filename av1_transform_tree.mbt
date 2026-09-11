/// Bounded AV1 transform-tree geometry.
///
/// This stage models transform partition geometry independently from entropy
/// symbols. Leaves are emitted in raster order and are later consumed by the
/// coefficient decoder.
pub(all) enum Av1TxPartition {
  Av1TxNone
  Av1TxSplit
  Av1TxHorz
  Av1TxVert
}

/// A rectangular transform node in pixel coordinates.
pub(all) struct Av1TxNode {
  row : Int
  col : Int
  width : Int
  height : Int
}

/// Return valid children for one transform-tree partition.
pub fn av1_tx_children(node : Av1TxNode, partition : Av1TxPartition) -> Array[Av1TxNode] {
  if node.row < 0 || node.col < 0 || node.width < 4 || node.height < 4 {
    return []
  }
  let out : Array[Av1TxNode] = []
  let half_w = node.width / 2
  let half_h = node.height / 2
  match partition {
    Av1TxNone => out.push(node)
    Av1TxSplit => {
      if node.width % 2 != 0 || node.height % 2 != 0 || half_w < 4 || half_h < 4 {
        return []
      }
      out.push({ row: node.row, col: node.col, width: half_w, height: half_h })
      out.push({ row: node.row, col: node.col + half_w, width: half_w, height: half_h })
      out.push({ row: node.row + half_h, col: node.col, width: half_w, height: half_h })
      out.push({ row: node.row + half_h, col: node.col + half_w, width: half_w, height: half_h })
    }
    Av1TxHorz => {
      if node.height % 2 != 0 || half_h < 4 { return [] }
      out.push({ row: node.row, col: node.col, width: node.width, height: half_h })
      out.push({ row: node.row + half_h, col: node.col, width: node.width, height: half_h })
    }
    Av1TxVert => {
      if node.width % 2 != 0 || half_w < 4 { return [] }
      out.push({ row: node.row, col: node.col, width: half_w, height: node.height })
      out.push({ row: node.row, col: node.col + half_w, width: half_w, height: node.height })
    }
  }
  out
}

/// Walk a transform tree and return its leaf nodes in raster order.
pub fn av1_tx_leaves(
  root : Av1TxNode,
  partitions : Array[Av1TxPartition],
) -> Array[Av1TxNode]? {
  let cursor = 0
  fn walk(node : Av1TxNode, parts : Array[Av1TxPartition], cursor : Ref[Int], out : Array[Av1TxNode]) -> Bool {
    if cursor.val >= parts.length() { return false }
    let partition = parts[cursor.val]
    cursor.val = cursor.val + 1
    let children = av1_tx_children(node, partition)
    if children.length() == 0 { return false }
    match partition {
      Av1TxNone => { out.push(node); true }
      _ => {
        for child in children {
          if !walk(child, parts, cursor, out) { return false }
        }
        true
      }
    }
  }
  let out : Array[Av1TxNode] = []
  if walk(root, partitions, { val: cursor }, out) { Some(out) } else { None }
}

///|
test "transform tree emits four raster leaves" {
  let leaves = av1_tx_leaves(
    { row: 0, col: 0, width: 32, height: 32 },
    [Av1TxSplit, Av1TxNone, Av1TxNone, Av1TxNone, Av1TxNone],
  ).unwrap()
  assert_eq(leaves.length(), 4)
  assert_eq((leaves[1].row, leaves[1].col), (0, 16))
  assert_eq((leaves[3].row, leaves[3].col), (16, 16))
}

///|
test "transform tree rejects odd and undersized splits" {
  assert_eq(av1_tx_children({ row: 0, col: 0, width: 7, height: 8 }, Av1TxSplit).length(), 0)
  assert_eq(av1_tx_children({ row: 0, col: 0, width: 4, height: 4 }, Av1TxSplit).length(), 0)
}
