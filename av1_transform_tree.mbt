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

/// Neighbour transform dimensions collected while walking a tile in raster
/// order.  Entries are indexed in 4x4 units; `-1` means that no block has
/// been decoded at that edge yet.  Keeping unavailable edges explicit avoids
/// manufacturing neighbour sizes for the first block in a tile.
pub struct Av1TxTraversalState {
  cols : Int
  rows : Int
  above_width : Array[Int]
  left_height : Array[Int]
}

/// Create empty neighbour state for one tile.  The state is intentionally
/// independent from the entropy CDF state so callers can reuse it across
/// blocks without resetting tx_depth adaptation.
pub fn av1_tx_traversal_state(width : Int, height : Int) -> Av1TxTraversalState {
  let cols = if width > 0 { (width + 3) / 4 } else { 0 }
  let rows = if height > 0 { (height + 3) / 4 } else { 0 }
  {
    cols,
    rows,
    above_width: Array::make(cols, -1),
    left_height: Array::make(rows, -1),
  }
}

/// Derive tx_depth context from dimensions of the blocks immediately above
/// and to the left of `node`.  Missing edges remain `-1` and contribute zero.
pub fn av1_tx_depth_context_for_node(
  state : Av1TxTraversalState,
  node : Av1TxNode,
) -> Int {
  let x4 = node.col / 4
  let y4 = node.row / 4
  let w4 = if node.width > 0 { (node.width + 3) / 4 } else { 0 }
  let h4 = if node.height > 0 { (node.height + 3) / 4 } else { 0 }
  let mut above = -1
  if y4 > 0 {
    for i in 0..<w4 {
      let x = x4 + i
      if x >= 0 && x < state.cols && state.above_width[x] > above {
        above = state.above_width[x]
      }
    }
  }
  let mut left = -1
  if x4 > 0 {
    for i in 0..<h4 {
      let y = y4 + i
      if y >= 0 && y < state.rows && state.left_height[y] > left {
        left = state.left_height[y]
      }
    }
  }
  av1_tx_depth_context_from_sizes(above, left, node.width, node.height)
}

/// Record a decoded block's dimensions for subsequent raster neighbours.
pub fn av1_tx_traversal_record(state : Av1TxTraversalState, node : Av1TxNode) -> Unit {
  let x4 = node.col / 4
  let y4 = node.row / 4
  let w4 = if node.width > 0 { (node.width + 3) / 4 } else { 0 }
  let h4 = if node.height > 0 { (node.height + 3) / 4 } else { 0 }
  for i in 0..<w4 {
    let x = x4 + i
    if x >= 0 && x < state.cols {
      state.above_width[x] = node.width
    }
  }
  for i in 0..<h4 {
    let y = y4 + i
    if y >= 0 && y < state.rows {
      state.left_height[y] = node.height
    }
  }
}

/// Decode the bounded tx_depth symbol used when frame tx_mode_select is set.
/// The context table is reduced to the three validated default rows until the
/// full neighbour-derived 21-context table is wired into block traversal.
/// Mutable tx-depth CDFs retained for the lifetime of a tile.  AV1 adapts
/// these rows after every symbol; keeping them in a caller-owned state avoids
/// resetting adaptation for each block.
pub struct Av1TxDepthState {
  cdf16 : Array[Array[Int]]
  cdf32 : Array[Array[Int]]
  cdf64 : Array[Array[Int]]
}

fn av1_tx_depth_state() -> Av1TxDepthState {
  {
    cdf16: [[12272, 30172, 32768, 0], [12272, 30172, 32768, 0], [18677, 30848, 32768, 0]],
    cdf32: [[12986, 15180, 32768, 0], [12986, 15180, 32768, 0], [24302, 25602, 32768, 0]],
    cdf64: [[5782, 11475, 32768, 0], [5782, 11475, 32768, 0], [16803, 22759, 32768, 0]],
  }
}

/// Derive the reduced tx-depth context from neighbouring block depths.  The
/// full AV1 table has 21 geometry-specific rows; this package currently uses
/// three validated rows, where each neighbour contributes one level of split
/// evidence.  Callers should pass -1 for an unavailable edge.
pub fn av1_tx_depth_context_from_neighbors(above_depth : Int, left_depth : Int) -> Int {
  let above = if above_depth > 0 { 1 } else { 0 }
  let left = if left_depth > 0 { 1 } else { 0 }
  above + left
}

