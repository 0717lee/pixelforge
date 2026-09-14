///|
test "av1 tile payload helper preserves the legacy one-tile boundary" {
  let payload : Array[Byte] = [b'\x0A', b'\x05', b'\x7F']
  let tiles = av1_extract_tile_payloads(payload, 1, 1, 0).unwrap()
  assert_eq(tiles.length(), 1)
  assert_eq(tiles[0].index, 0)
  assert_eq(tiles[0].row, 0)
  assert_eq(tiles[0].col, 0)
  assert_eq(tiles[0].offset, 0)
  assert_eq(tiles[0].length, 3)
  assert_eq(tiles[0].bytes[2], b'\x7F')
}

///|
test "av1 tile payload helper splits prefixed tiles row major" {
  // 2x2 tiles, one-byte big-endian tile_size_minus_1 prefixes.  The first
  // three tiles have lengths 2, 1 and 3; the final tile consumes one byte.
  let payload : Array[Byte] = [
    b'\x01', b'\xA0', b'\xA1', b'\x00', b'\xB0', b'\x02', b'\xC0', b'\xC1', b'\xC2',
    b'\xD0',
  ]
  let tiles = av1_extract_tile_payloads(payload, 2, 2, 1).unwrap()
  assert_eq(tiles.length(), 4)
  assert_eq((tiles[0].row, tiles[0].col, tiles[0].length), (0, 0, 2))
  assert_eq((tiles[1].row, tiles[1].col, tiles[1].length), (0, 1, 1))
  assert_eq((tiles[2].row, tiles[2].col, tiles[2].length), (1, 0, 3))
  assert_eq((tiles[3].row, tiles[3].col, tiles[3].length), (1, 1, 1))
  assert_eq(tiles[2].bytes[1], b'\xC1')
}

///|
test "av1 tile payload helper rejects malformed size envelopes" {
  assert_true(av1_extract_tile_payloads([b'\x01', b'\xAA'], 2, 1, 1) is None)
  assert_true(
    av1_extract_tile_payloads([b'\x02', b'\xAA', b'\xBB'], 2, 1, 1) is None,
  )
  assert_true(av1_extract_tile_payloads([b'\xAA'], 2, 1, 0) is None)
  assert_true(av1_extract_tile_payloads([b'\xAA'], 0, 1, 1) is None)
  assert_true(av1_extract_tile_payloads([], 1, 1, 0) is None)
  assert_true(av1_extract_tile_payloads([b'\xAA'], 1, 1, 5) is None)
}
