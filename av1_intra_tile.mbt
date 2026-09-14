///|
/// One tile-local reconstructed plane and its coefficient neighbours. Pixels
/// include the AV1 MI padding; the visible frame rectangle is cropped only
/// after every block has been decoded.
priv struct Av1IntraPlane {
  width : Int
  height : Int
  pixels : Array[Int]
  above_level : Array[Int]
  left_level : Array[Int]
  above_dc : Array[Int]
  left_dc : Array[Int]
}

///|
fn av1_intra_plane(width : Int, height : Int, bit_depth : Int) -> Av1IntraPlane {
  {
    width,
    height,
    pixels: Array::make(width * height, 1 << (bit_depth - 1)),
    above_level: Array::make(width / 4, 0),
    left_level: Array::make(height / 4, 0),
    above_dc: Array::make(width / 4, 0),
    left_dc: Array::make(height / 4, 0),
  }
}

///|
/// Tile-local mode and residual state. Each mode CDF row persists across all
/// coding blocks. Palette flags remain zero for every accepted block.
priv struct Av1IntraState {
  cols : Int
  rows : Int
  skips : Array[Int]
  cdef : Av1CdefConfig?
  cdef_indices : Array[Int]
  skip_cdfs : Array[Array[Int]]
  y_modes : Array[Int]
  y_mode : Array[Array[Array[Int]]]
  uv_cfl : Array[Array[Int]]
  uv_no_cfl : Array[Array[Int]]
  angle_delta : Array[Array[Int]]
  palette_y : Array[Array[Int]]
  palette_uv : Array[Int]
  filter_intra : Array[Array[Int]]
  tables : Av1TxEntTables
  y_coeff : Av1CoeffContext
  uv_coeff : Av1CoeffContext
  planes : Array[Av1IntraPlane]
  base_q_idx : Int
  bit_depth : Int
  monochrome : Bool
  reduced_tx_set : Bool
  allow_screen_content_tools : Bool
  enable_filter_intra : Bool
  tx_mode_select : Bool
  tx_depth : Av1TxDepthState
  tx_neighbors : Av1TxTraversalState
}

///|
fn av1_intra_state(
  width : Int,
  height : Int,
  base_q_idx : Int,
  bit_depth : Int,
  reduced_tx_set : Bool,
  allow_screen_content_tools : Bool,
  enable_filter_intra : Bool,
  tx_mode_select : Bool,
  cdef? : Av1CdefConfig? = None,
  monochrome? : Bool = false,
) -> Av1IntraState {
  let filter_intra : Array[Array[Int]] = []
  for
    probability in [
      4621, 6743, 5893, 7866, 12551, 9394, 12408, 14301, 12756, 22343, 16384, 16384,
      16384, 16384, 16384, 16384, 12770, 10368, 20229, 18101, 16384, 16384,
    ] {
    filter_intra.push([probability, 32768, 0])
  }
  let palette_y : Array[Array[Int]] = []
  for probability in [31676, 31912, 31823, 32030, 32309, 32265, 32450] {
    palette_y.push([probability, 32768, 0])
  }
  let planes = [av1_intra_plane(width, height, bit_depth)]
  if !monochrome {
    planes.push(av1_intra_plane(width / 2, height / 2, bit_depth))
    planes.push(av1_intra_plane(width / 2, height / 2, bit_depth))
  }
  {
    cols: width / 4,
    rows: height / 4,
    skips: Array::make(width / 4 * (height / 4), 0),
    cdef,
    cdef_indices: Array::make((width + 63) / 64 * ((height + 63) / 64), -1),
    skip_cdfs: [[31671, 32768, 0], [16515, 32768, 0], [4576, 32768, 0]],
    y_modes: Array::make(width / 4 * (height / 4), 0),
    y_mode: av1_intra_y_mode_cdfs(),
    uv_cfl: av1_intra_uv_mode_cdfs(true),
    uv_no_cfl: av1_intra_uv_mode_cdfs(false),
    angle_delta: av1_intra_angle_cdfs(),
    palette_y,
    palette_uv: [32461, 32768, 0],
    filter_intra,
    tables: av1_tx_ent_tables(base_q_idx),
    y_coeff: av1_coeff_context(base_q_idx, 0, 0),
    uv_coeff: av1_coeff_context(base_q_idx, 0, 1),
    planes,
    base_q_idx,
    bit_depth,
    monochrome,
    reduced_tx_set,
    allow_screen_content_tools,
    enable_filter_intra,
    tx_mode_select,
    tx_depth: av1_tx_depth_state(),
    tx_neighbors: av1_tx_traversal_state(width, height),
  }
}

