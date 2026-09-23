///|
/// Inter-frame block reconstruction: the tile leaf that mounts the inter syntax
/// of `av1_inter_mode.mbt` onto the existing partition walk, and turns it into
/// samples (AV1 §5.11.17 through §5.11.37).
///
/// The partition tree itself is shared with intra frames, so only the leaf
/// changes. An inter frame's intra blocks reuse the intra reading with the
/// inter-frame luma mode table; both share one tile entropy decoder, one set of
/// adaptive probabilities and one pair of reconstructed planes.
///
/// Everything a reference prediction has to do is here: read the motion, store
/// it into the frame's motion field, size the transforms, interpolate the
/// reference, then add the residual.

///|
/// Transform extents a coding block may reach (AV1 §5.11.15, Max_Tx_Size_Rect):
/// each axis is capped at 64 samples.
fn av1_max_rect_tx(width : Int, height : Int) -> (Int, Int) {
  (if width > 64 { 64 } else { width }, if height > 64 { 64 } else { height })
}

///|
/// Split_Tx_Size (AV1 §5.11.15): halve the long axis, or both axes when the
/// transform is square.
fn av1_tx_split(width : Int, height : Int) -> (Int, Int) {
  if width > height {
    (width / 2, height)
  } else if height > width {
    (width, height / 2)
  } else {
    (width / 2, height / 2)
  }
}

///|
/// get_tx_size( plane, txSz ) for a chroma plane (AV1 §5.11.35): the chroma
/// residual block's own maximum, with any 64-sample axis folded back to 32.
fn av1_chroma_tx_size(width : Int, height : Int, lossless : Bool) -> (Int, Int) {
  if lossless {
    return (4, 4)
  }
  let cap = av1_max_rect_tx(width, height)
  if cap.0 == 64 || cap.1 == 64 {
    if cap.0 == 16 {
      (16, 32)
    } else if cap.1 == 16 {
      (32, 16)
    } else {
      (32, 32)
    }
  } else {
    cap
  }
}

///|
/// The residual block size of one plane (AV1 §5.11.36, get_plane_residual_size
/// over the Subsampled_Size table). A residual block is never narrower or
/// shorter than four samples.
fn av1_plane_residual_size(
  width : Int,
  height : Int,
  plane : Int,
  sub_x : Int,
  sub_y : Int,
) -> (Int, Int) {
  if plane == 0 {
    return (width, height)
  }
  let scaled_w = if width >> sub_x < 4 { 4 } else { width >> sub_x }
  let scaled_h = if height >> sub_y < 4 { 4 } else { height >> sub_y }
  (scaled_w, scaled_h)
}

///|
/// get_tx_set for an inter block (AV1 §5.11.48). Sets 1 to 3 replace the two
/// intra sets; 0 means the transform type is fixed to DCT_DCT.
fn av1_inter_tx_set(width : Int, height : Int, reduced : Bool) -> Int {
  let larger = if width > height { width } else { height }
  let smaller = if width < height { width } else { height }
  let up = av1_msac_floor_log2(larger) - 2
  let sqr = av1_msac_floor_log2(smaller) - 2
  if up > 3 {
    0
  } else if reduced || up == 3 {
    3
  } else if sqr == 2 {
    2
  } else {
    1
  }
}

///|
/// Tx_Type_Inter_Inv_Set1..3 (AV1 §5.11.47): the decoded index back to a
/// transform type. Set 1 keeps the plain DCT_DCT in the middle of its range -
/// index 7, between the four colour variants and the mixed pairs - exactly as
/// libaom's `tx_type_inter_inv_set1` and libdav1d's `dav1d_tx_types_per_set`
/// lay it out.
fn av1_inter_tx_type_of(set : Int, index : Int) -> Av1TxType {
  match (set, index) {
    (1, 0) => Av1TxIdentityIdentity
    (1, 1) => Av1TxVerticalDct
    (1, 2) => Av1TxHorizontalDct
    (1, 3) => Av1TxVerticalAdst
    (1, 4) => Av1TxHorizontalAdst
    (1, 5) => Av1TxVerticalFlipadst
    (1, 6) => Av1TxHorizontalFlipadst
    (1, 7) => Av1TxDctDct
    (1, 8) => Av1TxAdstDct
    (1, 9) => Av1TxDctAdst
    (1, 10) => Av1TxFlipadstDct
    (1, 11) => Av1TxDctFlipadst
    (1, 12) => Av1TxAdstAdst
    (1, 13) => Av1TxFlipadstFlipadst
    (1, 14) => Av1TxAdstFlipadst
    (1, 15) => Av1TxFlipadstAdst
    (2, 0) => Av1TxIdentityIdentity
    (2, 1) => Av1TxVerticalDct
    (2, 2) => Av1TxHorizontalDct
    (2, 3) => Av1TxDctDct
    (2, 4) => Av1TxAdstDct
    (2, 5) => Av1TxDctAdst
    (2, 6) => Av1TxFlipadstDct
    (2, 7) => Av1TxDctFlipadst
    (2, 8) => Av1TxAdstAdst
    (2, 9) => Av1TxFlipadstFlipadst
    (2, 10) => Av1TxAdstFlipadst
    (2, 11) => Av1TxFlipadstAdst
    (3, 0) => Av1TxIdentityIdentity
    (3, 1) => Av1TxDctDct
    _ => Av1TxDctDct
  }
}

///|
/// How many transform types one inter set codes.
fn av1_inter_tx_set_symbols(set : Int) -> Int {
  match set {
    1 => 16
    2 => 12
    3 => 2
    _ => 0
  }
}

///|
/// is_tx_type_in_set for an inter block (AV1 §5.11.47): a chroma transform may
/// only reuse a luma type its own set contains.
fn av1_inter_tx_type_in_set(set : Int, tx_type : Av1TxType) -> Bool {
  match tx_type {
    Av1TxDctDct => true
    Av1TxVerticalAdst
    | Av1TxHorizontalAdst
    | Av1TxVerticalFlipadst
    | Av1TxHorizontalFlipadst => set == 1
    _ => set == 1 || set == 2 || set == 3
  }
}

