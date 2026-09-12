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

/// A transform-tree leaf together with the depth selected by the frame's
/// `tx_depth` symbol.  AV1 signals one depth for an intra block and derives
/// the geometry by repeatedly applying the split transform size; keeping the
/// depth on each leaf makes that relationship explicit for residual readers.
pub(all) struct Av1TxLeaf {
  node : Av1TxNode
  depth : Int
}

/// Decode the bounded tx_depth symbol used when frame tx_mode_select is set.
/// The context table is reduced to the three validated default rows until the
/// full neighbour-derived 21-context table is wired into block traversal.
fn av1_decode_tx_depth(
  decoder : Av1SymbolDecoder,
  max_size : Int,
  context : Int,
) -> Int? {
  let ctx = if context < 0 { 0 } else if context > 2 { 2 } else { context }
  let cdf : Array[Int] = if max_size >= 64 {
    match ctx { 0 => [5782, 11475, 32768, 0]; 1 => [5782, 11475, 32768, 0]; _ => [16803, 22759, 32768, 0] }
  } else if max_size >= 32 {
    match ctx { 0 => [12986, 15180, 32768, 0]; 1 => [12986, 15180, 32768, 0]; _ => [24302, 25602, 32768, 0] }
  } else if max_size >= 16 {
    match ctx { 0 => [12272, 30172, 32768, 0]; 1 => [12272, 30172, 32768, 0]; _ => [18677, 30848, 32768, 0] }
  } else {
    [19968, 32768, 0]
  }
  let depth = decoder.symbol(cdf)
  let max_depth = if max_size >= 64 { 3 } else if max_size >= 32 { 2 } else if max_size >= 16 { 1 } else { 0 }
  if depth < 0 || depth > max_depth { None } else { Some(depth) }
}

/// Build the leaves selected by one `tx_depth` value.  The entropy syntax
/// carries the depth once at the block root; subsequent nodes are geometric
/// splits and do not consume additional symbols.  This helper is deliberately
/// separate from coefficient decoding so callers can traverse the same leaf
/// order for prediction, residuals and context updates.
fn av1_tx_depth_leaves(
  node : Av1TxNode,
  remaining : Int,
  depth : Int,
  out : Array[Av1TxLeaf],
) -> Bool {
  if node.row < 0 || node.col < 0 || node.width < 4 || node.height < 4 ||
    remaining < 0 || depth < 0 {
    return false
  }
  if remaining == 0 {
    out.push({ node, depth })
    return true
  }
  let children = av1_tx_children(node, Av1TxSplit)
  if children.length() != 4 {
    return false
  }
  for child in children {
    if !av1_tx_depth_leaves(child, remaining - 1, depth + 1, out) {
      return false
    }
  }
  true
}

fn av1_decode_tx_tree(
  decoder : Av1SymbolDecoder,
  root : Av1TxNode,
  context : Int,
) -> Array[Av1TxLeaf]? {
  let max_size = if root.width > root.height { root.width } else { root.height }
  let depth = match av1_decode_tx_depth(decoder, max_size, context) {
    Some(value) => value
    None => return None
  }
  let out : Array[Av1TxLeaf] = []
  if av1_tx_depth_leaves(root, depth, 0, out) { Some(out) } else { None }
}

