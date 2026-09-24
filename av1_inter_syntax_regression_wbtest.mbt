/// Regression coverage for inter syntax and tile-local reconstruction. These
/// tests compare entropy state as well as output geometry: a plausible-looking
/// prediction must not hide an extra or missing arithmetic-decoder symbol.

///|
fn av1_inter_regression_info(
  tile_row? : Int = 0,
  tile_col? : Int = 0,
  tile_col_end? : Int = 8,
  filter? : Int = av1_interp_switchable,
  warp? : Bool = false,
) -> Av1InterInfo {
  let reference = av1_obmc_test_reference()
  let gm_params = Array::makei(8, _ => [0, 0, 65536, 0, 0, 65536])
  let gm_type = Array::make(8, av1_gm_identity)
  if warp {
    gm_type[av1_last_frame] = av1_gm_affine
    gm_params[av1_last_frame] = [300000, 100000, 65536, 4096, 0, 65536]
  }
  av1_inter_info(
    {
      field: av1_motion_field(8, 8),
      frame: {
        allow_high_precision_mv: false,
        use_ref_frame_mvs: false,
        force_integer_mv: 0,
        is_motion_mode_switchable: true,
        allow_warped_motion: true,
        gm_type,
        gm_params,
        ref_frame_sign_bias: Array::make(8, 0),
        frame_width: 32,
        frame_height: 32,
        temporal: None,
      },
      refs: [
        None,
        Some(reference),
        Some(reference),
        None,
        None,
        None,
        None,
        None,
      ],
      interpolation_filter: filter,
      enable_dual_filter: true,
      skip_mode_present: true,
      skip_mode_frame: [av1_last_frame, av1_last2_frame],
      reference_select: true,
      enable_interintra_compound: true,
      ref_distances: Array::make(8, 0),
      enable_masked_compound: true,
      enable_jnt_comp: true,
      mi_cols: 8,
      mi_rows: 8,
    },
    tile_row,
    tile_col,
    8,
    tile_col_end,
  )
}

///|
fn av1_inter_regression_entropy(
  got : Av1SymbolDecoder,
  expected : Av1SymbolDecoder,
) -> Unit raise {
  assert_eq(got.bit_pos, expected.bit_pos)
  assert_eq(got.symbol_range, expected.symbol_range)
  assert_eq(got.symbol_value, expected.symbol_value)
  assert_eq(got.symbol_max_bits, expected.symbol_max_bits)
  // The next syntax element is still the same after the operation under test.
  assert_eq(got.entropy_literal(12), expected.entropy_literal(12))
}

