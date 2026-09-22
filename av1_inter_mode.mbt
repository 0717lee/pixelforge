///|
/// Inter-frame block mode syntax (AV1 §5.11.20 through §5.11.30).
///
/// This file reads bits: it turns a tile's entropy stream into one block's
/// reference frame, motion vector, interpolation filters and mode. The candidate
/// stack those trees predict against is derived in `av1_mv.mbt`, and the samples
/// they select are interpolated in `av1_mc.mbt`.
///
/// Every probability row here is a per-tile mutable copy, because a tile adapts
/// its probabilities as it decodes. Grouping them in one struct lets a frame
/// context be snapshotted and restored as a unit.
///
/// Scope: single reference prediction. Compound, overlapped and warped motion,
/// inter-intra blending, intra block copy and segmentation each add either a
/// second motion vector or a blend, and the frame gate refuses a frame that
/// allows them, so nothing below reads syntax it cannot act on.

///|
/// Motion vector joints (AV1 §6.10.18): which of the two components is nonzero.
/// The zero joint needs no constant; it is the branch that reads neither.
let av1_mv_joint_hnzvz : Int = 1

///|
let av1_mv_joint_hzvnz : Int = 2

///|
let av1_mv_joint_hnzvnz : Int = 3

///|
/// Half-pel magnitudes coded by motion vector class 0 (AV1 §6.10.18).
let av1_class0_size : Int = 2

///|
/// Size_Group[ MiSize ] (AV1 §9.3): the context an intra block inside an inter
/// frame uses for its luma mode, and the base of the inter-intra contexts. One
/// row per size class.
let av1_size_group : Array[Int] = [
  0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 0, 0, 1, 1, 2, 2,
]

///|
/// ref_count_ctx( counts0, counts1 ) (AV1 §9.3.4).
fn av1_ref_count_ctx(counts0 : Int, counts1 : Int) -> Int {
  if counts0 < counts1 {
    0
  } else if counts0 == counts1 {
    1
  } else {
    2
  }
}

///|
/// Mutable inter probability rows for one tile. The `mv_*` arrays replicate the
/// normative one-dimensional defaults over the motion vector context (inter, or
/// intra block copy) and the vector component, because a tile adapts every copy
/// separately.
priv struct Av1InterCdfs {
  single_ref : Array[Array[Array[Int]]]
  new_mv : Array[Array[Int]]
  zero_mv : Array[Array[Int]]
  ref_mv : Array[Array[Int]]
  drl_mode : Array[Array[Int]]
  is_inter : Array[Array[Int]]
  skip_mode : Array[Array[Int]]
  interp_filter : Array[Array[Int]]
  use_obmc : Array[Array[Int]]
  motion_mode : Array[Array[Int]]
  y_mode : Array[Array[Int]]
  inter_tx_type_set1 : Array[Array[Int]]
  inter_tx_type_set2 : Array[Int]
  inter_tx_type_set3 : Array[Array[Int]]
  mv_joint : Array[Array[Int]]
  mv_sign : Array[Array[Array[Int]]]
  mv_class : Array[Array[Array[Int]]]
  mv_class0_bit : Array[Array[Array[Int]]]
  mv_class0_fr : Array[Array[Array[Array[Int]]]]
  mv_class0_hp : Array[Array[Array[Int]]]
  mv_bit : Array[Array[Array[Array[Int]]]]
  mv_fr : Array[Array[Array[Int]]]
  mv_hp : Array[Array[Array[Int]]]
  comp_mode : Array[Array[Int]]
  comp_ref_type : Array[Array[Int]]
  compound_mode : Array[Array[Int]]
  uni_comp_ref : Array[Array[Array[Int]]]
  comp_ref : Array[Array[Array[Int]]]
  comp_bwd_ref : Array[Array[Array[Int]]]
  compound_type : Array[Array[Int]]
}

///|
/// Replicate a `[component][row]` default table over the motion vector context.
fn av1_mv_ctx_rows(table : Array[Array[Int]]) -> Array[Array[Array[Int]]] {
  Array::makei(2, fn(_) { table.map(fn(row) { row.copy() }) })
}

///|
/// Replicate a flat default table over the motion vector context and component.
fn av1_mv_ctx_comp_rows(row : Array[Int]) -> Array[Array[Array[Int]]] {
  Array::makei(2, fn(_) { Array::makei(2, fn(_) { row.copy() }) })
}

///|
/// Fresh rows for one tile. Retain the result for the tile's lifetime: a second
/// call silently restarts probability adaptation.
fn av1_inter_cdfs() -> Av1InterCdfs {
  {
    single_ref: av1_single_ref_cdfs(),
    new_mv: av1_new_mv_cdfs(),
    zero_mv: av1_zero_mv_cdfs(),
    ref_mv: av1_ref_mv_cdfs(),
    drl_mode: av1_drl_mode_cdfs(),
    is_inter: av1_is_inter_cdfs(),
    skip_mode: av1_skip_mode_cdfs(),
    interp_filter: av1_interp_filter_cdfs(),
    use_obmc: av1_use_obmc_cdfs(),
    motion_mode: av1_motion_mode_cdfs(),
    y_mode: av1_y_mode_cdfs(),
    inter_tx_type_set1: av1_inter_tx_type_set1_cdfs(),
    inter_tx_type_set2: av1_inter_tx_type_set2_cdfs(),
    inter_tx_type_set3: av1_inter_tx_type_set3_cdfs(),
    mv_joint: Array::makei(2, fn(_) { av1_mv_joint_cdfs() }),
    mv_sign: av1_mv_ctx_comp_rows(av1_mv_sign_cdfs()),
    mv_class: av1_mv_ctx_rows(av1_mv_class_cdfs()),
    mv_class0_bit: av1_mv_ctx_comp_rows(av1_mv_class0_bit_cdfs()),
    mv_class0_fr: Array::makei(2, fn(_) {
      av1_mv_class0_fr_cdfs().map(fn(rows) { rows.map(fn(row) { row.copy() }) })
    }),
    mv_class0_hp: av1_mv_ctx_comp_rows(av1_mv_class0_hp_cdfs()),
    mv_bit: Array::makei(2, fn(_) {
      Array::makei(2, fn(_) { av1_mv_bit_cdfs().map(fn(row) { row.copy() }) })
    }),
    mv_fr: av1_mv_ctx_rows(av1_mv_fr_cdfs()),
    mv_hp: av1_mv_ctx_comp_rows(av1_mv_hp_cdfs()),
    comp_mode: av1_comp_mode_cdfs(),
    comp_ref_type: av1_comp_ref_type_cdfs(),
    compound_mode: av1_compound_mode_cdfs(),
    uni_comp_ref: av1_uni_comp_ref_cdfs(),
    comp_ref: av1_comp_ref_cdfs(),
    comp_bwd_ref: av1_comp_bwd_ref_cdfs(),
    compound_type: av1_compound_type_cdfs(),
  }
}

