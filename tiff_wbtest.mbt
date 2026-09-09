///|
test "tiff lzw bitstream decodes literal" {
  let decoded = tiff_lzw([b'\x80', b'\x13', b'\x60', b'\x20'], 0, 4, 1)
  assert_true(decoded is Some(values) && values[0] == b'\x4D')
}
