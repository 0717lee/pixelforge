/// Whitebox tests for the loop-restoration stripe boundary storage and
/// source view.
///
/// The stripe geometry is global per plane and independent of tiles:
/// stripe k spans `[max(0, k*S - O), min((k+1)*S - O, plane_height))`
/// with `S = 64 >> ss_y` and `O = 8 >> ss_y` (audit §6). These tests
/// pin the boundary positions, the saved row contents at internal
/// boundaries, the single-row duplication at the frame bottom, the
/// superres upscale phase against the normative scaler itself, the
/// store contract and every branch of the source view sampler: inside
/// a stripe reads the post-CDEF frame, internal boundaries read the
/// saved deblocked pairs `[top0, top0, top1]` / `[bottom0, bottom1,
/// bottom1]`, and the frame edges repeat the edge rows.

///|
/// Build a luma plane whose row y holds `y * width + x`, so every saved
/// row is identifiable by its sample values.
fn av1_stripe_test_plane(
  width : Int,
  height : Int,
  coded : Int,
  base : Int,
) -> Array[Int] {
  Array::makei(coded * coded, i => {
    let row = i / coded
    let col = i % coded
    if row < height && col < width {
      base + row * width + col
    } else {
      -1
    }
  })
}

///|
/// Build an 8-bit-safe plane for the superres path: the normative
/// scaler validates every sample against the bit depth, so rows must
/// stay inside [0, 255]. Row y column x holds `(37*y + x) % 256`,
/// which keeps the boundary rows 54..57 distinct.
fn av1_stripe_test_plane_small(
  width : Int,
  height : Int,
  coded : Int,
) -> Array[Int] {
  Array::makei(coded * coded, i => {
    let row = i / coded
    let col = i % coded
    if row < height && col < width {
      (37 * row + col) % 256
    } else {
      -1
    }
  })
}

///|
/// Assert a saved pair equals two expected rows of the source plane.
fn av1_stripe_assert_pair(
  pair : Array[Int],
  width : Int,
  row_a : Int,
  row_b : Int,
  plane : Array[Int],
  stride : Int,
) -> Unit raise {
  assert_eq(pair.length(), 2 * width)
  for i in 0..<2 {
    let row = if i == 0 { row_a } else { row_b }
    for col in 0..<width {
      assert_eq(pair[i * width + col], plane[row * stride + col])
    }
  }
}

///|
test "stripe bounds follow the normative 64/8 luma grid" {
  let bounds = av1_restoration_stripe_bounds(256, false).unwrap()
  assert_eq(bounds.length(), 5)
  assert_eq(bounds[0], (0, 56))
  assert_eq(bounds[1], (56, 120))
  assert_eq(bounds[2], (120, 184))
  assert_eq(bounds[3], (184, 248))
  assert_eq(bounds[4], (248, 256))
  // A 57-row plane yields two stripes; the second is clipped.
  let short = av1_restoration_stripe_bounds(57, false).unwrap()
  assert_eq(short.length(), 2)
  assert_eq(short[0], (0, 56))
  assert_eq(short[1], (56, 57))
}

///|
test "stripe bounds halve for subsampled chroma" {
  let bounds = av1_restoration_stripe_bounds(128, true).unwrap()
  assert_eq(bounds.length(), 5)
  assert_eq(bounds[0], (0, 28))
  assert_eq(bounds[1], (28, 60))
  assert_eq(bounds[2], (60, 92))
  assert_eq(bounds[3], (92, 124))
  assert_eq(bounds[4], (124, 128))
  let short = av1_restoration_stripe_bounds(57, true).unwrap()
  assert_eq(short.length(), 2)
  assert_eq(short[0], (0, 28))
  assert_eq(short[1], (28, 57))
}

///|
test "stripe bounds reject invalid plane heights" {
  assert_true(av1_restoration_stripe_bounds(0, false) is None)
  assert_true(av1_restoration_stripe_bounds(-16, true) is None)
  assert_true(av1_restoration_stripe_bounds(70000, false) is None)
}

