///|
/// Perceptual hash tests: hand-computed hashes on tiny images, invariance
/// to scaling, inversion behavior, and Hamming-distance arithmetic.

///|
test "hamming_distance counts differing bits exactly" {
  assert_eq(hamming_distance(0UL, 0UL), 0)
  assert_eq(hamming_distance(0xFFUL, 0UL), 8)
  assert_eq(hamming_distance(0b1010UL, 0b0101UL), 4)
  // All 64 bits differ between all-zeros and all-ones.
  assert_eq(hamming_distance(0UL, 0xFFFFFFFFFFFFFFFFUL), 64)
}

///|
test "average_hash of a half-dark half-bright image is hand-computable" {
  // 8x8 image: left 4 columns luma 0, right 4 columns luma 255. Mean is
  // ~127, so exactly the 32 right-half bits are set.
  let img = @pixelforge.Image::new(8, 8)
  for y in 0..<8 {
    for x in 0..<8 {
      let v : Byte = if x < 4 { b'\x00' } else { b'\xFF' }
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let h = img.average_hash()
  // Count set bits: must be exactly 32, and bit (y*8+x) set iff x >= 4.
  assert_eq(hamming_distance(h, 0UL), 32)
  for y in 0..<8 {
    for x in 0..<8 {
      let bit = (h >> (y * 8 + x)) & 1UL
      if x >= 4 {
        assert_eq(bit.to_int(), 1)
      } else {
        assert_eq(bit.to_int(), 0)
      }
    }
  }
}

///|
test "average_hash is invariant under 4x upscaling" {
  // The thumbnail averages regions, so scaling the same pattern up must
  // produce the identical hash.
  let small = @pixelforge.Image::new(8, 8)
  for y in 0..<8 {
    for x in 0..<8 {
      let v = @pixelforge.clamp_byte((x * 37 + y * 59) % 256)
      small.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let big = small.resize_nearest(32, 32)
  assert_eq(hamming_distance(small.average_hash(), big.average_hash()), 0)
}

///|
test "inverting an image flips every average_hash bit" {
  // invert() maps luma L to ~255-L, so every above-mean cell goes below
  // the (also inverted) mean: distance is exactly 64.
  let img = @pixelforge.Image::new(16, 16)
  for y in 0..<16 {
    for x in 0..<16 {
      let v = @pixelforge.clamp_byte(x * 16)
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let d = hamming_distance(img.average_hash(), img.invert().average_hash())
  assert_eq(d, 64)
}

///|
test "difference_hash tracks horizontal gradients" {
  // Monotonically brightening columns: every right neighbor is brighter,
  // so all 64 dHash bits are set. The vertically-varying image has no
  // horizontal gradient, so no bits are set.
  let ramp = @pixelforge.Image::new(9, 8)
  for y in 0..<8 {
    for x in 0..<9 {
      let v = @pixelforge.clamp_byte(x * 28)
      ramp.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  assert_eq(hamming_distance(ramp.difference_hash(), 0UL), 64)
  let vert = @pixelforge.Image::new(9, 8)
  for y in 0..<8 {
    for x in 0..<9 {
      let v = @pixelforge.clamp_byte(y * 30)
      vert.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  assert_eq(hamming_distance(vert.difference_hash(), 0UL), 0)
}

///|
test "small brightness shifts keep dHash distance at zero" {
  // dHash depends only on neighbor ordering, which +20 brightness keeps.
  let img = @pixelforge.Image::new(18, 16)
  for y in 0..<16 {
    for x in 0..<18 {
      let v = @pixelforge.clamp_byte((x * 13 + y * 7) % 200)
      img.set_pixel(x, y, v, v, v, b'\xFF')
    }
  }
  let shifted = img.brightness(20)
  assert_eq(
    hamming_distance(img.difference_hash(), shifted.difference_hash()),
    0,
  )
}
