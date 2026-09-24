/// Regression vectors from unmodified dav1d 1.2.1 C routines:
/// lf_mask.c calc_lf_value SHA256
/// 00b360305b59fc2f1984346f1d80efe628eea8bccd80222011729f929a756d96;
/// loopfilter_tmpl.c loop_filter SHA256
/// 4360c3cf2f68342e0a7c0aa3f3fec17d526defe0b3a257f53143f3d9c96f1105.
/// The C functions were compiled unchanged with a small typedef/printf harness.

///|
test "delta LF clamps before segmentation and scales reference deltas afterwards" {
  // Columns: frame level, accumulated delta-LF, segment ALT_LF.
  let cases = [
    [31, 4, -3],
    [60, 10, -20],
    [2, -10, 20],
    [31, 20, -30],
    [1, -63, 63],
    [63, 63, -63],
    [32, 0, 0],
    [0, 63, 0],
    [63, -63, 0],
    [0, 0, 0],
  ]
  // Original C outputs for reference/mode (0,0),(1,0),(1,1),(4,0),(7,1).
  let expected = [
    [34, 42, 32, 34, 0],
    [45, 53, 43, 45, 0],
    [21, 25, 20, 21, 0],
    [22, 26, 21, 22, 0],
    [63, 63, 63, 63, 0],
    [1, 5, 0, 1, 0],
    [34, 42, 32, 34, 0],
    [63, 63, 63, 63, 0],
    [1, 5, 0, 1, 0],
    [1, 5, 0, 1, 0],
  ]
  let references = [0, 1, 1, 4, 7]
  let modes = [0, 0, 1, 0, 1]
  for i in 0..<cases.length() {
    let config : Av1LoopFilterConfig = {
      levels: [cases[i][0], 1, 1, 1],
      sharpness: 0,
      delta_enabled: true,
      ref_deltas: [1, 3, -4, 0, -1, 0, 63, -64],
      mode_deltas: [2, -3],
    }
    for j in 0..<references.length() {
      assert_eq(
        av1_loop_filter_edge_level(
          config,
          0,
          0,
          references[j],
          modes[j],
          segment_delta=cases[i][2],
          delta_lf=cases[i][1],
        ),
        Some(expected[i][j]),
      )
    }
  }
}

///|
test "dynamic LF retains frame and chroma zero gates" {
  let disabled = av1_loop_filter_frame_test_config([0, 0, 0, 0])
  assert_eq(
    av1_loop_filter_edge_level(
      disabled,
      0,
      0,
      0,
      0,
      segment_delta=63,
      delta_lf=63,
    ),
    Some(0),
  )
  let enabled = av1_loop_filter_frame_test_config([0, 1, 0, 1])
  assert_eq(
    av1_loop_filter_edge_level(
      enabled,
      0,
      0,
      0,
      0,
      segment_delta=7,
      delta_lf=10,
    ),
    Some(17),
  )
  assert_eq(
    av1_loop_filter_edge_level(
      enabled,
      1,
      0,
      0,
      0,
      segment_delta=63,
      delta_lf=63,
    ),
    Some(0),
  )
  assert_eq(
    av1_loop_filter_edge_level(
      enabled,
      2,
      1,
      0,
      0,
      segment_delta=-20,
      delta_lf=63,
    ),
    Some(43),
  )
  assert_eq(av1_loop_filter_edge_level(enabled, 0, 0, 0, 0, delta_lf=64), None)
}

///|
test "LF block metadata uses the luma MI and bottom right chroma owner" {
  let config = av1_loop_filter_frame_test_config([10, 10, 10, 10])
  let map : Av1LoopFilterBlockMap = {
    cols: 4,
    rows: 4,
    segment_ids: Array::make(16, 0),
    deltas: Array::makei(64, i => i / 4 + 2 * (i % 4)),
    segmentation: av1_segmentation_empty(),
  }
  assert_true(av1_loop_filter_block_map_valid(map, 4, 4))
  // (4,0) in Y is MI(0,1), without OR-ing chroma subsampling into Y.
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 0, 0, 4, 0, 1, 1),
    Some(11),
  )
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 0, 1, 4, 0, 1, 1),
    Some(13),
  )
  // (4,0) in 4:2:0 chroma uses luma MI(1,3), and U/V have distinct components.
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 1, 0, 4, 0, 1, 1),
    Some(21),
  )
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 1, 1, 4, 0, 1, 1),
    Some(21),
  )
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 2, 0, 4, 0, 1, 1),
    Some(23),
  )
  // 4:2:2 only widens horizontally; 4:4:4 keeps both MI coordinates.
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 1, 0, 4, 0, 1, 0),
    Some(17),
  )
  assert_eq(
    av1_loop_filter_block_level(config, None, Some(map), 1, 0, 4, 0, 0, 0),
    Some(15),
  )
  let field = av1_motion_field(4, 4)
  field.refs[2] = 3
  field.y_modes[1] = av1_mode_nearest_mv
  field.refs[5 * 2] = 6
  assert_eq(av1_loop_filter_block_state(Some(field), 0, 4, 0, 1, 1), (3, 1))
}

