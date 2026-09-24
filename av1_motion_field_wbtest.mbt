/// `motion_field_estimation` is the driver that decides which reference frames
/// get projected and in which order. The two things a transcription slip would
/// break are the initialisation (every cell must start invalid so a hole is
/// distinguishable from a real projection) and the source eligibility test (a
/// key frame, an intra-only frame or a differently sized one must not be
/// projected at all). The projection arithmetic itself is pinned separately in
/// `av1_mv_projection_wbtest.mbt`.

///|
/// A sequence with order hints enabled, which is the only configuration in
/// which any of this runs. Taken from a real parse of `general_inter_64x64`,
/// the one committed fixture whose sequence header turns them on, rather than
/// hand-written so the test cannot drift from the parser's field types.
fn mfe_test_sequence() -> Av1SequenceInfo raise {
  match av1_sequence_info(general_inter_64x64_obu) {
    Some(value) => value
    None => fail("mfe test: no sequence header")
  }
}

///|
test "motion field estimation starts from an empty grid" {
  // No reference frames are stored, so nothing can be projected and every cell
  // of every per-reference grid must carry the invalid vector. A hole has to be
  // distinguishable from a real projection, or the temporal scan would read
  // garbage as a candidate.
  let refs : Array[Av1RefFrame?] = Array::make(av1_total_refs_per_frame, None)
  let hints : Array[Int] = Array::make(av1_total_refs_per_frame, 0)
  hints[av1_golden_frame] = 1
  hints[av1_alt_ref_frame] = 2
  let grid = av1_motion_field_estimation(
    mfe_test_sequence(),
    3,
    hints,
    refs,
    16,
    16,
  )
  assert_eq((grid.w8, grid.h8), (8, 8))
  assert_eq(grid.refs.length(), av1_alt_ref_frame - av1_last_frame + 1)
  for slot in 0..<grid.mv_rows.length() {
    for value in grid.mv_rows[slot] {
      assert_eq(value, av1_mv_invalid)
    }
    for value in grid.mv_cols[slot] {
      assert_eq(value, av1_mv_invalid)
    }
  }
}

///|
test "motion field estimation refuses a key frame as a source" {
  // A key frame carries no motion field, so the projection process must report
  // an unusable source and leave the grid untouched rather than projecting
  // whatever its empty arrays happen to hold.
  let refs : Array[Av1RefFrame?] = Array::make(av1_total_refs_per_frame, None)
  let samples : Array[Int] = Array::make(64 * 64, 100)
  refs[av1_last_frame] = Some(av1_mc_test_frame(samples, 64, 64, 32, 32, 8, 0))
  let hints : Array[Int] = Array::make(av1_total_refs_per_frame, 0)
  let grid = av1_motion_field_estimation(
    mfe_test_sequence(),
    1,
    hints,
    refs,
    16,
    16,
  )
  for slot in 0..<grid.mv_rows.length() {
    for value in grid.mv_rows[slot] {
      assert_eq(value, av1_mv_invalid)
    }
  }
}

///|
test "motion field estimation keeps the grid shape of the current frame" {
  // The grid is addressed in the current frame's 8x8 units, so its shape follows
  // the current frame and not whatever the references happen to be.
  let refs : Array[Av1RefFrame?] = Array::make(av1_total_refs_per_frame, None)
  let hints : Array[Int] = Array::make(av1_total_refs_per_frame, 0)
  let grid = av1_motion_field_estimation(
    mfe_test_sequence(),
    1,
    hints,
    refs,
    16,
    16,
  )
  assert_eq((grid.w8, grid.h8), (8, 8))
  assert_eq(grid.mv_rows.length(), 7)
  for slot in 0..<grid.mv_rows.length() {
    assert_eq(grid.mv_rows[slot].length(), 64)
    assert_eq(grid.mv_cols[slot].length(), 64)
  }
}

///|
test "motion field estimation excludes LAST when its ALTREF matches current GOLDEN" {
  let sequence = mfe_test_sequence()
  let base = av1_mc_test_frame(Array::make(64 * 64, 100), 64, 64, 32, 32, 8, 0)
  let saved_hints = Array::make(8, 0)
  let vectors = Array::make(16 * 16 * 2, 0)
  for unit in 0..<(16 * 16) {
    vectors[unit * 2] = 8
    vectors[unit * 2 + 1] = 16
  }
  let last : Av1RefFrame = {
    ..base,
    frame_type: av1_inter_frame,
    order_hint: 1,
    mi_cols: 16,
    mi_rows: 16,
    mf_refs: Array::make(16 * 16, av1_last_frame),
    mf_mvs: vectors,
    saved_order_hints: saved_hints,
  }
  let refs : Array[Av1RefFrame?] = Array::make(8, None)
  refs[av1_last_frame] = Some(last)
  let hints = Array::make(8, 0)
  hints[av1_last_frame] = 1
  let excluded = av1_motion_field_estimation(sequence, 2, hints, refs, 16, 16)
  for row in excluded.mv_rows {
    for value in row {
      assert_eq(value, av1_mv_invalid)
    }
  }
  // Changing only the ALTREF-of-LAST identity makes the same saved vectors
  // eligible; the source reference for their projection still has hint zero.
  saved_hints[av1_alt_ref_frame] = 3
  let included = av1_motion_field_estimation(sequence, 2, hints, refs, 16, 16)
  assert_eq(included.mv_rows[0][0], 8)
  assert_eq(included.mv_cols[0][0], 16)
}
