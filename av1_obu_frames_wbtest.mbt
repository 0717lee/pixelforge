///|
fn av1_obu_test_wrap(
  kind : Int,
  payload : Array[Byte],
  layer? : Int? = None,
) -> Array[Byte] {
  let out : Array[Byte] = [
    ((kind << 3) | 2 | (if layer is Some(_) { 4 } else { 0 })).to_byte(),
  ]
  match layer {
    Some(value) => out.push(value.to_byte())
    None => ()
  }
  let mut size = payload.length()
  while size >= 128 {
    out.push(((size & 127) | 128).to_byte())
    size = size >> 7
  }
  out.push(size.to_byte())
  for byte in payload {
    out.push(byte)
  }
  out
}

///|
test "OBU assembly preserves extension IDs and refuses truncated envelopes" {
  let packet = av1_obu_packets(
      av1_obu_test_wrap(3, [0x98], layer=Some((3 << 5) | (2 << 3))),
    ).unwrap()[0]
  assert_eq((packet.temporal_id, packet.spatial_id), (3, 2))
  assert_eq(packet.kind, 3)
  assert_eq(packet.payload, [0x98])
  assert_true(av1_obu_packets([0x9a, 0x01, 0x98]) is None)
  assert_true(av1_obu_packets([0x1e]) is None)
  assert_true(av1_obu_packets([0x1e, 0x01, 0x01, 0x98]) is None)
  assert_true(av1_obu_packets([0x1a, 0x02, 0x98]) is None)
  assert_true(av1_obu_packets([0x1a, 0x80]) is None)
  assert_eq(
    av1_obu_packets([0x1a, 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00, 0x98]).unwrap()[0].payload,
    [0x98],
  )
}

///|
test "OBU operating point checks both actual layer IDs" {
  let sequence = av1_sequence_info(obu_hidden_inter_show_existing_data).unwrap()
  sequence.operating_point_idc[0] = (1 << 3) | (1 << 10)
  let accepted : Av1ObuPacket = {
    kind: 3,
    extension: true,
    temporal_id: 3,
    spatial_id: 2,
    payload: [0x98],
  }
  assert_true(av1_obu_selected(accepted, sequence))
  assert_false(av1_obu_selected({ ..accepted, temporal_id: 0, }, sequence))
  assert_false(av1_obu_selected({ ..accepted, spatial_id: 0, }, sequence))
  assert_true(
    av1_obu_selected({ ..accepted, kind: 1, temporal_id: 0, }, sequence),
  )
  assert_true(
    av1_obu_selected(
      { ..accepted, extension: false, temporal_id: 0, },
      sequence,
    ),
  )
}

///|
test "OBU decoder filters unselected layer payload before frame syntax" {
  let sequence = av1_sequence_info(obu_hidden_inter_show_existing_data).unwrap()
  sequence.operating_point_idc[0] = 1 | (1 << 8)
  let packets = av1_obu_packets(obu_hidden_inter_show_existing_data).unwrap()
  let data : Array[Byte] = []
  for packet in packets {
    if packet.kind == 6 {
      for byte in av1_obu_test_wrap(6, packet.payload, layer=Some(0)) {
        data.push(byte)
      }
      break
    }
  }
  // This selected operating point excludes temporal layer 1; its malformed
  // frame-header payload must never be presented to the frame parser.
  for byte in av1_obu_test_wrap(3, [], layer=Some(1 << 5)) {
    data.push(byte)
  }
  let (_, displayed) = av1_decode_obu_planes(
    data,
    av1_frame_map(),
    Some(sequence),
    false,
  ).unwrap()
  assert_eq(displayed.length(), 1)
}

///|
test "OBU full-width timing retains per-operating-point presence and temporal IDs" {
  let sequence = av1_sequence_info(obu_layer_timing_32bit_data).unwrap()
  assert_eq(sequence.operating_point_idc, [259, 257, 0])
  assert_eq(sequence.decoder_model_present_for_this_op, [true, true, false])
  assert_eq(sequence.buffer_delay_length_minus_1, 31)
  assert_eq(sequence.buffer_removal_time_length_minus_1, 31)
  assert_eq(sequence.frame_presentation_time_length_minus_1, 31)
  assert_eq((sequence.width, sequence.height), (64, 64))
  let ids : Array[Int] = []
  for packet in av1_obu_packets(obu_layer_timing_32bit_data).unwrap() {
    if packet.kind == 6 {
      ids.push(packet.temporal_id)
    }
  }
  assert_eq(ids, [0, 1])
}

