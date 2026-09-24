/// Motion field estimation (AV1 §7.9.1) and its projection process (§7.9.2):
/// when a frame sets `use_ref_frame_mvs`, the motion vectors saved on the
/// reference frames are projected forward or backward onto an 8x8 luma grid, one
/// grid per reference name, so that later blocks can ask for a temporal
/// candidate at their own grid cell.
///
/// The arithmetic is `av1_mv_projection`; this module is the driver that decides
/// which reference frames are projected, in which direction, and in what order.

///|
/// The estimated grid: one pair of motion vectors per 8x8 luma cell per
/// reference name, with `av1_mv_invalid` marking a cell no projection reached.
pub(all) struct Av1MotionFieldGrid {
  refs : Array[Int]
  /// `mv_rows[name][y * w8 + x]`, row-major over the 8x8 grid.
  mv_rows : Array[Array[Int]]
  mv_cols : Array[Array[Int]]
  w8 : Int
  h8 : Int
}

///|
/// `project_mvs` (§7.9.2) for one source reference name. Returns whether the
/// source was a usable projection source; a `false` result leaves the grid
/// untouched, exactly as the specification requires.
///
/// `order_hint` is the current frame's hint and `order_hints` the per-name hints
/// of the current frame, `ref_frame_idx` maps a name onto its slot, and `refs`
/// is indexed by reference name.
fn av1_project_mvs(
  grid : Av1MotionFieldGrid,
  sequence : Av1SequenceInfo,
  src : Int,
  dst_sign : Int,
  order_hint : Int,
  order_hints : Array[Int],
  refs : Array[Av1RefFrame?],
  mi_cols : Int,
  mi_rows : Int,
) -> Bool {
  let source = match av1_inter_reference_by_name(refs, src) {
    Some(value) => value
    None => return false
  }
  // A key or intra-only frame has no motion field to project, and a differently
  // sized one cannot be addressed on this frame's grid.
  if source.mi_rows != mi_rows ||
    source.mi_cols != mi_cols ||
    source.frame_type == av1_intra_only_frame ||
    source.frame_type == av1_key_frame {
    return false
  }
  let ref_to_cur = av1_relative_dist(sequence, order_hints[src], order_hint)
  if ref_to_cur > av1_mv_max_frame_distance ||
    ref_to_cur < -av1_mv_max_frame_distance {
    return false
  }
  for y8 in 0..<grid.h8 {
    for x8 in 0..<grid.w8 {
      // The saved field is at MI granularity; only odd positions are consulted.
      let row = 2 * y8 + 1
      let col = 2 * x8 + 1
      let unit = row * source.mi_cols + col
      let src_ref = source.mf_refs[unit]
      if src_ref <= av1_intra_frame {
        continue
      }
      let ref_offset = av1_relative_dist(
        sequence,
        order_hints[src],
        source.saved_order_hints[src_ref],
      )
      if ref_offset <= 0 ||
        ref_offset > av1_mv_max_frame_distance ||
        ref_offset < -av1_mv_max_frame_distance {
        continue
      }
      let mv_row = source.mf_mvs[unit * 2]
      let mv_col = source.mf_mvs[unit * 2 + 1]
      let projected = av1_mv_projection(
        mv_row,
        mv_col,
        ref_to_cur * dst_sign,
        ref_offset,
      )
      let (pos_x8, pos_y8, ok) = av1_mv_block_position(
        x8,
        y8,
        projected.0,
        projected.1,
        dst_sign,
        mi_cols,
        mi_rows,
      )
      if !ok {
        continue
      }
      // Each destination reference name sees its own projection of the same
      // saved vector, because the distances differ.
      for dst in grid.refs {
        let ref_to_dst = av1_relative_dist(
          sequence,
          order_hint,
          order_hints[dst],
        )
        let moved = av1_mv_projection(mv_row, mv_col, ref_to_dst, ref_offset)
        let slot = dst - av1_last_frame
        if slot < 0 || slot >= grid.mv_rows.length() {
          continue
        }
        grid.mv_rows[slot][pos_y8 * grid.w8 + pos_x8] = moved.0
        grid.mv_cols[slot][pos_y8 * grid.w8 + pos_x8] = moved.1
      }
    }
  }
  true
}

///|
/// The reference frame stored under a name, or `None` when the buffer never
/// filled it.
fn av1_inter_reference_by_name(
  refs : Array[Av1RefFrame?],
  name : Int,
) -> Av1RefFrame? {
  if name < av1_last_frame || name >= refs.length() {
    None
  } else {
    refs[name]
  }
}

///|
/// `motion_field_estimation` (§7.9.1). Builds the per-reference 8x8 grids for a
/// frame that sets `use_ref_frame_mvs`.
pub fn av1_motion_field_estimation(
  sequence : Av1SequenceInfo,
  order_hint : Int,
  order_hints : Array[Int],
  refs : Array[Av1RefFrame?],
  mi_cols : Int,
  mi_rows : Int,
) -> Av1MotionFieldGrid {
  let w8 = mi_cols >> 1
  let h8 = mi_rows >> 1
  let names : Array[Int] = []
  for name in av1_last_frame..<=av1_alt_ref_frame {
    names.push(name)
  }
  let grid : Av1MotionFieldGrid = {
    refs: names,
    mv_rows: Array::makei(names.length(), fn(_) {
      Array::make(w8 * h8, av1_mv_invalid)
    }),
    mv_cols: Array::makei(names.length(), fn(_) {
      Array::make(w8 * h8, av1_mv_invalid)
    }),
    w8,
    h8,
  }
  // An ALTREF-of-LAST that is this frame's GOLDEN identifies the overlay
  // case: AV1 §7.9.1 excludes LAST's motion field from temporal projection.
  // Only the boolean return of project_mvs is discarded; its grid writes are
  // the operation's result and must not occur when useLast is false.
  match av1_inter_reference_by_name(refs, av1_last_frame) {
    Some(last) =>
      if last.saved_order_hints.length() > av1_alt_ref_frame &&
        last.saved_order_hints[av1_alt_ref_frame] !=
        order_hints[av1_golden_frame] {
        let _ = av1_project_mvs(
          grid, sequence, av1_last_frame, -1, order_hint, order_hints, refs, mi_cols,
          mi_rows,
        )
      }
    None => ()
  }
  let mut stamp = av1_mv_stack_stamp
  if av1_relative_dist(sequence, order_hints[av1_bwd_ref_frame], order_hint) > 0 {
    if av1_project_mvs(
        grid, sequence, av1_bwd_ref_frame, 1, order_hint, order_hints, refs, mi_cols,
        mi_rows,
      ) {
      stamp = stamp - 1
    }
  }
  if av1_relative_dist(sequence, order_hints[av1_alt_ref2_frame], order_hint) >
    0 {
    if av1_project_mvs(
        grid, sequence, av1_alt_ref2_frame, 1, order_hint, order_hints, refs, mi_cols,
        mi_rows,
      ) {
      stamp = stamp - 1
    }
  }
  if av1_relative_dist(sequence, order_hints[av1_alt_ref_frame], order_hint) > 0 &&
    stamp >= 0 {
    if av1_project_mvs(
        grid, sequence, av1_alt_ref_frame, 1, order_hint, order_hints, refs, mi_cols,
        mi_rows,
      ) {
      stamp = stamp - 1
    }
  }
  if stamp >= 0 {
    let _ = av1_project_mvs(
      grid, sequence, av1_last2_frame, -1, order_hint, order_hints, refs, mi_cols,
      mi_rows,
    )
  }
  grid
}
