/// Regression vectors for neighbour selection and planar warp addressing.
/// The four expected models below were evaluated with the unchanged scalar
/// dav1d 1.2.1 src/warpmv.c (SHA-256
/// db7eab1ea1dc6836ed9a29693ec64d581f8330ccf36eed00d6f6bffd0f4be2d4),
/// calling dav1d_find_affine_int then dav1d_get_shear_params at bx=by=4,
/// bw4=bh4=4, with a zero block motion vector. Explicit sample pairs accompany
/// each case so the reference does not depend on this decoder's mask walk.

///|
fn av1_warp_regression_store(
  field : Av1MotionField,
  row : Int,
  col : Int,
  width : Int,
  height : Int,
  mv_row : Int,
  mv_col : Int,
  ref_name? : Int = 1,
) -> Unit {
  av1_motion_field_store(
    field,
    row,
    col,
    width,
    height,
    13,
    [ref_name, -1],
    [mv_row, 0],
    [mv_col, 0],
  )
}

///|
fn av1_warp_regression_model(
  model : Av1WarpModel?,
  matrix : Array[Int],
  coefficients : Array[Int],
) -> Unit raise {
  match model {
    None => fail("valid scalar-reference affine model was discarded")
    Some(model) => {
      assert_eq(model.matrix, matrix)
      assert_eq(model.coefficients, coefficients)
    }
  }
}

///|
test "warp regression preserves the only matching top-right candidate" {
  let field = av1_motion_field(16, 16)
  av1_warp_regression_store(field, 2, 4, 4, 2, 0, 0, ref_name=2)
  av1_warp_regression_store(field, 2, 8, 2, 2, 2, 1)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 4, 4, 4, false, true, 1),
    (1L << 32, 0L),
  )
  // (152,-40) -> (153,-38), one projectable corner neighbour.
  av1_warp_regression_model(
    av1_warp_derive(field, 4, 4, 4, 4, 4, 4, false, true, 1, 0, 0),
    [667, 0, 65833, -326, 709, 64827],
    [320, -320, 704, -704],
  )
  assert_eq(
    av1_warp_matching_masks(
      field,
      4,
      4,
      4,
      4,
      4,
      4,
      false,
      true,
      1,
      have_top_right=false,
    ),
    (0L, 0L),
  )
  assert_eq(
    av1_warp_derive(
      field,
      4,
      4,
      4,
      4,
      4,
      4,
      false,
      true,
      1,
      0,
      0,
      have_top_right=false,
    )
    is None,
    true,
  )
}

///|
test "warp regression does not duplicate a top neighbour covering the corner" {
  let field = av1_motion_field(32, 16)
  av1_warp_regression_store(field, 2, 0, 16, 2, 2, 1)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 4, 4, 4, false, true, 1),
    (1L, 0L),
  )
}

///|
test "warp regression sparse top mask samples distinct neighbour vectors" {
  let field = av1_motion_field(16, 16)
  av1_warp_regression_store(field, 2, 4, 2, 2, 2, 1)
  av1_warp_regression_store(field, 2, 6, 2, 2, 6, -2)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 4, 4, 4, false, true, 1),
    (5L, 0L),
  )
  // (24,-40) -> (25,-38), (88,-40) -> (86,-34).
  // Reading offset 1 instead of 2 duplicates the first neighbour's vector.
  av1_warp_regression_model(
    av1_warp_derive(field, 4, 4, 4, 4, 4, 4, false, true, 1, 0, 0),
    [63641, -32246, 62545, 224, 4037, 62901],
    [-3008, 256, 4224, -2624],
  )
}

///|
test "warp regression sparse left mask samples distinct neighbour vectors" {
  let field = av1_motion_field(16, 16)
  av1_warp_regression_store(field, 4, 2, 2, 2, 2, 1)
  av1_warp_regression_store(field, 6, 2, 2, 2, 6, -2)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 4, 4, 4, true, false, 1),
    (0L, 5L),
  )
  // (-40,24) -> (-39,26), (-40,88) -> (-42,94).
  av1_warp_regression_model(
    av1_warp_derive(field, 4, 4, 4, 4, 4, 4, true, false, 1, 0, 0),
    [63641, -32246, 65796, -3027, -2670, 69608],
    [256, -3008, -2688, 3968],
  )
}