///|
/// The frame- and tile-level state every inter block of one tile reads. `refs` is
/// indexed by reference name (`av1_last_frame` through `av1_alt_ref_frame`), and
/// `None` marks a slot the reference buffer has never filled.
priv struct Av1InterInfo {
  cdfs : Av1InterCdfs
  field : Av1MotionField
  frame : Av1MvFrame
  refs : Array[Av1RefFrame?]
  /// `interpolation_filter`: 4 (`av1_interp_switchable`) means each block codes
  /// its own; anything else fixes both directions.
  interpolation_filter : Int
  enable_dual_filter : Bool
  skip_mode_present : Bool
  skip_mode_frame : Array[Int]
  /// `reference_select`: whether `read_ref_frames` may read `comp_mode` at all.
  reference_select : Bool
  /// Sequence-level masked-compound switches. `read_compound_type` reads its
  /// symbols only when one of them is set; the frame gate refuses such frames,
  /// so the decoder here rejects the stream instead of guessing a blend.
  enable_masked_compound : Bool
  enable_jnt_comp : Bool
  /// Frame dimensions in MI units; the motion field spans the whole frame.
  mi_cols : Int
  mi_rows : Int
  /// This tile's coded rectangle in MI units, exclusive at the end.
  tile_row_start : Int
  tile_col_start : Int
  tile_row_end : Int
  tile_col_end : Int
}

///|
/// One block's decoded inter syntax, in the fields the reconstruction and the
/// neighbour contexts of later blocks need.
pub(all) struct Av1InterBlock {
  mi_row : Int
  mi_col : Int
  width4 : Int
  height4 : Int
  block_width : Int
  block_height : Int
  size_index : Int
  avail_u : Bool
  avail_l : Bool
  mut skip : Int
  mut skip_mode : Bool
  mut is_inter : Bool
  mut y_mode : Int
  mut ref_frame : Int
  /// The second reference name of a compound block (`av1_none_frame` for a
  /// single-reference block). AV1 5.11.25 `read_ref_frames` fills both names.
  mut ref_frame1 : Int
  mut mv_row : Int
  mut mv_col : Int
  /// The second motion vector of a compound block, in its reference's units.
  mut mv_row1 : Int
  mut mv_col1 : Int
  /// Vertical and horizontal subpel filter, in the order the syntax codes them.
  mut interp_vertical : Int
  mut interp_horizontal : Int
  /// The reference-list index into the candidate stack, from `drl_mode`.
  mut ref_mv_idx : Int
  /// `read_motion_mode`: 0 = SIMPLE, 1 = OBMC, 2 = local warp. Only the symbol
  /// is decoded here; a block that selects a mode the predictor cannot act on
  /// makes the frame be refused rather than mis-reconstructed.
  mut motion_mode : Int
}

///|
/// A fresh block. An inter frame's intra blocks keep the reference at INTRA and
/// the filters at the eight-tap default, which is what their neighbours read.
fn av1_inter_block(
  mi_row : Int,
  mi_col : Int,
  width4 : Int,
  height4 : Int,
  size_index : Int,
  avail_u : Bool,
  avail_l : Bool,
) -> Av1InterBlock {
  {
    mi_row,
    mi_col,
    width4,
    height4,
    block_width: width4 * 4,
    block_height: height4 * 4,
    size_index,
    avail_u,
    avail_l,
    skip: 0,
    skip_mode: false,
    is_inter: false,
    y_mode: 0,
    ref_frame: av1_intra_frame,
    ref_frame1: av1_none_frame,
    mv_row: 0,
    mv_col: 0,
    mv_row1: 0,
    mv_col1: 0,
    interp_vertical: av1_interp_eighttap,
    interp_horizontal: av1_interp_eighttap,
    ref_mv_idx: 0,
    motion_mode: 0,
  }
}

///|
/// The reference name of the block above or to the left, or INTRA_FRAME when
/// that neighbour does not exist (AV1 §5.11.23).
fn av1_field_reference(field : Av1MotionField, row : Int, col : Int) -> Int {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    av1_intra_frame
  } else {
    field.refs[(row * field.cols + col) * 2]
  }
}

///|
/// read_is_inter( ) (AV1 §5.11.20). A segmentation feature can force the answer,
/// but the frame gate refuses segmentation.
fn av1_read_is_inter(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  if block.skip_mode {
    block.is_inter = true
    return true
  }
  let left = av1_field_reference(info.field, block.mi_row, block.mi_col - 1)
  let above = av1_field_reference(info.field, block.mi_row - 1, block.mi_col)
  let left_intra = left <= av1_intra_frame
  let above_intra = above <= av1_intra_frame
  let mut ctx = 0
  if block.avail_u && block.avail_l {
    ctx = if left_intra && above_intra {
      3
    } else if left_intra || above_intra {
      1
    } else {
      0
    }
  } else if block.avail_u {
    ctx = if above_intra { 2 } else { 0 }
  } else if block.avail_l {
    ctx = if left_intra { 2 } else { 0 }
  }
  if ctx >= info.cdfs.is_inter.length() {
    return false
  }
  block.is_inter = decoder.symbol(info.cdfs.is_inter[ctx]) == 1
  true
}

