///|
test "av1 decodes a real all-zero DC tile to neutral gray" {
  let sequence = av1_sequence_info([
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
  ]).unwrap()
  let header = av1_parse_stage1_frame(
    [
      b'\x12', b'\xB0', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00', b'\x2E',
    ],
    sequence,
  ).unwrap()
  assert_eq((header.header_bytes, header.base_q_idx), (8, 43))
  let tile : Array[Byte] = [b'\x2E']
  let image = av1_decode_dc_tile(64, 64, tile, 43).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "av1 decodes the reference flat reduced-still stream end to end" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0',
    b'\x08', b'\x32', b'\x09', b'\x12', b'\xB0', b'\x00', b'\x00', b'\x40', b'\x00',
    b'\x00', b'\x00', b'\x2E',
  ]
  let image = av1_decode(stream).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "av1 decodes a single DC residual from the reference solid-Y stream" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0',
    b'\x08', b'\x32', b'\x0C', b'\x12', b'\x10', b'\x00', b'\x00', b'\x40', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\xEB', b'\xCC', b'\xD7',
  ]
  let image = av1_decode(stream).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x62', b'\x62', b'\x62', b'\xFF'))
  assert_eq(image.get_pixel(63, 63), (b'\x62', b'\x62', b'\x62', b'\xFF'))
}

///|
test "reference single-DC residual envelope is parsed" {
  let sequence = av1_sequence_info([
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
  ]).unwrap()
  let header = av1_parse_stage1_frame(
    [
      b'\x12', b'\x10', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00', b'\x00',
      b'\xEB', b'\xCC', b'\xD7',
    ],
    sequence,
  ).unwrap()
  assert_eq((header.header_bytes, header.base_q_idx), (8, 33))
  assert_eq(header.tile_payload[0], b'\x00')
}

///|
test "av1 decodes a 32x32 neutral tile" {
  // Crafted with scripts/craft_av1_fixture.py (LARGEST tx mode, all-skip,
  // uv_mode read from the CFL-allowed table used for 32x32 blocks).
  let image = av1_decode_dc_tile(32, 32, [b'\x14', b'\x80'], 80, disable_cdf_update=true).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
  assert_eq(image.get_pixel(31, 31), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "av1 dc tile applies full-range conversion to a single DC residual" {
  // The reference residual stream reconstructs Y=100 with neutral chroma.
  // Full-range conversion therefore keeps the luma value at RGB=100,
  // whereas the limited-range path maps it to the nearby studio-range value.
  let image = av1_decode_dc_tile(
    64,
    64,
    [b'\x00', b'\xEB', b'\xCC', b'\xD7'],
    33,
    full_range=true,
  ).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x64', b'\x64', b'\x64', b'\xFF'))
}

///|
test "av1 dc tile rejects unsupported dimensions and payload bounds" {
  assert_true(av1_decode_dc_tile(16, 16, [b'\x2E'], 43) is None)
  assert_true(av1_decode_dc_tile(32, 64, [b'\x2E'], 43) is None)
  assert_true(av1_decode_dc_tile(32, 32, [], 43) is None)
  assert_true(av1_decode_dc_tile(32, 32, [b'\x2E', b'\x2E', b'\x2E', b'\x2E', b'\x2E'], 43) is None)
  // qindex zero is valid for lossless/high-bit-depth constant tiles.
  assert_true(av1_decode_dc_tile(32, 32, [b'\x2B', b'\xC1'], 256) is None)
}

///|
test "external use128 neutral fixture" {
  let stream : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFE',
    b'\x00', b'\x08', b'\x32', b'\x06', b'\x17', b'\x80', b'\x00', b'\x00',
    b'\x40', b'\x2E',
  ]
  assert_true(av1_parse_stage1_frame([b'\x17', b'\x80', b'\x00', b'\x00', b'\x40', b'\x2E'], av1_sequence_info(stream).unwrap()) is Some(_))
  let image = av1_decode(stream).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}

///|
test "highbd tile path normalizes a neutral 10-bit frame" {
  let image = av1_decode_dc_tile(
    64,
    64,
    [b'\x2E'],
    120,
    bit_depth=10,
    full_range=true,
  ).unwrap()
  assert_eq(image.get_pixel(0, 0), (b'\x80', b'\x80', b'\x80', b'\xFF'))
}
