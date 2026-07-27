///|
/// PNG internals verified against published reference vectors, plus a
/// hand-assembled fixed-Huffman DEFLATE stream that exercises the LZ77
/// copy path the stored-block encoder never emits.

///|
test "crc32 matches the canonical check vector" {
  // CRC-32("123456789") = 0xCBF43926 (the standard check value).
  let data : Array[Byte] = []
  for c in [49, 50, 51, 52, 53, 54, 55, 56, 57] {
    data.push(c.to_byte())
  }
  assert_eq(crc32(data, 0, 9), 0xCBF43926U)
}

///|
test "adler32 matches the canonical check vector" {
  // Adler-32("Wikipedia") = 0x11E60398 (the textbook example).
  let data : Array[Byte] = []
  for c in [87, 105, 107, 105, 112, 101, 100, 105, 97] {
    data.push(c.to_byte())
  }
  assert_eq(adler32(data, 0, 9), 0x11E60398U)
}

///|
test "zlib_inflate decodes a fixed-Huffman reference stream" {
  // zlib.compress(b"hello") — a widely published constant that uses one
  // fixed-Huffman block: 78 9c cb 48 cd c9 c9 07 00 + adler 06 2c 02 15.
  let z : Array[Byte] = []
  for
    c in [
      0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x06, 0x2C, 0x02, 0x15,
    ] {
    z.push(c.to_byte())
  }
  let raw = zlib_inflate(z, 0, z.length()).unwrap()
  let expect = [104, 101, 108, 108, 111] // "hello"
  assert_eq(raw.length(), 5)
  for i in 0..<5 {
    assert_eq(raw[i].to_int(), expect[i])
  }
}

///|
test "zlib_inflate handles LZ77 length/distance copies" {
  // Hand-assembled fixed-Huffman block producing "aaaaaa":
  // literal 'a', then <length 5, distance 1>, then end-of-block.
  // Bits: 1|01 (final, fixed) + 10010001 ('a') + 0000011 (len sym 259)
  // + 00000 (dist 0) + 0000000 (eob) => bytes 4B 04 03 00.
  // Adler-32("aaaaaa") = 0x07FB0247.
  let z : Array[Byte] = []
  for c in [0x78, 0x01, 0x4B, 0x04, 0x03, 0x00, 0x07, 0xFB, 0x02, 0x47] {
    z.push(c.to_byte())
  }
  let raw = zlib_inflate(z, 0, z.length()).unwrap()
  assert_eq(raw.length(), 6)
  for i in 0..<6 {
    assert_eq(raw[i].to_int(), 97)
  }
}

///|
test "zlib_inflate rejects a corrupted adler trailer" {
  let z : Array[Byte] = []
  for
    c in [
      0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x06, 0x2C, 0x02, 0x16,
    ] {
    z.push(c.to_byte())
  }
  assert_true(zlib_inflate(z, 0, z.length()) is None)
}
