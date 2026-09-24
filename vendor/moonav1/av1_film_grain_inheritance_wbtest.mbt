/// The literal byte vectors below were independently packed from AV1
/// film_grain_params syntax: apply, seed, INTER-only update, then parameters
/// or the reference slot. Each valid vector ends in the three-bit sentinel 5.

///|
fn av1_grain_inheritance_test_key() -> Av1FilmGrainParams {
  let reader : Av1FrameBits = {
    data: [b'\x89', b'\xAB', b'\x8A', b'\x00', b'\xB2', b'\x5D', b'\x40'],
    bit_pos: 0,
  }
  av1_parse_film_grain_params(reader, true, true, true).unwrap()
}

///|
test "key intra only and switch grain syntax omits the update flag" {
  for frame_type in [av1_key_frame, av1_intra_only_frame, av1_switch_frame] {
    let reader : Av1FrameBits = {
      data: [b'\x89', b'\xAB', b'\x8A', b'\x00', b'\xB2', b'\x5D', b'\x40'],
      bit_pos: 0,
    }
    let params = av1_parse_film_grain_params(
      reader,
      true,
      true,
      true,
      frame_type~,
    ).unwrap()
    assert_true(params.apply_grain)
    assert_eq(params.grain_seed, 0x1357)
    assert_eq(params.num_y_points, 1)
    assert_eq(params.point_y_value, [64])
    assert_eq(params.point_y_scaling, [22])
    assert_eq(params.grain_scaling_minus8, 1)
    assert_eq(params.ar_coeff_lag, 0)
    assert_eq(params.ar_coeff_shift_minus6, 2)
    assert_eq(params.grain_scale_shift, 3)
    assert_true(params.overlap_flag)
    assert_false(params.clip_to_restricted_range)
    assert_eq(reader.bit_pos, 47)
    assert_eq(reader.take(3), Some(5))
  }
}

///|
test "inter grain seed precedes a new parameter update" {
  let reader : Av1FrameBits = {
    data: [b'\x92', b'\x34', b'\x45', b'\x00', b'\x59', b'\x2E', b'\xA0'],
    bit_pos: 0,
  }
  let params = av1_parse_film_grain_params(
    reader,
    true,
    true,
    true,
    frame_type=av1_inter_frame,
  ).unwrap()
  assert_eq(params.grain_seed, 0x2468)
  assert_eq(params.point_y_value, [64])
  assert_eq(params.point_y_scaling, [22])
  assert_eq(params.grain_scale_shift, 3)
  assert_eq(reader.bit_pos, 48)
  assert_eq(reader.take(3), Some(5))
}

///|
test "grain inheritance uses a named reference but retains the new seed" {
  let map = av1_frame_map()
  // Reuse the committed aomenc grain fixture's full luma/chroma/AR parameters.
  let previous = av1_fg_params().unwrap()
  map.valid[3] = true
  map.saved_film_grain[3] = Some(previous)
  let reader : Av1FrameBits = { data: [b'\xAB', b'\x3C', b'\x1D'], bit_pos: 0, }
  let params = av1_parse_film_grain_params(
    reader,
    false,
    true,
    true,
    frame_type=av1_inter_frame,
    map=Some(map),
    ref_frame_idx=[0, 0, 0, 3, 0, 0, 0],
  ).unwrap()
  assert_true(params.apply_grain)
  assert_eq(params.grain_seed, 0x5678)
  assert_eq(params.point_y_value, previous.point_y_value)
  assert_eq(params.point_cb_value, previous.point_cb_value)
  assert_eq(params.point_cr_scaling, previous.point_cr_scaling)
  assert_eq(params.ar_coeffs_y, previous.ar_coeffs_y)
  assert_eq(params.ar_coeffs_cb, previous.ar_coeffs_cb)
  assert_eq(params.ar_coeffs_cr, previous.ar_coeffs_cr)
  assert_eq(params.cb_offset, previous.cb_offset)
  assert_eq(params.cr_mult, previous.cr_mult)
  assert_eq(reader.bit_pos, 21)
  assert_eq(reader.take(3), Some(5))
  params.point_y_value[0] = 99
  params.ar_coeffs_cb[0] = 1
  assert_eq(previous.point_y_value[0], 16)
  assert_eq(previous.grain_seed, 51993)
  assert_true(previous.ar_coeffs_cb[0] != 1)
}