/// Decode the intra luma tx_type symbol after all_zero and before EOB.
/// Set 2 is used for the reduced 5-symbol set; set 1 exposes seven symbols.
fn av1_decode_intra_tx_type(
  decoder : Av1SymbolDecoder,
  tx_size : Int,
  use_set2 : Bool,
) -> Av1TxType? {
  if tx_size > 32 { return Some(Av1TxDctDct) }
  let symbol = if use_set2 {
    decoder.symbol([6554, 13107, 19661, 26214, 32768, 0])
  } else {
    decoder.symbol([1535, 8035, 9461, 12751, 23467, 27825, 32768, 0])
  }
  if use_set2 {
    match symbol {
      0 => Some(Av1TxIdentityIdentity)
      1 => Some(Av1TxDctDct)
      2 => Some(Av1TxAdstAdst)
      3 => Some(Av1TxAdstDct)
      4 => Some(Av1TxDctAdst)
      _ => None
    }
  } else {
    match symbol {
      0 => Some(Av1TxIdentityIdentity)
      1 => Some(Av1TxDctDct)
      2 => Some(Av1TxVerticalDct)
      3 => Some(Av1TxHorizontalDct)
      4 => Some(Av1TxAdstAdst)
      5 => Some(Av1TxAdstDct)
      6 => Some(Av1TxDctAdst)
      _ => None
    }
  }
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

/// Decode square coefficient blocks at transform-tree leaves while sharing
/// one mutable MSAC reader and coefficient CDF context.
fn av1_tx_decode_coeff_leaves(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  root : Av1TxNode,
  partitions : Array[Av1TxPartition],
  bit_depth : Int,
) -> Array[Array[Int]]? {
  let leaves = match av1_tx_leaves(root, partitions) {
    Some(value) => value
    None => return None
  }
  let out : Array[Array[Int]] = []
  for leaf in leaves {
    if leaf.width != leaf.height ||
      (leaf.width != 4 && leaf.width != 8 && leaf.width != 16 &&
        leaf.width != 32 && leaf.width != 64) {
      return None
    }
    let coeffs = if leaf.width <= 16 {
      context.tx_ctx = if leaf.width == 16 { 2 } else if leaf.width == 8 { 1 } else { 0 }
      av1_decode_coeffs_small_with_decoder(decoder, base_q_idx, context, leaf.width, bit_depth=bit_depth)
    } else {
      context.tx_ctx = if leaf.width == 64 { 4 } else { 3 }
      av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, context, bit_depth=bit_depth)
    }
    let coeffs = match coeffs {
      Some(value) => value
      None => return None
    }
    out.push(coeffs)
  }
  Some(out)
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
test "transform tree walks smaller AV1 leaf sizes" {
  let leaves = av1_tx_leaves(
    { row: 0, col: 0, width: 8, height: 8 },
    [Av1TxSplit, Av1TxNone, Av1TxNone, Av1TxNone, Av1TxNone],
  ).unwrap()
  assert_eq(leaves.length(), 4)
  assert_eq((leaves[0].width, leaves[0].height), (4, 4))
}

///|
test "transform tree rejects odd and undersized splits" {
  assert_eq(av1_tx_children({ row: 0, col: 0, width: 7, height: 8 }, Av1TxSplit).length(), 0)
  assert_eq(av1_tx_children({ row: 0, col: 0, width: 4, height: 4 }, Av1TxSplit).length(), 0)
}

///|
test "transform tree coefficient walk rejects truncated entropy" {
  let decoder = av1_msac_new([b'\x00'], true)
  let result = av1_tx_decode_coeff_leaves(
    decoder,
    0,
    av1_coeff_context(0, 3, 0),
    { row: 0, col: 0, width: 32, height: 32 },
    [Av1TxNone],
    8,
  )
  assert_true(result is None)
}

///|
test "tx depth reader bounds frame transform depth" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  assert_true(av1_decode_tx_depth(decoder, 64, 0) is Some(_))
  assert_true(av1_decode_tx_depth(decoder, 4, 0) is Some(_))
}

///|
test "tx depth entropy walker emits root leaf for zero depth" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  let leaves = av1_decode_tx_tree(
    decoder,
    { row: 0, col: 0, width: 4, height: 4 },
    0,
  ).unwrap()
  assert_eq(leaves.length(), 1)
  assert_eq(leaves[0].depth, 0)
  assert_eq((leaves[0].node.width, leaves[0].node.height), (4, 4))
}

///|
test "tx depth walker rejects a split below minimum geometry" {
  let out : Array[Av1TxLeaf] = []
  assert_false(
    av1_tx_depth_leaves({ row: 0, col: 0, width: 4, height: 4 }, 1, 0, out),
  )
  assert_eq(out.length(), 0)
}

///|
test "intra tx type reader maps both bounded symbol sets" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  assert_true(av1_decode_intra_tx_type(decoder, 16, true) is Some(_))
  assert_true(av1_decode_intra_tx_type(decoder, 16, false) is Some(_))
  assert_true(av1_decode_intra_tx_type(decoder, 64, false) is Some(_))
}

///|
test "tx depth entropy recursively emits transform leaves" {
  let decoder = av1_msac_new(Array::make(32, b'\x00'), true)
  let leaves = av1_decode_tx_tree(decoder, { row: 0, col: 0, width: 16, height: 16 }, 0).unwrap()
  assert_true(leaves.length() >= 1)
}

///|
test "transform tree decodes a small zero-EOB coefficient leaf" {
  let decoder = av1_msac_new(Array::make(64, b'\x00'), true)
  let result = av1_tx_decode_coeff_leaves(
    decoder,
    0,
    av1_coeff_context(0, 0, 0),
    { row: 0, col: 0, width: 4, height: 4 },
    [Av1TxNone],
    8,
  ).unwrap()
  assert_eq(result.length(), 1)
  assert_eq(result[0].length(), 16)
  assert_eq(result[0][0], 2)
}
