/// Bounded four-block AV1 reconstruction for a 64x64 luma plane.
///
/// This module assembles the four 32x32 children produced by a `SPLIT`
/// partition. Coefficient arrays are already dequantised integer transform
/// samples; entropy decoding remains in `av1_coeff_decode.mbt`. Chroma uses
/// four 16x16 children (4:2:0) and may be supplied as empty arrays for a
/// neutral 128 plane. The walker keeps prediction edges in raster order so
/// each child can reference reconstructed neighbours.

///| copy one reconstructed block into a plane, adding intra prediction.
fn av1_reconstruct_child(
  plane : Array[Int],
  frame_width : Int,
  frame_height : Int,
  child : Av1SbPartitionNode,
  mode : Int,
  coeffs : Array[Int],
  side : Int,
) -> Bool {
  av1_reconstruct_child_with_type(
    plane, frame_width, frame_height, child, mode, coeffs, side, Av1TxDctDct,
  )
}

fn av1_reconstruct_child_with_type(
  plane : Array[Int],
  frame_width : Int,
  frame_height : Int,
  child : Av1SbPartitionNode,
  mode : Int,
  coeffs : Array[Int],
  side : Int,
  tx_type : Av1TxType,
  bit_depth? : Int = 8,
) -> Bool {
  if child.size != side || child.row + side > frame_height || child.col + side > frame_width {
    return false
  }
  let above : Array[Int] = []
  let left : Array[Int] = []
  let have_above = child.row > 0
  let have_left = child.col > 0
  if have_above {
    for j in 0..<side {
      above.push(plane[(child.row - 1) * frame_width + child.col + j])
    }
  }
  if have_left {
    for i in 0..<side {
      left.push(plane[(child.row + i) * frame_width + child.col - 1])
    }
  }
  let prediction = match
    av1_intra_predict(
      mode,
      side,
      side,
      above,
      left,
      if have_above && have_left {
        plane[(child.row - 1) * frame_width + child.col - 1]
      } else {
        1 << (bit_depth - 1)
      },
      bit_depth,
      have_above~,
      have_left~,
    ) {
    Some(value) => value
    None => return false
  }
  let residual = match av1_reconstruct_block_with_type(coeffs, side, side, tx_type, bit_depth) {
    Some(value) => value
    None => return false
  }
  for y in 0..<side {
    for x in 0..<side {
      let idx = (child.row + y) * frame_width + child.col + x
      let value = prediction[y * side + x] + residual[y * side + x]
      let hi = (1 << bit_depth) - 1
      plane[idx] = if value < 0 { 0 } else if value > hi { hi } else { value }
    }
  }
  true
}

/// Reconstruct a rectangular transform leaf in raster order.
///
/// Superblock partition children are always square, but AV1 transform sizes
/// may be rectangular (4x8, 8x4, ...). Keep this path separate so the
/// square partition helper retains its simple `size` invariant while typed
/// transform assembly can consume the full rectangular coefficient plane.
fn av1_reconstruct_rect_leaf_with_type(
  plane : Array[Int],
  frame_width : Int,
  frame_height : Int,
  leaf : Av1TxLeaf,
  mode : Int,
  coeffs : Array[Int],
  tx_type : Av1TxType,
  bit_depth : Int,
) -> Bool {
  let row = leaf.node.row
  let col = leaf.node.col
  let width = leaf.node.width
  let height = leaf.node.height
  if row < 0 || col < 0 || width <= 0 || height <= 0 ||
    row + height > frame_height || col + width > frame_width ||
    coeffs.length() != width * height {
    return false
  }
  let above : Array[Int] = []
  let left : Array[Int] = []
  let have_above = row > 0
  let have_left = col > 0
  if have_above {
    for x in 0..<width { above.push(plane[(row - 1) * frame_width + col + x]) }
  }
  if have_left {
    for y in 0..<height { left.push(plane[(row + y) * frame_width + col - 1]) }
  }
  let top_left = if have_above && have_left {
    plane[(row - 1) * frame_width + col - 1]
  } else {
    1 << (bit_depth - 1)
  }
  let prediction = match av1_intra_predict(
    mode, width, height, above, left, top_left, bit_depth,
    have_above~, have_left~,
  ) {
    Some(value) => value
    None => return false
  }
  let residual = match av1_reconstruct_block_with_type(
    coeffs, width, height, tx_type, bit_depth,
  ) {
    Some(value) => value
    None => return false
  }
  let hi = (1 << bit_depth) - 1
  for y in 0..<height {
    for x in 0..<width {
      let idx = (row + y) * frame_width + col + x
      let value = prediction[y * width + x] + residual[y * width + x]
      plane[idx] = if value < 0 { 0 } else if value > hi { hi } else { value }
    }
  }
  true
}

