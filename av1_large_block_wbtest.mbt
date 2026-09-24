///|
test "128-axis coding block indices and transform limits match AV1 tables" {
  assert_eq(av1_intra_block_index(64, 128), Some(13))
  assert_eq(av1_intra_block_index(128, 64), Some(14))
  assert_eq(av1_intra_block_index(128, 128), Some(15))
  assert_eq(av1_intra_block_index(32, 128), None)
  assert_eq(av1_intra_block_index(128, 32), None)
  for size in [(64, 128), (128, 64), (128, 128)] {
    let (width, height) = size
    assert_eq(av1_tx_size_from_depth(width, height, 0), Some((64, 64)))
    assert_eq(av1_tx_size_from_depth(width, height, 1), Some((32, 32)))
    assert_eq(av1_tx_size_from_depth(width, height, 2), Some((16, 16)))
  }
}

///|
fn av1_large_block_test_payload(prefix : Array[Byte]) -> Array[Byte] {
  let payload = prefix.copy()
  for _ in 0..<8 {
    payload.push(b'\x00')
  }
  payload
}

///|
test "128-axis blocks cap transforms and omit palette syntax with screen tools" {
  // MSAC transcripts generated with scripts/craft_av1_fixture.py:
  // skip=1, Y=DC, UV=DC (color only), tx_depth=1 (SELECT only), marker=101.
  // No 128-axis block signals palette or filter-intra syntax, even with
  // screen-content tools enabled. Intra SELECT still signals depth on skip.
  for size in [(64, 128), (128, 64), (128, 128)] {
    let (width, height) = size
    for monochrome in [false, true] {
      for select in [false, true] {
        let prefix : Array[Byte] = if monochrome {
          if select {
            [b'\xf8', b'\xa8']
          } else {
            [b'\xfa', b'\x40']
          }
        } else if select {
          [b'\xf8', b'\x4c']
        } else {
          [b'\xf9', b'\x60']
        }
        let state = av1_intra_state(
          width,
          height,
          32,
          8,
          false,
          true,
          true,
          select,
          monochrome~,
        )
        let palette_before : Array[Array[Array[Int]]] = []
        for row in state.palette.y_mode {
          palette_before.push(row.map(cdf => cdf.copy()))
        }
        let filter_before : Array[Array[Int]] = []
        for row in state.filter_intra {
          filter_before.push(row.copy())
        }
        let decoder = av1_msac_new(av1_large_block_test_payload(prefix), true)
        assert_true(
          av1_intra_block(decoder, state, { row: 0, col: 0, width, height, }),
        )
        let expected_size = if select { 32 } else { 64 }
        assert_eq(
          state.tx_neighbors.above_width,
          Array::make(width / 4, expected_size),
        )
        assert_eq(
          state.tx_neighbors.left_height,
          Array::make(height / 4, expected_size),
        )
        for plane in state.planes {
          assert_eq(plane.pixels, Array::make(plane.width * plane.height, 128))
        }
        assert_eq(state.palette.y_mode, palette_before)
        assert_eq(state.palette.uv_mode, [[32461, 32768, 0], [21488, 32768, 0]])
        assert_eq(state.filter_intra, filter_before)
        assert_eq(state.tx_depth.cdf64[0][3], if select { 1 } else { 0 })
        assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
      }
    }
  }
}
///|
test "128-axis residual chunks retain full coding-plane skip contexts" {
  // Per chunk: Y64 all_zero(ctx1)=1, U32/V32 all_zero(ctx10)=1.
  // This is a non-skipped coding block: neither luma nor chroma transforms
  // cover the complete coding plane. A chunk-local whole flag would choose
  // Y ctx0 / UV ctx7 and read a different entropy stream.
  for size in [(64, 128), (128, 64), (128, 128)] {
    let (width, height) = size
    let state = av1_intra_state(
      width, height, 32, 8, false, false, false, false,
    )
    let decoder = av1_msac_new(av1_large_block_test_payload([b'\xb8']), true)
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: 0, col: 0, width, height, },
        AV1_INTRA_DC,
        AV1_INTRA_DC,
        64,
        64,
        0,
      ),
    )
    let chunks = width / 64 * (height / 64)
    assert_eq(state.tables.txb_skip[4][1][2], chunks)
    assert_eq(state.tables.txb_skip[3][10][2], chunks * 2)
    assert_eq(state.tables.txb_skip[4][0][2], 0)
    assert_eq(state.tables.txb_skip[3][7][2], 0)
    for plane in state.planes {
      assert_eq(plane.pixels, Array::make(plane.width * plane.height, 128))
    }
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
test "128-axis lossless block keeps four-pixel transform selection" {
  let state = av1_intra_state(
    128,
    128,
    0,
    10,
    false,
    true,
    true,
    true,
    monochrome=true,
  )
  let decoder = av1_msac_new(
    av1_large_block_test_payload([b'\xfa', b'\x40']),
    true,
  )
  assert_true(
    av1_intra_block(decoder, state, { row: 0, col: 0, width: 128, height: 128, }),
  )
  assert_eq(state.tx_neighbors.above_width, Array::make(32, 4))
  assert_eq(state.tx_neighbors.left_height, Array::make(32, 4))
  assert_eq(state.planes[0].pixels, Array::make(128 * 128, 512))
  assert_eq(state.tx_depth.cdf64[0][3], 0)
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}
