///|
test "CICP identity conversion requires 444 and uses RGB range on every channel" {
  assert_true(
    av1_yuv_highbd_to_rgba(1, 1, [16], [235], [81], 8, matrix_coefficients=0)
    is None,
  )
  let image = av1_yuv_highbd_to_rgba(
    1,
    1,
    [16],
    [235],
    [81],
    8,
    subsampling_x=false,
    subsampling_y=false,
    matrix_coefficients=0,
  ).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x4c', b'\x00', b'\xff', b'\xff'))
}

///|
test "YCgCo limited range expands reconstructed RGB with 219 denominator" {
  // H.273 27-29,51-57: limited RGB (235,16,16) encodes to (71,73,238).
  let red = av1_yuv_highbd_to_rgba(
    1,
    1,
    [71],
    [73],
    [238],
    8,
    subsampling_x=false,
    subsampling_y=false,
    matrix_coefficients=8,
  ).unwrap()
  assert_eq(red.get_pixel(0, 0), (b'\xff', b'\x00', b'\x00', b'\xff'))
  for depth in [8, 10, 12] {
    let shift = depth - 8
    for level in [16, 235] {
      let gray = av1_yuv_highbd_to_rgba(
        1,
        1,
        [level << shift],
        [128 << shift],
        [128 << shift],
        depth,
        subsampling_x=false,
        subsampling_y=false,
        matrix_coefficients=8,
      ).unwrap()
      let value = if level == 16 { b'\x00' } else { b'\xff' }
      assert_eq(gray.get_pixel(0, 0), (value, value, value, b'\xff'))
    }
  }
}

///|
test "XYZ color primaries require a transfer and convert to sRGB explicitly" {
  assert_true(
    av1_yuv_highbd_to_rgba(
      1,
      1,
      [100],
      [130],
      [150],
      8,
      subsampling_x=false,
      subsampling_y=false,
      full_range=true,
      matrix_coefficients=11,
      color_primaries=10,
    )
    is None,
  )
  // Independent NumPy solve of the BT.709 xy-primary / D65 white-point
  // matrix, following H.273 YDzDx inversion, linear TC8 and sRGB TC13.
  let cases = [
    (8, 100, 130, 150, (b'\xff', b'\x7e', b'\xa7', b'\xff')),
    (12, 1024, 2000, 2500, (b'\xff', b'\x2b', b'\x81', b'\xff')),
    (10, 360, 500, 600, (b'\xfd', b'\x72', b'\x97', b'\xff')),
  ]
  for item in cases {
    let (depth, y, u, v, expected) = item
    let image = av1_yuv_highbd_to_rgba(
      1,
      1,
      [y],
      [u],
      [v],
      depth,
      subsampling_x=false,
      subsampling_y=false,
      full_range=true,
      matrix_coefficients=11,
      color_primaries=10,
      transfer_characteristics=8,
    ).unwrap()
    assert_eq(image.get_pixel(0, 0), expected)
  }
}

///|
fn av1_color_test_property(data : Bytes) -> Array[Prop]? {
  // parse_props consumes an already bounded box tree. This isolates the
  // colr payload semantics from unrelated BMFF item/extent construction.
  let root : Box = {
    typ: t_iprp,
    start: 0,
    payload: 0,
    end: data.length(),
    parent: -1,
  }
  let boxes : Array[Box] = [
    root,
    { typ: t_ipco, start: 1, payload: 0, end: data.length(), parent: 0, },
    { typ: t_colr, start: 2, payload: 0, end: data.length(), parent: 1, },
  ]
  Some(parse_props(data.to_array(), boxes, Some(root))) catch {
    _ => None
  }
}

///|
test "nclx preserves the full range bit and ICC is not zero valued nclx" {
  let nclx = av1_color_test_property(b"nclx\x00\x01\x00\x0d\x00\x01\x80").unwrap()[0]
  assert_eq(nclx.kind, t_colr)
  assert_eq((nclx.p, nclx.t, nclx.m), (1, 13, 1))
  assert_true(nclx.full_range)
  let icc = av1_color_test_property(b"prof\x00\x01\x00\x0d\x00\x01\x80").unwrap()[0]
  assert_true(icc.kind != t_colr)
  assert_true(av1_color_test_property(b"nclx\x00\x01\x00\x0d\x00\x01") is None)
}
