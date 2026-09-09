///|
test "av1 reduced still sequence header is parsed" {
  // OBU type 1, has_size_field=1, followed by a 20-bit profile 0,
  // reduced-still header describing a 2x2 8-bit 4:2:0 image.
  let obu : Array[Byte] = [b'\x0A', b'\x03', b'\x18', b'\x06', b'\x30']
  let info = av1_sequence_info(obu)
  match info {
    Some(v) => {
      assert_eq(v.profile, 0)
      assert_eq(v.width, 2)
      assert_eq(v.height, 2)
      assert_eq(v.bit_depth, 8)
      assert_false(v.monochrome)
      assert_true(v.subsampling_x)
      assert_true(v.subsampling_y)
      assert_true(v.reduced_still_picture_header)
    }
    None => assert_true(false)
  }
}

///|
test "av1 parser rejects malformed and unsupported sequence headers" {
  assert_true(av1_sequence_info([]) is None)
  // A valid OBU header with a truncated payload must fail safely.
  assert_true(av1_sequence_info([b'\x0A', b'\x01', b'\x18']) is None)
  // The pixel entry point does not claim a decoded image before tile entropy
  // decoding is implemented.
  assert_true(av1_decode([b'\x0A', b'\x03', b'\x18', b'\x06', b'\x60']) is None)
}

///|
test "av1 parser accepts a real reduced-still OBU prefix" {
  // Sequence OBU extracted from the repository's tiny AVIF fixture. The
  // following frame OBU is intentionally not decoded by this milestone.
  let av1 : Array[Byte] = [
    b'\x0A', b'\x07', b'\x38', b'\x00', b'\x36', b'\xD0', b'\x10', b'\xD0', b'\x02',
  ]
  let info = av1_sequence_info(av1)
  assert_true(info is Some(_))
}

///|
test "av1 reduced frame OBU is surfaced without fake pixels" {
  let data : Array[Byte] = [
    b'\x0A', b'\x07', b'\x38', b'\x00', b'\x36', b'\xD0', b'\x10', b'\xD0', b'\x02',
    b'\x32', b'\x2D', b'\x10', b'\x00', b'\x00', b'\x40', b'\x7F', b'\x30', b'\x24',
    b'\x03', b'\x50', b'\x96', b'\x14', b'\xA4', b'\xD2', b'\x93', b'\x4A', b'\x4E',
    b'\x4D', b'\x28', b'\x3F', b'\xFF', b'\xEB', b'\x66', b'\x2F', b'\x9B', b'\x70',
    b'\x7D', b'\xC1', b'\xF7', b'\x08', b'\x06', b'\x64', b'\x41', b'\xFF', b'\xC6',
    b'\xF8', b'\xC7', b'\xA7', b'\x86', b'\x12', b'\x89', b'\x4A', b'\x25', b'\x28',
    b'\x9C', b'\x70',
  ]
  let frame = av1_frame_info(data)
  match frame {
    Some(v) => {
      assert_true(v.key_frame)
      assert_true(v.show_frame)
      assert_eq(v.payload_size, 45)
    }
    None => assert_true(false)
  }
}

///|
test "av1 msac decoder normalizes and reads booleans" {
  assert_eq(av1_msac_read_first([b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'], 128), Some(0))
  assert_eq(av1_msac_read_first([b'\x7F', b'\x7F', b'\x7F', b'\x7F', b'\x7F'], 128), Some(1))
}
