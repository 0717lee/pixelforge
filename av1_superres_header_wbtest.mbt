///|
fn av1_superres_header_test_sequence(
  width : Int,
  monochrome : Bool,
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
    use_128x128_superblock: false,
    enable_filter_intra: false,
    enable_intra_edge_filter: false,
    enable_superres: true,
    enable_cdef: true,
    enable_restoration: true,
    full_range: true,
    separate_uv_delta_q: false,
    film_grain_params_present: false,
    color_primaries: 1,
    transfer_characteristics: 1,
    matrix_coefficients: 6,
  }
}

///|
/// Loop-restoration header fields for a superres frame: the two-bit mode
/// codes per plane, then the unit-size bits that follow whenever any plane
/// is active. `luma_bits` are the SB64/SB128 unit header bits in order; a
/// negative `chroma_bit` omits the 4:2:0 halving bit.
fn av1_superres_header_test_lr_fields(
  lr_types : Array[Int],
  luma_bits : Array[Int],
  chroma_bit : Int,
) -> Array[(Int, Int)] {
  let fields : Array[(Int, Int)] = []
  for lr_type in lr_types {
    fields.push((lr_type, 2))
  }
  let mut active = false
  for lr_type in lr_types {
    if lr_type != 0 {
      active = true
    }
  }
  if active {
    for bit in luma_bits {
      fields.push((bit, 1))
    }
    if chroma_bit >= 0 {
      fields.push((chroma_bit, 1))
    }
  }
  fields
}

///|
/// Lossless-transform header with screen tools, optional scaling and
/// configurable LR syntax. The marker is tile data only; these tests do not
/// claim entropy decoding.
fn av1_superres_header_test_payload(
  active : Bool,
  monochrome : Bool,
  lr_fields : Array[(Int, Int)],
) -> Array[Byte] {
  let fields = [(0, 1), (1, 1), (1, 1), (if active { 1 } else { 0 }, 1)]
  if active {
    fields.push((7, 3))
  } // denominator16.
  fields.push((0, 1)) // render size defaults to upscaled width.
  if !active {
    fields.push((0, 1))
  } // allow_intrabc is absent for scaling.
  fields.push((1, 1)) // uniform tile; coded width64 needs no column bits.
  fields.push((0, 8)) // q0.
  fields.push((0, 1)) // Y DC delta.
  if !monochrome {
    fields.push((0, 1))
    fields.push((0, 1))
  }
  fields.push((0, 1)) // qmatrix.
  fields.push((0, 1)) // segmentation.
  // CodedLossless skips delta-Q, loop filter, CDEF and tx_mode syntax.
  // AllLossless is false with scaling, so LR syntax is still present.
  if active {
    for field in lr_fields {
      fields.push(field)
    }
  }
  fields.push((1, 1)) // reduced_tx_set is always present.
  let bytes = av1_cdef_header_test_pack(av1_cdef_header_test_bits(fields), 0)
  bytes.push(b'\xa5')
  bytes
}

///|
test "superres q0 header uses coded tile width and still reads restoration" {
  for monochrome in [false, true] {
    let lr_fields = if monochrome {
      av1_superres_header_test_lr_fields([0], [], -1)
    } else {
      av1_superres_header_test_lr_fields([0, 0, 0], [], -1)
    }
    let payload = av1_superres_header_test_payload(true, monochrome, lr_fields)
    let header = av1_parse_stage1_frame(
      payload,
      av1_superres_header_test_sequence(128, monochrome),
      allow_monochrome=true,
    ).unwrap()
    assert_eq(
      (header.frame_width, header.upscaled_width, header.superres_denom),
      (64, 128, 16),
    )
    assert_eq(header.tile_col_starts_sb, [0, 1])
    assert_eq(header.tile_cols_log2, 0)
    assert_eq(header.tile_payload, [b'\xa5'])
    assert_eq(header.header_bytes, payload.length() - 1)
    assert_true(
      header.coded_lossless &&
      header.reduced_tx_set &&
      header.allow_screen_content_tools,
    )
    assert_false(header.tx_mode_select)
    assert_true(header.cdef is None && header.loop_filter is None)
    // All-None LR still stores a configuration with the implicit U256.
    let config = header.restoration.unwrap()
    assert_false(av1_restoration_active(config))
    for size in config.unit_sizes {
      assert_eq(size, 256)
    }
  }
}

///|
test "superres disabled header retains intrabc bit and omits all lossless LR" {
  for monochrome in [false, true] {
    let header = av1_parse_stage1_frame(
      av1_superres_header_test_payload(false, monochrome, []),
      av1_superres_header_test_sequence(64, monochrome),
      allow_monochrome=true,
    ).unwrap()
    assert_eq(
      (header.frame_width, header.upscaled_width, header.superres_denom),
      (64, 64, 8),
    )
    assert_eq(header.tile_payload, [b'\xa5'])
    assert_true(header.coded_lossless && header.reduced_tx_set)
    // An all-lossless frame omits restoration syntax entirely.
    assert_true(header.restoration is None)
  }
}

///|
test "superres header rejects dimensions without per plane growth or valid bounds" {
  let lr_fields = av1_superres_header_test_lr_fields([0, 0, 0], [], -1)
  let payload = av1_superres_header_test_payload(true, false, lr_fields)
  for width in [0, 1, 2, 65537, 2147483647] {
    assert_true(
      av1_parse_stage1_frame(
        payload,
        av1_superres_header_test_sequence(width, false),
      )
      is None,
    )
  }
  assert_true(
    av1_parse_stage1_frame(
      payload,
      av1_superres_header_test_sequence(1, true),
      allow_monochrome=true,
    )
    is None,
  )
}
