/// The projection arithmetic is pure, so it can be pinned without a bitstream.
/// The expected values below are hand-computed from the specification's own
/// numbers: `Div_Mult[i] = floor(2^14 / i)`, `Round2Signed(x, 14)` halves the
/// whole expression, and the result is clipped to ±(2^14 - 1).

///|
test "mv projection halves a two-frame vector" {
  // Div_Mult[2] = 8192, so 100 * 1 * 8192 / 2^14 = 50 exactly.
  assert_eq(av1_mv_projection(100, -100, 1, 2), (50, -50))
}

///|
test "mv projection over three frames floors toward zero" {
  // Div_Mult[3] = 5461, so 232 * 5461 / 2^14 = 77.33, which rounds to 77.
  assert_eq(av1_mv_projection(232, -232, 1, 3), (77, -77))
}

///|
test "mv projection saturates at the 14-bit bound" {
  // 1000 over one frame projects to 31000, far past the ±16383 clip.
  assert_eq(
    av1_mv_projection(1000, -1000, 31, 1),
    ((1 << 14) - 1, -((1 << 14) - 1)),
  )
}

///|
test "mv projection of a zero numerator is zero" {
  assert_eq(av1_mv_projection(500, -500, 0, 4), (0, 0))
}

///|
test "mv projection over a zero denominator is zero" {
  // Div_Mult[0] is defined as 0, so the product is zero rather than a fault.
  assert_eq(av1_mv_projection(500, -500, 1, 0), (0, 0))
}

///|
test "mv projection clips the numerator to the frame distance bound" {
  // The bound is 31, so a numerator of 40 behaves as 31.
  let clipped = av1_mv_projection(100, 100, 40, 1)
  let exact = av1_mv_projection(100, 100, 31, 1)
  assert_eq(clipped, exact)
}

///|
test "mv projection clips the denominator to the frame distance bound" {
  // Div_Mult has 32 entries, so a denominator past the bound reuses index 31.
  let clipped = av1_mv_projection(100, 100, 1, 40)
  let exact = av1_mv_projection_component(100, 1, 31)
  assert_eq(clipped, (exact, exact))
}

///|
test "mv projection is symmetric under negation" {
  // Round2Signed is sign-symmetric, so a mirrored vector must project mirrored.
  let (r1, c1) = av1_mv_projection(137, -91, 5, 7)
  let (r2, c2) = av1_mv_projection(-137, 91, 5, 7)
  assert_eq(r1, -r2)
  assert_eq(c1, -c2)
}

///|
test "mv projection constants stay inside the reciprocal table" {
  // maxFrameDistance indexes Div_Mult, which has 32 entries; this is the
  // invariant that let the bound be derived before go-av1 was consulted.
  assert_true(av1_mv_max_frame_distance < av1_mv_div_mult_size)
  assert_true(av1_mv_max_frame_distance > 0)
  assert_eq(av1_mv_div_mult[av1_mv_max_frame_distance], 528)
  assert_eq(av1_mv_invalid, -32768)
  assert_eq(av1_mv_refmvs_limit, 4095)
  assert_eq(av1_mv_stack_stamp, 1)
}

///|
test "mv block position keeps a nearby projection inside the window" {
  // A 64x64 frame is 16 MI per axis, so the 8x8 grid is 8 units wide. The window
  // around grid coordinate 4 is [3, 11] on the row axis (max_offset 0 means the
  // projected coordinate must stay inside the same eight-unit band) and much
  // wider on the column axis (max_offset 8).
  // The shift is `delta >> 6`, so 96 (twelve samples in 1/8-pel) moves the
  // coordinate by exactly one 8x8 unit.
  let (x8, y8, ok) = av1_mv_block_position(4, 4, 0, 96, -1, 16, 16)
  // The direction multiplier applies to both axes, so the column also steps
  // back one unit.
  assert_eq((x8, y8, ok), (3, 4, true))
}

///|
test "mv block position rejects a projection that leaves the frame" {
  // A huge column vector pushes the projected coordinate past the grid extent.
  let (_, _, ok) = av1_mv_block_position(0, 0, 0, 1 << 20, -1, 16, 16)
  assert_eq(ok, false)
}

///|
test "mv block position rejects a row that leaves its eight-unit band" {
  // maxOffsetHeight is 0, so a projected coordinate outside [base8, base8+8)
  // is refused even when it is still inside the frame.
  let (_, y8, ok) = av1_mv_block_position(0, 0, 1 << 20, 0, -1, 16, 16)
  assert_eq(ok, false)
}

///|
test "mv block position rejects a negative projection" {
  let (_, _, ok) = av1_mv_block_position(0, 0, -1 << 20, 0, -1, 16, 16)
  assert_eq(ok, false)
}

///|
test "mv block position sign follows the direction multiplier" {
  // The same projected vector moves the coordinate the other way when the
  // destination sign flips. Grid coordinate 7 sits at the top of its eight-unit
  // band and maxOffsetHeight is 0, so only the backward direction fits.
  let (_, y1, ok1) = av1_mv_block_position(4, 7, 96, 0, 1, 16, 16)
  let (_, y2, ok2) = av1_mv_block_position(4, 7, 96, 0, -1, 16, 16)
  assert_eq((y1, ok1), (8, false))
  assert_eq((y2, ok2), (6, true))
}
