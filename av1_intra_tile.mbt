///|
/// One tile-local reconstructed plane and its coefficient neighbours. Pixels
/// include the AV1 MI padding; the visible frame rectangle is cropped only
/// after every block has been decoded.
priv struct Av1IntraPlane {
  width : Int
  height : Int
  pixels : Array[Int]
  tx_sizes : Array[Int]
  above_level : Array[Int]
  left_level : Array[Int]
  above_dc : Array[Int]
  left_dc : Array[Int]
}

///|
fn av1_intra_plane(
  width : Int,
  height : Int,
  bit_depth : Int,
  track_loop_filter? : Bool = false,
) -> Av1IntraPlane {
  {
    width,
    height,
    pixels: Array::make(width * height, 1 << (bit_depth - 1)),
    tx_sizes: if track_loop_filter {
      Array::make(width / 4 * (height / 4), 0)
    } else {
      []
    },
    above_level: Array::make(width / 4, 0),
    left_level: Array::make(height / 4, 0),
    above_dc: Array::make(width / 4, 0),
    left_dc: Array::make(height / 4, 0),
  }
}

///|
/// Tile-local mode and residual state. Each mode CDF row persists across all
/// coding blocks, including palette mode, color-cache and index probabilities.
priv struct Av1IntraState {
  cols : Int
  rows : Int
  skips : Array[Int]
  cdef : Av1CdefConfig?
  cdef_indices : Array[Int]
  skip_cdfs : Array[Array[Int]]
  y_modes : Array[Int]
  uv_modes : Array[Int]
  y_mode : Array[Array[Array[Int]]]
  uv_cfl : Array[Array[Int]]
  uv_no_cfl : Array[Array[Int]]
  cfl : Av1CflState
  angle_delta : Array[Array[Int]]
  palette : Av1PaletteState
  mut palette_y_map : Array[Int]
  mut palette_uv_map : Array[Int]
  filter_intra : Array[Array[Int]]
  filter_intra_mode_cdf : Array[Int]
  mut filter_intra_mode : Int
  tables : Av1TxEntTables
  y_coeff : Av1CoeffContext
  uv_coeff : Av1CoeffContext
  planes : Array[Av1IntraPlane]
  base_q_idx : Int
  /// Per-plane quantizer deltas; the dequant reads the plane's own index.
  quant_deltas : Av1QuantDeltas
  /// Chroma subsampling shifts (0 or 1). Plane geometry, chroma block
  /// positions and the coefficient contexts all derive from them.
  sub_x : Int
  sub_y : Int
  bit_depth : Int
  monochrome : Bool
  reduced_tx_set : Bool
  allow_screen_content_tools : Bool
  enable_filter_intra : Bool
  enable_intra_edge_filter : Bool
  superblock_size : Int
  mut prediction_block : Av1SbBlock?
  mut prediction_partition : Av1SbPartition
  mut y_angle_delta : Int
  mut uv_angle_delta : Int
  tx_mode_select : Bool
  tx_depth : Av1TxDepthState
  tx_neighbors : Av1TxTraversalState
  /// Variable-transform split rows, used only when an inter block codes a
  /// rectangular transform tree.
  vartx : Av1VarTxCdfState
  /// The per-block `segment_id` symbol's rows, one context per above/left
  /// agreement level, adapted tile-wide like every other table.
  seg_id : Array[Array[Int]]
  /// The segment id each 4x4 unit of this tile took, in decode order. It is
  /// what `get_cur_frame_segid` predicts the next block from, so it is written
  /// over the block's full 4x4 footprint exactly as `skips` is.
  seg_ids : Array[Int]
  /// The parsed `segmentation_params` of the frame being decoded; empty when
  /// the frame disabled segmentation.
  segmentation : Av1SegmentationParams
  /// This block's quantizer index: this superblock's index plus the segment's
  /// ALT_Q feature (AV1 §6.10.9). The residual's CDF rows stay at the frame's
  /// own q_category, as libdav1d's per-tile initialisation does; this index is
  /// the one the dequantisation reads.
  mut seg_q_idx : Int
  /// This superblock's quantizer index: the frame's base index accumulated with
  /// the per-superblock `delta_q` symbols (AV1 §6.10.10), clipped as libdav1d's
  /// `last_qidx` is. Block indices build on it.
  mut sb_q_idx : Int
  /// `delta_q_params` of the frame this tile belongs to: whether each
  /// superblock codes its own quantizer delta, and the scale those deltas
  /// carry.
  delta_q_present : Bool
  delta_q_res : Int
  /// The per-superblock `delta_q` symbol's row, adapted tile-wide.
  delta_q : Array[Int]
  /// This block's lossless flag: the frame is lossless and this segment's
  /// quantizer index is still zero.
  mut seg_lossless : Bool
  /// Inter-frame block state, or None for an intra frame whose leaf reads the
  /// intra syntax directly.
  inter : Av1InterInfo?
  /// The inter block whose transforms are being reconstructed; a chroma
  /// transform reads its origin to find the luma type it inherits.
  mut current : Av1InterBlock?
  restoration_units : Array[Av1RestorationUnitRecord]
}