///|
/// read_skip_mode( ) (AV1 §5.11.21). A block that skips its modes entirely copies
/// the two frame-level skip-mode references.
fn av1_read_skip_mode(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  block.skip_mode = false
  if !info.skip_mode_present || block.block_width < 8 || block.block_height < 8 {
    return true
  }
  let mut ctx = 0
  if block.avail_u {
    ctx = ctx + av1_field_skip_mode(info.field, block.mi_row - 1, block.mi_col)
  }
  if block.avail_l {
    ctx = ctx + av1_field_skip_mode(info.field, block.mi_row, block.mi_col - 1)
  }
  if ctx >= info.cdfs.skip_mode.length() {
    return false
  }
  if decoder.symbol(info.cdfs.skip_mode[ctx]) == 1 {
    block.skip_mode = true
    block.skip = 1
    block.is_inter = true
    block.ref_frame = info.skip_mode_frame[0]
  }
  true
}

///|
fn av1_field_skip_mode(field : Av1MotionField, row : Int, col : Int) -> Int {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    0
  } else {
    field.skip_modes[row * field.cols + col]
  }
}

///|
/// AV1's `checkBackward`: whether a reference name sits in the backward half of
/// the reference list. The comp_mode and comp_ref_type contexts use it.
fn av1_ref_is_backward(name : Int) -> Bool {
  name >= av1_bwd_ref_frame && name <= av1_alt_ref_frame
}

///|
/// AV1's `isSamedirRefPair`: whether two names point the same way.
fn av1_samedir_ref_pair(ref0 : Int, ref1 : Int) -> Bool {
  (ref0 >= av1_bwd_ref_frame) == (ref1 >= av1_bwd_ref_frame)
}

///|
/// comp_mode context (AV1 §8.3). Reads the two neighbours' reference pairs: a
/// single-reference or intra neighbour collapses to one name, a compound one
/// keeps both, and the context counts how far each sits into the backward half.
fn av1_comp_mode_ctx(info : Av1InterInfo, block : Av1InterBlock) -> Int {
  let above = av1_neighbour_pair(info.field, block.mi_row - 1, block.mi_col)
  let left = av1_neighbour_pair(info.field, block.mi_row, block.mi_col - 1)
  let above_intra = above[0] == av1_intra_frame
  let left_intra = left[0] == av1_intra_frame
  let above_single = above[1] == av1_none_frame
  let left_single = left[1] == av1_none_frame
  if block.avail_u && block.avail_l {
    if above_single && left_single {
      (if av1_ref_is_backward(above[0]) { 1 } else { 0 }) ^
      (if av1_ref_is_backward(left[0]) { 1 } else { 0 })
    } else if above_single {
      2 + (if av1_ref_is_backward(above[0]) || above_intra { 1 } else { 0 })
    } else if left_single {
      2 + (if av1_ref_is_backward(left[0]) || left_intra { 1 } else { 0 })
    } else {
      4
    }
  } else if block.avail_u {
    if above_single {
      if av1_ref_is_backward(above[0]) { 1 } else { 0 }
    } else {
      3
    }
  } else if block.avail_l {
    if left_single {
      if av1_ref_is_backward(left[0]) { 1 } else { 0 }
    } else {
      3
    }
  } else {
    1
  }
}

///|
/// comp_ref_type context (AV1 §8.3): whether each neighbour is single- or
/// compound-reference, and for compound ones whether the pair points one way.
fn av1_comp_ref_type_ctx(info : Av1InterInfo, block : Av1InterBlock) -> Int {
  let above = av1_neighbour_pair(info.field, block.mi_row - 1, block.mi_col)
  let left = av1_neighbour_pair(info.field, block.mi_row, block.mi_col - 1)
  let a0 = above[0]
  let a1 = above[1]
  let l0 = left[0]
  let l1 = left[1]
  let above_intra = a0 == av1_intra_frame
  let left_intra = l0 == av1_intra_frame
  let above_comp = block.avail_u && !above_intra && a1 != av1_none_frame
  let left_comp = block.avail_l && !left_intra && l1 != av1_none_frame
  let above_uni = above_comp && av1_samedir_ref_pair(a0, a1)
  let left_uni = left_comp && av1_samedir_ref_pair(l0, l1)
  let samedir = if av1_samedir_ref_pair(a0, l0) { 1 } else { 0 }
  if block.avail_u && !above_intra && block.avail_l && !left_intra {
    if !above_comp && !left_comp {
      1 + 2 * samedir
    } else if !above_comp {
      if !left_uni { 1 } else { 3 + samedir }
    } else if !left_comp {
      if !above_uni { 1 } else { 3 + samedir }
    } else if !above_uni && !left_uni {
      0
    } else if !above_uni || !left_uni {
      2
    } else {
      3 +
      (if (a0 == av1_bwd_ref_frame) == (l0 == av1_bwd_ref_frame) { 1 } else { 0 })
    }
  } else if block.avail_u && block.avail_l {
    if above_comp {
      1 + 2 * (if above_uni { 1 } else { 0 })
    } else if left_comp {
      1 + 2 * (if left_uni { 1 } else { 0 })
    } else {
      2
    }
  } else if above_comp {
    4 * (if above_uni { 1 } else { 0 })
  } else if left_comp {
    4 * (if left_uni { 1 } else { 0 })
  } else {
    2
  }
}