///|
/// Spec TX_TYPES index of a transform type (AV1 §6.10.4). The MoonBit enum
/// carries three extra identity combinations, so the mapping is explicit.
fn av1_tx_type_code(tx_type : Av1TxType) -> Int {
  match tx_type {
    Av1TxDctDct => 0
    Av1TxAdstDct => 1
    Av1TxDctAdst => 2
    Av1TxAdstAdst => 3
    Av1TxFlipadstDct => 4
    Av1TxDctFlipadst => 5
    Av1TxFlipadstFlipadst => 6
    Av1TxAdstFlipadst => 7
    Av1TxFlipadstAdst => 8
    Av1TxIdentityIdentity => 9
    Av1TxVerticalDct => 10
    Av1TxHorizontalDct => 11
    Av1TxVerticalAdst => 12
    Av1TxHorizontalAdst => 13
    Av1TxVerticalFlipadst => 14
    Av1TxHorizontalFlipadst => 15
    _ => 0
  }
}

///|
fn av1_tx_type_of_code(code : Int) -> Av1TxType {
  match code {
    0 => Av1TxDctDct
    1 => Av1TxAdstDct
    2 => Av1TxDctAdst
    3 => Av1TxAdstAdst
    4 => Av1TxFlipadstDct
    5 => Av1TxDctFlipadst
    6 => Av1TxFlipadstFlipadst
    7 => Av1TxAdstFlipadst
    8 => Av1TxFlipadstAdst
    9 => Av1TxIdentityIdentity
    10 => Av1TxVerticalDct
    11 => Av1TxHorizontalDct
    12 => Av1TxVerticalAdst
    13 => Av1TxHorizontalAdst
    14 => Av1TxVerticalFlipadst
    15 => Av1TxHorizontalFlipadst
    _ => Av1TxDctDct
  }
}

///|
/// TxTypes[ y4 ][ x4 ] over one transform's luma footprint (AV1 §5.11.47), which
/// is what a chroma transform of the same block reads back.
fn av1_inter_record_tx_types(
  field : Av1MotionField,
  x4 : Int,
  y4 : Int,
  width : Int,
  height : Int,
  tx_type : Av1TxType,
) -> Unit {
  let code = av1_tx_type_code(tx_type)
  for row in y4..<(y4 + height / 4) {
    for col in x4..<(x4 + width / 4) {
      if row >= 0 && row < field.rows && col >= 0 && col < field.cols {
        field.tx_types[row * field.cols + col] = code
      }
    }
  }
}

///|
/// transform_type( x4, y4, txSz ) for an inter block (AV1 §5.11.47). The type is
/// only coded when the transform set offers a choice and the quantizer is not
/// zero; otherwise it is DCT_DCT, but it is still recorded for chroma.
fn av1_inter_luma_tx_type(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  info : Av1InterInfo,
  width : Int,
  height : Int,
  x4 : Int,
  y4 : Int,
) -> Av1TxType {
  let set = av1_inter_tx_set(width, height, state.reduced_tx_set)
  let sqr = av1_msac_floor_log2(if width < height { width } else { height }) - 2
  if set == 0 || state.seg_lossless {
    av1_inter_record_tx_types(info.field, x4, y4, width, height, Av1TxDctDct)
    return Av1TxDctDct
  }
  let cdfs = info.cdfs
  let index = if set == 1 {
    if sqr < 0 || sqr >= cdfs.inter_tx_type_set1.length() {
      return Av1TxDctDct
    }
    decoder.symbol(cdfs.inter_tx_type_set1[sqr])
  } else if set == 2 {
    decoder.symbol(cdfs.inter_tx_type_set2)
  } else {
    if sqr < 0 || sqr >= cdfs.inter_tx_type_set3.length() {
      return Av1TxDctDct
    }
    decoder.symbol(cdfs.inter_tx_type_set3[sqr])
  }
  if index < 0 || index >= av1_inter_tx_set_symbols(set) {
    return Av1TxDctDct
  }
  let tx_type = av1_inter_tx_type_of(set, index)
  av1_inter_record_tx_types(info.field, x4, y4, width, height, tx_type)
  tx_type
}

///|
/// compute_tx_type( plane, txSz, blockX, blockY ) for the chroma planes of an
/// inter block (AV1 §5.11.47): inherit the luma type at the transform's own
/// origin, falling back to DCT_DCT when it is outside the chroma set.
fn av1_inter_chroma_tx_type(
  state : Av1IntraState,
  info : Av1InterInfo,
  current : Av1InterBlock,
  width : Int,
  height : Int,
  x : Int,
  y : Int,
) -> Av1TxType {
  let set = av1_inter_tx_set(width, height, state.reduced_tx_set)
  if set == 0 {
    return Av1TxDctDct
  }
  let field = info.field
  let x4 = x / 4
  let y4 = y / 4
  let luma_col = if x4 << state.sub_x < current.mi_col {
    current.mi_col
  } else {
    x4 << state.sub_x
  }
  let luma_row = if y4 << state.sub_y < current.mi_row {
    current.mi_row
  } else {
    y4 << state.sub_y
  }
  if luma_row >= field.rows || luma_col >= field.cols {
    return Av1TxDctDct
  }
  let code = field.tx_types[luma_row * field.cols + luma_col]
  let tx_type = av1_tx_type_of_code(code)
  if av1_inter_tx_type_in_set(set, tx_type) {
    tx_type
  } else {
    Av1TxDctDct
  }
}

///|
/// read_var_tx_size( row, col, txSz, depth ) (AV1 §5.11.16). Positions are frame
/// MI units; leaves are collected in the order the tree is read, which is the
/// order their coefficients appear in the bitstream.
fn av1_read_var_tx_size(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  info : Av1InterInfo,
  block : Av1InterBlock,
  row : Int,
  col : Int,
  tx_width : Int,
  tx_height : Int,
  depth : Int,
  leaves : Array[Av1TxNode],
) -> Bool {
  if row >= info.mi_rows || col >= info.mi_cols {
    return true
  }
  let field = info.field
  let split = if tx_width == 4 && tx_height == 4 {
    0
  } else if depth >= 2 {
    0
  } else {
    let above = av1_above_tx_width(
      field,
      block.mi_row,
      row,
      col,
      row == block.mi_row && block.avail_u,
    )
    let left = av1_left_tx_height(
      field,
      block.mi_col,
      row,
      col,
      col == block.mi_col && block.avail_l,
    )
    let ctx = av1_txfm_split_ctx(
      above,
      left,
      block.block_width,
      block.block_height,
      tx_width,
      tx_height,
    )
    if ctx < 0 || ctx >= state.vartx.rows.length() {
      return false
    }
    decoder.symbol(state.vartx.rows[ctx])
  }
  let width4 = tx_width / 4
  let height4 = tx_height / 4
  // A node whose size class is 8x8 or smaller does not subdivide even when the
  // split symbol says otherwise: the symbol is still read, so the entropy stays
  // in step, but the node stays a leaf (libdav1d's `t_dim->max > TX_8X8`).
  let can_split = (if tx_width > tx_height { tx_width } else { tx_height }) > 8
  if split == 1 && can_split {
    let (sub_width, sub_height) = av1_tx_split(tx_width, tx_height)
    for i = 0; i < height4; i = i + sub_height / 4 {
      for j = 0; j < width4; j = j + sub_width / 4 {
        if !av1_read_var_tx_size(
            decoder,
            state,
            info,
            block,
            row + i,
            col + j,
            sub_width,
            sub_height,
            depth + 1,
            leaves,
          ) {
          return false
        }
      }
    }
    return true
  }
  av1_motion_field_store_tx(
    field, row, col, width4, height4, tx_width, tx_height,
  )
  leaves.push({
    row: (row - info.tile_row_start) * 4,
    col: (col - info.tile_col_start) * 4,
    width: tx_width,
    height: tx_height,
  })
  true
}