///|
test "OBU tile groups require exact sequential coverage" {
  assert_eq(
    av1_assemble_tile_groups([[0x80, 0xaa], [0xe0, 0xbb]], 2, 1, 1, 1),
    Some([0, 0, 0, 0, 0xaa, 0xbb]),
  )
  assert_true(av1_assemble_tile_groups([[0x80, 0xaa]], 2, 1, 1, 1) is None)
  assert_true(
    av1_assemble_tile_groups([[0xe0, 0xbb], [0x80, 0xaa]], 2, 1, 1, 1) is None,
  )
  assert_true(
    av1_assemble_tile_groups([[0x80, 0xaa], [0x80, 0xbb]], 2, 1, 1, 1) is None,
  )
  assert_true(
    av1_assemble_tile_groups([[0x81, 0xaa], [0xe0, 0xbb]], 2, 1, 1, 1) is None,
  )
  assert_true(
    av1_assemble_tile_groups([[0x80], [0xe0, 0xbb]], 2, 1, 1, 1) is None,
  )
  assert_eq(
    av1_assemble_tile_groups([[0x00, 0x00, 0xaa, 0xbb]], 2, 1, 1, 1),
    Some([0, 0, 0, 0, 0xaa, 0xbb]),
  )
}

///|
test "OBU public video API outputs every displayed frame and retains hidden references" {
  let decoder = av1_video_decoder()
  let images = av1_video_decode_temporal_unit(
    decoder, obu_hidden_inter_show_existing_data,
  ).unwrap()
  assert_eq(images.length(), 3)
  let packets = av1_obu_packets(obu_hidden_inter_show_existing_data).unwrap()
  let split_decoder = av1_video_decoder()
  let mut shown = 0
  let mut hidden = 0
  for packet in packets {
    if packet.kind == 2 {
      continue
    }
    let data = av1_obu_test_wrap(packet.kind, packet.payload)
    let frames = av1_video_decode_temporal_unit_planes(split_decoder, data).unwrap()
    if packet.kind == 6 && frames.is_empty() {
      hidden = hidden + 1
    }
    for frame in frames {
      assert_eq((frame.width, frame.height), (64, 64))
      shown = shown + 1
    }
  }
  assert_eq((shown, hidden), (3, 1))
  let missing = av1_video_decoder()
  assert_true(
    av1_video_decode_temporal_unit(missing, [0x1a, 0x01, 0x98]) is None,
  )
  // A displayed key frame cannot subsequently be shown with show-existing.
  let key_decoder = av1_video_decoder()
  for packet in packets {
    av1_video_decode_temporal_unit_planes(
      key_decoder,
      av1_obu_test_wrap(packet.kind, packet.payload),
    )
    |> ignore
    if packet.kind == 6 {
      break
    }
  }
  assert_true(
    av1_video_decode_temporal_unit(key_decoder, [0x1a, 0x01, 0x88]) is None,
  )
}

///|
test "OBU standalone frame header checks matching tile layer and complete input" {
  let packets = av1_obu_packets(obu_split_two_tile_groups_data).unwrap()
  let truncated : Array[Byte] = []
  let wrong_layer : Array[Byte] = []
  for packet in packets {
    if packet.kind != 4 || packet.payload[0] == 0x80 {
      for byte in av1_obu_test_wrap(packet.kind, packet.payload) {
        truncated.push(byte)
      }
    }
    let layer = if packet.kind == 4 { Some(0x20) } else { None }
    for byte in av1_obu_test_wrap(packet.kind, packet.payload, layer~) {
      wrong_layer.push(byte)
    }
  }
  assert_true(av1_decode_frame_planes(truncated) is None)
  assert_true(av1_decode_frame_planes(wrong_layer) is None)
}

