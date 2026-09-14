///|
fn av1_filter_intra_test_payload(prefix : Array[Byte]) -> Array[Byte] {
  let bytes = prefix.copy()
  for _ in 0..<8 {
    bytes.push(b'\x00')
  }
  bytes
}

///|
test "filter intra shares its adaptive mode CDF and resets each coding block" {
  // Three skipped 8x8 blocks: FILTER_PAETH, FILTER_V, disabled, then 101.
  let decoder = av1_msac_new(
    av1_filter_intra_test_payload([b'\xf8', b'\xb8', b'\x62', b'\xe8']),
    true,
  )
  let state = av1_intra_state(24, 8, 32, 8, false, false, true, false)
  for i in 0..<3 {
    assert_true(
      av1_intra_block(decoder, state, {
        row: 0,
        col: i * 8,
        width: 8,
        height: 8,
      }),
    )
    assert_eq(state.filter_intra_mode, [4, 1, -1][i])
    assert_eq(state.filter_intra_mode_cdf[5], if i == 0 { 1 } else { 2 })
    assert_eq(state.filter_intra[3][2], i + 1)
  }
  assert_eq(state.y_modes, Array::make(12, AV1_INTRA_DC))
  assert_eq(state.uv_modes, Array::make(12, AV1_INTRA_DC))
  // The Y filter mode never overrides UV's raw DC predictor.
  assert_eq(state.planes[1].pixels, Array::make(48, 128))
  assert_eq(state.planes[2].pixels, Array::make(48, 128))
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}

