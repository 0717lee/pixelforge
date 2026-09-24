/// CDEF frame syntax tests. Field transcripts exercise the uncompressed
/// header reader and preserve an explicit following-field marker.

///|
fn av1_cdef_header_test_bits(fields : Array[(Int, Int)]) -> Array[Int] {
  let bits : Array[Int] = []
  for field in fields {
    let (value, count) = field
    for i in 0..<count {
      bits.push((value >> (count - i - 1)) & 1)
    }
  }
  bits
}

///|
fn av1_cdef_header_test_pack(bits : Array[Int], prefix : Int) -> Array[Byte] {
  let bytes : Array[Byte] = Array::make(
    (prefix + bits.length() + 7) / 8,
    b'\x00',
  )
  for i in 0..<bits.length() {
    let offset = prefix + i
    let value = bytes[offset / 8].to_int() | (bits[i] << (7 - offset % 8))
    bytes[offset / 8] = value.to_byte()
  }
  bytes
}

///|
/// Place the last supplied bit at a byte boundary so a truncated transcript
/// has exactly its stated number of readable bits, with no trailing padding.
fn av1_cdef_header_test_reader(bits : Array[Int]) -> Av1FrameBits {
  let prefix = (8 - bits.length() % 8) % 8
  { data: av1_cdef_header_test_pack(bits, prefix), bit_pos: prefix, }
}

///|
fn av1_cdef_header_test_fields(
  bits : Int,
  damping : Int,
  monochrome : Bool,
) -> Array[(Int, Int)] {
  let fields = [(damping - 3, 2), (bits, 2)]
  for i in 0..<(1 << bits) {
    fields.push((i, 4))
    fields.push((i % 4, 2))
    if !monochrome {
      fields.push((15 - i, 4))
      fields.push(((i + 1) % 4, 2))
    }
  }
  fields
}

///|
test "CDEF header remaps both secondary strength code threes" {
  // 11 00 1111 11 1110 11: damping=6, bits=0, Y=(15,3), UV=(14,3).
  let reader : Av1FrameBits = { data: [b'\xcf', b'\xfb'], bit_pos: 0, }
  let config = av1_parse_cdef_config(reader, false).unwrap()
  assert_eq(config.bits, 0)
  assert_eq(config.damping, 6)
  assert_eq(config.y_primary, [15])
  assert_eq(config.y_secondary, [4])
  assert_eq(config.uv_primary, [14])
  assert_eq(config.uv_secondary, [4])
  assert_eq(reader.bit_pos, 16)
  assert_true(av1_cdef_config_valid(config))
}

///|
test "CDEF header parses every table size damping and plane count" {
  for bits in 0..<4 {
    for damping in 3..<7 {
      for monochrome in [false, true] {
        let fields = av1_cdef_header_test_fields(bits, damping, monochrome)
        fields.push((5, 3))
        let reader = av1_cdef_header_test_reader(
          av1_cdef_header_test_bits(fields),
        )
        let config = av1_parse_cdef_config(reader, monochrome).unwrap()
        assert_eq(config.bits, bits)
        assert_eq(config.damping, damping)
        assert_eq(config.y_primary.length(), 1 << bits)
        for i in 0..<(1 << bits) {
          assert_eq(config.y_primary[i], i)
          assert_eq(config.y_secondary[i], [0, 1, 2, 4][i % 4])
          if !monochrome {
            assert_eq(config.uv_primary[i], 15 - i)
            assert_eq(config.uv_secondary[i], [0, 1, 2, 4][(i + 1) % 4])
          }
        }
        if monochrome {
          assert_eq(config.uv_primary.length(), 0)
          assert_eq(config.uv_secondary.length(), 0)
        }
        assert_true(av1_cdef_config_valid(config, monochrome~))
        assert_eq(reader.take(3), Some(5))
      }
    }
  }
}

///|
test "CDEF header rejects truncation at every field bit" {
  for monochrome in [false, true] {
    let complete = av1_cdef_header_test_bits(
      av1_cdef_header_test_fields(3, 5, monochrome),
    )
    for length in 0..<complete.length() {
      let prefix : Array[Int] = []
      for i in 0..<length {
        prefix.push(complete[i])
      }
      assert_true(
        av1_parse_cdef_config(av1_cdef_header_test_reader(prefix), monochrome)
        is None,
      )
    }
    assert_true(
      av1_parse_cdef_config(av1_cdef_header_test_reader(complete), monochrome)
      is Some(_),
    )
  }
}