///|
/// read_ref_frames( ) (AV1 §5.11.24): the binary tree over the seven named
/// reference frames. The tree context counts how often each name appears in the
/// two neighbours, forward against backward.
fn av1_read_ref_frames(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  if block.skip_mode {
    return true
  }
  // A compound block codes two reference names; a single one keeps the second
  // at NONE, which is what its neighbours and the predictor read.
  block.ref_frame1 = av1_none_frame
  if info.reference_select && block.width4 >= 2 && block.height4 >= 2 {
    if decoder.symbol(info.cdfs.comp_mode[av1_comp_mode_ctx(info, block)]) != 0 {
      return av1_read_compound_refs(decoder, info, block)
    }
  }
  let left = av1_neighbour_pair(info.field, block.mi_row, block.mi_col - 1)
  let above = av1_neighbour_pair(info.field, block.mi_row - 1, block.mi_col)
  let counts = fn(name) {
    let mut count = 0
    if block.avail_u {
      if above[0] == name {
        count = count + 1
      }
      if above[1] == name {
        count = count + 1
      }
    }
    if block.avail_l {
      if left[0] == name {
        count = count + 1
      }
      if left[1] == name {
        count = count + 1
      }
    }
    count
  }
  let symbol = fn(index, counts0, counts1) {
    let ctx = av1_ref_count_ctx(counts0, counts1)
    if ctx >= info.cdfs.single_ref.length() ||
      index >= info.cdfs.single_ref[ctx].length() {
      -1
    } else {
      decoder.symbol(info.cdfs.single_ref[ctx][index])
    }
  }
  let forward = counts(av1_last_frame) +
    counts(av1_last2_frame) +
    counts(av1_last3_frame) +
    counts(av1_golden_frame)
  let backward = counts(av1_bwd_ref_frame) +
    counts(av1_alt_ref2_frame) +
    counts(av1_alt_ref_frame)
  let first = symbol(0, forward, backward)
  let mut name = av1_last_frame
  if first == 1 {
    // Backward half of the tree: ALTREF, or one of the two nearer ones.
    let second = symbol(
      1,
      counts(av1_bwd_ref_frame) + counts(av1_alt_ref2_frame),
      counts(av1_alt_ref_frame),
    )
    if second == 0 {
      let third = symbol(
        5,
        counts(av1_bwd_ref_frame),
        counts(av1_alt_ref2_frame),
      )
      if third < 0 {
        return false
      }
      name = if third == 1 { av1_alt_ref2_frame } else { av1_bwd_ref_frame }
    } else if second == 1 {
      name = av1_alt_ref_frame
    } else {
      return false
    }
  } else if first == 0 {
    let second = symbol(
      2,
      counts(av1_last_frame) + counts(av1_last2_frame),
      counts(av1_last3_frame) + counts(av1_golden_frame),
    )
    if second == 1 {
      let third = symbol(4, counts(av1_last3_frame), counts(av1_golden_frame))
      if third < 0 {
        return false
      }
      name = if third == 1 { av1_golden_frame } else { av1_last3_frame }
    } else if second == 0 {
      let third = symbol(3, counts(av1_last_frame), counts(av1_last2_frame))
      if third < 0 {
        return false
      }
      name = if third == 1 { av1_last2_frame } else { av1_last_frame }
    } else {
      return false
    }
  } else {
    return false
  }
  block.ref_frame = name
  true
}

///|
/// The compound half of `read_ref_frames` (AV1 §5.11.25): `comp_ref_type`
/// selects the unidirectional or the bidirectional pair, and each shape then
/// names its two references from the same neighbour-count contexts the single
/// tree uses. `read` mirrors the single tree's `symbol` helper but borrows the
/// table, so each pair keeps its own defaults.
fn av1_read_compound_refs(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  let left = av1_neighbour_pair(info.field, block.mi_row, block.mi_col - 1)
  let above = av1_neighbour_pair(info.field, block.mi_row - 1, block.mi_col)
  let counts = fn(name) {
    let mut count = 0
    if block.avail_u {
      if above[0] == name {
        count = count + 1
      }
      if above[1] == name {
        count = count + 1
      }
    }
    if block.avail_l {
      if left[0] == name {
        count = count + 1
      }
      if left[1] == name {
        count = count + 1
      }
    }
    count
  }
  let read = fn(
    table : Array[Array[Array[Int]]],
    index : Int,
    counts0 : Int,
    counts1 : Int,
  ) -> Int {
    let ctx = av1_ref_count_ctx(counts0, counts1)
    if ctx >= table.length() || index >= table[ctx].length() {
      -1
    } else {
      decoder.symbol(table[ctx][index])
    }
  }
  if decoder.symbol(info.cdfs.comp_ref_type[av1_comp_ref_type_ctx(info, block)]) != 0 {
    // Unidirectional: both names point the same way.
    let forward = counts(av1_last_frame) +
      counts(av1_last2_frame) +
      counts(av1_last3_frame) +
      counts(av1_golden_frame)
    let backward = counts(av1_bwd_ref_frame) +
      counts(av1_alt_ref2_frame) +
      counts(av1_alt_ref_frame)
    if read(info.cdfs.uni_comp_ref, 0, forward, backward) == 1 {
      block.ref_frame = av1_bwd_ref_frame
      block.ref_frame1 = av1_alt_ref_frame
      return true
    }
    let p1 = read(
      info.cdfs.uni_comp_ref,
      1,
      counts(av1_last2_frame),
      counts(av1_last3_frame) + counts(av1_golden_frame),
    )
    if p1 < 0 {
      return false
    }
    if p1 == 0 {
      block.ref_frame = av1_last_frame
      block.ref_frame1 = av1_last2_frame
      return true
    }
    let p2 = read(
      info.cdfs.uni_comp_ref,
      2,
      counts(av1_last3_frame),
      counts(av1_golden_frame),
    )
    if p2 < 0 {
      return false
    }
    if p2 == 1 {
      block.ref_frame = av1_last_frame
      block.ref_frame1 = av1_golden_frame
    } else {
      block.ref_frame = av1_last_frame
      block.ref_frame1 = av1_last3_frame
    }
    return true
  }
  // Bidirectional: a forward name, then a backward one.
  let ctx_ref = read(
    info.cdfs.comp_ref,
    0,
    counts(av1_last_frame) + counts(av1_last2_frame),
    counts(av1_last3_frame) + counts(av1_golden_frame),
  )
  if ctx_ref < 0 {
    return false
  }
  if ctx_ref == 0 {
    let p1 = read(
      info.cdfs.comp_ref,
      1,
      counts(av1_last_frame),
      counts(av1_last2_frame),
    )
    if p1 < 0 {
      return false
    }
    block.ref_frame = if p1 == 1 { av1_last2_frame } else { av1_last_frame }
  } else {
    let p2 = read(
      info.cdfs.comp_ref,
      2,
      counts(av1_last3_frame),
      counts(av1_golden_frame),
    )
    if p2 < 0 {
      return false
    }
    block.ref_frame = if p2 == 1 { av1_golden_frame } else { av1_last3_frame }
  }
  let ctx_bwd = read(
    info.cdfs.comp_bwd_ref,
    0,
    counts(av1_bwd_ref_frame) + counts(av1_alt_ref2_frame),
    counts(av1_alt_ref_frame),
  )
  if ctx_bwd < 0 {
    return false
  }
  if ctx_bwd == 0 {
    let p1 = read(
      info.cdfs.comp_bwd_ref,
      1,
      counts(av1_bwd_ref_frame),
      counts(av1_alt_ref2_frame),
    )
    if p1 < 0 {
      return false
    }
    block.ref_frame1 = if p1 == 1 { av1_alt_ref2_frame } else { av1_bwd_ref_frame }
  } else {
    block.ref_frame1 = av1_alt_ref_frame
  }
  true
}