///|
test "OP0 presents highest available spatial layer per temporal unit and per sample" {
  let sequence = av1_sequence_info(obu_spatial_layer_presentation_data).unwrap()
  assert_eq(sequence.operating_point_idc[0], 769)
  let packets = av1_obu_packets(obu_spatial_layer_presentation_data).unwrap()
  let units : Array[Array[Byte]] = []
  let mut unit : Array[Byte] = []
  let spatial_ids : Array[Int] = []
  for packet in packets {
    if packet.kind == 2 {
      if !unit.is_empty() {
        units.push(unit)
      }
      unit = []
      continue
    }
    if packet.kind == 6 {
      spatial_ids.push(packet.spatial_id)
    }
    let layer = if packet.extension {
      Some((packet.temporal_id << 5) | (packet.spatial_id << 3))
    } else {
      None
    }
    for byte in av1_obu_test_wrap(packet.kind, packet.payload, layer~) {
      unit.push(byte)
    }
  }
  if !unit.is_empty() {
    units.push(unit)
  }
  assert_eq(spatial_ids, [0, 1, 0, 0, 1])
  assert_eq(units.length(), 3)
  let decoder = av1_video_decoder()
  let mut offset = 0
  for sample in units {
    // ISOBMFF samples omit TD OBUs; input end still closes the presentation.
    let frames = av1_video_decode_temporal_unit_planes(decoder, sample).unwrap()
    assert_eq(frames.length(), 1)
    for plane in 0..<3 {
      for pixel in av1_frame_crop(frames[0], plane) {
        assert_eq(
          pixel,
          obu_spatial_layer_presentation_reference[offset].to_int(),
        )
        offset = offset + 1
      }
    }
  }
  assert_eq(offset, obu_spatial_layer_presentation_reference.length())
  let images = av1_video_decode_temporal_unit(
    av1_video_decoder(),
    obu_spatial_layer_presentation_data,
  ).unwrap()
  assert_eq(images.length(), 3)
  let first = av1_video_decode_frame(
    av1_video_decoder(),
    obu_spatial_layer_presentation_data,
  ).unwrap()
  assert_eq(first.get_pixel(0, 0), images[0].get_pixel(0, 0))
  assert_true(first.get_pixel(0, 0) != images[1].get_pixel(0, 0))
}

///|
test "OBU explicit spatial selection preserves decoded references and native output" {
  let frame_bytes = 64 * 64 * 3 / 2
  for layer in 0..<2 {
    let (_, frames) = av1_decode_obu_planes(
      obu_spatial_layer_presentation_data,
      av1_frame_map(),
      None,
      false,
      spatial_layer=Some(layer),
    ).unwrap()
    assert_eq(frames.length(), if layer == 0 { 3 } else { 2 })
    for index in 0..<frames.length() {
      // Stock dav1d's presentation-mode fixture contains high/low/high.
      // Every low layer is the same key; each high inter depends on that key.
      let reference_index = if layer == 0 { 1 } else { index * 2 }
      let mut offset = reference_index * frame_bytes
      for plane in 0..<3 {
        for pixel in av1_frame_crop(frames[index], plane) {
          assert_eq(
            pixel,
            obu_spatial_layer_presentation_reference[offset].to_int(),
          )
          offset = offset + 1
        }
      }
      assert_eq(offset, (reference_index + 1) * frame_bytes)
    }
  }
  let low = av1_decode_frame_planes(
    obu_spatial_layer_presentation_data,
    spatial_layer=Some(0),
  ).unwrap()
  assert_eq(
    av1_frame_crop(low, 0)[0],
    obu_spatial_layer_presentation_reference[frame_bytes].to_int(),
  )
  let (_, absent) = av1_decode_obu_planes(
    obu_spatial_layer_presentation_data,
    av1_frame_map(),
    None,
    false,
    spatial_layer=Some(2),
  ).unwrap()
  assert_true(absent.is_empty())
  assert_true(
    av1_decode_frame_planes(
      obu_spatial_layer_presentation_data,
      spatial_layer=Some(4),
    )
    is None,
  )
}

///|
test "OBU selected operating point filters temporal layers before decoding" {
  let (_, frames) = av1_decode_obu_planes(
    obu_layer_timing_32bit_data,
    av1_frame_map(),
    None,
    false,
    operating_point=1,
  ).unwrap()
  assert_eq(frames.length(), 1)
  let mut offset = 0
  for plane in 0..<3 {
    for pixel in av1_frame_crop(frames[0], plane) {
      assert_eq(pixel, obu_layer_timing_32bit_reference[offset].to_int())
      offset = offset + 1
    }
  }
  assert_true(
    av1_decode_frame_planes(obu_layer_timing_32bit_data, operating_point=3)
    is None,
  )
  assert_true(
    av1_decode_frame_planes(obu_layer_timing_32bit_data, operating_point=-1)
    is None,
  )
}
