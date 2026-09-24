///|
test "monochrome tile state keeps only native depth luma geometry" {
  for bit_depth in [8, 10, 12] {
    for width in [8, 16, 32, 64] {
      let height = 24
      let state = av1_intra_state(
        width,
        height,
        32,
        bit_depth,
        false,
        false,
        false,
        false,
        monochrome=true,
      )
      assert_true(state.monochrome)
      assert_eq(state.planes.length(), 1)
      assert_eq(
        (state.planes[0].width, state.planes[0].height),
        (width, height),
      )
      assert_eq(
        state.planes[0].pixels,
        Array::make(width * height, 1 << (bit_depth - 1)),
      )
      assert_eq(state.planes[0].above_level.length(), width / 4)
      assert_eq(state.planes[0].left_level.length(), height / 4)
      assert_eq(state.skips.length(), width / 4 * (height / 4))
      assert_eq(state.cdef_indices, [-1])
    }
  }
}

///|
test "color tile state keeps the existing three plane default" {
  let state = av1_intra_state(64, 32, 32, 10, false, false, false, false)
  assert_false(state.monochrome)
  assert_eq(state.planes.length(), 3)
  assert_eq((state.planes[0].width, state.planes[0].height), (64, 32))
  for plane in 1..<3 {
    assert_eq((state.planes[plane].width, state.planes[plane].height), (32, 16))
    assert_eq(state.planes[plane].pixels, Array::make(32 * 16, 512))
  }
}

///|
test "monochrome skipped blocks omit UV syntax and retain luma syntax" {
  // od_ec transcripts from scripts/craft_av1_fixture.py::MsacEncoder:
  // skip=1, y_mode=DC, palette_y=0, filter_intra=0 (only <=32), then
  // the independent boolean marker 1,0,1. There is no UV mode or palette.
  let transcripts : Array[(Int, Array[Byte])] = [
    (8, [b'\xf8', b'\x18']),
    (16, [b'\xf8', b'\x70']),
    (32, [b'\xf9', b'\x60']),
    (64, [b'\xfa', b'\x40']),
  ]
  for transcript in transcripts {
    let (side, prefix) = transcript
    let payload = prefix.copy()
    for _ in 0..<8 {
      payload.push(b'\x00')
    }
    let state = av1_intra_state(
      side,
      side,
      32,
      8,
      false,
      true,
      true,
      false,
      monochrome=true,
    )
    let decoder = av1_msac_new(payload, true)
    assert_true(
      av1_intra_block(decoder, state, {
        row: 0,
        col: 0,
        width: side,
        height: side,
      }),
    )
    assert_eq(state.planes.length(), 1)
    assert_eq(state.planes[0].pixels, Array::make(side * side, 128))
    assert_eq(state.skips, Array::make(side / 4 * (side / 4), 1))
    assert_eq(state.y_modes, Array::make(side / 4 * (side / 4), AV1_INTRA_DC))
    assert_eq(state.uv_cfl, av1_intra_uv_mode_cdfs(true))
    assert_eq(state.uv_no_cfl, av1_intra_uv_mode_cdfs(false))
    assert_eq(state.palette.uv_mode, [[32461, 32768, 0], [21488, 32768, 0]])
    let palette_context = 2 * av1_msac_floor_log2(side / 4) - 2
    assert_eq(state.palette.y_mode[palette_context][0][2], 1)
    if side <= 32 {
      let block_index = av1_intra_block_index(side, side).unwrap()
      assert_eq(state.filter_intra[block_index][2], 1)
    }
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
fn av1_monochrome_test_tile(
  cdef : Av1CdefConfig?,
  base_q_idx? : Int = 32,
) -> Av1IntraState? {
  // Frame 8x8 forces the 64/32/16 partition splits. The one 8x8 partition
  // is NONE followed by the skipped DC block transcript used above.
  av1_decode_intra_tile_state(
    8,
    8,
    [
      b'\x90', b'\xd8', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
      b'\x00',
    ],
    base_q_idx,
    false,
    true,
    false,
    8,
    false,
    true,
    false,
    cdef~,
    monochrome=true,
  )
}

///|
test "monochrome tile entry validates CDEF shape and keeps lossless gate" {
  let mono : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [4],
    y_secondary: [1],
    uv_primary: [],
    uv_secondary: [],
  }
  let color : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [4],
    y_secondary: [1],
    uv_primary: [2],
    uv_secondary: [1],
  }
  let state = av1_monochrome_test_tile(Some(mono)).unwrap()
  assert_true(state.monochrome)
  assert_eq(state.planes.length(), 1)
  assert_eq(state.planes[0].pixels, Array::make(64, 128))
  assert_eq(state.cdef_indices, [-1])
  assert_true(av1_monochrome_test_tile(Some(color)) is None)
  assert_true(av1_monochrome_test_tile(Some(mono), base_q_idx=0) is None)
  assert_true(av1_monochrome_test_tile(None, base_q_idx=0) is Some(_))
}
