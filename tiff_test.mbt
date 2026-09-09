///|
fn put_tiff16(data : Array[Byte], p : Int, value : Int) -> Unit {
  data[p] = (value & 255).to_byte()
  data[p + 1] = (value >> 8).to_byte()
}

///|
fn put_tiff32(data : Array[Byte], p : Int, value : Int) -> Unit {
  put_tiff16(data, p, value)
  put_tiff16(data, p + 2, value >> 16)
}

///|
fn put_tiff64(data : Array[Byte], p : Int, value : Int) -> Unit {
  put_tiff32(data, p, value)
  put_tiff32(data, p + 4, 0)
}

///|
fn tiff_lzw_fixture_bytes() -> Array[Byte] {
  let codes : Array[Int] = [256, 77, 257]
  let out : Array[Byte] = []
  let mut bits = 0
  for code in codes {
    for shift in 0..<9 {
      let bit = (code >> (8 - shift)) & 1
      let index = bits / 8
      if index >= out.length() { out.push(b'\x00') }
      if bit != 0 { out[index] = (out[index].to_int() | (1 << (7 - bits % 8))).to_byte() }
      bits = bits + 1
    }
  }
  out
}

///|
test "tiff_decode reads a baseline little-endian rgb strip" {
  let data : Array[Byte] = Array::make(131, b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 42); put_tiff32(data, 4, 8)
  put_tiff16(data, 8, 9)
  let entry = fn(index : Int) -> Int { 10 + index * 12 }
  put_tiff16(data, entry(0), 256); put_tiff16(data, entry(0) + 2, 4); put_tiff32(data, entry(0) + 4, 1); put_tiff32(data, entry(0) + 8, 1)
  put_tiff16(data, entry(1), 257); put_tiff16(data, entry(1) + 2, 4); put_tiff32(data, entry(1) + 4, 1); put_tiff32(data, entry(1) + 8, 1)
  put_tiff16(data, entry(2), 258); put_tiff16(data, entry(2) + 2, 3); put_tiff32(data, entry(2) + 4, 3); put_tiff32(data, entry(2) + 8, 122)
  put_tiff16(data, entry(3), 259); put_tiff16(data, entry(3) + 2, 3); put_tiff32(data, entry(3) + 4, 1); put_tiff16(data, entry(3) + 8, 1)
  put_tiff16(data, entry(4), 262); put_tiff16(data, entry(4) + 2, 3); put_tiff32(data, entry(4) + 4, 1); put_tiff16(data, entry(4) + 8, 2)
  put_tiff16(data, entry(5), 273); put_tiff16(data, entry(5) + 2, 4); put_tiff32(data, entry(5) + 4, 1); put_tiff32(data, entry(5) + 8, 128)
  put_tiff16(data, entry(6), 277); put_tiff16(data, entry(6) + 2, 3); put_tiff32(data, entry(6) + 4, 1); put_tiff16(data, entry(6) + 8, 3)
  put_tiff16(data, entry(7), 278); put_tiff16(data, entry(7) + 2, 4); put_tiff32(data, entry(7) + 4, 1); put_tiff32(data, entry(7) + 8, 1)
  put_tiff16(data, entry(8), 279); put_tiff16(data, entry(8) + 2, 4); put_tiff32(data, entry(8) + 4, 1); put_tiff32(data, entry(8) + 8, 3)
  data[122] = 8; data[124] = 8; data[126] = 8
  data[128] = b'\x11'; data[129] = b'\x22'; data[130] = b'\x33'
  let image = tiff_decode(data).unwrap()
  assert_eq(image.width, 1)
  assert_eq(image.height, 1)
  let (r, g, b, a) = image.get_pixel(0, 0)
  assert_eq((r.to_int(), g.to_int(), b.to_int(), a.to_int()), (17, 34, 51, 255))
}

///|
test "tiff_decode expands a PackBits grayscale strip" {
  let data : Array[Byte] = Array::make(124, b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 42); put_tiff32(data, 4, 8)
  put_tiff16(data, 8, 9)
  let entry = fn(index : Int) -> Int { 10 + index * 12 }
  put_tiff16(data, entry(0), 256); put_tiff16(data, entry(0) + 2, 4); put_tiff32(data, entry(0) + 4, 1); put_tiff32(data, entry(0) + 8, 1)
  put_tiff16(data, entry(1), 257); put_tiff16(data, entry(1) + 2, 4); put_tiff32(data, entry(1) + 4, 1); put_tiff32(data, entry(1) + 8, 1)
  put_tiff16(data, entry(2), 258); put_tiff16(data, entry(2) + 2, 3); put_tiff32(data, entry(2) + 4, 1); put_tiff16(data, entry(2) + 8, 8)
  put_tiff16(data, entry(3), 259); put_tiff16(data, entry(3) + 2, 3); put_tiff32(data, entry(3) + 4, 1); put_tiff16(data, entry(3) + 8, 32773)
  put_tiff16(data, entry(4), 262); put_tiff16(data, entry(4) + 2, 3); put_tiff32(data, entry(4) + 4, 1); put_tiff16(data, entry(4) + 8, 1)
  put_tiff16(data, entry(5), 273); put_tiff16(data, entry(5) + 2, 4); put_tiff32(data, entry(5) + 4, 1); put_tiff32(data, entry(5) + 8, 122)
  put_tiff16(data, entry(6), 278); put_tiff16(data, entry(6) + 2, 4); put_tiff32(data, entry(6) + 4, 1); put_tiff32(data, entry(6) + 8, 1)
  put_tiff16(data, entry(7), 279); put_tiff16(data, entry(7) + 2, 4); put_tiff32(data, entry(7) + 4, 1); put_tiff32(data, entry(7) + 8, 2)
  put_tiff16(data, entry(8), 284); put_tiff16(data, entry(8) + 2, 3); put_tiff32(data, entry(8) + 4, 1); put_tiff16(data, entry(8) + 8, 1)
  data[122] = 0; data[123] = 77
  let image = tiff_decode(data).unwrap()
  let (r, g, b, a) = image.get_pixel(0, 0)
  assert_eq((r.to_int(), g.to_int(), b.to_int(), a.to_int()), (77, 77, 77, 255))
}

