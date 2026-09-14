///|
// Same deterministic input-only formula as generate-av1-cdef-reference.py.
fn av1_cdef_frame_pattern(
  width : Int,
  height : Int,
  bit_depth : Int,
  seed : Int,
) -> Array[Int] {
  let scale = 1 << (bit_depth - 8)
  let base = if seed % 3 == 0 { 128 } else if seed % 3 == 1 { 8 } else { 247 }
  let maximum = (1 << bit_depth) - 1
  let pixels : Array[Int] = []
  for y in 0..<height {
    for x in 0..<width {
      let value = (
          base +
          (x * 13 + y * 17 + x * y * 3 + seed * 7) % 23 -
          11 +
          (x / 3 + y / 2 + seed) % 7 -
          3
        ) *
        scale +
        (x * 5 + y * 7 + seed) % scale
      pixels.push(
        if value < 0 {
          0
        } else if value > maximum {
          maximum
        } else {
          value
        },
      )
    }
  }
  pixels
}

///|
test "cdef direction and variance match 24 original libaom references" {
  // Exact cdef_find_dir_c outputs already recorded by the committed generator.
  // Revision 1a4b3aef9b3e5b9251c45e9f986f41894dd45bb2, cdef_block.c SHA-256:
  // e22f2e787adc8d78c4c88e03617a25db2603081ec18ca442a3e2f9a7bc5b5636
  let references = [
    (8, 808, 5, 424),
    (8, 840, 4, 63),
    (8, 872, 0, 189),
    (8, 904, 4, 14),
    (8, 936, 6, 505),
    (8, 968, 7, 394),
    (8, 1000, 0, 273),
    (8, 1032, 4, 119),
    (10, 1010, 0, 242),
    (10, 1042, 0, 200),
    (10, 1074, 6, 556),
    (10, 1106, 4, 40),
    (10, 1138, 7, 335),
    (10, 1170, 2, 223),
    (10, 1202, 6, 377),
    (10, 1234, 1, 203),
    (12, 1212, 6, 889),
    (12, 1244, 4, 33),
    (12, 1276, 7, 443),
    (12, 1308, 1, 232),
    (12, 1340, 7, 193),
    (12, 1372, 3, 178),
    (12, 1404, 4, 154),
    (12, 1436, 0, 157),
  ]
  for reference in references {
    let (bit_depth, seed, direction, variance) = reference
    let input = av1_cdef_frame_pattern(8, 8, bit_depth, seed)
    assert_eq(
      av1_cdef_find_direction(input, 8, 0, 0, bit_depth),
      (direction, variance),
    )
    let padded = Array::make(16 * 16, 0)
    for y in 0..<8 {
      for x in 0..<8 {
        padded[(y + 8) * 16 + x + 8] = input[y * 8 + x]
      }
    }
    assert_eq(
      av1_cdef_find_direction(padded, 16, 8, 8, bit_depth),
      (direction, variance),
    )
  }
}

///|
test "cdef flat blocks tie to direction zero with zero variance" {
  for bit_depth in [8, 10, 12] {
    for value in [0, 1 << (bit_depth - 1), (1 << bit_depth) - 1] {
      assert_eq(
        av1_cdef_find_direction(Array::make(64, value), 8, 0, 0, bit_depth),
        (0, 0),
      )
    }
  }
  assert_eq(av1_cdef_adjust_strength(112, 0), 0)
  assert_eq(av1_cdef_adjust_strength(112, 1), 28)
  assert_eq(av1_cdef_adjust_strength(112, 1 << 20), 112)
  assert_eq(av1_cdef_adjust_strength(28, 242), 9)
}

///|
fn av1_cdef_frame_secondary_config() -> Av1CdefConfig {
  {
    bits: 0,
    damping: 6,
    y_primary: [0],
    y_secondary: [4],
    uv_primary: [0],
    uv_secondary: [4],
  }
}

