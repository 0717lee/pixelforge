///|
test "monochrome CDEF matches original C native-strength luma golden" {
  // Existing cdef_block.c oracle: direction=0, variance=242, native primary=9.
  // The same Y result applies independently of whether chroma planes exist.
  let y = av1_cdef_frame_pattern(8, 8, 10, 1010)
  let snapshot = y.copy()
  let config : Av1CdefConfig = {
    bits: 0,
    damping: 5,
    y_primary: [7],
    y_secondary: [2],
    uv_primary: [],
    uv_secondary: [],
  }
  let actual = av1_cdef_filter_frame(8, 8, [y], [0, 0, 0, 0], [0], config, 10).unwrap()
  assert_eq(actual.length(), 1)
  assert_eq(
    actual[0],
    av1_cdef_frame_reference_pixels(
      "3d33fb3e03bf3ea3cb3f73d33bd3f73e13cb3f73e73d53b93f93ec3e03db3cc3bf3f83f63e93e13e03e03df3dd3df3d93dc3dc3e23eb3f73f93f93f93c33d73e73f53f93d13ea3f63f93d03eb3f93d23f03f63c43ec3c13eb3c43eb3f93ce3f9",
    ),
  )
  assert_eq(actual[0][2], 992)
  assert_eq(y, snapshot)
}

///|
test "monochrome CDEF preserves color Y behavior across depths and index boundaries" {
  let mono_config : Av1CdefConfig = {
    bits: 1,
    damping: 6,
    y_primary: [7, 1],
    y_secondary: [2, 4],
    uv_primary: [],
    uv_secondary: [],
  }
  let color_config : Av1CdefConfig = {
    bits: 1,
    damping: 6,
    y_primary: [7, 1],
    y_secondary: [2, 4],
    uv_primary: [15, 8],
    uv_secondary: [4, 2],
  }
  for bit_depth in [8, 10, 12] {
    let y = av1_cdef_frame_pattern(72, 8, bit_depth, bit_depth * 101)
    let u = av1_cdef_frame_pattern(36, 4, bit_depth, bit_depth * 101 + 1)
    let v = av1_cdef_frame_pattern(36, 4, bit_depth, bit_depth * 101 + 2)
    let skips = Array::make(36, 0)
    skips[0] = 1
    skips[1] = 1
    skips[18] = 1
    skips[19] = 1
    for indices in [[0, 1], [0, -1]] {
      let mono = av1_cdef_filter_frame(
        72,
        8,
        [y],
        skips,
        indices,
        mono_config,
        bit_depth,
      ).unwrap()
      let color = av1_cdef_filter_frame(
        72,
        8,
        [y, u, v],
        skips,
        indices,
        color_config,
        bit_depth,
      ).unwrap()
      assert_eq(mono.length(), 1)
      assert_eq(color.length(), 3)
      assert_eq(mono[0], color[0])
      assert_true(mono[0] != y)
      for row in 0..<8 {
        for x in 0..<8 {
          assert_eq(mono[0][row * 72 + x], y[row * 72 + x])
        }
      }
    }
  }
}

///|
test "monochrome CDEF rejects plane counts and mismatched configuration shapes" {
  let mono_config : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [7],
    y_secondary: [2],
    uv_primary: [],
    uv_secondary: [],
  }
  let color_config : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [7],
    y_secondary: [2],
    uv_primary: [7],
    uv_secondary: [2],
  }
  let y = Array::make(64, 128)
  let uv = Array::make(16, 128)
  let skips = [0, 0, 0, 0]
  assert_true(
    av1_cdef_filter_frame(8, 8, [], skips, [0], mono_config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, [y, uv], skips, [0], color_config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, [y, uv, uv, uv], skips, [0], color_config, 8)
    is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, [y], skips, [0], color_config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, [y, uv, uv], skips, [0], mono_config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, [uv], skips, [0], mono_config, 8) is None,
  )
  y[0] = 256
  assert_true(
    av1_cdef_filter_frame(8, 8, [y], skips, [0], mono_config, 8) is None,
  )
}
