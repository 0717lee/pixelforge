///|
/// Independent libdav1d planar references for the three historical lossless
/// streams below: Y=504/2016/64, with neutral U/V. The old RGB=130 expectations
/// came from applying a 64x64 DCT to ONLY_4X4 syntax and were incorrect.
fn av1_lossless_reference_constant(
  image : Image,
  bit_depth : Int,
  luma : Int,
) -> Unit raise {
  let expected = av1_yuv420_highbd_to_rgba(
    64,
    64,
    Array::make(4096, luma),
    Array::make(1024, 1 << (bit_depth - 1)),
    Array::make(1024, 1 << (bit_depth - 1)),
    bit_depth,
  ).unwrap()
  assert_eq((image.width, image.height), (64, 64))
  for y in 0..<64 {
    for x in 0..<64 {
      assert_eq(image.get_pixel(x, y), expected.get_pixel(x, y))
    }
  }
}

///|
/// dav1d YUV SHA256: d0406eeb6f7c3a7eae1165b8f16b0e188d2c0f8f2c81265f1192e99797deb54d
test "10-bit qindex zero tile decodes" {
  let d : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xA8',
    b'\x08', b'\x32', b'\x0B', b'\x10', b'\x00', b'\x00', b'\x00', b'\x4B', b'\x18',
    b'\x0D', b'\xE4', b'\xBF', b'\xFF', b'\xA0',
  ]
  let image = av1_decode(d).unwrap()
  av1_lossless_reference_constant(image, 10, 504)
}

///|
/// dav1d YUV SHA256: 02f6d5d29f3b72b637120e71da8c45965247717b489a247aaf06d3dc32c954ee
test "12-bit qindex zero tile decodes" {
  let d : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x58', b'\x15', b'\x7F', b'\xFD', b'\xAC',
    b'\x61', b'\x32', b'\x0B', b'\x10', b'\x00', b'\x00', b'\x00', b'\x4B', b'\x17',
    b'\xDD', b'\x21', b'\x4B', b'\xFF', b'\xFA',
  ]
  let image = av1_decode(d).unwrap()
  av1_lossless_reference_constant(image, 12, 2016)
}

///|
/// dav1d YUV SHA256: 30ee7b53a3716c53affadcfbc5779ed7c7baab29745aba9dac431d1362ec93d0
test "10-bit lossless black frame reconstructs every 4x4 transform" {
  let d : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xA8',
    b'\x08', b'\x32', b'\x0C', b'\x10', b'\x00', b'\x00', b'\x00', b'\x4B', b'\x17',
    b'\xC0', b'\xF1', b'\xB4', b'\xCB', b'\xFF', b'\xFA',
  ]
  av1_lossless_reference_constant(av1_decode(d).unwrap(), 10, 64)
}

///|
/// A crafted profile-2 stream with non-zero 12-bit AC content exercises the
/// same coefficient/sign/transform path as the 8-bit cosine fixture.  The
/// assertion intentionally checks reconstruction and variation rather than
/// RGB rounding against an external limited-range converter.
test "12-bit AC residual stream reconstructs a varying image" {
  let d : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x58', b'\x15', b'\x7F', b'\xFC', b'\x0C',
    b'\x61', b'\x32', b'\x08', b'\x17', b'\x80', b'\x00', b'\x00', b'\x20', b'\x09',
    b'\x1C', b'\x30',
  ]
  let image = av1_decode(d).unwrap()
  assert_true(image.get_pixel(0, 0) != image.get_pixel(63, 63))
}
