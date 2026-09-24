///|
test "loop filter color levels precede signed reference and mode updates" {
  // Y=(0,32), UV=(48,0), sharpness=6, enabled+update; ref0=-64,
  // ref4=63, mode0=-1, mode1=0. A three-bit sentinel follows the 67-bit header.
  let reader : Av1FrameBits = {
    data: [
      b'\x02', b'\x0c', b'\x00', b'\xde', b'\x00', b'\xbf', b'\x1f', b'\xf0', b'\x14',
    ],
    bit_pos: 0,
  }
  let config = av1_parse_loop_filter_config(reader, false).unwrap()
  assert_eq(config.levels, [0, 32, 48, 0])
  assert_eq(config.sharpness, 6)
  assert_true(config.delta_enabled)
  assert_eq(config.ref_deltas, [-64, 0, 0, 0, 63, 0, -1, -1])
  assert_eq(config.mode_deltas, [-1, 0])
  assert_eq(reader.bit_pos, 67)
  assert_eq(reader.take(3), Some(5))
}

///|
test "loop filter monochrome omits UV and disabled deltas omit update" {
  let reader : Av1FrameBits = { data: [b'\x0d', b'\x84', b'\xc0'], bit_pos: 0, }
  let config = av1_parse_loop_filter_config(reader, true).unwrap()
  assert_eq(config.levels, [3, 24, 0, 0])
  assert_eq(config.sharpness, 2)
  assert_false(config.delta_enabled)
  assert_eq(config.ref_deltas, [1, 0, 0, 0, -1, 0, -1, -1])
  assert_eq(config.mode_deltas, [0, 0])
  assert_eq(reader.bit_pos, 16)
  assert_eq(reader.take(3), Some(6))
}

///|
test "zero luma levels omit UV while enabled unchanged deltas keep defaults" {
  let reader : Av1FrameBits = { data: [b'\x00', b'\x0f', b'\x30'], bit_pos: 0, }
  let config = av1_parse_loop_filter_config(reader, false).unwrap()
  assert_eq(config.levels, [0, 0, 0, 0])
  assert_eq(config.sharpness, 7)
  assert_true(config.delta_enabled)
  assert_eq(config.ref_deltas, [1, 0, 0, 0, -1, 0, -1, -1])
  assert_eq(reader.bit_pos, 17)
  assert_eq(reader.take(3), Some(3))
}

///|
test "loop filter cannot accept an incomplete signed update" {
  let reader : Av1FrameBits = {
    data: [b'\x02', b'\x0c', b'\x00', b'\xde'],
    bit_pos: 0,
  }
  assert_true(av1_parse_loop_filter_config(reader, false) is None)
}

///|
fn av1_loop_filter_test_config(
  levels : Array[Int],
  intra_delta : Int,
  enabled : Bool,
) -> Av1LoopFilterConfig {
  {
    levels,
    sharpness: 3,
    delta_enabled: enabled,
    ref_deltas: [intra_delta, 0, 0, 0, -1, 0, -1, -1],
    mode_deltas: [-64, 63],
  }
}

///|
test "intra strength uses per-plane gates and base-level delta scaling" {
  let config = av1_loop_filter_test_config([0, 32, 48, 0], 1, true)
  assert_eq(av1_loop_filter_intra_level(config, 0, 0), Some(1))
  assert_eq(av1_loop_filter_intra_level(config, 0, 1), Some(34))
  assert_eq(av1_loop_filter_intra_level(config, 1, 0), Some(50))
  assert_eq(av1_loop_filter_intra_level(config, 2, 0), Some(0))
  assert_eq(
    av1_loop_filter_intra_level(
      av1_loop_filter_test_config([0, 0, 0, 0], 63, true),
      0,
      0,
    ),
    Some(0),
  )
  for delta in [-64, 63] {
    let adjusted = av1_loop_filter_test_config([31, 32, 1, 1], delta, true)
    assert_eq(
      av1_loop_filter_intra_level(adjusted, 0, 1),
      Some(if delta < 0 { 0 } else { 63 }),
    )
  }
  let disabled = av1_loop_filter_test_config([0, 32, 48, 0], 63, false)
  assert_eq(av1_loop_filter_intra_level(disabled, 0, 0), Some(0))
  assert_eq(av1_loop_filter_intra_level(disabled, 0, 1), Some(32))
  assert_eq(av1_loop_filter_intra_level(config, 3, 0), None)
  assert_eq(av1_loop_filter_intra_level(config, 0, 2), None)
}
