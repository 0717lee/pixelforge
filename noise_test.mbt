///|
/// Noise generator tests: seed determinism, statistical sanity of the
/// generated noise, degenerate parameters, and alpha preservation.

///|
test "same seed reproduces the identical noisy image" {
  let img = solid(16, 16, 128, 128, 128, 255)
  let a = img.add_gaussian_noise(42UL, 12.0)
  let b = img.add_gaussian_noise(42UL, 12.0)
  for i in 0..<(16 * 16 * 4) {
    assert_eq(a.data[i].to_int(), b.data[i].to_int())
  }
  let sp1 = img.add_salt_pepper(7UL, 0.2)
  let sp2 = img.add_salt_pepper(7UL, 0.2)
  for i in 0..<(16 * 16 * 4) {
    assert_eq(sp1.data[i].to_int(), sp2.data[i].to_int())
  }
}

///|
test "different seeds produce different noise" {
  let img = solid(16, 16, 128, 128, 128, 255)
  let a = img.add_gaussian_noise(1UL, 12.0)
  let b = img.add_gaussian_noise(2UL, 12.0)
  let mut differing = 0
  for i in 0..<(16 * 16 * 4) {
    if a.data[i].to_int() != b.data[i].to_int() {
      differing = differing + 1
    }
  }
  assert_true(differing > 0)
}

///|
test "gaussian noise stays roughly zero-mean and actually perturbs pixels" {
  // On a mid-gray field the mean must stay near 128 and plenty of pixels
  // must move; the exact values are pinned by the seeded LCG.
  let img = solid(32, 32, 128, 128, 128, 255)
  let out = img.add_gaussian_noise(99UL, 10.0)
  let mut sum = 0
  let mut changed = 0
  for y in 0..<32 {
    for x in 0..<32 {
      let v = out.get_pixel(x, y).0.to_int()
      sum = sum + v
      if v != 128 {
        changed = changed + 1
      }
    }
  }
  let mean = sum / (32 * 32)
  assert_true(mean >= 123 && mean <= 133) // ~128 +/- 5
  assert_true(changed > 512) // most pixels perturbed
  // Alpha untouched.
  assert_eq(out.get_pixel(0, 0).3.to_int(), 255)
}

///|
test "sigma 0 and density 0 are exact copies" {
  let img = gray_image(4, 1, [10, 100, 180, 250])
  let g = img.add_gaussian_noise(5UL, 0.0)
  let s = img.add_salt_pepper(5UL, 0.0)
  for i in 0..<(4 * 4) {
    assert_eq(g.data[i].to_int(), img.data[i].to_int())
    assert_eq(s.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "salt and pepper hits roughly the requested density with both colors" {
  // density 0.3 on 64x64 mid-gray: corrupted pixels are exactly 0 or 255,
  // count within a generous band around 30%, and both colors appear.
  let img = solid(64, 64, 128, 128, 128, 255)
  let out = img.add_salt_pepper(2026UL, 0.3)
  let mut salt = 0
  let mut pepper = 0
  let mut untouched = 0
  for y in 0..<64 {
    for x in 0..<64 {
      let v = out.get_pixel(x, y).0.to_int()
      if v == 255 {
        salt = salt + 1
      } else if v == 0 {
        pepper = pepper + 1
      } else {
        assert_eq(v, 128) // anything else must be the original gray
        untouched = untouched + 1
      }
    }
  }
  let corrupted = salt + pepper
  let total = 64 * 64
  assert_true(corrupted > total * 24 / 100) // >= ~24%
  assert_true(corrupted < total * 36 / 100) // <= ~36%
  assert_true(salt > 0 && pepper > 0)
  assert_eq(corrupted + untouched, total)
}

///|
test "median filter visibly cleans salt-and-pepper noise" {
  // The classic pairing: impulse noise -> 3x3 median. Count wrong pixels
  // before and after; the median must remove most of them.
  let img = solid(32, 32, 100, 100, 100, 255)
  let noisy = img.add_salt_pepper(11UL, 0.08)
  let cleaned = noisy.median()
  let mut wrong_before = 0
  let mut wrong_after = 0
  for y in 0..<32 {
    for x in 0..<32 {
      if noisy.get_pixel(x, y).0.to_int() != 100 {
        wrong_before = wrong_before + 1
      }
      if cleaned.get_pixel(x, y).0.to_int() != 100 {
        wrong_after = wrong_after + 1
      }
    }
  }
  assert_true(wrong_before > 40) // noise actually landed
  assert_true(wrong_after * 4 < wrong_before) // >= 75% removed
}
