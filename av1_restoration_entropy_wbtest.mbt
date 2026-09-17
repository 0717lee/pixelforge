/// Whitebox tests for the loop-restoration unit syntax reader.
///
/// The MSAC decoder has deterministic behaviour on all-zero and all-ones
/// tile payloads: every CDF symbol resolves to the first or last symbol
/// of its row and every boolean to 0 or 1, so the decoded unit
/// parameters are hand-computable. SGR branches that need a mid-range
/// `ep` use crafted deterministic payloads whose decoded values were
/// derived from a line-by-line Python mirror of this decoder
/// (`_refs/lr_entropy_sim.py`). These tests pin the reader's unit
/// ranges, per-plane reference continuity, the chroma five-tap
/// inference, all three SGR projection branches, the switchable row
/// and the rational superres corner mapping against those values.

///|
/// Build a global restoration layout for the given frame geometry.
fn av1_lr_test_layout(
  modes : Array[Av1RestorationType],
  unit_sizes : Array[Int],
  frame_width : Int,
  frame_height : Int,
  denom? : Int = 8,
) -> Av1RestorationLayout {
  let upscaled = if denom == 8 { frame_width } else { frame_width * denom / 8 }
  av1_restoration_layout(
    { modes, unit_sizes },
    frame_width,
    upscaled,
    frame_height,
    false,
    true,
    true,
    denom,
  ).unwrap()
}

///|
test "entropy literal and ns resolve deterministically on all-ones" {
  // All-ones payloads give symbol_value 0, so every CDF symbol and
  // boolean resolves to its last code: literal bits are all 1 and ns
  // takes the finite-tail branch.
  let decoder = av1_msac_new(
    Array::make(16, b'\xFF'),
    false,
  )
  assert_eq(decoder.bool(), 1)
  assert_eq(decoder.entropy_literal(4), 15)
  // ns(16): w=5, m=16, v=literal(4)=15 < m, so the direct tail.
  assert_eq(decoder.entropy_ns(16), 15)
  // ns(12): w=4, m=4, v=literal(3)=7, 7 >= m so (7*2)-4+bool = 11.
  assert_eq(decoder.entropy_ns(12), 11)
  // subexp(16,1): blocks 2,2 then the finite tail ns(12).
  assert_eq(decoder.entropy_subexp(16, 1), 15)
  // subexp(64,3): blocks 8,8,16 then the finite tail ns(48)=47.
  assert_eq(decoder.entropy_subexp(64, 3), 63)
  // inverse recenter: large values pass through, odd small values fold.
  assert_eq(av1_msac_inverse_recenter(3, 15), 15)
  assert_eq(av1_msac_inverse_recenter(46, 63), 14)
  assert_eq(av1_msac_inverse_recenter(-3, 15), 15)
  assert_eq(av1_msac_inverse_recenter(-7, 31), 31)
}

///|
test "entropy primitives resolve deterministically on all-zeros" {
  // All-zero payloads give symbol_value 32767, so every CDF symbol and
  // boolean resolves to its first code: literal bits are all 0 and the
  // subexp continuation branch immediately returns the literal.
  let decoder = av1_msac_new(
    Array::make(16, b'\x00'),
    false,
  )
  assert_eq(decoder.bool(), 0)
  assert_eq(decoder.entropy_literal(4), 0)
  assert_eq(decoder.entropy_ns(16), 0)
  assert_eq(decoder.entropy_subexp(16, 1), 0)
  // A zero subexp value recenters to the reference itself.
  assert_eq(av1_msac_inverse_recenter(3, 0), 3)
}

///|
test "tile state starts with the spec defaults" {
  let state = av1_restoration_tile_state_new(3)
  assert_eq(state.cdf_switchable, [9413, 22581, 32768, 0])
  assert_eq(state.cdf_wiener, [11570, 32768, 0])
  assert_eq(state.cdf_sgr, [16855, 32768, 0])
  assert_eq(state.ref_wiener[0][0], [3, -7, 15])
  assert_eq(state.ref_wiener[0][1], [3, -7, 15])
  assert_eq(state.ref_wiener[1][0], [3, -7, 15])
  assert_eq(state.ref_sgr[0], [-32, 31])
  assert_eq(state.ref_sgr[2], [-32, 31])
  assert_eq(state.units.length(), 0)
}

