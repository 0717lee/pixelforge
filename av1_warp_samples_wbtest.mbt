/// `find_warp_samples` reads no entropy-coded symbols, so it can be pinned
/// against the specification with a synthetic motion field. The three things
/// the white-box cases below exercise are the ones a transcription slip would
/// break: the above-row scan stepping by the neighbour's width, the
/// top-left/top-right corner suppression flags, and the "no small candidate but
/// something was scanned" fallback that sets `NumSamples` to 1.

///|
/// A motion field with one inter block stored over the given 4x4 extent.
fn ws_test_field(
  cols : Int,
  rows : Int,
  row : Int,
  col : Int,
  width4 : Int,
  height4 : Int,
  mv_row : Int,
  mv_col : Int,
) -> Av1MotionField {
  let field = av1_motion_field(cols, rows)
  av1_motion_field_store(
    field,
    row,
    col,
    width4,
    height4,
    0,
    [av1_last_frame, av1_none_frame],
    [mv_row, 0],
    [mv_col, 0],
    skip=0,
    skip_mode=0,
    interp=[av1_interp_eighttap, av1_interp_eighttap],
  )
  field
}

///|
/// The scan limit is derived, not measured: a 64x64-superblock profile caps a
/// block at 64x64 = 16 units per axis, and the above/left scans step by at
/// least the smallest block's 2 units, so 8 + 8 + 2 corners is the ceiling.
test "warp sample scan limit covers the largest scannable block" {
  let largest_w4 = 64 / 4
  let largest_h4 = 64 / 4
  let smallest_step = 8 / 4
  let ceiling = largest_w4 / smallest_step + largest_h4 / smallest_step + 2
  assert_true(av1_warp_samples_scan_limit >= ceiling)
}

///|
test "warp samples: an intra neighbour above contributes nothing" {
  // The block under test sits at MI row 4, so its above neighbour is the unit at
  // row 3. A 4x4 block stored at row 0 covers rows 0..3, so storing an intra
  // block there is what makes that neighbour intra. `add_sample` then returns
  // before scanning, and with nothing scanned the fallback does not fire.
  let field = av1_motion_field(16, 16)
  av1_motion_field_store(
    field,
    0,
    4,
    4,
    4,
    0,
    [av1_intra_frame, av1_none_frame],
    [0, 0],
    [0, 0],
    skip=0,
    skip_mode=0,
    interp=[av1_interp_eighttap, av1_interp_eighttap],
  )
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, false, 8, 8, av1_last_frame),
    0,
  )
}

///|
test "warp samples: a matching neighbour above is one candidate" {
  // A 16x16 inter block above with the same reference and a motion vector
  // within the threshold yields exactly one candidate.
  let field = ws_test_field(16, 16, 0, 4, 4, 4, 16, 24)
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, false, 16, 24, av1_last_frame),
    1,
  )
}

///|
test "warp samples: a neighbour with a different reference is skipped" {
  // Same geometry, but the neighbour names a different reference frame, so
  // `add_sample` returns before touching the candidate list.
  let field = ws_test_field(16, 16, 0, 4, 4, 4, 16, 24)
  av1_motion_field_store(
    field,
    0,
    4,
    4,
    4,
    0,
    [av1_golden_frame, av1_none_frame],
    [16, 0],
    [24, 0],
    skip=0,
    skip_mode=0,
    interp=[av1_interp_eighttap, av1_interp_eighttap],
  )
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, false, 16, 24, av1_last_frame),
    0,
  )
}

///|
test "warp samples: a large motion difference still scans" {
  // The neighbour shares the reference but its motion vector is far away, so
  // the candidate is invalid. It is still the first thing scanned, and the
  // specification's fallback promotes a lone scanned candidate to NumSamples
  // of 1 so the warp path is not silently disabled.
  let field = ws_test_field(16, 16, 0, 4, 4, 4, 900, 900)
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, false, 16, 24, av1_last_frame),
    1,
  )
}

///|
test "warp samples: no neighbour at all scans nothing" {
  let field = av1_motion_field(16, 16)
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, true, 8, 8, av1_last_frame),
    0,
  )
}

///|
test "warp samples: the corner suppression flags follow the above row" {
  // The above neighbour is 8 units wide and starts two units left of the block,
  // so `colOffset` is negative (top-left suppressed) while `colOffset + srcW`
  // still covers the block's width (top-right kept). With a 16x16 block under
  // test the top-right corner is eligible, so it is scanned in addition to the
  // above row.
  let field = ws_test_field(16, 16, 0, 2, 8, 4, 16, 24)
  assert_eq(
    av1_warp_samples(field, 4, 4, 4, 4, true, false, 16, 24, av1_last_frame),
    1,
  )
}
