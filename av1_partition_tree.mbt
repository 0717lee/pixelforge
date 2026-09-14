/// Bounded AV1 partition-tree geometry helpers.
///
/// Coordinates and dimensions are expressed in pixels.  The AV1 reference
/// decoder stores the same values in 4x4 (MI) units; using pixels here keeps
/// this standalone model useful to the image reconstruction path while the
/// `partition_context` calculation converts sizes to the corresponding MI
/// logarithm.

/// AV1 partition symbols.  The first four are the symbols used by the staged
/// decoder; the extended forms are represented so a later walker can add them
/// without changing the public data model.
pub(all) enum Av1SbPartition {
  Av1SbPartitionNone
  Av1SbPartitionHorz
  Av1SbPartitionVert
  Av1SbPartitionSplit
  Av1SbPartitionHorzA
  Av1SbPartitionHorzB
  Av1SbPartitionVertA
  Av1SbPartitionVertB
  Av1SbPartitionHorz4
  Av1SbPartitionVert4
}

/// A rectangular node in a superblock partition tree.
pub(all) struct Av1SbPartitionNode {
  row : Int
  col : Int
  size : Int
  frame_width : Int
  frame_height : Int
}

/// Creates a square partition node.  Invalid geometry is rejected by the
/// child and edge predicates rather than clamped silently.
pub fn av1_partition_node(
  row : Int,
  col : Int,
  size : Int,
  frame_width : Int,
  frame_height : Int,
) -> Av1SbPartitionNode {
  { row, col, size, frame_width, frame_height }
}

/// Whether the lower half of this block lies inside the frame (AV1 `hasRows`).
pub fn Av1SbPartitionNode::has_rows(self : Av1SbPartitionNode) -> Bool {
  self.size > 0 && self.row >= 0 && self.row + self.size / 2 < self.frame_height
}

/// Whether the right half of this block lies inside the frame (AV1 `hasCols`).
pub fn Av1SbPartitionNode::has_cols(self : Av1SbPartitionNode) -> Bool {
  self.size > 0 && self.col >= 0 && self.col + self.size / 2 < self.frame_width
}

/// True when the node has no complete lower or right half.  AV1 forces a
/// split in this case, avoiding a partition symbol that would address pixels
/// outside the frame.
pub fn Av1SbPartitionNode::edge_forces_split(self : Av1SbPartitionNode) -> Bool {
  !self.has_rows() && !self.has_cols()
}

/// Convert a pixel block size to AV1's `MiWidthLog2` value.
fn av1_partition_size_log2(size : Int) -> Int {
  let mut mi = size / 4
  if mi < 1 {
    return 0
  }
  let mut out = 0
  while mi > 1 {
    mi = mi >> 1
    out = out + 1
  }
  out
}

/// AV1 `partitionCtx`: above contributes one and left contributes two when
/// the neighbouring block is smaller than the current block.
pub fn av1_partition_context(
  current_size : Int,
  above_size : Int?,
  left_size : Int?,
) -> Int {
  let current_log2 = av1_partition_size_log2(current_size)
  let above = match above_size {
    Some(size) => if av1_partition_size_log2(size) < current_log2 { 1 } else { 0 }
    None => 0
  }
  let left = match left_size {
    Some(size) => if av1_partition_size_log2(size) < current_log2 { 1 } else { 0 }
    None => 0
  }
  left * 2 + above
}

fn av1_partition_child(
  node : Av1SbPartitionNode,
  row : Int,
  col : Int,
  size : Int,
) -> Av1SbPartitionNode? {
  if row < 0 || col < 0 || row >= node.frame_height || col >= node.frame_width || size <= 0 {
    None
  } else {
    Some({
      row,
      col,
      size,
      frame_width: node.frame_width,
      frame_height: node.frame_height,
    })
  }
}

fn av1_partition_push_child(
  out : Array[Av1SbPartitionNode],
  child : Av1SbPartitionNode?,
) -> Unit {
  match child {
    Some(value) => out.push(value)
    None => ()
  }
}

