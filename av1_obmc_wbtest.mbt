/// Overlapped block motion compensation, exercised where the committed fixture
/// cannot reach.
///
/// `inter_obmc_64x64` is a 64x64 frame whose only OBMC block sits on the top
/// row, so `AvailU` is 0 and the *above* pass of AV1 §7.11.3.9 never runs there.
/// The libaom build in `D:\ProgramData\anaconda3\Library\bin` segfaults before
/// flushing on most other two-frame encodes, so a second fixture with a
/// lower-row OBMC block could not be produced. These white-box cases drive
/// `av1_obmc_blend` directly instead, and pin the geometry, the mask
/// orientation and the blend rounding of the above pass.

///|
/// A reference frame whose luma plane is a 32x32 ramp: each row repeats, so a
/// vertical pass is a pure copy and only the horizontal filter is observable.
fn av1_obmc_test_reference() -> Av1RefFrame {
  let coded = av1_partition_coded_extent(32)
  let chroma_coded = av1_partition_coded_extent(16)
  let luma : Array[Int] = Array::make(coded * coded, 0)
  let chroma : Array[Int] = Array::make(chroma_coded * chroma_coded, 0)
  for y in 0..<32 {
    for x in 0..<32 {
      luma[y * coded + x] = 60 + x * 5 % 40
      if x < 16 && y < 16 {
        chroma[y * chroma_coded + x] = 100 + x * 3 % 20
      }
    }
  }
  {
    planes: [luma, chroma, chroma],
    coded_width: coded,
    coded_height: coded,
    width: 32,
    height: 32,
    sub_x: 1,
    sub_y: 1,
    bit_depth: 8,
    frame_width: 32,
    upscaled_width: 32,
    frame_height: 32,
    render_width: 32,
    render_height: 32,
    order_hint: 0,
    frame_type: 0,
    frame_id: 0,
    order_hints: [0, 0, 0, 0, 0, 0, 0, 0],
    gm_params: [],
    loop_filter_ref_deltas: [],
    loop_filter_mode_deltas: [],
    cdfs: None,
    // No inter block stage ran for this frame, so it carries no motion field
    // and is ineligible as a temporal-candidate source.
    mf_refs: [],
    mf_mvs: [],
    mi_cols: 0,
    mi_rows: 0,
    saved_order_hints: [],
  }
}

///|
/// A 32x32 luma / 16x16 chroma state whose planes hold one known pattern, and
/// the inter info of a one-tile frame over it.
fn av1_obmc_test_state() -> (Av1IntraState, Av1InterInfo) {
  let state = av1_intra_state(
    32,
    32,
    100,
    8,
    false,
    false,
    false,
    false,
    monochrome=false,
    sub_x=1,
    sub_y=1,
  )
  // A flat 200 everywhere: the own prediction the blend reads back.
  for plane in 0..<3 {
    let target = state.planes[plane]
    for i in 0..<target.pixels.length() {
      target.pixels[i] = 200
    }
  }
  let field = av1_motion_field(8, 8)
  let info = av1_inter_info(
    {
      field,
      frame: {
        allow_high_precision_mv: false,
        use_ref_frame_mvs: false,
        force_integer_mv: 0,
        is_motion_mode_switchable: false,
        allow_warped_motion: false,
        gm_type: [],
        gm_params: [],
        ref_frame_sign_bias: [],
        // is_scaled is only consulted on the three-symbol motion-mode branch;
        // this fixture never reaches it.
        frame_width: 32,
        frame_height: 32,
        // No temporal grid: use_ref_frame_mvs is false, so the scan is skipped
        // entirely.
        temporal: None,
      },
      // Indexed by reference name: av1_last_frame is 1, so the stored frame
      // sits in slot 1 and the rest stay empty.
      refs: [
        None,
        Some(av1_obmc_test_reference()),
        None,
        None,
        None,
        None,
        None,
        None,
      ],
      interpolation_filter: 4,
      enable_dual_filter: false,
      skip_mode_present: false,
      skip_mode_frame: [],
      reference_select: false,
      ref_distances: Array::make(8, 0),
      enable_masked_compound: false,
      enable_jnt_comp: false,
      mi_cols: 8,
      mi_rows: 8,
    },
    0,
    0,
    8,
    8,
  )
  (state, info)
}

