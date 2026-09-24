///|
fn av1_cfl_test_payload(prefix : Array[Byte]) -> Array[Byte] {
  let payload = prefix.copy()
  for _ in 0..<8 {
    payload.push(b'\x00')
  }
  payload
}

///|
test "CfL signed scaling rounds half ties away from zero" {
  for pair in [(31, 0), (32, 1), (33, 1), (95, 1), (96, 2), (97, 2)] {
    let (sample, expected) = pair
    assert_eq(av1_cfl_scaled_luma(1, sample), expected)
    assert_eq(av1_cfl_scaled_luma(1, -sample), -expected)
    assert_eq(av1_cfl_scaled_luma(-1, sample), -expected)
    assert_eq(av1_cfl_scaled_luma(-1, -sample), expected)
  }
  assert_eq(av1_cfl_scaled_luma(3, 32), 2)
  assert_eq(av1_cfl_scaled_luma(3, -32), -2)
  assert_eq(av1_cfl_scaled_luma(0, 32760), 0)
  assert_eq(av1_cfl_scaled_luma(16, 32760), 8190)
}

///|
test "CfL joint signs share adaptive alpha rows across planes and blocks" {
  // od_ec transcript covers all eight joint signs, including both planes
  // consecutively using row1 (both negative) and row5 (both positive).
  let decoder = av1_msac_new(
    av1_cfl_test_payload([
      b'\x79', b'\xac', b'\xbf', b'\xef', b'\x4d', b'\x19', b'\x71', b'\x75', b'\x40',
      b'\xfe', b'\x08', b'\x10', b'\x30',
    ]),
    true,
  )
  let cfl = av1_cfl_state()
  for
    expected in [
      (-1, -16),
      (16, 1),
      (0, -5),
      (3, 0),
      (-4, 0),
      (0, 2),
      (-9, 3),
      (2, -5),
    ] {
    assert_true(av1_cfl_read_alphas(decoder, cfl))
    assert_eq((cfl.alpha_u, cfl.alpha_v), expected)
  }
  assert_eq(cfl.sign[8], 8)
  for row in cfl.alpha {
    assert_eq(row[16], 2)
  }
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  let fresh = av1_cfl_state()
  assert_eq(fresh.sign[8], 0)
  for row in fresh.alpha {
    assert_eq(row[16], 0)
  }
}

///|
test "CfL pads fractional Q3 samples before subtracting the rounded mean" {
  let cfl = av1_cfl_state()
  av1_cfl_begin_block(cfl, { row: 0, col: 0, width: 4, height: 4, }, true)
  assert_true(av1_cfl_store_tx(cfl, 0, 0, 4, 4, Array::makei(16, fn(i) { i })))
  assert_eq((cfl.buf_width, cfl.buf_height), (2, 2))
  assert_eq(
    [cfl.recon_q3[0], cfl.recon_q3[1], cfl.recon_q3[32], cfl.recon_q3[33]],
    [20, 36, 84, 100],
  )
  assert_true(av1_cfl_prepare(cfl, 4, 4))
  let padded = [
    20, 36, 36, 36, 84, 100, 100, 100, 84, 100, 100, 100, 84, 100, 100, 100,
  ]
  for i in 0..<16 {
    let offset = i / 4 * 32 + i % 4
    assert_eq(cfl.recon_q3[offset], padded[i])
    assert_eq(cfl.ac_q3[offset], padded[i] - 80)
  }
  // The Q3 mean can have a half tie even though every stored Q3 value is even.
  av1_cfl_begin_block(cfl, { row: 0, col: 8, width: 8, height: 8, }, true)
  let samples = Array::make(64, 0)
  samples[0] = 4
  assert_true(av1_cfl_store_tx(cfl, 8, 0, 8, 8, samples))
  assert_false(cfl.ac_ready)
  assert_true(av1_cfl_prepare(cfl, 4, 4))
  assert_eq(cfl.ac_q3[0], 7)
  for i in 1..<16 {
    assert_eq(cfl.ac_q3[i / 4 * 32 + i % 4], -1)
  }
}

///|
test "CfL owner combines reconstructed non-owner four-axis luma groups" {
  let state = av1_intra_state(16, 16, 32, 8, false, false, false, false)
  for col in 8..<12 {
    state.planes[0].pixels[7 * 16 + col] = 10
  }
  for col in 12..<16 {
    state.planes[0].pixels[7 * 16 + col] = 20
  }
  for row in 8..<12 {
    state.planes[0].pixels[row * 16 + 7] = 30
  }
  for row in 12..<16 {
    state.planes[0].pixels[row * 16 + 7] = 40
  }
  let decoder = av1_msac_new(av1_cfl_test_payload([b'\x9c']), true)
  for part in [(8, 8, AV1_INTRA_V), (12, 8, AV1_INTRA_V), (8, 12, AV1_INTRA_H)] {
    let (x, y, mode) = part
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: y, col: x, width: 4, height: 4, },
        mode,
        AV1_INTRA_DC,
        4,
        4,
        1,
      ),
    )
  }
  state.cfl.alpha_u = 8
  state.cfl.alpha_v = -8
  assert_true(
    av1_intra_residuals(
      decoder,
      state,
      { row: 12, col: 12, width: 4, height: 4, },
      AV1_INTRA_V,
      AV1_INTRA_CFL,
      4,
      4,
      1,
    ),
  )
  let q3 = [80, 160, 320, 160]
  let expected_u = [115, 125, 146, 125]
  let expected_v = [141, 131, 110, 131]
  assert_eq((state.cfl.buf_width, state.cfl.buf_height), (4, 4))
  for row in 0..<4 {
    for col in 0..<4 {
      let quadrant = row / 2 * 2 + col / 2
      assert_eq(state.cfl.recon_q3[row * 32 + col], q3[quadrant])
      assert_eq(state.cfl.ac_q3[row * 32 + col], q3[quadrant] - 180)
      assert_eq(
        state.planes[1].pixels[(row + 4) * 8 + col + 4],
        expected_u[quadrant],
      )
      assert_eq(
        state.planes[2].pixels[(row + 4) * 8 + col + 4],
        expected_v[quadrant],
      )
    }
  }
  assert_eq(decoder.bool(), 1)
}