/// Reconstruct luma from raster-ordered transform leaves.
pub fn av1_reconstruct_tx_luma(
  width : Int,
  height : Int,
  leaves : Array[Av1TxLeaf],
  coefficients : Array[Array[Int]],
  mode : Int,
  types : Array[Av1TxType],
  bit_depth? : Int = 8,
) -> Array[Int]? {
  if width <= 0 || height <= 0 || leaves.length() == 0 ||
    leaves.length() != coefficients.length() || leaves.length() != types.length() {
    return None
  }
  let plane : Array[Int] = Array::make(width * height, 1 << (bit_depth - 1))
  for i in 0..<leaves.length() {
    let leaf = leaves[i].node
    if leaf.row + leaf.height > height || leaf.col + leaf.width > width {
      return None
    }
    if leaf.width == leaf.height {
      let child = av1_partition_node(leaf.row, leaf.col, leaf.width, width, height)
      if !av1_reconstruct_child_with_type(
        plane, width, height, child, mode, coefficients[i], leaf.width, types[i], bit_depth=bit_depth,
      ) { return None }
    } else if !av1_reconstruct_rect_leaf_with_type(
      plane, width, height, leaves[i], mode, coefficients[i], types[i], bit_depth,
    ) { return None }
  }
  Some(plane)
}

/// Reconstruct one 4:2:0 chroma plane from 16×16 transform leaves.
pub fn av1_reconstruct_tx_chroma(
  leaves : Array[Av1TxLeaf],
  coefficients : Array[Array[Int]],
  mode : Int,
  types : Array[Av1TxType],
  size? : Int = 32,
  bit_depth? : Int = 8,
) -> Array[Int]? {
  av1_reconstruct_tx_luma(size, size, leaves, coefficients, mode, types, bit_depth~)
}

/// Compose typed transform leaves for Y/U/V into an RGBA image.
pub fn av1_reconstruct_tx_rgba(
  width : Int,
  height : Int,
  y_leaves : Array[Av1TxLeaf],
  y_coefficients : Array[Array[Int]],
  u_leaves : Array[Av1TxLeaf],
  u_coefficients : Array[Array[Int]],
  v_leaves : Array[Av1TxLeaf],
  v_coefficients : Array[Array[Int]],
  y_mode : Int,
  uv_mode : Int,
  y_types : Array[Av1TxType],
  u_types : Array[Av1TxType],
  v_types : Array[Av1TxType],
  bit_depth : Int,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  if width != height || (width != 32 && width != 64) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  let y = match av1_reconstruct_tx_luma(width, height, y_leaves, y_coefficients, y_mode, y_types, bit_depth~) {
    Some(value) => value
    None => return None
  }
  let u = match av1_reconstruct_tx_chroma(u_leaves, u_coefficients, uv_mode, u_types, size=width / 2, bit_depth~) {
    Some(value) => value
    None => return None
  }
  let v = match av1_reconstruct_tx_chroma(v_leaves, v_coefficients, uv_mode, v_types, size=width / 2, bit_depth~) {
    Some(value) => value
    None => return None
  }
  av1_yuv420_highbd_to_rgba(
    width, height, y, u, v,
    bit_depth, full_range~, matrix_coefficients~,
  )
}

///| convert an integer plane to bytes without allocating per sample.
fn av1_plane_bytes(values : Array[Int]) -> Array[Byte] {
  let out : Array[Byte] = []
  for value in values {
    out.push(clamp_byte(value))
  }
  out
}

