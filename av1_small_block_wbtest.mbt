///|
test "four-axis coding blocks use AV1 indices and shared chroma ownership" {
  let state = av1_intra_state(32, 32, 32, 8, false, false, false, false)
  let mono = av1_intra_state(
    32,
    32,
    32,
    8,
    false,
    false,
    false,
    false,
    monochrome=true,
  )
  for geometry in [(4, 4, 0), (4, 8, 1), (8, 4, 2), (4, 16, 16), (16, 4, 17)] {
    let (width, height, index) = geometry
    assert_eq(av1_intra_block_index(width, height), Some(index))
    for y4 in 0..<2 {
      for x4 in 0..<2 {
        let block : Av1SbBlock = { row: y4 * 4, col: x4 * 4, width, height, }
        let owns_uv = (width >= 8 || x4 == 1) && (height >= 8 || y4 == 1)
        assert_eq(av1_intra_has_chroma(state, block), owns_uv)
        assert_false(av1_intra_has_chroma(mono, block))
      }
    }
  }
}

///|
fn av1_small_block_test_payload(prefix : Array[Byte]) -> Array[Byte] {
  let payload = prefix.copy()
  for _ in 0..<8 {
    payload.push(b'\x00')
  }
  payload
}

///|
test "four-axis owners reconstruct expanded UV at aligned eight-pixel origins" {
  for
    geometry in [
      (4, 4, 4, 4),
      (4, 8, 4, 0),
      (8, 4, 0, 4),
      (4, 16, 4, 0),
      (16, 4, 0, 4),
    ] {
    let (width, height, x, y) = geometry
    let state = av1_intra_state(16, 16, 32, 8, false, false, false, false)
    for plane in 1..<3 {
      for i in 0..<state.planes[plane].pixels.length() {
        state.planes[plane].pixels[i] = 200
      }
    }
    let decoder = av1_msac_new(av1_small_block_test_payload([b'\x9c']), true)
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: y, col: x, width, height, },
        AV1_INTRA_DC,
        AV1_INTRA_V,
        width,
        height,
        1,
      ),
    )
    let uv_width = if width < 8 { 4 } else { width / 2 }
    let uv_height = if height < 8 { 4 } else { height / 2 }
    for plane in 1..<3 {
      for row in 0..<8 {
        for col in 0..<8 {
          let expected = if row < uv_height && col < uv_width {
            127
          } else {
            200
          }
          assert_eq(
            (plane, col, row, state.planes[plane].pixels[row * 8 + col]),
            (plane, col, row, expected),
          )
        }
      }
    }
    // A skipped residual has no entropy syntax on any of its planes.
    assert_eq(decoder.bool(), 1)
  }
  for position in [(0, 0), (4, 0), (0, 4)] {
    let (x, y) = position
    let state = av1_intra_state(8, 8, 32, 8, false, false, false, false)
    for plane in 1..<3 {
      for i in 0..<16 {
        state.planes[plane].pixels[i] = 200
      }
    }
    let decoder = av1_msac_new(av1_small_block_test_payload([b'\x9c']), true)
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: y, col: x, width: 4, height: 4, },
        AV1_INTRA_DC,
        AV1_INTRA_V,
        4,
        4,
        1,
      ),
    )
    assert_eq(state.planes[1].pixels, Array::make(16, 200))
    assert_eq(state.planes[2].pixels, Array::make(16, 200))
  }
}

///|
test "four-axis angle syntax distinguishes basic and extended BLOCK indices" {
  for mode in [AV1_INTRA_V, AV1_INTRA_H] {
    for index in [0, 1, 2] {
      let state = av1_intra_state(16, 16, 32, 8, false, false, false, false)
      let decoder = av1_msac_new(av1_small_block_test_payload([b'\x9c']), true)
      let before = [
        decoder.bit_pos,
        decoder.symbol_value,
        decoder.symbol_range,
        decoder.symbol_max_bits,
      ]
      assert_true(av1_intra_read_mode_angle(decoder, state, mode, index))
      assert_eq(
        [
          decoder.bit_pos,
          decoder.symbol_value,
          decoder.symbol_range,
          decoder.symbol_max_bits,
        ],
        before,
      )
    }
    for index in [16, 17] {
      let state = av1_intra_state(16, 16, 32, 8, false, false, false, false)
      let prefix = if mode == AV1_INTRA_V { b'\x8c' } else { b'\x94' }
      let decoder = av1_msac_new(av1_small_block_test_payload([prefix]), true)
      assert_true(av1_intra_read_mode_angle(decoder, state, mode, index))
      assert_eq(state.angle_delta[mode - 1][7], 1)
      assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
    }
  }
}

///|
test "four-axis owner mode syntax retains filter palette lossless and SELECT gates" {
  // Independent od_ec transcripts: skip=1, Y/UV=DC, palette flags=0 for
  // extended blocks, filter_intra=0, maximal SELECT depth (unless lossless),
  // and the following boolean marker 101. CfL is an alphabet selection here;
  // the decoded UV mode remains DC.
  let shapes = [
    (4, 4, 4, 4, 0),
    (4, 8, 4, 0, 1),
    (8, 4, 0, 4, 2),
    (4, 16, 4, 0, 16),
    (16, 4, 0, 4, 17),
  ]
  let lossless_prefixes : Array[Array[Byte]] = [
    [b'\xf7', b'\x9a'],
    [b'\xf7', b'\xa4'],
    [b'\xf7', b'\xa2'],
    [b'\xf8', b'\x30'],
    [b'\xf8', b'\x08'],
  ]
  let lossy_prefixes : Array[Array[Byte]] = [
    [b'\xf7', b'\x9a'],
    [b'\xf7', b'\xb5'],
    [b'\xf7', b'\xad'],
    [b'\xf7', b'\xf2', b'\x80'],
    [b'\xf7', b'\xdb', b'\x40'],
  ]
  for q in [0, 32] {
    for i in 0..<shapes.length() {
      let (width, height, x, y, index) = shapes[i]
      let prefix = if q == 0 { lossless_prefixes[i] } else { lossy_prefixes[i] }
      let state = av1_intra_state(32, 32, q, 8, false, true, true, true)
      let decoder = av1_msac_new(av1_small_block_test_payload(prefix), true)
      assert_true(
        av1_intra_block(decoder, state, { row: y, col: x, width, height, }),
      )
      assert_eq(state.filter_intra[index][2], 1)
      assert_eq(state.palette.y_mode[0][0][2], if index >= 3 { 1 } else { 0 })
      assert_eq(state.palette.uv_mode[0][2], if index >= 3 { 1 } else { 0 })
      let cfl_allowed = q != 0 || (width <= 8 && height <= 8)
      let cfl = state.uv_cfl[0]
      let no_cfl = state.uv_no_cfl[0]
      assert_eq(cfl[cfl.length() - 1], if cfl_allowed { 1 } else { 0 })
      assert_eq(no_cfl[no_cfl.length() - 1], if cfl_allowed { 0 } else { 1 })
      assert_eq(
        state.tx_depth.cdf8[0][2],
        if q != 0 && (index == 1 || index == 2) {
          1
        } else {
          0
        },
      )
      assert_eq(
        state.tx_depth.cdf16[0][3],
        if q != 0 && index >= 16 {
          1
        } else {
          0
        },
      )
      assert_eq(state.tx_neighbors.above_width[x / 4], 4)
      assert_eq(state.tx_neighbors.left_height[y / 4], 4)
      assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
    }
  }
}