/// Derive the tx_depth context from the transform dimensions recorded for
/// the neighbouring blocks (AV1 spec section 8.3).  The syntax context is a
/// pair of independent flags: one for an above neighbour whose transform
/// width reaches the current maximum width, and one for a left neighbour whose
/// transform height reaches the current maximum height.  A negative dimension
/// denotes an unavailable edge and contributes zero.
pub fn av1_tx_depth_context_from_sizes(
  above_width : Int,
  left_height : Int,
  max_tx_width : Int,
  max_tx_height : Int,
) -> Int {
  if max_tx_width <= 0 || max_tx_height <= 0 {
    return 0
  }
  let above = if above_width >= max_tx_width && above_width >= 0 { 1 } else { 0 }
  let left = if left_height >= max_tx_height && left_height >= 0 { 1 } else { 0 }
  above + left
}

fn av1_decode_tx_depth_with_state(
  decoder : Av1SymbolDecoder,
  state : Av1TxDepthState,
  max_size : Int,
  context : Int,
) -> Int? {
  // 4x4 roots have no tx_depth syntax; depth zero is implied by geometry.
  if max_size < 16 {
    return Some(0)
  }
  let ctx = if context < 0 { 0 } else if context > 2 { 2 } else { context }
  let cdf : Array[Int] = if max_size >= 64 {
    state.cdf64[ctx]
  } else if max_size >= 32 {
    state.cdf32[ctx]
  } else if max_size >= 16 {
    state.cdf16[ctx]
  } else {
    [19968, 32768, 0]
  }
  let depth = decoder.symbol(cdf)
  let max_depth = if max_size >= 64 { 3 } else if max_size >= 32 { 2 } else if max_size >= 16 { 1 } else { 0 }
  if depth < 0 || depth > max_depth { None } else { Some(depth) }
}

fn av1_decode_tx_depth(
  decoder : Av1SymbolDecoder,
  max_size : Int,
  context : Int,
) -> Int? {
  av1_decode_tx_depth_with_state(decoder, av1_tx_depth_state(), max_size, context)
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
  av1_decode_tx_tree_with_state(decoder, av1_tx_depth_state(), root, context)
}

/// Stateful variant used by tile traversal; the wrapper above remains for
/// compatibility with existing callers and isolated tests.
fn av1_decode_tx_tree_with_state(
  decoder : Av1SymbolDecoder,
  state : Av1TxDepthState,
  root : Av1TxNode,
  context : Int,
) -> Array[Av1TxLeaf]? {
  let max_size = if root.width > root.height { root.width } else { root.height }
  let depth = match av1_decode_tx_depth_with_state(decoder, state, max_size, context) {
    Some(value) => value
    None => return None
  }

  let out : Array[Av1TxLeaf] = []
  if av1_tx_depth_leaves(root, depth, 0, out) { Some(out) } else { None }
}

/// Read one leaf's coefficients while sharing one mutable MSAC reader and
/// coefficient CDF context. `scan_class` selects the coefficient scan ordered
/// by the leaf's transform type; `dc_sign_ctx` is the neighbour dc-sign
/// context (0..2).
fn av1_tx_decode_leaf_nodes(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  context : Av1CoeffContext,
  leaves : Array[Av1TxLeaf],
  bit_depth : Int,
  scan_class? : Int = AV1_SCAN_DEFAULT,
  dc_sign_ctx? : Int = 0,
) -> Array[Av1LeafCoeffs]? {
  if leaves.length() == 0 { return None }
  let out : Array[Av1LeafCoeffs] = []
  for leaf in leaves {
    let side = leaf.node.width
    let height = leaf.node.height
    if !((side == height && (side == 4 || side == 8 || side == 16 || side == 32 || side == 64)) ||
      (side == 32 && height == 16) || (side == 16 && height == 32)) {
      return None
    }
    let leaf_coeffs = if (side == 32 && height == 16) || (side == 16 && height == 32) {
      context.tx_ctx = 3
      av1_decode_coeffs_leaf_with_decoder(
        decoder, base_q_idx, context, side, bit_depth~, scan_class~, dc_sign_ctx~, height~,
      )
    } else if side <= 16 {
      context.tx_ctx = if side == 16 { 2 } else if side == 8 { 1 } else { 0 }
      av1_decode_coeffs_leaf_with_decoder(
        decoder, base_q_idx, context, side, bit_depth~, scan_class~, dc_sign_ctx~,
      )
    } else {
      context.tx_ctx = if side == 64 { 4 } else { 3 }
      av1_decode_coeffs_leaf_with_decoder(
        decoder, base_q_idx, context, side, bit_depth~, scan_class~, dc_sign_ctx~,
      )
    }
    match leaf_coeffs {
      Some(value) => out.push(value)
      None => return None
    }
  }
  Some(out)
}

