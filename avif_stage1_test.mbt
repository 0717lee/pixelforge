///|
test "avif stage one extracts a real 8-bit 4:2:0 tile" {
  let data : Array[Byte] = [
    b'\x00', b'\x00', b'\x00', b'\x20', b'\x66', b'\x74', b'\x79', b'\x70', b'\x61',
    b'\x76', b'\x69', b'\x66', b'\x00', b'\x00', b'\x00', b'\x00', b'\x61', b'\x76',
    b'\x69', b'\x66', b'\x6D', b'\x69', b'\x66', b'\x31', b'\x6D', b'\x69', b'\x61',
    b'\x66', b'\x4D', b'\x41', b'\x31', b'\x42', b'\x00', b'\x00', b'\x00', b'\xF9',
    b'\x6D', b'\x65', b'\x74', b'\x61', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x2F', b'\x68', b'\x64', b'\x6C', b'\x72', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x70', b'\x69', b'\x63',
    b'\x74', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x50', b'\x69', b'\x63', b'\x74', b'\x75',
    b'\x72', b'\x65', b'\x48', b'\x61', b'\x6E', b'\x64', b'\x6C', b'\x65', b'\x72',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x0E', b'\x70', b'\x69', b'\x74', b'\x6D',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x1E', b'\x69', b'\x6C', b'\x6F', b'\x63', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x44', b'\x00', b'\x00', b'\x01', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x00', b'\x00', b'\x01', b'\x21', b'\x00', b'\x00', b'\x00', b'\x13',
    b'\x00', b'\x00', b'\x00', b'\x28', b'\x69', b'\x69', b'\x6E', b'\x66', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x1A',
    b'\x69', b'\x6E', b'\x66', b'\x65', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x00', b'\x00', b'\x61', b'\x76', b'\x30', b'\x31', b'\x43', b'\x6F',
    b'\x6C', b'\x6F', b'\x72', b'\x00', b'\x00', b'\x00', b'\x00', b'\x6A', b'\x69',
    b'\x70', b'\x72', b'\x70', b'\x00', b'\x00', b'\x00', b'\x4B', b'\x69', b'\x70',
    b'\x63', b'\x6F', b'\x00', b'\x00', b'\x00', b'\x14', b'\x69', b'\x73', b'\x70',
    b'\x65', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x40',
    b'\x00', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00', b'\x10', b'\x70',
    b'\x69', b'\x78', b'\x69', b'\x00', b'\x00', b'\x00', b'\x00', b'\x03', b'\x08',
    b'\x08', b'\x08', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x61', b'\x76', b'\x31',
    b'\x43', b'\x81', b'\x00', b'\x0C', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13',
    b'\x63', b'\x6F', b'\x6C', b'\x72', b'\x6E', b'\x63', b'\x6C', b'\x78', b'\x00',
    b'\x02', b'\x00', b'\x02', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x17', b'\x69', b'\x70', b'\x6D', b'\x61', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x01', b'\x04', b'\x01', b'\x02',
    b'\x83', b'\x04', b'\x00', b'\x00', b'\x00', b'\x1B', b'\x6D', b'\x64', b'\x61',
    b'\x74', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xA0', b'\x08',
    b'\x32', b'\x09', b'\x10', b'\x00', b'\x00', b'\x00', b'\x4A', b'\x7D', b'\xF7',
    b'\xFF', b'\xFF',
  ]
  let c = avif_container_parse(data).unwrap()
  assert_eq((c.width, c.height, c.bit_depth), (64, 64, 8))
  assert_true(c.yuv420)
  let seq = av1_sequence_info(c.payload).unwrap()
  assert_eq((seq.width, seq.height, seq.bit_depth), (64, 64, 8))
  let frame_info = av1_frame_info(c.payload).unwrap()
  assert_true(frame_info.payload_size > 0)
  let input = avif_stage1_input(data).unwrap()
  assert_eq((input.width, input.height, input.bit_depth), (64, 64, 8))
  assert_true(input.tile_payload.length() > 0)
  assert_eq(input.base_q_idx, 0)

  // An alpha association belongs to the container boundary, not to the
  // primary AV1 tile validator. Re-tag the fixture's colour property as the
  // auxiliary association marker and make sure the primary stage still
  // reaches the tile handoff. Auxiliary payload validation remains a separate
  // responsibility of `avif_decode_rgba`.
  let alpha_marked = data.copy()
  let mut marked = false
  for i in 0..<(alpha_marked.length() - 4) {
    if alpha_marked[i] == b'c' && alpha_marked[i + 1] == b'o' &&
      alpha_marked[i + 2] == b'l' && alpha_marked[i + 3] == b'r' {
      alpha_marked[i] = b'a'
      alpha_marked[i + 1] = b'u'
      alpha_marked[i + 2] = b'x'
      alpha_marked[i + 3] = b'C'
      marked = true
      break
    }
  }
  assert_true(marked)
  let alpha_container = avif_container_parse(alpha_marked).unwrap()
  assert_true(alpha_container.has_alpha)
  assert_true(avif_stage1_input(alpha_marked) is Some(_))

  // Replace only the 19-byte mdat payload with the canonical flat AV1 frame
  // (same item length) to exercise the AVIF container -> tile -> RGBA path.
  let canonical = data.copy()
  let start = canonical.length() - 19
  let flat : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x09', b'\x12', b'\xB0', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00',
    b'\x2E',
  ]
  for i in 0..<flat.length() {
    canonical[start + i] = flat[i]
  }
  let decoded = avif_decode(canonical).unwrap()
  assert_eq(decoded.get_pixel(0, 0), (b'\x82', b'\x82', b'\x82', b'\xFF'))
}
