///|
/// Tests the shared numeric dispatch used by every host binding.
test "apply_filter_id dispatches to the selected filter" {
  // id 1 = invert
  let inv = single(100, 200, 30, 255).apply_filter_id(1, 0.0)
  assert_eq(inv.get_pixel(0, 0).0.to_int(), 155)
  assert_eq(inv.get_pixel(0, 0).1.to_int(), 55)
  assert_eq(inv.get_pixel(0, 0).2.to_int(), 225)
  // id 0 = grayscale (luma of (100,200,30) is 150)
  assert_eq(
    single(100, 200, 30, 255).apply_filter_id(0, 0.0).get_pixel(0, 0).0.to_int(),
    150,
  )
  // unknown id = passthrough copy
  assert_eq(
    single(42, 7, 9, 255).apply_filter_id(999, 0.0).get_pixel(0, 0).0.to_int(),
    42,
  )
}

///|
test "filter id 21 dispatches to otsu" {
  // A bimodal image: id 21 must equal a direct otsu() call, byte for byte.
  let img = @pixelforge.Image::new(8, 8)
  for y in 0..<8 {
    for x in 0..<8 {
      let v : Byte = if x < 4 { b'\x1E' } else { b'\xD2' } // 30 / 210
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let via_id = img.apply_filter_id(21, 0.0)
  let direct = img.otsu()
  for i in 0..<(8 * 8 * 4) {
    assert_eq(via_id.data[i].to_int(), direct.data[i].to_int())
  }
}
