/// First executable AV1 tile milestone.
///
/// This module accepts a small, fully specified subset: a 32x32 or 64x64
/// reduced-still key frame, one tile, intra prediction, with square DCT_DCT
/// residuals for the legacy path and the full tx-mode leaf walk for frames
/// that select transform sizes. Entropy symbols are decoded from the tile
/// with the stateful MSAC reader. Other streams return None and remain
/// eligible for later milestones.

///|
/// Mutable CDF state for one transform context. UV blocks share one context
/// for the tile, as required by the AV1 symbol update process.
priv struct Av1DcContext {
  eob : Array[Int]
  base : Array[Int]
  br : Array[Int]
  sign : Array[Int]
}

///|
/// Decode an EOB=1 DC coefficient and run the exact integer inverse DCT.
fn av1_decode_single_dc(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  tx_ctx : Int,
  context : Av1DcContext,
  bit_depth? : Int = 8,
) -> Int? {
  if (tx_ctx != 3 && tx_ctx != 4) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  if decoder.symbol(context.eob) != 0 {
    return None
  }
  let mut level = decoder.symbol(context.base) + 1
  if level > 2 {
    let mut complete = false
    for _ in 0..<4 {
      if complete {
        continue
      }
      let extra = decoder.symbol(context.br)
      level = level + extra
      if extra < 3 {
        complete = true
      }
    }
  }
  let sign = decoder.symbol(context.sign)
  if level > 14 {
    let mut length = 0
    let mut terminated = false
    while length < 32 && !terminated {
      length = length + 1
      terminated = decoder.bool() == 1
    }
    if !terminated {
      return None
    }
    let mut code = 1
    for _ in 0..<(length - 1) {
      code = (code << 1) | decoder.bool()
    }
    level = code + 14
  }
  if level > 65535 {
    return None
  }
  let denom = if tx_ctx == 4 { 4 } else { 2 }
  let dq = ((level * av1_dc_quant(bit_depth, base_q_idx)) & 0xFFFFFF) / denom
  let signed = if sign == 1 { -dq } else { dq }
  let side = if tx_ctx == 4 { 64 } else { 32 }
  let coeffs : Array[Int] = Array::make(side * side, 0)
  coeffs[0] = signed
  match av1_inverse_dct_2d(coeffs, side, side, bit_depth) {
    Some(residual) => Some(residual[0])
    None => None
  }
}

///|
/// Transform size context for the all_zero CDF (AV1 spec §5.11.39:
/// txSzCtx = (Tx_Size_Sqr + Tx_Size_Sqr_Up + 1) >> 1, which for square
/// transforms is 0..4 for 4x4..64x64).
fn av1_tx_size_ctx(side : Int) -> Int {
  if side <= 4 {
    0
  } else if side == 8 {
    1
  } else if side == 16 {
    2
  } else if side == 32 {
    3
  } else {
    4
  }
}

/// Transform-size context for rectangular leaves.  AV1's Tx_Size_Sqr context
/// follows the larger transform axis, so 64x32 and 32x64 use the 64-wide row.
fn av1_tx_size_ctx_rect(width : Int, height : Int) -> Int {
  let max_side = if width > height { width } else { height }
  av1_tx_size_ctx(max_side)
}

///|
/// Luma all_zero context from the neighbour level model (AV1 spec §8.3,
/// readAllZero). `top`/`left` are the maximum neighbour cul levels over the
/// leaf's 4x4 units.
fn av1_txb_skip_ctx_luma(top : Int, left : Int, whole : Bool) -> Int {
  if whole {
    return 0
  }
  if top == 0 && left == 0 {
    return 1
  }
  if top == 0 || left == 0 {
    return if (if top > left { top } else { left }) > 3 { 3 } else { 2 }
  }
  if (if top > left { top } else { left }) <= 3 {
    return 4
  }
  if (if top < left { top } else { left }) <= 3 {
    return 5
  }
  6
}