///|
test "save stores deblocked rows at every internal luma boundary" {
  let width = 256
  let height = 256
  let coded = 256
  let plane = av1_stripe_test_plane(width, height, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  assert_eq(store.planes.length(), 1)
  let info = store.planes[0]
  assert_eq(info.count, 5)
  assert_eq(info.width, 256)
  assert_eq(info.height, 256)
  assert_eq(info.starts[0], 0)
  assert_eq(info.ends[0], 56)
  assert_eq(info.starts[4], 248)
  assert_eq(info.ends[4], 256)
  // Outer boundaries stay empty; the view repeats frame edge rows.
  assert_eq(info.top[0].length(), 0)
  assert_eq(info.bottom[4].length(), 0)
  // Stripe 1 starts at 56: rows 54 and 55 live above it.
  av1_stripe_assert_pair(info.top[1], 256, 54, 55, plane, coded)
  // Stripe 0 ends at 56: rows 56 and 57 follow it.
  av1_stripe_assert_pair(info.bottom[0], 256, 56, 57, plane, coded)
  av1_stripe_assert_pair(info.top[4], 256, 246, 247, plane, coded)
  av1_stripe_assert_pair(info.bottom[3], 256, 248, 249, plane, coded)
  assert_true(av1_restoration_stripe_store_valid(store))
}

///|
test "save duplicates the single remaining row at the frame bottom" {
  let width = 256
  let height = 57
  let coded = 256
  let plane = av1_stripe_test_plane(width, height, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let info = store.planes[0]
  assert_eq(info.count, 2)
  assert_eq(info.starts[1], 56)
  assert_eq(info.ends[1], 57)
  // Row 56 is the last row; the second saved row duplicates it.
  av1_stripe_assert_pair(info.bottom[0], 256, 56, 56, plane, coded)
  av1_stripe_assert_pair(info.top[1], 256, 54, 55, plane, coded)
  // The final stripe ends at the frame bottom: no bottom pair.
  assert_eq(info.bottom[1].length(), 0)
  assert_true(av1_restoration_stripe_store_valid(store))
}

///|
test "save upscales superres boundaries with the normative scaler" {
  let width = 128
  let output_width = 192
  let height = 64
  let coded = 128
  let plane = av1_stripe_test_plane_small(width, height, coded)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    output_width,
    height,
    8,
    true,
  ).unwrap()
  let info = store.planes[0]
  assert_eq(info.count, 2)
  assert_eq(info.width, 192)
  // The saved rows must equal the normative scaler applied to the same
  // coded rows at the same down/up widths, so the frame sampling phase
  // is preserved. Pack each pair independently and compare.
  let packed_above = Array::makei(2 * coded, i => {
    let row = if i / coded == 0 { 54 } else { 55 }
    plane[row * coded + i % coded]
  })
  let expected_above = av1_superres_upscale_plane(
    packed_above,
    coded,
    coded,
    width,
    output_width,
    2,
    8,
  ).unwrap()
  let packed_below = Array::makei(2 * coded, i => {
    let row = if i / coded == 0 { 56 } else { 57 }
    plane[row * coded + i % coded]
  })
  let expected_below = av1_superres_upscale_plane(
    packed_below,
    coded,
    coded,
    width,
    output_width,
    2,
    8,
  ).unwrap()
  assert_eq(info.top[1].length(), 2 * 192)
  assert_eq(info.bottom[0].length(), 2 * 192)
  for col in 0..<192 {
    assert_eq(info.top[1][col], expected_above[col])
    assert_eq(info.top[1][192 + col], expected_above[192 + col])
    assert_eq(info.bottom[0][col], expected_below[col])
    assert_eq(info.bottom[0][192 + col], expected_below[192 + col])
  }
  assert_true(av1_restoration_stripe_store_valid(store))
}

///|
test "save covers three planes with per-plane chroma geometry" {
  let width = 256
  let height = 256
  let coded = 256
  let luma = av1_stripe_test_plane(width, height, coded, 0)
  let cb = av1_stripe_test_plane(128, 128, 128, 100000)
  let cr = av1_stripe_test_plane(128, 128, 128, 200000)
  let store = av1_restoration_save_stripes(
    [luma, cb, cr],
    coded,
    width,
    width,
    height,
    8,
    false,
  ).unwrap()
  assert_eq(store.planes.length(), 3)
  let info = store.planes[1]
  assert_eq(info.count, 5)
  assert_eq(info.width, 128)
  assert_eq(info.height, 128)
  assert_eq(info.starts[1], 28)
  assert_eq(info.ends[0], 28)
  // Chroma stripes sit at the halved grid: rows 26/27 above row 28.
  av1_stripe_assert_pair(info.top[1], 128, 26, 27, cb, 128)
  av1_stripe_assert_pair(info.bottom[0], 128, 28, 29, cb, 128)
  av1_stripe_assert_pair(info.bottom[3], 128, 124, 125, cb, 128)
  // The second chroma plane carries its own values.
  let info2 = store.planes[2]
  av1_stripe_assert_pair(info2.top[1], 128, 26, 27, cr, 128)
  assert_true(av1_restoration_stripe_store_valid(store))
}

///|
test "save rejects invalid geometry" {
  let plane = av1_stripe_test_plane(256, 256, 256, 0)
  // Plane count disagrees with monochrome.
  assert_true(
    av1_restoration_save_stripes([plane], 256, 256, 256, 256, 8, false) is None,
  )
  assert_true(
    av1_restoration_save_stripes([plane, plane, plane], 256, 256, 256, 256, 8,
      true) is None,
  )
  // Zero or negative extents.
  assert_true(av1_restoration_save_stripes([plane], 256, 0, 0, 256, 8, true) is None)
  assert_true(
    av1_restoration_save_stripes([plane], 256, 256, 256, 0, 8, true) is None,
  )
  // Unsupported bit depth.
  assert_true(
    av1_restoration_save_stripes([plane], 256, 256, 256, 256, 9, true) is None,
  )
  // Output width beyond the 2x superres bound.
  assert_true(
    av1_restoration_save_stripes([plane], 256, 256, 513, 256, 8, true) is None,
  )
  // Coded width narrower than the visible width.
  assert_true(
    av1_restoration_save_stripes([plane], 128, 256, 256, 256, 8, true) is None,
  )
  // Source plane shorter than the stripe grid requires.
  let small = Array::make(256 * 16, 0)
  assert_true(
    av1_restoration_save_stripes([small], 256, 256, 256, 256, 8, true) is None,
  )
}

///|
test "stripe pair accessor dispatches by side and rejects out-of-range" {
  let width = 256
  let coded = 256
  let plane = av1_stripe_test_plane(width, 256, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    256,
    8,
    true,
  ).unwrap()
  let above = av1_restoration_stripe_pair(store, 0, 1, true)
  let below = av1_restoration_stripe_pair(store, 0, 0, false)
  assert_eq(above.length(), 512)
  assert_eq(below.length(), 512)
  assert_eq(above[0], plane[54 * coded])
  assert_eq(above[256], plane[55 * coded])
  assert_eq(below[0], plane[56 * coded])
  assert_eq(below[256], plane[57 * coded])
  // Out-of-range plane or stripe reads as absent.
  assert_eq(av1_restoration_stripe_pair(store, 1, 0, true).length(), 0)
  assert_eq(av1_restoration_stripe_pair(store, 0, 99, true).length(), 0)
  assert_eq(av1_restoration_stripe_pair(store, 0, -1, false).length(), 0)
  // The empty outer boundaries also read as absent.
  assert_eq(av1_restoration_stripe_pair(store, 0, 0, true).length(), 0)
  assert_eq(av1_restoration_stripe_pair(store, 0, 4, false).length(), 0)
}

///|
test "store validity contract rejects broken stores" {
  let width = 256
  let coded = 256
  let plane = av1_stripe_test_plane(width, 256, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    256,
    8,
    true,
  ).unwrap()
  assert_true(av1_restoration_stripe_store_valid(store))
  // No planes at all.
  assert_false(av1_restoration_stripe_store_valid({ planes: [] }))
  // Outer boundary populated.
  let info = store.planes[0]
  info.top[0] = Array::make(2 * 256, 0)
  assert_false(av1_restoration_stripe_store_valid(store))
  info.top[0] = []
  // Internal boundary missing.
  info.top[1] = []
  assert_false(av1_restoration_stripe_store_valid(store))
  info.top[1] = Array::make(2 * 256, 0)
  // Pair at the wrong width.
  info.bottom[0] = Array::make(2 * 128, 0)
  assert_false(av1_restoration_stripe_store_valid(store))
}

///|
test "source view reads frame inside stripes and pairs at boundaries" {
  let width = 256
  let height = 256
  let coded = 256
  let plane = av1_stripe_test_plane(width, height, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  // Post-CDEF frame: every row offset by a large distinct base.
  let post = av1_stripe_test_plane(width, height, coded, 100000)
  let view : Av1RestorationSourceView = {
    store,
    frame: [post],
    frame_strides: [256],
  }
  // Inside stripe 1 (rows 56..119): the frame itself.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 100, 1), 100000 + 100 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 0, 119, 1), 100000 + 119 * 256)
  // Above the internal start of stripe 1: rows 54/55 are saved as
  // [top0, top0, top1] at offsets -3, -2, -1.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 53, 1), 54 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 54, 1), 54 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 55, 1), 55 * 256 + 10)
  // Below the internal end of stripe 0: rows 56/57 are saved as
  // [bottom0, bottom1, bottom1] at offsets 0, 1, 2.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 56, 0), 56 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 57, 0), 57 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 58, 0), 57 * 256 + 10)
  // Last stripe 4: top rows 246/247, no bottom pair (frame bottom).
  // Offsets -3 and -2 share the first saved row, -1 uses the second.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 245, 4), 246 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 246, 4), 246 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 247, 4), 247 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 250, 4), 100000 + 250 * 256 + 10)
  // Frame top repeats row 0; the last stripe's out-of-frame taps
  // repeat the last row.
  assert_eq(av1_restoration_source_sample(view, 0, 10, -3, 0), 100000 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, -1, 0), 100000 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 256, 4), 100000 + 255 * 256 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 300, 4), 100000 + 255 * 256 + 10)
  // x clamps to the visible plane width.
  assert_eq(av1_restoration_source_sample(view, 0, -5, 100, 1), 100000 + 100 * 256)
  assert_eq(av1_restoration_source_sample(view, 0, 300, 100, 1), 100000 + 100 * 256 + 255)
  // Out-of-range plane or stripe reads as zero.
  assert_eq(av1_restoration_source_sample(view, 1, 10, 100, 0), 0)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 100, 99), 0)
  assert_eq(av1_restoration_source_sample(view, -1, 10, 100, 0), 0)
}