/// Return in-frame child coordinates for a partition symbol.  `None` returns
/// the node itself as a leaf.  Split children are filtered at the frame edge,
/// matching the reference decoder's early out for rows/columns outside the
/// image.
pub fn av1_partition_children(
  node : Av1SbPartitionNode,
  partition : Av1SbPartition,
) -> Array[Av1SbPartitionNode] {
  let half = node.size / 2
  let out : Array[Av1SbPartitionNode] = []
  match partition {
    Av1SbPartitionNone => out.push(node)
    Av1SbPartitionHorz => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      if node.has_rows() {
        av1_partition_push_child(
          out,
          av1_partition_child(node, node.row + half, node.col, half),
        )
      }
    }
    Av1SbPartitionVert => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      if node.has_cols() {
        av1_partition_push_child(
          out,
          av1_partition_child(node, node.row, node.col + half, half),
        )
      }
    }
    Av1SbPartitionSplit => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row, node.col + half, half),
      )
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row + half, node.col, half),
      )
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row + half, node.col + half, half),
      )
    }
    // A/B partitions combine one full half with two quarter blocks.  The
    // children stay square in this geometry model; rectangular transform
    // leaves are handled by the separate tx tree.
    Av1SbPartitionHorzA => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col + half, half))
    }
    Av1SbPartitionHorzB => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + half, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
    }
    Av1SbPartitionVertA => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + half, half))
    }
    Av1SbPartitionVertB => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col + half, half))
    }
    Av1SbPartitionHorz4 => {
      let quarter = node.size / 4
      if quarter >= 4 {
        for i in 0..<4 {
          av1_partition_push_child(out, av1_partition_child(node, node.row + i * quarter, node.col, quarter))
        }
      }
    }
    Av1SbPartitionVert4 => {
      let quarter = node.size / 4
      if quarter >= 4 {
        for i in 0..<4 {
          av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + i * quarter, quarter))
        }
      }
    }
  }
  out
}

/// Walk a pre-decoded partition sequence and return leaf blocks in raster
/// order.  Entropy decoding remains the caller's responsibility; this helper
/// provides the same bounded geometry walk used by the transform tree.
pub fn av1_partition_leaves(
  root : Av1SbPartitionNode,
  partitions : Array[Av1SbPartition],
) -> Array[Av1SbPartitionNode]? {
  let cursor : Ref[Int] = { val: 0 }
  let out : Array[Av1SbPartitionNode] = []
  fn walk(
    node : Av1SbPartitionNode,
    parts : Array[Av1SbPartition],
    cursor : Ref[Int],
    out : Array[Av1SbPartitionNode],
  ) -> Bool {
    if cursor.val >= parts.length() { return false }
    let partition = parts[cursor.val]
    cursor.val = cursor.val + 1
    let children = av1_partition_children(node, partition)
    if children.length() == 0 { return false }
    match partition {
      Av1SbPartitionNone => { out.push(node); true }
      _ => {
        for child in children {
          if !walk(child, parts, cursor, out) { return false }
        }
        true
      }
    }
  }
  if walk(root, partitions, cursor, out) && cursor.val == partitions.length() {
    Some(out)
  } else {
    None
  }
}

/// Per-tile default partition CDFs.  The rows are indexed by the AV1
/// `partitionCtx` (above contributes one, left contributes two).  Keeping the
/// rows mutable is important: MSAC adapts partition CDFs after every symbol.
priv struct Av1PartitionCdfState {
  w8 : Array[Array[Int]]
  w16 : Array[Array[Int]]
  w32 : Array[Array[Int]]
  w64 : Array[Array[Int]]
  w128 : Array[Array[Int]]
}