///|
/// AV1 BLOCK_* indices for coding rectangles with unambiguous 4:2:0 chroma
/// ownership. Sub-eight-pixel axes are rejected.
fn av1_intra_block_index(width : Int, height : Int) -> Int? {
  if width == 8 && height == 8 {
    Some(3)
  } else if width == 8 && height == 16 {
    Some(4)
  } else if width == 16 && height == 8 {
    Some(5)
  } else if width == 16 && height == 16 {
    Some(6)
  } else if width == 16 && height == 32 {
    Some(7)
  } else if width == 32 && height == 16 {
    Some(8)
  } else if width == 32 && height == 32 {
    Some(9)
  } else if width == 32 && height == 64 {
    Some(10)
  } else if width == 64 && height == 32 {
    Some(11)
  } else if width == 64 && height == 64 {
    Some(12)
  } else if width == 64 && height == 128 {
    Some(13)
  } else if width == 128 && height == 64 {
    Some(14)
  } else if width == 128 && height == 128 {
    Some(15)
  } else if width == 8 && height == 32 {
    Some(18)
  } else if width == 32 && height == 8 {
    Some(19)
  } else if width == 16 && height == 64 {
    Some(20)
  } else if width == 64 && height == 16 {
    Some(21)
  } else {
    None
  }
}

///|
/// Read the luma transform type after all_zero. The transform set uses the
/// square-up dimension for its DCT-only gate, but the square-down dimension
/// selects the CDF row (AV1 transform_type / get_tx_set).
fn av1_intra_tx_type(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  width : Int,
  height : Int,
  mode : Int,
) -> Av1TxType? {
  if state.base_q_idx == 0 || width >= 32 || height >= 32 {
    return Some(Av1TxDctDct)
  }
  av1_decode_intra_tx_type(
    decoder,
    state.tables,
    if width < height {
      width
    } else {
      height
    },
    mode,
    state.reduced_tx_set,
    state.base_q_idx,
  )
}