///|
test "filter intra use syntax follows sequence mode size and lossless gates" {
  let prefixes = [
    [b'\xfa', b'\xd0'], // lossless, skip1, DC, use1, FILTER_D157.
    [b'\xfa', b'\x40'], // sequence disabled: no use bit.
    [b'\xfb', b'\xbe'], // V with zero angle delta: no use bit.
    [b'\xfa', b'\x40'], // 64x16 DC: no use bit.
    [b'\xf8', b'\x18'], // use0 clears the previous selection.
  ]
  for i in 0..<5 {
    let width = if i == 3 { 64 } else { 8 }
    let height = if i == 3 { 16 } else { 8 }
    let state = av1_intra_state(
      width,
      height,
      if i == 0 {
        0
      } else {
        32
      },
      8,
      false,
      false,
      i != 1,
      false,
      monochrome=true,
      track_loop_filter=true,
    )
    state.filter_intra_mode = 4
    let decoder = av1_msac_new(av1_filter_intra_test_payload(prefixes[i]), true)
    assert_true(
      av1_intra_block(decoder, state, { row: 0, col: 0, width, height, }),
    )
    assert_eq(state.filter_intra_mode, if i == 0 { 3 } else { -1 })
    assert_eq(state.filter_intra_mode_cdf[5], if i == 0 { 1 } else { 0 })
    if i == 0 {
      assert_eq(state.planes[0].tx_sizes, Array::make(4, 4 | (4 << 8)))
    }
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
test "filter intra syntax is absent for a decoded luma palette" {
  let state = av1_intra_state(
    8,
    8,
    32,
    8,
    false,
    true,
    true,
    false,
    monochrome=true,
  )
  state.filter_intra_mode = 4
  // skip1, DC, palette2 [24,224], full 8x8 map, then 101.
  // Generated and replayed using PaletteConstruction.block/PaletteTrace.block
  // from scripts/generate-av1-palette-reference.py; no FI use bit is present.
  let decoder = av1_msac_new(
    av1_filter_intra_test_payload([
      b'\xfb', b'\x68', b'\x30', b'\xf2', b'\xa4', b'\xef', b'\xff', b'\xf9', b'\xa6',
      b'\x29', b'\x8c', b'\xff', b'\xd6',
    ]),
    true,
  )
  assert_true(
    av1_intra_block(decoder, state, { row: 0, col: 0, width: 8, height: 8, }),
  )
  assert_eq(state.palette.y_colors, [24, 224])
  assert_eq(
    state.planes[0].pixels,
    Array::makei(64, i => {
      let x = i % 8
      let y = i / 8
      if (x * 3 + y * 5 + x / 3 * (y / 2)) % 2 == 0 {
        24
      } else {
        224
      }
    }),
  )
  assert_eq(state.filter_intra_mode, -1)
  assert_eq(state.filter_intra_mode_cdf[5], 0)
  assert_eq(state.filter_intra[3][2], 0)
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}
///|
test "filter intra remaps only luma transform CDF context" {
  let encoded = [b'\x4c', b'\x34', b'\x2a', b'\x1e', b'\x4c']
  let directions = [0, 1, 2, 6, 0]
  for mode in 0..<5 {
    let state = av1_intra_state(8, 8, 32, 8, false, false, true, false)
    state.filter_intra_mode = mode
    let decoder = av1_msac_new(
      av1_filter_intra_test_payload([encoded[mode]]),
      true,
    )
    assert_true(
      av1_intra_tx_type(decoder, state, 8, 8, AV1_INTRA_DC) is Some(Av1TxDctDct),
    )
    for direction in 0..<13 {
      assert_eq(
        state.tables.tx_set1[1][direction][7],
        if direction == directions[mode] {
          1
        } else {
          0
        },
      )
    }
    assert_eq(state.y_modes, Array::make(4, AV1_INTRA_DC))
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
/// Pinned original C FILTER_PAETH runs once per TX4x4, with its original
/// iwht4x4_1_add applying dequantized DC=8 to the first TX before the next
/// predictor reads its edge. Two samples clip at 255. Delaying that residual
/// changes five output samples, including three in the following TX.
test "filter intra reads reconstructed clipped neighbors for each Y transform" {
  let expected = [
    255, 255, 246, 249, 251, 253, 255, 244, 245, 248, 239, 242, 245, 247, 250, 241,
    249, 251, 243, 245, 247, 249, 251, 243, 253, 254, 247, 248, 250, 250, 252, 245,
    243, 246, 240, 242, 245, 245, 247, 242, 248, 249, 243, 245, 247, 247, 249, 244,
    252, 252, 247, 248, 249, 249, 251, 246, 242, 244, 240, 242, 244, 244, 246, 243,
  ]
  for enable_intra_edge_filter in [false, true] {
    let state = av1_intra_state(
      16,
      16,
      0,
      8,
      false,
      false,
      true,
      false,
      monochrome=true,
      enable_intra_edge_filter~,
    )
    state.filter_intra_mode = 4
    state.y_angle_delta = 3
    for y in 0..<16 {
      for x in 0..<16 {
        state.planes[0].pixels[y * 16 + x] = 240 + (x * 3 + y * 5) % 16
      }
    }
    // Nonzero DC=2, followed by three all-zero TX symbols, then 101.
    let decoder = av1_msac_new(
      av1_filter_intra_test_payload([b'\x01', b'\x05']),
      true,
    )
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: 8, col: 8, width: 8, height: 8, },
        AV1_INTRA_DC,
        AV1_INTRA_DC,
        4,
        4,
        0,
      ),
    )
    let actual = Array::makei(64, i => {
      state.planes[0].pixels[(8 + i / 8) * 16 + 8 + i % 8]
    })
    assert_eq(actual, expected)
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
test "filter intra complete luma reconstruction supplies CfL chroma" {
  let state = av1_intra_state(8, 8, 32, 8, false, false, true, false)
  // skip1, Y=DC, UV=CfL, alpha U=V=+16, FILTER_V, then 101.
  let decoder = av1_msac_new(
    av1_filter_intra_test_payload([b'\xfb', b'\x89', b'\xff', b'\xf8', b'\x10']),
    true,
  )
  assert_true(
    av1_intra_block(decoder, state, { row: 0, col: 0, width: 8, height: 8, }),
  )
  assert_eq(state.filter_intra_mode, 1)
  assert_eq(state.y_modes, Array::make(4, AV1_INTRA_DC))
  assert_eq(state.uv_modes, Array::make(4, AV1_INTRA_CFL))
  assert_eq((state.cfl.alpha_u, state.cfl.alpha_v), (16, 16))
  assert_eq(state.planes[1].pixels, state.planes[2].pixels)
  let mut varies = false
  for value in state.planes[1].pixels {
    if value != 128 {
      varies = true
    }
  }
  assert_true(varies)
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}
