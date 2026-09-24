///|
test "cdef zero strengths preserve an 8-bit luma plane" {
  let plane : Array[Int] = []
  for i in 0..<64 {
    plane.push((i * 3) & 255)
  }
  let params : Array[Av1CdefParams] = [
    { primary_strength: 0, secondary_strength: 0, damping: 3, direction: 0, },
  ]
  let filtered = av1_cdef_filter_plane(8, 8, plane, params).unwrap()
  assert_eq(filtered, plane)
}

///|
test "cdef nonzero strengths preserve every flat direction and bit depth" {
  for bit_depth in [8, 10, 12] {
    let plane = Array::make(64, 1 << (bit_depth - 1))
    for direction in 0..<8 {
      let params : Array[Av1CdefParams] = [
        { primary_strength: 7, secondary_strength: 2, damping: 3, direction, },
      ]
      assert_eq(
        av1_cdef_filter_plane(8, 8, plane, params, bit_depth~).unwrap(),
        plane,
      )
    }
  }
}

///|
test "cdef constraint preserves differences beyond the damping cutoff" {
  let plane : Array[Int] = Array::make(8 * 8, 0)
  plane[4 * 8 + 4] = 10
  let filtered = av1_cdef_filter_plane(8, 8, plane, [
    { primary_strength: 4, secondary_strength: 0, damping: 3, direction: 0, },
  ]).unwrap()
  // dampingAdj = 3 - floorLog2(4) = 1; 4 - (10 >> 1) < 0.
  assert_eq(filtered, plane)
}

///|
test "cdef composes independent 420 luma and chroma grids" {
  let y = Array::make(16 * 8, 128)
  let u = Array::make(8 * 4, 128)
  let v = Array::make(8 * 4, 128)
  let y_params : Array[Av1CdefParams] = Array::make(2, {
    primary_strength: 0,
    secondary_strength: 0,
    damping: 3,
    direction: 0,
  })
  let uv_params : Array[Av1CdefParams] = Array::make(2, {
    primary_strength: 0,
    secondary_strength: 0,
    damping: 3,
    direction: 0,
  })
  let (yf, uf, vf) = av1_cdef_filter_yuv420(16, 8, y, u, v, y_params, uv_params).unwrap()
  assert_eq(yf, y)
  assert_eq(uf, u)
  assert_eq(vf, v)
}

///|
test "cdef rejects malformed grids and unsupported depths" {
  let params : Array[Av1CdefParams] = [
    { primary_strength: 0, secondary_strength: 0, damping: 3, direction: 0, },
  ]
  assert_eq(av1_cdef_filter_plane(9, 8, Array::make(72, 0), params), None)
  assert_eq(
    av1_cdef_filter_plane(8, 8, Array::make(64, 0), params, bit_depth=16),
    None,
  )
  assert_eq(av1_cdef_filter_plane(2147483647, 2147483647, [], params), None)
  assert_eq(av1_cdef_filter_plane(8, 8, Array::make(64, -1), params), None)
  for bit_depth in [8, 10, 12] {
    assert_eq(
      av1_cdef_filter_plane(
        8,
        8,
        Array::make(64, 1 << bit_depth),
        params,
        bit_depth~,
      ),
      None,
    )
  }
  assert_eq(
    av1_cdef_filter_plane(8, 8, Array::make(64, 128), [
      { primary_strength: 7, secondary_strength: 3, damping: 3, direction: 0, },
    ]),
    None,
  )
}