///|
/// Complete one transform before the next one reads neighbour state. All
/// coefficient contexts are clipped to the coded MI bounds, including DC
/// sign sums for transforms that extend past a visible frame edge.
fn av1_intra_transform(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  plane_index : Int,
  mode : Int,
  x : Int,
  y : Int,
  tx_width : Int,
  tx_height : Int,
  block_width : Int,
  block_height : Int,
  skip : Int,
) -> Bool {
  let plane = state.planes[plane_index]
  if x >= plane.width || y >= plane.height {
    return true
  }
  let x4 = x / 4
  let y4 = y / 4
  let w4 = tx_width / 4
  let h4 = tx_height / 4
  let cols = plane.width / 4
  let rows = plane.height / 4
  let mut above_level = 0
  let mut left_level = 0
  let mut above_nonzero = false
  let mut left_nonzero = false
  let mut dc_sign = 0
  for i in 0..<w4 {
    if x4 + i < cols {
      let level = plane.above_level[x4 + i]
      if level > above_level {
        above_level = level
      }
      let dc = plane.above_dc[x4 + i]
      if level != 0 || dc != 0 {
        above_nonzero = true
      }
      if dc == 1 {
        dc_sign = dc_sign - 1
      } else if dc == 2 {
        dc_sign = dc_sign + 1
      }
    }
  }
  for i in 0..<h4 {
    if y4 + i < rows {
      let level = plane.left_level[y4 + i]
      if level > left_level {
        left_level = level
      }
      let dc = plane.left_dc[y4 + i]
      if level != 0 || dc != 0 {
        left_nonzero = true
      }
      if dc == 1 {
        dc_sign = dc_sign - 1
      } else if dc == 2 {
        dc_sign = dc_sign + 1
      }
    }
  }
  let whole = tx_width == block_width && tx_height == block_height
  let skip_context = if plane_index == 0 {
    av1_txb_skip_ctx_luma(above_level, left_level, whole)
  } else {
    av1_txb_skip_ctx_chroma(above_nonzero, left_nonzero, whole)
  }
  let tx_context = av1_tx_size_ctx_rect(tx_width, tx_height)
  let all_zero = if skip == 1 {
    1
  } else {
    decoder.symbol(state.tables.txb_skip[tx_context][skip_context])
  }
  let mut cul_level = 0
  let mut dc_category = 0
  let mut residual : Array[Int] = []
  if all_zero == 0 {
    let tx_type = if plane_index == 0 {
      match av1_intra_tx_type(decoder, state, tx_width, tx_height, mode) {
        Some(value) => value
        None => return false
      }
    } else if state.base_q_idx == 0 || tx_width >= 32 || tx_height >= 32 {
      Av1TxDctDct
    } else {
      match
        av1_chroma_tx_type(
          mode,
          if tx_width < tx_height {
            tx_width
          } else {
            tx_height
          },
          state.reduced_tx_set,
        ) {
        Some(value) => value
        None => return false
      }
    }
    // U/V share probability rows, but the plane-level neighbour arrays above
    // remain independent. The luma instance likewise survives all blocks.
    let coeff_context = if plane_index == 0 {
      state.y_coeff
    } else {
      state.uv_coeff
    }
    coeff_context.tx_ctx = tx_context
    let coeffs = match
      av1_decode_coeffs_leaf_with_decoder(
        decoder,
        state.base_q_idx,
        coeff_context,
        tx_width,
        bit_depth=state.bit_depth,
        height=tx_height,
        scan_class=av1_tx_scan_class(tx_type),
        dc_sign_ctx=if dc_sign < 0 { 1 } else if dc_sign > 0 { 2 } else { 0 },
      ) {
      Some(value) => value
      None => return false
    }
    cul_level = coeffs.cul_level
    dc_category = coeffs.dc_category
    let decoded = if state.base_q_idx == 0 {
      av1_inverse_dct_2d(coeffs.coeffs, 4, 4, state.bit_depth, lossless=true)
    } else {
      av1_inverse_transform_2d(
        tx_type,
        coeffs.coeffs,
        tx_width,
        tx_height,
        state.bit_depth,
      )
    }
    residual = match decoded {
      Some(value) => value
      None => return false
    }
  } else if all_zero != 1 {
    return false
  }
  if decoder.symbol_max_bits < -14 {
    return false
  }
  let above : Array[Int] = []
  let left : Array[Int] = []
  if y > 0 {
    for i in 0..<tx_width {
      let col = if x + i < plane.width { x + i } else { plane.width - 1 }
      above.push(plane.pixels[(y - 1) * plane.width + col])
    }
  }
  if x > 0 {
    for i in 0..<tx_height {
      let row = if y + i < plane.height { y + i } else { plane.height - 1 }
      left.push(plane.pixels[row * plane.width + x - 1])
    }
  }
  let corner = if x > 0 && y > 0 {
    plane.pixels[(y - 1) * plane.width + x - 1]
  } else {
    1 << (state.bit_depth - 1)
  }
  let prediction = match
    av1_intra_predict(
      mode,
      tx_width,
      tx_height,
      above,
      left,
      corner,
      state.bit_depth,
      have_above=y > 0,
      have_left=x > 0,
    ) {
    Some(value) => value
    None => return false
  }
  for row in 0..<tx_height {
    if y + row >= plane.height {
      break
    }
    for col in 0..<tx_width {
      if x + col >= plane.width {
        break
      }
      let index = row * tx_width + col
      let value = prediction[index] +
        (if all_zero == 0 { residual[index] } else { 0 })
      plane.pixels[(y + row) * plane.width + x + col] = av1_intra_clip(
        value,
        state.bit_depth,
      )
    }
  }
  for i in 0..<w4 {
    if x4 + i < cols {
      plane.above_level[x4 + i] = cul_level
      plane.above_dc[x4 + i] = dc_category
    }
  }
  for i in 0..<h4 {
    if y4 + i < rows {
      plane.left_level[y4 + i] = cul_level
      plane.left_dc[y4 + i] = dc_category
    }
  }
  true
}