///|
/// Chroma all_zero context (AV1 spec §8.3): 7 plus one per non-empty
/// neighbour side, plus 3 when the residual block exceeds the transform.
fn av1_txb_skip_ctx_chroma(above_nonzero : Bool, left_nonzero : Bool, whole : Bool) -> Int {
  let ctx = 7 +
    (if above_nonzero { 1 } else { 0 }) +
    (if left_nonzero { 1 } else { 0 })
  if whole {
    ctx
  } else {
    ctx + 3
  }
}

///|
/// dc_sign context from the neighbour dc categories (AV1 spec §8.3).
fn av1_dc_sign_ctx_from(above_dc : Array[Int], left_dc : Array[Int], x4 : Int, y4 : Int, width_units : Int, height_units? : Int = 0) -> Int {
  let h_units = if height_units > 0 { height_units } else { width_units }
  let mut score = 0
  for k in 0..<width_units {
    let a = above_dc[x4 + k]
    if a == 1 {
      score = score - 1
    } else if a == 2 {
      score = score + 1
    }
  }
  for k in 0..<h_units {
    let l = left_dc[y4 + k]
    if l == 1 {
      score = score - 1
    } else if l == 2 {
      score = score + 1
    }
  }
  if score < 0 {
    1
  } else if score > 0 {
    2
  } else {
    0
  }
}

///|
/// Consume the block-level filter_intra_mode_info symbols (AV1 spec
/// §5.11.45). The filter-intra predictor itself is not implemented in this
/// bounded path, so an active flag rejects the stream after the bits are
/// consumed in the correct order. Returns false when the caller must reject.
fn av1_read_filter_intra_bits(
  decoder : Av1SymbolDecoder,
  width : Int,
  y_mode : Int,
  enable_filter_intra : Bool,
) -> Bool {
  if !enable_filter_intra || y_mode != 0 || width > 32 {
    return true
  }
  let use_cdf : Array[Int] = if width >= 32 {
    [22343, 32768, 0]
  } else if width >= 16 {
    [12408, 32768, 0]
  } else if width >= 8 {
    [7866, 32768, 0]
  } else {
    [4621, 32768, 0]
  }
  if decoder.symbol(use_cdf) == 1 {
    // filter_intra_mode uses the five-symbol default CDF.
    if decoder.symbol([8949, 12776, 17211, 29558, 32768, 0]) > 4 {
      return false
    }
    return false
  }
  true
}