///|
test "tiff_decode expands a TIFF LZW grayscale strip" {
  let compressed = tiff_lzw_fixture_bytes()
  let data : Array[Byte] = Array::make(122 + compressed.length(), b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 42); put_tiff32(data, 4, 8)
  put_tiff16(data, 8, 9)
  let entry = fn(index : Int) -> Int { 10 + index * 12 }
  put_tiff16(data, entry(0), 256); put_tiff16(data, entry(0) + 2, 4); put_tiff32(data, entry(0) + 4, 1); put_tiff32(data, entry(0) + 8, 1)
  put_tiff16(data, entry(1), 257); put_tiff16(data, entry(1) + 2, 4); put_tiff32(data, entry(1) + 4, 1); put_tiff32(data, entry(1) + 8, 1)
  put_tiff16(data, entry(2), 258); put_tiff16(data, entry(2) + 2, 3); put_tiff32(data, entry(2) + 4, 1); put_tiff16(data, entry(2) + 8, 8)
  put_tiff16(data, entry(3), 259); put_tiff16(data, entry(3) + 2, 3); put_tiff32(data, entry(3) + 4, 1); put_tiff16(data, entry(3) + 8, 5)
  put_tiff16(data, entry(4), 262); put_tiff16(data, entry(4) + 2, 3); put_tiff32(data, entry(4) + 4, 1); put_tiff16(data, entry(4) + 8, 1)
  put_tiff16(data, entry(5), 273); put_tiff16(data, entry(5) + 2, 4); put_tiff32(data, entry(5) + 4, 1); put_tiff32(data, entry(5) + 8, 122)
  put_tiff16(data, entry(6), 278); put_tiff16(data, entry(6) + 2, 4); put_tiff32(data, entry(6) + 4, 1); put_tiff32(data, entry(6) + 8, 1)
  put_tiff16(data, entry(7), 279); put_tiff16(data, entry(7) + 2, 4); put_tiff32(data, entry(7) + 4, 1); put_tiff32(data, entry(7) + 8, compressed.length())
  put_tiff16(data, entry(8), 284); put_tiff16(data, entry(8) + 2, 3); put_tiff32(data, entry(8) + 4, 1); put_tiff16(data, entry(8) + 8, 1)
  for i in 0..<compressed.length() { data[122 + i] = compressed[i] }
  let image = tiff_decode(data).unwrap()
  assert_eq(image.get_pixel(0, 0).0.to_int(), 77)
}

///|
test "tiff_decode reads multiple uncompressed strips" {
  let data : Array[Byte] = Array::make(140, b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 42); put_tiff32(data, 4, 8)
  put_tiff16(data, 8, 9)
  let entry = fn(index : Int) -> Int { 10 + index * 12 }
  put_tiff16(data, entry(0), 256); put_tiff16(data, entry(0) + 2, 4); put_tiff32(data, entry(0) + 4, 1); put_tiff32(data, entry(0) + 8, 1)
  put_tiff16(data, entry(1), 257); put_tiff16(data, entry(1) + 2, 4); put_tiff32(data, entry(1) + 4, 1); put_tiff32(data, entry(1) + 8, 2)
  put_tiff16(data, entry(2), 258); put_tiff16(data, entry(2) + 2, 3); put_tiff32(data, entry(2) + 4, 1); put_tiff16(data, entry(2) + 8, 8)
  put_tiff16(data, entry(3), 259); put_tiff16(data, entry(3) + 2, 3); put_tiff32(data, entry(3) + 4, 1); put_tiff16(data, entry(3) + 8, 1)
  put_tiff16(data, entry(4), 262); put_tiff16(data, entry(4) + 2, 3); put_tiff32(data, entry(4) + 4, 1); put_tiff16(data, entry(4) + 8, 1)
  put_tiff16(data, entry(5), 273); put_tiff16(data, entry(5) + 2, 4); put_tiff32(data, entry(5) + 4, 2); put_tiff32(data, entry(5) + 8, 122)
  put_tiff16(data, entry(6), 278); put_tiff16(data, entry(6) + 2, 4); put_tiff32(data, entry(6) + 4, 1); put_tiff32(data, entry(6) + 8, 1)
  put_tiff16(data, entry(7), 279); put_tiff16(data, entry(7) + 2, 4); put_tiff32(data, entry(7) + 4, 2); put_tiff32(data, entry(7) + 8, 130)
  put_tiff16(data, entry(8), 284); put_tiff16(data, entry(8) + 2, 3); put_tiff32(data, entry(8) + 4, 1); put_tiff16(data, entry(8) + 8, 1)
  put_tiff32(data, 122, 138); put_tiff32(data, 126, 139)
  put_tiff32(data, 130, 1); put_tiff32(data, 134, 1)
  data[138] = 10; data[139] = 20
  let image = tiff_decode(data).unwrap()
  assert_eq(image.height, 2)
  assert_eq(image.get_pixel(0, 0).0.to_int(), 10)
  assert_eq(image.get_pixel(0, 1).0.to_int(), 20)
}