fn av1_partition_cdf_state() -> Av1PartitionCdfState {
  {
    w8: [
      [19132, 25510, 30392, 32768, 0],
      [13928, 19855, 28540, 32768, 0],
      [12522, 23679, 28629, 32768, 0],
      [9896, 18783, 25853, 32768, 0],
    ],
    w16: [
      [15597, 20929, 24571, 26706, 27664, 28821, 29601, 30571, 31902, 32768, 0],
      [7925, 11043, 16785, 22470, 23971, 25043, 26651, 28701, 29834, 32768, 0],
      [5414, 13269, 15111, 20488, 22360, 24500, 25537, 26336, 32117, 32768, 0],
      [2662, 6362, 8614, 20860, 23053, 24778, 26436, 27829, 31171, 32768, 0],
    ],
    w32: [
      [18462, 20920, 23124, 27647, 28227, 29049, 29519, 30178, 31544, 32768, 0],
      [7689, 9060, 12056, 24992, 25660, 26182, 26951, 28041, 29052, 32768, 0],
      [6015, 9009, 10062, 24544, 25409, 26545, 27071, 27526, 32047, 32768, 0],
      [1394, 2208, 2796, 28614, 29061, 29466, 29840, 30185, 31899, 32768, 0],
    ],
    w64: [
      [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0],
      [6732, 7490, 9497, 27944, 28250, 28515, 28969, 29630, 30104, 32768, 0],
      [5945, 7663, 8348, 28683, 29117, 29749, 30064, 30298, 32238, 32768, 0],
      [870, 1212, 1487, 31198, 31394, 31574, 31743, 31881, 32332, 32768, 0],
    ],
    w128: [
      [27899, 28219, 28529, 32484, 32539, 32619, 32639, 32768, 0],
      [6607, 6990, 8268, 32060, 32219, 32338, 32371, 32768, 0],
      [5429, 6676, 7122, 32027, 32227, 32531, 32582, 32768, 0],
      [711, 966, 1172, 32448, 32538, 32617, 32664, 32768, 0],
    ],
  }
}

fn av1_partition_cdf_rows(
  state : Av1PartitionCdfState,
  size : Int,
) -> Array[Array[Int]] {
  if size <= 8 {
    state.w8
  } else if size <= 16 {
    state.w16
  } else if size <= 32 {
    state.w32
  } else if size <= 64 {
    state.w64
  } else {
    state.w128
  }
}

fn av1_partition_symbol_from_index(index : Int) -> Av1SbPartition? {
  match index {
    0 => Some(Av1SbPartitionNone)
    1 => Some(Av1SbPartitionHorz)
    2 => Some(Av1SbPartitionVert)
    3 => Some(Av1SbPartitionSplit)
    4 => Some(Av1SbPartitionHorzA)
    5 => Some(Av1SbPartitionHorzB)
    6 => Some(Av1SbPartitionVertA)
    7 => Some(Av1SbPartitionVertB)
    8 => Some(Av1SbPartitionHorz4)
    9 => Some(Av1SbPartitionVert4)
    _ => None
  }
}

fn av1_partition_probability(cdf : Array[Int], symbol : Int) -> Int {
  let prev = if symbol == 0 { 0 } else { cdf[symbol - 1] }
  let next = if symbol < cdf.length() - 2 { cdf[symbol] } else { 32768 }
  next - prev
}

/// Read an edge partition's two-symbol `split_or_horz`/`split_or_vert` CDF.
/// This is the gather operation from AV1 §9.3; it prevents out-of-frame child
/// blocks from consuming a symbol that cannot be represented by the geometry.
fn av1_partition_edge_symbol(
  decoder : Av1SymbolDecoder,
  cdf : Array[Int],
  has_rows : Bool,
  has_cols : Bool,
) -> Av1SbPartition? {
  let mut split_probability = 0
  if has_cols && !has_rows {
    // split_or_horz: VERT, SPLIT, HORZ_A, VERT_A, VERT_B, VERT4
    for symbol in [2, 3, 4, 6, 7, 9] {
      if symbol < cdf.length() - 1 {
        split_probability = split_probability + av1_partition_probability(cdf, symbol)
      }
    }
    let gathered = [32768 - split_probability, 32768, 0]
    if decoder.symbol(gathered) == 1 {
      Some(Av1SbPartitionSplit)
    } else {
      Some(Av1SbPartitionHorz)
    }
  } else if has_rows && !has_cols {
    // split_or_vert: HORZ, SPLIT, HORZ_A, HORZ_B, VERT_A, HORZ4
    for symbol in [1, 3, 4, 5, 6, 8] {
      if symbol < cdf.length() - 1 {
        split_probability = split_probability + av1_partition_probability(cdf, symbol)
      }
    }
    let gathered = [32768 - split_probability, 32768, 0]
    if decoder.symbol(gathered) == 1 {
      Some(Av1SbPartitionSplit)
    } else {
      Some(Av1SbPartitionVert)
    }
  } else {
    Some(Av1SbPartitionSplit)
  }
}

