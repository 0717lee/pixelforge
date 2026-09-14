/// Hand-built bitstreams exercise only the show-existing envelope.  No test
/// here claims to decode inter prediction or reference-frame pixels.

test "av1 parses show-existing timing and frame-id envelope" {
  // 1 | map_idx=5 (101) | presentation_time=17 (10001) |
  // frame_id=77 (1001101) => 0xD8CD.
  let config : Av1ShowExistingFrameConfig = {
    decoder_model_info_present: true,
    equal_picture_interval: false,
    frame_presentation_time_length_minus_1: 4,
    frame_id_numbers_present: true,
    additional_frame_id_len_minus1: 1,
    delta_frame_id_length_minus2: 3,
    reference_frame_types: [0, 0, 0, 0, 1, 2, 3, 0],
  }
  let value = av1_parse_show_existing_frame([b'\xD8', b'\xCD'], config)
  match value {
    Some(v) => {
      assert_true(v.show_existing_frame)
      assert_eq(v.frame_to_show_map_idx, 5)
      assert_eq(v.reference_frame_type, 2)
      assert_eq(v.frame_presentation_time, Some(17))
      assert_eq(v.display_frame_id, Some(77))
      assert_eq(v.header_bits, 16)
      assert_eq(v.header_bytes, 2)
    }
    None => assert_true(false)
  }
}

test "av1 parses show-existing without optional timing" {
  // 1 | map_idx=2 (010), followed by byte alignment padding.
  let config : Av1ShowExistingFrameConfig = {
    decoder_model_info_present: false,
    equal_picture_interval: false,
    frame_presentation_time_length_minus_1: 0,
    frame_id_numbers_present: false,
    additional_frame_id_len_minus1: 0,
    delta_frame_id_length_minus2: 0,
    reference_frame_types: [0, 1, 2, 3, 4, 5, 6, 7],
  }
  let value = av1_parse_show_existing_frame([b'\xA0'], config).unwrap()
  assert_true(value.show_existing_frame)
  assert_eq(value.frame_to_show_map_idx, 2)
  assert_eq(value.reference_frame_type, 2)
  assert_true(value.frame_presentation_time is None)
  assert_true(value.display_frame_id is None)
  assert_eq(value.header_bits, 4)
  assert_eq(value.header_bytes, 1)
}

test "av1 rejects truncated or illegal show-existing envelope" {
  let config : Av1ShowExistingFrameConfig = {
    decoder_model_info_present: true,
    equal_picture_interval: false,
    frame_presentation_time_length_minus_1: 4,
    frame_id_numbers_present: false,
    additional_frame_id_len_minus1: 0,
    delta_frame_id_length_minus2: 0,
    reference_frame_types: [0, 1],
  }
  // Fewer than eight reference slots is invalid state, even before indexing.
  assert_true(av1_parse_show_existing_frame([b'\x80'], config) is None)

  let valid_slots : Av1ShowExistingFrameConfig = {
    decoder_model_info_present: true,
    equal_picture_interval: false,
    frame_presentation_time_length_minus_1: 4,
    frame_id_numbers_present: false,
    additional_frame_id_len_minus1: 0,
    delta_frame_id_length_minus2: 0,
    reference_frame_types: [0, 1, 2, 3, 4, 5, 6, 7],
  }
  // show_existing=1, map_idx=0, but the five timing bits are truncated.
  assert_true(av1_parse_show_existing_frame([b'\x80'], valid_slots) is None)
  // show_existing=0 is outside this reference-display-only API.
  assert_true(av1_parse_show_existing_frame([b'\x00'], valid_slots) is None)
}
