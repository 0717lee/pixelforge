///|
/// Expand the generated value/count pairs without narrowing coded samples.
fn av1_reference_planes_expand(runs : Array[Int]) -> Array[Int] {
  let samples : Array[Int] = []
  for pair in 0..<(runs.length() / 2) {
    for _ in 0..<runs[pair * 2 + 1] {
      samples.push(runs[pair * 2])
    }
  }
  samples
}

///|
/// Compare the complete coded-depth YUV planes with independent dav1d samples,
/// then retain the public decoder's complete RGBA comparison. These fixture
/// corpora contain one tile and disable in-loop postprocessing.
fn av1_reference_planes_compare(
  stream : Array[Byte],
  width : Int,
  height : Int,
  bit_depth : Int,
  y_runs : Array[Int],
  u_runs : Array[Int],
  v_runs : Array[Int],
) -> Unit raise {
  let y_plane = av1_reference_planes_expand(y_runs)
  let u_plane = av1_reference_planes_expand(u_runs)
  let v_plane = av1_reference_planes_expand(v_runs)
  let chroma_width = (width + 1) / 2
  let chroma_height = (height + 1) / 2
  assert_eq(y_plane.length(), width * height)
  assert_eq(u_plane.length(), chroma_width * chroma_height)
  assert_eq(v_plane.length(), chroma_width * chroma_height)
  let sequence = av1_sequence_info(stream).unwrap()
  assert_eq(
    (sequence.width, sequence.height, sequence.bit_depth),
    (width, height, bit_depth),
  )
  let frame_payloads = av1_obu_payloads(stream, 6)
  assert_eq(frame_payloads.length(), 1)
  let frame = av1_parse_stage1_frame(
    frame_payloads[0],
    sequence,
    allow_highbd=true,
  ).unwrap()
  assert_eq((frame.tile_cols, frame.tile_rows), (1, 1))
  let state = av1_decode_intra_tile_state(
    width,
    height,
    frame.tile_payload,
    frame.base_q_idx,
    frame.disable_cdf_update,
    frame.allow_screen_content_tools,
    sequence.use_128x128_superblock,
    bit_depth,
    frame.reduced_tx_set,
    sequence.enable_filter_intra,
    frame.tx_mode_select,
  ).unwrap()
  let references = [y_plane, u_plane, v_plane]
  assert_eq(state.planes.length(), 3)
  for plane in 0..<3 {
    let plane_width = if plane == 0 { width } else { chroma_width }
    let plane_height = if plane == 0 { height } else { chroma_height }
    let actual = av1_intra_crop(state.planes[plane], plane_width, plane_height)
    let expected = references[plane]
    assert_eq(actual.length(), expected.length())
    for index in 0..<expected.length() {
      assert_eq((plane, index, actual[index]), (plane, index, expected[index]))
    }
  }
  let expected = av1_yuv420_highbd_to_rgba(
    width,
    height,
    y_plane,
    u_plane,
    v_plane,
    bit_depth,
    full_range=sequence.full_range,
    matrix_coefficients=sequence.matrix_coefficients,
  ).unwrap()
  let actual = av1_decode(stream).unwrap()
  for y in 0..<height {
    for x in 0..<width {
      assert_eq(
        (x, y, actual.get_pixel(x, y)),
        (x, y, expected.get_pixel(x, y)),
      )
    }
  }
}
