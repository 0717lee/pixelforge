///| LBP descriptor tests.

test "lbp histogram ignores incomplete border and recognises flat texture" {
  let img = @pixelforge.Image::new(5, 4)
  for y in 0..<4 {
    for x in 0..<5 {
      img.set_pixel(x, y, b'\x7B', b'\x7B', b'\x7B', b'\xFF')
    }
  }
  let codes = img.lbp_codes()
  let histogram = img.lbp_histogram()
  // 3*2 interior pixels; equal neighbours set all eight bits.
  assert_eq(histogram[255], 6)
  let mut total = 0
  for i in 0..<256 {
    total = total + histogram[i]
  }
  assert_eq(total, 6)
  assert_eq(codes[0], 0)
  assert_eq(codes[1 * 5 + 1], b'\xFF')
}

test "lbp codes follow clockwise bit order" {
  let img = @pixelforge.Image::new(3, 3)
  // Centre is 100.  Only top-left and bottom-right are brighter, producing
  // bits 0 and 4 in the documented clockwise order.
  for y in 0..<3 {
    for x in 0..<3 {
      img.set_pixel(x, y, b'\x00', b'\x00', b'\x00', b'\xFF')
    }
  }
  img.set_pixel(1, 1, b'\x64', b'\x64', b'\x64', b'\xFF')
  img.set_pixel(0, 0, b'\xC8', b'\xC8', b'\xC8', b'\xFF')
  img.set_pixel(2, 2, b'\xC8', b'\xC8', b'\xC8', b'\xFF')
  let codes = img.lbp_codes()
  assert_eq(codes[4], b'\x11')
  let histogram = img.lbp_histogram()
  assert_eq(histogram[0x11], 1)
}

test "lbp histogram is empty for images without an interior" {
  let histogram = @pixelforge.Image::new(2, 7).lbp_histogram()
  for i in 0..<256 {
    assert_eq(histogram[i], 0)
  }
}