///|
/// Transform set for an intra transform block (AV1 spec get_tx_set):
/// 0 = DCT only (32x32 and larger), 1 = seven-symbol set, 2 = five-symbol set
/// (16x16 leaves, or every size under a reduced_tx_set frame header).
fn av1_intra_tx_set(side : Int, reduced_tx_set : Bool) -> Int {
  if side > 32 {
    return 0
  }
  if side == 32 {
    return 0
  }
  if side == 16 {
    return 2
  }
  if reduced_tx_set {
    return 2
  }
  1
}

///|
/// Map a TX_SET_INTRA_1 symbol to its transform type (AV1 spec
/// Tx_Type_Intra_Inv_Set1: IDTX, DCT_DCT, V_DCT, H_DCT, ADST_ADST,
/// ADST_DCT, DCT_ADST).
fn av1_tx_type_intra_set1(symbol : Int) -> Av1TxType? {
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

///|
/// Map a TX_SET_INTRA_2 symbol to its transform type (AV1 spec
/// Tx_Type_Intra_Inv_Set2: IDTX, DCT_DCT, ADST_ADST, ADST_DCT, DCT_ADST).
fn av1_tx_type_intra_set2(symbol : Int) -> Av1TxType? {
  match symbol {
    0 => Some(Av1TxIdentityIdentity)
    1 => Some(Av1TxDctDct)
    2 => Some(Av1TxAdstAdst)
    3 => Some(Av1TxAdstDct)
    4 => Some(Av1TxDctAdst)
    _ => None
  }
}

///|
/// Filter-intra modes remap to the intra direction used for the tx_type CDF
/// context (AV1 spec Filter_Intra_Mode_To_Intra_Dir): DC, V, H, D157, DC.
fn av1_filter_intra_mode_to_intra_dir(mode : Int) -> Int? {
  match mode {
    0 => Some(0)
    1 => Some(1)
    2 => Some(2)
    3 => Some(6)
    4 => Some(0)
    _ => None
  }
}

///|
/// Chroma transform type derived from the UV intra mode (AV1 spec
/// mode_to_txfm). D65..D113 directional rows follow the spec table order:
/// DC, V, H, D45, D135, D113, D157, D203, D67, SMOOTH, SMOOTH_V, SMOOTH_H,
/// PAETH.
fn av1_mode_to_txfm(mode : Int) -> Av1TxType? {
  match mode {
    0 => Some(Av1TxDctDct)
    1 => Some(Av1TxAdstDct)
    2 => Some(Av1TxDctAdst)
    3 => Some(Av1TxDctDct)
    4 => Some(Av1TxAdstAdst)
    5 => Some(Av1TxAdstDct)
    6 => Some(Av1TxDctAdst)
    7 => Some(Av1TxDctAdst)
    8 => Some(Av1TxAdstDct)
    9 => Some(Av1TxAdstAdst)
    10 => Some(Av1TxAdstDct)
    11 => Some(Av1TxDctAdst)
    12 => Some(Av1TxAdstAdst)
    _ => None
  }
}

///|
/// Whether a transform type belongs to the given intra transform set.
fn av1_tx_type_in_set(tx_type : Av1TxType, set : Int) -> Bool {
  if set == 0 {
    return tx_type is Av1TxDctDct
  }
  match tx_type {
    Av1TxDctDct => true
    Av1TxIdentityIdentity => true
    Av1TxAdstAdst => true
    Av1TxAdstDct => true
    Av1TxDctAdst => true
    Av1TxVerticalDct => set == 1
    Av1TxHorizontalDct => set == 1
    _ => false
  }
}

///|
/// Read the luma intra_tx_type symbol for one transform leaf (AV1 spec
/// transform_type). The symbol is consumed only when the transform set is
/// non-empty and the effective quantizer is non-zero; otherwise DCT_DCT is
/// implied. `intra_dir` is the luma prediction direction (remapped through
/// filter-intra when that tool is active).
fn av1_decode_intra_tx_type(
  decoder : Av1SymbolDecoder,
  tables : Av1TxEntTables,
  side : Int,
  intra_dir : Int,
  reduced_tx_set : Bool,
  effective_qidx : Int,
) -> Av1TxType? {
  let set = av1_intra_tx_set(side, reduced_tx_set)
  if set == 0 || effective_qidx <= 0 {
    return Some(Av1TxDctDct)
  }
  if intra_dir < 0 || intra_dir > 12 {
    return None
  }
  let symbol = if set == 1 {
    decoder.symbol(tables.tx_set1[if side == 4 { 0 } else { 1 }][intra_dir])
  } else {
    let row = if side == 4 {
      0
    } else if side == 8 {
      1
    } else {
      2
    }
    decoder.symbol(tables.tx_set2[row][intra_dir])
  }
  if set == 1 {
    av1_tx_type_intra_set1(symbol)
  } else {
    av1_tx_type_intra_set2(symbol)
  }
}

///|
/// Derive the chroma transform type from the UV mode without consuming a
/// symbol (AV1 spec compute_tx_type). Types outside the chroma's set fall
/// back to DCT_DCT.
fn av1_chroma_tx_type(
  uv_mode : Int,
  side : Int,
  reduced_tx_set : Bool,
) -> Av1TxType? {
  let set = av1_intra_tx_set(side, reduced_tx_set)
  if set == 0 {
    return Some(Av1TxDctDct)
  }
  let candidate = match av1_mode_to_txfm(uv_mode) {
    Some(value) => value
    None => return None
  }
  if av1_tx_type_in_set(candidate, set) {
    Some(candidate)
  } else {
    Some(Av1TxDctDct)
  }
}

///|
/// Scan class selected by a transform type: vertical/horizontal 1D types use
/// the matching scan order; everything else uses the default diagonal.
fn av1_tx_scan_class(tx_type : Av1TxType) -> Int {
  match tx_type {
    Av1TxVerticalDct | Av1TxVerticalAdst | Av1TxVerticalFlipadst => AV1_SCAN_VERT
    Av1TxHorizontalDct | Av1TxHorizontalAdst | Av1TxHorizontalFlipadst => AV1_SCAN_HORZ
    _ => AV1_SCAN_DEFAULT
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
    if !((leaf.width == leaf.height && (leaf.width == 4 || leaf.width == 8 || leaf.width == 16 ||
      leaf.width == 32 || leaf.width == 64)) ||
      (leaf.width == 32 && leaf.height == 16) || (leaf.width == 16 && leaf.height == 32)) {
      return None
    }
    let coeffs = if (leaf.width == 32 && leaf.height == 16) || (leaf.width == 16 && leaf.height == 32) {
      context.tx_ctx = 3
      av1_decode_coeffs_leaf_with_decoder(
        decoder, base_q_idx, context, leaf.width, bit_depth=bit_depth, height=leaf.height,
      ).map(fn(value) { value.coeffs })
    } else if leaf.width <= 16 {
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

test "4x4 tx depth is implied without entropy read" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  let before = decoder.bit_pos
  assert_true(av1_decode_tx_depth(decoder, 4, 0) is Some(0))
  assert_eq(decoder.bit_pos, before)
}

test "tx depth CDF state adapts across blocks" {
  let decoder = av1_msac_new(Array::make(16, b'\x00'), true)
  let state = av1_tx_depth_state()
  let before = state.cdf32[0][3]
  ignore(av1_decode_tx_depth_with_state(decoder, state, 32, 0))
  ignore(av1_decode_tx_depth_with_state(decoder, state, 32, 0))
  assert_true(state.cdf32[0][3] > before)
}

test "tx depth context derives from neighbours" {
  assert_eq(av1_tx_depth_context_from_neighbors(-1, -1), 0)
  assert_eq(av1_tx_depth_context_from_neighbors(1, -1), 1)
  assert_eq(av1_tx_depth_context_from_neighbors(2, 3), 2)
}

test "tx depth context derives from neighbour transform sizes" {
  // Unavailable edges and transforms smaller than the root do not contribute.
  assert_eq(av1_tx_depth_context_from_sizes(-1, -1, 32, 32), 0)
  assert_eq(av1_tx_depth_context_from_sizes(16, 32, 32, 32), 1)
  assert_eq(av1_tx_depth_context_from_sizes(32, 32, 32, 32), 2)
  // Rectangular roots compare width and height independently.
  assert_eq(av1_tx_depth_context_from_sizes(32, 16, 32, 64), 1)
  assert_eq(av1_tx_depth_context_from_sizes(0, 0, 0, 32), 0)
}

///|
test "tx traversal state keeps unavailable edges explicit" {
  let state = av1_tx_traversal_state(64, 64)
  let first = { row: 0, col: 0, width: 32, height: 32 }
  assert_eq(av1_tx_depth_context_for_node(state, first), 0)
  av1_tx_traversal_record(state, first)
  // A block to the right sees the recorded left height; a block below sees
  // the recorded above width.  No dimensions are invented for other edges.
  assert_eq(
    av1_tx_depth_context_for_node(state, { row: 0, col: 32, width: 32, height: 32 }),
    1,
  )
  assert_eq(
    av1_tx_depth_context_for_node(state, { row: 32, col: 0, width: 32, height: 32 }),
    1,
  )
  av1_tx_traversal_record(state, { row: 0, col: 32, width: 32, height: 32 })
  av1_tx_traversal_record(state, { row: 32, col: 0, width: 32, height: 32 })
  assert_eq(
    av1_tx_depth_context_for_node(state, { row: 32, col: 32, width: 32, height: 32 }),
    2,
  )
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

test "intra tx type reader gates on qindex and transform set" {
  let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
  // Zero qindex implies DCT_DCT without consuming a symbol.
  assert_true(
    av1_decode_intra_tx_type(decoder, av1_tx_ent_tables(0), 4, 0, false, 0)
    is Some(Av1TxDctDct),
  )
  // 32x32 leaves are DCT-only for intra frames.
  assert_true(
    av1_decode_intra_tx_type(
      decoder, av1_tx_ent_tables(128), 32, 0, false, 128,
    )
    is Some(Av1TxDctDct),
  )
  // Non-zero qindex with 4x4/16x16 leaves consumes one symbol; all-zero
  // entropy decodes symbol zero (IDTX).
  assert_true(
    av1_decode_intra_tx_type(decoder, av1_tx_ent_tables(64), 4, 0, false, 64)
    is Some(Av1TxIdentityIdentity),
  )
  assert_true(
    av1_decode_intra_tx_type(decoder, av1_tx_ent_tables(64), 16, 0, false, 64)
    is Some(Av1TxIdentityIdentity),
  )
  assert_true(
    av1_decode_intra_tx_type(decoder, av1_tx_ent_tables(64), 8, 5, true, 64)
    is Some(_),
  )
}

///|
test "chroma tx type follows the uv mode table" {
  assert_true(av1_chroma_tx_type(0, 16, false) is Some(Av1TxDctDct))
  assert_true(av1_chroma_tx_type(1, 16, false) is Some(Av1TxAdstDct))
  assert_true(av1_chroma_tx_type(2, 16, false) is Some(Av1TxDctAdst))
  // 32x32 chroma transforms are DCT-only for intra frames.
  assert_true(av1_chroma_tx_type(1, 32, false) is Some(Av1TxDctDct))
}

///|
test "tx type scan class selects 1D scans" {
  assert_eq(av1_tx_scan_class(Av1TxDctDct), AV1_SCAN_DEFAULT)
  assert_eq(av1_tx_scan_class(Av1TxVerticalDct), AV1_SCAN_VERT)
  assert_eq(av1_tx_scan_class(Av1TxHorizontalAdst), AV1_SCAN_HORZ)
}

///|
test "tx type inverse sets reject out-of-range symbols" {
  assert_true(av1_tx_type_intra_set1(7) is None)
  assert_true(av1_tx_type_intra_set2(5) is None)
  assert_true(av1_filter_intra_mode_to_intra_dir(5) is None)
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
  assert_eq(result[0][0], 4)
}

///|
test "transform tree decodes multiple leaves with one CDF context" {
  let decoder = av1_msac_new(Array::make(128, b'\x00'), true)
  let leaves : Array[Av1TxLeaf] = [
    { node: { row: 0, col: 0, width: 4, height: 4 }, depth: 1 },
    { node: { row: 0, col: 4, width: 4, height: 4 }, depth: 1 },
  ]
  let result = av1_tx_decode_leaf_nodes(decoder, 0, av1_coeff_context(0, 0, 0), leaves, 8)
  assert_true(result is Some(_))
}

///|
test "transform tree decodes 32x16 rectangular coefficient leaf" {
  let decoder = av1_msac_new(Array::make(64, b'\x00'), true)
  let leaves : Array[Av1TxLeaf] = [
    { node: { row: 0, col: 0, width: 32, height: 16 }, depth: 0 },
  ]
  let result = av1_tx_decode_leaf_nodes(
    decoder, 0, av1_coeff_context(0, 0, 0), leaves, 8,
  )
  let coefficients = result.unwrap()
  assert_eq(coefficients.length(), 1)
  assert_eq(coefficients[0].coeffs.length(), 32 * 16)
}

///|
test "transform tree decodes the transposed 16x32 rectangular leaf" {
  let decoder = av1_msac_new(Array::make(64, b'\x00'), true)
  let leaves : Array[Av1TxLeaf] = [
    { node: { row: 0, col: 0, width: 16, height: 32 }, depth: 0 },
  ]
  let result = av1_tx_decode_leaf_nodes(
    decoder, 0, av1_coeff_context(0, 0, 0), leaves, 8,
  ).unwrap()
  assert_eq(result[0].coeffs.length(), 16 * 32)
}
