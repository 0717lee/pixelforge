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

test "grid descriptor returns ordered tile items" {
  let data : Array[Byte] = [0,0,0,220,109,101,116,97,0,0,0,0,0,0,0,89,105,105,110,102,0,0,0,0,0,3,0,0,0,25,105,110,102,101,0,0,0,0,0,1,0,0,103,114,105,100,103,114,105,100,0,0,0,0,25,105,110,102,101,0,0,0,0,0,2,0,0,97,118,48,49,103,114,105,100,0,0,0,0,25,105,110,102,101,0,0,0,0,0,3,0,0,97,118,48,49,103,114,105,100,0,0,0,0,73,105,108,111,99,0,0,0,1,68,0,0,0,0,0,3,0,0,0,1,16,0,0,0,0,1,0,0,0,0,0,0,0,10,0,0,0,2,16,0,0,0,0,1,0,0,0,10,0,0,0,1,0,0,0,3,16,0,0,0,0,1,0,0,0,11,0,0,0,1,0,0,0,24,105,114,101,102,0,0,0,0,100,105,109,103,0,1,0,2,0,2,0,3,0,0,0,22,105,100,97,116,0,0,0,0,0,1,0,4,0,4,65,66,67,68]
  let g = avif_grid_descriptor(data).unwrap()
  assert_eq((g.item_id, g.rows, g.columns, g.output_width, g.output_height), (1, 1, 2, 4, 4))
  assert_eq(g.tiles.map(fn(t) { t.item_id }), [2, 3])
  assert_eq(g.tiles[0].extents[0].length, 1)
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
  let stco_payload : Array[Byte] = [0, 0, 0, 0, 0, 0, 0, 2]
  for b in ga_test_u32(100) {
    stco_payload.push(b)
  }
  for b in ga_test_u32(103) {
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
  assert_eq(parsed.frames[1].timestamp, 10)
}