///|
/// Store one inter block into the motion field the way the block stage does.
fn av1_obmc_test_store(
  info : Av1InterInfo,
  row : Int,
  col : Int,
  width4 : Int,
  height4 : Int,
  mv_row : Int,
  mv_col : Int,
) -> Unit {
  av1_motion_field_store(
    info.field,
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
}

///|
test "obmc above pass blends the top half of every column from the neighbour above" {
  let (state, info) = av1_obmc_test_state()
  // The block under test sits at MI row 4, column 4 (luma 16,16) and is 16x16,
  // so the above neighbour is read at (mi_row - 1, x4 | 1) = (3, 5).
  av1_obmc_test_store(info, 4, 4, 4, 4, 8, 8)
  av1_obmc_test_store(info, 3, 4, 4, 4, -16, 24)
  let block = av1_inter_block(4, 4, 4, 4, 0, true, false)
  block.motion_mode = 1
  guard av1_obmc_blend(state, info, block, 0) else {
    fail("obmc blend rejected")
  }
  let target = state.planes[0]
  // The neighbour's vector, interpolated over the shared strip, is what the
  // mask ramps the own prediction towards.
  let neighbour = av1_motion_compensate({
    reference: match av1_inter_reference(info, av1_last_frame) {
      Some(value) => value
      None => fail("no reference")
    },
    frame_width: 32,
    frame_height: 32,
    plane: 0,
    x: 16,
    y: 16,
    width: 16,
    height: 8,
    mv_row: -16,
    mv_col: 24,
    filter_vertical: av1_interp_eighttap,
    filter_horizontal: av1_interp_eighttap,
    compound: false,
  })
  let mask = av1_obmc_mask(8)
  for i in 0..<8 {
    for j in 0..<16 {
      let expected = (
          mask[i] * 200 + (64 - mask[i]) * neighbour[i * 16 + j] + 32
        ) >>
        6
      assert_eq(target.pixels[(16 + i) * 32 + 16 + j], expected)
    }
  }
  // Rows 8..15 are outside the above strip and stay at the own prediction.
  for i in 8..<16 {
    for j in 0..<16 {
      assert_eq(target.pixels[(16 + i) * 32 + 16 + j], 200)
    }
  }
}

///|
test "obmc above pass contributes nothing when the row above is intra" {
  let (state, info) = av1_obmc_test_state()
  // The block under test is inter, but the row it would blend from is an intra
  // block, so `RefFrames[candRow][candCol][0]` is INTRA_FRAME and no candidate
  // is added. This is the real reason a top-of-tile block gains nothing.
  av1_motion_field_store(
    info.field,
    3,
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
  av1_obmc_test_store(info, 4, 4, 4, 4, 8, 8)
  let block = av1_inter_block(4, 4, 4, 4, 0, true, false)
  block.motion_mode = 1
  guard av1_obmc_blend(state, info, block, 0) else {
    fail("obmc blend rejected")
  }
  let target = state.planes[0]
  for i in 0..<16 {
    for j in 0..<16 {
      assert_eq(target.pixels[(16 + i) * 32 + 16 + j], 200)
    }
  }
}

///|
test "obmc above pass uses the chroma grid and the 32-sample cap" {
  let (state, info) = av1_obmc_test_state()
  av1_obmc_test_store(info, 4, 4, 4, 4, 8, 8)
  av1_obmc_test_store(info, 3, 4, 4, 4, -16, 24)
  let block = av1_inter_block(4, 4, 4, 4, 0, true, false)
  block.motion_mode = 1
  guard av1_obmc_blend(state, info, block, 1) else {
    fail("obmc blend rejected")
  }
  let target = state.planes[1]
  // Chroma: predW = Min(8, 16) = 8, predH = Min(4, 16) = 4, so the strip is the
  // top-left 8x4 of the chroma block at (8, 8).
  let neighbour = av1_motion_compensate({
    reference: match av1_inter_reference(info, av1_last_frame) {
      Some(value) => value
      None => fail("no reference")
    },
    frame_width: 32,
    frame_height: 32,
    plane: 1,
    x: 8,
    y: 8,
    width: 8,
    height: 4,
    mv_row: -16,
    mv_col: 24,
    filter_vertical: av1_interp_eighttap,
    filter_horizontal: av1_interp_eighttap,
    compound: false,
  })
  let mask = av1_obmc_mask(4)
  for i in 0..<4 {
    for j in 0..<8 {
      let expected = (
          mask[i] * 200 + (64 - mask[i]) * neighbour[i * 8 + j] + 32
        ) >>
        6
      assert_eq(target.pixels[(8 + i) * 16 + 8 + j], expected)
    }
  }
  for i in 4..<8 {
    for j in 0..<8 {
      assert_eq(target.pixels[(8 + i) * 16 + 8 + j], 200)
    }
  }
}
