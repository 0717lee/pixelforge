/// Whitebox tests for the AV1 loop-restoration filter kernels.
///
/// The fixtures are deterministic: hand-computed values pin the Wiener
/// round constants (bd 8/10/12), the 7-tap symmetric expansion, the
/// delta-convolution geometry, the SGR projection mix and the
/// intermediate clip; the independent reference implementation in
/// `_refs/lr_filter_sim.py` (audit §6/§7 rules with the go-av1
/// quantization) generates the full 120x16 expected planes compared
/// pixel by pixel. Cross-stripe tests place a unit rectangle over the
/// 56-row boundary so one piece reads the frame inside the stripe and
/// the other resolves the saved deblocked pairs.

///|
/// A constant plane at the given value.
fn av1_filter_test_plane(
  width : Int,
  height : Int,
  value : Int,
) -> Array[Int] {
  Array::make(width * height, value)
}

///|
/// A plane with a single vertical stripe of `value` at column `col`.
fn av1_filter_test_delta(
  width : Int,
  height : Int,
  col : Int,
  value : Int,
) -> Array[Int] {
  Array::makei(width * height, i => {
    let c = i % width
    if c == col { value } else { 0 }
  })
}

///|
/// A plane whose row y holds `(base + step*y + x) % 256`.
fn av1_filter_test_rows(
  width : Int,
  height : Int,
  base : Int,
  step : Int,
) -> Array[Int] {
  Array::makei(width * height, i => {
    let row = i / width
    (base + step * row + (i % width)) % 256
  })
}

///|
/// One-plane source view over a constant-stride frame.
fn av1_filter_test_view(
  store : Av1RestorationStripeStore,
  frame : Array[Int],
  stride : Int,
) -> Av1RestorationSourceView {
  { store, frame: [frame], frame_strides: [stride] }
}

///|
/// A monochrome layout with one unit size and the derived grid.
fn av1_filter_test_layout(
  width : Int,
  height : Int,
  unit : Int,
  mode : Av1RestorationType,
) -> Av1RestorationLayout {
  {
    config: { modes: [mode], unit_sizes: [unit] },
    frame_width: width,
    upscaled_width: width,
    frame_height: height,
    superres_denom: 8,
    unit_cols: [av1_lr_count_units(unit, width)],
    unit_rows: [av1_lr_count_units(unit, height)],
  }
}

///|
/// Assert every sample of one output plane.
fn av1_filter_assert_plane(
  plane : Array[Int],
  width : Int,
  height : Int,
  expected : Array[Int],
) -> Unit raise {
  assert_eq(plane.length(), width * height)
  for i in 0..<(width * height) {
    assert_eq(plane[i], expected[i])
  }
}

///|
test "wiener coeff expands the symmetric 7-tap filter" {
  assert_eq(av1_wiener_coeff([1, 2, 3]), [1, 2, 3, 116, 3, 2, 1])
  assert_eq(av1_wiener_coeff([0, 0, 0]), [0, 0, 0, 128, 0, 0, 0])
  // A chroma tap 0 of zero makes the 7-tap loop the 5-tap filter.
  assert_eq(av1_wiener_coeff([0, 4, 8]), [0, 4, 8, 104, 8, 4, 0])
  // A one-tap filter keeps the center at 128.
  assert_eq(av1_wiener_coeff([2, 0, 0]), [2, 0, 0, 124, 0, 0, 2])
}

///|
test "unit cells extend the last cell to the plane edge" {
  assert_eq(av1_lr_unit_cell(64, 200, 3, 0), (0, 64))
  assert_eq(av1_lr_unit_cell(64, 200, 3, 1), (64, 128))
  assert_eq(av1_lr_unit_cell(64, 200, 3, 2), (128, 200))
  assert_eq(av1_lr_unit_cell(128, 120, 1, 0), (0, 120))
}

