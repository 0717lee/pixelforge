///|
test "frame OBU aligns before and after its tile group header" {
  // Three frame-header bits, five zero alignment bits; then the group flag
  // and seven zero alignment bits precede the two tile payloads.
  let payload : Array[Byte] = [b'\xA0', b'\x00', b'\x00', b'\x71', b'\x72']
  let (offset, data) = av1_frame_tile_group_payload(payload, 3, 2, 1).unwrap()
  assert_eq(offset, 2)
  assert_eq(data, [b'\x00', b'\x71', b'\x72'])
}

///|
test "frame OBU rejects nonzero alignment and missing group bytes" {
  assert_true(
    av1_frame_tile_group_payload([b'\xA1', b'\x00', b'\x71'], 3, 2, 1) is None,
  )
  assert_true(
    av1_frame_tile_group_payload([b'\xA0', b'\x01', b'\x71'], 3, 2, 1) is None,
  )
  assert_true(av1_frame_tile_group_payload([b'\xA0'], 3, 2, 1) is None)
  assert_true(av1_frame_tile_group_payload([b'\xA0', b'\x00'], 3, 2, 1) is None)
  // Even a complete explicit range is forbidden in OBU_FRAME.
  assert_true(
    av1_frame_tile_group_payload([b'\xA0', b'\xA0', b'\x71'], 3, 2, 1) is None,
  )
}