///|
test "CfL stores complete luma TX outside MI bounds and pads only missing TXs" {
  for tx_size in [16, 4] {
    let state = av1_intra_state(8, 8, 32, 8, false, false, false, false)
    state.cfl.alpha_u = 16
    state.cfl.alpha_v = 0
    let decoder = av1_msac_new(av1_cfl_test_payload([b'\x9c']), true)
    assert_true(
      av1_intra_residuals(
        decoder,
        state,
        { row: 0, col: 0, width: 16, height: 16, },
        AV1_INTRA_SMOOTH_V,
        AV1_INTRA_CFL,
        tx_size,
        tx_size,
        1,
      ),
    )
    let q3_rows = if tx_size == 16 {
      [1016, 1020, 1024, 1024, 1028, 1032, 1032, 1032]
    } else {
      [1020, 1028, 1032, 1032, 1032, 1032, 1032, 1032]
    }
    let mean = if tx_size == 16 { 1026 } else { 1030 }
    for row in 0..<8 {
      for col in 0..<8 {
        assert_eq(state.cfl.recon_q3[row * 32 + col], q3_rows[row])
        assert_eq(state.cfl.ac_q3[row * 32 + col], q3_rows[row] - mean)
      }
    }
    let uv_rows = if tx_size == 16 {
      [125, 126, 127, 127]
    } else {
      [125, 127, 129, 129]
    }
    for row in 0..<4 {
      for col in 0..<4 {
        assert_eq(state.planes[1].pixels[row * 4 + col], uv_rows[row])
      }
    }
    assert_eq(state.planes[2].pixels, Array::make(16, 128))
    assert_eq(decoder.bool(), 1)
  }
}

///|
test "CfL clips scaled prediction at native depth before residual reconstruction" {
  for bit_depth in [8, 10, 12] {
    let maximum = (1 << bit_depth) - 1
    let cfl = av1_cfl_state()
    av1_cfl_begin_block(cfl, { row: 0, col: 0, width: 8, height: 8, }, true)
    let samples = Array::makei(64, fn(i) { if i < 32 { 0 } else { maximum } })
    assert_true(av1_cfl_store_tx(cfl, 0, 0, 8, 8, samples))
    let prediction = Array::make(16, 10)
    assert_true(av1_cfl_predict(cfl, prediction, 4, 4, 16, bit_depth))
    for i in 0..<16 {
      assert_eq(prediction[i], if i < 8 { 0 } else { maximum })
    }
    // A following residual starts from the clipped prediction.
    assert_eq(av1_intra_clip(prediction[0] + 7, bit_depth), 7)
    assert_eq(av1_intra_clip(prediction[8] - 7, bit_depth), maximum - 7)
  }
}

///|
test "CfL UV mode reads alphas before luma palette and skips UV palette angle" {
  // skip=1,Y=DC,UV=CfL,joint=4,Ualpha=-3,Valpha=5,paletteY=0,filter=0,101.
  for bit_depth in [8, 10, 12] {
    for q in [0, 32] {
      let state = av1_intra_state(8, 8, q, bit_depth, false, true, true, false)
      let decoder = av1_msac_new(
        av1_cfl_test_payload([b'\xfb', b'\x50', b'\x4f']),
        true,
      )
      assert_true(
        av1_intra_block(decoder, state, { row: 0, col: 0, width: 8, height: 8, }),
      )
      assert_eq((state.cfl.alpha_u, state.cfl.alpha_v), (-3, 5))
      assert_eq(state.cfl.sign[8], 1)
      assert_eq(state.cfl.alpha[2][16], 1)
      assert_eq(state.cfl.alpha[4][16], 1)
      assert_eq(state.palette.y_mode[0][0][2], 1)
      assert_eq(state.palette.uv_mode[0][2], 0)
      assert_eq(state.angle_delta, av1_intra_angle_cdfs())
      assert_eq(state.filter_intra[3][2], 1)
      for plane in state.planes {
        assert_eq(
          plane.pixels,
          Array::make(plane.width * plane.height, 1 << (bit_depth - 1)),
        )
      }
      assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
    }
  }
}
