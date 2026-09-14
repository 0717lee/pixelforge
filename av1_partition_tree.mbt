/// Bounded AV1 partition-tree geometry helpers.
///
/// Coordinates and dimensions are expressed in pixels.  The AV1 reference
/// decoder stores the same values in 4x4 (MI) units; using pixels here keeps
/// this standalone model useful to the image reconstruction path while the
/// `partition_context` calculation converts sizes to the corresponding MI
/// logarithm.

/// AV1 partition symbols. Only SPLIT creates more partition syntax; every
/// other symbol produces one or more terminal coding blocks.
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

/// A square node at which AV1 partition syntax is evaluated.
pub(all) struct Av1SbPartitionNode {
  row : Int
  col : Int
  size : Int
  frame_width : Int
  frame_height : Int
}

/// A coding-block rectangle in pixels. Dimensions retain the coded block
/// size at frame edges; sample reconstruction is responsible for clipping.
pub(all) struct Av1SbBlock {
  row : Int
  col : Int
  width : Int
  height : Int
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
  av1_partition_node_valid(self) &&
  self.row + self.size / 2 < av1_partition_coded_extent(self.frame_height)
}

/// Whether the right half of this block lies inside the frame (AV1 `hasCols`).
pub fn Av1SbPartitionNode::has_cols(self : Av1SbPartitionNode) -> Bool {
  av1_partition_node_valid(self) &&
  self.col + self.size / 2 < av1_partition_coded_extent(self.frame_width)
}

/// True when the node has no complete lower or right half.  AV1 forces a
/// split in this case, avoiding a partition symbol that would address pixels
/// outside the frame.
pub fn Av1SbPartitionNode::edge_forces_split(self : Av1SbPartitionNode) -> Bool {
  av1_partition_node_valid(self) && self.size >= 8 &&
  !self.has_rows() && !self.has_cols()
}

/// MiCols/MiRows are twice the frame dimension rounded up to eight pixels.
fn av1_partition_coded_extent(pixels : Int) -> Int {
  ((pixels + 7) / 8) * 8
}

///|
fn av1_partition_node_valid(node : Av1SbPartitionNode) -> Bool {
  node.size >= 4 && node.size <= 128 && (node.size & (node.size - 1)) == 0 &&
  node.row >= 0 && node.col >= 0 && node.row % 4 == 0 && node.col % 4 == 0 &&
  node.row <= 2147483647 - node.size && node.col <= 2147483647 - node.size &&
  node.frame_width > 0 && node.frame_width <= 2147483640 &&
  node.frame_height > 0 && node.frame_height <= 2147483640
}

