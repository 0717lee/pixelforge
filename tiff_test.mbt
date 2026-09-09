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