///| four-way 64x64 split reconstruction returning planar 8-bit YUV420.
///
/// `y_coeffs` contains four 32x32 dequantised coefficient blocks in the order
/// returned by `av1_partition_children(SPLIT)`. U and V contain four 16x16
/// blocks; an empty array means that the corresponding chroma plane is neutral.
/// Modes are intra mode numbers (DC/V/H/PAETH/SMOOTH variants). This bounded
/// path rejects non-four-way geometry and malformed block lengths.
pub fn av1_reconstruct_split_yuv420(
  y_coeffs : Array[Array[Int]],
  u_coeffs : Array[Array[Int]],
  v_coeffs : Array[Array[Int]],
  y_modes : Array[Int],
  u_modes : Array[Int],
  v_modes : Array[Int],
) -> (Array[Byte], Array[Byte], Array[Byte])? {
  if y_coeffs.length() != 4 || y_modes.length() != 4 ||
    (u_coeffs.length() != 0 && u_coeffs.length() != 4) ||
    (v_coeffs.length() != 0 && v_coeffs.length() != 4) ||
    (u_coeffs.length() == 4 && u_modes.length() != 4) ||
    (v_coeffs.length() == 4 && v_modes.length() != 4) {
    return None
  }
  let root = av1_partition_node(0, 0, 64, 64, 64)
  let children = av1_partition_children(root, Av1SbPartitionSplit)
  if children.length() != 4 {
    return None
  }
  let y_plane : Array[Int] = Array::make(64 * 64, 128)
  for i in 0..<4 {
    if !av1_reconstruct_child(y_plane, 64, 64, children[i], y_modes[i], y_coeffs[i], 32) {
      return None
    }
  }
  let chroma_children : Array[Av1SbPartitionNode] = []
  for child in children {
    chroma_children.push(av1_partition_node(child.row / 2, child.col / 2, 16, 32, 32))
  }
  let u_plane : Array[Int] = Array::make(32 * 32, 128)
  let v_plane : Array[Int] = Array::make(32 * 32, 128)
  if u_coeffs.length() == 4 {
    for i in 0..<4 {
      if !av1_reconstruct_child(u_plane, 32, 32, chroma_children[i], u_modes[i], u_coeffs[i], 16) {
        return None
      }
    }
  }
  if v_coeffs.length() == 4 {
    for i in 0..<4 {
      if !av1_reconstruct_child(v_plane, 32, 32, chroma_children[i], v_modes[i], v_coeffs[i], 16) {
        return None
      }
    }
  }
  Some((av1_plane_bytes(y_plane), av1_plane_bytes(u_plane), av1_plane_bytes(v_plane)))
}

///| reconstruct a 64x64 RGBA image from four split luma children.
pub fn av1_reconstruct_split_64x64(
  y_coeffs : Array[Array[Int]],
  u_coeffs : Array[Array[Int]],
  v_coeffs : Array[Array[Int]],
  y_modes : Array[Int],
  u_modes : Array[Int],
  v_modes : Array[Int],
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  let (y, u, v) = match
    av1_reconstruct_split_yuv420(y_coeffs, u_coeffs, v_coeffs, y_modes, u_modes, v_modes) {
    Some(value) => value
    None => return None
  }
  av1_yuv420_to_rgba_color(64, 64, y, u, v, full_range~, matrix_coefficients~)
}

///| zero-residual split produces a neutral 64x64 frame in full-range mode.
test "split reconstruction walks four children in raster order" {
  let block = Array::make(32 * 32, 0)
  let blocks : Array[Array[Int]] = [block.copy(), block.copy(), block.copy(), block.copy()]
  let (y, u, v) = av1_reconstruct_split_yuv420(
    blocks,
    [],
    [],
    [AV1_INTRA_DC, AV1_INTRA_DC, AV1_INTRA_DC, AV1_INTRA_DC],
    [],
    [],
  ).unwrap()
  assert_eq(y.length(), 4096)
  assert_eq(u.length(), 1024)
  assert_eq(v.length(), 1024)
  assert_eq(y[0].to_int(), 128)
  assert_eq(y[63].to_int(), 128)
  assert_eq(y[4095].to_int(), 128)
}

///| malformed child arrays are rejected before transform allocation.
test "split reconstruction rejects malformed child blocks" {
  let block = Array::make(32 * 32, 0)
  assert_eq(
    av1_reconstruct_split_yuv420(
      [block.copy(), block.copy(), block.copy(), Array::make(3, 0)],
      [],
      [],
      [0, 0, 0, 0],
      [],
      [],
    ),
    None,
  )
}

