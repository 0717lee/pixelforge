/// `Div_Mult` is the one piece of the temporal motion-vector projection that the
/// local specification states in full, so it can be pinned without libaom or
/// dav1d. The two constants that gate the rest of the projection
/// (`MAX_FRAME_DISTANCE`, `MAX_OFFSET_WIDTH`/`HEIGHT`) and the `Round2Signed`
/// definition are not in the local references; see HANDOFF.md addendum 25 for
/// what is still missing before `av1_mv_projection` can be written.

///|
test "Div_Mult matches the specification table" {
  let expected = [
    0, 16384, 8192, 5461, 4096, 3276, 2730, 2340, 2048, 1820, 1638, 1489, 1365, 1260,
    1170, 1092, 1024, 963, 910, 862, 819, 780, 744, 712, 682, 655, 630, 606, 585,
    564, 546, 528,
  ]
  assert_eq(av1_mv_div_mult.length(), av1_mv_div_mult_size)
  assert_eq(av1_mv_div_mult, expected)
}

///|
test "Div_Mult equals 16384 divided by its index" {
  // Every entry is the floor of 2^14 over the index, with index 0 mapped to 0
  // so a zero denominator projects to a zero vector. This is a check on the
  // transcription above: a single mistyped digit breaks it.
  for i in 0..<av1_mv_div_mult_size {
    let want = if i == 0 { 0 } else { 16384 / i }
    assert_eq(av1_mv_div_mult[i], want)
  }
}

///|
test "Div_Mult decreases over the usable indices" {
  // The projection relies on the table being a decreasing reciprocal, so a
  // transposed or duplicated row would be caught here too. Index 0 is the
  // zero-denominator special case and sits below index 1 by construction, so
  // the run starts at 2.
  for i in 2..<av1_mv_div_mult_size {
    assert_true(av1_mv_div_mult[i] <= av1_mv_div_mult[i - 1])
  }
  assert_eq(av1_mv_div_mult[0], 0)
  assert_eq(av1_mv_div_mult[1], 1 << 14)
  assert_true(av1_mv_div_mult[av1_mv_div_mult_size - 1] > 0)
}
