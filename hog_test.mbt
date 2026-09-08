///| HOG descriptor tests.

test "hog returns normalized block with deterministic orientation bins" {
  let image = @pixelforge.Image::new(4, 4)
  // A horizontal luminance ramp gives a single unsigned orientation at 0.
  for y in 0..<4 {
    for x in 0..<4 {
      let value = (x * 40).to_byte()
      image.set_pixel(x, y, value, value, value, b'\xFF')
    }
  }
  let descriptor = image.hog(2, 4, 1)
  assert_eq(descriptor.length(), 16)
  // Each 2x2 cell contributes the same horizontal gradient; each normalized
  // one-cell block has unit L2 norm and all energy in bin zero.
  for cell in 0..<4 {
    let base = cell * 4
    assert_true(descriptor[base] > 0.99)
    assert_true(descriptor[base + 1] < 1.0e-9)
    assert_true(descriptor[base + 2] < 1.0e-9)
    assert_true(descriptor[base + 3] < 1.0e-9)
  }
}

test "hog ignores incomplete cells and emits overlapping block layout" {
  let image = @pixelforge.Image::new(5, 5)
  let descriptor = image.hog(2, 9, 2)
  // 2x2 complete cells, one 2x2 block, nine bins per cell.
  assert_eq(descriptor.length(), 36)
  for i in 0..<36 {
    assert_eq(descriptor[i], 0.0)
  }
}

test "hog rejects invalid parameters" {
  let image = @pixelforge.Image::new(2, 2)
  assert_eq(image.hog(3, 8, 1).length(), 0)
}