///|
/// read_block_tx_size( ) (AV1 §5.11.15). A non-skipped inter block under
/// TX_MODE_SELECT reads the variable transform tree; everything else reads at
/// most one tx_depth symbol. The luma result is also recorded into the frame's
/// motion field, because later blocks measure their neighbours against it.
fn av1_read_block_tx_size(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> (Int, Int, Array[Array[Av1TxNode]])? {
  let roots : Array[Array[Av1TxNode]] = []
  let (max_width, max_height) = av1_max_rect_tx(
    block.block_width,
    block.block_height,
  )
  if state.tx_mode_select &&
    block.size_index > 0 &&
    block.is_inter &&
    block.skip == 0 &&
    !state.seg_lossless {
    let (tx_w4, tx_h4) = (max_width / 4, max_height / 4)
    let mut row = block.mi_row
    while row < block.mi_row + block.height4 {
      let mut col = block.mi_col
      while col < block.mi_col + block.width4 {
        // One root per 64-pixel residual chunk, in the order residual() walks
        // them, so the leaf lists can be consumed chunk by chunk.
        let leaves : Array[Av1TxNode] = []
        roots.push(leaves)
        if !av1_read_var_tx_size(
            decoder, state, info, block, row, col, max_width, max_height, 0, leaves,
          ) {
          return None
        }
        col = col + tx_w4
      }
      row = row + tx_h4
    }
    return Some((max_width, max_height, roots))
  }
  let allow_select = !block.is_inter || block.skip == 0
  if state.seg_lossless {
    av1_motion_field_store_tx(
      info.field,
      block.mi_row,
      block.mi_col,
      block.width4,
      block.height4,
      4,
      4,
    )
    return Some((4, 4, []))
  }
  let mut tx_width = max_width
  let mut tx_height = max_height
  if allow_select && block.size_index > 0 && state.tx_mode_select {
    let context = av1_tx_depth_ctx(info, block, max_width, max_height)
    let depth = match
      av1_decode_tx_depth_for_block(
        decoder,
        state.tx_depth,
        block.block_width,
        block.block_height,
        context,
      ) {
      Some(value) => value
      None => return None
    }
    for _ in 0..<depth {
      let (next_width, next_height) = av1_tx_split(tx_width, tx_height)
      tx_width = next_width
      tx_height = next_height
    }
  }
  av1_motion_field_store_tx(
    info.field,
    block.mi_row,
    block.mi_col,
    block.width4,
    block.height4,
    tx_width,
    tx_height,
  )
  Some((tx_width, tx_height, []))
}

///|
/// tx_depth context (AV1 §9.3.4). An inter neighbour reports its own block size
/// whether or not it was skipped, and an unavailable edge reports zero rather
/// than the 64 the transform-tree contexts use.
fn av1_tx_depth_ctx(
  info : Av1InterInfo,
  block : Av1InterBlock,
  max_width : Int,
  max_height : Int,
) -> Int {
  let field = info.field
  let above = if !block.avail_u {
    0
  } else {
    let unit = (block.mi_row - 1) * field.cols + block.mi_col
    if field.is_inter[unit] {
      field.width4[unit] * 4
    } else {
      field.tx_width[unit]
    }
  }
  let left = if !block.avail_l {
    0
  } else {
    let unit = block.mi_row * field.cols + block.mi_col - 1
    if field.is_inter[unit] {
      field.height4[unit] * 4
    } else {
      field.tx_height[unit]
    }
  }
  (if above >= max_width { 1 } else { 0 }) +
  (if left >= max_height { 1 } else { 0 })
}

///|
/// compute_prediction( ) for a single-reference block (AV1 §7.11.3.1). Each plane
/// is interpolated from the reference named by the motion field at the plane's
/// own sample grid, so a chroma block that is merged with its neighbour reads the
/// neighbour's vector rather than its own.
fn av1_inter_predict(
  state : Av1IntraState,
  info : Av1InterInfo,
  block : Av1InterBlock,
  tile_block : Av1SbBlock,
) -> Bool {
  let field = info.field
  // Only the block that owns the chroma samples of a merged group predicts
  // them; the other one has no chroma syntax at all (AV1 §5.11.17).
  let plane_count = if av1_intra_has_chroma(state, tile_block) { 3 } else { 1 }
  let mut diffwtd_luma : Array[Int] = []
  for plane in 0..<plane_count {
    let sub_x = if plane == 0 { 0 } else { state.sub_x }
    let sub_y = if plane == 0 { 0 } else { state.sub_y }
    let (residual_w, residual_h) = av1_plane_residual_size(
      block.block_width,
      block.block_height,
      plane,
      sub_x,
      sub_y,
    )
    let pred_w = block.block_width >> sub_x
    let pred_h = block.block_height >> sub_y
    let base_x = (block.mi_col >> sub_x) * 4
    let base_y = (block.mi_row >> sub_y) * 4
    let cand_row = block.mi_row >> sub_y << sub_y
    let cand_col = block.mi_col >> sub_x << sub_x
    let target = state.planes[plane]
    // A LOCALWARP block with a representable model skips the whole
    // motion-compensation path: each 8x8 chunk of the plane is filtered
    // through the model itself, so there is no single subpel phase to filter
    // at and no filter symbol to read (AV1 §7.11.3.8). The warp filter works on
    // 8-pixel chunks, so libdav1d only routes a plane through it when that
    // plane's own block is at least 8x8 samples; a smaller chroma block
    // predicts through the ordinary motion-compensation path at the block's own
    // vector and the eight-tap regular filter it reads no symbol for.
    if block.motion_mode == 2 &&
      block.warp.length() == 1 &&
      pred_w >= 8 && pred_h >= 8 {
      let reference = match
        av1_inter_reference(info, field.refs[(block.mi_row * field.cols + block.mi_col) * 2]) {
        Some(value) => value
        None => return false
      }
      let prediction = av1_warp_predict(
        reference,
        block.warp[0],
        plane,
        block.mi_col,
        block.mi_row,
        base_x,
        base_y,
        pred_w,
        pred_h,
      )
      av1_motion_store(
        target.pixels,
        target.width,
        prediction,
        pred_w,
        pred_h,
        base_x - (info.tile_col_start >> sub_x) * 4,
        base_y - (info.tile_row_start >> sub_y) * 4,
        (1 << state.bit_depth) - 1,
      )
      continue
    }
    // A GLOBAL(Global)MV block whose reference carries a non-identity
    // frame-level model predicts through that model per pixel, exactly as a
    // LOCALWARP block does (AV1 §7.11.3.8). A compound block needs this for
    // each of its lists at once, so it is refused one level up instead.
    if block.motion_mode != 2 &&
      block.y_mode == av1_mode_global_mv &&
      block.ref_frame1 <= av1_intra_frame &&
      av1_gm_type(info, block.ref_frame) > av1_gm_translation &&
      info.frame.force_integer_mv == 0 {
      match av1_warp_from_global_motion(info.frame.gm_params[block.ref_frame]) {
        Some(model) => {
          let reference = match av1_inter_reference(info, block.ref_frame) {
            Some(value) => value
            None => return false
          }
          let prediction = av1_warp_predict(
            reference,
            model,
            plane,
            block.mi_col,
            block.mi_row,
            base_x,
            base_y,
            pred_w,
            pred_h,
          )
          av1_motion_store(
            target.pixels,
            target.width,
            prediction,
            pred_w,
            pred_h,
            base_x - (info.tile_col_start >> sub_x) * 4,
            base_y - (info.tile_row_start >> sub_y) * 4,
            (1 << state.bit_depth) - 1,
          )
          continue
        }
        None => ()
      }
    }
    let mut r = 0
    let mut y = 0
    while y < residual_h / 4 * 4 {
      let mut c = 0
      let mut x = 0
      while x < residual_w / 4 * 4 {
        let unit = ((cand_row + r) * field.cols + cand_col + c) * 2
        if unit + 1 >= field.refs.length() {
          return false
        }
        let name = field.refs[unit]
        if name <= av1_intra_frame {
          // An intra neighbour cannot be interpolated from; only the inter-intra
          // blend reaches here, and the frame gate refuses that tool.
          return false
        }
        let reference = match av1_inter_reference(info, name) {
          Some(value) => value
          None => return false
        }
        let second_name = field.refs[unit + 1]
        // Every branch below interpolates the block's own vector with its own
        // filters; only the compound one needs a second request.
        let single_request : Av1MotionRequest = {
          reference,
          frame_width: info.mi_cols * 4,
          frame_height: info.mi_rows * 4,
          plane,
          x: base_x + x,
          y: base_y + y,
          width: pred_w,
          height: pred_h,
          mv_row: field.mv_rows[unit],
          mv_col: field.mv_cols[unit],
          filter_vertical: field.interp_v[(cand_row + r) * field.cols + cand_col + c],
          filter_horizontal: field.interp_h[(cand_row + r) * field.cols + cand_col + c],
          compound: false,
        }
        let prediction = if block.interintra != 0 {
          // An interintra block mixes the motion-compensated prediction with an
          // intra one of this block's neighbourhood (AV1 §7.11.3.10). The intra
          // edges come from the reconstructed neighbourhood, and the weight is
          // either the mode-variant ramp or a wedge mask.
          let inter = av1_motion_compensate(single_request)
          let px = base_x + x
          let py = base_y + y
          let above : Array[Int] = []
          let left : Array[Int] = []
          if py > 0 {
            for i in 0..<pred_w {
              let col = if px + i < target.width { px + i } else { target.width - 1 }
              above.push(target.pixels[(py - 1) * target.width + col])
            }
          }
          if px > 0 {
            for i in 0..<pred_h {
              let row = if py + i < target.height { py + i } else { target.height - 1 }
              left.push(target.pixels[row * target.width + px - 1])
            }
          }
          let corner = if px > 0 && py > 0 {
            target.pixels[(py - 1) * target.width + px - 1]
          } else {
            1 << (state.bit_depth - 1)
          }
          let intra = match
            av1_intra_predict(
              av1_interintra_mode(block.interintra_mode),
              pred_w,
              pred_h,
              above,
              left,
              corner,
              state.bit_depth,
              have_above=py > 0,
              have_left=px > 0,
            ) {
            Some(value) => value
            None => return false
          }
          let weights = if block.wedge_interintra == 0 {
            // The intra-variant ramp: the intra share along one axis, scaled by
            // the block's larger dimension (AV1 §7.11.3.17).
            let big = if pred_w < pred_h { pred_h } else { pred_w }
            let scale = 128 / big
            let built = Array::make(pred_w * pred_h, 0)
            for i in 0..<pred_h {
              for j in 0..<pred_w {
                built[i * pred_w + j] = av1_ii_weight(block.interintra_mode, i, j, scale)
              }
            }
            built
          } else {
            // The wedge mask on this plane's grid (AV1 §7.11.3.11, §7.11.3.14).
            // An interintra wedge always codes a zero sign.
            let mask = av1_wedge_plane_mask(
              block.block_width,
              block.block_height,
              block.wedge_index_ii,
              0,
              sub_x,
              sub_y,
            )
            match mask {
              Some(value) => value
              None => return false
            }
          }
          let hi = (1 << state.bit_depth) - 1
          let blended = Array::make(inter.length(), 0)
          for k in 0..<blended.length() {
            let m = weights[k]
            // `interPostRound` is zero for a single-reference block, so the
            // motion-compensated prediction blends unrounded (AV1 §7.11.3.14).
            let p0 = if inter[k] < 0 { 0 } else if inter[k] > hi { hi } else { inter[k] }
            let v = (m * intra[k] + (64 - m) * p0 + 32) >> 6
            blended[k] = if v < 0 { 0 } else if v > hi { hi } else { v }
          }
          blended
        } else if second_name > av1_intra_frame {
          // A compound block interpolates both lists with the block's own
          // filters, and the intermediate results are combined one step later
          // than a single-reference decode rounds them (AV1 §7.11.3.10,
          // `interPostRound`).
          let filter_vertical = field.interp_v[(cand_row + r) * field.cols +
            cand_col +
            c]
          let filter_horizontal = field.interp_h[(cand_row + r) * field.cols +
            cand_col +
            c]
          let first_request : Av1MotionRequest = {
            reference,
            frame_width: info.mi_cols * 4,
            frame_height: info.mi_rows * 4,
            plane,
            x: base_x + x,
            y: base_y + y,
            width: pred_w,
            height: pred_h,
            mv_row: field.mv_rows[unit],
            mv_col: field.mv_cols[unit],
            filter_vertical,
            filter_horizontal,
            compound: true,
          }
          let second_reference = match av1_inter_reference(info, second_name) {
            Some(value) => value
            None => return false
          }
          let second_request : Av1MotionRequest = {
            reference: second_reference,
            frame_width: info.mi_cols * 4,
            frame_height: info.mi_rows * 4,
            plane,
            x: base_x + x,
            y: base_y + y,
            width: pred_w,
            height: pred_h,
            mv_row: field.mv_rows[unit + 1],
            mv_col: field.mv_cols[unit + 1],
            filter_vertical,
            filter_horizontal,
            compound: true,
          }
          let first = av1_motion_compensate(first_request)
          let second = av1_motion_compensate(second_request)
          let post = if state.bit_depth == 12 { 2 } else { 4 }
                  let blended = Array::make(first.length(), 0)
          if block.compound_type == av1_compound_diffwtd ||
            block.compound_type == av1_compound_wedge {
            // A masked blend: per-sample weights pick how much of each list the
            // sample takes, and the weights come either from the difference
            // between the two predictions (§7.11.3.12) or from the wedge table
            // (§7.11.3.11). The two lists are then swapped when the mask's sign
            // bit asks for the mirrored variant (§7.11.3.14).
            let weights = if block.compound_type == av1_compound_diffwtd {
              // The weights come from the luma plane: chroma takes the
              // luma mask averaged down to its sample grid, the same way
              // the wedge variant does (§7.11.3.14).
              if plane == 0 {
                let built = av1_diffwtd_mask(first, second, pred_w, pred_h, 0, 0, block.mask_type, state.bit_depth)
                diffwtd_luma = built
                built
              } else {
                av1_reduce_plane_mask(
                  diffwtd_luma,
                  block.block_width,
                  block.block_height,
                  sub_x,
                  sub_y,
                )
              }
            } else {
              let mask = av1_wedge_plane_mask(
                block.block_width,
                block.block_height,
                block.wedge_index,
                block.wedge_sign,
                sub_x,
                sub_y,
              )
              match mask {
                Some(value) => value
                None => return false
              }
            }
            let head = if block.mask_type == 0 { first } else { second }
            let tail = if block.mask_type == 0 { second } else { first }
            let shift = 6 + post
            let bias = 32 << post
            for k in 0..<blended.length() {
              let m = weights[k]
              blended[k] = (m * head[k] + (64 - m) * tail[k] + bias) >> shift
            }
          } else if block.compound_type == av1_compound_distance {
            // The distance weighting scales each list's interpolation by its
            // reference's order-hint distance (AV1 §7.11.3.15).
            let (forward, backward) = av1_distance_weights(info, name, second_name)
            let shift = 4 + post
            let bias = 1 << (shift - 1)
            for k in 0..<blended.length() {
              blended[k] = (forward * first[k] + backward * second[k] + bias) >> shift
            }
          } else {
            let shift = 1 + post
            let bias = 1 << (shift - 1)
            for k in 0..<blended.length() {
              blended[k] = (first[k] + second[k] + bias) >> shift
            }
          }
          blended
        } else {
          av1_motion_compensate(single_request)
        }
        av1_motion_store(
          target.pixels,
          target.width,
          prediction,
          pred_w,
          pred_h,
          base_x + x - (info.tile_col_start >> sub_x) * 4,
          base_y + y - (info.tile_row_start >> sub_y) * 4,
          (1 << state.bit_depth) - 1,
        )
        c = c + 1
        x = x + pred_w
      }
      r = r + 1
      y = y + pred_h
    }
    // A block that coded OBMC blends its neighbours' vectors over the strips
    // they share with it, on top of the prediction just written.
    if block.motion_mode == 1 && !av1_obmc_blend(state, info, block, plane) {
      return false
    }
  }
  true
}

///|
/// The five OBMC blending ramps (AV1 §7.11.3.9). A strip picks the ramp whose
/// extent matches its own length, so an 8-sample strip and a 32-sample one
/// reach full weight at different distances from the shared edge.
let av1_obmc_masks : Array[Array[Int]] = [
  [45, 64],
  [39, 50, 59, 64],
  [36, 42, 48, 53, 57, 61, 64, 64],
  [34, 37, 40, 43, 46, 49, 52, 54, 56, 58, 60, 61, 64, 64, 64, 64],
  [
    33, 35, 36, 38, 40, 41, 43, 44, 45, 47, 48, 50, 51, 52, 53, 55, 56, 57, 58, 59,
    60, 60, 61, 62, 64, 64, 64, 64, 64, 64, 64, 64,
  ],
]

///|
/// get_obmc_mask( length ).
fn av1_obmc_mask(length : Int) -> Array[Int] {
  if length <= 2 {
    av1_obmc_masks[0]
  } else if length <= 4 {
    av1_obmc_masks[1]
  } else if length <= 8 {
    av1_obmc_masks[2]
  } else if length <= 16 {
    av1_obmc_masks[3]
  } else {
    av1_obmc_masks[4]
  }
}

///|
/// predict_overlap for one OBMC candidate (AV1 §7.11.3.9). The neighbour's own
/// vector and its own interpolation filter interpolate a strip of the reference,
/// the strip is clipped to the sample range, and then it is blended into the
/// prediction the block already wrote into the plane.
fn av1_obmc_overlap(
  state : Av1IntraState,
  info : Av1InterInfo,
  target : Av1IntraPlane,
  plane : Int,
  tile_x : Int,
  tile_y : Int,
  limit : Int,
  cand_row : Int,
  cand_col : Int,
  x4 : Int,
  y4 : Int,
  sub_x : Int,
  sub_y : Int,
  pred_w : Int,
  pred_h : Int,
  mask : Array[Int],
  pass : Int,
) -> Bool {
  let field = info.field
  let index = cand_row * field.cols + cand_col
  let unit = index * 2
  let reference = match av1_inter_reference(info, field.refs[unit]) {
    Some(value) => value
    None => return false
  }
  let pred_x = (x4 * 4) >> sub_x
  let pred_y = (y4 * 4) >> sub_y
  let request : Av1MotionRequest = {
    reference,
    frame_width: info.mi_cols * 4,
    frame_height: info.mi_rows * 4,
    plane,
    x: pred_x,
    y: pred_y,
    width: pred_w,
    height: pred_h,
    mv_row: field.mv_rows[unit],
    mv_col: field.mv_cols[unit],
    filter_vertical: field.interp_v[index],
    filter_horizontal: field.interp_h[index],
    compound: false,
  }
  let obmc = av1_motion_compensate(request)
  for i in 0..<pred_h {
    for j in 0..<pred_w {
      let weight = if pass == 0 { mask[i] } else { mask[j] }
      let row = pred_y + i - tile_y
      let column = pred_x + j - tile_x
      if row < 0 || column < 0 || row >= target.height || column >= target.width {
        return false
      }
      let at = row * target.width + column
      let neighbour = av1_mc_clip(0, limit, obmc[i * pred_w + j])
      let blended = weight * target.pixels[at] + (64 - weight) * neighbour + 32
      target.pixels[at] = blended >> 6
    }
  }
  true
}

///|
/// overlapped_motion_compensation( ) for one plane (AV1 §7.11.3.9). The above
/// pass blends the top half of each column strip from the neighbours above and
/// the left pass blends the left half of each row strip from the neighbours to
/// the left. Both read the plane's current contents, so the two passes compose
/// in the order the specification applies them.
fn av1_obmc_blend(
  state : Av1IntraState,
  info : Av1InterInfo,
  block : Av1InterBlock,
  plane : Int,
) -> Bool {
  let field = info.field
  let sub_x = if plane == 0 { 0 } else { state.sub_x }
  let sub_y = if plane == 0 { 0 } else { state.sub_y }
  let w = block.block_width >> sub_x
  let h = block.block_height >> sub_y
  let (residual_w, residual_h) = av1_plane_residual_size(
    block.block_width,
    block.block_height,
    plane,
    sub_x,
    sub_y,
  )
  let target = state.planes[plane]
  let tile_x = (info.tile_col_start >> sub_x) * 4
  let tile_y = (info.tile_row_start >> sub_y) * 4
  let limit = (1 << state.bit_depth) - 1
  if block.avail_u && residual_w >= 8 && residual_h >= 8 {
    let log2_width = av1_msac_floor_log2(block.block_width)
    let n_limit = if 4 < log2_width { 4 } else { log2_width }
    let mut x4 = block.mi_col
    let mut count = 0
    while count < n_limit &&
          x4 < info.mi_cols &&
          x4 < block.mi_col + block.width4 {
      let cand_row = block.mi_row - 1
      let cand_col = x4 | 1
      if cand_row < 0 || cand_col < 0 || cand_col >= field.cols {
        return false
      }
      let index = cand_row * field.cols + cand_col
      let extent = field.width4[index]
      let step4 = if extent < 2 { 2 } else if extent > 16 { 16 } else { extent }
      if field.refs[index * 2] > av1_intra_frame {
        count = count + 1
        let scaled = (step4 * 4) >> sub_x
        let pred_w = if w < scaled { w } else { scaled }
        let half = 32 >> sub_y
        let pred_h = if half < h >> 1 { half } else { h >> 1 }
        if !av1_obmc_overlap(
            state,
            info,
            target,
            plane,
            tile_x,
            tile_y,
            limit,
            cand_row,
            cand_col,
            x4,
            block.mi_row,
            sub_x,
            sub_y,
            pred_w,
            pred_h,
            av1_obmc_mask(pred_h),
            0,
          ) {
          return false
        }
      }
      x4 = x4 + step4
    }
  }
  if block.avail_l {
    let log2_height = av1_msac_floor_log2(block.block_height)
    let n_limit = if 4 < log2_height { 4 } else { log2_height }
    let mut y4 = block.mi_row
    let mut count = 0
    while count < n_limit &&
          y4 < info.mi_rows &&
          y4 < block.mi_row + block.height4 {
      let cand_col = block.mi_col - 1
      let cand_row = y4 | 1
      if cand_col < 0 || cand_row < 0 || cand_row >= field.rows {
        return false
      }
      let index = cand_row * field.cols + cand_col
      let extent = field.height4[index]
      let step4 = if extent < 2 { 2 } else if extent > 16 { 16 } else { extent }
      if field.refs[index * 2] > av1_intra_frame {
        count = count + 1
        let scaled = (step4 * 4) >> sub_y
        let pred_h = if h < scaled { h } else { scaled }
        let half = 32 >> sub_x
        let pred_w = if half < w >> 1 { half } else { w >> 1 }
        if !av1_obmc_overlap(
            state,
            info,
            target,
            plane,
            tile_x,
            tile_y,
            limit,
            cand_row,
            cand_col,
            block.mi_col,
            y4,
            sub_x,
            sub_y,
            pred_w,
            pred_h,
            av1_obmc_mask(pred_w),
            1,
          ) {
          return false
        }
      }
      y4 = y4 + step4
    }
  }
  true
}

///|
/// The stored reference frame behind one reference name.
fn av1_inter_reference(info : Av1InterInfo, name : Int) -> Av1RefFrame? {
  if name < av1_last_frame || name >= info.refs.length() {
    None
  } else {
    info.refs[name]
  }
}

///|
/// residual( ) for an inter block (AV1 §5.11.34). Prediction already filled the
/// block, so every transform only adds its residual. Luma follows the transform
/// tree the block recorded; chroma keeps a uniform raster inside each 64-pixel
/// chunk, and both share the intra path's transform decoding.
fn av1_inter_residual(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1InterBlock,
  tile_block : Av1SbBlock,
  luma_width : Int,
  luma_height : Int,
  roots : Array[Array[Av1TxNode]],
) -> Bool {
  let has_chroma = av1_intra_has_chroma(state, tile_block)
  let plane_count = if has_chroma { 3 } else { 1 }
  // Motion compensation, not intra prediction, fills an inter block, so the
  // colour-from-luma state is explicitly off for the whole block.
  av1_cfl_begin_block(state.cfl, tile_block, false)
  let chunks_x = if block.block_width > 64 { block.block_width / 64 } else { 1 }
  let chunks_y = if block.block_height > 64 {
    block.block_height / 64
  } else {
    1
  }
  let chunk_width = block.block_width / chunks_x
  let chunk_height = block.block_height / chunks_y
  for chunk_y in 0..<chunks_y {
    for chunk_x in 0..<chunks_x {
      let origin_x = tile_block.col + chunk_x * chunk_width
      let origin_y = tile_block.row + chunk_y * chunk_height
      let chunk = chunk_y * chunks_x + chunk_x
      if roots.is_empty() {
        if !av1_inter_residual_raster(
            decoder, state, block, 0, origin_x, origin_y, chunk_width, chunk_height,
            luma_width, luma_height,
          ) {
          return false
        }
      } else {
        if chunk >= roots.length() {
          return false
        }
        for leaf in roots[chunk] {
          if !av1_intra_transform(
              decoder,
              state,
              0,
              0,
              leaf.col,
              leaf.row,
              leaf.width,
              leaf.height,
              chunk_width,
              chunk_height,
              block.skip,
              inter=true,
            ) {
            return false
          }
        }
      }
      for plane in 1..<plane_count {
        let sub_x = state.sub_x
        let sub_y = state.sub_y
        let (residual_w, residual_h) = av1_plane_residual_size(
          chunk_width, chunk_height, plane, sub_x, sub_y,
        )
        let (tx_width, tx_height) = av1_chroma_tx_size(
          residual_w,
          residual_h,
          state.seg_lossless,
        )
        if !av1_inter_residual_raster(
            decoder,
            state,
            block,
            plane,
            origin_x >> sub_x,
            origin_y >> sub_y,
            residual_w,
            residual_h,
            tx_width,
            tx_height,
          ) {
          return false
        }
      }
    }
  }
  true
}

///|
/// Walk one plane's transform raster inside a residual chunk.
fn av1_inter_residual_raster(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1InterBlock,
  plane : Int,
  origin_x : Int,
  origin_y : Int,
  width : Int,
  height : Int,
  tx_width : Int,
  tx_height : Int,
) -> Bool {
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      if !av1_intra_transform(
          decoder,
          state,
          plane,
          0,
          origin_x + x,
          origin_y + y,
          tx_width,
          tx_height,
          width,
          height,
          block.skip,
          inter=true,
        ) {
        return false
      }
      x = x + tx_width
    }
    y = y + tx_height
  }
  true
}