///|
/// The two reference names stored at one MI unit, for the reference-count
/// contexts. An unwritten or intra neighbour reports INTRA_FRAME and NONE.
fn av1_neighbour_pair(
  field : Av1MotionField,
  row : Int,
  col : Int,
) -> Array[Int] {
  let pair = [av1_intra_frame, av1_none_frame]
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    return pair
  }
  let unit = (row * field.cols + col) * 2
  pair[0] = field.refs[unit]
  pair[1] = field.refs[unit + 1]
  pair
}

///|
/// `Compound_Mode_Ctx_Map` (AV1 §8.3): the compound_mode context from the
/// reference-count and new-MV stack contexts.
let av1_compound_mode_ctx_map : Array[Array[Int]] = [
  [0, 1, 1, 1, 1],
  [1, 2, 3, 4, 4],
  [4, 4, 5, 6, 7],
]

///|
/// The mode tree of §5.11.24: whether the block codes a fresh vector, falls back
/// to the frame's global motion, or reuses one of the stacked candidates.
fn av1_read_inter_mode(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
  stack : Av1MvStack,
) -> Bool {
  if block.skip_mode {
    block.y_mode = av1_mode_nearest_mv
    return true
  }
  if block.ref_frame1 > av1_intra_frame {
    // A compound block reads one symbol: NEAREST_NEARESTMV or NEW_NEWMV.
    let row = if stack.refmv_context < 0 {
      0
    } else if stack.refmv_context > 2 {
      2
    } else {
      stack.refmv_context
    }
    let column = if stack.newmv_context < 0 {
      0
    } else if stack.newmv_context > 4 {
      4
    } else {
      stack.newmv_context
    }
    let ctx = av1_compound_mode_ctx_map[row][column]
    if ctx >= info.cdfs.compound_mode.length() {
      return false
    }
    block.y_mode = av1_mode_nearest_nearest_mv +
      decoder.symbol(info.cdfs.compound_mode[ctx])
    return true
  }
  if stack.newmv_context < 0 || stack.newmv_context >= info.cdfs.new_mv.length() {
    return false
  }
  if decoder.symbol(info.cdfs.new_mv[stack.newmv_context]) == 0 {
    block.y_mode = av1_mode_new_mv
    return true
  }
  if stack.zero_mv_context < 0 ||
    stack.zero_mv_context > 1 ||
    stack.zero_mv_context >= info.cdfs.zero_mv.length() {
    return false
  }
  if decoder.symbol(info.cdfs.zero_mv[stack.zero_mv_context]) == 0 {
    block.y_mode = av1_mode_global_mv
    return true
  }
  if stack.refmv_context < 0 || stack.refmv_context >= info.cdfs.ref_mv.length() {
    return false
  }
  block.y_mode = if decoder.symbol(info.cdfs.ref_mv[stack.refmv_context]) == 0 {
    av1_mode_nearest_mv
  } else {
    av1_mode_near_mv
  }
  true
}

///|
/// has_nearmv( ) (AV1 §5.11.24).
fn av1_has_nearmv(mode : Int) -> Bool {
  mode == av1_mode_near_mv
}

///|
/// The depth reference list index (AV1 §5.11.24): walk the stacked candidates
/// and stop at the first one the bitstream selects. The two entry points differ
/// on purpose, which is why a NEARMV block can never reach candidate zero: its
/// index starts at 1 before any symbol is read, so a thin stack still yields the
/// candidate the global motion vector was parked in.
fn av1_read_drl_idx(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
  stack : Av1MvStack,
) -> Bool {
  // A compound block's NEW_NEWMV is the new-MV tree applied to both lists.
  let new_mv = block.y_mode == av1_mode_new_mv || block.y_mode == av1_mode_new_new_mv
  let near_mv = av1_has_nearmv(block.y_mode)
  if !new_mv && !near_mv {
    // Only those two trees exist; every other mode names its candidate already.
    block.ref_mv_idx = 0
    return true
  }
  block.ref_mv_idx = if near_mv { 1 } else { 0 }
  let mut index = if new_mv { 0 } else { 1 }
  let limit = if near_mv { 3 } else { 2 }
  while index < limit {
    if stack.count <= index + 1 {
      return true
    }
    if index >= stack.drl_contexts.length() ||
      stack.drl_contexts[index] >= info.cdfs.drl_mode.length() {
      return false
    }
    if decoder.symbol(info.cdfs.drl_mode[stack.drl_contexts[index]]) == 0 {
      block.ref_mv_idx = index
      return true
    }
    block.ref_mv_idx = index + 1
    index = index + 1
  }
  true
}

