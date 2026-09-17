/// Loop-restoration frame syntax tests. Field transcripts exercise the
/// uncompressed header reader and the unit-layout helper, preserving an
/// explicit following-field marker where exact bit consumption matters.

///|
/// Append a single trailing one bit so every transcript proves exact syntax
/// consumption: after parsing, `reader.take(1)` must still return that bit.
fn av1_restoration_header_test_bits(bits : Array[Int]) -> Array[Int] {
  let marked : Array[Int] = []
  for bit in bits {
    marked.push(bit)
  }
  marked.push(1)
  marked
}

///|
fn av1_restoration_header_test_sequence(
  width : Int,
  use_128x128_superblock? : Bool = false,
  enable_restoration? : Bool = true,
  monochrome? : Bool = false,
) -> Av1SequenceInfo {
  {
    profile: 0,
    width,
    height: 16,
    bit_depth: 8,
    monochrome,
    subsampling_x: true,
    subsampling_y: true,
    reduced_still_picture_header: true,
    use_128x128_superblock,
    enable_filter_intra: false,
    enable_intra_edge_filter: false,
    enable_superres: true,
    enable_cdef: true,
    enable_restoration,
    full_range: true,
    separate_uv_delta_q: false,
    film_grain_params_present: false,
    color_primaries: 1,
    transfer_characteristics: 1,
    matrix_coefficients: 6,
  }
}

///|
fn av1_restoration_header_test_reader(bits : Array[Int]) -> Av1FrameBits {
  av1_cdef_header_test_reader(av1_restoration_header_test_bits(bits))
}

///|
test "restoration header maps all four two-bit mode codes per plane" {
  // 00 None, 01 Switchable, 10 Wiener, 11 Sgrproj. The integer is not the
  // internal enum: 01 is Switchable and 10 is Wiener.
  let cases = [
    ([0, 0], Av1RestorationNone),
    ([0, 1], Av1RestorationSwitchable),
    ([1, 0], Av1RestorationWiener),
    ([1, 1], Av1RestorationSgrproj),
  ]
  for case in cases {
    let (bits, expected) = case
    let reader = av1_restoration_header_test_reader(bits)
    let config = av1_parse_restoration_config(reader, true, false, true, true)
    // Active modes still require luma unit-size bits; only None terminates
    // the syntax, so these transcripts parse for None alone.
    if expected is Av1RestorationNone {
      let config = config.unwrap()
      assert_eq(config.modes, [expected])
      assert_eq(config.unit_sizes, [256])
      assert_eq(reader.take(1), Some(1))
    } else {
      assert_true(config is None)
    }
  }
}

///|
test "restoration header reads all four modes with unit bits for every plane" {
  // Color frame: Y Wiener, U Switchable, V Sgrproj. Active chroma forces
  // the halving bit even when the halving itself is off; U64 stays U64.
  let reader = av1_restoration_header_test_reader([1, 0, 0, 1, 1, 1, 0, 0])
  let config = av1_parse_restoration_config(reader, false, false, true, true).unwrap()
  assert_eq(config.modes, [
    Av1RestorationWiener,
    Av1RestorationSwitchable,
    Av1RestorationSgrproj,
  ])
  assert_eq(config.unit_sizes, [64, 64, 64])
  assert_eq(reader.take(1), Some(1))
}

///|
test "restoration header derives every luma unit size from header bits" {
  // SB64: one bit then a second when the size exceeds 64.
  // [1, 0] -> 64, [1, 1, 0] -> 128, [1, 1, 1] -> 256.
  let sb64 = [([0], 64), ([1, 0], 128), ([1, 1], 256)]
  for case in sb64 {
    let (bits, expected) = case
    let reader = av1_restoration_header_test_reader([1, 0] + bits)
    let config = av1_parse_restoration_config(reader, true, false, true, true).unwrap()
    assert_eq(config.modes, [Av1RestorationWiener])
    assert_eq(config.unit_sizes, [expected])
    assert_eq(reader.take(1), Some(1))
  }
  // SB128: the size already exceeds 64, so a single bit selects 128 or 256.
  for case in [([0], 128), ([1], 256)] {
    let (bits, expected) = case
    let reader = av1_restoration_header_test_reader([1, 0] + bits)
    let config = av1_parse_restoration_config(reader, true, true, true, true).unwrap()
    assert_eq(config.modes, [Av1RestorationWiener])
    assert_eq(config.unit_sizes, [expected])
    assert_eq(reader.take(1), Some(1))
  }
}