///|
test "round n and clip follow the normative arithmetic" {
  assert_eq(av1_lr_round_n(5, 1), 3)
  assert_eq(av1_lr_round_n(7, 2), 2)
  assert_eq(av1_lr_round_n(-5, 1), -2)
  assert_eq(av1_lr_round_n(1234, 0), 1234)
  assert_eq(av1_lr_round_n(1234, -3), 1234)
  assert_eq(av1_lr_clip(0, 255, -1), 0)
  assert_eq(av1_lr_clip(0, 255, 300), 255)
  assert_eq(av1_lr_clip(0, 255, 100), 100)
}

///|
test "sgr parameter table lookup covers the 4-bit ep range" {
  assert_eq(av1_sgr_params(0), Some((2, 12, 1, 4)))
  assert_eq(av1_sgr_params(10), Some((0, 0, 1, 5)))
  assert_eq(av1_sgr_params(15), Some((2, 75, 0, 0)))
  assert_true(av1_sgr_params(16) is None)
  assert_true(av1_sgr_params(-1) is None)
}

///|
test "wiener identity taps reproduce a constant plane" {
  let width = 16
  let height = 16
  let lf = av1_filter_test_plane(width, height, 100)
  let post = av1_filter_test_plane(width, height, 100)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([0, 0, 0], [0, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height,
    av1_filter_test_plane(width, height, 100))
}

///|
test "wiener delta column convolves at the hand-computed values" {
  // One 255 column in an 8x8 plane, horizontal taps [1,0,0] and
  // identity vertical taps. The intermediate clip is inactive; the
  // expected row is roundN(128*mid, 11) of the 7-tap sums.
  let width = 8
  let height = 8
  let lf = av1_filter_test_plane(width, height, 0)
  let post = av1_filter_test_delta(width, height, 4, 255)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([0, 0, 0], [1, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  // Every row reads the same delta column, so the expected row
  // [0, 2, 0, 0, 251, 0, 0, 2] repeats down the plane.
  let expected = av1_filter_test_plane(width, height, 0)
  for y in 0..<height {
    expected[y * width + 1] = 2
    expected[y * width + 4] = 251
    expected[y * width + 7] = 2
  }
  av1_filter_assert_plane(out[0], width, height, expected)
}

///|
test "wiener switches round constants at bit depth 12" {
  // The same delta scene at bd 12 keeps the same output values because
  // round0/interRound move 3/11 to 5/9 in lockstep with the offset.
  let width = 8
  let height = 8
  let lf = av1_filter_test_plane(width, height, 0)
  let post = av1_filter_test_delta(width, height, 4, 255)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    12,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([0, 0, 0], [1, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 12, true).unwrap()
  let expected = av1_filter_test_plane(width, height, 0)
  for y in 0..<height {
    expected[y * width + 1] = 2
    expected[y * width + 4] = 251
    expected[y * width + 7] = 2
  }
  av1_filter_assert_plane(out[0], width, height, expected)
}

///|
test "wiener at bit depth 10 keeps the same round constants" {
  // round0/interRound stay 3/11 for bd 8 and 10; only the offset and
  // limit move. A constant 600 at bd 10 has mid = roundN(128*600, 3)
  // = 9600, inside the clip range [-8192, 24575], so the identity
  // holds. (The clip is sized so legal samples never saturate.)
  let width = 8
  let height = 8
  let lf = av1_filter_test_plane(width, height, 600)
  let post = av1_filter_test_plane(width, height, 600)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    10,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([0, 0, 0], [0, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 10, true).unwrap()
  av1_filter_assert_plane(out[0], width, height,
    av1_filter_test_plane(width, height, 600))
}

///|
test "sgr set 15 with zero projections is the identity" {
  // set 15 = (r0=2, eps0=30, r1=0); w0=w1=0 makes the whole unit the
  // unshifted center pixel, so the plane passes through unchanged.
  let width = 16
  let height = 16
  let lf = av1_filter_test_plane(width, height, 100)
  let post = av1_filter_test_plane(width, height, 100)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationSgrproj)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(15, [0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height,
    av1_filter_test_plane(width, height, 100))
}

///|
test "sgr set 0 with constant input runs both box passes" {
  // Constant 200, set 0 = (r0=2, eps0=12, r1=1, eps1=4), xqd [31,32].
  // Both box passes run: each window has p=0 so a2=1, while b2 =
  // (256-1)*sum*one_over_n keeps the projection at the center value,
  // so flt0 = flt1 = 3201 in the cdef domain and
  // v = 32*3200 + 31*3201 + 65*3201 = 409696, roundN(v, 11) = 200.
  // The plane is unchanged; the non-constant behavior of both passes
  // is pinned by the full-plane reference fixtures below.
  let width = 8
  let height = 8
  let lf = av1_filter_test_plane(width, height, 50)
  let post = av1_filter_test_plane(width, height, 200)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationSgrproj)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(0, [31, 32]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height,
    av1_filter_test_plane(width, height, 200))
}

///|
test "cross-stripe wiener reads the saved deblocked rows" {
  // 16x120 plane: stripes [0,56) and [56,120). The post-CDEF frame is
  // constant 200, the saved LF rows are constant 100. With vertical
  // taps [1,0,0] the output of row y depends on src(y-3), src(y),
  // src(y+3); rows 53..58 touch one saved row and drop to 199, every
  // other row stays at 200.
  let width = 16
  let height = 120
  let lf = av1_filter_test_plane(width, height, 100)
  let post = av1_filter_test_plane(width, height, 200)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([1, 0, 0], [0, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  let expected = av1_filter_test_plane(width, height, 200)
  for y in 53..<59 {
    for x in 0..<width {
      expected[y * width + x] = 199
    }
  }
  av1_filter_assert_plane(out[0], width, height, expected)
}

///|
test "full-plane wiener matches the independent reference" {
  let width = 16
  let height = 120
  let lf = av1_filter_test_rows(width, height, 0, 37)
  let post = av1_filter_test_rows(width, height, 0, 53)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([1, 0, 0], [1, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height, lr_sim_wiener)
}

///|
test "full-plane vertical-tap wiener matches the independent reference" {
  let width = 16
  let height = 120
  let lf = av1_filter_test_rows(width, height, 0, 37)
  let post = av1_filter_test_rows(width, height, 0, 53)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([3, -7, 15], [0, 0, 0]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height, lr_sim_wiener_v)
}

///|
test "full-plane sgr set 0 matches the independent reference" {
  let width = 16
  let height = 120
  let lf = av1_filter_test_rows(width, height, 0, 37)
  let post = av1_filter_test_rows(width, height, 0, 53)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationSgrproj)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(0, [31, 32]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height, lr_sim_sgr_set0)
}

///|
test "full-plane sgr set 10 matches the independent reference" {
  // set 10 = (r0=0, eps0=0, r1=1, eps1=5): the first projection is
  // substituted by the unshifted center pixel, the second box filter
  // still runs.
  let width = 16
  let height = 120
  let lf = av1_filter_test_rows(width, height, 0, 37)
  let post = av1_filter_test_rows(width, height, 0, 53)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationSgrproj)
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(10, [0, 32]))],
  ]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height, lr_sim_sgr_set10)
}

///|
test "frame driver applies chroma subsampling and None pass-through" {
  // 128x128 4:2:0 frame: luma is SGR-restored (identity set 15), both
  // chroma planes are None and pass through unchanged.
  let width = 128
  let height = 128
  let luma = av1_filter_test_plane(width, height, 50)
  let chroma = av1_filter_test_plane(64, 64, 25)
  let store = av1_restoration_save_stripes(
    [luma, chroma, chroma],
    width,
    width,
    width,
    height,
    8,
    false,
  ).unwrap()
  let post_luma = av1_filter_test_plane(width, height, 200)
  let post_chroma = av1_filter_test_plane(64, 64, 100)
  let view : Av1RestorationSourceView = {
    store,
    frame: [post_luma, post_chroma, post_chroma],
    frame_strides: [128, 64, 64],
  }
  let layout : Av1RestorationLayout = {
    config: {
      modes: [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
      unit_sizes: [128, 64, 64],
    },
    frame_width: width,
    upscaled_width: width,
    frame_height: height,
    superres_denom: 8,
    unit_cols: [1, 1, 1],
    unit_rows: [1, 1, 1],
  }
  let units : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(15, [0, 0]))],
    [None],
    [None],
  ]
  let out = av1_restoration_filter_frame(
    view,
    units,
    layout,
    8,
    false,
    subsampling_x=true,
    subsampling_y=true,
  ).unwrap()
  av1_filter_assert_plane(out[0], width, height,
    av1_filter_test_plane(width, height, 200))
  av1_filter_assert_plane(out[1], 64, 64, av1_filter_test_plane(64, 64, 100))
  av1_filter_assert_plane(out[2], 64, 64, av1_filter_test_plane(64, 64, 100))
}