///|
/// V/H still signal angle_delta for coding blocks >=8x8. The other
/// supported modes have no angle syntax; diagonal modes and CfL need their
/// own prediction paths before their residuals can be reconstructed.
fn av1_intra_read_mode_angle(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  mode : Int,
) -> Bool {
  if mode == AV1_INTRA_V || mode == AV1_INTRA_H {
    return decoder.symbol(state.angle_delta[mode - 1]) == 3
  }
  mode == AV1_INTRA_DC ||
  mode == AV1_INTRA_SMOOTH ||
  mode == AV1_INTRA_SMOOTH_V ||
  mode == AV1_INTRA_SMOOTH_H ||
  mode == AV1_INTRA_PAETH
}

///|
/// The first non-skipped coding block in a 64x64 CDEF region selects that
/// region's strength. A 128-pixel coding block shares one index across its
/// whole footprint; skipped blocks leave the region available for a later
/// non-skipped block without consuming entropy.
fn av1_intra_cdef_index(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
  skip : Int,
) -> Bool {
  if skip == 1 {
    return true
  }
  if skip != 0 {
    return false
  }
  let config = match state.cdef {
    Some(value) => value
    None => return true
  }
  let width = state.cols * 4
  let height = state.rows * 4
  if block.col < 0 ||
    block.row < 0 ||
    block.col >= width ||
    block.row >= height ||
    block.width <= 0 ||
    block.height <= 0 ||
    block.width > 128 ||
    block.height > 128 {
    return false
  }
  let region_cols = (width + 63) / 64
  let region_rows = (height + 63) / 64
  let x0 = block.col / 64
  let y0 = block.row / 64
  let first = y0 * region_cols + x0
  let mut index = state.cdef_indices[first]
  if index < 0 {
    index = 0
    for _ in 0..<config.bits {
      index = (index << 1) | decoder.bool()
    }
    if decoder.symbol_max_bits < -14 {
      return false
    }
  }
  let x1 = (block.col + block.width - 1) / 64
  let y1 = (block.row + block.height - 1) / 64
  for row in y0..<(y1 + 1) {
    if row >= region_rows {
      break
    }
    for col in x0..<(x1 + 1) {
      if col >= region_cols {
        break
      }
      state.cdef_indices[row * region_cols + col] = index
    }
  }
  true
}

///|
/// Decode residuals in AV1 syntax order: 64x64 luma chunk, then plane, then
/// transform raster order within that chunk. Keep the full coding-plane
/// dimensions for txb_skip context; a chunk is not a new coding block.
fn av1_intra_residuals(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
  y_mode : Int,
  uv_mode : Int,
  luma_tx_width : Int,
  luma_tx_height : Int,
  skip : Int,
) -> Bool {
  for chunk_y in 0..<((block.height + 63) / 64) {
    for chunk_x in 0..<((block.width + 63) / 64) {
      for plane in 0..<state.planes.length() {
        let divisor = if plane == 0 { 1 } else { 2 }
        let width = block.width / divisor
        let height = block.height / divisor
        let unit_width = if block.width < 64 { width } else { 64 / divisor }
        let unit_height = if block.height < 64 { height } else { 64 / divisor }
        let tx_width = if plane == 0 {
          luma_tx_width
        } else if state.base_q_idx == 0 {
          4
        } else if width > 32 {
          32
        } else {
          width
        }
        let tx_height = if plane == 0 {
          luma_tx_height
        } else if state.base_q_idx == 0 {
          4
        } else if height > 32 {
          32
        } else {
          height
        }
        let mut row = 0
        while row < unit_height {
          let mut col = 0
          while col < unit_width {
            if !av1_intra_transform(
                decoder,
                state,
                plane,
                if plane == 0 {
                  y_mode
                } else {
                  uv_mode
                },
                (block.col + chunk_x * 64) / divisor + col,
                (block.row + chunk_y * 64) / divisor + row,
                tx_width,
                tx_height,
                width,
                height,
                skip,
              ) {
              return false
            }
            col = col + tx_width
          }
          row = row + tx_height
        }
      }
    }
  }
  true
}