///|
test "cdef secondary-only frame uses direction zero and chroma damping" {
  let y = av1_cdef_frame_pattern(8, 8, 8, 808)
  let u = av1_cdef_frame_pattern(4, 4, 8, 809)
  let v = av1_cdef_frame_pattern(4, 4, 8, 810)
  let params : Array[Av1CdefParams] = [
    { primary_strength: 0, secondary_strength: 4, damping: 6, direction: 0, },
  ]
  let (yf, uf, vf) = av1_cdef_filter_yuv420(8, 8, y, u, v, params, params).unwrap()
  let planes = [y, u, v]
  let actual = av1_cdef_filter_frame(
    8,
    8,
    planes,
    [0, 0, 0, 0],
    [0],
    av1_cdef_frame_secondary_config(),
    8,
  ).unwrap()
  assert_eq(actual, [yf, uf, vf])
  assert_true(actual[0] != y)
  assert_true(
    actual[0] !=
    av1_cdef_filter_plane(8, 8, y, [
      { primary_strength: 0, secondary_strength: 4, damping: 6, direction: 5, },
    ]).unwrap(),
  )
}

///|
test "cdef raw primary selects direction even when variance reduces strength to zero" {
  let y = av1_cdef_frame_pattern(8, 8, 8, 808)
  let planes = [y, Array::make(16, 128), Array::make(16, 128)]
  let config : Av1CdefConfig = {
    bits: 0,
    damping: 6,
    y_primary: [1],
    y_secondary: [4],
    uv_primary: [0],
    uv_secondary: [0],
  }
  assert_eq(av1_cdef_adjust_strength(1, 424), 0)
  let actual = av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [0], config, 8).unwrap()
  let expected = av1_cdef_filter_plane(8, 8, y, [
    { primary_strength: 0, secondary_strength: 4, damping: 6, direction: 5, },
  ]).unwrap()
  assert_eq(actual[0], expected)
  assert_true(
    actual[0] !=
    av1_cdef_filter_plane(8, 8, y, [
      { primary_strength: 0, secondary_strength: 4, damping: 6, direction: 0, },
    ]).unwrap(),
  )
}

///|
test "cdef skips an 8x8 block only when all four MI flags are skipped" {
  let planes = [
    av1_cdef_frame_pattern(8, 8, 8, 808),
    av1_cdef_frame_pattern(4, 4, 8, 809),
    av1_cdef_frame_pattern(4, 4, 8, 810),
  ]
  let config = av1_cdef_frame_secondary_config()
  assert_eq(
    av1_cdef_filter_frame(8, 8, planes, [1, 1, 1, 1], [0], config, 8).unwrap(),
    planes,
  )
  assert_eq(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [-1], config, 8).unwrap(),
    planes,
  )
  let actual = av1_cdef_filter_frame(8, 8, planes, [1, 1, 1, 0], [0], config, 8).unwrap()
  let all_active = av1_cdef_filter_frame(
    8,
    8,
    planes,
    [0, 0, 0, 0],
    [0],
    config,
    8,
  ).unwrap()
  assert_eq(actual, all_active)
  assert_true(actual[0] != planes[0])
}

///|
test "cdef frame selects 64x64 indices and reads source across region boundaries" {
  let width = 72
  let y = av1_cdef_frame_pattern(width, 8, 8, 808)
  let u = av1_cdef_frame_pattern(width / 2, 4, 8, 809)
  let v = av1_cdef_frame_pattern(width / 2, 4, 8, 810)
  let config : Av1CdefConfig = {
    bits: 1,
    damping: 6,
    y_primary: [0, 0],
    y_secondary: [4, 1],
    uv_primary: [0, 0],
    uv_secondary: [4, 1],
  }
  let params : Array[Av1CdefParams] = []
  for block in 0..<9 {
    params.push({
      primary_strength: 0,
      secondary_strength: if block < 8 {
        4
      } else {
        1
      },
      damping: 6,
      direction: 0,
    })
  }
  let (yf, uf, vf) = av1_cdef_filter_yuv420(width, 8, y, u, v, params, params).unwrap()
  // Original C confirms that taps crossing x=64 produce 1 and 15 here;
  // filtering the final 8x8 as an isolated frame would produce 0 and 16.
  assert_eq(yf[64], 1)
  assert_eq(yf[7 * width + 64], 15)
  let planes = [y, u, v]
  let snapshot = [y.copy(), u.copy(), v.copy()]
  let skips = Array::make(width / 4 * 2, 0)
  assert_eq(
    av1_cdef_filter_frame(width, 8, planes, skips, [0, 1], config, 8).unwrap(),
    [yf, uf, vf],
  )
  assert_eq(planes, snapshot)
  let missing = av1_cdef_filter_frame(
    width,
    8,
    planes,
    skips,
    [0, -1],
    config,
    8,
  ).unwrap()
  for plane in 0..<3 {
    let divisor = if plane == 0 { 1 } else { 2 }
    for row in 0..<(8 / divisor) {
      for x in (64 / divisor)..<(width / divisor) {
        assert_eq(
          missing[plane][row * (width / divisor) + x],
          planes[plane][row * (width / divisor) + x],
        )
      }
    }
  }
}