fn av1_partition_neighbour_size(
  leaves : Array[Av1SbPartitionNode],
  node : Av1SbPartitionNode,
  above : Bool,
) -> Int? {
  for leaf in leaves {
    if above {
      if leaf.row + leaf.size == node.row &&
        node.col >= leaf.col && node.col < leaf.col + leaf.size {
        return Some(leaf.size)
      }
    } else if leaf.col + leaf.size == node.col &&
      node.row >= leaf.row && node.row < leaf.row + leaf.size {
      return Some(leaf.size)
    }
  }
  None
}

fn av1_decode_partition_symbol(
  decoder : Av1SymbolDecoder,
  state : Av1PartitionCdfState,
  node : Av1SbPartitionNode,
  leaves : Array[Av1SbPartitionNode],
) -> Av1SbPartition? {
  if node.size <= 4 {
    return Some(Av1SbPartitionNone)
  }
  let above = av1_partition_neighbour_size(leaves, node, true)
  let left = av1_partition_neighbour_size(leaves, node, false)
  let rows = av1_partition_cdf_rows(state, node.size)
  let context = av1_partition_context(node.size, above, left)
  let cdf = rows[if context < 4 { context } else { 3 }]
  if !node.has_rows() || !node.has_cols() {
    return av1_partition_edge_symbol(decoder, cdf, node.has_rows(), node.has_cols())
  }
  av1_partition_symbol_from_index(decoder.symbol(cdf))
}

/// Decode the partition symbols of one reduced-still tile and return its
/// in-frame leaf blocks in raster order.  This API deliberately stops at
/// 4x4 leaves; block mode and transform syntax are decoded by the tile path
/// after this geometry stage.  It is useful both as a conformance probe and
/// as the shared walker for future multi-block reconstruction.
pub fn av1_decode_partition_leaves(
  tile_payload : Array[Byte],
  frame_width : Int,
  frame_height : Int,
  disable_cdf_update? : Bool = false,
  use_128x128_superblock? : Bool = false,
) -> Array[Av1SbPartitionNode]? {
  if tile_payload.length() == 0 || frame_width <= 0 || frame_height <= 0 {
    return None
  }
  let mut root_size = if frame_width > frame_height { frame_width } else { frame_height }
  if root_size < 8 { root_size = 8 }
  if root_size > 128 { return None }
  let mut power = 8
  while power < root_size { power = power * 2 }
  root_size = power
  let root = av1_partition_node(0, 0, root_size, frame_width, frame_height)
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  let state = av1_partition_cdf_state()
  let leaves : Array[Av1SbPartitionNode] = []
  fn walk(
    decoder : Av1SymbolDecoder,
    state : Av1PartitionCdfState,
    node : Av1SbPartitionNode,
    leaves : Array[Av1SbPartitionNode],
  ) -> Bool {
    if node.row >= node.frame_height || node.col >= node.frame_width {
      return true
    }
    let partition = match av1_decode_partition_symbol(decoder, state, node, leaves) {
      Some(value) => value
      None => return false
    }
    match partition {
      Av1SbPartitionNone => {
        leaves.push(node)
        return true
      }
      _ => ()
    }
    if node.size <= 4 {
      leaves.push(node)
      return true
    }
    let children = av1_partition_children(node, partition)
    if children.length() == 0 { return false }
    for child in children {
      if !walk(decoder, state, child, leaves) { return false }
    }
    true
  }
  // Keep the optional superblock argument meaningful: a 128x128 root is
  // legal only when the sequence tool is enabled, otherwise callers get the
  // normal 64x64/32x32 tree.
  if use_128x128_superblock && root_size != 128 { return None }
  if !walk(decoder, state, root, leaves) { None } else { Some(leaves) }
}
