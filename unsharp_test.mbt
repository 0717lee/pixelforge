///|
/// Unsharp mask tests: identity cases, flat-field invariance, and the
/// defining property that it steepens an existing edge.

///|
test "unsharp_mask with amount 0 or radius 0 is a copy" {
  let img = gray_image(4, 1, [10, 120, 60, 200])
  let a = img.unsharp_mask(2, 0.0)
  let b = img.unsharp_mask(0, 1.5)
  for i in 0..<(4 * 4) {
    assert_eq(a.data[i].to_int(), img.data[i].to_int())
    assert_eq(b.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "unsharp_mask leaves a flat field unchanged" {
  // original == blurred everywhere, so the detail term is zero.
  let img = solid(8, 6, 90, 140, 30, 255)
  let out = img.unsharp_mask(2, 2.0)
  for y in 0..<6 {
    for x in 0..<8 {
      let (r, g, b, alpha) = out.get_pixel(x, y)
      assert_eq(r.to_int(), 90)
      assert_eq(g.to_int(), 140)
      assert_eq(b.to_int(), 30)
      assert_eq(alpha.to_int(), 255)
    }
  }
}

///|
test "unsharp_mask steepens a step edge (overshoot/undershoot)" {
  // A vertical step from 80 to 160. After unsharp masking, the dark side of
  // the edge should dip below 80 and the bright side rise above 160.
  let img = @pixelforge.Image::new(8, 4)
  for y in 0..<4 {
    for x in 0..<8 {
      let v : Byte = if x < 4 { b'\x50' } else { b'\xA0' } // 80 / 160
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let out = img.unsharp_mask(1, 1.5)
  let dark = out.get_pixel(3, 2).0.to_int() // last dark column
  let bright = out.get_pixel(4, 2).0.to_int() // first bright column
  assert_true(dark < 80) // undershoot on the dark side
  assert_true(bright > 160) // overshoot on the bright side
}

///|
test "unsharp_mask preserves alpha" {
  let img = single(120, 120, 120, 42)
  assert_eq(img.unsharp_mask(2, 1.0).get_pixel(0, 0).3.to_int(), 42)
}
