/// Directional reference availability follows libaom reconintra.c at
/// 8e7b6a567df174d795479b92b4ac766d271add73, including its packed 128-superblock
/// tables and VERT_A/B exceptions. No sample values determine availability.
/// Copyright (c) 2016, Alliance for Open Media. All rights reserved.
/// BSD 2 Clause License and Alliance for Open Media Patent License 1.0:
/// https://www.aomedia.org/license/software and https://www.aomedia.org/license/patent

///|
priv struct Av1IntraEdgeCounts {
  n_top : Int
  n_left : Int
  n_topright : Int
  n_bottomleft : Int
}

///|
fn av1_intra_edge_table(
  top_right : Bool,
  index : Int,
  partition : Av1SbPartition,
) -> Array[Int]? {
  let normal = if top_right { av1_edge_tr_tables } else { av1_edge_bl_tables }
  if partition is Av1SbPartitionVertA || partition is Av1SbPartitionVertB {
    let special = if top_right {
      av1_edge_tr_vert_tables
    } else {
      av1_edge_bl_vert_tables
    }
    match index {
      3 => Some(special[0])
      6 => Some(special[1])
      9 => Some(special[2])
      12 => Some(special[3])
      1 | 4 | 7 | 10 | 13 | 15 => Some(normal[index])
      _ => None
    }
  } else {
    Some(normal[index])
  }
}

///|
fn av1_intra_has_top_right(
  block_width : Int,
  block_height : Int,
  mi_row : Int,
  mi_col : Int,
  row_offset : Int,
  col_offset : Int,
  tx_width : Int,
  subsample : Int,
  sb_size : Int,
  top_available : Bool,
  right_available : Bool,
  table : Array[Int],
) -> Bool {
  if !top_available || !right_available {
    return false
  }
  let bw_mi = block_width / 4
  let plane_bw = if bw_mi >> subsample > 0 { bw_mi >> subsample } else { 1 }
  let tx_w_mi = tx_width / 4
  if row_offset > 0 {
    if block_width > 64 {
      let chunk = 16 >> subsample
      if row_offset == chunk && col_offset + tx_w_mi == chunk {
        return true
      }
      return col_offset % chunk + tx_w_mi < chunk
    }
    return col_offset + tx_w_mi < plane_bw
  }
  if col_offset + tx_w_mi < plane_bw {
    return true
  }
  let log_w = av1_msac_floor_log2(bw_mi)
  let log_h = av1_msac_floor_log2(block_height / 4)
  let sb_mi = sb_size / 4
  let block_row = (mi_row & (sb_mi - 1)) >> log_h
  let block_col = (mi_col & (sb_mi - 1)) >> log_w
  if block_row == 0 {
    return true
  }
  if (block_col + 1) << log_w >= sb_mi {
    return false
  }
  // MAX_MIB_SIZE_LOG2 is five even when the sequence uses 64x64 SBs.
  let index = (block_row << (5 - log_w)) + block_col
  ((table[index / 8] >> (index % 8)) & 1) != 0
}

///|
fn av1_intra_has_bottom_left(
  block_width : Int,
  block_height : Int,
  mi_row : Int,
  mi_col : Int,
  row_offset : Int,
  col_offset : Int,
  tx_height : Int,
  subsample : Int,
  sb_size : Int,
  bottom_available : Bool,
  left_available : Bool,
  table : Array[Int],
) -> Bool {
  if !bottom_available || !left_available {
    return false
  }
  let tx_h_mi = tx_height / 4
  if block_width > 64 && col_offset > 0 {
    let chunk = 16 >> subsample
    if col_offset % chunk == 0 {
      let block_height_plane = (block_height / 4) >> subsample
      let unit_height = if block_height_plane < chunk {
        block_height_plane
      } else {
        chunk
      }
      return row_offset % chunk + tx_h_mi < unit_height
    }
  }
  if col_offset > 0 {
    return false
  }
  let bh_mi = block_height / 4
  let plane_bh = if bh_mi >> subsample > 0 { bh_mi >> subsample } else { 1 }
  if row_offset + tx_h_mi < plane_bh {
    return true
  }
  let log_w = av1_msac_floor_log2(block_width / 4)
  let log_h = av1_msac_floor_log2(bh_mi)
  let sb_mi = sb_size / 4
  let block_row = (mi_row & (sb_mi - 1)) >> log_h
  let block_col = (mi_col & (sb_mi - 1)) >> log_w
  if block_col == 0 {
    let row_in_sb = (block_row << log_h >> subsample) + row_offset
    return row_in_sb + tx_h_mi < sb_mi >> subsample
  }
  if (block_row + 1) << log_h >= sb_mi {
    return false
  }
  let index = (block_row << (5 - log_w)) + block_col
  ((table[index / 8] >> (index % 8)) & 1) != 0
}

