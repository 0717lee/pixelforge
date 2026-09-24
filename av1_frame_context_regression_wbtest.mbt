///|
fn av1_context_test_key() -> (
  Av1SequenceInfo,
  Av1FrameHeaderInfo,
  Av1FramePlanes,
) {
  let key = av1_inter_slice_bytes(inter_minimal_64x64_obu, 0, 69)
  let sequence = av1_sequence_info(key).unwrap()
  let header = av1_parse_stage1_frame(
    av1_obu_payloads(key, 6)[0],
    sequence,
    map=av1_frame_map(),
  ).unwrap()
  (sequence, header, av1_decode_frame_planes(key).unwrap())
}

///|
test "disabled frame end keeps the selected older primary context" {
  let (sequence, key, frame) = av1_context_test_key()
  let map = av1_frame_map()
  let context_a = av1_frame_cdfs_default(49)
  let context_b = av1_frame_cdfs_default(128)
  context_a.tables[av1_cdf_partition_count][0][0] = 12345
  context_b.tables[av1_cdf_partition_count][0][0] = 23456
  av1_frame_map_update(
    map,
    { ..key, refresh_frame_flags: 1, disable_frame_end_update_cdf: false, },
    frame,
    sequence,
    cdfs=Some(context_a),
  )
  av1_frame_map_update(
    map,
    { ..key, refresh_frame_flags: 2, disable_frame_end_update_cdf: false, },
    frame,
    sequence,
    cdfs=Some(context_b),
  )
  assert_eq(map.saved_cdfs.unwrap().tables, context_b.tables)
  let frame_c : Av1FrameHeaderInfo = {
    ..key,
    frame_type: av1_inter_frame,
    frame_is_intra: false,
    base_q_idx: 128,
    primary_ref_frame: 0,
    ref_frame_idx: [0, 1, 1, 1, 1, 1, 1],
    refresh_frame_flags: 4,
    disable_frame_end_update_cdf: true,
  }
  av1_frame_map_update(map, frame_c, frame, sequence, cdfs=Some(context_b))
  assert_eq(map.slots[2].unwrap().cdfs.unwrap().tables, context_a.tables)
  assert_eq(map.saved_cdfs.unwrap().tables, context_a.tables)
  assert_eq(map.slots[1].unwrap().cdfs.unwrap().tables, context_b.tables)
  // Mutating a tile's working copy must not change an older reference slot.
  let inherited = av1_frame_initial_cdfs(map, frame_c)
  inherited.tables[av1_cdf_partition_count][0][0] = 30000
  assert_eq(map.slots[0].unwrap().cdfs.unwrap().tables, context_a.tables)
}

///|
test "disabled key frame freezes its quantizer category defaults" {
  let (sequence, key, frame) = av1_context_test_key()
  let map = av1_frame_map()
  let unrelated = av1_frame_cdfs_default(128)
  unrelated.tables[av1_cdf_partition_count][0][0] = 23456
  av1_frame_map_update(
    map,
    { ..key, refresh_frame_flags: 1, disable_frame_end_update_cdf: false, },
    frame,
    sequence,
    cdfs=Some(unrelated),
  )
  let frozen_key : Av1FrameHeaderInfo = {
    ..key,
    base_q_idx: 49,
    primary_ref_frame: av1_primary_ref_none,
    refresh_frame_flags: 2,
    disable_frame_end_update_cdf: true,
  }
  av1_frame_map_update(map, frozen_key, frame, sequence, cdfs=Some(unrelated))
  let expected = av1_frame_cdfs_default(49)
  assert_true(expected.tables != av1_frame_cdfs_default(128).tables)
  assert_eq(map.slots[1].unwrap().cdfs.unwrap().tables, expected.tables)
  let next : Av1FrameHeaderInfo = {
    ..key,
    base_q_idx: 128,
    frame_type: av1_inter_frame,
    frame_is_intra: false,
    primary_ref_frame: 0,
    ref_frame_idx: [1, 1, 1, 1, 1, 1, 1],
  }
  assert_eq(av1_frame_initial_cdfs(map, next).tables, expected.tables)
  assert_eq(map.saved_cdfs.unwrap().tables, expected.tables)
}

