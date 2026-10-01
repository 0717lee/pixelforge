///|
test "alpha weighted resize preserves the default straight channel behavior" {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\x00')
  image.set_pixel(1, 0, b'\x00', b'\x00', b'\xFF', b'\xFF')
  assert_eq(
    image.resize_bilinear(1, 1).get_pixel(0, 0),
    (b'\x80', b'\x00', b'\x80', b'\x80'),
  )
  assert_eq(
    image.resize_bilinear(1, 1, alpha_weighted=true).get_pixel(0, 0),
    (b'\x00', b'\x00', b'\xFF', b'\x80'),
  )
}

///|
test "alpha weighted midpoint agrees with integer coverage reference" {
  // At a 2x2 -> 1x1 midpoint all four coverages are exactly 1/4.
  // Compute expected channels with integer sums, independent of the sampler.
  for seed in 0..<100 {
    let image = @pixelforge.Image::new(2, 2)
    let mut total_alpha = 0
    let weighted = [0, 0, 0]
    for p in 0..<4 {
      let a = (seed * 19 + p * 67) % 256
      total_alpha += a
      for c in 0..<3 {
        let value = (seed * 31 + p * 53 + c * 97) % 256
        image.data[p * 4 + c] = value.to_byte()
        weighted[c] += value * a
      }
      image.data[p * 4 + 3] = a.to_byte()
    }
    let output = image.resize_bilinear(1, 1, alpha_weighted=true)
    assert_eq(output.data[3].to_int(), (total_alpha + 2) / 4)
    for c in 0..<3 {
      assert_eq(
        output.data[c].to_int(),
        (weighted[c] + total_alpha / 2) / total_alpha,
      )
    }
  }
}

///|
test "alpha weighted resize canonicalizes newly transparent output" {
  let image = @pixelforge.Image::new(2, 2)
  for i in 0..<image.data.length() {
    image.data[i] = if i % 4 == 3 { b'\x00' } else { b'\xFF' }
  }
  for alpha in [b'\x00', b'\x01'] {
    image.data[3] = alpha
    // One alpha=1 pixel contributes 1/4, which rounds to zero.
    assert_eq(
      image.resize_bilinear(1, 1, alpha_weighted=true).get_pixel(0, 0),
      (b'\x00', b'\x00', b'\x00', b'\x00'),
    )
  }
}

///|
test "alpha weighted identity preserves hidden RGB and owns output" {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\x00')
  image.set_pixel(1, 0, b'\x40', b'\x50', b'\x60', b'\x80')
  let output = image.resize_bilinear(2, 1, alpha_weighted=true)
  assert_eq(output.data, image.data)
  output.data[0] = b'\xFF'
  assert_eq(image.data[0], b'\x10')
}

///|
test "alpha weighted resize clamps edges and handles empty inputs" {
  let image = @pixelforge.Image::new(1, 1)
  image.set_pixel(0, 0, b'\x10', b'\x20', b'\x30', b'\x40')
  let output = image.resize_bilinear(3, 5, alpha_weighted=true)
  for y in 0..<5 {
    for x in 0..<3 {
      assert_eq(output.get_pixel(x, y), image.get_pixel(0, 0))
    }
  }
  for (w, h) in [(0, 0), (0, 3), (4, 0)] {
    let output = @pixelforge.Image::new(w, h).resize_bilinear(
      0,
      -1,
      alpha_weighted=true,
    )
    assert_eq((output.width, output.height), (1, 1))
    assert_eq(output.get_pixel(0, 0), (b'\x00', b'\x00', b'\x00', b'\x00'))
  }
}