///|
test "source view clamps x on saved boundary rows" {
  let width = 128
  let height = 128
  let coded = 128
  let plane = av1_stripe_test_plane(width, height, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let post = av1_stripe_test_plane(width, height, coded, 100000)
  let view : Av1RestorationSourceView = {
    store,
    frame: [post],
    frame_strides: [128],
  }
  // Stripe 1 starts at 56; a tap far past the right edge clamps to
  // the last visible column on the saved top pair.
  assert_eq(av1_restoration_source_sample(view, 0, 200, 53, 1), 54 * 128 + 127)
  assert_eq(av1_restoration_source_sample(view, 0, -7, 55, 1), 55 * 128)
  // Same clamping inside the stripe on the frame rows.
  assert_eq(av1_restoration_source_sample(view, 0, 500, 100, 1), 100000 + 100 * 128 + 127)
  assert_eq(av1_restoration_source_sample(view, 0, -9, 100, 1), 100000 + 100 * 128)
}

///|
test "source view repeats the saved row past the frame bottom of a non-last stripe" {
  let width = 128
  let height = 57
  let coded = 128
  let plane = av1_stripe_test_plane(width, height, coded, 0)
  let store = av1_restoration_save_stripes(
    [plane],
    coded,
    width,
    width,
    height,
    8,
    true,
  ).unwrap()
  let post = av1_stripe_test_plane(width, height, coded, 100000)
  let view : Av1RestorationSourceView = {
    store,
    frame: [post],
    frame_strides: [128],
  }
  // Stripe 0 ends at 56; its bottom pair is row 56 duplicated. Taps
  // at offsets 0, 1 and 2 beyond the end read the saved rows even
  // though rows 57+ lie past the frame bottom.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 56, 0), 56 * 128 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 57, 0), 56 * 128 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 58, 0), 56 * 128 + 10)
  // The last stripe (1) ends at the frame bottom: its out-of-frame
  // taps repeat the post-CDEF edge row instead of a saved pair.
  assert_eq(av1_restoration_source_sample(view, 0, 10, 57, 1), 100000 + 56 * 128 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 60, 1), 100000 + 56 * 128 + 10)
  // Its top taps read the saved top pair (rows 54, 55).
  assert_eq(av1_restoration_source_sample(view, 0, 10, 53, 1), 54 * 128 + 10)
  assert_eq(av1_restoration_source_sample(view, 0, 10, 55, 1), 55 * 128 + 10)
}
