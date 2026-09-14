///|
test "av1 parses the reduced still frame tile boundary" {
  let frame : Array[Byte] = [
    b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00', b'\x0A',
    b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46', b'\x02',
    b'\x28',
  ]
  let seq = av1_sequence_info([
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
  ]).unwrap()
  let header = av1_parse_stage1_frame(frame, seq).unwrap()
  assert_eq(header.header_bytes, 8)
  assert_eq(header.tile_payload[0], b'\x0A')
  assert_eq(header.tile_payload.length(), 11)
  assert_eq((header.tile_cols, header.tile_rows, header.tile_size_bytes), (1, 1, 0))
  let tiles = av1_frame_tile_payloads(header).unwrap()
  assert_eq(tiles.length(), 1)
  assert_eq(tiles[0].bytes, header.tile_payload)
}