///|
test "read_sb decodes all-None units on a zeroed tile stream" {
  // Every mode symbol resolves to None on an all-zero payload, so no
  // coefficients are read and the records stay empty-valued.
  let layout = av1_lr_test_layout(
    [Av1RestorationWiener, Av1RestorationNone, Av1RestorationNone],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(32, b'\x00'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 1)
  assert_eq(state.units[0].plane, 0)
  assert_eq(state.units[0].unit_row, 0)
  assert_eq(state.units[0].unit_col, 0)
  assert_true(state.units[0].unit is Av1RestorationUnitNone)
  // A decoded-None unit leaves both coefficient references untouched.
  assert_eq(state.ref_wiener[0][0], [3, -7, 15])
  assert_eq(state.ref_sgr[0], [-32, 31])
}

///|
test "read_sb adapts the mode CDF after a None symbol" {
  let layout = av1_lr_test_layout(
    [Av1RestorationWiener, Av1RestorationNone, Av1RestorationNone],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(32, b'\x00'), true)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  // The decoded None symbol pulls the first entry towards 32768 and
  // bumps the adaptation counter.
  assert_eq(state.cdf_wiener, [12894, 32768, 1])
}

///|
test "read_sb decodes Wiener taps with per-unit reference continuity" {
  // All-ones payloads resolve every Wiener tap to the subexp maximum
  // (n-1). The tap mid references sit at the alphabet centre, so the
  // first unit of a plane recenters to the tap minima and the second
  // unit (now recentering against the minima) to the maxima; the
  // sequence alternates for the remaining units. Horizontal and
  // vertical references evolve in lockstep, so both axes match.
  // U64 with SB128 covers four luma units and one chroma unit per
  // plane; planes are read in order and units in row-major order.
  let layout = av1_lr_test_layout(
    [Av1RestorationWiener, Av1RestorationWiener, Av1RestorationWiener],
    [64, 64, 64],
    256,
    256,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(64, b'\xFF'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 6)
  let y_tap0 : Array[Int] = []
  let y_tap1 : Array[Int] = []
  let y_tap2 : Array[Int] = []
  let mut index = 0
  for record in state.units {
    if record.plane != 0 {
      continue
    }
    assert_eq(record.unit_row, index / 2)
    assert_eq(record.unit_col, index % 2)
    match record.unit {
      Av1RestorationUnitWiener(v, h) => {
        y_tap0.push(v[0])
        y_tap1.push(v[1])
        y_tap2.push(v[2])
        // Vertical and horizontal references are separate but evolve
        // in lockstep from identical starts, so both axes agree.
        assert_eq(v, h)
      }
      _ => assert_true(false)
    }
    index = index + 1
  }
  assert_eq(y_tap0, [-5, 10, -5, 10])
  assert_eq(y_tap1, [-23, 8, -23, 8])
  assert_eq(y_tap2, [-17, 46, -17, 46])
  assert_eq(state.ref_wiener[0][0], [10, 8, 46])
  assert_eq(state.ref_wiener[0][1], [10, 8, 46])
  // Chroma units infer tap 0 on both axes and read only five taps.
  match state.units[4].unit {
    Av1RestorationUnitWiener(v, h) => {
      assert_eq(v, [0, -23, -17])
      assert_eq(h, [0, -23, -17])
    }
    _ => assert_true(false)
  }
  match state.units[5].unit {
    Av1RestorationUnitWiener(v, h) => {
      assert_eq(v, [0, -23, -17])
      assert_eq(h, [0, -23, -17])
    }
    _ => assert_true(false)
  }
}

///|
test "read_sb decodes SGR inferred projections on all-ones" {
  // ep 15 selects radii (2,0): r1 is zero, so xqd0 is coded and xqd1
  // is derived from 128-xqd0 without entropy and clipped into
  // [-32,95]. The maximum subexp value recenters to the xqd0 minimum.
  let layout = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationSgrproj, Av1RestorationSgrproj],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(32, b'\xFF'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 3)
  for record in state.units {
    match record.unit {
      Av1RestorationUnitSgrproj(ep, xqd) => {
        assert_eq(ep, 15)
        assert_eq(xqd, [-96, 95])
      }
      _ => assert_true(false)
    }
  }
  // Inferred values still replace the running references.
  assert_eq(state.ref_sgr[0], [-96, 95])
  assert_eq(state.ref_sgr[2], [-96, 95])
}

///|
test "read_sb decodes SGR both-radius projections with reference updates" {
  // A crafted payload (deterministic bytes; values derived from the
  // Python mirror) decodes two SGR units with ep 5 and ep 3, both in
  // the (2,1) radii band, so both projections are read from entropy
  // and the second unit recenters against the first unit's values.
  let layout = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
    [64, 64, 64],
    256,
    64,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(
    [
      b'\xAD', b'\x93', b'\x88', b'\x36', b'\x6B', b'\x9F', b'\x40', b'\xD4',
    ],
    false,
  )
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 2)
  match state.units[0].unit {
    Av1RestorationUnitSgrproj(ep, xqd) => {
      assert_eq(ep, 5)
      assert_eq(xqd, [-38, 16])
    }
    _ => assert_true(false)
  }
  match state.units[1].unit {
    Av1RestorationUnitSgrproj(ep, xqd) => {
      assert_eq(ep, 3)
      assert_eq(xqd, [-43, 45])
    }
    _ => assert_true(false)
  }
  assert_eq(state.ref_sgr[0], [-43, 45])
}