///|
fn av1_context_test_tiles(
  header : Av1FrameHeaderInfo,
  sequence : Av1SequenceInfo,
  payload : Array[Byte],
  starts : Array[Int],
  size_bytes : Int,
  update_tile : Int,
) -> (Av1FramePlanes, Av1RestorationStripeStore?, Av1FrameCdfs?)? {
  let sink : Array[Av1FrameCdfs?] = []
  av1_decode_tile_planes(
    starts[starts.length() - 1],
    header.frame_height,
    starts,
    [0, header.frame_height],
    payload,
    size_bytes,
    header.base_q_idx,
    header.disable_cdf_update,
    header.allow_screen_content_tools,
    sequence.full_range,
    sequence.matrix_coefficients,
    sequence.use_128x128_superblock,
    sequence.bit_depth,
    header.reduced_tx_set,
    sequence.enable_filter_intra,
    header.tx_mode_select,
    header.cdef,
    monochrome=sequence.monochrome,
    loop_filter=header.loop_filter,
    context_update_tile_id=update_tile,
    cdfs_out=Some(sink),
  )
}

///|
test "a nonzero context update tile selects that tile's adapted rows" {
  // The first tile is the unchanged 64-valued tile from the aomenc fixture
  // tests/fixtures/av1-multitile/tiles2x1_8bit_q10.obu. Tile 1 is replaced
  // with the neutral skip tile already used by the tile-boundary tests. The
  // OBU size is shortened and context_update_tile_id is set to 1. Distinct
  // residual/skip paths make selecting the wrong snapshot observable.
  // Independent FFmpeg 9.0.1 / libdav1d 1.5.4 decoding of these exact bytes
  // produced 12,288 yuv420p bytes: every left-tile Y sample is 64, every
  // right-tile Y sample is 128. Those constants are asserted below in addition
  // to comparing the joined frame with separately decoded tiles.
  let obu : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x19', b'\x7F', b'\xFE', b'\x00',
    b'\x04', b'\x32', b'\x0E', b'\x1C', b'\x28', b'\x00', b'\x00', b'\x04', b'\x00',
    b'\x00', b'\x04', b'\x00', b'\xEB', b'\xC8', b'\xE2', b'\x40', b'\x2E',
  ]
  let sequence = av1_sequence_info(obu).unwrap()
  let header = av1_parse_stage1_frame(av1_obu_payloads(obu, 6)[0], sequence).unwrap()
  assert_eq(header.context_update_tile_id, 1)
  assert_eq(header.tile_cols, 2)
  let tiles = av1_extract_tile_payloads(
    header.tile_payload,
    2,
    1,
    header.tile_size_bytes,
  ).unwrap()
  let (first, _, first_cdfs) = av1_context_test_tiles(
    header,
    sequence,
    tiles[0].bytes,
    [0, 64],
    0,
    0,
  ).unwrap()
  let (second, _, second_cdfs) = av1_context_test_tiles(
    header,
    sequence,
    tiles[1].bytes,
    [0, 64],
    0,
    0,
  ).unwrap()
  assert_true(first_cdfs.unwrap().tables != second_cdfs.unwrap().tables)
  let (joined, _, captured) = av1_context_test_tiles(
    header,
    sequence,
    header.tile_payload,
    [0, 64, 128],
    header.tile_size_bytes,
    header.context_update_tile_id,
  ).unwrap()
  assert_eq(captured.unwrap().tables, second_cdfs.unwrap().tables)
  for row in 0..<64 {
    for col in 0..<64 {
      assert_eq(joined.planes[0][row * 128 + col], 64)
      assert_eq(joined.planes[0][row * 128 + 64 + col], 128)
      assert_eq(
        joined.planes[0][row * 128 + col],
        first.planes[0][row * 64 + col],
      )
      assert_eq(
        joined.planes[0][row * 128 + 64 + col],
        second.planes[0][row * 64 + col],
      )
    }
  }
  let (_, _, captured_first) = av1_context_test_tiles(
    header,
    sequence,
    header.tile_payload,
    [0, 64, 128],
    header.tile_size_bytes,
    0,
  ).unwrap()
  assert_eq(captured_first.unwrap().tables, first_cdfs.unwrap().tables)
  for invalid in [-1, 2] {
    assert_true(
      av1_context_test_tiles(
        header,
        sequence,
        header.tile_payload,
        [0, 64, 128],
        header.tile_size_bytes,
        invalid,
      )
      is None,
    )
  }
}