/// Reconstruct a four-way 4:2:0 split while carrying transform types per
/// plane and child. This is the typed counterpart to the legacy DCT_DCT API.
pub fn av1_reconstruct_split_yuv420_with_types(
  y_coeffs : Array[Array[Int]],
  u_coeffs : Array[Array[Int]],
  v_coeffs : Array[Array[Int]],
  y_modes : Array[Int],
  u_modes : Array[Int],
  v_modes : Array[Int],
  y_types : Array[Av1TxType],
  u_types : Array[Av1TxType],
  v_types : Array[Av1TxType],
) -> (Array[Byte], Array[Byte], Array[Byte])? {
  if y_coeffs.length() != 4 || y_modes.length() != 4 || y_types.length() != 4 {
    return None
  }
  let root = av1_partition_node(0, 0, 64, 64, 64)
  let children = av1_partition_children(root, Av1SbPartitionSplit)
  let y_plane : Array[Int] = Array::make(64 * 64, 128)
  for i in 0..<4 {
    if !av1_reconstruct_child_with_type(y_plane, 64, 64, children[i], y_modes[i], y_coeffs[i], 32, y_types[i]) {
      return None
    }
  }
  let u_plane : Array[Int] = Array::make(32 * 32, 128)
  let v_plane : Array[Int] = Array::make(32 * 32, 128)
  let chroma_children : Array[Av1SbPartitionNode] = []
  for child in children { chroma_children.push(av1_partition_node(child.row / 2, child.col / 2, 16, 32, 32)) }
  if u_coeffs.length() == 4 {
    if u_modes.length() != 4 || u_types.length() != 4 { return None }
    for i in 0..<4 {
      if !av1_reconstruct_child_with_type(u_plane, 32, 32, chroma_children[i], u_modes[i], u_coeffs[i], 16, u_types[i]) { return None }
    }
  }
  if v_coeffs.length() == 4 {
    if v_modes.length() != 4 || v_types.length() != 4 { return None }
    for i in 0..<4 {
      if !av1_reconstruct_child_with_type(v_plane, 32, 32, chroma_children[i], v_modes[i], v_coeffs[i], 16, v_types[i]) { return None }
    }
  }
  Some((av1_plane_bytes(y_plane), av1_plane_bytes(u_plane), av1_plane_bytes(v_plane)))
}

fn av1_reconstruct_block_with_type(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  tx_type : Av1TxType,
  bit_depth : Int,
) -> Array[Int]? {
  if coeffs.length() != width * height {
    return None
  }
  av1_inverse_transform_2d(tx_type, coeffs, width, height, bit_depth)
}

///|
test "split reconstruction accepts non-DC chroma modes" {
  let y = Array::make(32 * 32, 0)
  let c = Array::make(16 * 16, 0)
  let out = av1_reconstruct_split_yuv420(
    [y.copy(), y.copy(), y.copy(), y.copy()],
    [c.copy(), c.copy(), c.copy(), c.copy()],
    [c.copy(), c.copy(), c.copy(), c.copy()],
    [AV1_INTRA_DC, AV1_INTRA_DC, AV1_INTRA_DC, AV1_INTRA_DC],
    [AV1_INTRA_V, AV1_INTRA_H, AV1_INTRA_PAETH, AV1_INTRA_DC],
    [AV1_INTRA_H, AV1_INTRA_V, AV1_INTRA_PAETH, AV1_INTRA_DC],
  )
  assert_true(out is Some(_))
}

///|
test "block reconstruction dispatches a four-point ADST" {
  let values = Array::make(16, 0)
  values[0] = 100
  let out = av1_reconstruct_block_with_type(values, 4, 4, Av1TxAdstAdst, 8).unwrap()
  assert_eq(out.length(), 16)
}

