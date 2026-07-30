///|
/// Integral image / box blur tests: the SAT reproduces exact rectangle sums,
/// box_blur(1) matches a hand-averaged 3x3 mean, and flat fields are fixed.

///|
test "integral image rectangle sum equals the exact pixel sum" {
  // 4x4 red ramp: pixel (x,y) has red = y*4 + x (0..15).
  let img = @pixelforge.Image::new(4, 4)
  for y in 0..<4 {
    for x in 0..<4 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(y * 4 + x),
        b'\x00',
        b'\x00',
        b'\xFF',
      )
    }
  }
  let sat = img.integral_image()
  // Whole image: 0+1+...+15 = 120.
  assert_eq(sat.rect_sum(0, 0, 0, 3, 3).to_int(), 120)
  // Inner 2x2 rectangle [1,1]..[2,2]: values 5,6,9,10 = 30.
  assert_eq(sat.rect_sum(0, 1, 1, 2, 2).to_int(), 30)
  // A single pixel (3,3) = 15.
  assert_eq(sat.rect_sum(0, 3, 3, 3, 3).to_int(), 15)
}

///|
test "box_blur keeps a flat field unchanged" {
  let img = solid(8, 6, 70, 130, 210, 255)
  let out = img.box_blur(2)
  for y in 0..<6 {
    for x in 0..<8 {
      let (r, g, b, a) = out.get_pixel(x, y)
      assert_eq(r.to_int(), 70)
      assert_eq(g.to_int(), 130)
      assert_eq(b.to_int(), 210)
      assert_eq(a.to_int(), 255)
    }
  }
}

///|
test "box_blur(1) equals a hand-averaged 3x3 mean at the center" {
  // Center pixel (1,1) of a 3x3: mean of all nine reds, rounded.
  let img = @pixelforge.Image::new(3, 3)
  let reds = [10, 20, 30, 40, 50, 60, 70, 80, 90]
  for y in 0..<3 {
    for x in 0..<3 {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(reds[y * 3 + x]),
        b'\x00',
        b'\x00',
        b'\xFF',
      )
    }
  }
  let out = img.box_blur(1)
  // sum = 450, count = 9, rounded mean = (450 + 4) / 9 = 50.
  assert_eq(out.get_pixel(1, 1).0.to_int(), 50)
}

///|
test "box_blur(0) is an exact copy" {
  let img = gray_image(4, 1, [10, 200, 30, 90])
  let out = img.box_blur(0)
  for i in 0..<(4 * 4) {
    assert_eq(out.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "box_blur corner averages only the in-bounds window" {
  // Top-left corner with radius 1 sees only the 2x2 block (0,0)..(1,1).
  let img = @pixelforge.Image::new(3, 3)
  for y in 0..<3 {
    for x in 0..<3 {
      let v : Byte = if x < 2 && y < 2 { b'\x64' } else { b'\x00' } // 100 / 0
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  // Corner (0,0): window (0,0)..(1,1) all 100 -> mean 100.
  let out = img.box_blur(1)
  assert_eq(out.get_pixel(0, 0).0.to_int(), 100)
}