///|
fn av1_intra_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
) -> Bool {
  let block_index = match av1_intra_block_index(block.width, block.height) {
    Some(value) => value
    None => return false
  }
  let x4 = block.col / 4
  let y4 = block.row / 4
  let mut skip_context = 0
  if y4 > 0 {
    skip_context = skip_context + state.skips[(y4 - 1) * state.cols + x4]
  }
  if x4 > 0 {
    skip_context = skip_context + state.skips[y4 * state.cols + x4 - 1]
  }
  let skip = decoder.symbol(state.skip_cdfs[skip_context])
  if skip != 0 && skip != 1 {
    return false
  }
  if !av1_intra_cdef_index(decoder, state, block, skip) {
    return false
  }
  let above_mode = if y4 > 0 {
    state.y_modes[(y4 - 1) * state.cols + x4]
  } else {
    0
  }
  let left_mode = if x4 > 0 {
    state.y_modes[y4 * state.cols + x4 - 1]
  } else {
    0
  }
  let y_mode = decoder.symbol(
    state.y_mode[av1_intra_mode_context(above_mode)][av1_intra_mode_context(
      left_mode,
    )],
  )
  if !av1_intra_read_mode_angle(decoder, state, y_mode) {
    return false
  }
  // Monochrome streams contain no UV mode, angle or palette syntax. The
  // placeholder mode is never consumed because there is only a luma plane.
  let uv_mode = if state.monochrome {
    AV1_INTRA_DC
  } else {
    // is_cfl_allowed differs for lossless: only a 4x4 chroma residual block
    // may use CfL, even when the luma coding block is below 32 pixels.
    let cfl_allowed = if state.base_q_idx == 0 {
      block.width == 8 && block.height == 8
    } else {
      block.width <= 32 && block.height <= 32
    }
    let mode = decoder.symbol(
      if cfl_allowed {
        state.uv_cfl[y_mode]
      } else {
        state.uv_no_cfl[y_mode]
      },
    )
    if !av1_intra_read_mode_angle(decoder, state, mode) {
      return false
    }
    mode
  }
  if state.allow_screen_content_tools && block.width <= 64 && block.height <= 64 {
    let palette_context = av1_msac_floor_log2(block.width / 4) +
      av1_msac_floor_log2(block.height / 4) -
      2
    if y_mode == AV1_INTRA_DC &&
      decoder.symbol(state.palette_y[palette_context]) != 0 {
      return false
    }
    if !state.monochrome &&
      uv_mode == AV1_INTRA_DC &&
      decoder.symbol(state.palette_uv) != 0 {
      return false
    }
  }
  if state.enable_filter_intra &&
    y_mode == AV1_INTRA_DC &&
    block.width <= 32 &&
    block.height <= 32 {
    if decoder.symbol(state.filter_intra[block_index]) != 0 {
      return false
    }
  }
  let root : Av1TxNode = {
    row: block.row,
    col: block.col,
    width: block.width,
    height: block.height,
  }
  let selected = if state.base_q_idx == 0 {
    (4, 4)
  } else if state.tx_mode_select {
    let depth = match
      av1_decode_tx_depth_for_block(
        decoder,
        state.tx_depth,
        block.width,
        block.height,
        av1_tx_depth_context_for_node(state.tx_neighbors, root),
      ) {
      Some(value) => value
      None => return false
    }
    match av1_tx_size_from_depth(block.width, block.height, depth) {
      Some(value) => value
      None => return false
    }
  } else {
    match av1_tx_size_from_depth(block.width, block.height, 0) {
      Some(value) => value
      None => return false
    }
  }
  let (luma_tx_width, luma_tx_height) = selected
  for row in y4..<(y4 + block.height / 4) {
    if row >= state.rows {
      break
    }
    for col in x4..<(x4 + block.width / 4) {
      if col >= state.cols {
        break
      }
      state.skips[row * state.cols + col] = skip
      state.y_modes[row * state.cols + col] = y_mode
    }
  }
  if !av1_intra_residuals(
      decoder, state, block, y_mode, uv_mode, luma_tx_width, luma_tx_height, skip,
    ) {
    return false
  }
  av1_tx_traversal_record_size(
    state.tx_neighbors,
    root,
    luma_tx_width,
    luma_tx_height,
  )
  decoder.symbol_max_bits >= -14
}

///|
fn av1_intra_crop(
  plane : Av1IntraPlane,
  width : Int,
  height : Int,
) -> Array[Int] {
  let output : Array[Int] = Array::make(width * height, 0)
  for row in 0..<height {
    for col in 0..<width {
      output[row * width + col] = plane.pixels[row * plane.width + col]
    }
  }
  output
}

