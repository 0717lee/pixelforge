///|
/// Remux the first complete AV1 frame without changing sequence or tile bits.
/// The inter fixture suite independently pins these key frames against dav1d.
fn avif_decoder_regression_item(whole : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  for kind in [1, 6] {
    let payload = av1_obu_payloads(whole, kind)[0]
    out.push(((kind << 3) | 2).to_byte())
    let mut length = payload.length()
    while length >= 128 {
      out.push(((length & 127) | 128).to_byte())
      length = length >> 7
    }
    out.push(length.to_byte())
    for value in payload {
      out.push(value)
    }
  }
  out
}

///|
fn avif_decoder_regression_container(item : Array[Byte]) -> Array[Byte] {
  let sequence = av1_sequence_info(item).unwrap()
  let ftyp = avif_alpha_binding_box("ftyp", [
    97, 118, 105, 102, 0, 0, 0, 0, 97, 118, 105, 102, 109, 105, 102, 49,
  ])
  let pitm = avif_alpha_binding_fullbox("pitm", 0, 0, [0, 1])
  let infe = avif_alpha_binding_fullbox("infe", 2, 0, [
    0, 1, 0, 0, 97, 118, 48, 49, 0,
  ])
  let iinf = avif_alpha_binding_fullbox(
    "iinf",
    0,
    0,
    avif_alpha_binding_join([[0, 1], infe]),
  )
  let locations : Array[Byte] = [
    0x44, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0,
  ]
  avif_alpha_binding_number(locations, item.length(), 4)
  let iloc = avif_alpha_binding_fullbox("iloc", 1, 0, locations)
  let dimensions : Array[Byte] = []
  avif_alpha_binding_number(dimensions, sequence.width, 4)
  avif_alpha_binding_number(dimensions, sequence.height, 4)
  let ispe = avif_alpha_binding_fullbox("ispe", 0, 0, dimensions)
  let flags = (if sequence.bit_depth > 8 { 0x40 } else { 0 }) |
    (if sequence.bit_depth == 12 { 0x20 } else { 0 }) |
    (if sequence.monochrome { 0x10 } else { 0 }) |
    (if sequence.subsampling_x { 8 } else { 0 }) |
    (if sequence.subsampling_y { 4 } else { 0 })
  let config = avif_alpha_binding_box("av1C", [
    0x81,
    (sequence.profile << 5).to_byte(),
    flags.to_byte(),
    0,
  ])
  let depths : Array[Byte] = [
    if sequence.monochrome {
      b'\x01'
    } else {
      b'\x03'
    },
  ]
  for _ in 0..<(if sequence.monochrome { 1 } else { 3 }) {
    depths.push(sequence.bit_depth.to_byte())
  }
  let pixi = avif_alpha_binding_fullbox("pixi", 0, 0, depths)
  let ipco = avif_alpha_binding_box(
    "ipco",
    avif_alpha_binding_join([ispe, config, pixi]),
  )
  let ipma = avif_alpha_binding_fullbox("ipma", 0, 0, [
    0, 0, 0, 1, 0, 1, 3, 1, 0x82, 3,
  ])
  let iprp = avif_alpha_binding_box(
    "iprp",
    avif_alpha_binding_join([ipco, ipma]),
  )
  let idat = avif_alpha_binding_box("idat", item)
  avif_alpha_binding_join([
    ftyp,
    avif_alpha_binding_fullbox(
      "meta",
      0,
      0,
      avif_alpha_binding_join([pitm, iinf, iloc, iprp, idat]),
    ),
  ])
}

///|
test "AVIF public decoder preserves segment and superblock quantization" {
  for whole in [inter_segmentation_64x64_obu, inter_deltaq_64x64_obu] {
    let item = avif_decoder_regression_item(whole)
    let data = avif_decoder_regression_container(item)
    let sequence = av1_sequence_info(item).unwrap()
    let header = av1_parse_stage1_frame(
      av1_obu_payloads(item, 6)[0],
      sequence,
      map=av1_frame_map(),
    ).unwrap()
    assert_true(header.segmentation.enabled || header.delta_q_present)
    let raw = av1_decode(item).unwrap()
    let image = avif_decode(data).unwrap()
    assert_eq((image.width, image.height), (raw.width, raw.height))
    for y in 0..<raw.height {
      for x in 0..<raw.width {
        assert_eq(image.get_pixel(x, y), raw.get_pixel(x, y))
      }
    }
  }
}
