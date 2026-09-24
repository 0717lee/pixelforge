///|
fn av1_intrabc_test_state(
  bit_depth? : Int = 8,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
  monochrome? : Bool = false,
  superblock_size? : Int = 64,
) -> Av1IntraState {
  av1_intra_state(
    384,
    256,
    80,
    bit_depth,
    false,
    true,
    false,
    true,
    sub_x~,
    sub_y~,
    monochrome~,
    superblock_size~,
    allow_intrabc=true,
  )
}

///|
test "intrabc displacement obeys tile, delay and wavefront bounds" {
  let state = av1_intrabc_test_state()
  let block : Av1SbBlock = { row: 64, col: 128, width: 16, height: 16, }
  assert_true(av1_intrabc_dv_valid(state, block, -64 * 8, -128 * 8))
  assert_false(av1_intrabc_dv_valid(state, block, -65 * 8, -128 * 8))
  assert_false(av1_intrabc_dv_valid(state, block, -64 * 8, -129 * 8))
  assert_false(av1_intrabc_dv_valid(state, block, -64 * 8 + 1, -128 * 8))
  assert_false(av1_intrabc_dv_valid(state, block, 0, 0))
  // Four SB64 of delay are insufficient; the source must be strictly earlier.
  let first_row : Av1SbBlock = { row: 0, col: 256, width: 16, height: 16, }
  assert_false(av1_intrabc_dv_valid(state, first_row, 0, -256 * 8))
  let later : Av1SbBlock = { row: 0, col: 320, width: 16, height: 16, }
  assert_true(av1_intrabc_dv_valid(state, later, 0, -320 * 8))
  // Row-distance alone does not allow an arbitrarily far-right source.
  let next_row : Av1SbBlock = { row: 64, col: 0, width: 16, height: 16, }
  assert_true(av1_intrabc_dv_valid(state, next_row, -64 * 8, 0))
  assert_false(av1_intrabc_dv_valid(state, next_row, -64 * 8, 64 * 8))
  assert_false(av1_intrabc_dv_valid(state, next_row, -64 * 8, 384 * 8))
  let sb128 = av1_intrabc_test_state(superblock_size=128)
  let row128 : Av1SbBlock = { row: 128, col: 0, width: 16, height: 16, }
  assert_true(av1_intrabc_dv_valid(sb128, row128, -128 * 8, 64 * 8))
  assert_false(av1_intrabc_dv_valid(sb128, row128, -128 * 8, 128 * 8))
}

///|
test "intrabc predictor uses completed copy neighbours and tile-relative defaults" {
  let ibc = av1_intrabc_state(384, 256, tile_col=96, tile_row=64)
  let top : Av1SbBlock = { row: 0, col: 320, width: 16, height: 16, }
  assert_eq(av1_intrabc_predictor(ibc, top, 64), (0, -320 * 8))
  let lower : Av1SbBlock = { row: 64, col: 128, width: 16, height: 16, }
  assert_eq(av1_intrabc_predictor(ibc, lower, 64), (-64 * 8, 0))
  let above : Av1SbBlock = { row: 48, col: 128, width: 16, height: 16, }
  av1_intrabc_record(ibc, above, false, 0, 0, 0, 8, 8)
  assert_eq(av1_intrabc_predictor(ibc, lower, 64), (-64 * 8, 0))
  av1_intrabc_record(ibc, above, true, -32 * 8, -96 * 8, 0, 8, 8)
  assert_eq(av1_intrabc_predictor(ibc, lower, 64), (-32 * 8, -96 * 8))
  // A zero nearest vector falls through to the second candidate before the
  // default vector. This also pins stable above-before-left stack ordering.
  av1_intrabc_record(ibc, above, true, 0, 0, 0, 8, 8)
  let left : Av1SbBlock = { row: 64, col: 112, width: 16, height: 16, }
  av1_intrabc_record(ibc, left, true, -64 * 8, -16 * 8, 0, 8, 8)
  assert_eq(av1_intrabc_predictor(ibc, lower, 64), (-64 * 8, -16 * 8))
}

///|
test "intrabc integer DV has separate entropy and omits fractional symbols" {
  let ibc = av1_intrabc_state(384, 256)
  let reference = av1_intrabc_state(384, 256)
  for tables in [ibc.info.cdfs, reference.info.cdfs] {
    tables.mv_joint[1][0] = 1
    tables.mv_joint[1][1] = 2
    tables.mv_joint[1][2] = 3
    for component in 0..<2 {
      let row = tables.mv_class[1][component]
      for index in 0..<(row.length() - 1) {
        row[index] = 32768 - (row.length() - 2 - index)
      }
    }
  }
  let data : Array[Byte] = [0x79, 0x64, 0x38, 0xa7, 0x5c, 0xe9, 0x26, 0x41]
  let decoder = av1_msac_new(data, true)
  let expected = av1_msac_new(data, true)
  let tables = reference.info.cdfs
  assert_eq(expected.symbol(tables.mv_joint[1]), 3)
  let delta : Array[Int] = []
  for component in 0..<2 {
    let sign = expected.symbol(tables.mv_sign[1][component])
    assert_eq(expected.symbol(tables.mv_class[1][component]), 0)
    let bit = expected.symbol(tables.mv_class0_bit[1][component])
    delta.push((bit + 1) * 8 * (if sign == 1 { -1 } else { 1 }))
  }
  assert_eq(
    av1_intrabc_read_dv(decoder, ibc, (-512, -1024)),
    Some((-512 + delta[0], -1024 + delta[1])),
  )
  assert_eq(decoder.bit_pos, expected.bit_pos)
  assert_eq(decoder.symbol_value, expected.symbol_value)
  assert_eq(decoder.symbol_range, expected.symbol_range)
  assert_eq(decoder.entropy_literal(12), expected.entropy_literal(12))
  assert_eq(ibc.info.cdfs.mv_joint[0][4], 0)
  assert_eq(ibc.info.cdfs.mv_joint[1][4], 1)
  for component in 0..<2 {
    for row in ibc.info.cdfs.mv_class0_fr[1][component] {
      assert_eq(row[row.length() - 1], 0)
    }
    assert_eq(ibc.info.cdfs.mv_class0_hp[1][component][2], 0)
    assert_eq(ibc.info.cdfs.mv_fr[1][component][4], 0)
    assert_eq(ibc.info.cdfs.mv_hp[1][component][2], 0)
  }
}

