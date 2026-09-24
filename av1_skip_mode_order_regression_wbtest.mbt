///|
fn av1_skip_order_test_prefix(
  order_hint : Int,
  hints : Array[Int],
) -> (Av1SequenceInfo, Av1FramePrefix) {
  let key = av1_inter_slice_bytes(inter_minimal_64x64_obu, 0, 69)
  let original_sequence = av1_sequence_info(key).unwrap()
  let prefix = av1_parse_frame_prefix(
    { data: av1_obu_payloads(key, 6)[0], bit_pos: 0, },
    original_sequence,
    Some(av1_frame_map()),
  ).unwrap()
  prefix.frame_is_intra = false
  prefix.order_hint = order_hint
  for i in 0..<7 {
    prefix.order_hints[i + 1] = hints[i]
  }
  (
    { ..original_sequence, enable_order_hint: true, order_hint_bits: 4, },
    prefix,
  )
}

///|
test "skip mode pairs the closest two earlier references and reads its flag" {
  // Current order 3, forward orders 2 and 1. Selecting the oldest (order 0)
  // would incorrectly conclude that a second earlier reference cannot exist.
  let (sequence, prefix) = av1_skip_order_test_prefix(3, [1, 0, 0, 2, 0, 0, 0])
  let reader : Av1FrameBits = { data: [b'\xD0'], bit_pos: 0, }
  let (present, frames) = av1_frame_skip_mode(reader, prefix, sequence, true).unwrap()
  assert_true(present)
  assert_eq(frames, [1, 4])
  assert_eq(reader.bit_pos, 1)
  assert_eq(reader.take(3), Some(5))
}

///|
test "skip mode picks the closest reference on each temporal side" {
  let (sequence, prefix) = av1_skip_order_test_prefix(3, [0, 4, 6, 2, 7, 1, 5])
  let reader : Av1FrameBits = { data: [b'\xD0'], bit_pos: 0, }
  let (present, frames) = av1_frame_skip_mode(reader, prefix, sequence, true).unwrap()
  assert_true(present)
  assert_eq(frames, [2, 4])
  assert_eq(reader.take(3), Some(5))
}

///|
test "skip mode compares circular order hints across wraparound" {
  let (sequence, prefix) = av1_skip_order_test_prefix(0, [
    15, 14, 1, 3, 13, 4, 0,
  ])
  let reader : Av1FrameBits = { data: [b'\xD0'], bit_pos: 0, }
  let (present, frames) = av1_frame_skip_mode(reader, prefix, sequence, true).unwrap()
  assert_true(present)
  assert_eq(frames, [1, 3])
  assert_eq(reader.take(3), Some(5))
}

///|
test "duplicate earlier references do not create a skip mode pair" {
  let (sequence, prefix) = av1_skip_order_test_prefix(3, [2, 2, 2, 2, 2, 2, 2])
  let reader : Av1FrameBits = { data: [b'\xD0'], bit_pos: 0, }
  let (present, _) = av1_frame_skip_mode(reader, prefix, sequence, true).unwrap()
  assert_false(present)
  assert_eq(reader.bit_pos, 0)
  assert_eq(reader.take(4), Some(13))
}
