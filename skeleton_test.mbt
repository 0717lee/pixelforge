/// Zhang--Suen skeletonization tests.

fn skeleton_foreground_count(image : @pixelforge.Image) -> Int {
  let mut count = 0
  for y in 0..<7 {
    for x in 0..<7 {
      if image.get_pixel(x, y).0.to_int() > 0 {
        count = count + 1
      }
    }
  }
  count
}

test "skeletonize thresholds and preserves alpha" {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\xFF', b'\xFF', b'\xFF', b'\x2A')
  image.set_pixel(1, 0, b'\x10', b'\x10', b'\x10', b'\x7B')
  let out = image.skeletonize(128, 0)
  assert_eq(out.get_pixel(0, 0), (b'\xFF', b'\xFF', b'\xFF', b'\x2A'))
  assert_eq(out.get_pixel(1, 0), (b'\x00', b'\x00', b'\x00', b'\x7B'))
}

test "skeletonize thins a filled square deterministically" {
  let image = @pixelforge.Image::new(7, 7)
  for y in 1..<6 {
    for x in 1..<6 {
      image.set_pixel(x, y, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
    }
  }
  let first = image.skeletonize(128, 32)
  let second = image.skeletonize(128, 32)
  assert_true(skeleton_foreground_count(first) < 25)
  assert_eq(skeleton_foreground_count(first), skeleton_foreground_count(second))
  for y in 0..<7 {
    for x in 0..<7 {
      assert_eq(first.get_pixel(x, y), second.get_pixel(x, y))
    }
  }
  // A converged thinning keeps a connected centre pixel for this square.
  assert_true(first.get_pixel(3, 3).0.to_int() > 0)
}

test "skeletonize keeps a one-pixel stroke unchanged" {
  let image = @pixelforge.Image::new(7, 7)
  for x in 1..<6 {
    image.set_pixel(x, 3, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  }
  let out = image.skeletonize(128, 10000)
  assert_eq(skeleton_foreground_count(out), 5)
  for x in 1..<6 {
    assert_true(out.get_pixel(x, 3).0.to_int() > 0)
  }
}