///|
/// tile/block coordinates are luma pixels; tx coordinates are plane pixels.
/// coded dimensions are the MI-padded frame dimensions. Preserve the original
/// chroma owner's MI position when scaling a 4-axis block for table lookup.
/// Counts are nonnegative. The directional caller changes unused TR/BL counts
/// to -1 according to the final angle before invoking the prediction kernel.
fn av1_intra_edge_counts(
  tile : Av1SbBlock,
  coded_width : Int,
  coded_height : Int,
  block : Av1SbBlock,
  partition : Av1SbPartition,
  tx : Av1TxNode,
  plane : Int,
  sb_size : Int,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
) -> Av1IntraEdgeCounts? {
  if coded_width <= 0 ||
    coded_height <= 0 ||
    coded_width > MAX_IMAGE_PIXELS / coded_height ||
    coded_width % 8 != 0 ||
    coded_height % 8 != 0 ||
    tile.row < 0 ||
    tile.col < 0 ||
    tile.width <= 0 ||
    tile.height <= 0 ||
    tile.row % 4 != 0 ||
    tile.col % 4 != 0 ||
    tile.width % 4 != 0 ||
    tile.height % 4 != 0 ||
    tile.width > coded_width ||
    tile.height > coded_height ||
    tile.col > coded_width - tile.width ||
    tile.row > coded_height - tile.height ||
    (sb_size != 64 && sb_size != 128) ||
    plane < 0 ||
    plane > 2 ||
    block.row < tile.row ||
    block.col < tile.col ||
    block.row >= tile.row + tile.height ||
    block.col >= tile.col + tile.width ||
    block.row % 4 != 0 ||
    block.col % 4 != 0 ||
    block.width > sb_size ||
    block.height > sb_size ||
    av1_intra_block_index(block.width, block.height) is None ||
    !av1_tx_block_geometry_valid(tx.width, tx.height) ||
    tx.width > 64 ||
    tx.height > 64 {
    return None
  }
  let mi_row = block.row / 4
  let mi_col = block.col / 4
  // Each axis carries its own subsampling shift; a luma block narrower than
  // eight pixels merges into its eight-pixel chroma group only on a subsampled
  // axis (AV1 section 6.4.3 is_chroma_reference).
  let plane_sub_x = if plane == 0 { 0 } else { sub_x }
  let plane_sub_y = if plane == 0 { 0 } else { sub_y }
  if plane != 0 &&
    (
      (plane_sub_x == 1 && block.width < 8 && (mi_col & 1) == 0) ||
      (plane_sub_y == 1 && block.height < 8 && (mi_row & 1) == 0)
    ) {
    return None
  }
  let origin_x = if plane_sub_x == 1 { block.col / 8 * 4 } else { block.col }
  let origin_y = if plane_sub_y == 1 { block.row / 8 * 4 } else { block.row }
  let plane_width = if plane != 0 {
    let scaled = block.width >> plane_sub_x
    if scaled < 4 {
      4
    } else {
      scaled
    }
  } else {
    block.width
  }
  let plane_height = if plane != 0 {
    let scaled = block.height >> plane_sub_y
    if scaled < 4 {
      4
    } else {
      scaled
    }
  } else {
    block.height
  }
  if tx.col < origin_x ||
    tx.row < origin_y ||
    tx.col % 4 != 0 ||
    tx.row % 4 != 0 ||
    tx.width > plane_width ||
    tx.height > plane_height ||
    tx.col - origin_x > plane_width - tx.width ||
    tx.row - origin_y > plane_height - tx.height ||
    tx.col >= (tile.col + tile.width) >> plane_sub_x ||
    tx.row >= (tile.row + tile.height) >> plane_sub_y {
    return None
  }
  let col_offset = (tx.col - origin_x) / 4
  let row_offset = (tx.row - origin_y) / 4
  let top_available = row_offset != 0 ||
    (if plane_sub_y == 1 && block.height == 4 {
      mi_row - 1 > tile.row / 4
    } else {
      mi_row > tile.row / 4
    })
  let left_available = col_offset != 0 ||
    (if plane_sub_x == 1 && block.width == 4 {
      mi_col - 1 > tile.col / 4
    } else {
      mi_col > tile.col / 4
    })
  let xr = (coded_width >> plane_sub_x) - tx.col - tx.width
  let yd = (coded_height >> plane_sub_y) - tx.row - tx.height
  let right_available = mi_col + ((col_offset + tx.width / 4) << plane_sub_x) <
    (tile.col + tile.width) / 4
  let bottom_available = yd > 0 &&
    mi_row + ((row_offset + tx.height / 4) << plane_sub_y) <
    (tile.row + tile.height) / 4
  let scaled_width = plane_width << plane_sub_x
  let scaled_height = plane_height << plane_sub_y
  let index = av1_intra_block_index(scaled_width, scaled_height).unwrap()
  let tr_table = match av1_intra_edge_table(true, index, partition) {
    Some(value) => value
    None => return None
  }
  let bl_table = match av1_intra_edge_table(false, index, partition) {
    Some(value) => value
    None => return None
  }
  let has_tr = av1_intra_has_top_right(
    scaled_width,
    scaled_height,
    mi_row,
    mi_col,
    row_offset,
    col_offset,
    tx.width,
    plane_sub_x,
    sb_size,
    top_available,
    right_available,
    tr_table,
  )
  let has_bl = av1_intra_has_bottom_left(
    scaled_width,
    scaled_height,
    mi_row,
    mi_col,
    row_offset,
    col_offset,
    tx.height,
    plane_sub_y,
    sb_size,
    bottom_available,
    left_available,
    bl_table,
  )
  Some({
    n_top: if top_available {
      if xr >= 0 {
        tx.width
      } else {
        xr + tx.width
      }
    } else {
      0
    },
    n_left: if left_available {
      if yd >= 0 {
        tx.height
      } else {
        yd + tx.height
      }
    } else {
      0
    },
    n_topright: if has_tr && xr > 0 {
      if xr < tx.width {
        xr
      } else {
        tx.width
      }
    } else {
      0
    },
    n_bottomleft: if has_bl && yd > 0 {
      if yd < tx.height {
        yd
      } else {
        tx.height
      }
    } else {
      0
    },
  })
}

