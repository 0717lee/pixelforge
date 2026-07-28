///|
/// Compositing tests with hand-computed expectations for every blend mode
/// and the alpha edge cases.

///|
test "opaque normal replaces, transparent top preserves" {
  let bottom = solid(3, 2, 10, 20, 30, 255)
  let top = solid(3, 2, 200, 150, 100, 255)
  let over = bottom.composite(top, @pixelforge.BlendMode::Normal)
  let (r, g, b, a) = over.get_pixel(1, 1)
  assert_eq(r.to_int(), 200)
  assert_eq(g.to_int(), 150)
  assert_eq(b.to_int(), 100)
  assert_eq(a.to_int(), 255)
  let clear = solid(3, 2, 200, 150, 100, 0)
  let kept = bottom.composite(clear, @pixelforge.BlendMode::Normal)
  let (kr, kg, kb, ka) = kept.get_pixel(0, 0)
  assert_eq(kr.to_int(), 10)
  assert_eq(kg.to_int(), 20)
  assert_eq(kb.to_int(), 30)
  assert_eq(ka.to_int(), 255)
}

///|
test "blend modes match hand-computed values on opaque layers" {
  // cb = 100, cs = 200, both fully opaque.
  let bottom = solid(1, 1, 100, 100, 100, 255)
  let top = solid(1, 1, 200, 200, 200, 255)
  // Multiply: round(100*200/255) = round(78.43) = 78.
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Multiply).get_pixel(0, 0).0.to_int(),
    78,
  )
  // Screen: 255 - round(155*55/255) = 255 - 33 = 222.
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Screen).get_pixel(0, 0).0.to_int(),
    222,
  )
  // Darken -> 100, Lighten -> 200, Difference -> 100, Add -> 255 (clamped).
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Darken).get_pixel(0, 0).0.to_int(),
    100,
  )
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Lighten).get_pixel(0, 0).0.to_int(),
    200,
  )
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Difference).get_pixel(0, 0).0.to_int(),
    100,
  )
  assert_eq(
    bottom.composite(top, @pixelforge.BlendMode::Add).get_pixel(0, 0).0.to_int(),
    255,
  )
}

///|
test "overlay switches formula at the backdrop midpoint" {
  // cb = 64 < 128: round(2*64*192/255) = round(96.4) = 96.
  let dark = solid(1, 1, 64, 64, 64, 255)
  let src = solid(1, 1, 192, 192, 192, 255)
  assert_eq(
    dark.composite(src, @pixelforge.BlendMode::Overlay).get_pixel(0, 0).0.to_int(),
    96,
  )
  // cb = 200 >= 128: 255 - round(2*55*63/255) = 255 - 27 = 228.
  let bright = solid(1, 1, 200, 200, 200, 255)
  let s2 = solid(1, 1, 192, 192, 192, 255)
  assert_eq(
    bright.composite(s2, @pixelforge.BlendMode::Overlay).get_pixel(0, 0).0.to_int(),
    228,
  )
}

///|
test "half-transparent normal composite lands between the layers" {
  // cb = 100 (opaque), cs = 200 at alpha 128:
  // ao = 128 + round(127*255/255) = 255,
  // c = round((128*200 + 127*100) / 255) = round(150.7) = 150.
  let bottom = solid(1, 1, 100, 100, 100, 255)
  let top = solid(1, 1, 200, 200, 200, 128)
  let out = bottom.composite(top, @pixelforge.BlendMode::Normal)
  let (r, _, _, a) = out.get_pixel(0, 0)
  assert_eq(r.to_int(), 150)
  assert_eq(a.to_int(), 255)
}

///|
test "compositing onto a fully transparent backdrop keeps the source" {
  // ab = 0: the blend result must collapse to plain source (spec: mixing
  // toward B by backdrop alpha), and ao = as.
  let bottom = solid(1, 1, 40, 50, 60, 0)
  let top = solid(1, 1, 200, 150, 100, 128)
  let out = bottom.composite(top, @pixelforge.BlendMode::Multiply)
  let (r, g, b, a) = out.get_pixel(0, 0)
  assert_eq(r.to_int(), 200)
  assert_eq(g.to_int(), 150)
  assert_eq(b.to_int(), 100)
  assert_eq(a.to_int(), 128)
}
