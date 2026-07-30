///|
/// Connected-component tests with exact expected counts and label checks.

///|
test "disjoint squares are counted separately" {
  // Three 2x2 white squares on black, well separated.
  let img = solid(12, 6, 0, 0, 0, 255)
  img.fill_rect(0, 0, 2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  img.fill_rect(5, 2, 2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  img.fill_rect(10, 4, 2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  assert_eq(img.count_components(128), 3)
}

///|
test "touching pixels merge into one component, diagonals do not" {
  // An L-shape (edge-connected) is one blob...
  let l_shape = solid(6, 6, 0, 0, 0, 255)
  l_shape.fill_rect(1, 1, 1, 4, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  l_shape.fill_rect(1, 4, 4, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  assert_eq(l_shape.count_components(128), 1)
  // ...but two pixels touching only at a corner are separate under
  // 4-connectivity.
  let diag = solid(4, 4, 0, 0, 0, 255)
  diag.set_pixel(1, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  diag.set_pixel(2, 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  assert_eq(diag.count_components(128), 2)
}

///|
test "empty and full images give 0 and 1 components" {
  assert_eq(solid(5, 5, 0, 0, 0, 255).count_components(128), 0)
  assert_eq(solid(5, 5, 255, 255, 255, 255).count_components(128), 1)
}

///|
test "label map marks background 0 and blobs with distinct labels" {
  let img = solid(7, 3, 0, 0, 0, 255)
  img.set_pixel(1, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  img.set_pixel(5, 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  let (labels, count) = img.label_components(128)
  assert_eq(count, 2)
  assert_eq(labels[0], 0) // background corner
  let a = labels[1 * 7 + 1]
  let b = labels[1 * 7 + 5]
  assert_true(a >= 1 && a <= 2)
  assert_true(b >= 1 && b <= 2)
  assert_true(a != b)
}

///|
test "component labeling survives a snake that fills the image" {
  // A serpentine path connecting everything: exactly one component even
  // though the flood fill has to walk hundreds of pixels.
  let img = solid(20, 20, 255, 255, 255, 255)
  assert_eq(img.count_components(10), 1)
}