///|
test "read_sb decodes SGR inferred projection on the r0=0 branch" {
  // A crafted payload decodes one SGR unit with ep 12 in the (0,1)
  // radii band: xqd0 is inferred zero without entropy and only xqd1
  // is coded. The inferred zero still replaces the running reference.
  let layout = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(
    [
      b'\xE7', b'\x13', b'\x1A', b'\xFC', b'\xC8', b'\xE3', b'\x48', b'\xC7',
    ],
    false,
  )
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 1)
  match state.units[0].unit {
    Av1RestorationUnitSgrproj(ep, xqd) => {
      assert_eq(ep, 12)
      assert_eq(xqd, [0, 51])
    }
    _ => assert_true(false)
  }
  assert_eq(state.ref_sgr[0], [0, 51])
}

///|
test "read_sb resolves switchable units to the last row symbol" {
  // The switchable row's third symbol is Sgrproj, which all-ones
  // payloads resolve to; the following SGR syntax then reads as usual.
  let layout = av1_lr_test_layout(
    [Av1RestorationSwitchable, Av1RestorationNone, Av1RestorationNone],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(32, b'\xFF'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 1)
  match state.units[0].unit {
    Av1RestorationUnitSgrproj(ep, xqd) => {
      assert_eq(ep, 15)
      assert_eq(xqd, [-96, 95])
    }
    _ => assert_true(false)
  }
}

///|
test "read_sb skips frame-None planes without consuming symbols" {
  // Only the luma plane is active; chroma None planes consume nothing.
  let layout = av1_lr_test_layout(
    [Av1RestorationWiener, Av1RestorationNone, Av1RestorationNone],
    [128, 128, 128],
    128,
    128,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(32, b'\xFF'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 1)
  assert_eq(state.units[0].plane, 0)
}

///|
test "read_sb covers several units from one superblock" {
  // A 256-wide frame with U64 luma units yields a 2x2 unit grid; the
  // SB128 rectangle owns all four, read in row-major order.
  let layout = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
    [64, 64, 64],
    256,
    256,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(64, b'\xFF'), false)
  assert_true(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
  assert_eq(state.units.length(), 4)
  assert_eq(state.units[0].unit_row, 0)
  assert_eq(state.units[0].unit_col, 0)
  assert_eq(state.units[1].unit_row, 0)
  assert_eq(state.units[1].unit_col, 1)
  assert_eq(state.units[2].unit_row, 1)
  assert_eq(state.units[2].unit_col, 0)
  assert_eq(state.units[3].unit_row, 1)
  assert_eq(state.units[3].unit_col, 1)
}

///|
test "read_sb maps superres corners with the rational denominator" {
  // With superres D=16 the coded SB column rectangle expands by D/8 on
  // the upscaled unit grid: a 64-wide coded frame with U64 luma units
  // owns two columns per SB instead of one.
  let coded = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
    [64, 64, 64],
    64,
    64,
  )
  let state_coded = av1_restoration_tile_state_new(3)
  let decoder_coded = av1_msac_new(Array::make(32, b'\x00'), false)
  assert_true(
    av1_restoration_read_sb(
      decoder_coded,
      state_coded,
      coded,
      0,
      0,
      64,
      subsampling_x=true,
      subsampling_y=true,
    ),
  )
  assert_eq(state_coded.units.length(), 1)
  assert_eq(state_coded.units[0].unit_col, 0)
  let scaled = av1_lr_test_layout(
    [Av1RestorationSgrproj, Av1RestorationNone, Av1RestorationNone],
    [64, 64, 64],
    64,
    64,
    denom=16,
  )
  assert_eq(scaled.unit_cols[0], 2)
  let state_scaled = av1_restoration_tile_state_new(3)
  let decoder_scaled = av1_msac_new(Array::make(32, b'\x00'), false)
  assert_true(
    av1_restoration_read_sb(
      decoder_scaled,
      state_scaled,
      scaled,
      0,
      0,
      64,
      subsampling_x=true,
      subsampling_y=true,
    ),
  )
  assert_eq(state_scaled.units.length(), 2)
  assert_eq(state_scaled.units[0].unit_col, 0)
  assert_eq(state_scaled.units[1].unit_col, 1)
}

///|
test "read_sb rejects entropy overrun at the unit boundary" {
  // A tiny payload exhausts the MSAC budget during coefficient reads.
  let layout = av1_lr_test_layout(
    [Av1RestorationWiener, Av1RestorationWiener, Av1RestorationWiener],
    [128, 128, 128],
    256,
    256,
  )
  let state = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(3, b'\xFF'), true)
  assert_false(
    av1_restoration_read_sb(decoder, state, layout, 0, 0, 128, subsampling_x=true, subsampling_y=true),
  )
}
