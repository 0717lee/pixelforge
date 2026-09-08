///|
/// Hand-counted measurements for connected-component region properties.

///|
fn regionprops_solid(
  width : Int,
  height : Int,
  value : Int,
) -> @pixelforge.Image {
  let image = @pixelforge.Image::new(width, height)
  let channel = @pixelforge.clamp_byte(value)
  for y in 0..<height {
    for x in 0..<width {
      image.set_pixel(x, y, channel, channel, channel, b'\xFF')
    }
  }
  image
}

///|
test "regionprops reports a single pixel" {
  let image = regionprops_solid(4, 3, 0)
  image.set_pixel(2, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let regions = image.regionprops(128)
  assert_eq(regions.length(), 1)
  let region = regions[0]
  assert_eq(region.label, 1)
  assert_eq(region.area, 1)
  assert_eq(region.min_x, 2)
  assert_eq(region.min_y, 1)
  assert_eq(region.max_x, 2)
  assert_eq(region.max_y, 1)
  assert_true(region.centroid_x == 2.0 && region.centroid_y == 1.0)
}

///|
test "regionprops separates regions and computes rectangular centroid" {
  let image = regionprops_solid(8, 6, 0)
  image.fill_rect(1, 1, 2, 3, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  image.fill_rect(5, 3, 2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let regions = image.regionprops(128)
  assert_eq(regions.length(), 2)
  let first = regions[0]
  assert_eq(first.label, 1)
  assert_eq(first.area, 6)
  assert_eq(first.min_x, 1)
  assert_eq(first.min_y, 1)
  assert_eq(first.max_x, 2)
  assert_eq(first.max_y, 3)
  assert_true((first.centroid_x - 1.5) * (first.centroid_x - 1.5) < 1.0e-18)
  assert_true((first.centroid_y - 2.0) * (first.centroid_y - 2.0) < 1.0e-18)
  let second = regions[1]
  assert_eq(second.label, 2)
  assert_eq(second.area, 4)
  assert_eq(second.min_x, 5)
  assert_eq(second.min_y, 3)
  assert_eq(second.max_x, 6)
  assert_eq(second.max_y, 4)
  assert_true(second.centroid_x == 5.5 && second.centroid_y == 3.5)
}

///|
test "regionprops uses strict luma threshold and four connectivity" {
  let image = regionprops_solid(3, 2, 0)
  image.set_pixel(0, 0, b'\x80', b'\x80', b'\x80', b'\xFF')
  image.set_pixel(1, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let regions = image.regionprops(128)
  assert_eq(regions.length(), 1)
  assert_eq(regions[0].area, 1)
  assert_eq(regions[0].min_x, 1)
  assert_eq(regions[0].min_y, 1)
}

///|
test "regionprops returns no regions for an empty foreground" {
  let regions = regionprops_solid(5, 4, 0).regionprops(0)
  assert_eq(regions.length(), 0)
  assert_eq(@pixelforge.Image::new(0, 0).regionprops(0).length(), 0)
}