///|
test "per MI LF metadata matches original C pixels at every bit depth" {
  let expected = [
    [
      100, 100, 102, 103, 105, 106, 108, 108, 100, 101, 102, 106, 109, 108, 109,
      110, 101, 102, 104, 104, 108, 109, 110, 112, 102, 105, 104, 107, 110, 109,
      113, 109, 104, 108, 108, 109, 111, 110, 116, 117, 105, 106, 108, 109, 111,
      111, 114, 114, 106, 107, 108, 112, 115, 114, 115, 116, 106, 108, 110, 110,
      114, 114, 116, 118,
    ],
    [
      400, 400, 406, 412, 420, 426, 432, 432, 400, 401, 402, 412, 427, 432, 433,
      434, 405, 402, 404, 410, 426, 436, 434, 436, 409, 410, 410, 418, 431, 439,
      442, 440, 415, 421, 424, 431, 440, 443, 453, 452, 419, 424, 430, 436, 444,
      446, 456, 456, 424, 425, 432, 439, 448, 450, 457, 458, 424, 426, 435, 438,
      446, 449, 458, 460,
    ],
    [
      1600, 1600, 1624, 1648, 1680, 1704, 1728, 1728, 1600, 1601, 1602, 1636, 1699,
      1728, 1729, 1730, 1618, 1602, 1604, 1634, 1698, 1742, 1730, 1732, 1636, 1628,
      1632, 1663, 1718, 1755, 1756, 1754, 1660, 1675, 1692, 1718, 1757, 1773, 1803,
      1802, 1678, 1696, 1720, 1744, 1776, 1786, 1824, 1824, 1696, 1697, 1722, 1747,
      1780, 1800, 1825, 1826, 1696, 1698, 1725, 1746, 1778, 1799, 1826, 1828,
    ],
  ]
  let features = Array::makei(8, _ => Array::make(8, false))
  let values = Array::makei(8, _ => Array::make(8, 0))
  let y_features = [[0, 3], [-1, 4], [0, -63], [-63, -63]]
  for segment in 0..<4 {
    for direction in 0..<2 {
      features[segment][direction + 1] = true
      values[segment][direction + 1] = y_features[segment][direction]
    }
  }
  let segmentation : Av1SegmentationParams = {
    enabled: true,
    update_map: true,
    temporal_update: false,
    update_data: true,
    feature_enabled: features,
    feature_data: values,
    seg_id_pre_skip: false,
    last_active_seg_id: 3,
  }
  let deltas = [-4, -63, 3, 12]
  let map : Av1LoopFilterBlockMap = {
    cols: 2,
    rows: 2,
    segment_ids: [0, 1, 2, 3],
    deltas: Array::makei(16, i => deltas[i / 4]),
    segmentation,
  }
  for case in 0..<3 {
    let depth = 8 + 2 * case
    let scale = 1 << (depth - 8)
    let pixels = Array::makei(64, i => {
      let x = i % 8
      let y = i / 8
      (100 + (if x >= 4 { 8 } else { 0 }) + (if y >= 4 { 6 } else { 0 })) *
      scale +
      x * y % 5
    })
    // Original C calls vertical4 at (4,0) and (4,4) at levels 12/19,
    // then horizontal4 at (0,4)/(4,4) at levels 15/4. All four edges
    // obtain their nonzero level from the previous side, not the current MI.
    assert_true(
      av1_loop_filter_frame(
        av1_loop_filter_frame_test_config([16, 16, 0, 0]),
        8,
        8,
        8,
        8,
        depth,
        [pixels],
        [Array::make(4, 4 | (4 << 8))],
        block_map=Some(map),
      ),
    )
    assert_eq(pixels, expected[case])
  }
}

///|
test "delta LF changes at a real 64 pixel SB boundary" {
  let expected = [
    [100, 100, 102, 103, 105, 106, 108, 108],
    [400, 400, 406, 412, 420, 426, 432, 432],
    [1600, 1600, 1624, 1648, 1680, 1704, 1728, 1728],
  ]
  let map : Av1LoopFilterBlockMap = {
    cols: 32,
    rows: 2,
    segment_ids: Array::make(64, 0),
    deltas: Array::makei(256, i => if i / 4 % 32 < 16 { -4 } else { -63 }),
    segmentation: av1_segmentation_empty(),
  }
  for case in 0..<3 {
    let scale = 1 << (2 * case)
    let pixels = Array::makei(1024, i => {
      (if i % 128 < 64 { 100 } else { 108 }) * scale
    })
    assert_true(
      av1_loop_filter_frame(
        av1_loop_filter_frame_test_config([16, 16, 0, 0]),
        128,
        8,
        128,
        8,
        8 + 2 * case,
        [pixels],
        [Array::make(64, 4 | (4 << 8))],
        block_map=Some(map),
      ),
    )
    for row in 0..<8 {
      for col in 0..<128 {
        let value = if col >= 60 && col < 68 {
          expected[case][col - 60]
        } else {
          (if col < 64 { 100 } else { 108 }) * scale
        }
        assert_eq(pixels[row * 128 + col], value)
      }
    }
  }
}

///|
test "LF rejects malformed block metadata before modifying pixels" {
  let pixels = Array::makei(64, i => 100 + i % 8)
  let original = pixels.copy()
  let map : Av1LoopFilterBlockMap = {
    cols: 2,
    rows: 2,
    segment_ids: [0, 0, 0, 0],
    deltas: Array::make(16, 0),
    segmentation: av1_segmentation_empty(),
  }
  map.deltas[7] = 64
  assert_false(
    av1_loop_filter_frame(
      av1_loop_filter_frame_test_config([16, 16, 0, 0]),
      8,
      8,
      8,
      8,
      8,
      [pixels],
      [Array::make(4, 4 | (4 << 8))],
      block_map=Some(map),
    ),
  )
  assert_eq(pixels, original)
}