///|
test "restoration header halves chroma units only for 4:2:0 with active UV" {
  // Y None, U Wiener, V None: any active chroma plane forces the halving
  // bit even though luma itself is None. Bit 1 halves U64 to U32.
  let reader = av1_restoration_header_test_reader([0, 0, 1, 0, 0, 0, 0, 1])
  let config = av1_parse_restoration_config(reader, false, false, true, true).unwrap()
  assert_eq(config.modes, [
    Av1RestorationNone,
    Av1RestorationWiener,
    Av1RestorationNone,
  ])
  assert_eq(config.unit_sizes, [64, 32, 32])
  assert_eq(reader.take(1), Some(1))
  // Bit 0 keeps the shared luma size on both chroma planes.
  let reader = av1_restoration_header_test_reader([0, 0, 1, 0, 0, 0, 0, 0])
  let config = av1_parse_restoration_config(reader, false, false, true, true).unwrap()
  assert_eq(config.unit_sizes, [64, 64, 64])
  assert_eq(reader.take(1), Some(1))
  // 4:4:4 (s == 0) omits the halving bit entirely.
  let reader = av1_restoration_header_test_reader([0, 0, 1, 0, 0, 0, 0])
  let config = av1_parse_restoration_config(reader, false, false, false, false).unwrap()
  assert_eq(config.unit_sizes, [64, 64, 64])
  assert_eq(reader.take(1), Some(1))
}

///|
test "restoration header omits the chroma bit when only luma is active" {
  // Y Switchable with U/V None: chroma_none stays true, so no halving bit
  // is read and both chroma planes inherit the luma unit size.
  let reader = av1_restoration_header_test_reader([0, 1, 0, 0, 0, 0, 0])
  let config = av1_parse_restoration_config(reader, false, false, true, true).unwrap()
  assert_eq(config.modes, [
    Av1RestorationSwitchable,
    Av1RestorationNone,
    Av1RestorationNone,
  ])
  assert_eq(config.unit_sizes, [64, 64, 64])
  assert_eq(reader.take(1), Some(1))
}

///|
test "restoration header rejects truncated active syntax" {
  // An active mode without its mandatory unit-size bits must fail rather
  // than silently downgrade to None.
  let reader = av1_cdef_header_test_reader([1, 0])
  assert_true(
    av1_parse_restoration_config(reader, true, false, true, true) is None,
  )
  let reader = av1_cdef_header_test_reader([1, 0, 1])
  assert_true(
    av1_parse_restoration_config(reader, true, false, true, true) is None,
  )
}

///|
test "restoration unit count absorbs a trailing half unit" {
  // floor((W + U/2) / U), minimum one. The equality case creates a unit.
  assert_eq(av1_lr_count_units(64, 63), 1)
  assert_eq(av1_lr_count_units(64, 95), 1)
  assert_eq(av1_lr_count_units(64, 96), 2)
  assert_eq(av1_lr_count_units(64, 160), 3)
  assert_eq(av1_lr_count_units(256, 10), 1)
  assert_eq(av1_lr_count_units(256, 128), 1)
  assert_eq(av1_lr_count_units(256, 129), 1)
  assert_eq(av1_lr_count_units(256, 383), 1)
  assert_eq(av1_lr_count_units(256, 384), 2)
}

///|
test "restoration layout counts units over visible plane dimensions" {
  let mono = { modes: [Av1RestorationWiener], unit_sizes: [64], }
  let layout = av1_restoration_layout(mono, 95, 95, 16, true, true, true, 8).unwrap()
  assert_eq(layout.unit_cols, [1])
  assert_eq(layout.unit_rows, [1])
  let layout = av1_restoration_layout(mono, 96, 96, 16, true, true, true, 8).unwrap()
  assert_eq(layout.unit_cols, [2])
  // Height uses the same tail rule independently of width.
  let tall = av1_restoration_layout(mono, 64, 64, 96, true, true, true, 8).unwrap()
  assert_eq(tall.unit_cols, [1])
  assert_eq(tall.unit_rows, [2])
}

///|
test "restoration layout halves chroma planes and their units" {
  let color = {
    modes: [
      Av1RestorationWiener,
      Av1RestorationSgrproj,
      Av1RestorationSwitchable,
    ],
    unit_sizes: [64, 32, 32],
  }
  let layout = av1_restoration_layout(
    color, 200, 200, 200, false, true, true, 8,
  ).unwrap()
  // Luma 200/U64 -> (200+32)/64 = 3; chroma 100/U32 -> (100+16)/32 = 3.
  assert_eq(layout.unit_cols, [3, 3, 3])
  assert_eq(layout.unit_rows, [3, 3, 3])
  let halved = av1_restoration_layout(
    color, 100, 100, 100, false, true, true, 8,
  ).unwrap()
  // Luma 100/U64 -> (100+32)/64 = 2; chroma plane 50x50 with U32 ->
  // (50+16)/32 = 2, the half-unit tail absorbed by the last unit.
  assert_eq(halved.unit_cols, [2, 2, 2])
  assert_eq(halved.unit_rows, [2, 2, 2])
}

