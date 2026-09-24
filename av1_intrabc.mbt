/// Intra block copy uses inter transforms and a separate integer displacement
/// vector context, while its reference samples belong to the current tile.

///|
priv struct Av1IntrabcState {
  use_cdf : Array[Int]
  info : Av1InterInfo
  frame_mi_cols : Int
  frame_mi_rows : Int
  tile_col : Int
  tile_row : Int
}

///|
fn av1_intrabc_state(
  width : Int,
  height : Int,
  frame_mi_cols? : Int = 0,
  frame_mi_rows? : Int = 0,
  tile_col? : Int = 0,
  tile_row? : Int = 0,
) -> Av1IntrabcState {
  let cols = width / 4
  let rows = height / 4
  {
    use_cdf: [30531, 32768, 0],
    info: {
      cdfs: av1_inter_cdfs(),
      field: av1_motion_field(cols, rows),
      frame: {
        allow_high_precision_mv: false,
        use_ref_frame_mvs: false,
        force_integer_mv: 1,
        is_motion_mode_switchable: false,
        allow_warped_motion: false,
        gm_type: Array::make(8, 0),
        gm_params: Array::makei(8, _ => av1_identity_gm_params()),
        ref_frame_sign_bias: Array::make(8, 0),
        frame_width: width,
        frame_height: height,
        temporal: None,
      },
      refs: Array::make(8, None),
      interpolation_filter: 3,
      enable_dual_filter: false,
      skip_mode_present: false,
      skip_mode_frame: [],
      reference_select: false,
      enable_interintra_compound: false,
      ref_distances: Array::make(8, 0),
      enable_masked_compound: false,
      enable_jnt_comp: false,
      mi_cols: cols,
      mi_rows: rows,
      tile_row_start: 0,
      tile_col_start: 0,
      tile_row_end: rows,
      tile_col_end: cols,
    },
    frame_mi_cols: if frame_mi_cols > 0 {
      frame_mi_cols
    } else {
      tile_col + cols
    },
    frame_mi_rows: if frame_mi_rows > 0 {
      frame_mi_rows
    } else {
      tile_row + rows
    },
    tile_col,
    tile_row,
  }
}

///|
/// Inter residuals read the same transform tables for either kind of motion.
/// Keeping this lookup separate leaves intra-frame mode parsing unchanged.
fn av1_block_motion_info(state : Av1IntraState) -> Av1InterInfo? {
  match state.inter {
    Some(info) => Some(info)
    None => state.intrabc.map(value => value.info)
  }
}

///|
/// find_mv_stack with INTRA_FRAME. The spatial search and stable sort are the
/// ordinary MV processes. The extended search has no inter-frame references
/// to add, and the temporal and global predictors are zero for this frame.
/// Clamp in full-frame coordinates, although the motion field is tile-local.
fn av1_intrabc_predictor(
  ibc : Av1IntrabcState,
  block : Av1SbBlock,
  superblock_size : Int,
) -> (Int, Int) {
  let field = ibc.info.field
  let frame = ibc.info.frame
  let current : Av1MvBlock = {
    mi_row: block.row / 4,
    mi_col: block.col / 4,
    width4: block.width / 4,
    height4: block.height / 4,
    block_width: block.width,
    block_height: block.height,
    refs: [av1_intra_frame, av1_none_frame],
    tile_row_start: 0,
    tile_row_end: field.rows,
    tile_col_start: 0,
    tile_col_end: field.cols,
  }
  let stack = av1_mv_stack_new()
  av1_scan_row(field, stack, current, frame, -1, false)
  av1_scan_col(field, stack, current, frame, -1, false)
  if block.width <= 64 && block.height <= 64 {
    av1_scan_point(field, stack, current, frame, -1, current.width4, false)
  }
  let nearest = stack.count
  for index in 0..<nearest {
    stack.weights[index] = stack.weights[index] + av1_ref_cat_level
  }
  av1_scan_point(field, stack, current, frame, -1, -1, false)
  av1_scan_row(field, stack, current, frame, -3, false)
  av1_scan_col(field, stack, current, frame, -3, false)
  if current.height4 > 1 {
    av1_scan_row(field, stack, current, frame, -5, false)
  }
  if current.width4 > 1 {
    av1_scan_col(field, stack, current, frame, -5, false)
  }
  av1_sort_mv_stack(stack, 0, nearest, false)
  av1_sort_mv_stack(stack, nearest, stack.count, false)
  for index in 0..<2 {
    let mv = av1_stack_mv(stack, index, 0)
    let row = av1_clamp_mv(
      mv.0,
      ibc.tile_row + current.mi_row,
      current.height4,
      ibc.frame_mi_rows,
      av1_mv_border + block.height * 8,
    )
    let col = av1_clamp_mv(
      mv.1,
      ibc.tile_col + current.mi_col,
      current.width4,
      ibc.frame_mi_cols,
      av1_mv_border + block.width * 8,
    )
    if row != 0 || col != 0 {
      return (row, col)
    }
  }
  if block.row < superblock_size {
    (0, -(superblock_size + 256) * 8)
  } else {
    (-superblock_size * 8, 0)
  }
}