///|
/// intra_block_mode_info( ) for an intra block coded inside an inter frame
/// (AV1 §5.11.27). The luma mode reads the size-group table rather than the
/// neighbour modes an intra frame would use, and the transform size comes from
/// the same read_block_tx_size the inter branch uses.
fn av1_intra_in_inter_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  info : Av1InterInfo,
  inter : Av1InterBlock,
  block : Av1SbBlock,
  block_index : Int,
  has_chroma : Bool,
) -> Bool {
  let group = if block_index < av1_size_group.length() {
    av1_size_group[block_index]
  } else {
    return false
  }
  if group >= info.cdfs.y_mode.length() {
    return false
  }
  let y_mode = decoder.symbol(info.cdfs.y_mode[group])
  if y_mode < 0 || y_mode > 12 {
    return false
  }
  if !av1_intra_read_mode_angle(decoder, state, y_mode, block_index) {
    return false
  }
  let mut uv_mode = AV1_INTRA_DC
  if has_chroma {
    let cfl_allowed = if state.seg_lossless {
      block.width <= 8 && block.height <= 8
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
    if mode == AV1_INTRA_CFL {
      if !cfl_allowed || !av1_cfl_read_alphas(decoder, state.cfl) {
        return false
      }
    } else if !av1_intra_read_mode_angle(
        decoder,
        state,
        mode,
        block_index,
        plane=1,
      ) {
      return false
    }
    uv_mode = mode
  }
  // `palette_mode_info` (AV1 §5.11.21) sits between the uv mode and filter
  // intra, exactly as in the intra-only block path.
  if !av1_palette_read_colors(
      decoder,
      state.palette,
      block,
      state.bit_depth,
      y_mode,
      uv_mode,
      has_chroma,
      state.allow_screen_content_tools,
    ) {
    return false
  }
  // `filter_intra_mode_info` requires PaletteSizeY == 0 (AV1 §5.11.29).
  if state.enable_filter_intra &&
    y_mode == AV1_INTRA_DC &&
    state.palette.y_colors.is_empty() &&
    block.width <= 32 &&
    block.height <= 32 {
    match decoder.symbol(state.filter_intra[block_index]) {
      0 => ()
      1 => {
        let mode = decoder.symbol(state.filter_intra_mode_cdf)
        if mode < 0 || mode >= 5 {
          return false
        }
        state.filter_intra_mode = mode
      }
      _ => return false
    }
  }
  // The palette index map precedes transform-size syntax, as for an intra frame.
  if !av1_intra_palette_maps(decoder, state, block) {
    return false
  }
  inter.y_mode = y_mode
  let size = match av1_read_block_tx_size(decoder, state, info, inter) {
    Some(value) => value
    None => return false
  }
  let (tx_width, tx_height, _) = size
  av1_intra_record_modes(state, block, y_mode, uv_mode, has_chroma, inter.skip)
  if !av1_intra_residuals(
      decoder,
      state,
      block,
      y_mode,
      uv_mode,
      tx_width,
      tx_height,
      inter.skip,
    ) {
    return false
  }
  av1_tx_traversal_record_size(
    state.tx_neighbors,
    {
      row: block.row,
      col: block.col,
      width: block.width,
      height: block.height,
    },
    tx_width,
    tx_height,
  )
  true
}

///|
/// Record the tile-local mode and skip grids a later block's contexts read.
fn av1_intra_record_modes(
  state : Av1IntraState,
  block : Av1SbBlock,
  y_mode : Int,
  uv_mode : Int,
  has_chroma : Bool,
  skip : Int,
) -> Unit {
  let x4 = block.col / 4
  let y4 = block.row / 4
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
      if has_chroma {
        state.uv_modes[row * state.cols + col] = uv_mode
      }
    }
  }
}