///|
/// Return tile-local MI indices of the neighbouring coding blocks used for
/// edge-filter type. UV selects the bottom-right owner in each aligned chroma
/// group; it must not inspect the adjacent non-owner luma block instead.
fn av1_intra_edge_neighbor_indices(
  tile : Av1SbBlock,
  block : Av1SbBlock,
  plane : Int,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
) -> (Int?, Int?)? {
  if tile.row < 0 ||
    tile.col < 0 ||
    tile.row % 4 != 0 ||
    tile.col % 4 != 0 ||
    tile.width <= 0 ||
    tile.height <= 0 ||
    tile.width % 4 != 0 ||
    tile.height % 4 != 0 ||
    plane < 0 ||
    plane > 2 ||
    block.row < tile.row ||
    block.col < tile.col ||
    block.row >= tile.row + tile.height ||
    block.col >= tile.col + tile.width ||
    block.row % 4 != 0 ||
    block.col % 4 != 0 ||
    av1_intra_block_index(block.width, block.height) is None {
    return None
  }
  if plane != 0 &&
    (
      (sub_x == 1 && block.width < 8 && ((block.col / 4) & 1) == 0) ||
      (sub_y == 1 && block.height < 8 && ((block.row / 4) & 1) == 0)
    ) {
    return None
  }
  let cols = tile.width / 4
  let rows = tile.height / 4
  let row = (block.row - tile.row) / 4
  let col = (block.col - tile.col) / 4
  let above_row = if plane == 0 || sub_y == 0 {
    row - 1
  } else {
    row - ((block.row / 4) & 1) - 1
  }
  let above_col = if plane == 0 || sub_x == 0 {
    col
  } else {
    col - ((block.col / 4) & 1) + 1
  }
  let left_row = if plane == 0 || sub_y == 0 {
    row
  } else {
    row - ((block.row / 4) & 1) + 1
  }
  let left_col = if plane == 0 || sub_x == 0 {
    col - 1
  } else {
    col - ((block.col / 4) & 1) - 1
  }
  let above = if above_row >= 0 &&
    above_row < rows &&
    above_col >= 0 &&
    above_col < cols {
    Some(above_row * cols + above_col)
  } else {
    None
  }
  let left = if left_row >= 0 &&
    left_row < rows &&
    left_col >= 0 &&
    left_col < cols {
    Some(left_row * cols + left_col)
  } else {
    None
  }
  Some((above, left))
}

