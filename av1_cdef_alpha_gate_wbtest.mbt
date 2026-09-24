/// Alpha compatibility checks through the complete OBU/frame entry point.
/// The base sequence and entropy payload are the existing accepted alpha
/// fixture. Only the sequence CDEF flag and frame CDEF fields are changed.

///|
fn av1_cdef_alpha_test_stream(
  bits : Int,
  primary : Int,
  secondary_code : Int,
  damping : Int,
) -> Array[Byte] {
  // Reproduce the valid fixture's normative monochrome header fields.
  // It has no U/V quantizer deltas; loop-filter delta_enabled is 1 and its
  // update flag is 0. Build the syntax rather than splice at a bit offset.
  let fields = [
    (0, 1),
    (0, 1),
    (0, 1),
    (1, 1), // CDF update, tools, render, uniform tile.
    (80, 8),
    (0, 1), // Base quantizer and Y DC delta flag.
    (0, 1),
    (0, 1),
    (0, 1), // Qmatrix, segmentation, delta-Q.
    (0, 6),
    (0, 6),
    (0, 3), // Luma vertical/horizontal LF and sharpness.
    (1, 1),
    (0, 1), // Loop-filter delta enabled, no delta update.
    (damping - 3, 2),
    (bits, 2),
  ]
  for _ in 0..<(1 << bits) {
    fields.push((primary, 4))
    fields.push((secondary_code, 2))
  }
  fields.push((0, 1)) // Existing tx_mode_select remains false.
  fields.push((0, 1)) // Existing reduced_tx_set remains false.
  let frame = av1_cdef_header_test_pack(av1_cdef_header_test_bits(fields), 0)
  frame.push(b'\x44') // Unchanged, accepted alpha tile entropy.
  let stream : Array[Byte] = [
    b'\x12',
    b'\x00',
    b'\x0a',
    b'\x06',
    b'\x18',
    b'\x15',
    b'\x7f',
    b'\xfe',
    b'\x24',
    b'\x40', // Original 0x04 with enable_cdef's bit 0x20 set.
    b'\x32',
    frame.length().to_byte(),
  ]
  for byte in frame {
    stream.push(byte)
  }
  stream
}

///|
fn av1_cdef_alpha_test_header(stream : Array[Byte]) -> Av1FrameHeaderInfo {
  let sequence = av1_sequence_info(stream).unwrap()
  let frames = av1_obu_payloads(stream, 6)
  av1_parse_stage1_frame(
    frames[0],
    sequence,
    allow_monochrome=true,
    allow_highbd=true,
  ).unwrap()
}

///|
test "alpha preserves CDEF disabled and zero-strength single-entry frames" {
  let original : Array[Byte] = [
    b'\x12', b'\x00', b'\x0a', b'\x06', b'\x18', b'\x15', b'\x7f', b'\xfe', b'\x04',
    b'\x40', b'\x32', b'\x06', b'\x15', b'\x00', b'\x00', b'\x01', b'\x00', b'\x44',
  ]
  assert_true(av1_cdef_alpha_test_header(original).cdef is None)
  let expected = av1_decode_alpha(original).unwrap()
  assert_eq(expected.length(), 4096)
  for alpha in expected {
    assert_eq(alpha, b'\x80')
  }
  for damping in 3..<7 {
    let stream = av1_cdef_alpha_test_stream(0, 0, 0, damping)
    // These exact four streams were independently decoded by FFmpeg to
    // 4096 gray samples, all 128. Keep the bit writer tied to those bytes.
    let verified : Array[Byte] = [
      b'\x12', b'\x00', b'\x0a', b'\x06', b'\x18', b'\x15', b'\x7f', b'\xfe', b'\x24',
      b'\x40', b'\x32', b'\x07', b'\x15', b'\x00', b'\x00', b'\x01',
    ]
    verified.push([b'\x00', b'\x20', b'\x40', b'\x60'][damping - 3])
    verified.push(b'\x00')
    verified.push(b'\x44')
    assert_eq(stream, verified)
    let sequence = av1_sequence_info(stream).unwrap()
    assert_true(sequence.monochrome)
    assert_true(sequence.enable_cdef)
    let frame = av1_cdef_alpha_test_header(stream)
    let config = frame.cdef.unwrap()
    assert_eq(config.damping, damping)
    assert_eq(config.bits, 0)
    assert_eq(config.y_primary, [0])
    assert_eq(config.y_secondary, [0])
    assert_eq(config.uv_primary, [])
    assert_eq(config.uv_secondary, [])
    assert_eq(frame.tile_payload, [b'\x44'])
    assert_false(frame.tx_mode_select)
    assert_false(frame.reduced_tx_set)
    assert_eq(av1_decode_alpha(stream).unwrap(), expected)
  }
}

///|
test "alpha decodes CDEF index entropy past the payload end from padding zero bits" {
  for bits in 1..<4 {
    let stream = av1_cdef_alpha_test_stream(bits, 0, 0, 3)
    let frame = av1_cdef_alpha_test_header(stream)
    let config = frame.cdef.unwrap()
    assert_true(av1_cdef_config_valid(config, monochrome=true))
    assert_eq(config.bits, bits)
    assert_eq(config.y_primary.length(), 1 << bits)
    assert_eq(frame.tile_payload, [b'\x44'])
    // The isolated entropy is valid without CDEF index syntax. With index
    // bits required the payload runs out, and AV1 8.2 defines the values
    // read past its end as padding zero bits, so the symbol walk completes.
    // libdav1d accepts the very same stream: it emits a 4096-sample plane
    // whose bytes are exactly these.
    let alpha = av1_decode_alpha(stream).unwrap()
    assert_eq(alpha.length(), 4096)
    let expected = [(129, 128), (129, 129), (127, 127)]
    assert_eq((alpha[0].to_int(), alpha[9].to_int()), expected[bits - 1])
  }
}

///|
test "alpha decodes primary and secondary CDEF strengths on a constant plane" {
  for strengths in [(1, 0), (0, 1), (0, 2), (0, 3), (15, 3)] {
    let (primary, secondary_code) = strengths
    let stream = av1_cdef_alpha_test_stream(0, primary, secondary_code, 4)
    let frame = av1_cdef_alpha_test_header(stream)
    let config = frame.cdef.unwrap()
    assert_eq(config.bits, 0)
    assert_eq(config.y_primary, [primary])
    assert_eq(config.y_secondary, [
      if secondary_code == 3 {
        4
      } else {
        secondary_code
      },
    ])
    assert_eq(frame.tile_payload, [b'\x44'])
    // These five streams were independently decoded by libdav1d: all
    // 4096 samples remain 128 because every reconstructed neighbour agrees.
    let alpha = av1_decode_alpha(stream).unwrap()
    assert_eq(alpha.length(), 4096)
    for value in alpha {
      assert_eq(value, b'\x80')
    }
  }
}
