///|
test "frame tile bounds reject duplicate reversed oversized and overflow endpoints" {
  for
    cols in [
      [0, 0, 2],
      [0, 2, 1, 2],
      [0, 1, 3],
      [0, -1, 2],
      [0, 1, 2147483647],
      [0, 33554434],
    ] {
    assert_true(
      av1_decode_tile_group_with_boundaries(
        128,
        64,
        cols,
        [0, 1],
        64,
        [b'\x00', b'\x2E', b'\x2E'],
        1,
        43,
      )
      is None,
    )
  }
  assert_true(
    av1_decode_tile_group(65536, 65536, 1024, 1024, [b'\x2E'], 1, 43) is None,
  )
}

///|
test "frame tile endpoints preserve visible crop and exact superblock cover" {
  assert_eq(av1_frame_tile_starts([0, 1, 2], 64, 95).unwrap(), [0, 64, 95])
  assert_eq(av1_frame_tile_starts([0, 2, 3], 128, 257).unwrap(), [0, 256, 257])
  assert_true(av1_frame_tile_starts([0, 1, 3], 64, 95) is None)
  assert_true(av1_frame_tile_starts([0, 1, 2], 64, 64) is None)
}

///|
test "CDEF tile probe requires whole 64 pixel regions at internal boundaries" {
  let config : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [0],
    y_secondary: [0],
    uv_primary: [0],
    uv_secondary: [0],
  }
  assert_true(
    av1_decode_tile_group(
      64,
      64,
      2,
      1,
      [b'\x00', b'\x2E', b'\x2E'],
      1,
      43,
      cdef=Some(config),
    )
    is None,
  )
  let expected = av1_decode_tile_group(
    128,
    64,
    2,
    1,
    [b'\x00', b'\x2E', b'\x2E'],
    1,
    43,
  ).unwrap()
  let actual = av1_decode_tile_group(
    128,
    64,
    2,
    1,
    [b'\x00', b'\x2E', b'\x2E'],
    1,
    43,
    cdef=Some(config),
  ).unwrap()
  for row in 0..<64 {
    for col in 0..<128 {
      assert_eq(actual.get_pixel(col, row), expected.get_pixel(col, row))
    }
  }
}
