///|
/// A malformed root or child is rejected without allocating a partial image.
test "split tile decoder rejects non-split and truncated payloads" {
  assert_true(av1_decode_split_tile_64x64([], 32) is None)
  assert_true(av1_decode_split_tile_64x64([b'\x00', b'\x00'], 32) is None)
}