///|
/// Smooth context belongs to neighbouring coding-block modes, not to a
/// preceding transform inside the current block. Inter UV modes may be stale
/// and are ignored, matching reconintra.c:is_smooth.
fn av1_intra_edge_neighbor_smooth(
  tile : Av1SbBlock,
  block : Av1SbBlock,
  plane : Int,
  y_modes : Array[Int],
  uv_modes : Array[Int],
  inter? : Array[Bool]? = None,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
) -> Bool? {
  let (above, left) = match
    av1_intra_edge_neighbor_indices(tile, block, plane, sub_x~, sub_y~) {
    Some(value) => value
    None => return None
  }
  let modes = if plane == 0 { y_modes } else { uv_modes }
  let count = tile.width / 4 * (tile.height / 4)
  if modes.length() != count {
    return None
  }
  if inter is Some(flags) && flags.length() != count {
    return None
  }
  for neighbor in [above, left] {
    if neighbor is Some(i) {
      let skip = if plane == 0 {
        false
      } else {
        match inter {
          Some(flags) => flags[i]
          None => false
        }
      }
      if !skip && modes[i] >= AV1_INTRA_SMOOTH && modes[i] <= AV1_INTRA_SMOOTH_H {
        return Some(true)
      }
    }
  }
  Some(false)
}

///|
// Packed flags copied from the original libaom 128x128 tables.
let av1_edge_tr_tables : Array[Array[Int]] = [
  [
    255, 255, 255, 255, 85, 85, 85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 127,
    127, 127, 127, 85, 85, 85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 255, 127,
    255, 127, 85, 85, 85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 127, 127, 127,
    127, 85, 85, 85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 255, 255, 255, 127,
    85, 85, 85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 127, 127, 127, 127, 85, 85,
    85, 85, 119, 119, 119, 119, 85, 85, 85, 85, 255, 127, 255, 127, 85, 85, 85, 85,
    119, 119, 119, 119, 85, 85, 85, 85, 127, 127, 127, 127, 85, 85, 85, 85, 119,
    119, 119, 119, 85, 85, 85, 85,
  ], // 4x4
  [
    255, 255, 255, 255, 119, 119, 119, 119, 127, 127, 127, 127, 119, 119, 119, 119,
    255, 127, 255, 127, 119, 119, 119, 119, 127, 127, 127, 127, 119, 119, 119, 119,
    255, 255, 255, 127, 119, 119, 119, 119, 127, 127, 127, 127, 119, 119, 119, 119,
    255, 127, 255, 127, 119, 119, 119, 119, 127, 127, 127, 127, 119, 119, 119, 119,
  ], // 4x8
  [
    255, 255, 0, 0, 85, 85, 0, 0, 119, 119, 0, 0, 85, 85, 0, 0, 127, 127, 0, 0, 85,
    85, 0, 0, 119, 119, 0, 0, 85, 85, 0, 0, 255, 127, 0, 0, 85, 85, 0, 0, 119, 119,
    0, 0, 85, 85, 0, 0, 127, 127, 0, 0, 85, 85, 0, 0, 119, 119, 0, 0, 85, 85, 0,
    0,
  ], // 8x4
  [
    255, 255, 85, 85, 119, 119, 85, 85, 127, 127, 85, 85, 119, 119, 85, 85, 255,
    127, 85, 85, 119, 119, 85, 85, 127, 127, 85, 85, 119, 119, 85, 85,
  ], // 8x8
  [
    255, 255, 119, 119, 127, 127, 119, 119, 255, 127, 119, 119, 127, 127, 119, 119,
  ], // 8x16
  [255, 0, 85, 0, 119, 0, 85, 0, 127, 0, 85, 0, 119, 0, 85, 0], // 16x8
  [255, 85, 119, 85, 127, 85, 119, 85], // 16x16
  [255, 119, 127, 119], // 16x32
  [15, 5, 7, 5], // 32x16
  [95, 87], // 32x32
  [127], // 32x64
  [19], // 64x32
  [7], // 64x64
  [3], // 64x128
  [1], // 128x64
  [1], // 128x128
  [
    255, 255, 255, 255, 127, 127, 127, 127, 255, 127, 255, 127, 127, 127, 127, 127,
    255, 255, 255, 127, 127, 127, 127, 127, 255, 127, 255, 127, 127, 127, 127, 127,
  ], // 4x16
  [
    255, 0, 0, 0, 85, 0, 0, 0, 119, 0, 0, 0, 85, 0, 0, 0, 127, 0, 0, 0, 85, 0, 0,
    0, 119, 0, 0, 0, 85, 0, 0, 0,
  ], // 16x4
  [255, 255, 127, 127, 255, 127, 127, 127], // 8x32
  [15, 0, 5, 0, 7, 0, 5, 0], // 32x8
  [255, 127], // 16x64
  [3, 1], // 64x16
]