///|
///|
/// DefaultSegmentIdCdf: three rows, one per `get_cur_frame_segid` context, over
/// `MAX_SEGMENTS - 1` symbols. libdav1d's `default_cdf.m.seg_id` in transcribed
/// form.
fn av1_seg_id_cdfs() -> Array[Array[Int]] {
  [
    [5622, 7893, 16093, 18233, 27809, 28373, 32533, 32768, 0],
    [14274, 18230, 22557, 24935, 29980, 30851, 32344, 32768, 0],
    [27527, 28487, 28723, 28890, 32397, 32647, 32679, 32768, 0],
  ]
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
  enable_intra_edge_filter? : Bool = false,
  superblock_size? : Int = 64,
  track_loop_filter? : Bool = false,
  quant_deltas? : Av1QuantDeltas = {
    y_dc: 0,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  },
  sub_x? : Int = 1,
  sub_y? : Int = 1,
  inter? : Av1InterInfo? = None,
  /// The frame's parsed `segmentation_params` (AV1 §6.10.9); empty when the
  /// frame disabled segmentation.
  segmentation? : Av1SegmentationParams? = None,
  /// `delta_q_params` (AV1 §6.10.10): whether each superblock codes its own
  /// quantizer delta and the log2 scale those deltas carry.
  delta_q_present? : Bool = false,
  delta_q_res? : Int = 0,
) -> Av1IntraState {
  let filter_intra : Array[Array[Int]] = []
  for
    probability in [
      4621, 6743, 5893, 7866, 12551, 9394, 12408, 14301, 12756, 22343, 16384, 16384,
      16384, 16384, 16384, 16384, 12770, 10368, 20229, 18101, 16384, 16384,
    ] {
    filter_intra.push([probability, 32768, 0])
  }
  let planes = [av1_intra_plane(width, height, bit_depth, track_loop_filter~)]
  if !monochrome {
    // Coded chroma extents follow ceil(width / 2^sub): the coded luma size is
    // always a multiple of 8 here, so this only matters for odd visible sizes.
    let chroma_w = (width + (1 << sub_x) - 1) >> sub_x
    let chroma_h = (height + (1 << sub_y) - 1) >> sub_y
    planes.push(
      av1_intra_plane(chroma_w, chroma_h, bit_depth, track_loop_filter~),
    )
    planes.push(
      av1_intra_plane(chroma_w, chroma_h, bit_depth, track_loop_filter~),
    )
  }
  {
    cols: width / 4,
    rows: height / 4,
    skips: Array::make(width / 4 * (height / 4), 0),
    cdef,
    cdef_indices: Array::make((width + 63) / 64 * ((height + 63) / 64), -1),
    skip_cdfs: [[31671, 32768, 0], [16515, 32768, 0], [4576, 32768, 0]],
    y_modes: Array::make(width / 4 * (height / 4), 0),
    uv_modes: Array::make(width / 4 * (height / 4), 0),
    y_mode: av1_intra_y_mode_cdfs(),
    uv_cfl: av1_intra_uv_mode_cdfs(true),
    uv_no_cfl: av1_intra_uv_mode_cdfs(false),
    cfl: av1_cfl_state(sub_x~, sub_y~),
    angle_delta: av1_intra_angle_cdfs(),
    palette: av1_palette_state(width / 4, height / 4),
    palette_y_map: [],
    palette_uv_map: [],
    filter_intra,
    filter_intra_mode_cdf: [8949, 12776, 17211, 29558, 32768, 0],
    filter_intra_mode: -1,
    tables: av1_tx_ent_tables(base_q_idx),
    y_coeff: av1_coeff_context(base_q_idx, 0, 0),
    uv_coeff: av1_coeff_context(base_q_idx, 0, 1),
    planes,
    base_q_idx,
    quant_deltas,
    sub_x,
    sub_y,
    bit_depth,
    monochrome,
    reduced_tx_set,
    allow_screen_content_tools,
    enable_filter_intra,
    enable_intra_edge_filter,
    superblock_size,
    prediction_block: None,
    prediction_partition: Av1SbPartitionNone,
    y_angle_delta: 0,
    uv_angle_delta: 0,
    tx_mode_select,
    tx_depth: av1_tx_depth_state(),
    tx_neighbors: av1_tx_traversal_state(width, height),
    vartx: av1_vartx_cdf_state(),
    seg_id: av1_seg_id_cdfs(),
    seg_ids: Array::make(width / 4 * (height / 4), 0),
    segmentation: match segmentation {
      Some(params) => params
      None => av1_segmentation_empty()
    },
    seg_q_idx: base_q_idx,
    sb_q_idx: base_q_idx,
    delta_q_present: delta_q_present,
    delta_q_res: delta_q_res,
    delta_q: av1_delta_q_cdf(),
    seg_lossless: base_q_idx == 0 && av1_quant_deltas_lossless(quant_deltas),
    inter,
    current: None,
    restoration_units: [],
  }
}