///|
test "tiff_decode reads a minimal BigTIFF strip" {
  let data : Array[Byte] = Array::make(213, b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 43); put_tiff16(data, 4, 8); put_tiff16(data, 6, 0); put_tiff64(data, 8, 16)
  put_tiff64(data, 16, 9)
  let entry = fn(index : Int) -> Int { 24 + index * 20 }
  let set_entry = fn(index : Int, tag : Int, kind : Int, value : Int) {
    put_tiff16(data, entry(index), tag); put_tiff16(data, entry(index) + 2, kind); put_tiff64(data, entry(index) + 4, 1); put_tiff64(data, entry(index) + 12, value)
  }
  set_entry(0, 256, 4, 1); set_entry(1, 257, 4, 1); set_entry(2, 258, 3, 8); set_entry(3, 259, 3, 1); set_entry(4, 262, 3, 1)
  set_entry(5, 273, 16, 212); set_entry(6, 277, 3, 1); set_entry(7, 278, 4, 1); set_entry(8, 279, 16, 1)
  data[212] = 99
  let image = tiff_decode(data).unwrap()
  assert_eq(image.get_pixel(0, 0).0.to_int(), 99)
}

///|
test "tiff_decode reads a tiled grayscale image" {
  let data : Array[Byte] = Array::make(136, b'\x00')
  data[0] = b'I'; data[1] = b'I'; put_tiff16(data, 2, 42); put_tiff32(data, 4, 8)
  put_tiff16(data, 8, 10)
  let entry = fn(index : Int) -> Int { 10 + index * 12 }
  put_tiff16(data, entry(0), 256); put_tiff16(data, entry(0) + 2, 4); put_tiff32(data, entry(0) + 4, 1); put_tiff32(data, entry(0) + 8, 2)
  put_tiff16(data, entry(1), 257); put_tiff16(data, entry(1) + 2, 4); put_tiff32(data, entry(1) + 4, 1); put_tiff32(data, entry(1) + 8, 1)
  put_tiff16(data, entry(2), 258); put_tiff16(data, entry(2) + 2, 3); put_tiff32(data, entry(2) + 4, 1); put_tiff16(data, entry(2) + 8, 8)
  put_tiff16(data, entry(3), 259); put_tiff16(data, entry(3) + 2, 3); put_tiff32(data, entry(3) + 4, 1); put_tiff16(data, entry(3) + 8, 1)
  put_tiff16(data, entry(4), 262); put_tiff16(data, entry(4) + 2, 3); put_tiff32(data, entry(4) + 4, 1); put_tiff16(data, entry(4) + 8, 1)
  put_tiff16(data, entry(5), 277); put_tiff16(data, entry(5) + 2, 3); put_tiff32(data, entry(5) + 4, 1); put_tiff16(data, entry(5) + 8, 1)
  put_tiff16(data, entry(6), 322); put_tiff16(data, entry(6) + 2, 4); put_tiff32(data, entry(6) + 4, 1); put_tiff32(data, entry(6) + 8, 2)
  put_tiff16(data, entry(7), 323); put_tiff16(data, entry(7) + 2, 4); put_tiff32(data, entry(7) + 4, 1); put_tiff32(data, entry(7) + 8, 1)
  put_tiff16(data, entry(8), 324); put_tiff16(data, entry(8) + 2, 4); put_tiff32(data, entry(8) + 4, 1); put_tiff32(data, entry(8) + 8, 134)
  put_tiff16(data, entry(9), 325); put_tiff16(data, entry(9) + 2, 4); put_tiff32(data, entry(9) + 4, 1); put_tiff32(data, entry(9) + 8, 2)
  data[134] = 12; data[135] = 34
  let image = tiff_decode(data).unwrap()
  assert_eq(image.get_pixel(0, 0).0.to_int(), 12)
  assert_eq(image.get_pixel(1, 0).0.to_int(), 34)
}