///|
test "inter regression: smallest split transforms become 4x4 leaves" {
  for shape in [(8, 8), (4, 8), (8, 4)] {
    let (width, height) = shape
    let state = av1_intra_state(32, 32, 100, 8, false, false, false, true)
    let info = av1_inter_regression_info()
    let index = match av1_intra_block_index(width, height) {
      Some(value) => value
      None => fail("test block geometry")
    }
    let block = av1_inter_block(
      0,
      0,
      width / 4,
      height / 4,
      index,
      false,
      false,
    )
    for row in state.vartx.rows {
      row[0] = 1
    }
    let data : Array[Byte] = [0xff, 0xff, 0x64, 0x93, 0x5a, 0xc7]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    assert_eq(expected.symbol([1, 32768, 0]), 1)
    let leaves : Array[Av1TxNode] = []
    assert_true(
      av1_read_var_tx_size(
        decoder, state, info, block, 0, 0, width, height, 0, leaves,
      ),
    )
    assert_eq(leaves.length(), width * height / 16)
    for i in 0..<leaves.length() {
      let leaf = leaves[i]
      assert_eq((leaf.width, leaf.height), (4, 4))
      assert_eq(
        (leaf.row, leaf.col),
        (i / (width / 4) * 4, i % (width / 4) * 4),
      )
    }
    let mut count = 0
    for row in state.vartx.rows {
      count = count + row[row.length() - 1]
    }
    assert_eq(count, 1)
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "inter regression: skip mode consumes no compound or filter syntax" {
  for filter in [av1_interp_switchable, 2] {
    let info = av1_inter_regression_info(filter~)
    let block = av1_inter_block(0, 0, 4, 4, 6, false, false)
    block.skip_mode = true
    block.skip = 1
    block.is_inter = true
    let data : Array[Byte] = [0xe3, 0x78, 0x2f, 0x51, 0x89, 0xa4]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    assert_true(av1_inter_block_motion(decoder, info, block))
    assert_eq(block.y_mode, av1_mode_nearest_nearest_mv)
    assert_eq(block.compound_type, av1_compound_average)
    assert_eq((block.compound_idx, block.comp_group_idx), (1, 0))
    assert_eq((block.interp_vertical, block.interp_horizontal), (0, 0))
    assert_eq(block.motion_mode, 0)
    for row in info.cdfs.comp_group_idx {
      assert_eq(row[row.length() - 1], 0)
    }
    for row in info.cdfs.interp_filter {
      assert_eq(row[row.length() - 1], 0)
    }
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "inter regression: compound blocks omit motion mode" {
  let info = av1_inter_regression_info()
  av1_obmc_test_store(info, 0, 2, 2, 2, 0, 0)
  let block = av1_inter_block(2, 2, 2, 2, 3, true, true)
  block.ref_frame = av1_last_frame
  block.ref_frame1 = av1_last2_frame
  block.y_mode = av1_mode_nearest_nearest_mv
  let data : Array[Byte] = [0xff, 0x72, 0x86, 0x13, 0xad]
  let decoder = av1_msac_new(data, true)
  let expected = av1_msac_new(data, true)
  assert_true(av1_read_motion_mode(decoder, info, block))
  assert_eq(block.motion_mode, 0)
  assert_eq(info.cdfs.use_obmc[3][2], 0)
  assert_eq(info.cdfs.motion_mode[3][3], 0)
  av1_inter_regression_entropy(decoder, expected)
}

///|
test "inter regression: local warp fallback always selects regular filters" {
  for filter in [av1_interp_switchable, 1, 2] {
    let info = av1_inter_regression_info(filter~)
    av1_obmc_test_store(info, 0, 2, 2, 2, 0, 0)
    let above = info.field.cols + 2
    info.field.interp_v[above] = 1
    info.field.interp_h[above] = 2
    let block = av1_inter_block(2, 2, 2, 2, 3, true, true)
    block.ref_frame = av1_last_frame
    block.motion_mode = 2
    block.warp = []
    let data : Array[Byte] = [0xb7, 0x19, 0xd3, 0x42]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    av1_read_interp_filter(decoder, info, block)
    assert_eq((block.interp_vertical, block.interp_horizontal), (0, 0))
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "inter regression: unavailable top-right warp candidate cannot change syntax" {
  for tile_edge in [true, false] {
    let info = av1_inter_regression_info(
      tile_col_end=if tile_edge { 4 } else { 8 },
    )
    av1_motion_field_store(
      info.field,
      0,
      2,
      2,
      2,
      av1_mode_nearest_mv,
      [av1_last2_frame, av1_none_frame],
      [0, 0],
      [0, 0],
    )
    av1_obmc_test_store(info, 0, 4, 2, 2, 0, 0)
    let block = av1_inter_block(2, 2, 2, 2, 3, true, false)
    block.ref_frame = av1_last_frame
    block.y_mode = av1_mode_nearest_mv
    let data : Array[Byte] = [0x8d, 0x72, 0x3a, 0xb9, 0x41]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    ignore(expected.symbol(info.cdfs.use_obmc[3].copy()))
    assert_true(
      av1_read_motion_mode(decoder, info, block, have_top_right=tile_edge),
    )
    assert_eq(info.cdfs.use_obmc[3][2], 1)
    assert_eq(info.cdfs.motion_mode[3][3], 0)
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "inter regression: nonzero tile origin uses the local segment map" {
  let empty = av1_segmentation_empty()
  let segmentation : Av1SegmentationParams = {
    enabled: true,
    update_map: true,
    temporal_update: false,
    update_data: true,
    feature_enabled: empty.feature_enabled,
    feature_data: empty.feature_data,
    seg_id_pre_skip: false,
    last_active_seg_id: 2,
  }
  let state = av1_intra_state(
    16,
    16,
    100,
    8,
    false,
    false,
    false,
    false,
    segmentation=Some(segmentation),
  )
  state.seg_ids[5] = 2
  state.seg_ids[6] = 2
  state.seg_ids[9] = 2
  let info = av1_inter_regression_info(tile_row=4, tile_col=4)
  for row in info.cdfs.skip_mode {
    row[0] = 1
  }
  let data : Array[Byte] = [0xff, 0xff, 0x64, 0x93, 0x5a, 0xc7]
  let decoder = av1_msac_new(data, true)
  let expected = av1_msac_new(data, true)
  assert_eq(expected.symbol([1, 32768, 0]), 1)
  assert_true(
    av1_inter_tile_block(
      decoder,
      state,
      info,
      { row: 8, col: 8, width: 8, height: 8, },
      Av1SbPartitionNone,
    ),
  )
  for index in [10, 11, 14, 15] {
    assert_eq(state.seg_ids[index], 2)
  }
  assert_eq(state.seg_ids[0], 0)
  av1_inter_regression_entropy(decoder, expected)
}

///|
test "inter regression: interintra reads local tile edges and availability" {
  for available in [true, false] {
    let state = av1_intra_state(16, 16, 100, 8, false, false, false, false)
    let info = av1_inter_regression_info(tile_row=4, tile_col=4)
    for plane in 0..<3 {
      let target = state.planes[plane]
      for i in 0..<target.pixels.length() {
        target.pixels[i] = 220
      }
    }
    let block = av1_inter_block(6, 6, 2, 2, 3, available, available)
    block.ref_frame = av1_last_frame
    block.interintra = 1
    block.interintra_mode = 0
    av1_motion_field_store(
      info.field,
      6,
      6,
      2,
      2,
      av1_mode_nearest_mv,
      [av1_last_frame, av1_none_frame],
      [0, 0],
      [0, 0],
      interp=[0, 0],
    )
    assert_true(
      av1_inter_predict(state, info, block, {
        row: 8,
        col: 8,
        width: 8,
        height: 8,
      }),
    )
    for plane in 0..<3 {
      let sub = if plane == 0 { 0 } else { 1 }
      let width = 8 >> sub
      let start = 8 >> sub
      let reference = match info.refs[av1_last_frame] {
        Some(value) => value
        None => fail("test reference")
      }
      let inter = av1_motion_compensate({
        reference,
        frame_width: 32,
        frame_height: 32,
        plane,
        x: 24 >> sub,
        y: 24 >> sub,
        width,
        height: width,
        mv_row: 0,
        mv_col: 0,
        filter_vertical: 0,
        filter_horizontal: 0,
        compound: false,
      })
      let intra = if available { 220 } else { 128 }
      let target = state.planes[plane]
      for y in 0..<width {
        for x in 0..<width {
          let weight = av1_ii_weight(0, y, x, 128 / width)
          assert_eq(
            target.pixels[(start + y) * target.width + start + x],
            (weight * intra + (64 - weight) * inter[y * width + x] + 32) >> 6,
          )
        }
      }
    }
  }
}

///|
test "inter regression: global warp falls back on sub-eight chroma planes" {
  let state = av1_intra_state(32, 32, 100, 8, false, false, false, false)
  let info = av1_inter_regression_info(warp=true)
  let block = av1_inter_block(2, 2, 2, 2, 3, true, true)
  block.ref_frame = av1_last_frame
  block.y_mode = av1_mode_global_mv
  block.mv_row = 8
  block.mv_col = 16
  av1_motion_field_store(
    info.field,
    2,
    2,
    2,
    2,
    block.y_mode,
    [av1_last_frame, av1_none_frame],
    [8, 0],
    [16, 0],
    interp=[0, 0],
  )
  assert_true(
    av1_inter_predict(state, info, block, {
      row: 8,
      col: 8,
      width: 8,
      height: 8,
    }),
  )
  for plane in [1, 2] {
    let reference = match info.refs[av1_last_frame] {
      Some(value) => value
      None => fail("test reference")
    }
    let expected = av1_motion_compensate({
      reference,
      frame_width: 32,
      frame_height: 32,
      plane,
      x: 4,
      y: 4,
      width: 4,
      height: 4,
      mv_row: 8,
      mv_col: 16,
      filter_vertical: 0,
      filter_horizontal: 0,
      compound: false,
    })
    let target = state.planes[plane]
    for y in 0..<4 {
      for x in 0..<4 {
        assert_eq(
          target.pixels[(4 + y) * target.width + 4 + x],
          expected[y * 4 + x],
        )
      }
    }
  }
}

///|
test "inter regression: tx type syntax ignores delta Q and lossless flag" {
  for syntax_q in [0, 49] {
    let state = av1_intra_state(32, 32, 49, 8, false, false, false, false)
    state.seg_syntax_q_idx = syntax_q
    state.seg_q_idx = if syntax_q == 0 { 49 } else { 0 }
    state.seg_lossless = syntax_q > 0
    let info = av1_inter_regression_info()
    let data : Array[Byte] = [0x89, 0x63, 0xab, 0x2d]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    if syntax_q > 0 {
      ignore(expected.symbol(info.cdfs.inter_tx_type_set1[1].copy()))
    }
    ignore(av1_inter_luma_tx_type(decoder, state, info, 8, 8, 0, 0))
    assert_eq(
      info.cdfs.inter_tx_type_set1[1][16],
      if syntax_q > 0 {
        1
      } else {
        0
      },
    )
    av1_inter_regression_entropy(decoder, expected)
  }
}

///|
test "inter regression: each compound global list reconstructs without extra syntax" {
  for warp_reference in [av1_last_frame, av1_last2_frame] {
    let state = av1_intra_state(32, 32, 100, 8, false, false, false, false)
    let info = av1_inter_regression_info()
    info.frame.gm_type[warp_reference] = av1_gm_affine
    info.frame.gm_params[warp_reference] = [0, 0, 65536, 4096, 0, 65536]
    let block = av1_inter_block(0, 0, 4, 4, 6, false, false)
    block.ref_frame = av1_last_frame
    block.ref_frame1 = av1_last2_frame
    block.y_mode = av1_mode_global_global_mv
    av1_motion_field_store(
      info.field,
      0,
      0,
      4,
      4,
      block.y_mode,
      [av1_last_frame, av1_last2_frame],
      [0, 0],
      [0, 0],
      interp=[0, 0],
    )
    let data : Array[Byte] = [0xe3, 0x78, 0x2f, 0x51]
    let decoder = av1_msac_new(data, true)
    let expected = av1_msac_new(data, true)
    assert_true(av1_read_motion_mode(decoder, info, block))
    assert_eq(block.motion_mode, 0)
    av1_inter_regression_entropy(decoder, expected)
    assert_true(
      av1_inter_predict(state, info, block, {
        row: 0,
        col: 0,
        width: 16,
        height: 16,
      }),
    )
    for plane in 0..<3 {
      assert_true(state.planes[plane].pixels.any(pixel => pixel != 0))
    }
    // Translational compound global motion remains reconstructible.
    info.frame.gm_type[warp_reference] = av1_gm_translation
    assert_true(
      av1_inter_predict(state, info, block, {
        row: 0,
        col: 0,
        width: 16,
        height: 16,
      }),
    )
  }
}