///|
test "none units leave the plane untouched" {
  let width = 8
  let height = 8
  let lf = av1_filter_test_plane(width, height, 0)
  let post = av1_filter_test_delta(width, height, 4, 255)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  let units : Array[Array[Av1RestorationUnit?]] = [[None]]
  let out = av1_restoration_filter_frame(view, units, layout, 8, true).unwrap()
  av1_filter_assert_plane(out[0], width, height, post)
}

///|
test "filter plane rejects invalid unit parameters" {
  let width = 16
  let height = 16
  let lf = av1_filter_test_plane(width, height, 0)
  let post = av1_filter_test_plane(width, height, 0)
  let store = av1_restoration_save_stripes(
    [lf],
    width,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let view = av1_filter_test_view(store, post, width)
  let layout = av1_filter_test_layout(width, height, 128, Av1RestorationWiener)
  // Wiener taps must carry exactly three coefficients per axis.
  let bad_taps : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitWiener([1, 0], [0, 0, 0]))],
  ]
  assert_true(
    av1_restoration_filter_frame(view, bad_taps, layout, 8, true) is None,
  )
  let sgr_layout = av1_filter_test_layout(width, height, 128,
    Av1RestorationSgrproj)
  // SGR projections must carry exactly two coefficients.
  let bad_xqd_len : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(0, [1, 2, 3]))],
  ]
  assert_true(
    av1_restoration_filter_frame(view, bad_xqd_len, sgr_layout, 8, true) is None,
  )
  // Projection ranges: w0 in [-96, 31], w1 in [-32, 95].
  for xqd in [[-97, 0], [32, 0], [0, -33], [0, 96]] {
    let bad_range : Array[Array[Av1RestorationUnit?]] = [
      [Some(Av1RestorationUnitSgrproj(0, xqd))],
    ]
    assert_true(
      av1_restoration_filter_frame(view, bad_range, sgr_layout, 8, true) is None,
    )
  }
  // The parameter version must fit the 4-bit ep range.
  let bad_set : Array[Array[Av1RestorationUnit?]] = [
    [Some(Av1RestorationUnitSgrproj(16, [0, 0]))],
  ]
  assert_true(
    av1_restoration_filter_frame(view, bad_set, sgr_layout, 8, true) is None,
  )
  // The unit map must match the derived grid.
  let bad_count : Array[Array[Av1RestorationUnit?]] = [
    [None, None],
  ]
  assert_true(
    av1_restoration_filter_frame(view, bad_count, layout, 8, true) is None,
  )
  // A plane beyond the configured modes is rejected.
  let short_layout : Av1RestorationLayout = {
    config: { modes: [Av1RestorationWiener], unit_sizes: [128] },
    frame_width: width,
    upscaled_width: width,
    frame_height: height,
    superres_denom: 8,
    unit_cols: [1],
    unit_rows: [1],
  }
  assert_true(
    av1_restoration_filter_plane(post, view, [None], short_layout, 1, false,
      false, 8) is None,
  )
  // A zero box radius is not a valid direct call; the caller
  // substitutes the center pixel instead.
  assert_true(
    av1_sgr_box_pass(view, 0, 0, 0, 8, 8, 0, 0, 12, 0, 8) is None,
  )
}