///|
test "typed split reconstruction carries per-plane transform types" {
  let y = Array::make(32 * 32, 0)
  let c = Array::make(16 * 16, 0)
  let result = av1_reconstruct_split_yuv420_with_types(
    [y.copy(), y.copy(), y.copy(), y.copy()],
    [c.copy(), c.copy(), c.copy(), c.copy()],
    [c.copy(), c.copy(), c.copy(), c.copy()],
    [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
    [Av1TxDctDct, Av1TxDctDct, Av1TxDctDct, Av1TxDctDct],
    [Av1TxAdstAdst, Av1TxDctDct, Av1TxDctDct, Av1TxDctDct],
    [Av1TxDctDct, Av1TxDctDct, Av1TxDctDct, Av1TxDctDct],
  )
  assert_true(result is Some(_))
}

///|
test "tx luma assembler places raster leaves" {
  let leaves : Array[Av1TxLeaf] = [
    { node: { row: 0, col: 0, width: 16, height: 16 }, depth: 1 },
    { node: { row: 0, col: 16, width: 16, height: 16 }, depth: 1 },
    { node: { row: 16, col: 0, width: 16, height: 16 }, depth: 1 },
    { node: { row: 16, col: 16, width: 16, height: 16 }, depth: 1 },
  ]
  let coeff = Array::make(16 * 16, 0)
  let plane = av1_reconstruct_tx_luma(
    32, 32, leaves, [coeff.copy(), coeff.copy(), coeff.copy(), coeff.copy()],
    AV1_INTRA_DC, [Av1TxDctDct, Av1TxDctDct, Av1TxDctDct, Av1TxDctDct],
  ).unwrap()
  assert_eq(plane.length(), 1024)
  assert_eq(plane[0], 128)
}

///|
test "tx luma assembler accepts rectangular transform leaves" {
  let leaf : Av1TxLeaf = { node: { row: 0, col: 0, width: 8, height: 4 }, depth: 0 }
  let coeff = Array::make(8 * 4, 0)
  let plane = av1_reconstruct_tx_luma(
    8, 4, [leaf], [coeff], AV1_INTRA_DC, [Av1TxDctDct],
  ).unwrap()
  assert_eq(plane.length(), 32)
  assert_eq(plane[0], 128)
}

///|
test "tx chroma assembler uses 16 pixel leaves" {
  let leaves : Array[Av1TxLeaf] = [
    { node: { row: 0, col: 0, width: 16, height: 16 }, depth: 1 },
    { node: { row: 0, col: 16, width: 16, height: 16 }, depth: 1 },
    { node: { row: 16, col: 0, width: 16, height: 16 }, depth: 1 },
    { node: { row: 16, col: 16, width: 16, height: 16 }, depth: 1 },
  ]
  let coeff = Array::make(16 * 16, 0)
  let plane = av1_reconstruct_tx_chroma(
    leaves, [coeff.copy(), coeff.copy(), coeff.copy(), coeff.copy()],
    AV1_INTRA_DC, [Av1TxDctDct, Av1TxDctDct, Av1TxDctDct, Av1TxDctDct],
  ).unwrap()
  assert_eq(plane.length(), 1024)
  assert_eq(plane[1023], 128)
}

///|
test "typed transform planes compose through the highbd RGBA path" {
  let y_leaf : Array[Av1TxLeaf] = [{ node: { row: 0, col: 0, width: 32, height: 32 }, depth: 0 }]
  let c_leaf : Array[Av1TxLeaf] = [{ node: { row: 0, col: 0, width: 16, height: 16 }, depth: 0 }]
  let y = Array::make(32 * 32, 0)
  let c = Array::make(16 * 16, 0)
  let image = av1_reconstruct_tx_rgba(
    32, 32, y_leaf, [y], c_leaf, [c.copy()], c_leaf, [c.copy()],
    AV1_INTRA_DC, AV1_INTRA_DC,
    [Av1TxDctDct], [Av1TxDctDct], [Av1TxDctDct], 10,
  ).unwrap()
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}

///|
test "typed transform planes compose at 12-bit precision" {
  let y_leaf : Array[Av1TxLeaf] = [{ node: { row: 0, col: 0, width: 32, height: 32 }, depth: 0 }]
  let c_leaf : Array[Av1TxLeaf] = [{ node: { row: 0, col: 0, width: 16, height: 16 }, depth: 0 }]
  let y = Array::make(32 * 32, 0)
  let c = Array::make(16 * 16, 0)
  let image = av1_reconstruct_tx_rgba(
    32, 32, y_leaf, [y], c_leaf, [c.copy()], c_leaf, [c.copy()],
    AV1_INTRA_DC, AV1_INTRA_DC,
    [Av1TxDctDct], [Av1TxDctDct], [Av1TxDctDct], 12,
  ).unwrap()
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}
