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
  assert_eq(
    (header.tile_cols, header.tile_rows, header.tile_size_bytes),
    (1, 1, 0),
  )
  let tiles = av1_frame_tile_payloads(header).unwrap()
  assert_eq(tiles.length(), 1)
  assert_eq(tiles[0].bytes, header.tile_payload)
}

///|
/// A two-superblock reduced frame exercises the uniform tile_info() fields and
/// the tile_group_obu byte-alignment bit. The first tile is length two (the
/// one-byte tile_size_minus_1 prefix is 1); the final tile consumes the tail.
test "av1 parses a uniform two-tile reduced frame" {
  let seq = av1_sequence_info([
    b'\x0A', b'\x06', b'\x18', b'\x19', b'\x7F', b'\xFE', b'\x00', b'\x04',
  ]).unwrap()
  assert_eq((seq.width, seq.height), (128, 64))
  let frame : Array[Byte] = [
    b'\x18', b'\x80', b'\x00', b'\x00', b'\x02', b'\x00', b'\x01', b'\xA0', b'\xA1',
    b'\xB0',
  ]
  let header = av1_parse_stage1_frame(frame, seq).unwrap()
  assert_eq((header.tile_cols, header.tile_rows), (2, 1))
  assert_eq((header.tile_cols_log2, header.tile_rows_log2), (1, 0))
  assert_eq(header.tile_size_bytes, 1)
  assert_eq(header.tile_payload, [b'\x01', b'\xA0', b'\xA1', b'\xB0'])
  let tiles = av1_frame_tile_payloads(header).unwrap()
  assert_eq(tiles.length(), 2)
  assert_eq((tiles[0].row, tiles[0].col, tiles[0].length), (0, 0, 2))
  assert_eq((tiles[1].row, tiles[1].col, tiles[1].length), (0, 1, 1))
  assert_eq(tiles[0].bytes, [b'\xA0', b'\xA1'])
  assert_eq(tiles[1].bytes, [b'\xB0'])
}

///|
test "av1 parses nonuniform and rejects truncated multi-tile envelopes" {
  let seq = av1_sequence_info([
    b'\x0A', b'\x06', b'\x18', b'\x19', b'\x7F', b'\xFE', b'\x00', b'\x04',
  ]).unwrap()
  let frame : Array[Byte] = [
    b'\x18', b'\x80', b'\x00', b'\x00', b'\x02', b'\x00', b'\x01', b'\xA0', b'\xA1',
    b'\xB0',
  ]
  let nonuniform = frame.copy()
  nonuniform[0] = b'\x00'
  let nonuniform_header = av1_parse_stage1_frame(nonuniform, seq).unwrap()
  assert_eq((nonuniform_header.tile_cols, nonuniform_header.tile_rows), (2, 1))
  assert_eq(
    (nonuniform_header.tile_cols_log2, nonuniform_header.tile_rows_log2),
    (1, 0),
  )
  assert_eq(nonuniform_header.tile_col_starts_sb, [0, 1, 2])
  assert_eq(nonuniform_header.tile_row_starts_sb, [0, 1])
  assert_eq(nonuniform_header.tile_size_bytes, 1)
  let truncated : Array[Byte] = [
    b'\x18', b'\x80', b'\x00', b'\x00', b'\x02', b'\x00',
  ]
  assert_true(av1_parse_stage1_frame(truncated, seq) is None)
  let malformed_group = frame.copy()
  // Set tile_start_and_end_present and encode a partial [0, 0] range.
  malformed_group[5] = b'\x80'
  assert_true(av1_parse_stage1_frame(malformed_group, seq) is None)
  assert_true(
    av1_extract_tile_payloads([b'\x02', b'\xAA', b'\xBB'], 2, 1, 1) is None,
  )
}
