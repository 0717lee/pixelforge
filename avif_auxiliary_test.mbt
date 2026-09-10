fn aux_test_box(t : Array[Byte], payload : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  let n = payload.length() + 8
  out.push((n >> 24).to_byte()); out.push((n >> 16).to_byte()); out.push((n >> 8).to_byte()); out.push(n.to_byte())
  for b in t { out.push(b) }
  for b in payload { out.push(b) }
  out
}

fn aux_test_fourcc(a : Int, b : Int, c : Int, d : Int) -> Array[Byte] {
  [a.to_byte(), b.to_byte(), c.to_byte(), d.to_byte()]
}

test "alpha descriptor validates auxiliary item extents" {
  let infe = aux_test_box(aux_test_fourcc(0x69, 0x6E, 0x66, 0x65), [2, 0, 0, 0, 0, 2, 0, 0, 0x61, 0x75, 0x78, 0x6C, 0])
  let iinf_payload : Array[Byte] = [0, 0, 0, 0, 0, 1]
  for b in infe { iinf_payload.push(b) }
  let iinf = aux_test_box(aux_test_fourcc(0x69, 0x69, 0x6E, 0x66), iinf_payload)
  let iloc_payload : Array[Byte] = [1, 0, 0, 0, 0x44, 0x40, 0, 0, 0, 1, 0, 2, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
  let iloc = aux_test_box(aux_test_fourcc(0x69, 0x6C, 0x6F, 0x63), iloc_payload)
  let ispe = aux_test_box(aux_test_fourcc(0x69, 0x73, 0x70, 0x65), [0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2])
  let auxc = aux_test_box(aux_test_fourcc(0x61, 0x75, 0x78, 0x43), [0x75, 0x72, 0x6E, 0])
  let av1c = aux_test_box(aux_test_fourcc(0x61, 0x76, 0x31, 0x43), [0x81, 0, 0])
  let ipco_payload : Array[Byte] = []
  for b in ispe { ipco_payload.push(b) }; for b in auxc { ipco_payload.push(b) }; for b in av1c { ipco_payload.push(b) }
  let ipco = aux_test_box(aux_test_fourcc(0x69, 0x70, 0x63, 0x6F), ipco_payload)
  let ipma_payload : Array[Byte] = [0, 0, 0, 0, 0, 0, 0, 1, 0, 2, 3, 1, 2, 3]
  let ipma = aux_test_box(aux_test_fourcc(0x69, 0x70, 0x6D, 0x61), ipma_payload)
  let iprp_payload : Array[Byte] = []; for b in ipco { iprp_payload.push(b) }; for b in ipma { iprp_payload.push(b) }
  let iprp = aux_test_box(aux_test_fourcc(0x69, 0x70, 0x72, 0x70), iprp_payload)
  let idat = aux_test_box(aux_test_fourcc(0x69, 0x64, 0x61, 0x74), [0xAA])
  let meta_payload : Array[Byte] = [0, 0, 0, 0]
  for b in iinf { meta_payload.push(b) }; for b in iloc { meta_payload.push(b) }; for b in iprp { meta_payload.push(b) }; for b in idat { meta_payload.push(b) }
  let meta = aux_test_box(aux_test_fourcc(0x6D, 0x65, 0x74, 0x61), meta_payload)
  let parsed = avif_alpha_item_descriptor(meta).unwrap()
  assert_eq(parsed.item_id, 2)
  assert_eq((parsed.width, parsed.height, parsed.bit_depth), (2, 2, 8))
  assert_eq(parsed.extents.length(), 1)
  assert_eq((parsed.extents[0].offset, parsed.extents[0].length), (meta.length() - 1, 1))
  assert_eq(avif_alpha_item_payload(meta).unwrap(), [b'\xAA'])
}

test "alpha descriptor rejects malformed extent references" {
  let malformed : Array[Byte] = [0, 0, 0, 8, 0x6D, 0x65, 0x74, 0x61]
  assert_true(avif_alpha_item_descriptor(malformed) is None)
}


