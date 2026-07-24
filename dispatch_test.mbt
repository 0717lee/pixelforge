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
