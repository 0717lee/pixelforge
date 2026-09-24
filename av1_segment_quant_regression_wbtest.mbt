/// Regression transcripts for AV1 get_qindex(ignoreDeltaQ=1), LosslessArray
/// and tile_info. Header fields are hand-authored from AV1 sections 5.9.14
/// and 5.9.15; dav1d 1.2.1 src/obu.c derives all eight lossless entries in
/// the same order, before reading filters or transform-mode syntax.

///|
fn av1_segment_quant_test_params(deltas : Array[Int]) -> Av1SegmentationParams {
  let params = {
    ..av1_segmentation_empty(),
    enabled: true,
    update_map: true,
    update_data: true,
    last_active_seg_id: 7,
  }
  for id in 0..<8 {
    params.feature_enabled[id][av1_seg_level_alt_q] = true
    params.feature_data[id][av1_seg_level_alt_q] = deltas[id]
  }
  params
}

///|
fn av1_segment_quant_test_state(
  base_q : Int,
  alt_q : Int,
  quant_deltas? : Av1QuantDeltas = {
    y_dc: 0,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  },
) -> Av1IntraState {
  av1_intra_state(
    16,
    16,
    base_q,
    8,
    false,
    false,
    false,
    true,
    segmentation=Some(av1_segment_quant_test_params(Array::make(8, alt_q))),
    quant_deltas~,
    delta_q_present=true,
  )
}

///|
test "segment ALT_Q restores lossless at nonzero frame base independent of SB delta Q" {
  let state = av1_segment_quant_test_state(49, -49)
  for sb_q in [20, 49, 60] {
    state.sb_q_idx = sb_q
    av1_seg_apply_block(state, 0, 0, 2, 2, 0)
    assert_eq(state.seg_syntax_q_idx, 0)
    assert_true(state.seg_lossless)
    assert_eq(state.seg_q_idx, if sb_q == 60 { 11 } else { 0 })
  }
  assert_eq(state.seg_ids[0], 0)
  assert_eq(state.seg_ids[state.cols + 1], 0)
}

///|
test "segment dequant zero does not turn nonzero nominal qindex lossless" {
  let state = av1_segment_quant_test_state(49, -20)
  state.sb_q_idx = 20
  av1_seg_apply_block(state, 0, 0, 1, 1, 0)
  assert_eq(state.seg_q_idx, 0)
  assert_eq(state.seg_syntax_q_idx, 29)
  assert_false(state.seg_lossless)
  // read_tx_type uses the nominal segment qindex even though dequant is zero.
  let decoder = av1_msac_new([b'\x00', b'\x00'], true)
  let row = state.tables.tx_set1[0][0]
  assert_eq(row[row.length() - 1], 0)
  assert_true(av1_intra_tx_type(decoder, state, 4, 4, 0) is Some(_))
  assert_eq(row[row.length() - 1], 1)
}

///|
test "zero nominal segment qindex omits tx type even with nonzero dequant and delta" {
  let state = av1_segment_quant_test_state(49, -49, quant_deltas={
    y_dc: 1,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  })
  state.sb_q_idx = 60
  av1_seg_apply_block(state, 0, 0, 1, 1, 0)
  assert_eq(state.seg_q_idx, 11)
  assert_eq(state.seg_syntax_q_idx, 0)
  assert_false(state.seg_lossless)
  let decoder = av1_msac_new([b'\x80', b'\x00'], true)
  let before = (decoder.bit_pos, decoder.symbol_range, decoder.symbol_value)
  assert_true(av1_intra_tx_type(decoder, state, 4, 4, 0) is Some(Av1TxDctDct))
  assert_eq(
    (decoder.bit_pos, decoder.symbol_range, decoder.symbol_value),
    before,
  )
  let row = state.tables.tx_set1[0][0]
  assert_eq(row[row.length() - 1], 0)
}

///|
test "segment lossless requires all five quantization deltas zero" {
  for
    deltas in [
      { y_dc: 1, u_dc: 0, u_ac: 0, v_dc: 0, v_ac: 0, },
      { y_dc: 0, u_dc: -1, u_ac: 0, v_dc: 0, v_ac: 0, },
      { y_dc: 0, u_dc: 0, u_ac: 1, v_dc: 0, v_ac: 0, },
      { y_dc: 0, u_dc: 0, u_ac: 0, v_dc: -1, v_ac: 0, },
      { y_dc: 0, u_dc: 0, u_ac: 0, v_dc: 0, v_ac: 1, },
    ] {
    let state = av1_segment_quant_test_state(49, -49, quant_deltas=deltas)
    av1_seg_apply_block(state, 0, 0, 1, 1, 0)
    assert_eq(state.seg_syntax_q_idx, 0)
    assert_false(state.seg_lossless)
    assert_false(av1_frame_coded_lossless(49, deltas, state.segmentation))
  }
}

///|
test "segment qindex respects feature enable clipping and no segmentation" {
  let params = av1_segment_quant_test_params([-255, -49, 0, 255, 0, 0, 0, 0])
  assert_eq(av1_segment_qindex(49, params, 0), 0)
  assert_eq(av1_segment_qindex(49, params, 1), 0)
  assert_eq(av1_segment_qindex(49, params, 2), 49)
  assert_eq(av1_segment_qindex(49, params, 3), 255)
  params.feature_enabled[1][av1_seg_level_alt_q] = false
  assert_eq(av1_segment_qindex(49, params, 1), 49)
  assert_eq(av1_segment_qindex(49, av1_segmentation_empty(), 0), 49)
  let state = av1_segment_quant_test_state(49, -49)
  state.sb_q_idx = 60
  av1_seg_apply_block(state, 0, 0, 1, 1, -1)
  assert_eq(state.seg_q_idx, 60)
  assert_eq(state.seg_syntax_q_idx, 49)
  assert_false(state.seg_lossless)
}