///|
/// Decode one intra frame block's residuals for the tx-mode multi-leaf path:
/// all luma transform leaves first, then one chroma transform per plane (AV1
/// spec residual(): chroma tx size is the plane maximum, independent of the
/// luma tx_depth). Neighbour level/dc contexts track the all_zero CDF rows.
fn av1_decode_tx_mode_residuals(
  decoder : Av1SymbolDecoder,
  tables : Av1TxEntTables,
  width : Int,
  height : Int,
  leaves : Array[Av1TxLeaf],
  base_q_idx : Int,
  y_mode : Int,
  uv_mode : Int,
  bit_depth : Int,
  reduced_tx_set : Bool,
) -> (Array[Array[Int]], Array[Array[Int]], Array[Array[Int]], Array[Av1TxType], Array[Av1TxType], Array[Av1TxType], Array[Av1TxLeaf])? {
  // Keep every transform-size CDF row alive in one context object.  The
  // selected row changes with each tx leaf (tx_depth can produce 8/16/32
  // leaves), while the arrays themselves must remain shared for adaptation.
  let y_context = av1_coeff_context(base_q_idx, 3, 0)
  let y_coeff_results : Array[Av1LeafCoeffs] = []
  let y_types : Array[Av1TxType] = []
  let units = width / 4
  let above_level : Array[Int] = Array::make(units, 0)
  let left_level : Array[Int] = Array::make(units, 0)
  let above_dc : Array[Int] = Array::make(units, 0)
  let left_dc : Array[Int] = Array::make(units, 0)
  for leaf in leaves {
    let side = leaf.node.width
    let leaf_height = leaf.node.height
    if side < 4 || side > 64 || leaf_height < 4 || leaf_height > 64 ||
      !(side == leaf_height || av1_tx_rect_supported(side, leaf_height)) {
      return None
    }
    let x4 = leaf.node.col / 4
    let y4 = leaf.node.row / 4
    let w4 = side / 4
    let h4 = leaf_height / 4
    if x4 + w4 > units || y4 + h4 > units {
      return None
    }
    let mut top = 0
    for k in 0..<w4 {
      if above_level[x4 + k] > top {
        top = above_level[x4 + k]
      }
    }
    let mut left = 0
    for k in 0..<h4 {
      if left_level[y4 + k] > left {
        left = left_level[y4 + k]
      }
    }
    let whole = side == width && leaf_height == height
    let ctx = av1_txb_skip_ctx_luma(top, left, whole)
    let y_zero = decoder.symbol(tables.txb_skip[av1_tx_size_ctx_rect(side, leaf_height)][ctx])
    if y_zero > 1 {
      return None
    }
    if y_zero == 1 {
      // A skipped transform block contributes zero level/DC context to every
      // covered 4x4 unit. Keep neighbour state consistent for following
      // leaves in raster order.
      for i in 0..<w4 {
        above_level[x4 + i] = 0
        above_dc[x4 + i] = 0
      }
      for j in 0..<h4 {
        left_level[y4 + j] = 0
        left_dc[y4 + j] = 0
      }
      y_coeff_results.push({
        coeffs: Array::make(side * leaf_height, 0),
        cul_level: 0,
        dc_category: 0,
      })
      y_types.push(Av1TxDctDct)
    } else {
      let tx_type = match
        av1_decode_intra_tx_type(decoder, tables, side, y_mode, reduced_tx_set, base_q_idx) {
        Some(value) => value
        None => return None
      }
      let dsc = av1_dc_sign_ctx_from(above_dc, left_dc, x4, y4, w4, height_units=h4)
      y_context.tx_ctx = av1_tx_size_ctx_rect(side, leaf_height)
      let decoded = match
        av1_tx_decode_leaf_nodes(
          decoder,
          base_q_idx,
          y_context,
          [leaf],
          bit_depth,
          scan_class=av1_tx_scan_class(tx_type),
          dc_sign_ctx=dsc,
        ) {
        Some(value) => value
        None => return None
      }
      let result = decoded[0]
      for i in 0..<w4 {
        above_level[x4 + i] = result.cul_level
        above_dc[x4 + i] = result.dc_category
      }
      for j in 0..<h4 {
        left_level[y4 + j] = result.cul_level
        left_dc[y4 + j] = result.dc_category
      }
      y_coeff_results.push(result)
      y_types.push(tx_type)
    }
  }
  // Chroma residual() is traversed independently from the luma transform
  // tree.  For 4:2:0 each plane is covered in raster order by transform
  // blocks at the plane maximum (32x32 for a 64x64 luma block, 16x16 for a
  // 32x32 block).  Keep the geometry explicit so larger callers can be
  // tiled without accidentally collapsing the plane into one block.
  let chroma_width = (width + 1) / 2
  let chroma_height = (height + 1) / 2
  let chroma_tx_width = if chroma_width >= 32 { 32 } else { chroma_width }
  let chroma_tx_height = if chroma_height >= 32 { 32 } else { chroma_height }
  let chroma_leaves : Array[Av1TxLeaf] = []
  let mut chroma_row = 0
  while chroma_row < chroma_height {
    let mut chroma_col = 0
    while chroma_col < chroma_width {
      let leaf_width = if chroma_width - chroma_col < chroma_tx_width {
        chroma_width - chroma_col
      } else {
        chroma_tx_width
      }
      let leaf_height = if chroma_height - chroma_row < chroma_tx_height {
        chroma_height - chroma_row
      } else {
        chroma_tx_height
      }
      if leaf_width < 4 || leaf_height < 4 ||
        !(leaf_width == leaf_height || av1_tx_rect_supported(leaf_width, leaf_height)) {
        return None
      }
      chroma_leaves.push({
        node: {
          row: chroma_row,
          col: chroma_col,
          width: leaf_width,
          height: leaf_height,
        },
        depth: 0,
      })
      chroma_col = chroma_col + chroma_tx_width
    }
    chroma_row = chroma_row + chroma_tx_height
  }
  let u_type = match av1_chroma_tx_type(uv_mode, chroma_tx_width, reduced_tx_set) {
    Some(value) => value
    None => return None
  }
  let v_type = u_type
  let mut u_results : Array[Av1LeafCoeffs] = []
  let mut v_results : Array[Av1LeafCoeffs] = []
  for plane in 0..<2 {
    // AV1's coefficient CDF tables use one shared chroma plane row for U/V;
    // the plane loop still keeps independent mutable contexts for each plane.
    let plane_idx = 1
    let context = av1_coeff_context(
      base_q_idx,
      if chroma_tx_width >= 32 { 3 } else { 2 },
      plane_idx,
    )
    let units = chroma_width / 4
    let above_level : Array[Int] = Array::make(units, 0)
    let left_level : Array[Int] = Array::make(units, 0)
    let above_dc : Array[Int] = Array::make(units, 0)
    let left_dc : Array[Int] = Array::make(units, 0)
    let results : Array[Av1LeafCoeffs] = []
    for leaf in chroma_leaves {
      let side = leaf.node.width
      let leaf_height = leaf.node.height
      let x4 = leaf.node.col / 4
      let y4 = leaf.node.row / 4
      let w4 = side / 4
      let h4 = leaf_height / 4
      let mut above_nonzero = false
      let mut left_nonzero = false
      for i in 0..<w4 {
        if above_level[x4 + i] > 0 {
          above_nonzero = true
        }
        if left_level[y4 + (if i < h4 { i } else { h4 - 1 })] > 0 {
          left_nonzero = true
        }
      }
      let whole = side == chroma_width && leaf_height == chroma_height
      let ctx = av1_txb_skip_ctx_chroma(above_nonzero, left_nonzero, whole)
      let zero = decoder.symbol(tables.txb_skip[av1_tx_size_ctx_rect(side, leaf_height)][ctx])
      if zero > 1 {
        return None
      }
      if zero == 1 {
        let skipped = {
          coeffs: Array::make(side * leaf_height, 0),
          cul_level: 0,
          dc_category: 0,
        }
        results.push(skipped)
        for i in 0..<w4 {
          above_level[x4 + i] = 0
          above_dc[x4 + i] = 0
        }
        for j in 0..<h4 {
          left_level[y4 + j] = 0
          left_dc[y4 + j] = 0
        }
      } else {
        let tx_type = if plane == 0 { u_type } else { v_type }
        let scan_class = av1_tx_scan_class(tx_type)
        let dsc = av1_dc_sign_ctx_from(above_dc, left_dc, x4, y4, w4)
        let decoded = match
          av1_tx_decode_leaf_nodes(
            decoder,
            base_q_idx,
            context,
            [leaf],
            bit_depth,
            scan_class~,
            dc_sign_ctx=dsc,
          ) {
          Some(value) => value
          None => return None
        }
        let result = decoded[0]
        results.push(result)
        for i in 0..<w4 {
          above_level[x4 + i] = result.cul_level
          above_dc[x4 + i] = result.dc_category
        }
        for j in 0..<h4 {
          left_level[y4 + j] = result.cul_level
          left_dc[y4 + j] = result.dc_category
        }
      }
    }
    if plane == 0 {
      u_results = results
    } else {
      v_results = results
    }
  }
  let y_coeffs : Array[Array[Int]] = []
  for result in y_coeff_results {
    y_coeffs.push(result.coeffs)
  }
  let u_coeffs : Array[Array[Int]] = []
  for result in u_results {
    u_coeffs.push(result.coeffs)
  }
  let v_coeffs : Array[Array[Int]] = []
  for result in v_results {
    v_coeffs.push(result.coeffs)
  }
  Some((y_coeffs, u_coeffs, v_coeffs, y_types, [u_type], [v_type], chroma_leaves))
}