///|
/// General partition traversal for the supported intra predictors. The frame
/// parser must already have excluded inter, segmentation, delta-Q/LF and
/// other unhandled frame syntax. Luma transform sizes follow tx_mode_select
/// when signalled; lossless blocks always use 4x4 transforms.
/// There is one shared MSAC/CDF state for all superblocks. A coding block's
/// mode and residual callback finishes before the walker reads its sibling.
fn av1_decode_intra_tile_state(
  width : Int,
  height : Int,
  payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update : Bool,
  allow_screen_content_tools : Bool,
  use_128x128_superblock : Bool,
  bit_depth : Int,
  reduced_tx_set : Bool,
  enable_filter_intra : Bool,
  tx_mode_select : Bool,
  cdef? : Av1CdefConfig? = None,
  monochrome? : Bool = false,
) -> Av1IntraState? {
  if width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    payload.length() == 0 ||
    payload.length() > 268435455 ||
    base_q_idx < 0 ||
    base_q_idx > 255 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  match cdef {
    Some(config) =>
      if base_q_idx == 0 || !av1_cdef_config_valid(config, monochrome~) {
        return None
      }
    None => ()
  }
  let coded_width = av1_partition_coded_extent(width)
  let coded_height = av1_partition_coded_extent(height)
  if coded_width > MAX_IMAGE_PIXELS / coded_height {
    return None
  }
  let state = av1_intra_state(
    coded_width,
    coded_height,
    base_q_idx,
    bit_depth,
    reduced_tx_set,
    allow_screen_content_tools,
    enable_filter_intra,
    tx_mode_select,
    cdef~,
    monochrome~,
  )
  let neighbors = match
    av1_partition_neighbor_state(
      { row: 0, col: 0, width: coded_width, height: coded_height, },
      width,
      height,
    ) {
    Some(value) => value
    None => return None
  }
  let decoder = av1_msac_new(payload, !disable_cdf_update)
  let cdfs = av1_partition_cdf_state()
  let sb_size = if use_128x128_superblock { 128 } else { 64 }
  let mut row = 0
  while row < coded_height {
    let mut col = 0
    while col < coded_width {
      if !av1_walk_partition_tree(
          decoder,
          cdfs,
          neighbors,
          av1_partition_node(row, col, sb_size, width, height),
          fn(reader, block) { av1_intra_block(reader, state, block) },
        ) {
        return None
      }
      col = col + sb_size
    }
    row = row + sb_size
  }
  Some(state)
}

///|
/// Keep full-depth reconstructed planes until the final color conversion.
fn av1_decode_intra_tile(
  width : Int,
  height : Int,
  payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update : Bool,
  allow_screen_content_tools : Bool,
  full_range : Bool,
  matrix_coefficients : Int,
  use_128x128_superblock : Bool,
  bit_depth : Int,
  reduced_tx_set : Bool,
  enable_filter_intra : Bool,
  tx_mode_select : Bool,
  cdef? : Av1CdefConfig? = None,
) -> Image? {
  let state = match
    av1_decode_intra_tile_state(
      width,
      height,
      payload,
      base_q_idx,
      disable_cdf_update,
      allow_screen_content_tools,
      use_128x128_superblock,
      bit_depth,
      reduced_tx_set,
      enable_filter_intra,
      tx_mode_select,
      cdef~,
    ) {
    Some(value) => value
    None => return None
  }
  match cdef {
    Some(config) => {
      let filtered = match
        av1_cdef_filter_frame(
          state.planes[0].width,
          state.planes[0].height,
          [
            state.planes[0].pixels,
            state.planes[1].pixels,
            state.planes[2].pixels,
          ],
          state.skips,
          state.cdef_indices,
          config,
          bit_depth,
        ) {
        Some(value) => value
        None => return None
      }
      for plane in 0..<3 {
        for i in 0..<filtered[plane].length() {
          state.planes[plane].pixels[i] = filtered[plane][i]
        }
      }
    }
    None => ()
  }
  av1_yuv420_highbd_to_rgba(
    width,
    height,
    av1_intra_crop(state.planes[0], width, height),
    av1_intra_crop(state.planes[1], (width + 1) / 2, (height + 1) / 2),
    av1_intra_crop(state.planes[2], (width + 1) / 2, (height + 1) / 2),
    bit_depth,
    full_range~,
    matrix_coefficients~,
  )
}