///|
test "CDEF config validation checks header ranges and every array length" {
  for bits in [-1, 4] {
    assert_false(
      av1_cdef_config_valid({
        bits,
        damping: 3,
        y_primary: [0],
        y_secondary: [0],
        uv_primary: [0],
        uv_secondary: [0],
      }),
    )
  }
  for damping in [2, 7] {
    assert_false(
      av1_cdef_config_valid({
        bits: 0,
        damping,
        y_primary: [0],
        y_secondary: [0],
        uv_primary: [0],
        uv_secondary: [0],
      }),
    )
  }
  for lengths in [(1, 2, 2, 2), (2, 1, 2, 2), (2, 2, 1, 2), (2, 2, 2, 1)] {
    let (yp, ys, up, us) = lengths
    assert_false(
      av1_cdef_config_valid({
        bits: 1,
        damping: 3,
        y_primary: Array::make(yp, 0),
        y_secondary: Array::make(ys, 0),
        uv_primary: Array::make(up, 0),
        uv_secondary: Array::make(us, 0),
      }),
    )
  }
  for strength in [-1, 16] {
    assert_false(
      av1_cdef_config_valid({
        bits: 0,
        damping: 3,
        y_primary: [strength],
        y_secondary: [0],
        uv_primary: [0],
        uv_secondary: [0],
      }),
    )
    assert_false(
      av1_cdef_config_valid({
        bits: 0,
        damping: 3,
        y_primary: [0],
        y_secondary: [0],
        uv_primary: [strength],
        uv_secondary: [0],
      }),
    )
  }
  for strength in [-1, 3, 5] {
    assert_false(
      av1_cdef_config_valid({
        bits: 0,
        damping: 3,
        y_primary: [0],
        y_secondary: [strength],
        uv_primary: [0],
        uv_secondary: [0],
      }),
    )
    assert_false(
      av1_cdef_config_valid({
        bits: 0,
        damping: 3,
        y_primary: [0],
        y_secondary: [0],
        uv_primary: [0],
        uv_secondary: [strength],
      }),
    )
  }
  let monochrome : Av1CdefConfig = {
    bits: 0,
    damping: 3,
    y_primary: [15],
    y_secondary: [4],
    uv_primary: [],
    uv_secondary: [],
  }
  assert_true(av1_cdef_config_valid(monochrome, monochrome=true))
  assert_false(av1_cdef_config_valid(monochrome))
  assert_false(
    av1_cdef_config_valid(
      {
        bits: 0,
        damping: 3,
        y_primary: [0],
        y_secondary: [0],
        uv_primary: [0],
        uv_secondary: [0],
      },
      monochrome=true,
    ),
  )
}

///|
fn av1_cdef_header_test_sequence(
  enable_cdef : Bool,
  monochrome? : Bool = false,
  enable_restoration? : Bool = false,
) -> Av1SequenceInfo {
  {
    ..av1_reduced_still_sequence,
    profile: 0,
    width: 64,
    height: 64,
    bit_depth: 8,
    monochrome,
    subsampling_x: true,
    subsampling_y: true,
    use_128x128_superblock: false,
    enable_filter_intra: false,
    enable_intra_edge_filter: false,
    enable_superres: false,
    enable_cdef,
    enable_restoration,
    full_range: false,
    color_primaries: 1,
    transfer_characteristics: 1,
    matrix_coefficients: 6,
  }
}