///|
/// assign_mv( ) (AV1 §5.11.24): pick the predicted vector out of the stack and
/// code the difference only where the mode is new motion.
fn av1_assign_mv(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
  stack : Av1MvStack,
) -> Bool {
  if block.ref_frame1 > av1_intra_frame {
    // Compound: both lists take the same mode, so NEW_NEWMV codes a fresh
    // vector per list against that list's candidate, and NEAREST_NEARESTMV
    // copies the nearest candidate of each list.
    let fresh = block.y_mode == av1_mode_new_new_mv
    if block.ref_mv_idx < 0 || block.ref_mv_idx >= av1_ref_mv_stack_size {
      return false
    }
    let position = if !fresh || stack.count > 1 { block.ref_mv_idx } else { 0 }
    let first = av1_stack_mv(stack, position, 0)
    let second = av1_stack_mv(stack, position, 1)
    if fresh {
      let diff0 = av1_read_mv(decoder, info)
      let diff1 = av1_read_mv(decoder, info)
      block.mv_row = first.0 + diff0.0
      block.mv_col = first.1 + diff0.1
      block.mv_row1 = second.0 + diff1.0
      block.mv_col1 = second.1 + diff1.1
    } else {
      block.mv_row = first.0
      block.mv_col = first.1
      block.mv_row1 = second.0
      block.mv_col1 = second.1
    }
    return true
  }
  if block.y_mode == av1_mode_global_mv {
    block.mv_row = stack.global_rows[0]
    block.mv_col = stack.global_cols[0]
    return true
  }
  let mut position = if block.y_mode == av1_mode_nearest_mv {
    0
  } else {
    block.ref_mv_idx
  }
  if block.y_mode == av1_mode_new_mv && stack.count <= 1 {
    position = 0
  }
  if position < 0 || position >= av1_ref_mv_stack_size {
    return false
  }
  let predicted = av1_stack_mv(stack, position, 0)
  if block.y_mode == av1_mode_new_mv {
    let diff = av1_read_mv(decoder, info)
    block.mv_row = predicted.0 + diff.0
    block.mv_col = predicted.1 + diff.1
  } else {
    block.mv_row = predicted.0
    block.mv_col = predicted.1
  }
  true
}

///|
/// read_mv( ) (AV1 §5.11.25): the joint names which components follow. Only the
/// intra block copy path uses the second motion vector context, and the frame
/// gate refuses it.
fn av1_read_mv(decoder : Av1SymbolDecoder, info : Av1InterInfo) -> (Int, Int) {
  let context = 0
  let joint = decoder.symbol(info.cdfs.mv_joint[context])
  let mut diff_row = 0
  let mut diff_col = 0
  if joint == av1_mv_joint_hzvnz || joint == av1_mv_joint_hnzvnz {
    diff_row = av1_read_mv_component(decoder, info, context, 0)
  }
  if joint == av1_mv_joint_hnzvz || joint == av1_mv_joint_hnzvnz {
    diff_col = av1_read_mv_component(decoder, info, context, 1)
  }
  (diff_row, diff_col)
}

