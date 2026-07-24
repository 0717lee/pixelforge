///|
/// Blackbox tests exercise the library exactly as an external user would,
/// through the public `@pixelforge` API. Expected values are hand-computed so a
/// regression in the channel math shows up immediately.

///|
/// Builds a 1x1 image with the given RGBA channels, the smallest fixture that
/// still fully exercises a point filter.
fn single(r : Int, g : Int, b : Int, a : Int) -> @pixelforge.Image {
  let img = @pixelforge.Image::new(1, 1)
  img.set_pixel(
    0,
    0,
    @pixelforge.clamp_byte(r),
    @pixelforge.clamp_byte(g),
    @pixelforge.clamp_byte(b),
    @pixelforge.clamp_byte(a),
  )
  img
}

///|
test "grayscale collapses channels to Rec.601 luma and keeps alpha" {
  // y = (299*100 + 587*200 + 114*30) / 1000 = 150720 / 1000 = 150
  let (r, g, b, a) = single(100, 200, 30, 128).grayscale().get_pixel(0, 0)
  assert_eq(r.to_int(), 150)
  assert_eq(g.to_int(), 150)
  assert_eq(b.to_int(), 150)
  assert_eq(a.to_int(), 128)
}

///|
test "invert flips each channel around 255 and keeps alpha" {
  let (r, g, b, a) = single(100, 200, 30, 200).invert().get_pixel(0, 0)
  assert_eq(r.to_int(), 155)
  assert_eq(g.to_int(), 55)
  assert_eq(b.to_int(), 225)
  assert_eq(a.to_int(), 200)
}

///|
test "brightness shifts channels and saturates at 255" {
  let (r, g, b, _) = single(100, 200, 30, 255).brightness(50).get_pixel(0, 0)
  assert_eq(r.to_int(), 150)
  assert_eq(g.to_int(), 250)
  assert_eq(b.to_int(), 80)
}

///|
test "brightness with a negative delta darkens and floors at 0" {
  let (r, _, _, _) = single(40, 0, 0, 255).brightness(-100).get_pixel(0, 0)
  assert_eq(r.to_int(), 0)
}

///|
test "contrast scales around mid-gray and clamps" {
  // c=100 -> (100-128)*2 + 128 = 72 ; c=200 -> 272 -> clamp 255
  let (r, g, _, _) = single(100, 200, 128, 255).contrast(2.0).get_pixel(0, 0)
  assert_eq(r.to_int(), 72)
  assert_eq(g.to_int(), 255)
}

///|
test "original image is never mutated by a filter" {
  let img = single(10, 20, 30, 255)
  let _ = img.invert()
  let (r, g, b, _) = img.get_pixel(0, 0)
  assert_eq(r.to_int(), 10)
  assert_eq(g.to_int(), 20)
  assert_eq(b.to_int(), 30)
}