///|
test "grain inheritance rejects missing or unnamed references" {
  let map = av1_frame_map()
  map.saved_film_grain[3] = Some(av1_grain_inheritance_test_key())
  for case in 0..<2 {
    map.valid[3] = case == 1
    let reader : Av1FrameBits = {
      data: [b'\xAB', b'\x3C', b'\x1D'],
      bit_pos: 0,
    }
    assert_true(
      av1_parse_film_grain_params(
        reader,
        true,
        true,
        true,
        frame_type=av1_inter_frame,
        map=Some(map),
        ref_frame_idx=if case == 0 {
          [3, 3, 3, 3, 3, 3, 3]
        } else {
          [0, 0, 0, 0, 0, 0, 0]
        },
      )
      is None,
    )
    assert_eq(reader.bit_pos, 21)
    assert_eq(reader.take(3), Some(5))
  }
}

///|
test "disabled grain consumes only the apply bit" {
  for frame_type in [av1_key_frame, av1_inter_frame, av1_switch_frame] {
    let reader : Av1FrameBits = { data: [b'\x50'], bit_pos: 0, }
    let params = av1_parse_film_grain_params(
      reader,
      true,
      true,
      true,
      frame_type~,
    ).unwrap()
    assert_false(params.apply_grain)
    assert_eq(params.grain_seed, 0)
    assert_eq(params.num_y_points, 0)
    assert_eq(reader.bit_pos, 1)
    assert_eq(reader.take(3), Some(5))
  }
}

///|
test "grain syntax rejects excessive and non increasing scaling points" {
  let excessive : Av1FrameBits = {
    data: [b'\x80', b'\x03', b'\xFD'],
    bit_pos: 0,
  }
  assert_true(av1_parse_film_grain_params(excessive, true, true, true) is None)
  assert_eq(excessive.bit_pos, 21)
  let descending : Av1FrameBits = {
    data: [b'\x80', b'\x03', b'\x92', b'\x00', b'\xB1', b'\xF8', b'\xB5'],
    bit_pos: 0,
  }
  assert_true(av1_parse_film_grain_params(descending, true, true, true) is None)
  assert_eq(descending.bit_pos, 53)
  assert_eq(descending.take(3), Some(5))
}

///|
test "reference refresh snapshots grain independently of native samples" {
  let (sequence, header, frame) = av1_context_test_key()
  let native = frame.planes.map(plane => plane.copy())
  let map = av1_frame_map()
  let grain = av1_grain_inheritance_test_key()
  av1_frame_map_update(
    map,
    {
      ..header,
      refresh_frame_flags: 0x18,
      showable_frame: true,
      film_grain: Some(grain),
    },
    frame,
    sequence,
  )
  assert_true(map.saved_film_grain[0] is None)
  assert_true(map.saved_showable[3])
  assert_eq(map.saved_film_grain[3].unwrap().grain_seed, 0x1357)
  grain.point_y_value[0] = 99
  assert_eq(map.saved_film_grain[3].unwrap().point_y_value, [64])
  map.saved_film_grain[3].unwrap().point_y_value[0] = 77
  assert_eq(map.saved_film_grain[4].unwrap().point_y_value, [64])
  assert_eq(map.slots[3].unwrap().planes, native)
  assert_eq(frame.planes, native)
  let display = av1_frame_apply_grain(
    frame,
    av1_fg_params().unwrap(),
    sequence.monochrome,
    sequence.subsampling_x,
    sequence.subsampling_y,
  ).unwrap()
  assert_true(display.planes != native)
  assert_eq(frame.planes, native)
  assert_eq(map.slots[3].unwrap().planes, native)
  av1_frame_map_invalidate(map)
  assert_true(map.saved_film_grain[3] is None)
  assert_false(map.saved_showable[3])
}