///|
/// decode_block( ) for an inter frame (AV1 §5.11.17). The leaf replaces the
/// intra one entirely: skip may be implied by skip_mode, the block may be intra,
/// and an inter block's samples come from motion compensation rather than from
/// its own neighbourhood.
fn av1_inter_tile_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  info : Av1InterInfo,
  block : Av1SbBlock,
  partition : Av1SbPartition,
) -> Bool {
  state.prediction_partition = partition
  state.y_angle_delta = 0
  state.uv_angle_delta = 0
  state.filter_intra_mode = -1
  let block_index = match av1_intra_block_index(block.width, block.height) {
    Some(value) => value
    None => return false
  }
  let x4 = block.col / 4
  let y4 = block.row / 4
  let mi_row = info.tile_row_start + y4
  let mi_col = info.tile_col_start + x4
  let has_chroma = av1_intra_has_chroma(state, block)
  let current = av1_inter_block(
    mi_row,
    mi_col,
    block.width / 4,
    block.height / 4,
    block_index,
    mi_row > info.tile_row_start,
    mi_col > info.tile_col_start,
  )
  if !av1_read_skip_mode(decoder, info, current) {
    return false
  }
  if !current.skip_mode {
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
    current.skip = skip
  }
  // `read_segment_id` sits between skip and the CDEF index (AV1 §5.11.13), and
  // the segment it names decides the block's quantizer index from here on. A
  // block that skip mode forced to skip takes the predicted id and codes no
  // symbol, which the reader itself applies. The gate one level up refuses a
  // frame whose features would read the symbol before skip, so the preskip
  // form cannot reach this decoder.
  if state.segmentation.enabled && state.segmentation.seg_id_pre_skip {
    return false
  }
  let seg_id = av1_read_segment_id(
    decoder, state, current.mi_row, current.mi_col, current.avail_u, current.avail_l,
    current.skip, false,
  )
  av1_seg_apply_block(
    state, current.mi_row, current.mi_col, current.width4, current.height4, seg_id,
  )
  if !av1_intra_cdef_index(decoder, state, block, current.skip) {
    return false
  }
  if !av1_read_is_inter(decoder, info, current) {
    return false
  }
  if !current.is_inter {
    return av1_intra_in_inter_block(
      decoder, state, info, current, block, block_index, has_chroma,
    )
  }
  if !av1_inter_block_motion(decoder, info, current) {
    return false
  }
  // The specification writes the motion field before transform sizing and
  // before prediction, so a block's own entries are already visible to both.
  av1_motion_field_store(
    info.field,
    mi_row,
    mi_col,
    current.width4,
    current.height4,
    current.y_mode,
    [current.ref_frame, current.ref_frame1],
    [current.mv_row, current.mv_row1],
    [current.mv_col, current.mv_col1],
    skip=current.skip,
    skip_mode=if current.skip_mode { 1 } else { 0 },
    compound_idx=current.compound_idx,
    comp_group_idx=current.comp_group_idx,
    interp=[current.interp_vertical, current.interp_horizontal],
  )
  av1_intra_record_modes(
    state,
    block,
    current.y_mode,
    AV1_INTRA_DC,
    has_chroma,
    current.skip,
  )
  let sized = match av1_read_block_tx_size(decoder, state, info, current) {
    Some(value) => value
    None =>
    {
      return false
    }
  }
  let (tx_width, tx_height, roots) = sized
  state.current = Some(current)
  if !av1_inter_predict(state, info, current, block) {
    return false
  }
  if !av1_inter_residual(
      decoder, state, current, block, tx_width, tx_height, roots,
    ) {
    return false
  }
  true
}

