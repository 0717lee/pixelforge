/// `find_warp_samples` (AV1 §7.10.4.1) and its `add_sample` helper
/// (§7.10.4.2), transcribed from `av1spec08.md:1836-1989`.
///
/// The process reads **no entropy-coded symbols**: it only inspects the motion
/// field of already-decoded neighbour blocks. Its output `NumSamples` is what
/// decides, inside `read_motion_mode`, whether a block codes the binary
/// `use_obmc` symbol or the three-symbol `motion_mode` symbol, so a wrong
/// `NumSamples` desynchronises the symbol stream rather than merely picking a
/// worse predictor.
///
/// What is *not* implemented here, and why:
///
/// * The warp **estimation** and warped **prediction** (§7.11.3.5, §7.11.3.8)
///   are absent, so a block that selects LOCALWARP is refused by the caller.
/// * `LEAST_SQUARES_SAMPLES_MAX`, the bound that makes `add_sample` stop
///   scanning, is not stated anywhere in the local specification references.
///   It is a parameter so the scan structure can be tested independently of it;
///   see `av1_warp_samples_scan_limit` for the derived regime in which the
///   bound is inert.

///|
/// The largest block the 64x64-superblock profile can code is 64x64, i.e. 16
/// units of 4x4 per axis. `find_warp_samples` scans at most `w4 / miStep`
/// positions above and `h4 / miStep` to the left, and `miStep` is
/// `Min(w4, srcW)` with the smallest codable block being 8x8 = 2 units, so each
/// axis contributes at most 8. The top-left and top-right corners add two more.
/// A limit of 18 therefore never truncates that profile's scan, which makes the
/// result independent of the unknown `LEAST_SQUARES_SAMPLES_MAX` there.
pub let av1_warp_samples_scan_limit : Int = 18

///|
/// `find_warp_samples`: the number of valid warp candidates around one block.
///
/// `block_row`/`block_col` are the block's MI position, `block_w4`/`block_h4`
/// its 4x4 extent, `avail_u`/`avail_l` the tile availability flags,
/// `mv_row`/`mv_col` the block's own motion vector, and `ref_frame` the
/// reference name every candidate must share.
fn av1_warp_samples(
  field : Av1MotionField,
  block_row : Int,
  block_col : Int,
  block_w4 : Int,
  block_h4 : Int,
  avail_u : Bool,
  avail_l : Bool,
  mv_row : Int,
  mv_col : Int,
  ref_frame : Int,
) -> Int {
  let mut num_samples = 0
  let mut num_scanned = 0
  let mut do_top_left = true
  let mut do_top_right = true
  // `add_sample` (AV1 §7.10.4.2).
  let add = fn(delta_row : Int, delta_col : Int) -> Unit {
    if num_scanned >= av1_warp_samples_scan_limit {
      return
    }
    let mv_row_at = block_row + delta_row
    let mv_col_at = block_col + delta_col
    if mv_row_at < 0 ||
      mv_col_at < 0 ||
      mv_row_at >= field.rows ||
      mv_col_at >= field.cols {
      return
    }
    let unit = av1_field_unit(field, mv_row_at, mv_col_at) * 2
    if !field.written[unit / 2] ||
      field.refs[unit] != ref_frame ||
      field.refs[unit + 1] != av1_none_frame {
      return
    }
    let cand_w4 = field.width4[unit / 2]
    let cand_h4 = field.height4[unit / 2]
    let cand_row = mv_row_at - mv_row_at % cand_h4
    let cand_col = mv_col_at - mv_col_at % cand_w4
    let cand_unit = av1_field_unit(field, cand_row, cand_col) * 2
    // The candidate's `cand[0..3]` source/destination positions the warp fit
    // consumes are derived from the block centre below; they are not needed to
    // decide validity, so only the threshold comparison is computed.
    let threshold = if 16 > 112 {
      16
    } else if 112 < block_w4 * 4 && 112 < block_h4 * 4 {
      112
    } else if block_w4 * 4 < block_h4 * 4 {
      block_w4 * 4
    } else {
      block_h4 * 4
    }
    let diff_row = if field.mv_rows[cand_unit] - mv_row >= 0 {
      field.mv_rows[cand_unit] - mv_row
    } else {
      mv_row - field.mv_rows[cand_unit]
    }
    let diff_col = if field.mv_cols[cand_unit] - mv_col >= 0 {
      field.mv_cols[cand_unit] - mv_col
    } else {
      mv_col - field.mv_cols[cand_unit]
    }
    let valid = diff_row + diff_col <= threshold
    num_scanned = num_scanned + 1
    if !valid && num_scanned > 1 {
      return
    }
    if valid {
      num_samples = num_samples + 1
    }
  }
  if avail_u {
    let src_unit = av1_field_unit(field, block_row - 1, block_col)
    let src_w4 = field.width4[src_unit]
    if block_w4 <= src_w4 {
      let col_offset = -(block_col & (src_w4 - 1))
      if col_offset < 0 {
        do_top_left = false
      }
      if col_offset + src_w4 > block_w4 {
        do_top_right = false
      }
      add(-1, 0)
    } else {
      let mut i = 0
      while i < block_w4 && i < field.cols - block_col {
        let step = if block_w4 < src_w4 { block_w4 } else { src_w4 }
        add(-1, i)
        i = i + (if step < 1 { 1 } else { step })
      }
    }
  }
  if avail_l {
    let src_unit = av1_field_unit(field, block_row, block_col - 1)
    let src_h4 = field.height4[src_unit]
    if block_h4 <= src_h4 {
      let row_offset = -(block_row & (src_h4 - 1))
      if row_offset < 0 {
        do_top_left = false
      }
      add(0, -1)
    } else {
      let mut i = 0
      while i < block_h4 && i < field.rows - block_row {
        let step = if block_h4 < src_h4 { block_h4 } else { src_h4 }
        add(i, -1)
        i = i + (if step < 1 { 1 } else { step })
      }
    }
  }
  if do_top_left {
    add(-1, -1)
  }
  if do_top_right &&
    (if block_w4 > block_h4 { block_w4 } else { block_h4 }) <= 16 {
    add(-1, block_w4)
  }
  if num_samples == 0 && num_scanned > 0 {
    num_samples = 1
  }
  num_samples
}