///|
fn av1_partition_symbol_allowed(
  node : Av1SbPartitionNode,
  partition : Av1SbPartition,
) -> Bool {
  if !av1_partition_node_valid(node) { return false }
  if node.size == 4 { return partition is Av1SbPartitionNone }
  if node.edge_forces_split() { return partition is Av1SbPartitionSplit }
  if !node.has_rows() {
    return partition is Av1SbPartitionHorz || partition is Av1SbPartitionSplit
  }
  if !node.has_cols() {
    return partition is Av1SbPartitionVert || partition is Av1SbPartitionSplit
  }
  match partition {
    Av1SbPartitionNone | Av1SbPartitionHorz | Av1SbPartitionVert | Av1SbPartitionSplit => true
    Av1SbPartitionHorz4 | Av1SbPartitionVert4 => node.size >= 16 && node.size <= 64
    _ => node.size >= 16
  }
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

/// AV1 partitionCtx: above_size is the above coding block's width; left_size
/// is the left coding block's height. Unavailable tile neighbours are None.
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

fn av1_partition_push_block(
  out : Array[Av1SbBlock],
  node : Av1SbPartitionNode,
  row : Int,
  col : Int,
  width : Int,
  height : Int,
) -> Unit {
  if row < av1_partition_coded_extent(node.frame_height) &&
    col < av1_partition_coded_extent(node.frame_width) {
    out.push({ row, col, width, height })
  }
}

/// Return coding-block rectangles in AV1 syntax order. SPLIT rectangles are
/// square recursive nodes; all other results are terminal blocks. Origins
/// outside the MI grid are omitted, while partial edge blocks keep their
/// full coded dimensions. Invalid geometry or partition combinations return [].
pub fn av1_partition_children(
  node : Av1SbPartitionNode,
  partition : Av1SbPartition,
) -> Array[Av1SbBlock] {
  if !av1_partition_symbol_allowed(node, partition) { return [] }
  let size = node.size
  let half = node.size / 2
  let out : Array[Av1SbBlock] = []
  match partition {
    Av1SbPartitionNone => av1_partition_push_block(out, node, node.row, node.col, size, size)
    Av1SbPartitionHorz => {
      av1_partition_push_block(out, node, node.row, node.col, size, half)
      av1_partition_push_block(out, node, node.row + half, node.col, size, half)
    }
    Av1SbPartitionVert => {
      av1_partition_push_block(out, node, node.row, node.col, half, size)
      av1_partition_push_block(out, node, node.row, node.col + half, half, size)
    }
    Av1SbPartitionSplit => {
      av1_partition_push_block(out, node, node.row, node.col, half, half)
      av1_partition_push_block(out, node, node.row, node.col + half, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col + half, half, half)
    }
    Av1SbPartitionHorzA => {
      av1_partition_push_block(out, node, node.row, node.col, half, half)
      av1_partition_push_block(out, node, node.row, node.col + half, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col, size, half)
    }
    Av1SbPartitionHorzB => {
      av1_partition_push_block(out, node, node.row, node.col, size, half)
      av1_partition_push_block(out, node, node.row + half, node.col, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col + half, half, half)
    }
    Av1SbPartitionVertA => {
      av1_partition_push_block(out, node, node.row, node.col, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col, half, half)
      av1_partition_push_block(out, node, node.row, node.col + half, half, size)
    }
    Av1SbPartitionVertB => {
      av1_partition_push_block(out, node, node.row, node.col, half, size)
      av1_partition_push_block(out, node, node.row, node.col + half, half, half)
      av1_partition_push_block(out, node, node.row + half, node.col + half, half, half)
    }
    Av1SbPartitionHorz4 => {
      let quarter = size / 4
      for i in 0..<4 {
        av1_partition_push_block(out, node, node.row + i * quarter, node.col, size, quarter)
      }
    }
    Av1SbPartitionVert4 => {
      let quarter = size / 4
      for i in 0..<4 {
        av1_partition_push_block(out, node, node.row, node.col + i * quarter, quarter, size)
      }
    }
  }
  out
}

/// Walk signalled partition decisions in AV1 syntax order. Implied 4x4 NONE
/// and forced frame-edge SPLIT decisions consume no entries. Only SPLIT
/// recurses; rectangular and A/B partition blocks are terminal.
pub fn av1_partition_leaves(
  root : Av1SbPartitionNode,
  partitions : Array[Av1SbPartition],
) -> Array[Av1SbBlock]? {
  let cursor : Ref[Int] = { val: 0 }
  let out : Array[Av1SbBlock] = []
  let complete = av1_walk_partition_geometry(
    root,
    fn(_) {
      if cursor.val >= partitions.length() { return None }
      let partition = partitions[cursor.val]
      cursor.val = cursor.val + 1
      Some(partition)
    },
    fn(block) { out.push(block); true },
  )
  if complete && cursor.val == partitions.length() {
    Some(out)
  } else {
    None
  }
}

/// Shared syntax-order traversal for the entropy reader and geometry probes.
fn av1_walk_partition_geometry(
  node : Av1SbPartitionNode,
  read_partition : (Av1SbPartitionNode) -> Av1SbPartition?,
  decode_leaf : (Av1SbBlock) -> Bool,
) -> Bool {
  if !av1_partition_node_valid(node) { return false }
  if node.row >= av1_partition_coded_extent(node.frame_height) ||
    node.col >= av1_partition_coded_extent(node.frame_width) {
    return true
  }
  let partition = if node.size == 4 {
    Av1SbPartitionNone
  } else if node.edge_forces_split() {
    Av1SbPartitionSplit
  } else {
    match read_partition(node) {
      Some(value) => value
      None => return false
    }
  }
  let blocks = av1_partition_children(node, partition)
  if blocks.length() == 0 { return false }
  for block in blocks {
    if partition is Av1SbPartitionSplit {
      let child = av1_partition_node(
        block.row, block.col, block.width, node.frame_width, node.frame_height,
      )
      if !av1_walk_partition_geometry(child, read_partition, decode_leaf) { return false }
    } else if !decode_leaf(block) {
      return false
    }
  }
  true
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

/// Coding-block dimensions at each 4x4 position in one tile. The tile bounds
/// are in pixels on the MI grid, which may extend past visible frame pixels.
/// Dimensions are recorded after the corresponding leaf callback succeeds.
priv struct Av1PartitionNeighbors {
  tile : Av1SbBlock
  frame_width : Int
  frame_height : Int
  cols : Int
  rows : Int
  block_widths : Array[Int]
  block_heights : Array[Int]
}

///|
fn av1_partition_neighbor_state(
  tile : Av1SbBlock,
  frame_width : Int,
  frame_height : Int,
) -> Av1PartitionNeighbors? {
  if frame_width <= 0 || frame_width > 2147483640 ||
    frame_height <= 0 || frame_height > 2147483640 ||
    tile.row < 0 || tile.col < 0 || tile.width <= 0 || tile.height <= 0 ||
    tile.row % 4 != 0 || tile.col % 4 != 0 ||
    tile.width % 4 != 0 || tile.height % 4 != 0 ||
    tile.row > av1_partition_coded_extent(frame_height) - tile.height ||
    tile.col > av1_partition_coded_extent(frame_width) - tile.width {
    return None
  }
  let cols = tile.width / 4
  let rows = tile.height / 4
  if cols > 2147483647 / rows { return None }
  Some({
    tile,
    frame_width,
    frame_height,
    cols,
    rows,
    block_widths: Array::make(cols * rows, -1),
    block_heights: Array::make(cols * rows, -1),
  })
}

///|
fn av1_partition_node_in_tile(
  state : Av1PartitionNeighbors,
  node : Av1SbPartitionNode,
) -> Bool {
  if !av1_partition_node_valid(node) ||
    node.frame_width != state.frame_width || node.frame_height != state.frame_height {
    return false
  }
  let end_row = state.tile.row + state.tile.height
  let end_col = state.tile.col + state.tile.width
  node.row >= state.tile.row && node.col >= state.tile.col &&
  node.row < end_row && node.col < end_col &&
  (node.row + node.size <= end_row || end_row == av1_partition_coded_extent(state.frame_height)) &&
  (node.col + node.size <= end_col || end_col == av1_partition_coded_extent(state.frame_width))
}

/// Read the coding-block width immediately above and height immediately left
/// of this square node. A missing record inside the tile is a traversal error.
fn av1_partition_neighbor_context(
  state : Av1PartitionNeighbors,
  node : Av1SbPartitionNode,
) -> Int? {
  if !av1_partition_node_in_tile(state, node) { return None }
  let x4 = (node.col - state.tile.col) / 4
  let y4 = (node.row - state.tile.row) / 4
  let above = if y4 == 0 {
    None
  } else {
    let width = state.block_widths[(y4 - 1) * state.cols + x4]
    if width < 0 { return None }
    Some(width)
  }
  let left = if x4 == 0 {
    None
  } else {
    let height = state.block_heights[y4 * state.cols + x4 - 1]
    if height < 0 { return None }
    Some(height)
  }
  Some(av1_partition_context(node.size, above, left))
}

/// Record the full coded dimensions over the block's in-frame MI footprint.
fn av1_partition_record_block(state : Av1PartitionNeighbors, block : Av1SbBlock) -> Bool {
  let width = block.width
  let height = block.height
  let max_size = if width > height { width } else { height }
  let min_size = if width < height { width } else { height }
  if width < 4 || height < 4 || width > 128 || height > 128 ||
    (width & (width - 1)) != 0 || (height & (height - 1)) != 0 ||
    max_size > min_size * 4 || (max_size == 128 && min_size < 64) ||
    block.row < state.tile.row || block.col < state.tile.col ||
    block.row % 4 != 0 || block.col % 4 != 0 ||
    block.row >= state.tile.row + state.tile.height ||
    block.col >= state.tile.col + state.tile.width {
    return false
  }
  let x4 = (block.col - state.tile.col) / 4
  let y4 = (block.row - state.tile.row) / 4
  let end_x = if x4 + width / 4 > state.cols { state.cols } else { x4 + width / 4 }
  let end_y = if y4 + height / 4 > state.rows { state.rows } else { y4 + height / 4 }
  for y in y4..<end_y {
    for x in x4..<end_x {
      state.block_widths[y * state.cols + x] = width
      state.block_heights[y * state.cols + x] = height
    }
  }
  true
}

fn av1_decode_partition_symbol(
  decoder : Av1SymbolDecoder,
  state : Av1PartitionCdfState,
  node : Av1SbPartitionNode,
  neighbors : Av1PartitionNeighbors,
) -> Av1SbPartition? {
  if !av1_partition_node_in_tile(neighbors, node) { return None }
  if node.size == 4 { return Some(Av1SbPartitionNone) }
  if node.edge_forces_split() { return Some(Av1SbPartitionSplit) }
  let context = match av1_partition_neighbor_context(neighbors, node) {
    Some(value) => value
    None => return None
  }
  let rows = av1_partition_cdf_rows(state, node.size)
  let cdf = rows[context]
  if !node.has_rows() || !node.has_cols() {
    return av1_partition_edge_symbol(decoder, cdf, node.has_rows(), node.has_cols())
  }
  av1_partition_symbol_from_index(decoder.symbol(cdf))
}

/// Decode a superblock with one shared MSAC and tile CDF/neighbor state.
/// Each terminal block is decoded synchronously before recording its coding
/// dimensions and reading the next partition symbol. The callback consumes
/// mode, transform and residual syntax from the supplied decoder. Returning
/// false aborts immediately; callers discard decoder/context state on failure.
fn av1_walk_partition_tree(
  decoder : Av1SymbolDecoder,
  cdfs : Av1PartitionCdfState,
  neighbors : Av1PartitionNeighbors,
  root : Av1SbPartitionNode,
  decode_leaf : (Av1SymbolDecoder, Av1SbBlock) -> Bool,
) -> Bool {
  if !av1_partition_node_in_tile(neighbors, root) { return false }
  av1_walk_partition_geometry(
    root,
    fn(node) { av1_decode_partition_symbol(decoder, cdfs, node, neighbors) },
    fn(block) {
      decode_leaf(decoder, block) && av1_partition_record_block(neighbors, block)
    },
  ) && decoder.symbol_max_bits >= -14
}

/// Decode an isolated partition-only probe, with fresh CDFs and unavailable
/// external neighbours. Payloads contain partition symbols only: real tile
/// mode and residual syntax must be consumed by the shared callback walker.
/// The root is fixed at 64 pixels, or 128 when use_128x128_superblock is true.
/// This probe accepts at most one root's frame extent and returns complete
/// coded rectangles, including the MI padding beyond visible frame pixels.
pub fn av1_decode_partition_leaves(
  tile_payload : Array[Byte],
  frame_width : Int,
  frame_height : Int,
  disable_cdf_update? : Bool = false,
  use_128x128_superblock? : Bool = false,
) -> Array[Av1SbBlock]? {
  let root_size = if use_128x128_superblock { 128 } else { 64 }
  if tile_payload.length() == 0 || frame_width <= 0 || frame_height <= 0 ||
    frame_width > root_size || frame_height > root_size {
    return None
  }
  let root = av1_partition_node(0, 0, root_size, frame_width, frame_height)
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  let neighbors = match av1_partition_neighbor_state(
    {
      row: 0,
      col: 0,
      width: av1_partition_coded_extent(frame_width),
      height: av1_partition_coded_extent(frame_height),
    },
    frame_width,
    frame_height,
  ) {
    Some(value) => value
    None => return None
  }
  let leaves : Array[Av1SbBlock] = []
  if av1_walk_partition_tree(
    decoder, av1_partition_cdf_state(), neighbors, root,
    fn(_, block) { leaves.push(block); true },
  ) { Some(leaves) } else { None }
}
