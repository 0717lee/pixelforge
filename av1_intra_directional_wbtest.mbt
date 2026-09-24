///|
fn av1_intra_directional_payload(prefix : Array[Byte]) -> Array[Byte] {
  let payload = prefix.copy()
  for _ in 0..<8 {
    payload.push(b'\x00')
  }
  payload
}

///|
test "contextual partition traversal preserves mixed vertical leaf provenance" {
  for vertical_a in [true, false] {
    let partition = if vertical_a {
      Av1SbPartitionVertA
    } else {
      Av1SbPartitionVertB
    }
    // The only entropy field is the 16x16 partition, then marker 101.
    let prefix = if vertical_a { b'\xe5' } else { b'\xec' }
    let decoder = av1_msac_new(
      av1_intra_directional_payload([prefix, b'\x40']),
      true,
    )
    let root = av1_partition_node(0, 0, 16, 16, 16)
    let neighbors = av1_partition_neighbor_state(
      { row: 0, col: 0, width: 16, height: 16, },
      16,
      16,
    ).unwrap()
    let visits : Array[(Int, Int, Int, Int, Int)] = []
    assert_true(
      av1_walk_partition_tree_context(
        decoder,
        av1_partition_cdf_state(),
        neighbors,
        root,
        fn(_, block, source) {
          let code = match source {
            Av1SbPartitionVertA => 6
            Av1SbPartitionVertB => 7
            _ => -1
          }
          visits.push((block.row, block.col, block.width, block.height, code))
          true
        },
      ),
    )
    let expected = if vertical_a {
      [(0, 0, 8, 8, 6), (8, 0, 8, 8, 6), (0, 8, 8, 16, 6)]
    } else {
      [(0, 0, 8, 16, 7), (0, 8, 8, 8, 7), (8, 8, 8, 8, 7)]
    }
    assert_eq(visits, expected)
    let public_blocks = av1_partition_leaves(root, [partition]).unwrap()
    assert_eq(public_blocks.length(), visits.length())
    for i in 0..<public_blocks.length() {
      let (row, col, width, height, _) = visits[i]
      let block = public_blocks[i]
      assert_eq(
        (block.row, block.col, block.width, block.height),
        (row, col, width, height),
      )
    }
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}

///|
test "intra angle reader retains nonzero deltas for every directional raw mode" {
  // One angle field for modes 1..8, with decoded deltas -3,-2,-1,0,1,2,3,-3.
  let decoder = av1_msac_new(
    av1_intra_directional_payload([b'\x01', b'\xee', b'\x47', b'\x02']),
    true,
  )
  let state = av1_intra_state(8, 8, 32, 8, false, false, false, false)
  let expected = [-3, -2, -1, 0, 1, 2, 3, -3]
  for i in 0..<8 {
    let before_y = state.y_angle_delta
    let before_uv = state.uv_angle_delta
    let plane = i % 2
    assert_true(av1_intra_read_mode_angle(decoder, state, i + 1, 3, plane~))
    assert_eq(
      state.y_angle_delta,
      if plane == 0 {
        expected[i]
      } else {
        before_y
      },
    )
    assert_eq(
      state.uv_angle_delta,
      if plane == 0 {
        before_uv
      } else {
        expected[i]
      },
    )
    assert_eq(state.angle_delta[i][7], 1)
  }
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}

///|
test "directional blocks retain independent Y and UV angle deltas" {
  // skip=1, Y=V delta=-3 (81 degrees), UV=H delta=+3 (189 degrees), 101.
  let state = av1_intra_state(
    8,
    8,
    32,
    8,
    false,
    true,
    true,
    false,
    enable_intra_edge_filter=true,
  )
  let decoder = av1_msac_new(
    av1_intra_directional_payload([b'\xfb', b'\x8e', b'\x15', b'\x68']),
    true,
  )
  assert_true(
    av1_intra_block(decoder, state, { row: 0, col: 0, width: 8, height: 8, }),
  )
  assert_eq((state.y_angle_delta, state.uv_angle_delta), (-3, 3))
  assert_eq(state.y_modes, Array::make(4, AV1_INTRA_V))
  assert_eq(state.uv_modes, Array::make(4, AV1_INTRA_H))
  assert_eq(state.planes[0].pixels, Array::make(64, 127))
  assert_eq(state.planes[1].pixels, Array::make(16, 129))
  assert_eq(state.planes[2].pixels, Array::make(16, 129))
  assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
}

///|
test "every coding block resets omitted nondirectional sub8 and CfL angles" {
  for variant in 0..<3 {
    let monochrome = variant != 2
    let state = av1_intra_state(
      8,
      8,
      32,
      8,
      false,
      true,
      true,
      false,
      monochrome~,
    )
    state.y_angle_delta = 3
    state.uv_angle_delta = -2
    state.prediction_partition = Av1SbPartitionVertB
    let prefix = if variant == 0 {
      [b'\xfb', b'\xcc'] // 4x4 V: angle is implied zero.
    } else if variant == 1 {
      [b'\xf8', b'\x18'] // Monochrome 8x8 DC: no angle fields.
    } else {
      [b'\xfb', b'\x50', b'\x4f'] // Y=DC, UV=CfL: no UV angle field.
    }
    let side = if variant == 0 { 4 } else { 8 }
    let decoder = av1_msac_new(av1_intra_directional_payload(prefix), true)
    assert_true(
      av1_intra_block(decoder, state, {
        row: 0,
        col: 0,
        width: side,
        height: side,
      }),
    )
    assert_eq((state.y_angle_delta, state.uv_angle_delta), (0, 0))
    assert_true(state.prediction_partition is Av1SbPartitionNone)
    assert_eq([decoder.bool(), decoder.bool(), decoder.bool()], [1, 0, 1])
  }
}