///|
test "restoration layout validates configs and geometry" {
  let valid_mono = { modes: [Av1RestorationSgrproj], unit_sizes: [256], }
  assert_true(av1_restoration_config_valid(valid_mono, monochrome=true))
  assert_false(av1_restoration_config_valid(valid_mono, monochrome=false))
  let color = {
    modes: [Av1RestorationNone, Av1RestorationNone, Av1RestorationNone],
    unit_sizes: [128, 64, 64],
  }
  assert_true(av1_restoration_config_valid(color))
  assert_false(av1_restoration_active(color))
  // Chroma planes must share one size, either the luma size or its single
  // 4:2:0 halving; 4:4:4 would compare equality instead.
  let mismatched = { modes: color.modes, unit_sizes: [128, 128, 64], }
  assert_false(av1_restoration_config_valid(mismatched))
  let bad_shift = { modes: color.modes, unit_sizes: [256, 32, 32], }
  assert_false(av1_restoration_config_valid(bad_shift))
  let bad_size = { modes: color.modes, unit_sizes: [128, 48, 48], }
  assert_false(av1_restoration_config_valid(bad_size))
  // A layout can never grow the upscaled width below the coded width.
  assert_true(
    av1_restoration_layout(color, 200, 100, 64, false, true, true, 8) is None,
  )
}

///|
test "coded-lossless superres frame stores an active restoration config" {
  // Y Switchable U128, U/V Wiener halved to U64. The q0 frame omits LF, CDEF
  // and tx_mode, but AllLossless is false so restoration syntax remains.
  let lr_fields = av1_superres_header_test_lr_fields([1, 2, 2], [1, 0], 1)
  let payload = av1_superres_header_test_payload(true, false, lr_fields)
  let header = av1_parse_stage1_frame(
    payload,
    av1_restoration_header_test_sequence(128),
  ).unwrap()
  let config = header.restoration.unwrap()
  assert_true(av1_restoration_active(config))
  assert_eq(config.modes, [
    Av1RestorationSwitchable,
    Av1RestorationWiener,
    Av1RestorationWiener,
  ])
  assert_eq(config.unit_sizes, [128, 64, 64])
  assert_eq(header.tile_payload, [b'\xa5'])
  assert_eq(header.header_bytes, payload.length() - 1)
  // SB128 selects the same sizes with one fewer luma bit.
  let sb128_fields = av1_superres_header_test_lr_fields([3, 3, 3], [0], 0)
  let header = av1_parse_stage1_frame(
    av1_superres_header_test_payload(true, false, sb128_fields),
    av1_restoration_header_test_sequence(128, use_128x128_superblock=true),
  ).unwrap()
  let config = header.restoration.unwrap()
  assert_eq(config.modes, [
    Av1RestorationSgrproj,
    Av1RestorationSgrproj,
    Av1RestorationSgrproj,
  ])
  assert_eq(config.unit_sizes, [128, 128, 128])
}

///|
test "chroma-only restoration halves units and omits the luma mode" {
  // Y None with U Wiener: the luma unit size is still signalled, and the
  // chroma halving bit applies because chroma is not all None.
  let lr_fields = av1_superres_header_test_lr_fields([0, 2, 0], [0], 1)
  let header = av1_parse_stage1_frame(
    av1_superres_header_test_payload(true, false, lr_fields),
    av1_restoration_header_test_sequence(128),
  ).unwrap()
  let config = header.restoration.unwrap()
  assert_true(av1_restoration_active(config))
  assert_eq(config.modes, [
    Av1RestorationNone,
    Av1RestorationWiener,
    Av1RestorationNone,
  ])
  assert_eq(config.unit_sizes, [64, 32, 32])
}

///|
test "disabled sequence restoration omits the frame syntax entirely" {
  // The payload carries no LR bits; the sequence gate must not invent any.
  let header = av1_parse_stage1_frame(
    av1_superres_header_test_payload(true, false, []),
    av1_restoration_header_test_sequence(128, enable_restoration=false),
  ).unwrap()
  assert_true(header.restoration is None)
  assert_eq(header.tile_payload, [b'\xa5'])
}

///|
test "monochrome restoration frame omits all UV syntax" {
  // Mono Wiener U64: three syntax bits total, no chroma modes or halving.
  let lr_fields = av1_superres_header_test_lr_fields([2], [0], -1)
  let header = av1_parse_stage1_frame(
    av1_superres_header_test_payload(true, true, lr_fields),
    av1_restoration_header_test_sequence(128, monochrome=true),
    allow_monochrome=true,
  ).unwrap()
  let config = header.restoration.unwrap()
  assert_eq(config.modes, [Av1RestorationWiener])
  assert_eq(config.unit_sizes, [64])
}