///|
test "intrabc current-frame prediction preserves all bit depths and chroma phases" {
  for bit_depth in [8, 10, 12] {
    for layout in [(true, 1, 1), (false, 1, 1), (false, 1, 0), (false, 0, 0)] {
      let (monochrome, sub_x, sub_y) = layout
      let state = av1_intrabc_test_state(
        bit_depth~,
        sub_x~,
        sub_y~,
        monochrome~,
      )
      let ibc = state.intrabc.unwrap()
      for row in 0..<16 {
        for col in 0..<state.cols {
          ibc.info.field.written[row * state.cols + col] = true
        }
      }
      for plane in 0..<state.planes.length() {
        let pixels = state.planes[plane]
        for y in 0..<pixels.height {
          for x in 0..<pixels.width {
            pixels.pixels[y * pixels.width + x] = (
                x * 19 + y * 37 + plane * 173 + 61
              ) &
              ((1 << bit_depth) - 1)
          }
        }
      }
      let before = state.planes.map(plane => plane.pixels.copy())
      // Both DV components are odd luma pixels. Subsampled axes must use
      // BILINEAR half phases, including negative displacement rounding.
      let blocks : Array[Av1SbBlock] = [
        { row: 64, col: 128, width: 16, height: 16, },
        { row: 68, col: 132, width: 4, height: 4, },
      ]
      for block in blocks {
        assert_true(av1_intrabc_predict(state, ibc, block, -63 * 8, -127 * 8))
        for plane in 0..<state.planes.length() {
          let sx = if plane == 0 { 0 } else { sub_x }
          let sy = if plane == 0 { 0 } else { sub_y }
          let pixels = state.planes[plane]
          let x0 = block.col / (4 << sx) * 4
          let y0 = block.row / (4 << sy) * 4
          let (width, height) = av1_plane_residual_size(
            block.width,
            block.height,
            plane,
            sx,
            sy,
          )
          for y in 0..<height {
            for x in 0..<width {
              let xx = x0 + x + (-127 >> sx)
              let yy = y0 + y + (-63 >> sy)
              let samples = before[plane]
              let a = samples[yy * pixels.width + xx]
              let b = samples[yy * pixels.width + xx + sx]
              let c = samples[(yy + sy) * pixels.width + xx]
              let d = samples[(yy + sy) * pixels.width + xx + sx]
              assert_eq(
                pixels.pixels[(y0 + y) * pixels.width + x0 + x],
                (a + b + c + d + 2) / 4,
              )
            }
          }
        }
      }
    }
  }
}

///|
test "intrabc refuses unfinished source pixels and out-of-tile small chroma owners" {
  let state = av1_intrabc_test_state()
  let ibc = state.intrabc.unwrap()
  let block : Av1SbBlock = { row: 64, col: 128, width: 16, height: 16, }
  assert_false(av1_intrabc_predict(state, ibc, block, -64 * 8, -128 * 8))
  let small : Av1SbBlock = { row: 68, col: 132, width: 4, height: 4, }
  assert_true(av1_intrabc_dv_valid(state, small, -64 * 8, -128 * 8))
  assert_false(av1_intrabc_dv_valid(state, small, -68 * 8, -128 * 8))
  assert_false(av1_intrabc_dv_valid(state, small, -64 * 8, -132 * 8))
  // Clearing even one source MI refuses a copy despite all other blocks in
  // the allowed region having completed.
  for index in 0..<(state.cols * 16) {
    ibc.info.field.written[index] = true
  }
  ibc.info.field.written[state.cols + 1] = false
  assert_false(av1_intrabc_predict(state, ibc, block, -64 * 8, -128 * 8))
}

///|
test "intrabc 444 and 422 directional chroma neighbours follow subsampled axes" {
  let tile : Av1SbBlock = { row: 0, col: 0, width: 64, height: 64, }
  let block : Av1SbBlock = { row: 16, col: 8, width: 4, height: 4, }
  assert_eq(
    av1_intra_edge_neighbor_indices(tile, block, 1, sub_x=0, sub_y=0),
    Some((Some(50), Some(65))),
  )
  let owner : Av1SbBlock = { row: 16, col: 12, width: 4, height: 4, }
  assert_eq(
    av1_intra_edge_neighbor_indices(tile, owner, 1, sub_x=1, sub_y=0),
    Some((Some(51), Some(65))),
  )
  let modes = Array::make(256, AV1_INTRA_DC)
  let uv = modes.copy()
  uv[50] = AV1_INTRA_SMOOTH
  assert_eq(
    av1_intra_edge_neighbor_smooth(tile, block, 1, modes, uv, sub_x=0, sub_y=0),
    Some(true),
  )
}