///|
/// Which inter frames this decoder can reconstruct. Every tool left out here is
/// a second motion vector, a blend or a per-block parameter that the block stage
/// cannot yet act on; refusing the frame keeps the bitstream honest instead of
/// decoding a prefix of it.
pub fn av1_inter_frame_supported(
  header : Av1FrameHeaderInfo,
  sequence : Av1SequenceInfo,
) -> Bool {
  // `allow_intrabc` is deliberately absent: AV1 §6.8.2 reads that bit only
  // under `if ( FrameIsIntra )`, so it is never set on an inter frame and the
  // check could not fire. Intra block copy is refused one level up, where the
  // frame is actually decoded (`av1_frame_planes`).
  //
  // `allow_screen_content_tools` used to be listed here too. On an inter frame
  // it only derives `force_integer_mv`, which the MV reader already handles,
  // plus the palette syntax of `intra_block_mode_info` for intra blocks inside
  // the frame; both paths are implemented and pinned by
  // `inter_screen_content_64x64` and `inter_palette_64x64`.
  // `allow_warped_motion` used to be listed here. It is gone because the
  // three-symbol `motion_mode` branch it selects is now read correctly:
  // `find_warp_samples` decides the branch, and a block that picks LOCALWARP is
  // refused by `av1_read_motion_mode` rather than decoded with a warp this
  // decoder does not have. `inter_warped_64x64` pins both halves.
  // `use_ref_frame_mvs` used to be listed here as well. It is gone because
  // `motion_field_estimation` (§7.9.1) projects each reference's saved vectors
  // onto this frame's 8x8 grid before the tiles are decoded, and
  // `av1_temporal_scan` (§7.10.2.5) pushes them onto the candidate stack.
  // `inter_temporalmv_64x64` pins the whole chain: with the scan disabled the
  // same stream is refused rather than decoded.
  //
  // `enable_masked_compound` used to refuse the frame wholesale. It is gone
  // now that `read_compound_type` reads `comp_group_idx`, `compound_type`,
  // `wedge_index`/`wedge_sign` or `mask_type`, and the block stage can blend
  // either a difference weighting (§7.11.3.12) or a wedge mask (§7.11.3.11).
  // `inter_diffwtd_64x64` pins the difference weighting sample-exact against
  // dav1d; the wedge variant's mask table is pinned against dav1d's generated
  // `WedgeMasks` by `av1_wedge_mask_wbtest.mbt`.
  //
  // Global motion is read for every reference of an inter frame, and a
  // translation model is a plain block motion vector: `av1_setup_global_mv`
  // derives it and a GLOBAL(Global)MV block takes it from the stack, so those
  // frames decode. A rotate-zoom or affine model drives the block through the
  // per-pixel warp grid instead (see `av1_warp_predict`, which LOCALWARP also
  // uses), so the model has to be representable by that grid: a pure shear is
  // not, and neither is one whose coefficients the grid clips, which is what
  // `av1_warp_shear_params` reports. `inter_globalmv_64x64` pins the
  // translation form; the other forms need a stream that signals one.
  if !header.frame_is_intra && header.tile_payload.is_empty() {
    return false
  }
  for index in 0..<header.gm_type.length() {
    let typ = header.gm_type[index]
    if typ <= av1_gm_translation {
      continue
    }
    // A translation model is a plain block motion vector. A rotate-zoom or
    // affine model drives the block through the warp grid instead (see
    // `av1_warp_predict`, which LOCALWARP also uses), which needs the model to
    // be representable on that grid: `av1_warp_shear_params` reports the
    // shears and the clipped coefficients that are not, and an integer-motion
    // frame never takes the grid at all.
    if header.force_integer_mv != 0 {
      return false
    }
    let coefficients : Array[Int] = [0, 0, 0, 0]
    if av1_warp_shear_params(header.gm_params[index], coefficients) {
      return false
    }
  }
  true
}