///|
/// read_mv_component( comp ) (AV1 §5.11.25). Magnitude class 0 codes a short
/// offset directly; the higher classes code `mv_class` magnitude bits on top of
/// a class-sized base. Both paths end in the fractional bits the frame is
/// allowed to signal, and the sign is applied last.
fn av1_read_mv_component(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  context : Int,
  component : Int,
) -> Int {
  let cdfs = info.cdfs
  if component < 0 || component > 1 || context < 0 || context > 1 {
    return 0
  }
  let sign = decoder.symbol(cdfs.mv_sign[context][component])
  let class_cdf = cdfs.mv_class[context][component]
  let class = decoder.symbol(class_cdf)
  // Bounded by the table, not a constant: the largest class is still a valid
  // magnitude and codes one mv_bit per position below it.
  if class < 0 || class >= class_cdf.length() - 1 {
    return 0
  }
  let mut magnitude = 0
  if class == 0 {
    let bit = decoder.symbol(cdfs.mv_class0_bit[context][component])
    if bit < 0 || bit > 1 {
      return 0
    }
    let fraction = if info.frame.force_integer_mv != 0 {
      3
    } else {
      decoder.symbol(cdfs.mv_class0_fr[context][component][bit])
    }
    let high = if info.frame.allow_high_precision_mv {
      decoder.symbol(cdfs.mv_class0_hp[context][component])
    } else {
      1
    }
    magnitude = ((bit << 3) | (fraction << 1) | high) + 1
  } else {
    let bits_cdf = cdfs.mv_bit[context][component]
    let mut bits = 0
    for index in 0..<class {
      bits = bits | (decoder.symbol(bits_cdf[index]) << index)
    }
    let fraction = if info.frame.force_integer_mv != 0 {
      3
    } else {
      decoder.symbol(cdfs.mv_fr[context][component])
    }
    let high = if info.frame.allow_high_precision_mv {
      decoder.symbol(cdfs.mv_hp[context][component])
    } else {
      1
    }
    magnitude = (av1_class0_size << (class + 2)) +
      ((bits << 3) | (fraction << 1) | high) +
      1
  }
  if sign == 1 {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// has_overlappable_candidates( ) (AV1 §7.10.3, `av1spec08.md:1819`): an inter
/// neighbour above or to the left at an even MI position inside this block's
/// extent. Only inter neighbours count, so the very first block of a frame has
/// none and keeps the simple prediction path.
fn av1_has_overlappable_candidates(
  field : Av1MotionField,
  block : Av1InterBlock,
) -> Bool {
  if block.avail_u {
    let w4 = block.width4
    let mut x4 = block.mi_col
    while x4 < block.mi_col + w4 && x4 < field.cols {
      let pair = av1_neighbour_pair(field, block.mi_row - 1, x4)
      if pair[0] > av1_intra_frame {
        return true
      }
      x4 = x4 + 2
    }
  }
  if block.avail_l {
    let h4 = block.height4
    let mut y4 = block.mi_row
    while y4 < block.mi_row + h4 && y4 < field.rows {
      let pair = av1_neighbour_pair(field, y4, block.mi_col - 1)
      if pair[0] > av1_intra_frame {
        return true
      }
      y4 = y4 + 2
    }
  }
  false
}

///|
/// read_motion_mode( isCompound ) (AV1 §5.11.27). Returns false when the block
/// selects a mode this decoder cannot reconstruct, so the frame is refused whole
/// instead of being decoded as a prefix of itself. LOCALWARP needs a warp model
/// this configuration never reaches, so only the OBMC branch matters here.
fn av1_read_motion_mode(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  block.motion_mode = 0
  if block.skip_mode || !info.frame.is_motion_mode_switchable {
    return true
  }
  let smaller = if block.block_width < block.block_height {
    block.block_width
  } else {
    block.block_height
  }
  if smaller < 8 {
    return true
  }
  if info.frame.force_integer_mv == 0 &&
    (
      block.y_mode == av1_mode_global_mv ||
      block.y_mode == av1_mode_global_global_mv
    ) {
    if av1_gm_type(info, block.ref_frame) > av1_gm_translation {
      return true
    }
  }
  // A single-reference block names NONE as its second reference, so the
  // compound and intra-second-reference early exits do not apply to it.
  if !av1_has_overlappable_candidates(info.field, block) {
    return true
  }
  let size_index = block.size_index
  if size_index < 0 || size_index >= info.cdfs.use_obmc.length() {
    return false
  }
  // `find_warp_samples` reads no symbols; its count decides which of the two
  // symbol shapes this block codes (AV1 §5.11.27).
  let num_samples = av1_warp_samples(
    info.field,
    block.mi_row,
    block.mi_col,
    block.width4,
    block.height4,
    block.avail_u,
    block.avail_l,
    block.mv_row,
    block.mv_col,
    block.ref_frame,
  )
  if info.frame.force_integer_mv == 0 &&
    num_samples != 0 &&
    info.frame.allow_warped_motion &&
    !av1_mv_is_scaled(info, block.ref_frame) {
    // The three-symbol `motion_mode`: 0 = SIMPLE, 1 = OBMC, 2 = LOCALWARP.
    if size_index >= info.cdfs.motion_mode.length() {
      return false
    }
    let mode = decoder.symbol(info.cdfs.motion_mode[size_index])
    if mode < 0 || mode > 2 {
      return false
    }
    if mode == 2 {
      // LOCALWARP needs the warp estimation and the warped prediction grid of
      // §7.11.3.5/§7.11.3.8, neither of which is implemented, so the frame is
      // refused rather than decoded as a prefix of itself.
      return false
    }
    block.motion_mode = mode
    return true
  }
  if decoder.symbol(info.cdfs.use_obmc[size_index]) == 1 {
    block.motion_mode = 1
  }
  true
}

///|
/// `is_scaled( refFrame )` (AV1 §5.11.26): true when a stored reference's
/// visible extent differs from the current frame's. Reference scaling itself is
/// outside this decoder's scope, so this is the only per-frame test needed.
fn av1_mv_is_scaled(info : Av1InterInfo, name : Int) -> Bool {
  match av1_inter_reference(info, name) {
    Some(frame) =>
      frame.width != info.frame.frame_width ||
      frame.height != info.frame.frame_height
    None => false
  }
}

///|
/// The interpolation filter of §5.11.27, and the §8.3 context that selects its
/// row. A frame with a fixed filter sets both directions without a symbol.
fn av1_read_interp_filter(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Unit {
  if info.interpolation_filter != av1_interp_switchable {
    block.interp_vertical = info.interpolation_filter
    block.interp_horizontal = info.interpolation_filter
    return
  }
  let mut vertical = av1_interp_eighttap
  if av1_needs_interp_filter(info, block) {
    let ctx = av1_interp_filter_ctx(info, block, 0)
    if ctx < info.cdfs.interp_filter.length() {
      vertical = decoder.symbol(info.cdfs.interp_filter[ctx])
    }
  }
  block.interp_vertical = vertical
  block.interp_horizontal = if info.enable_dual_filter &&
    av1_needs_interp_filter(info, block) {
    let ctx = av1_interp_filter_ctx(info, block, 1)
    if ctx < info.cdfs.interp_filter.length() {
      decoder.symbol(info.cdfs.interp_filter[ctx])
    } else {
      vertical
    }
  } else {
    vertical
  }
}

///|
/// needs_interp_filter( ) (AV1 §5.11.27): a large block driven by a non-identity
/// warp model has no subpel phase of its own to filter at.
fn av1_needs_interp_filter(info : Av1InterInfo, block : Av1InterBlock) -> Bool {
  let smaller = if block.block_width < block.block_height {
    block.block_width
  } else {
    block.block_height
  }
  if smaller < 8 || block.skip_mode {
    return true
  }
  if block.y_mode != av1_mode_global_mv {
    return true
  }
  av1_gm_type(info, block.ref_frame) == av1_gm_translation
}

///|
fn av1_gm_type(info : Av1InterInfo, name : Int) -> Int {
  if name < 0 || name >= info.frame.gm_type.length() {
    av1_gm_identity
  } else {
    info.frame.gm_type[name]
  }
}

///|
/// interp_filter_ctx( dir ) (AV1 §8.3): only a neighbour that coded from the same
/// reference contributes its own filter choice.
fn av1_interp_filter_ctx(
  info : Av1InterInfo,
  block : Av1InterBlock,
  direction : Int,
) -> Int {
  // AV1 §8.3: the direction and the compound flag select the row group, the
  // neighbours' filters the offset inside it.
  let compound = if block.ref_frame1 > av1_intra_frame { 1 } else { 0 }
  let ctx = ((direction & 1) * 2 + compound) * 4
  let mut left = 3
  let mut above = 3
  if block.avail_l &&
    av1_unit_uses_reference(
      info.field,
      block.mi_row,
      block.mi_col - 1,
      block.ref_frame,
    ) {
    left = av1_field_interp(
      info.field,
      block.mi_row,
      block.mi_col - 1,
      direction,
    )
  }
  if block.avail_u &&
    av1_unit_uses_reference(
      info.field,
      block.mi_row - 1,
      block.mi_col,
      block.ref_frame,
    ) {
    above = av1_field_interp(
      info.field,
      block.mi_row - 1,
      block.mi_col,
      direction,
    )
  }
  let shared = if left == above {
    left
  } else if left == 3 {
    above
  } else if above == 3 {
    left
  } else {
    3
  }
  ctx + shared
}

///|
fn av1_unit_uses_reference(
  field : Av1MotionField,
  row : Int,
  col : Int,
  name : Int,
) -> Bool {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    return false
  }
  let unit = (row * field.cols + col) * 2
  field.refs[unit] == name || field.refs[unit + 1] == name
}

///|
fn av1_field_interp(
  field : Av1MotionField,
  row : Int,
  col : Int,
  direction : Int,
) -> Int {
  if row < 0 || col < 0 || row >= field.rows || col >= field.cols {
    return 3
  }
  let unit = row * field.cols + col
  if direction == 0 {
    field.interp_v[unit]
  } else {
    field.interp_h[unit]
  }
}

///|
/// inter_block_mode_info( ) for a block whose reference frames are already known
/// (AV1 §5.11.24): derive the candidate stack, read the mode and the vector, then
/// the filters.
fn av1_inter_block_motion(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  if !av1_read_ref_frames(decoder, info, block) {
    return false
  }
  let stack = match
    av1_find_mv_stack(
      info.field,
      {
        mi_row: block.mi_row,
        mi_col: block.mi_col,
        width4: block.width4,
        height4: block.height4,
        block_width: block.block_width,
        block_height: block.block_height,
        refs: [block.ref_frame, block.ref_frame1],
        tile_row_start: info.tile_row_start,
        tile_row_end: info.tile_row_end,
        tile_col_start: info.tile_col_start,
        tile_col_end: info.tile_col_end,
      },
      info.frame,
      block.ref_frame1 > av1_intra_frame,
    ) {
    Some(value) => value
    None => return false
  }
  if !av1_read_inter_mode(decoder, info, block, stack) {
    return false
  }
  if !av1_read_drl_idx(decoder, info, block, stack) {
    return false
  }
  if !av1_assign_mv(decoder, info, block, stack) {
    return false
  }
  if !av1_read_motion_mode(decoder, info, block) {
    return false
  }
  if !av1_read_compound_type(decoder, info, block) {
    return false
  }
  av1_read_interp_filter(decoder, info, block)
  true
}

///|
/// read_compound_type( isCompound ) (AV1 §5.11.25): which blend a compound
/// block uses. With both masked-compound switches off - what the frame gate
/// already insists on - the answer is COMPOUND_AVERAGE and no symbol is read.
/// A stream that asks for a wedge or a distance weighting is refused rather
/// than averaged, because those blends are not implemented.
fn av1_read_compound_type(
  decoder : Av1SymbolDecoder,
  info : Av1InterInfo,
  block : Av1InterBlock,
) -> Bool {
  if block.ref_frame1 <= av1_intra_frame {
    return true
  }
  if info.enable_masked_compound || info.enable_jnt_comp {
    return false
  }
  true
}

///|
/// The frame-level half of the inter state, shared by every tile of one frame.
/// The motion field spans the whole coded frame, because a block's candidates
/// are read from whatever was decoded before it in raster order.
pub(all) struct Av1InterFrame {
  field : Av1MotionField
  frame : Av1MvFrame
  /// Stored reference frames indexed by reference name, so a block's
  /// `RefFrame` selects its buffer directly.
  refs : Array[Av1RefFrame?]
  interpolation_filter : Int
  enable_dual_filter : Bool
  skip_mode_present : Bool
  skip_mode_frame : Array[Int]
  reference_select : Bool
  enable_masked_compound : Bool
  enable_jnt_comp : Bool
  mi_cols : Int
  mi_rows : Int
}

///|
/// Bind the frame's named references to its decoded buffers and size the motion
/// field (AV1 §7.8). A name whose slot was never refreshed has no buffer, and
/// the block stage refuses to predict from it.
pub fn av1_inter_frame_of(
  header : Av1FrameHeaderInfo,
  sequence : Av1SequenceInfo,
  map : Av1FrameMap,
) -> Av1InterFrame? {
  let coded_width = av1_partition_coded_extent(header.frame_width)
  let coded_height = av1_partition_coded_extent(header.frame_height)
  let mi_cols = coded_width / 4
  let mi_rows = coded_height / 4
  if mi_cols <= 0 || mi_rows <= 0 {
    return None
  }
  if header.ref_frame_idx.length() != av1_refs_per_frame {
    return None
  }
  let refs : Array[Av1RefFrame?] = Array::make(av1_num_ref_frames, None)
  for name in av1_last_frame..<=av1_alt_ref_frame {
    let slot = header.ref_frame_idx[name - av1_last_frame]
    if slot < 0 || slot >= av1_num_ref_frames {
      return None
    }
    refs[name] = map.slots[slot]
  }
  // `motion_field_estimation` runs while reading the uncompressed header, before
  // any tile is decoded, so the grid is built from the reference buffers as they
  // stand before this frame is stored.
  let temporal = if header.use_ref_frame_mvs {
    Some(
      av1_motion_field_estimation(
        sequence,
        header.order_hint,
        header.order_hints,
        refs,
        mi_cols,
        mi_rows,
      ),
    )
  } else {
    None
  }
  Some({
    field: av1_motion_field(mi_cols, mi_rows),
    frame: av1_mv_frame_of(header, temporal~),
    refs,
    interpolation_filter: header.interpolation_filter,
    enable_dual_filter: sequence.enable_dual_filter,
    skip_mode_present: header.skip_mode_present,
    skip_mode_frame: header.skip_mode_frame,
    reference_select: header.reference_select,
    enable_masked_compound: sequence.enable_masked_compound,
    enable_jnt_comp: sequence.enable_jnt_comp,
    mi_cols,
    mi_rows,
  })
}

///|
/// The per-tile view of a frame's inter state. Each tile restarts probability
/// adaptation from the frame context, so it gets its own rows: the inherited
/// snapshot when the frame names a primary reference, the normative defaults
/// otherwise.
fn av1_inter_info(
  config : Av1InterFrame,
  tile_row_start : Int,
  tile_col_start : Int,
  tile_row_end : Int,
  tile_col_end : Int,
  cdfs? : Av1FrameCdfs? = None,
) -> Av1InterInfo {
  {
    cdfs: av1_inter_cdfs_of(cdfs),
    field: config.field,
    frame: config.frame,
    refs: config.refs,
    interpolation_filter: config.interpolation_filter,
    enable_dual_filter: config.enable_dual_filter,
    skip_mode_present: config.skip_mode_present,
    skip_mode_frame: config.skip_mode_frame,
    reference_select: config.reference_select,
    enable_masked_compound: config.enable_masked_compound,
    enable_jnt_comp: config.enable_jnt_comp,
    mi_cols: config.mi_cols,
    mi_rows: config.mi_rows,
    tile_row_start,
    tile_col_start,
    tile_row_end,
    tile_col_end,
  }
}
