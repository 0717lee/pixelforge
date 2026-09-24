///|
fn av1_identity_test_prefix() -> (Av1SequenceInfo, Av1FramePrefix) {
  let (sequence, prefix) = av1_skip_order_test_prefix(0, [0, 0, 0, 0, 0, 0, 0])
  prefix.current_frame_id = 0
  prefix.frame_size_override_flag = 0
  prefix.force_integer_mv = 1
  (
    {
      ..sequence,
      reduced_still_picture_header: false,
      decoder_model_info_present: false,
      seq_force_screen_content_tools: 0,
      enable_order_hint: false,
      order_hint_bits: 0,
      enable_superres: false,
      enable_ref_frame_mvs: false,
      frame_id_numbers_present: true,
      delta_frame_id_length_minus_2: 0,
      additional_frame_id_length_minus_1: 0,
    },
    prefix,
  )
}

///|
test "frame identity lengths accept sixteen bits and reject invalid widths" {
  let (sequence, _) = av1_identity_test_prefix()
  assert_eq(av1_frame_id_lengths(sequence), Some((2, 3)))
  assert_eq(
    av1_frame_id_lengths({ ..sequence, delta_frame_id_length_minus_2: 13, }),
    Some((15, 16)),
  )
  for
    invalid in [
      { ..sequence, delta_frame_id_length_minus_2: -1, },
      { ..sequence, additional_frame_id_length_minus_1: -1, },
      { ..sequence, delta_frame_id_length_minus_2: 14, },
      {
        ..sequence,
        delta_frame_id_length_minus_2: 13,
        additional_frame_id_length_minus_1: 1,
      },
    ] {
    assert_true(av1_frame_id_lengths(invalid) is None)
  }
}

///|
test "frame identity marking retains both window endpoints across wrap" {
  // diffLen=2, idLen=3: the inclusive reference age window is 0..4.
  for
    item in [
      (5, [false, true, true, true, true, true, false, false]),
      (4, [true, true, true, true, true, false, false, false]),
      (0, [true, false, false, false, true, true, true, true]),
    ] {
    let (current, expected) = item
    let map = av1_frame_map()
    for slot in 0..<8 {
      map.valid[slot] = true
      map.frame_ids[slot] = slot
    }
    av1_frame_mark_refs(map, current, 2, 3)
    assert_eq(map.valid, expected)
    assert_eq(map.frame_ids, [0, 1, 2, 3, 4, 5, 6, 7])
  }
  let invalid = av1_frame_map()
  invalid.frame_ids[0] = 7
  av1_frame_mark_refs(invalid, 0, 2, 3)
  assert_false(invalid.valid[0])
}

///|
test "inter identity deltas include one and the full reference window" {
  // Seven repetitions of slot:3 + delta_minus_1:2, followed by
  // render_size_diff=0, switchable_filter=1, motion_switchable=0.
  for
    item in [
      (7, [b'\x00', b'\x00', b'\x00', b'\x00', b'\x08']),
      (4, [b'\x18', b'\xC6', b'\x31', b'\x8C', b'\x68']),
    ] {
    let (reference_id, payload) = item
    let (sequence, prefix) = av1_identity_test_prefix()
    let map = av1_frame_map()
    map.valid[0] = true
    map.frame_ids[0] = reference_id
    let reader : Av1FrameBits = { data: payload, bit_pos: 0, }
    assert_true(av1_frame_prefix_inter_refs(reader, prefix, sequence, map))
    assert_eq(reader.bit_pos, 38)
    assert_eq(prefix.ref_frame_idx, [0, 0, 0, 0, 0, 0, 0])
    assert_eq(prefix.frame_width, sequence.width)
    assert_eq(prefix.frame_height, sequence.height)
  }
}

///|
test "inter identity validates the seventh delta and reference validity" {
  let (sequence, prefix) = av1_identity_test_prefix()
  let map = av1_frame_map()
  map.valid[0] = true
  map.frame_ids[0] = 7
  // Only the seventh delta differs: it expects ID 6 instead of ID 7.
  let last_mismatch : Av1FrameBits = {
    data: [b'\x00', b'\x00', b'\x00', b'\x00', b'\x28'],
    bit_pos: 0,
  }
  assert_false(
    av1_frame_prefix_inter_refs(last_mismatch, prefix, sequence, map),
  )
  assert_eq(last_mismatch.bit_pos, 35)
  map.valid[0] = false
  let invalid_slot : Av1FrameBits = {
    data: [b'\x00', b'\x00', b'\x00', b'\x00', b'\x08'],
    bit_pos: 0,
  }
  assert_false(av1_frame_prefix_inter_refs(invalid_slot, prefix, sequence, map))
  assert_eq(invalid_slot.bit_pos, 5)
}