///|
pub fn av1_decode_dc_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
) -> Image? {
  if (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    (bit_depth != 8 && width != 64) ||
    // The legacy single-block reader does not consume high-bit-depth AC and
    // partition syntax. tx_mode_select uses the bounded tree reader below;
    // keep the explicit rejection only for that legacy path.
    (bit_depth != 8 && tile_payload.length() > 8 && !tx_mode_select) ||
    (width != 16 && width != 32 && width != 64) ||
    (use_128x128_superblock && width != 64) ||
    (width != height && !(tx_mode_select && av1_tx_rect_supported(width, height))) ||
    base_q_idx < 0 ||
    base_q_idx > 255 ||
    tile_payload.length() == 0 ||
    tile_payload.length() > (if width == 64 { 255 } else { 64 }) {
    return None
  }
  // Try the bounded four-child SPLIT path before the legacy single-block path.
  // A failed probe leaves no shared decoder state, so normal tiles continue.
  if width == 64 && bit_depth == 8 && !tx_mode_select {
    match
      av1_decode_split_tile_64x64(
        tile_payload,
        base_q_idx,
        disable_cdf_update~,
        full_range~,
        matrix_coefficients~,
        use_128x128_superblock~,
        allow_screen_content_tools~,
      ) {
      Some(image) => return Some(image)
      None => ()
    }
  }
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  let y_coeff = av1_coeff_context(base_q_idx, 4, 0)
  let uv_coeff = av1_coeff_context(base_q_idx, 3, 1)
  let uv_dc = Av1DcContext::{
    eob: av1_dc_eob1024_cdf(base_q_idx, 1),
    base: av1_dc_base_eob_dc_cdf(base_q_idx, 3, 1),
    br: av1_dc_br_cdf(base_q_idx, 1),
    sign: av1_dc_sign_cdf(base_q_idx, 1),
  }
  // A 64x64 frame with the 128x128 sequence tool reaches the
  // child 64x64 partition node at the frame edge, so W64 CDF applies.
  let partition : Array[Int] = if width == 64 {
    [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0]
  } else {
    [18462, 20920, 23124, 27647, 28227, 29049, 29519, 30178, 31544, 32768, 0]
  }
  let skip : Array[Int] = [31671, 32768, 0]
  let y_mode : Array[Int] = [
    15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093,
    30466, 32768, 0,
  ]
  let uv_mode : Array[Int] = if width > 32 {
    // Blocks larger than 32x32 do not allow CFL_PRED and use the dedicated
    // uv_mode table row (AV1 spec uv_mode()).
    [
      22631, 24152, 25378, 25661, 25986, 26520, 27055, 27923, 28244, 30059,
      30941, 31961, 32768, 0,
    ]
  } else {
    // Up to 32x32 CFL_PRED is allowed, switching the uv_mode CDF table.
    [
      10407, 11208, 12900, 13181, 13823, 14175, 14899, 15656, 15986, 20086,
      20995, 22455, 24212, 32768, 0,
    ]
  }
  let luma_zero : Array[Int] = if width == 64 {
    if base_q_idx <= 20 {
      [6308, 32768, 0]
    } else if base_q_idx <= 60 {
      [26584, 32768, 0]
    } else if base_q_idx <= 120 {
      [28573, 32768, 0]
    } else {
      [31539, 32768, 0]
    }
  } else if base_q_idx <= 20 {
    [17920, 32768, 0]
  } else if base_q_idx <= 60 {
    [26726, 32768, 0]
  } else if base_q_idx <= 120 {
    [30669, 32768, 0]
  } else {
    [31671, 32768, 0]
  }
  let chroma_zero : Array[Int] = if width == 64 {
    if base_q_idx <= 20 {
      [1366, 32768, 0]
    } else if base_q_idx <= 60 {
      [5583, 32768, 0]
    } else if base_q_idx <= 120 {
      [5124, 32768, 0]
    } else {
      [4656, 32768, 0]
    }
  } else if base_q_idx <= 20 {
    [3778, 32768, 0]
  } else if base_q_idx <= 60 {
    [4215, 32768, 0]
  } else if base_q_idx <= 120 {
    [3648, 32768, 0]
  } else {
    [3440, 32768, 0]
  }
  if decoder.symbol(partition) != 0 || decoder.symbol(skip) != 0 {
    return None
  }
  let y_mode_symbol = decoder.symbol(y_mode)
  let uv_mode_symbol = decoder.symbol(uv_mode)
  if uv_mode_symbol != 0 && !tx_mode_select {
    return None
  }
  if allow_screen_content_tools {
    let palette_y : Array[Int] = if width == 64 {
      [32450, 32768, 0]
    } else {
      [32309, 32768, 0]
    }
    if y_mode_symbol == 0 && decoder.symbol(palette_y) != 0 {
      return None
    }
    // The chroma palette flag follows the luma flag and is only signalled
    // for DC_PRED luma blocks (AV1 spec palette_mode_info).
    if y_mode_symbol == 0 && decoder.symbol([32461, 32768, 0]) != 0 {
      return None
    }
  }
  // filter_intra_mode_info is part of the block mode info for both tx modes.
  if !av1_read_filter_intra_bits(decoder, width, y_mode_symbol, enable_filter_intra) {
    return None
  }
  if tx_mode_select {
    // Keep tx_depth CDF rows and neighbour dimensions alive for the complete
    // tile traversal.  The first block has unavailable edges (context 0);
    // subsequent blocks can reuse this state when block traversal expands.
    let tx_depth_state = av1_tx_depth_state()
    let tx_traversal_state = av1_tx_traversal_state(width, height)
    let root = { row: 0, col: 0, width, height }
    let tx_depth_context = av1_tx_depth_context_for_node(tx_traversal_state, root)
    let leaves = match av1_decode_tx_tree_with_state(
      decoder,
      tx_depth_state,
      root,
      tx_depth_context,
    ) {
      Some(value) => value
      None => return None
    }
      let assembled = match
        av1_decode_tx_mode_residuals(
        decoder,
        av1_tx_ent_tables(base_q_idx),
        width,
        height,
        leaves,
        base_q_idx,
        y_mode_symbol,
        uv_mode_symbol,
        bit_depth,
        reduced_tx_set,
        ) {
        Some(value) => value
        None => return None
      }
      let (y_coeffs, u_coeffs, v_coeffs, y_types, u_types, v_types, chroma_leaves) = assembled
      let image = av1_reconstruct_tx_rgba(
        width, height, leaves, y_coeffs,
        chroma_leaves, u_coeffs, chroma_leaves, v_coeffs,
        y_mode_symbol, uv_mode_symbol, y_types, u_types, v_types, bit_depth,
        full_range~, matrix_coefficients~,
      )
      // Record the completed block only after all syntax and reconstruction
      // succeeds; failed probes must not leak neighbour dimensions.
      return match image {
        Some(value) => {
          av1_tx_traversal_record(tx_traversal_state, root)
          Some(value)
        }
        None => None
      }
    }
  let y_prediction = match
    av1_intra_predict(
      y_mode_symbol,
      width,
      height,
      [],
      [],
      0,
      bit_depth,
      have_above=false,
      have_left=false,
    ) {
    Some(value) => value
    None => return None
  }
  let luma_all_zero = decoder.symbol(luma_zero)
  let mut y_residual : Array[Int] = Array::make(width * height, 0)
  let mut y_tx_type = Av1TxDctDct
  if luma_all_zero == 0 {
    if tx_mode_select {
      let tx_type = match
        av1_decode_intra_tx_type(
          decoder,
          av1_tx_ent_tables(base_q_idx),
          width,
          y_mode_symbol,
          reduced_tx_set,
          base_q_idx,
        ) {
        Some(value) => value
        None => return None
      }
      match tx_type {
        Av1TxDctDct => ()
        _ => return None
      }
      y_tx_type = tx_type
    }
    if width != 64 {
      return None
    }
    let leaf_coeffs = match
      av1_decode_coeffs_leaf_with_decoder(
        decoder,
        base_q_idx,
        y_coeff,
        64,
        bit_depth~,
      ) {
      Some(value) => value
      None => return None
    }
    y_residual = match
      av1_inverse_transform_2d(y_tx_type, leaf_coeffs.coeffs, 64, 64, bit_depth) {
      Some(value) => value
      None => return None
    }
  } else if luma_all_zero != 1 {
    return None
  }
  let cu = decoder.symbol(chroma_zero)
  let chroma_size = width / 2
  let mut u_residual : Array[Int] = Array::make(chroma_size * chroma_size, 0)
  if cu == 0 {
    if width == 64 {
      let coefficients = match
        av1_decode_coeffs_square_with_decoder(
          decoder,
          base_q_idx,
          uv_coeff,
          bit_depth~,
        ) {
        Some(value) => value
        None => return None
      }
      u_residual = match av1_inverse_dct_2d(coefficients, 32, 32, bit_depth) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(
        decoder, base_q_idx, 3, uv_dc, bit_depth~,
      ) {
        Some(value) => value
        None => return None
      }
      u_residual = Array::make(chroma_size * chroma_size, residual)
    }
  } else if cu != 1 {
    return None
  }
  let cv = decoder.symbol(chroma_zero)
  let mut v_residual : Array[Int] = Array::make(chroma_size * chroma_size, 0)
  if cv == 0 {
    if width == 64 {
      let coefficients = match
        av1_decode_coeffs_square_with_decoder(
          decoder,
          base_q_idx,
          uv_coeff,
          bit_depth~,
        ) {
        Some(value) => value
        None => return None
      }
      v_residual = match av1_inverse_dct_2d(coefficients, 32, 32, bit_depth) {
        Some(value) => value
        None => return None
      }
    } else {
      let residual = match av1_decode_single_dc(
        decoder, base_q_idx, 3, uv_dc, bit_depth~,
      ) {
        Some(value) => value
        None => return None
      }
      v_residual = Array::make(chroma_size * chroma_size, residual)
    }
  } else if cv != 1 {
    return None
  }
  let y : Array[Int] = []
  let u : Array[Int] = []
  let v : Array[Int] = []
  let neutral = 1 << (bit_depth - 1)
  for i in 0..<y_residual.length() {
    y.push(y_prediction[i] + y_residual[i])
  }
  for i in 0..<(chroma_size * chroma_size) {
    u.push(neutral + u_residual[i])
    v.push(neutral + v_residual[i])
  }
  av1_yuv420_highbd_to_rgba(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
    full_range~,
    matrix_coefficients~,
  )
}

///|
/// Decodes a reduced-still AV1 OBU stream when it matches the first tile
/// milestone. The input is the AV1 item payload extracted from AVIF.
pub fn av1_decode(data : Array[Byte]) -> Image? {
  let sequence = av1_sequence_info(data)
  let seq = match sequence {
    None => return None
    Some(value) => value
  }
  let frames = av1_obu_payloads(data, 6)
  if seq.matrix_coefficients != 1 &&
    seq.matrix_coefficients != 2 &&
    seq.matrix_coefficients != 5 &&
    seq.matrix_coefficients != 6 {
    return None
  }
  if frames.length() == 0 {
    return None
  }
  let header = av1_parse_stage1_frame(frames[0], seq, allow_highbd=true)
  match header {
    None => None
    Some(frame) =>
      av1_decode_dc_tile(
        seq.width,
        seq.height,
        frame.tile_payload,
        frame.base_q_idx,
        disable_cdf_update=frame.disable_cdf_update,
        allow_screen_content_tools=frame.allow_screen_content_tools,
        full_range=seq.full_range,
        matrix_coefficients=seq.matrix_coefficients,
        use_128x128_superblock=seq.use_128x128_superblock,
        bit_depth=seq.bit_depth,
        tx_mode_select=frame.tx_mode_select,
        reduced_tx_set=frame.reduced_tx_set,
        enable_filter_intra=seq.enable_filter_intra,
      )
  }
}

///|
/// Decodes an AVIF container through the same pure MoonBit stage-one tile
/// path. Unsupported profiles and non-DC tiles return None; a validated
/// auxiliary alpha item is composed by `avif_decode_rgba` after this primary
/// image decode succeeds.
pub fn avif_decode(data : Array[Byte]) -> Image? {
  let input = avif_stage1_input(data)
  match input {
    None => None
    Some(value) =>
      av1_decode_dc_tile(
        value.width,
        value.height,
        value.tile_payload,
        value.base_q_idx,
        disable_cdf_update=value.disable_cdf_update,
        allow_screen_content_tools=value.allow_screen_content_tools,
        full_range=value.full_range,
        matrix_coefficients=value.matrix_coefficients,
        use_128x128_superblock=value.use_128x128_superblock,
        bit_depth=value.bit_depth,
        tx_mode_select=value.tx_mode_select,
        reduced_tx_set=value.reduced_tx_set,
        enable_filter_intra=value.enable_filter_intra,
      )
  }
}

///|
test "single DC helper decodes a chroma coefficient" {
  let decoder = av1_msac_new([b'\x00', b'\x00'], false)
  let context = Av1DcContext::{
    eob: av1_dc_eob1024_cdf(33, 1),
    base: av1_dc_base_eob_dc_cdf(33, 3, 1),
    br: av1_dc_br_cdf(33, 1),
    sign: av1_dc_sign_cdf(33, 1),
  }
  let residual = av1_decode_single_dc(decoder, 33, 3, context).unwrap()
  assert_eq(residual, 0)
}

///|
test "tx size context maps square transforms to rows" {
  assert_eq(av1_tx_size_ctx(4), 0)
  assert_eq(av1_tx_size_ctx(8), 1)
  assert_eq(av1_tx_size_ctx(16), 2)
  assert_eq(av1_tx_size_ctx(32), 3)
  assert_eq(av1_tx_size_ctx(64), 4)
}

///|
test "txb skip context ladder follows the neighbour model" {
  // A single transform covering the whole residual block uses context 0.
  assert_eq(av1_txb_skip_ctx_luma(0, 0, true), 0)
  // Nothing decoded above or left uses context 1.
  assert_eq(av1_txb_skip_ctx_luma(0, 0, false), 1)
  // One empty side uses context 2 (or 3 when the other level exceeds 3).
  assert_eq(av1_txb_skip_ctx_luma(0, 2, false), 2)
  assert_eq(av1_txb_skip_ctx_luma(0, 9, false), 3)
  // Both sides populated.
  assert_eq(av1_txb_skip_ctx_luma(2, 2, false), 4)
  assert_eq(av1_txb_skip_ctx_luma(9, 2, false), 5)
  assert_eq(av1_txb_skip_ctx_luma(9, 9, false), 6)
  // Chroma context offsets from 7 and grows with neighbour occupancy.
  assert_eq(av1_txb_skip_ctx_chroma(false, false, true), 7)
  assert_eq(av1_txb_skip_ctx_chroma(true, false, true), 8)
  assert_eq(av1_txb_skip_ctx_chroma(true, true, true), 9)
  assert_eq(av1_txb_skip_ctx_chroma(true, true, false), 12)
}

///|
test "dc sign context scores neighbour categories" {
  let above : Array[Int] = [0, 0, 2, 0]
  let left : Array[Int] = [1, 0, 0, 0]
  // +1 from the positive DC above, -1 from the negative DC left: neutral.
  assert_eq(av1_dc_sign_ctx_from(above, left, 0, 0, 4), 0)
  assert_eq(av1_dc_sign_ctx_from([2, 2, 2, 2], [0, 0, 0, 0], 0, 0, 4), 2)
  assert_eq(av1_dc_sign_ctx_from([1, 1, 1, 1], [0, 0, 0, 0], 0, 0, 4), 1)
}
