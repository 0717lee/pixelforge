///|
fn ga_test_fourcc(a : Int, b : Int, c : Int, d : Int) -> Array[Byte] {
  [a.to_byte(), b.to_byte(), c.to_byte(), d.to_byte()]
}

///|
fn ga_test_u32(x : Int) -> Array[Byte] {
  [(x >> 24).to_byte(), (x >> 16).to_byte(), (x >> 8).to_byte(), x.to_byte()]
}

///|
fn ga_test_box(typ : Array[Byte], payload : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  let n = payload.length() + 8
  for b in ga_test_u32(n) {
    out.push(b)
  }
  for b in typ {
    out.push(b)
  }
  for b in payload {
    out.push(b)
  }
  out
}

///|
test "grid and animation metadata reject malformed input" {
  assert_true(avif_grid_descriptor([]) is None)
  assert_true(avif_animation_descriptor([]) is None)
}

///|
test "animation descriptor returns ordered sample extents" {
  let mdhd_payload : Array[Byte] = [0, 0, 0, 0]
  for _ in 0..<8 {
    mdhd_payload.push(0)
  }
  for b in ga_test_u32(1000) {
    mdhd_payload.push(b)
  }
  for b in ga_test_u32(20) {
    mdhd_payload.push(b)
  }
  for _ in 0..<4 {
    mdhd_payload.push(0)
  }
  let mdhd = ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x68, 0x64), mdhd_payload)
  let stts_payload : Array[Byte] = [
    0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 10,
  ]
  let stts = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x74, 0x73), stts_payload)
  let stsz_payload : Array[Byte] = [0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 2]
  let stsz = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x73, 0x7A), stsz_payload)
  // One chunk carries both samples; the parser derives the second offset
  // from the preceding sample size (the valid compact AVIF layout).
  let stco_payload : Array[Byte] = [0, 0, 0, 0, 0, 0, 0, 1]
  for b in ga_test_u32(100) {
    stco_payload.push(b)
  }
  let stco = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x63, 0x6F), stco_payload)
  let stbl_payload : Array[Byte] = []
  for b in stts {
    stbl_payload.push(b)
  }
  for b in stsz {
    stbl_payload.push(b)
  }
  for b in stco {
    stbl_payload.push(b)
  }
  let stbl = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x62, 0x6C), stbl_payload)
  let minf = ga_test_box(ga_test_fourcc(0x6D, 0x69, 0x6E, 0x66), stbl)
  let mdia_payload : Array[Byte] = []
  for b in mdhd {
    mdia_payload.push(b)
  }
  for b in minf {
    mdia_payload.push(b)
  }
  let mdia = ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x69, 0x61), mdia_payload)
  let trak = ga_test_box(ga_test_fourcc(0x74, 0x72, 0x61, 0x6B), mdia)
  let moov = ga_test_box(ga_test_fourcc(0x6D, 0x6F, 0x6F, 0x76), trak)
  let data : Array[Byte] = []
  for b in moov {
    data.push(b)
  }
  for _ in 0..<120 {
    data.push(0)
  }
  let parsed = avif_animation_descriptor(data).unwrap()
  assert_eq(parsed.timescale, 1000)
  assert_eq(parsed.frames.length(), 2)
  assert_eq(
    (
      parsed.frames[0].offset,
      parsed.frames[0].length,
      parsed.frames[0].timestamp,
    ),
    (100, 3, 0),
  )
  assert_eq(parsed.frames[1].offset, 103)
  assert_eq(parsed.frames[1].timestamp, 10)
  let extracted = avif_animation_sample_payloads(data).unwrap()
  assert_eq(extracted.1.length(), 2)
  assert_eq(extracted.1[0].length(), 3)
}