///|
/// Displacement-vector syntax uses MV_INTRABC_CONTEXT and omits all fractional
/// and high-precision symbols, even when chroma subsampling produces half pels.
fn av1_intrabc_read_dv(
  decoder : Av1SymbolDecoder,
  ibc : Av1IntrabcState,
  predicted : (Int, Int),
) -> (Int, Int)? {
  let joint = decoder.symbol(ibc.info.cdfs.mv_joint[1])
  if joint < 0 || joint > 3 {
    return None
  }
  let mut row = predicted.0
  let mut col = predicted.1
  if joint == 2 || joint == 3 {
    let delta = av1_read_mv_component(decoder, ibc.info, 1, 0)
    if delta == 0 {
      return None
    }
    row = row + delta
  }
  if joint == 1 || joint == 3 {
    let delta = av1_read_mv_component(decoder, ibc.info, 1, 1)
    if delta == 0 {
      return None
    }
    col = col + delta
  }
  if row < -32768 ||
    row > 32767 ||
    col < -32768 ||
    col > 32767 ||
    (row & 7) != 0 ||
    (col & 7) != 0 {
    None
  } else {
    Some((row, col))
  }
}

///|
/// Conforming DV bounds, including the four-SB64 delay and wavefront limit
/// from libaom av1/common/mvref_common.h:av1_is_dv_valid. All tile starts align
/// to superblocks, so subtracting their origin preserves the SB differences.
fn av1_intrabc_dv_valid(
  state : Av1IntraState,
  block : Av1SbBlock,
  row : Int,
  col : Int,
) -> Bool {
  if (row & 7) != 0 || (col & 7) != 0 {
    return false
  }
  let left = block.col + (col >> 3)
  let top = block.row + (row >> 3)
  let right = left + block.width
  let bottom = top + block.height
  if left < 0 || top < 0 || right > state.cols * 4 || bottom > state.rows * 4 {
    return false
  }
  if av1_intra_has_chroma(state, block) {
    if (block.width < 8 && state.sub_x == 1 && left < 4) ||
      (block.height < 8 && state.sub_y == 1 && top < 4) {
      return false
    }
  }
  let active_row = block.row / state.superblock_size
  let active_col = block.col / 64
  let source_row = (bottom - 1) / state.superblock_size
  let source_col = (right - 1) / 64
  let columns = (state.cols + 15) / 16
  if source_row * columns + source_col >= active_row * columns + active_col - 4 {
    return false
  }
  let gradient = if state.superblock_size == 128 { 6 } else { 5 }
  source_row <= active_row &&
  source_col < active_col - 4 + gradient * (active_row - source_row)
}