///|
/// AV1 BLOCK_* indices for every legal coding-block geometry.
fn av1_intra_block_index(width : Int, height : Int) -> Int? {
  if width == 4 && height == 4 {
    Some(0)
  } else if width == 4 && height == 8 {
    Some(1)
  } else if width == 8 && height == 4 {
    Some(2)
  } else if width == 8 && height == 8 {
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
  } else if width == 4 && height == 16 {
    Some(16)
  } else if width == 16 && height == 4 {
    Some(17)
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
/// With 4:2:0 subsampling, blocks narrower than eight luma pixels share UV
/// samples with the preceding block. Only the odd MI coordinate on each
/// sub-eight-pixel axis reads and reconstructs the shared chroma block.
/// The chroma reference rule (AV1 section 6.4.3 is_chroma_reference): on a
/// subsampled axis a luma block narrower than eight pixels only carries chroma
/// when it is the second four-pixel half of its eight-pixel group. An axis
/// without subsampling never merges.
fn av1_intra_has_chroma(state : Av1IntraState, block : Av1SbBlock) -> Bool {
  if state.monochrome {
    return false
  }
  let x_owns = if state.sub_x == 1 {
    block.width >= 8 || ((block.col / 4) & 1) != 0
  } else {
    true
  }
  let y_owns = if state.sub_y == 1 {
    block.height >= 8 || ((block.row / 4) & 1) != 0
  } else {
    true
  }
  x_owns && y_owns
}

///|
/// DefaultDeltaQCdf (libdav1d `default_cdf.m.delta_q`, a CDF3 row): the
/// per-superblock quantizer delta's symbol, read at each superblock origin when
/// the frame signals `delta_q_present`.
fn av1_delta_q_cdf() -> Array[Int] {
  [28160, 32120, 32677, 32768, 0]
}

///|
/// `read_delta_qindex` (AV1 §6.10.10, libaom `decodeframe.c`): the magnitude
/// symbol over the three-value row, extended through the hi_tok tail when it
/// saturates, then signed and scaled by `delta_q_res`. Accumulated into this
/// superblock's quantizer index exactly as libdav1d's `last_qidx` is: clipped
/// to 1..255, so a delta can never reach zero.
fn av1_read_superblock_delta_q(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
) -> Unit {
  if !state.delta_q_present {
    return
  }
  let mut delta_q = decoder.symbol(state.delta_q)
  if delta_q == 3 {
    let n_bits = 1 + av1_msac_bools(decoder, 3)
    delta_q = av1_msac_bools(decoder, n_bits) + 1 + (1 << n_bits)
  }
  if delta_q != 0 {
    let negative = av1_msac_bool(decoder) == 1
    if negative {
      delta_q = -delta_q
    }
    delta_q = delta_q << state.delta_q_res
  }
  let accumulated = state.sb_q_idx + delta_q
  state.sb_q_idx = if accumulated < 1 {
    1
  } else if accumulated > 255 {
    255
  } else {
    accumulated
  }
}

///|
/// Whether this block is the one libdav1d reads the superblock's delta from:
/// the first block of the superblock, which is a block the size of the whole
/// superblock only when the superblock is not split.
fn av1_at_superblock_origin(
  state : Av1IntraState,
  mi_row : Int,
  mi_col : Int,
) -> Bool {
  let sb_size = state.superblock_size
  (mi_col * 4) % sb_size == 0 && (mi_row * 4) % sb_size == 0
}

///|
/// Whether the superblock's first block is a whole-superblock block, which
/// suppresses the delta symbol when it is skipped (libdav1d's
/// `bs != BS_64x64/128x128 || !b->skip`).
fn av1_superblock_block_is_whole(
  width : Int,
  height : Int,
  superblock_size : Int,
) -> Bool {
  width == superblock_size && height == superblock_size
}

///|
/// `get_cur_frame_segid` (AV1 §9.3.14) plus the `segment_id` symbol that
/// follows it. The predicted id comes from the neighbours already stored for
/// this tile, and the symbol codes the difference from it, de-interleaved
/// against the frame's last active segment id. Returns the id, or -1 when the
/// frame does not write the segment map at all.
///
/// `preskip` reads the symbol before the block's skip flag; the non-preskip
/// form reads it after skip and keeps the prediction for a skipped block, so a
/// skipped block codes no symbol.
fn av1_read_segment_id(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  mi_row : Int,
  mi_col : Int,
  avail_u : Bool,
  avail_l : Bool,
  skip : Int,
  preskip : Bool,
) -> Int {
  let params = state.segmentation
  if !params.enabled || !params.update_map {
    return -1
  }
  if params.temporal_update {
    // The temporal prediction reads the previous frame's segment map, which
    // this decoder does not keep; such a frame is refused one level up.
    return -1
  }
  // The predicted id and the context come from the same three neighbours:
  // above, left, and above-left of this block's top-left corner.
  let above = if avail_u && mi_row > 0 {
    state.seg_ids[(mi_row - 1) * state.cols + mi_col]
  } else {
    0
  }
  let left = if avail_l && mi_col > 0 {
    state.seg_ids[mi_row * state.cols + mi_col - 1]
  } else {
    0
  }
  let topleft = if avail_u && avail_l && mi_row > 0 && mi_col > 0 {
    state.seg_ids[(mi_row - 1) * state.cols + mi_col - 1]
  } else {
    0
  }
  let seg_ctx = if avail_u && avail_l {
    if left == above && topleft == left {
      2
    } else if left == above || topleft == left || above == topleft {
      1
    } else {
      0
    }
  } else {
    0
  }
  let predicted = if avail_u && avail_l {
    if above == topleft { above } else { left }
  } else if avail_l {
    left
  } else if avail_u {
    above
  } else {
    0
  }
  if !preskip && skip == 1 {
    return predicted
  }
  let diff = decoder.symbol(state.seg_id[seg_ctx])
  if diff < 0 {
    return 0
  }
  let max = params.last_active_seg_id + 1
  let value = av1_seg_neg_deinterleave(diff, predicted, max)
  if value > params.last_active_seg_id || value >= av1_segments {
    0
  } else {
    value
  }
}

///|
/// `neg_deinterleave` (AV1 §5.11.16 / libdav1d `decode.c`): undo the encoder's
/// zig-zag folding of a segment id difference around the predicted id.
fn av1_seg_neg_deinterleave(diff : Int, ref : Int, max : Int) -> Int {
  if ref == 0 {
    diff
  } else if ref >= max - 1 {
    max - diff - 1
  } else if 2 * ref < max {
    if diff <= 2 * ref {
      if (diff & 1) != 0 {
        ref + ((diff + 1) >> 1)
      } else {
        ref - (diff >> 1)
      }
    } else {
      diff
    }
  } else {
    if diff <= 2 * (max - ref - 1) {
      if (diff & 1) != 0 {
        ref + ((diff + 1) >> 1)
      } else {
        ref - (diff >> 1)
      }
    } else {
      max - (diff + 1)
    }
  }
}

///|
/// This block's quantizer index: the frame's base index plus the segment's
/// ALT_Q feature, clamped to the 8-bit index range (AV1 §6.10.9).
fn av1_seg_block_qindex(state : Av1IntraState, seg_id : Int) -> Int {
  let params = state.segmentation
  let base = state.sb_q_idx
  if !params.enabled || seg_id < 0 || seg_id >= av1_segments {
    return base
  }
  let delta = params.feature_data[seg_id][av1_seg_level_alt_q]
  let value = base + delta
  if value < 0 {
    0
  } else if value > 255 {
    255
  } else {
    value
  }
}

///|
/// Apply this block's segment: its quantizer index, its lossless flag and the
/// record later blocks predict their segment id from. Does nothing when the
/// frame does not write the segment map.
fn av1_seg_apply_block(
  state : Av1IntraState,
  mi_row : Int,
  mi_col : Int,
  width4 : Int,
  height4 : Int,
  seg_id : Int,
) -> Unit {
  if seg_id < 0 {
    state.seg_q_idx = state.sb_q_idx
    state.seg_lossless = av1_frame_lossless_flag(state) && state.seg_q_idx == 0
    return
  }
  state.seg_q_idx = av1_seg_block_qindex(state, seg_id)
  state.seg_lossless = av1_frame_lossless_flag(state) && state.seg_q_idx == 0
  if state.segmentation.enabled && state.segmentation.update_map {
    for row in mi_row..<(mi_row + height4) {
      if row < 0 || row >= state.rows {
        continue
      }
      for col in mi_col..<(mi_col + width4) {
        if col < 0 || col >= state.cols {
          continue
        }
        state.seg_ids[row * state.cols + col] = seg_id
      }
    }
  }
}

///|
/// The frame's own lossless flag, which a segment ALT_Q feature can only keep
/// or lose, never restore: it is the base index being zero with every
/// quantizer delta zero (AV1 §5.9.14, §6.10.9).
fn av1_frame_lossless_flag(state : Av1IntraState) -> Bool {
  state.base_q_idx == 0 && av1_quant_deltas_lossless(state.quant_deltas)
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
  if state.seg_lossless || width >= 32 || height >= 32 {
    return Some(Av1TxDctDct)
  }
  let direction = if state.filter_intra_mode >= 0 {
    match av1_filter_intra_mode_to_intra_dir(state.filter_intra_mode) {
      Some(value) => value
      None => return None
    }
  } else {
    mode
  }
  av1_decode_intra_tx_type(
    decoder,
    state.tables,
    if width < height {
      width
    } else {
      height
    },
    direction,
    state.reduced_tx_set,
    state.seg_q_idx,
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
  inter? : Bool = false,
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
      if inter {
        match state.inter {
          Some(info) =>
            av1_inter_luma_tx_type(
              decoder, state, info, tx_width, tx_height, x4, y4,
            )
          None => return false
        }
      } else {
        match av1_intra_tx_type(decoder, state, tx_width, tx_height, mode) {
          Some(value) => value
          None => return false
        }
      }
    } else if inter {
      match state.current {
        Some(current) => {
          let info = match state.inter {
            Some(value) => value
            None => return false
          }
          av1_inter_chroma_tx_type(
            state, info, current, tx_width, tx_height, x, y,
          )
        }
        None => return false
      }
    } else if state.seg_lossless || tx_width >= 32 || tx_height >= 32 {
      Av1TxDctDct
    } else {
      match
        av1_chroma_tx_type(
          if mode == AV1_INTRA_CFL {
            AV1_INTRA_DC
          } else {
            mode
          },
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
        state.seg_q_idx,
        coeff_context,
        tx_width,
        bit_depth=state.bit_depth,
        height=tx_height,
        scan_class=av1_tx_scan_class(tx_type),
        dc_sign_ctx=if dc_sign < 0 { 1 } else if dc_sign > 0 { 2 } else { 0 },
        dc_q_idx=av1_plane_qindex(
          state.seg_q_idx,
          state.quant_deltas,
          plane_index,
          true,
        ),
        ac_q_idx=av1_plane_qindex(
          state.seg_q_idx,
          state.quant_deltas,
          plane_index,
          false,
        ),
      ) {
      Some(value) => value
      None => return false
    }
    cul_level = coeffs.cul_level
    dc_category = coeffs.dc_category
    let decoded = if state.seg_lossless {
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
  } else if inter && plane_index == 0 {
    // An all-zero luma transform still records DCT_DCT, because the block's
    // chroma transforms inherit it (AV1 §5.11.39).
    match state.inter {
      Some(info) =>
        av1_inter_record_tx_types(
          info.field,
          x4,
          y4,
          tx_width,
          tx_height,
          Av1TxDctDct,
        )
      None => ()
    }
  }
  // AV1 §5.11.39 also writes `TxTypes[...] = DCT_DCT` for an all-zero luma
  // transform of an *intra* block. That write is deliberately not mirrored here:
  // this decoder has no intra-wide TxTypes grid, and nothing on the intra path
  // would read it - a chroma transform of an intra block derives its type from
  // `Mode_To_Txfm[UVMode]` (§5.11.47), and the loop filter and the transform-size
  // state read `plane.tx_sizes`, which the tail below writes for every leaf,
  // all-zero ones included.
  let colors = if plane_index == 0 {
    state.palette.y_colors
  } else if plane_index == 1 {
    state.palette.u_colors
  } else {
    state.palette.v_colors
  }
  let prediction = if inter {
    // An inter block's prediction is already in the plane: motion compensation
    // wrote it before the residual, and reconstruct only adds and clips.
    Array::makei(tx_width * tx_height, i => {
      let row = y + i / tx_width
      let col = x + i % tx_width
      plane.pixels[(if row < plane.height { row } else { plane.height - 1 }) *
      plane.width +
      (if col < plane.width { col } else { plane.width - 1 })]
    })
  } else if !colors.is_empty() {
    let block = match state.prediction_block {
      Some(value) => value
      None => return false
    }
    let origin_x = if plane_index == 0 || state.sub_x == 0 {
      block.col
    } else {
      block.col / 8 * 4
    }
    let origin_y = if plane_index == 0 || state.sub_y == 0 {
      block.row
    } else {
      block.row / 8 * 4
    }
    let indices = if plane_index == 0 {
      state.palette_y_map
    } else {
      state.palette_uv_map
    }
    if indices.length() != block_width * block_height ||
      x < origin_x ||
      y < origin_y ||
      x - origin_x + tx_width > block_width ||
      y - origin_y + tx_height > block_height {
      return false
    }
    Array::makei(tx_width * tx_height, i => {
      colors[indices[(y - origin_y + i / tx_width) * block_width +
      x -
      origin_x +
      i % tx_width]]
    })
  } else if plane_index == 0 && state.filter_intra_mode >= 0 {
    let n_top = if y == 0 {
      0
    } else if tx_width < plane.width - x {
      tx_width
    } else {
      plane.width - x
    }
    let n_left = if x == 0 {
      0
    } else if tx_height < plane.height - y {
      tx_height
    } else {
      plane.height - y
    }
    let above = Array::makei(n_top, i => {
      plane.pixels[(y - 1) * plane.width + x + i]
    })
    let left = Array::makei(n_left, i => {
      plane.pixels[(y + i) * plane.width + x - 1]
    })
    let corner = if x > 0 && y > 0 {
      plane.pixels[(y - 1) * plane.width + x - 1]
    } else {
      1 << (state.bit_depth - 1)
    }
    match
      av1_filter_intra_predict(
        state.filter_intra_mode,
        tx_width,
        tx_height,
        above,
        left,
        corner,
        state.bit_depth,
        n_top,
        n_left,
      ) {
      Some(value) => value
      None => return false
    }
  } else if mode >= 1 && mode <= 8 {
    let block = match state.prediction_block {
      Some(value) => value
      None => return false
    }
    let tile : Av1SbBlock = {
      row: 0,
      col: 0,
      width: state.cols * 4,
      height: state.rows * 4,
    }
    let counts = match
      av1_intra_edge_counts(
        tile,
        tile.width,
        tile.height,
        block,
        state.prediction_partition,
        { row: y, col: x, width: tx_width, height: tx_height, },
        plane_index,
        state.superblock_size,
        sub_x=state.sub_x,
        sub_y=state.sub_y,
      ) {
      Some(value) => value
      None => return false
    }
    let delta = if plane_index == 0 {
      state.y_angle_delta
    } else {
      state.uv_angle_delta
    }
    let base_angles = [90, 180, 45, 135, 113, 157, 203, 67]
    let angle = base_angles[mode - 1] + 3 * delta
    let n_right = if angle < 90 { counts.n_topright } else { -1 }
    let n_bottom = if angle > 180 { counts.n_bottomleft } else { -1 }
    let above : Array[Int] = []
    for i in 0..<(counts.n_top + (if n_right > 0 { n_right } else { 0 })) {
      above.push(plane.pixels[(y - 1) * plane.width + x + i])
    }
    let left : Array[Int] = []
    for i in 0..<(counts.n_left + (if n_bottom > 0 { n_bottom } else { 0 })) {
      left.push(plane.pixels[(y + i) * plane.width + x - 1])
    }
    let corner = if counts.n_top > 0 && counts.n_left > 0 {
      plane.pixels[(y - 1) * plane.width + x - 1]
    } else {
      1 << (state.bit_depth - 1)
    }
    let neighbor_smooth = match
      av1_intra_edge_neighbor_smooth(
        tile,
        block,
        plane_index,
        state.y_modes,
        state.uv_modes,
      ) {
      Some(value) => value
      None => return false
    }
    match
      av1_directional_predict(
        mode,
        delta,
        tx_width,
        tx_height,
        above,
        left,
        corner,
        state.bit_depth,
        counts.n_top,
        counts.n_left,
        n_right,
        n_bottom,
        state.enable_intra_edge_filter,
        neighbor_smooth,
      ) {
      Some(value) => value
      None => return false
    }
  } else {
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
    match
      av1_intra_predict(
        if plane_index != 0 && mode == AV1_INTRA_CFL {
          AV1_INTRA_DC
        } else {
          mode
        },
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
  }
  if plane_index != 0 && mode == AV1_INTRA_CFL {
    if !av1_cfl_predict(
        state.cfl,
        prediction,
        tx_width,
        tx_height,
        if plane_index == 1 {
          state.cfl.alpha_u
        } else {
          state.cfl.alpha_v
        },
        state.bit_depth,
      ) {
      return false
    }
  }
  let store_luma = plane_index == 0 && state.cfl.store_y
  if store_luma {
    // CfL consumes the complete reconstructed TX, including samples that
    // the visible/coded plane write below clips away at a frame edge.
    for i in 0..<prediction.length() {
      prediction[i] = av1_intra_clip(
        prediction[i] + (if all_zero == 0 { residual[i] } else { 0 }),
        state.bit_depth,
      )
    }
    if !av1_cfl_store_tx(state.cfl, x, y, tx_width, tx_height, prediction) {
      return false
    }
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
        (if all_zero == 0 && !store_luma { residual[index] } else { 0 })
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
  if !plane.tx_sizes.is_empty() {
    let packed = tx_width | (tx_height << 8)
    for row in y4..<(if y4 + h4 < rows { y4 + h4 } else { rows }) {
      for col in x4..<(if x4 + w4 < cols { x4 + w4 } else { cols }) {
        plane.tx_sizes[row * cols + col] = packed
      }
    }
  }
  true
}

///|
/// All eight directional modes signal angle_delta for BLOCK indices >=
/// BLOCK_8X8, including 4x16/16x4. Smaller indices and nondirectional modes
/// imply zero. Store the result for the selected plane; CfL alpha syntax is
/// decoded separately.
fn av1_intra_read_mode_angle(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  mode : Int,
  block_index : Int,
  plane? : Int = 0,
) -> Bool {
  if mode < 0 || mode > 12 {
    return false
  }
  let delta = if mode >= 1 && mode <= 8 && block_index >= 3 {
    decoder.symbol(state.angle_delta[mode - 1]) - 3
  } else {
    0
  }
  if delta < -3 || delta > 3 {
    return false
  }
  if plane == 0 {
    state.y_angle_delta = delta
  } else {
    state.uv_angle_delta = delta
  }
  true
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
  inter? : Bool = false,
) -> Bool {
  state.prediction_block = Some(block)
  let has_chroma = av1_intra_has_chroma(state, block)
  let plane_count = if has_chroma { 3 } else { 1 }
  av1_cfl_begin_block(
    state.cfl,
    block,
    !state.monochrome && (!has_chroma || uv_mode == AV1_INTRA_CFL),
  )
  for chunk_y in 0..<((block.height + 63) / 64) {
    for chunk_x in 0..<((block.width + 63) / 64) {
      for plane in 0..<plane_count {
        // Plane geometry follows AV1 section 5.11.5: the chroma block size is
        // max(4, luma >> sub) per axis, and its origin rounds the luma
        // position down to the chroma reference (even MI unit) on each
        // subsampled axis (is_chroma_reference).
        let plane_sub_x = if plane == 0 { 0 } else { state.sub_x }
        let plane_sub_y = if plane == 0 { 0 } else { state.sub_y }
        let divisor_x = 1 << plane_sub_x
        let divisor_y = 1 << plane_sub_y
        let width = if plane != 0 {
          let scaled = block.width >> plane_sub_x
          if scaled < 4 {
            4
          } else {
            scaled
          }
        } else {
          block.width
        }
        let height = if plane != 0 {
          let scaled = block.height >> plane_sub_y
          if scaled < 4 {
            4
          } else {
            scaled
          }
        } else {
          block.height
        }
        let origin_x = if plane_sub_x == 1 {
          block.col / 8 * 4
        } else {
          block.col
        }
        let origin_y = if plane_sub_y == 1 {
          block.row / 8 * 4
        } else {
          block.row
        }
        let unit_width = if block.width < 64 { width } else { 64 / divisor_x }
        let unit_height = if block.height < 64 {
          height
        } else {
          64 / divisor_y
        }
        let tx_width = if plane == 0 {
          luma_tx_width
        } else if state.seg_lossless {
          4
        } else if width > 32 {
          32
        } else {
          width
        }
        let tx_height = if plane == 0 {
          luma_tx_height
        } else if state.seg_lossless {
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
                origin_x + chunk_x * (64 / divisor_x) + col,
                origin_y + chunk_y * (64 / divisor_y) + row,
                tx_width,
                tx_height,
                width,
                height,
                skip,
                inter~,
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
/// Palette maps precede transform-size and coefficient syntax, even for
/// skipped transforms. Entropy covers the coded MI rectangle; map padding
/// extends the final decoded column/row without reading additional symbols.
fn av1_intra_palette_maps(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
) -> Bool {
  state.palette_y_map = []
  state.palette_uv_map = []
  let luma_cols = if block.width < state.cols * 4 - block.col {
    block.width
  } else {
    state.cols * 4 - block.col
  }
  let luma_rows = if block.height < state.rows * 4 - block.row {
    block.height
  } else {
    state.rows * 4 - block.row
  }
  for plane in 0..<2 {
    let colors = if plane == 0 {
      state.palette.y_colors
    } else {
      state.palette.u_colors
    }
    if colors.is_empty() {
      continue
    }
    // Palette index maps are per plane pixel. On a subsampled axis a luma
    // block narrower than eight pixels shares the chroma block of its paired
    // neighbour, so the map grows to the full four-chroma-pixel unit
    // (`extra`), matching the residual block above.
    let plane_sub_x = if plane == 0 { 0 } else { state.sub_x }
    let plane_sub_y = if plane == 0 { 0 } else { state.sub_y }
    let extra_cols = if plane_sub_x == 1 && block.width < 8 { 2 } else { 0 }
    let extra_rows = if plane_sub_y == 1 && block.height < 8 { 2 } else { 0 }
    let map_width = (block.width >> plane_sub_x) + extra_cols
    let map_height = (block.height >> plane_sub_y) + extra_rows
    let indices = match
      av1_palette_decode_index_map(
        decoder,
        colors.length(),
        map_width,
        map_height,
        (luma_rows >> plane_sub_y) + extra_rows,
        (luma_cols >> plane_sub_x) + extra_cols,
        if plane == 0 {
          state.palette.y_index[colors.length() - 2]
        } else {
          state.palette.uv_index[colors.length() - 2]
        },
      ) {
      Some(value) => value
      None => return false
    }
    if plane == 0 {
      state.palette_y_map = indices
    } else {
      state.palette_uv_map = indices
    }
  }
  true
}

///|
fn av1_intra_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
  partition? : Av1SbPartition = Av1SbPartitionNone,
) -> Bool {
  match state.inter {
    Some(info) => av1_inter_tile_block(decoder, state, info, block, partition)
    None => av1_intra_only_block(decoder, state, block, partition~)
  }
}

///|
fn av1_intra_only_block(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
  block : Av1SbBlock,
  partition? : Av1SbPartition = Av1SbPartitionNone,
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
  let has_chroma = av1_intra_has_chroma(state, block)
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
  // `read_segment_id` sits between skip and the CDEF index (AV1 §5.11.13), and
  // the segment it names decides the block's quantizer index from here on.
  if state.segmentation.enabled && state.segmentation.seg_id_pre_skip {
    return false
  }
  let seg_id = av1_read_segment_id(
    decoder, state, y4, x4, y4 > 0, x4 > 0, skip, false,
  )
  if !av1_intra_cdef_index(decoder, state, block, skip) {
    return false
  }
  // The superblock's quantizer delta follows the CDEF index (AV1 §6.10.10);
  // a whole-superblock block that is skipped is the one case dav1d does not
  // read it for.
  if av1_at_superblock_origin(state, y4, x4) &&
    !(skip == 1 && av1_superblock_block_is_whole(block.width, block.height, state.superblock_size)) {
    av1_read_superblock_delta_q(decoder, state)
  }
  // The segment's ALT_Q builds on this superblock's index, so the block's
  // quantizer index is settled after the delta, not before it.
  av1_seg_apply_block(state, y4, x4, block.width / 4, block.height / 4, seg_id)
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
  if !av1_intra_read_mode_angle(decoder, state, y_mode, block_index) {
    return false
  }
  // Non-owning 4-axis blocks and monochrome streams have no UV syntax.
  // Their placeholder mode is unused because residuals process only luma.
  let uv_mode = if !has_chroma {
    AV1_INTRA_DC
  } else {
    // is_cfl_allowed differs for lossless: only a 4x4 chroma residual block
    // may use CfL, even when the luma coding block is below 32 pixels.
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
    mode
  }
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
  if !av1_intra_palette_maps(decoder, state, block) {
    return false
  }
  let root : Av1TxNode = {
    row: block.row,
    col: block.col,
    width: block.width,
    height: block.height,
  }
  let selected = if state.seg_lossless {
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
  av1_intra_record_modes(state, block, y_mode, uv_mode, has_chroma, skip)
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
  true
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
  enable_intra_edge_filter? : Bool = false,
  track_loop_filter? : Bool = false,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
  restoration_layout? : Av1RestorationLayout? = None,
  tile_origin_row_mi? : Int = 0,
  tile_origin_col_mi? : Int = 0,
  inter? : Av1InterInfo? = None,
  /// The frame's parsed `segmentation_params` (AV1 §6.10.9); empty when the
  /// frame disabled segmentation.
  segmentation? : Av1SegmentationParams? = None,
  /// `delta_q_params` (AV1 §6.10.10): whether each superblock codes its own
  /// quantizer delta and the log2 scale those deltas carry.
  delta_q_present? : Bool = false,
  delta_q_res? : Int = 0,
  quant_deltas? : Av1QuantDeltas = {
    y_dc: 0,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  },
  /// The frame entropy context this tile starts from. `None` seeds every
  /// table with the normative defaults (a frame whose primary reference
  /// names no slot, or `PRIMARY_REF_NONE`).
  frame_cdfs? : Av1FrameCdfs? = None,
  /// When present, the tile's final entropy state is captured here, so the
  /// caller can store it as the frame context (AV1 §8.3).
  cdfs_out? : Array[Av1FrameCdfs?]? = None,
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
    enable_intra_edge_filter~,
    superblock_size=if use_128x128_superblock { 128 } else { 64 },
    track_loop_filter~,
    quant_deltas~,
    sub_x~,
    sub_y~,
    inter~,
    segmentation~,
    delta_q_present~,
    delta_q_res~,
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
  // Every adaptive table the tile owns starts from the frame context, so a
  // frame that inherits one through `primary_ref_frame` decodes with the
  // reference's adapted probabilities instead of the defaults.
  av1_intra_cdfs_of(state, frame_cdfs)
  // The partition trees and the loop-restoration selectors are tile-owned like
  // the block tables: each starts from the inherited frame context.
  let cdfs = av1_partition_cdfs_of(frame_cdfs)
  let sb_size = if use_128x128_superblock { 128 } else { 64 }
  // Per-tile loop-restoration entropy state: the mode CDF rows adapt
  // across every superblock of this tile and the coefficient references
  // survive SB rows. Reset once per tile, never per SB.
  let lr_tile_state = match restoration_layout {
    Some(layout) =>
      Some(av1_restoration_tile_state_new(layout.config.modes.length()))
    None => None
  }
  match lr_tile_state {
    Some(lr_state) =>
      match frame_cdfs {
        Some(snapshot) => av1_lr_cdfs_restore(lr_state, snapshot)
        None => ()
      }
    None => ()
  }
  let mut row = 0
  while row < coded_height {
    let mut col = 0
    while col < coded_width {
      // Loop-restoration unit parameters precede this root SB's first
      // partition symbol on the shared tile entropy decoder (AV1 spec
      // §5.11.57). The SB's global coded MI rectangle, including its
      // full nominal size at the frame edge, owns the units whose
      // top-left corners fall inside it.
      match lr_tile_state {
        Some(lr_state) =>
          match restoration_layout {
            Some(layout) =>
              if !av1_restoration_read_sb(
                  decoder,
                  lr_state,
                  layout,
                  tile_origin_col_mi + col / 4,
                  tile_origin_row_mi + row / 4,
                  sb_size,
                  subsampling_x=!monochrome && sub_x == 1,
                  subsampling_y=!monochrome && sub_y == 1,
                ) {
                return None
              }
            None => ()
          }
        None => ()
      }
      if !av1_walk_partition_tree_context(
          decoder,
          cdfs,
          neighbors,
          av1_partition_node(row, col, sb_size, width, height),
          fn(reader, block, partition) {
            av1_intra_block(reader, state, block, partition~)
          },
        ) {
        return None
      }
      col = col + sb_size
    }
    row = row + sb_size
  }
  match lr_tile_state {
    Some(lr_state) =>
      for record in lr_state.units {
        state.restoration_units.push(record)
      }
    None => ()
  }
  // The context_update_tile_id tile (tile 0) ends by writing its final rows
  // into the frame context the next frame may inherit (AV1 §8.3).
  match cdfs_out {
    Some(sink) =>
      sink.push(Some(av1_frame_cdfs_capture(state, cdfs, lr_tile_state)))
    None => ()
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
  enable_intra_edge_filter? : Bool = false,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
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
      enable_intra_edge_filter~,
      sub_x~,
      sub_y~,
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
          sub_x~,
          sub_y~,
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
  let chroma_w = (width + (1 << sub_x) - 1) >> sub_x
  let chroma_h = (height + (1 << sub_y) - 1) >> sub_y
  av1_yuv_highbd_to_rgba(
    width,
    height,
    av1_intra_crop(state.planes[0], width, height),
    av1_intra_crop(state.planes[1], chroma_w, chroma_h),
    av1_intra_crop(state.planes[2], chroma_w, chroma_h),
    bit_depth,
    subsampling_x=sub_x == 1,
    subsampling_y=sub_y == 1,
    full_range~,
    matrix_coefficients~,
  )
}
