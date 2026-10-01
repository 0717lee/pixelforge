///|
// Same bytes as assets/avif/grayscale.avif. Generated from eight gray pixels
// with FFmpeg/libaom; expected RGBA independently decoded with libdav1d.
// See assets/avif/README.md for regeneration.
fn avif_sample() -> Array[Byte] {
  [
    b'\x00', b'\x00', b'\x00', b'\x20', b'\x66', b'\x74', b'\x79', b'\x70', b'\x61',
    b'\x76', b'\x69', b'\x66', b'\x00', b'\x00', b'\x00', b'\x00', b'\x61', b'\x76',
    b'\x69', b'\x66', b'\x6D', b'\x69', b'\x66', b'\x31', b'\x6D', b'\x69', b'\x61',
    b'\x66', b'\x4D', b'\x41', b'\x31', b'\x41', b'\x00', b'\x00', b'\x00', b'\xF9',
    b'\x6D', b'\x65', b'\x74', b'\x61', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x2F', b'\x68', b'\x64', b'\x6C', b'\x72', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x70', b'\x69', b'\x63',
    b'\x74', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x50', b'\x69', b'\x63', b'\x74', b'\x75',
    b'\x72', b'\x65', b'\x48', b'\x61', b'\x6E', b'\x64', b'\x6C', b'\x65', b'\x72',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x0E', b'\x70', b'\x69', b'\x74', b'\x6D',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x1E', b'\x69', b'\x6C', b'\x6F', b'\x63', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x44', b'\x00', b'\x00', b'\x01', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x00', b'\x00', b'\x01', b'\x21', b'\x00', b'\x00', b'\x00', b'\x27',
    b'\x00', b'\x00', b'\x00', b'\x28', b'\x69', b'\x69', b'\x6E', b'\x66', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00', b'\x1A',
    b'\x69', b'\x6E', b'\x66', b'\x65', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x00', b'\x00', b'\x61', b'\x76', b'\x30', b'\x31', b'\x43', b'\x6F',
    b'\x6C', b'\x6F', b'\x72', b'\x00', b'\x00', b'\x00', b'\x00', b'\x6A', b'\x69',
    b'\x70', b'\x72', b'\x70', b'\x00', b'\x00', b'\x00', b'\x4B', b'\x69', b'\x70',
    b'\x63', b'\x6F', b'\x00', b'\x00', b'\x00', b'\x14', b'\x69', b'\x73', b'\x70',
    b'\x65', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x04',
    b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x10', b'\x70',
    b'\x69', b'\x78', b'\x69', b'\x00', b'\x00', b'\x00', b'\x00', b'\x03', b'\x08',
    b'\x08', b'\x08', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x61', b'\x76', b'\x31',
    b'\x43', b'\x81', b'\x20', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13',
    b'\x63', b'\x6F', b'\x6C', b'\x72', b'\x6E', b'\x63', b'\x6C', b'\x78', b'\x00',
    b'\x02', b'\x00', b'\x02', b'\x00', b'\x02', b'\x80', b'\x00', b'\x00', b'\x00',
    b'\x17', b'\x69', b'\x70', b'\x6D', b'\x61', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x01', b'\x04', b'\x01', b'\x02',
    b'\x83', b'\x04', b'\x00', b'\x00', b'\x00', b'\x2F', b'\x6D', b'\x64', b'\x61',
    b'\x74', b'\x0A', b'\x09', b'\x20', b'\x00', b'\x00', b'\x00', b'\x87', b'\x36',
    b'\xBE', b'\x64', b'\x80', b'\x32', b'\x1A', b'\x10', b'\x00', b'\x80', b'\x00',
    b'\x21', b'\x05', b'\xF8', b'\x35', b'\xDE', b'\x49', b'\x42', b'\x4A', b'\x12',
    b'\x35', b'\x59', b'\x47', b'\xF1', b'\xDD', b'\x7C', b'\xF0', b'\x0C', b'\x44',
    b'\x8A', b'\x22', b'\x32', b'\xE8',
  ]
}

///|
test "avif adapter matches independent RGBA reference and feeds filters" {
  let image = @pixelforge.avif_decode(avif_sample()).unwrap()
  assert_eq((image.width, image.height), (4, 2))
  let levels = [0, 32, 64, 96, 128, 160, 192, 255]
  for i in 0..<levels.length() {
    let value = levels[i].to_byte()
    assert_eq(image.get_pixel(i % 4, i / 4), (value, value, value, b'\xFF'))
  }
  let output = @pixelforge.png_decode(@pixelforge.png_encode(image.invert())).unwrap()
  for i in 0..<levels.length() {
    let value = (255 - levels[i]).to_byte()
    assert_eq(output.get_pixel(i % 4, i / 4), (value, value, value, b'\xFF'))
  }
}

///|
test "avif adapter rejects every truncated prefix and wrong container" {
  let data = avif_sample()
  for n in 0..<data.length() {
    let prefix = Array::makei(n, i => data[i])
    assert_true(@pixelforge.avif_decode(prefix) is None)
  }
  assert_true(@pixelforge.avif_decode([b'B', b'M', b'\x00', b'\x00']) is None)
}

///|
test "avif adapter returns owned pixels independent of input and other decodes" {
  let data = avif_sample()
  let image = @pixelforge.avif_decode(data).unwrap()
  let other = @pixelforge.avif_decode(data).unwrap()
  data[0] = b'\xFF'
  image.set_pixel(0, 0, b'\x01', b'\x02', b'\x03', b'\x04')
  assert_eq(other.get_pixel(0, 0), (b'\x00', b'\x00', b'\x00', b'\xFF'))
}