///|
test "show existing prefix checks display identity and valid reference" {
  let (sequence, _) = av1_identity_test_prefix()
  let map = av1_frame_map()
  map.valid[0] = true
  map.frame_ids[0] = 7
  map.frame_types[0] = av1_inter_frame
  map.current_frame_id = 2
  map.has_frame_id = true
  // show_existing=1, slot=000, display_id=111, trailing_one_bit=1.
  let reader : Av1FrameBits = { data: [b'\x8F'], bit_pos: 0, }
  let prefix = av1_parse_frame_prefix(reader, sequence, Some(map)).unwrap()
  assert_true(prefix.show_existing_frame)
  assert_eq(prefix.frame_to_show_map_idx, 0)
  assert_eq(prefix.current_frame_id, 7)
  assert_eq(reader.bit_pos, 7)
  assert_eq(reader.take(1), Some(1))
  assert_eq(map.current_frame_id, 2)
  assert_true(map.has_frame_id)
  assert_true(
    av1_parse_frame_prefix(
      { data: [b'\x81'], bit_pos: 0, },
      sequence,
      Some(map),
    )
    is None,
  )
  map.valid[0] = false
  assert_true(
    av1_parse_frame_prefix(
      { data: [b'\x8F'], bit_pos: 0, },
      sequence,
      Some(map),
    )
    is None,
  )
}

///|
test "hidden key identity advances by less than half the ID modulus" {
  let (sequence, _) = av1_identity_test_prefix()
  // Complete twenty-bit prefixes: hidden showable key, error resilient,
  // disabled CDF updates, three-bit ID, fixed size, zero refresh flags.
  for
    item in [
      (0, [b'\x0E', b'\x00', b'\x00'], true),
      (2, [b'\x0E', b'\x80', b'\x00'], true),
      (3, [b'\x0E', b'\xC0', b'\x00'], false),
      (7, [b'\x0F', b'\xC0', b'\x00'], false),
    ] {
    let (current, payload, accepted) = item
    let map = av1_frame_map()
    map.current_frame_id = 7
    map.has_frame_id = true
    let reader : Av1FrameBits = { data: payload, bit_pos: 0, }
    let result = av1_parse_frame_prefix(reader, sequence, Some(map))
    assert_eq(result is Some(_), accepted)
    if accepted {
      assert_eq(result.unwrap().current_frame_id, current)
      assert_eq(reader.bit_pos, 20)
    } else {
      assert_eq(reader.bit_pos, 10)
    }
  }
}

///|
test "initial frame and shown key do not compare against an old frame ID" {
  let (sequence, _) = av1_identity_test_prefix()
  let map = av1_frame_map()
  let initial : Av1FrameBits = {
    data: [b'\x0E', b'\x00', b'\x00'],
    bit_pos: 0,
  }
  assert_true(av1_parse_frame_prefix(initial, sequence, Some(map)) is Some(_))
  assert_eq(initial.bit_pos, 20)
  map.has_frame_id = true
  map.current_frame_id = 0
  assert_true(
    av1_parse_frame_prefix(
      { data: [b'\x0E', b'\x00', b'\x00'], bit_pos: 0, },
      sequence,
      Some(map),
    )
    is None,
  )
  // A shown key omits showable/error-resilient flags and implies refresh=255.
  let shown : Av1FrameBits = { data: [b'\x18', b'\x00'], bit_pos: 0, }
  let prefix = av1_parse_frame_prefix(shown, sequence, Some(map)).unwrap()
  assert_eq(prefix.current_frame_id, 0)
  assert_true(prefix.show_frame)
  assert_eq(prefix.refresh_frame_flags, 255)
  assert_eq(shown.bit_pos, 10)
}

///|
test "frame prefix expires old references immediately after its frame ID" {
  let (sequence, _) = av1_identity_test_prefix()
  let map = av1_frame_map()
  for slot in 0..<8 {
    map.valid[slot] = true
    map.frame_ids[slot] = slot
  }
  let prefix = av1_parse_frame_prefix(
    { data: [b'\x0E', b'\x00', b'\x00'], bit_pos: 0, },
    sequence,
    Some(map),
  ).unwrap()
  assert_eq(prefix.current_frame_id, 0)
  assert_eq(map.valid, [true, false, false, false, true, true, true, true])
}

///|
test "frame identity updates current state even with no refreshed slots" {
  let (original_sequence, key, frame) = av1_context_test_key()
  let sequence : Av1SequenceInfo = {
    ..original_sequence,
    frame_id_numbers_present: true,
    delta_frame_id_length_minus_2: 0,
    additional_frame_id_length_minus_1: 0,
  }
  let map = av1_frame_map()
  assert_false(map.has_frame_id)
  av1_frame_map_update(
    map,
    { ..key, current_frame_id: 7, refresh_frame_flags: 129, },
    frame,
    sequence,
  )
  assert_eq(map.current_frame_id, 7)
  assert_true(map.has_frame_id)
  for slot in [0, 7] {
    assert_true(map.valid[slot])
    assert_eq(map.frame_ids[slot], 7)
    assert_eq(map.slots[slot].unwrap().frame_id, 7)
    assert_eq(map.slots[slot].unwrap().planes, frame.planes)
  }
  av1_frame_map_update(
    map,
    { ..key, current_frame_id: 0, refresh_frame_flags: 0, },
    frame,
    sequence,
  )
  assert_eq(map.current_frame_id, 0)
  assert_true(map.has_frame_id)
  assert_eq(map.valid, [true, false, false, false, false, false, false, true])
  assert_eq(map.frame_ids[0], 7)
  assert_eq(map.frame_ids[7], 7)
  assert_eq(map.slots[0].unwrap().frame_id, 7)
  assert_eq(map.slots[7].unwrap().frame_id, 7)
}