///|
// Packed flags copied from the original libaom 128x128 tables.
let av1_edge_tr_vert_tables : Array[Array[Int]] = [
  [
    255, 255, 0, 0, 119, 119, 0, 0, 127, 127, 0, 0, 119, 119, 0, 0, 255, 127, 0,
    0, 119, 119, 0, 0, 127, 127, 0, 0, 119, 119, 0, 0,
  ], // 8x8
  [255, 0, 119, 0, 127, 0, 119, 0], // 16x16
  [15, 7], // 32x32
  [3], // 64x64
]

///|
// Packed flags copied from the original libaom 128x128 tables.
let av1_edge_bl_tables : Array[Array[Int]] = [
  [
    84, 85, 85, 85, 16, 17, 17, 17, 84, 85, 85, 85, 0, 1, 1, 1, 84, 85, 85, 85, 16,
    17, 17, 17, 84, 85, 85, 85, 0, 0, 1, 0, 84, 85, 85, 85, 16, 17, 17, 17, 84, 85,
    85, 85, 0, 1, 1, 1, 84, 85, 85, 85, 16, 17, 17, 17, 84, 85, 85, 85, 0, 0, 0,
    0, 84, 85, 85, 85, 16, 17, 17, 17, 84, 85, 85, 85, 0, 1, 1, 1, 84, 85, 85, 85,
    16, 17, 17, 17, 84, 85, 85, 85, 0, 0, 1, 0, 84, 85, 85, 85, 16, 17, 17, 17, 84,
    85, 85, 85, 0, 1, 1, 1, 84, 85, 85, 85, 16, 17, 17, 17, 84, 85, 85, 85, 0, 0,
    0, 0,
  ], // 4x4
  [
    16, 17, 17, 17, 0, 1, 1, 1, 16, 17, 17, 17, 0, 0, 1, 0, 16, 17, 17, 17, 0, 1,
    1, 1, 16, 17, 17, 17, 0, 0, 0, 0, 16, 17, 17, 17, 0, 1, 1, 1, 16, 17, 17, 17,
    0, 0, 1, 0, 16, 17, 17, 17, 0, 1, 1, 1, 16, 17, 17, 17, 0, 0, 0, 0,
  ], // 4x8
  [
    254, 255, 84, 85, 254, 255, 16, 17, 254, 255, 84, 85, 254, 255, 0, 1, 254, 255,
    84, 85, 254, 255, 16, 17, 254, 255, 84, 85, 254, 255, 0, 0, 254, 255, 84, 85,
    254, 255, 16, 17, 254, 255, 84, 85, 254, 255, 0, 1, 254, 255, 84, 85, 254, 255,
    16, 17, 254, 255, 84, 85, 254, 255, 0, 0,
  ], // 8x4
  [
    84, 85, 16, 17, 84, 85, 0, 1, 84, 85, 16, 17, 84, 85, 0, 0, 84, 85, 16, 17, 84,
    85, 0, 1, 84, 85, 16, 17, 84, 85, 0, 0,
  ], // 8x8
  [16, 17, 0, 1, 16, 17, 0, 0, 16, 17, 0, 1, 16, 17, 0, 0], // 8x16
  [254, 84, 254, 16, 254, 84, 254, 0, 254, 84, 254, 16, 254, 84, 254, 0], // 16x8
  [84, 16, 84, 0, 84, 16, 84, 0], // 16x16
  [16, 0, 16, 0], // 16x32
  [78, 14, 78, 14], // 32x16
  [4, 4], // 32x32
  [0], // 32x64
  [34], // 64x32
  [0], // 64x64
  [0], // 64x128
  [0], // 128x64
  [0], // 128x128
  [
    0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1,
    1, 1, 0, 0, 0, 0,
  ], // 4x16
  [
    254, 254, 254, 84, 254, 254, 254, 16, 254, 254, 254, 84, 254, 254, 254, 0, 254,
    254, 254, 84, 254, 254, 254, 16, 254, 254, 254, 84, 254, 254, 254, 0,
  ], // 16x4
  [0, 1, 0, 0, 0, 1, 0, 0], // 8x32
  [238, 78, 238, 14, 238, 78, 238, 14], // 32x8
  [0, 0], // 16x64
  [42, 42], // 64x16
]

///|
// Packed flags copied from the original libaom 128x128 tables.
let av1_edge_bl_vert_tables : Array[Array[Int]] = [
  [
    254, 255, 16, 17, 254, 255, 0, 1, 254, 255, 16, 17, 254, 255, 0, 0, 254, 255,
    16, 17, 254, 255, 0, 1, 254, 255, 16, 17, 254, 255, 0, 0,
  ], // 8x8
  [254, 16, 254, 0, 254, 16, 254, 0], // 16x16
  [14, 14], // 32x32
  [2], // 64x64
]
