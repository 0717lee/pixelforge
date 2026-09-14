/// Bounded eight-slot AV1 reference-frame image state.
///
/// This stores decoded RGBA images for the show-existing branch. Inter
/// prediction and motion compensation remain outside this small state layer.

pub(all) struct Av1ReferenceState {
  images : Array[Image?]
  frame_types : Array[Int]
}

/// Create an empty eight-slot reference state.
pub fn av1_reference_state() -> Av1ReferenceState {
  {
    images: Array::make(8, None),
    frame_types: Array::make(8, -1),
  }
}

/// Store a decoded image in one AV1 reference slot.
pub fn av1_reference_store(
  state : Av1ReferenceState,
  slot : Int,
  image : Image,
  frame_type : Int,
) -> Bool {
  if slot < 0 || slot >= 8 || frame_type < 0 || frame_type > 3 {
    return false
  }
  state.images[slot] = Some(image.copy())
  state.frame_types[slot] = frame_type
  true
}

/// Resolve a parsed show-existing envelope against stored reference pixels.
pub fn av1_reference_show_existing(
  state : Av1ReferenceState,
  envelope : Av1ShowExistingFrameEnvelope,
) -> Image? {
  if envelope.frame_to_show_map_idx < 0 || envelope.frame_to_show_map_idx >= 8 {
    return None
  }
  state.images[envelope.frame_to_show_map_idx].map(fn(image) { image.copy() })
}

///| 
test "reference state stores and resolves show-existing pixels" {
  let state = av1_reference_state()
  let image = Image::new(2, 1)
  image.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\xFF')
  assert_true(av1_reference_store(state, 3, image, 0))
  let config : Av1ShowExistingFrameConfig = {
    decoder_model_info_present: false,
    equal_picture_interval: false,
    frame_presentation_time_length_minus_1: 0,
    frame_id_numbers_present: false,
    additional_frame_id_len_minus1: 0,
    delta_frame_id_length_minus2: 0,
    reference_frame_types: [0, 1, 2, 3, 4, 5, 6, 7],
  }
  let envelope = av1_parse_show_existing_frame([b'\xB0'], config).unwrap()
  let shown = av1_reference_show_existing(state, envelope).unwrap()
  assert_eq(shown.get_pixel(0, 0), (b'\x10', b'\x20', b'\x30', b'\xFF'))
  assert_true(av1_reference_show_existing(state, {
    show_existing_frame: true,
    frame_to_show_map_idx: 2,
    reference_frame_type: 2,
    frame_presentation_time: None,
    display_frame_id: None,
    header_bits: 4,
    header_bytes: 1,
  }) is None)
}
