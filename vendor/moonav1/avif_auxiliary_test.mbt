///|
test "alpha descriptor rejects malformed extent references" {
  let malformed : Array[Byte] = [0, 0, 0, 8, 0x6D, 0x65, 0x74, 0x61]
  assert_true(avif_alpha_item_descriptor(malformed) is None)
}