///|
test "animation decoder reads BMFF samples and returns pixels" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00',
    b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46',
    b'\x02', b'\x28',
  ]
  let mdhd_payload : Array[Byte] = [0, 0, 0, 0]
  for _ in 0..<8 {
    mdhd_payload.push(0)
  }
  for b in ga_test_u32(1000) {
    mdhd_payload.push(b)
  }
  for b in ga_test_u32(20) {
    mdhd_payload.push(b)
  }
  for _ in 0..<4 {
    mdhd_payload.push(0)
  }
  let mdhd = ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x68, 0x64), mdhd_payload)
  let stts = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x74, 0x73), [
    0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 10,
  ])
  let stsz_payload : Array[Byte] = [0, 0, 0, 0]
  for b in ga_test_u32(sample.length()) {
    stsz_payload.push(b)
  }
  stsz_payload.push(0)
  stsz_payload.push(0)
  stsz_payload.push(0)
  stsz_payload.push(2)
  let stsz = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x73, 0x7A), stsz_payload)
  let stco_placeholder = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x63, 0x6F), [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ])
  let stbl_payload : Array[Byte] = []
  for b in stts {
    stbl_payload.push(b)
  }
  for b in stsz {
    stbl_payload.push(b)
  }
  for b in stco_placeholder {
    stbl_payload.push(b)
  }
  let minf = ga_test_box(
    ga_test_fourcc(0x6D, 0x69, 0x6E, 0x66),
    ga_test_box(ga_test_fourcc(0x73, 0x74, 0x62, 0x6C), stbl_payload),
  )
  let mdia_payload : Array[Byte] = []
  for b in mdhd {
    mdia_payload.push(b)
  }
  for b in minf {
    mdia_payload.push(b)
  }
  let moov = ga_test_box(
    ga_test_fourcc(0x6D, 0x6F, 0x6F, 0x76),
    ga_test_box(
      ga_test_fourcc(0x74, 0x72, 0x61, 0x6B),
      ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x69, 0x61), mdia_payload),
    ),
  )
  let sample_offset = moov.length() + 8
  // Rebuild stco with the absolute mdat payload offset.
  let stco = ga_test_box(ga_test_fourcc(0x73, 0x74, 0x63, 0x6F), [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    (sample_offset >> 24).to_byte(),
    (sample_offset >> 16).to_byte(),
    (sample_offset >> 8).to_byte(),
    sample_offset.to_byte(),
  ])
  let stbl2_payload : Array[Byte] = []
  for b in stts {
    stbl2_payload.push(b)
  }
  for b in stsz {
    stbl2_payload.push(b)
  }
  for b in stco {
    stbl2_payload.push(b)
  }
  let minf2 = ga_test_box(
    ga_test_fourcc(0x6D, 0x69, 0x6E, 0x66),
    ga_test_box(ga_test_fourcc(0x73, 0x74, 0x62, 0x6C), stbl2_payload),
  )
  let mdia2_payload : Array[Byte] = []
  for b in mdhd {
    mdia2_payload.push(b)
  }
  for b in minf2 {
    mdia2_payload.push(b)
  }
  let moov2 = ga_test_box(
    ga_test_fourcc(0x6D, 0x6F, 0x6F, 0x76),
    ga_test_box(
      ga_test_fourcc(0x74, 0x72, 0x61, 0x6B),
      ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x69, 0x61), mdia2_payload),
    ),
  )
  let data : Array[Byte] = []
  for b in moov2 {
    data.push(b)
  }
  let mdat_payload : Array[Byte] = []
  for b in sample {
    mdat_payload.push(b)
  }
  for b in sample {
    mdat_payload.push(b)
  }
  let mdat = ga_test_box(ga_test_fourcc(0x6D, 0x64, 0x61, 0x74), mdat_payload)
  for b in mdat {
    data.push(b)
  }
  assert_true(avif_animation_descriptor(data) is Some(_))
  let animation = avif_decode_animation(data).unwrap()
  assert_eq(animation.frames.length(), 2)
  assert_eq(
    (animation.frames[0].image.width, animation.frames[1].image.height),
    (64, 64),
  )
  let frame0 = avif_decode_animation_frame(data, 0).unwrap()
  let frame1 = avif_decode_animation_frame(data, 15).unwrap()
  assert_eq((frame0.width, frame0.height), (64, 64))
  assert_eq((frame1.width, frame1.height), (64, 64))
  // Dimensions alone do not prove the samples were decoded. Both frames come
  // from the same still image, so each must equal an independent single-image
  // decode of that sample, sample for sample.
  // The sample is a bare AV1 payload, so the reference is a direct AV1 decode
  // of the same bytes rather than a single-image AVIF parse.
  let direct = av1_decode(sample).unwrap()
  assert_eq((direct.width, direct.height), (64, 64))
  for frame in [frame0, frame1] {
    for y in 0..<frame.height {
      for x in 0..<frame.width {
        assert_eq(frame.get_pixel(x, y), direct.get_pixel(x, y))
      }
    }
  }
}
