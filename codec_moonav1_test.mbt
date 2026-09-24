///|
test "MoonAV1 image adapters preserve PixelForge pixel operations" {
  let image : @pixelforge.Image = @pixelforge.av1_yuv420_to_rgba(
    2,
    2,
    [b'\x80', b'\x80', b'\x80', b'\x80'],
    [b'\x80'],
    [b'\x80'],
  ).unwrap()
  let original = image.get_pixel(0, 0)
  let copied = image.copy()
  copied.set_pixel(0, 0, b'\x01', b'\x02', b'\x03', b'\xFF')
  assert_eq(image.get_pixel(0, 0), original)
  let composite = @pixelforge.avif_reconstruct_grid(1, 2, 4, 2, [image, copied]).unwrap()
  assert_eq(composite.width, 4)
  assert_eq(composite.get_pixel(2, 0), (b'\x01', b'\x02', b'\x03', b'\xFF'))
  assert_true(@pixelforge.avif_decode_rgba([]) is None)
}

///|
test "MoonAV1 facade preserves publicly mutable reference slots and copy semantics" {
  let state = @pixelforge.av1_reference_state()
  let input = @pixelforge.Image::new(1, 1)
  input.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\xFF')
  assert_true(@pixelforge.av1_reference_store(state, 3, input, 0))
  input.set_pixel(0, 0, b'\x00', b'\x00', b'\x00', b'\x00')
  let envelope : @pixelforge.Av1ShowExistingFrameEnvelope = {
    show_existing_frame: true,
    frame_to_show_map_idx: 3,
    reference_frame_type: 0,
    frame_presentation_time: None,
    display_frame_id: None,
    header_bits: 4,
    header_bytes: 1,
  }
  let shown = @pixelforge.av1_reference_show_existing(state, envelope).unwrap()
  assert_eq(shown.get_pixel(0, 0), (b'\x10', b'\x20', b'\x30', b'\xFF'))
  shown.set_pixel(0, 0, b'\x77', b'\x77', b'\x77', b'\xFF')
  assert_eq(
    state.images[3].unwrap().get_pixel(0, 0),
    (b'\x10', b'\x20', b'\x30', b'\xFF'),
  )
  state.images[3] = None
  assert_true(@pixelforge.av1_reference_show_existing(state, envelope) is None)
}
