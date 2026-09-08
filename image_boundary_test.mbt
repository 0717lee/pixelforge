///|
/// Image construction and access boundary tests.

///|
test "zero-sized images keep an empty, self-consistent buffer" {
  let wide_empty = @pixelforge.Image::new(0, 7)
  assert_eq(wide_empty.width, 0)
  assert_eq(wide_empty.height, 7)
  assert_eq(wide_empty.pixel_count(), 0)

  let tall_empty = @pixelforge.Image::new(9, 0)
  assert_eq(tall_empty.width, 9)
  assert_eq(tall_empty.height, 0)
  assert_eq(tall_empty.pixel_count(), 0)
}

///|
test "pixel access accepts every valid edge coordinate" {
  let img = @pixelforge.Image::new(2, 2)
  img.set_pixel(0, 0, b'\x01', b'\x02', b'\x03', b'\x04')
  img.set_pixel(1, 1, b'\xF1', b'\xF2', b'\xF3', b'\xF4')
  let (r0, g0, b0, a0) = img.get_pixel(0, 0)
  let (r1, g1, b1, a1) = img.get_pixel(1, 1)
  assert_eq(r0.to_int(), 1)
  assert_eq(g0.to_int(), 2)
  assert_eq(b0.to_int(), 3)
  assert_eq(a0.to_int(), 4)
  assert_eq(r1.to_int(), 241)
  assert_eq(g1.to_int(), 242)
  assert_eq(b1.to_int(), 243)
  assert_eq(a1.to_int(), 244)
}