///|
test "warp regression corner marker preserves the wide top neighbour offset" {
  let field = av1_motion_field(16, 16)
  av1_warp_regression_store(field, 2, 0, 8, 2, 2, 1)
  av1_warp_regression_store(field, 2, 8, 2, 2, 6, -2)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 4, 4, 4, false, true, 1),
    ((1L << 32) | 1L, 0L),
  )
  // (-8,-40) -> (-7,-38), (152,-40) -> (150,-34).
  av1_warp_regression_model(
    av1_warp_derive(field, 4, 4, 4, 4, 4, 4, false, true, 1, 0, 0),
    [25576, 19067, 64334, 90, 1636, 63071],
    [-1216, 64, 1664, -2496],
  )
}

///|
test "warp regression excludes top-right for a 128-pixel block axis" {
  let field = av1_motion_field(64, 48)
  av1_warp_regression_store(field, 2, 4, 4, 2, 0, 0, ref_name=2)
  av1_warp_regression_store(field, 2, 8, 2, 2, 2, 1)
  assert_eq(
    av1_warp_matching_masks(field, 4, 4, 4, 32, 4, 32, false, true, 1),
    (0L, 0L),
  )
}

///|
fn av1_warp_regression_frame(
  planes : Array[Array[Int]],
  width : Int,
  height : Int,
  coded_width : Int,
  coded_height : Int,
  sub_x : Int,
  sub_y : Int,
  bit_depth : Int,
) -> Av1RefFrame {
  {
    planes,
    width,
    height,
    coded_width,
    coded_height,
    sub_x,
    sub_y,
    bit_depth,
    frame_width: width,
    upscaled_width: width,
    frame_height: height,
    render_width: width,
    render_height: height,
    order_hint: 0,
    frame_type: av1_key_frame,
    frame_id: 0,
    order_hints: Array::make(av1_total_refs_per_frame, 0),
    gm_params: Array::make(av1_total_refs_per_frame, av1_identity_gm_params()),
    loop_filter_ref_deltas: av1_default_loop_filter_ref_deltas(),
    loop_filter_mode_deltas: [0, 0],
    cdfs: None,
    mf_refs: [],
    mf_mvs: [],
    mi_cols: 0,
    mi_rows: 0,
    saved_order_hints: [],
  }
}

///|
test "warp regression 444 planes use identical strides including the bottom edge" {
  let model = match
    av1_warp_from_global_motion([
      0x2000, -0x3000, 0x10000, 0x300, -0x300, 0x10000,
    ]) {
    Some(model) => model
    None => fail("rotation model rejected")
  }
  for bit_depth in [8, 10, 12] {
    let limit = (1 << bit_depth) - 1
    let pixels = Array::makei(16 * 16, i => (i * 11 + i / 16 * 37 + 19) & limit)
    let frame = av1_warp_regression_frame(
      [pixels, pixels, pixels],
      13,
      15,
      16,
      16,
      0,
      0,
      bit_depth,
    )
    for origin in [0, 2, 3] {
      let expected = av1_warp_predict(
        frame, model, 0, origin, origin, 0, 0, 8, 8,
      )
      for plane in [1, 2] {
        assert_eq(
          av1_warp_predict(frame, model, plane, origin, origin, 0, 0, 8, 8),
          expected,
        )
      }
    }
  }
}

///|
test "warp regression 420 and 422 chroma match equivalent plane coordinates" {
  let model = match
    av1_warp_from_global_motion([0x5000, 0x3000, 0x10000, 0, 0, 0x10000]) {
    Some(model) => model
    None => fail("translation model rejected")
  }
  for sub_y in [0, 1] {
    let stride = 16
    let coded_height = 24 >> sub_y
    let width = 15
    let height = (21 + sub_y) >> sub_y
    let pixels = Array::makei(stride * coded_height, i => {
      (i * 13 + i / stride * 23 + 5) & 1023
    })
    let frame = av1_warp_regression_frame(
      [Array::make(32 * 24, 0), pixels, pixels],
      29,
      21,
      32,
      24,
      1,
      sub_y,
      10,
    )
    let planar = av1_warp_regression_frame(
      [pixels, pixels, pixels],
      width,
      height,
      stride,
      coded_height,
      0,
      0,
      10,
    )
    let planar_model = match
      av1_warp_from_global_motion([
        0x2800,
        0x3000 >> sub_y,
        0x10000,
        0,
        0,
        0x10000,
      ]) {
      Some(model) => model
      None => fail("plane translation model rejected")
    }
    for origin in [0, 2, 4] {
      let expected = av1_warp_predict(
        planar,
        planar_model,
        0,
        origin >> 1,
        origin >> sub_y,
        0,
        0,
        8,
        8,
      )
      for plane in [1, 2] {
        assert_eq(
          av1_warp_predict(frame, model, plane, origin, origin, 0, 0, 8, 8),
          expected,
        )
      }
    }
  }
}