///|
/// Synthetic reduced-still, single-tile frame envelope. The final byte is a
/// tile-data marker; this test parses headers without decoding its contents.
fn av1_cdef_header_test_frame(
  base_q_idx : Int,
  cdef_fields : Array[(Int, Int)],
  monochrome? : Bool = false,
  enable_restoration? : Bool = false,
) -> Array[Byte] {
  let fields = [
    (0, 1),
    (0, 1),
    (0, 1),
    (1, 1), // CDF update, tools, render size, uniform tile.
    (base_q_idx, 8),
    (0, 1), // Y DC quantizer delta.
  ]
  if !monochrome {
    fields.push((0, 1)) // U DC delta.
    fields.push((0, 1)) // U AC delta; V inherits U with separate_uv_delta_q=0.
  }
  fields.push((0, 1)) // using_qmatrix
  fields.push((0, 1)) // segmentation_enabled
  if base_q_idx > 0 {
    fields.push((0, 1)) // delta_q_present
    fields.push((0, 6)) // loop_filter_level[0]
    fields.push((0, 6)) // loop_filter_level[1]
    fields.push((0, 3)) // sharpness
    fields.push((0, 1)) // loop_filter_delta_enabled
    for field in cdef_fields {
      fields.push(field)
    }
    if enable_restoration {
      let num_planes = if monochrome { 1 } else { 3 }
      for _ in 0..<num_planes {
        fields.push((0, 2))
      }
    }
    fields.push((1, 1)) // tx_mode_select
    fields.push((1, 1)) // reduced_tx_set
  } else {
    fields.push((0, 1)) // reduced_tx_set; CDEF and tx_mode omitted for lossless.
  }
  let payload = av1_cdef_header_test_pack(av1_cdef_header_test_bits(fields), 0)
  payload.push(b'\x71')
  payload
}

///|
test "CDEF frame envelope preserves enabled config and following tile bytes" {
  let fields = av1_cdef_header_test_fields(2, 6, false)
  let payload = av1_cdef_header_test_frame(96, fields)
  let frame = av1_parse_stage1_frame(
    payload,
    av1_cdef_header_test_sequence(true),
  ).unwrap()
  let config = frame.cdef.unwrap()
  assert_eq(config.bits, 2)
  assert_eq(config.damping, 6)
  assert_eq(config.y_primary, [0, 1, 2, 3])
  assert_eq(config.y_secondary, [0, 1, 2, 4])
  assert_eq(config.uv_primary, [15, 14, 13, 12])
  assert_eq(config.uv_secondary, [1, 2, 4, 0])
  assert_true(frame.tx_mode_select)
  assert_true(frame.reduced_tx_set)
  assert_eq(frame.header_bytes, payload.length() - 1)
  assert_eq(frame.tile_payload, [b'\x71'])
}

///|
test "CDEF frame envelope omits config when disabled or coded lossless" {
  let disabled = av1_parse_stage1_frame(
    av1_cdef_header_test_frame(96, []),
    av1_cdef_header_test_sequence(false),
  ).unwrap()
  assert_true(disabled.cdef is None)
  assert_false(disabled.coded_lossless)
  assert_true(disabled.tx_mode_select)
  for enabled in [false, true] {
    let lossless = av1_parse_stage1_frame(
      av1_cdef_header_test_frame(0, []),
      av1_cdef_header_test_sequence(enabled),
    ).unwrap()
    assert_true(lossless.cdef is None)
    assert_true(lossless.coded_lossless)
    assert_eq(lossless.tile_payload, [b'\x71'])
  }
}

///|
test "monochrome frame syntax omits UV quantization and restoration fields" {
  for enabled in [false, true] {
    for enable_restoration in [false, true] {
      for base_q_idx in [0, 96] {
        let cdef_fields = if enabled && base_q_idx != 0 {
          [(0, 2), (0, 2), (0, 4), (0, 2)] // damping=3, bits=0, zero Y strengths.
        } else {
          []
        }
        let payload = av1_cdef_header_test_frame(
          base_q_idx,
          cdef_fields,
          monochrome=true,
          enable_restoration~,
        )
        let sequence = av1_cdef_header_test_sequence(
          enabled,
          monochrome=true,
          enable_restoration~,
        )
        let frame = av1_parse_stage1_frame(
          payload,
          sequence,
          allow_monochrome=true,
        ).unwrap()
        assert_eq(frame.base_q_idx, base_q_idx)
        assert_eq(frame.coded_lossless, base_q_idx == 0)
        assert_eq(frame.tx_mode_select, base_q_idx != 0)
        assert_eq(frame.reduced_tx_set, base_q_idx != 0)
        assert_eq(frame.header_bytes, payload.length() - 1)
        assert_eq(frame.tile_payload, [b'\x71'])
        if enabled && base_q_idx != 0 {
          let config = frame.cdef.unwrap()
          assert_eq(config.bits, 0)
          assert_eq(config.damping, 3)
          assert_eq(config.y_primary, [0])
          assert_eq(config.y_secondary, [0])
          assert_eq(config.uv_primary, [])
          assert_eq(config.uv_secondary, [])
        } else {
          assert_true(frame.cdef is None)
        }
      }
    }
  }
}