///|
fn av1_cdef_frame_reference_pixels(hex : String) -> Array[Int] {
  let pixels : Array[Int] = []
  for i in 0..<(hex.length() / 3) {
    let mut value = 0
    for j in 0..<3 {
      let code = hex[i * 3 + j].to_int()
      value = value * 16 + (if code <= 57 { code - 48 } else { code - 87 })
    }
    pixels.push(value)
  }
  pixels
}

///|
test "cdef highbd variance adjustment keeps native fractional strength" {
  // Original pinned libaom kernel: direction=0, variance=242, native Y pri=9,
  // sec=8, damping=7; UV pri=28, sec=8, damping=6. Full output snapshots.
  let y = av1_cdef_frame_pattern(8, 8, 10, 1010)
  let u = av1_cdef_frame_pattern(4, 4, 10, 1011)
  let v = av1_cdef_frame_pattern(4, 4, 10, 1012)
  let config : Av1CdefConfig = {
    bits: 0,
    damping: 5,
    y_primary: [7],
    y_secondary: [2],
    uv_primary: [7],
    uv_secondary: [2],
  }
  let actual = av1_cdef_filter_frame(
    8,
    8,
    [y, u, v],
    [0, 0, 0, 0],
    [0],
    config,
    10,
  ).unwrap()
  assert_eq(
    actual[0],
    av1_cdef_frame_reference_pixels(
      "3d33fb3e03bf3ea3cb3f73d33bd3f73e13cb3f73e73d53b93f93ec3e03db3cc3bf3f83f63e93e13e03e03df3dd3df3d93dc3dc3e23eb3f73f93f93f93c33d73e73f53f93d13ea3f63f93d03eb3f93d23f03f63c43ec3c13eb3c43eb3f93ce3f9",
    ),
  )
  assert_eq(
    actual[1],
    av1_cdef_frame_reference_pixels(
      "2161ef21b2001fa1e821d2121eb1e322121b227225224226",
    ),
  )
  assert_eq(
    actual[2],
    av1_cdef_frame_reference_pixels(
      "00102f00e03903a01e01004502301900c05601101000c009",
    ),
  )
  let prematurely_rounded = av1_cdef_filter_plane(
    8,
    8,
    y,
    [{ primary_strength: 2, secondary_strength: 2, damping: 5, direction: 0, }],
    bit_depth=10,
  ).unwrap()
  assert_eq(actual[0][2], 992)
  assert_eq(prematurely_rounded[2], 991)
}

///|
test "cdef frame rejects malformed grids and samples before direction search" {
  let config = av1_cdef_frame_secondary_config()
  let planes = [
    Array::make(64, 128),
    Array::make(16, 128),
    Array::make(16, 128),
  ]
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0], [0], config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 2], [0], config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [], config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [1], config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [-2], config, 8) is None,
  )
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [0], config, 16) is None,
  )
  assert_true(
    av1_cdef_filter_frame(7, 8, planes, [0, 0, 0, 0], [0], config, 8) is None,
  )
  planes[0][0] = 256
  assert_true(
    av1_cdef_filter_frame(8, 8, planes, [0, 0, 0, 0], [0], config, 8) is None,
  )
}
