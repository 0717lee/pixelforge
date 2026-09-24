/// The temporal motion-vector projection arithmetic (AV1 §7.9.3).
///
/// Every input is now sourced: the reciprocal table comes from the
/// specification (`av1spec08.md:872-877`, identical to go-av1's `divMult`), the
/// distance bound from go-av1's `decode/motionfield.go` and
/// `decode/compound.go:248`, and `Round2Signed` is the sign-symmetric rounding
/// this repository already uses and independently verifies for the subpel
/// kernel (`av1_mc_round2_signed`). See HANDOFF.md addenda 25 and 30 for how
/// each was obtained and why none of them is guessed.

///|
/// `MAX_FRAME_DISTANCE`. Bounds both the numerator and the denominator of a
/// projection, and indexes `av1_mv_div_mult`, which has 32 entries — so the
/// bound must be at most 31, and go-av1's value is exactly that.
pub let av1_mv_max_frame_distance : Int = 31

///|
/// `MAX_OFFSET_WIDTH` / `MAX_OFFSET_HEIGHT`, the half-width of the window
/// `get_block_position` accepts around a projected 8x8 location.
pub let av1_mv_max_offset_width : Int = 8

///|
pub let av1_mv_max_offset_height : Int = 0

///|
/// `MFMV_STACK_SIZE - 2`: how many reference frames beyond LAST the projection
/// is allowed to consume.
pub let av1_mv_stack_stamp : Int = 3 - 2

///|
/// The motion-field magnitude limit: a saved vector larger than this in either
/// axis is not recorded as a temporal candidate.
pub let av1_mv_refmvs_limit : Int = (1 << 12) - 1

///|
/// The invalid motion vector that fills an un-projected `MotionFieldMvs` cell.
pub let av1_mv_invalid : Int = -(1 << 15)

///|
/// `get_mv_projection( mv, numerator, denominator )` for one component: scale a
/// saved motion vector from the frame distance it was measured over to another.
///
/// A zero denominator maps to `Div_Mult[0]`, which is zero, so a division by
/// zero projects to a zero vector rather than failing.
pub fn av1_mv_projection_component(
  component : Int,
  numerator : Int,
  denominator : Int,
) -> Int {
  let clipped_denominator = if denominator < av1_mv_max_frame_distance {
    denominator
  } else {
    av1_mv_max_frame_distance
  }
  let low = -av1_mv_max_frame_distance
  let clipped_numerator = if numerator < low {
    low
  } else if numerator > av1_mv_max_frame_distance {
    av1_mv_max_frame_distance
  } else {
    numerator
  }
  let scaled = av1_mc_round2_signed(
    component * clipped_numerator * av1_mv_div_mult[clipped_denominator],
    14,
  )
  let bound = (1 << 14) - 1
  if scaled < -bound {
    -bound
  } else if scaled > bound {
    bound
  } else {
    scaled
  }
}

///|
/// `get_mv_projection` for both components at once.
pub fn av1_mv_projection(
  mv_row : Int,
  mv_col : Int,
  numerator : Int,
  denominator : Int,
) -> (Int, Int) {
  (
    av1_mv_projection_component(mv_row, numerator, denominator),
    av1_mv_projection_component(mv_col, numerator, denominator),
  )
}

///|
/// `get_block_position` (AV1 §7.9.4) for one axis: project an 8x8 grid
/// coordinate by a motion vector and report whether the result stays inside the
/// window the specification allows around the un-projected position.
///
/// `grid` is the coordinate in 8x8 units, `delta` the projected motion vector's
/// component in 1/8-pel, `dst_sign` the direction multiplier, `limit8` the
/// frame's extent in 8x8 units, and `max_offset8` how far from the original
/// eight-unit neighbourhood a projection may land.
fn av1_mv_block_position_axis(
  grid : Int,
  delta : Int,
  dst_sign : Int,
  limit8 : Int,
  max_offset8 : Int,
) -> (Int, Bool) {
  let base8 = grid >> 3 << 3
  let shifted = if delta >= 0 { delta >> 6 } else { -(-delta >> 6) }
  let moved = grid + dst_sign * shifted
  let valid = moved >= 0 &&
    moved < limit8 &&
    moved >= base8 - max_offset8 &&
    moved < base8 + 8 + max_offset8
  (moved, valid)
}

///|
/// `get_block_position` for both axes. The width limit uses
/// `av1_mv_max_offset_width` and the height limit `av1_mv_max_offset_height`,
/// which are deliberately asymmetric in the specification.
pub fn av1_mv_block_position(
  x8 : Int,
  y8 : Int,
  proj_mv_row : Int,
  proj_mv_col : Int,
  dst_sign : Int,
  mi_cols : Int,
  mi_rows : Int,
) -> (Int, Int, Bool) {
  let (pos_y8, ok_y) = av1_mv_block_position_axis(
    y8,
    proj_mv_row,
    dst_sign,
    mi_rows >> 1,
    av1_mv_max_offset_height,
  )
  let (pos_x8, ok_x) = av1_mv_block_position_axis(
    x8,
    proj_mv_col,
    dst_sign,
    mi_cols >> 1,
    av1_mv_max_offset_width,
  )
  (pos_x8, pos_y8, ok_y && ok_x)
}