///|
/// Explicit reduced-still frame header. `lossless` chooses which syntax the
/// transcript actually contains, independently of the parser's derivation.
fn av1_segment_quant_test_header(
  base_q : Int,
  alt_q : Array[Int],
  lossless : Bool,
  y_dc? : Int = 0,
) -> Array[Byte] {
  let fields = [(0, 1), (0, 1), (0, 1), (1, 1), (base_q, 8)]
  fields.push((if y_dc == 0 { 0 } else { 1 }, 1))
  if y_dc != 0 {
    fields.push((y_dc & 127, 7))
  }
  fields.push((0, 1)) // U DC.
  fields.push((0, 1)) // U AC; V inherits U.
  fields.push((0, 1)) // using_qmatrix.
  fields.push((1, 1)) // segmentation_enabled; primary_ref is NONE.
  for id in 0..<8 {
    fields.push((1, 1)) // SEG_LVL_ALT_Q is enabled.
    fields.push((alt_q[id] & 511, 9))
    for _ in 1..<8 {
      fields.push((0, 1))
    }
  }
  if base_q > 0 {
    fields.push((0, 1))
  } // delta_q_present.
  if !lossless {
    fields.push((0, 6)) // LF Y vertical.
    fields.push((0, 6)) // LF Y horizontal; zero omits UV levels.
    fields.push((0, 3)) // LF sharpness.
    fields.push((0, 1)) // LF deltas disabled.
    fields.push((0, 2)) // CDEF damping=3.
    fields.push((0, 2)) // CDEF bits=0.
    fields.push((0, 12)) // Y and UV strengths.
    fields.push((0, 6)) // Three restoration NONE modes.
    fields.push((1, 1)) // TX_MODE_SELECT.
  }
  fields.push((1, 1)) // reduced_tx_set marker, present for lossless too.
  let payload = av1_cdef_header_test_pack(av1_cdef_header_test_bits(fields), 0)
  payload.push(b'\x71')
  payload
}

///|
test "all ALT_Q segments make nonzero-base header coded lossless" {
  let payload = av1_segment_quant_test_header(49, Array::make(8, -49), true)
  let frame = av1_parse_stage1_frame(
    payload,
    av1_cdef_header_test_sequence(true, enable_restoration=true),
  ).unwrap()
  assert_true(frame.coded_lossless)
  assert_false(frame.tx_mode_select)
  assert_true(frame.loop_filter is None)
  assert_true(frame.cdef is None)
  assert_true(frame.restoration is None)
  assert_true(frame.reduced_tx_set)
  assert_eq(frame.context_update_tile_id, 0)
  assert_eq(frame.header_bytes, payload.length() - 1)
  assert_eq(frame.tile_payload, [b'\x71'])
}

///|
test "any lossy segment retains filters and TX syntax even at frame base zero" {
  for id in 0..<8 {
    let deltas = Array::make(8, 0)
    deltas[id] = 1
    let payload = av1_segment_quant_test_header(0, deltas, false)
    let frame = av1_parse_stage1_frame(
      payload,
      av1_cdef_header_test_sequence(true, enable_restoration=true),
    ).unwrap()
    assert_false(frame.coded_lossless)
    assert_true(frame.tx_mode_select)
    assert_true(frame.loop_filter is Some(_))
    assert_true(frame.cdef is Some(_))
    assert_true(frame.restoration is Some(_))
    assert_true(frame.reduced_tx_set)
    assert_eq(frame.header_bytes, payload.length() - 1)
    assert_eq(frame.tile_payload, [b'\x71'])
  }
}

///|
test "zero nominal segment indices with nonzero quant delta retain header syntax" {
  let payload = av1_segment_quant_test_header(
    49,
    Array::make(8, -49),
    false,
    y_dc=1,
  )
  let frame = av1_parse_stage1_frame(
    payload,
    av1_cdef_header_test_sequence(true, enable_restoration=true),
  ).unwrap()
  assert_false(frame.coded_lossless)
  assert_true(frame.tx_mode_select)
  assert_true(frame.cdef is Some(_))
  assert_eq(frame.tile_payload, [b'\x71'])
}

///|
test "frame header retains nonzero context update tile and rejects absent tile" {
  let sequence = { ..av1_cdef_header_test_sequence(false), width: 192, }
  for tile in 0..<4 {
    let fields = [
      (0, 1),
      (0, 1),
      (0, 1), // CDF update, tools, render size.
      (1, 1),
      (1, 1),
      (1, 1), // Uniform tiles; log2(columns)=2, actual columns=3.
      (tile, 2),
      (0, 2), // context_update_tile_id, tile_size_bytes_minus_1.
      (0, 8),
      (0, 1),
      (0, 1),
      (0, 1), // qindex and quantization deltas.
      (0, 1),
      (0, 1),
      (1, 1), // qmatrix, segmentation, reduced_tx_set.
    ]
    let payload = av1_cdef_header_test_pack(
      av1_cdef_header_test_bits(fields),
      0,
    )
    payload.push(b'\x00') // tile_start_and_end_present_flag=0, byte alignment.
    payload.push(b'\x71')
    if tile < 3 {
      let frame = av1_parse_stage1_frame(payload, sequence).unwrap()
      assert_eq(frame.tile_cols, 3)
      assert_eq(frame.tile_rows, 1)
      assert_eq(frame.context_update_tile_id, tile)
      assert_eq(frame.tile_payload, [b'\x71'])
    } else {
      assert_true(av1_parse_stage1_frame(payload, sequence) is None)
    }
  }
}
