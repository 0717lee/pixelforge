/// CDEF index transcripts use a real MSAC input. 0x9c followed by zeros
/// yields boolean symbols 1,0,0,1,1,1,0; 0xa0 yields 1,0,1,0,0,0,0.
/// Decoder snapshots assert that implied or reused indices consume nothing.

///|
fn av1_cdef_index_test_config(bits : Int) -> Av1CdefConfig {
  let count = 1 << bits
  {
    bits,
    damping: 3,
    y_primary: Array::make(count, 4),
    y_secondary: Array::make(count, 1),
    uv_primary: Array::make(count, 2),
    uv_secondary: Array::make(count, 1),
  }
}

///|
fn av1_cdef_index_test_state(
  width : Int,
  height : Int,
  cdef : Av1CdefConfig?,
) -> Av1IntraState {
  av1_intra_state(width, height, 32, 8, false, false, false, false, cdef~)
}

///|
fn av1_cdef_index_test_reader(first : Byte) -> Av1SymbolDecoder {
  av1_msac_new(
    [first, b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'],
    true,
  )
}

///|
fn av1_cdef_index_test_snapshot(decoder : Av1SymbolDecoder) -> Array[Int] {
  [
    decoder.bit_pos,
    decoder.symbol_value,
    decoder.symbol_range,
    decoder.symbol_max_bits,
  ]
}

///|
test "CDEF absent configuration leaves indices and entropy untouched" {
  let state = av1_cdef_index_test_state(64, 64, None)
  let decoder = av1_cdef_index_test_reader(b'\x9c')
  let before = av1_cdef_index_test_snapshot(decoder)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 0, col: 0, width: 16, height: 16, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [-1])
  assert_eq(av1_cdef_index_test_snapshot(decoder), before)
  assert_true(decoder.allow_update)
  assert_eq(decoder.bool(), 1)
}

///|
test "CDEF skipped blocks preserve the first non-skip index syntax" {
  let state = av1_cdef_index_test_state(
    64,
    64,
    Some(av1_cdef_index_test_config(3)),
  )
  let decoder = av1_cdef_index_test_reader(b'\x9c')
  let before = av1_cdef_index_test_snapshot(decoder)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 0, col: 0, width: 16, height: 16, },
      1,
    ),
  )
  assert_eq(state.cdef_indices, [-1])
  assert_eq(av1_cdef_index_test_snapshot(decoder), before)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 0, col: 16, width: 16, height: 16, },
      0,
    ),
  )
  // 1,0,0 is the MSB-first three-bit strength index 4, not 1.
  assert_eq(state.cdef_indices, [4])
  let control = av1_cdef_index_test_reader(b'\x9c')
  assert_eq([control.bool(), control.bool(), control.bool()], [1, 0, 0])
  assert_eq(
    av1_cdef_index_test_snapshot(decoder),
    av1_cdef_index_test_snapshot(control),
  )
  assert_true(decoder.allow_update)
  assert_eq(decoder.bool(), 1)
}

///|
test "CDEF zero index bits imply strength zero without consuming entropy" {
  let state = av1_cdef_index_test_state(
    64,
    64,
    Some(av1_cdef_index_test_config(0)),
  )
  let decoder = av1_cdef_index_test_reader(b'\x9c')
  let before = av1_cdef_index_test_snapshot(decoder)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 8, col: 8, width: 8, height: 8, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [0])
  assert_eq(av1_cdef_index_test_snapshot(decoder), before)
}

///|
test "CDEF later blocks reuse a region index without another literal" {
  let state = av1_cdef_index_test_state(
    64,
    64,
    Some(av1_cdef_index_test_config(2)),
  )
  let decoder = av1_cdef_index_test_reader(b'\x9c')
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 0, col: 0, width: 8, height: 8, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [2])
  let after_first = av1_cdef_index_test_snapshot(decoder)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 8, col: 24, width: 8, height: 8, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [2])
  assert_eq(av1_cdef_index_test_snapshot(decoder), after_first)
  assert_eq(decoder.bool(), 0)
}

///|
test "CDEF indices have independent state for each partial 64 pixel region" {
  let state = av1_cdef_index_test_state(
    136,
    72,
    Some(av1_cdef_index_test_config(2)),
  )
  let decoder = av1_cdef_index_test_reader(b'\x9c')
  assert_eq(state.cdef_indices, [-1, -1, -1, -1, -1, -1])
  let blocks : Array[Av1SbBlock] = [
    { row: 0, col: 0, width: 8, height: 8, },
    { row: 0, col: 64, width: 8, height: 8, },
    { row: 64, col: 128, width: 8, height: 8, },
  ]
  for block in blocks {
    assert_true(av1_intra_cdef_index(decoder, state, block, 0))
  }
  // Three consecutive two-bit literals from 1,0,0,1,1,1.
  assert_eq(state.cdef_indices, [2, 1, -1, -1, -1, 3])
  assert_eq(decoder.bool(), 0)
}

///|
test "CDEF 128 pixel coding blocks propagate one literal over their footprint" {
  let state = av1_cdef_index_test_state(
    192,
    192,
    Some(av1_cdef_index_test_config(3)),
  )
  let decoder = av1_cdef_index_test_reader(b'\xa0')
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 0, col: 0, width: 128, height: 128, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [5, 5, -1, 5, 5, -1, -1, -1, -1])
  let after_first = av1_cdef_index_test_snapshot(decoder)
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 64, col: 64, width: 16, height: 16, },
      0,
    ),
  )
  assert_eq(av1_cdef_index_test_snapshot(decoder), after_first)
  // A coded footprint may extend beyond the frame's MI-padded rectangle.
  assert_true(
    av1_intra_cdef_index(
      decoder,
      state,
      { row: 128, col: 128, width: 128, height: 128, },
      0,
    ),
  )
  assert_eq(state.cdef_indices, [5, 5, -1, 5, 5, -1, -1, -1, 0])
  assert_eq(decoder.bool(), 0)
}