///|
/// Only samples reconstructed by a completed coding block may be copied.
fn av1_intrabc_sample_ready(
  ibc : Av1IntrabcState,
  plane : Av1IntraPlane,
  x : Int,
  y : Int,
  sub_x : Int,
  sub_y : Int,
) -> Bool {
  x >= 0 &&
  y >= 0 &&
  x < plane.width &&
  y < plane.height &&
  ibc.info.field.written[(y << sub_y) / 4 * ibc.info.field.cols +
  (x << sub_x) / 4]
}

///|
/// Integer luma DV becomes integer or half-pel motion on chroma. BILINEAR's
/// two nonzero taps at those phases reduce exactly to rounded averages at all
/// three supported bit depths, including the two-stage 12-bit rounding.
fn av1_intrabc_predict(
  state : Av1IntraState,
  ibc : Av1IntrabcState,
  block : Av1SbBlock,
  row : Int,
  col : Int,
) -> Bool {
  if !av1_intrabc_dv_valid(state, block, row, col) {
    return false
  }
  let planes = if av1_intra_has_chroma(state, block) { 3 } else { 1 }
  for plane_index in 0..<planes {
    let plane = state.planes[plane_index]
    let sx = if plane_index == 0 { 0 } else { state.sub_x }
    let sy = if plane_index == 0 { 0 } else { state.sub_y }
    let origin_x = block.col / (4 << sx) * 4
    let origin_y = block.row / (4 << sy) * 4
    let (width, height) = av1_plane_residual_size(
      block.width,
      block.height,
      plane_index,
      sx,
      sy,
    )
    let dx = col >> (3 + sx)
    let dy = row >> (3 + sy)
    let half_x = if sx == 1 { (col >> 3) & 1 } else { 0 }
    let half_y = if sy == 1 { (row >> 3) & 1 } else { 0 }
    for y in 0..<height {
      if origin_y + y >= plane.height {
        break
      }
      for x in 0..<width {
        if origin_x + x >= plane.width {
          break
        }
        let source_x = origin_x + x + dx
        let source_y = origin_y + y + dy
        let mut sum = 0
        for yy in 0..<(1 + half_y) {
          for xx in 0..<(1 + half_x) {
            if !av1_intrabc_sample_ready(
                ibc,
                plane,
                source_x + xx,
                source_y + yy,
                sx,
                sy,
              ) {
              return false
            }
            sum = sum +
              plane.pixels[(source_y + yy) * plane.width + source_x + xx]
          }
        }
        let shift = half_x + half_y
        plane.pixels[(origin_y + y) * plane.width + origin_x + x] = if shift ==
          0 {
          sum
        } else {
          (sum + (1 << (shift - 1))) >> shift
        }
      }
    }
  }
  true
}

///|
/// Publish both ordinary intra blocks and copy blocks to the candidate and
/// transform contexts. INTRA_FRAME with is_inter=true distinguishes intrabc.
fn av1_intrabc_record(
  ibc : Av1IntrabcState,
  block : Av1SbBlock,
  copy : Bool,
  row : Int,
  col : Int,
  skip : Int,
  tx_width : Int,
  tx_height : Int,
) -> Unit {
  av1_motion_field_store(
    ibc.info.field,
    block.row / 4,
    block.col / 4,
    block.width / 4,
    block.height / 4,
    AV1_INTRA_DC,
    [av1_intra_frame, av1_none_frame],
    [row, 0],
    [col, 0],
    skip~,
    interp=[3, 3],
  )
  let field = ibc.info.field
  for y in (block.row / 4)..<((block.row + block.height) / 4) {
    if y >= field.rows {
      break
    }
    for x in (block.col / 4)..<((block.col + block.width) / 4) {
      if x >= field.cols {
        break
      }
      field.is_inter[y * field.cols + x] = copy
    }
  }
  if !copy {
    av1_motion_field_store_tx(
      field,
      block.row / 4,
      block.col / 4,
      block.width / 4,
      block.height / 4,
      tx_width,
      tx_height,
    )
  }
}

///|
fn av1_intrabc_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  ibc : Av1IntrabcState,
  block : Av1SbBlock,
  block_index : Int,
  skip : Int,
) -> Bool {
  let predicted = av1_intrabc_predictor(ibc, block, state.superblock_size)
  let (row, col) = match av1_intrabc_read_dv(decoder, ibc, predicted) {
    Some(value) => value
    None => return false
  }
  if !av1_intrabc_predict(state, ibc, block, row, col) {
    return false
  }
  state.palette.y_colors = []
  state.palette.u_colors = []
  state.palette.v_colors = []
  state.palette_y_map = []
  state.palette_uv_map = []
  av1_palette_record(state.palette, block)
  let current = av1_inter_block(
    block.row / 4,
    block.col / 4,
    block.width / 4,
    block.height / 4,
    block_index,
    block.row > 0,
    block.col > 0,
  )
  current.is_inter = true
  current.skip = skip
  current.mv_row = row
  current.mv_col = col
  let (tx_width, tx_height, roots) = match
    av1_read_block_tx_size(decoder, state, ibc.info, current) {
    Some(value) => value
    None => return false
  }
  state.current = Some(current)
  av1_intra_record_modes(
    state,
    block,
    AV1_INTRA_DC,
    AV1_INTRA_DC,
    av1_intra_has_chroma(state, block),
    skip,
  )
  if !av1_intrabc_residual(
      decoder, state, current, block, tx_width, tx_height, roots,
    ) {
    return false
  }
  av1_intrabc_record(ibc, block, true, row, col, skip, tx_width, tx_height)
  av1_tx_traversal_record_size(
    state.tx_neighbors,
    {
      row: block.row,
      col: block.col,
      width: block.width,
      height: block.height,
    },
    block.width,
    block.height,
  )
  state.current = None
  true
}

///|
/// The inter walker handles arbitrary luma leaves. Align only the chroma
/// transform origins for subsampled four-pixel owners (AV1 is_chroma_reference).
fn av1_intrabc_residual(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  current : Av1InterBlock,
  block : Av1SbBlock,
  tx_width : Int,
  tx_height : Int,
  roots : Array[Array[Av1TxNode]],
) -> Bool {
  av1_cfl_begin_block(state.cfl, block, false)
  if (state.sub_x == 0 || block.width >= 8) &&
    (state.sub_y == 0 || block.height >= 8) {
    return av1_inter_residual(
      decoder, state, current, block, tx_width, tx_height, roots,
    )
  }
  // A sub-8x8 owner fits one residual chunk. Its luma tree still precedes U/V.
  if roots.is_empty() {
    if !av1_inter_residual_raster(
        decoder,
        state,
        current,
        0,
        block.col,
        block.row,
        block.width,
        block.height,
        tx_width,
        tx_height,
      ) {
      return false
    }
  } else {
    for leaves in roots {
      for leaf in leaves {
        if !av1_intra_transform(
            decoder,
            state,
            0,
            0,
            leaf.col,
            leaf.row,
            leaf.width,
            leaf.height,
            block.width,
            block.height,
            current.skip,
            inter=true,
          ) {
          return false
        }
      }
    }
  }
  if av1_intra_has_chroma(state, block) {
    for plane in 1..<3 {
      let (width, height) = av1_plane_residual_size(
        block.width,
        block.height,
        plane,
        state.sub_x,
        state.sub_y,
      )
      let (cw, ch) = av1_chroma_tx_size(width, height, state.seg_lossless)
      if !av1_inter_residual_raster(
          decoder,
          state,
          current,
          plane,
          block.col / (4 << state.sub_x) * 4,
          block.row / (4 << state.sub_y) * 4,
          width,
          height,
          cw,
          ch,
        ) {
        return false
      }
    }
  }
  true
}
