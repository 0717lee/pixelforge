///|
/// Filter metadata assembled on the frame's luma 4x4 grid. Each MI has four
/// accumulated delta-LF values in Y-vertical, Y-horizontal, U, V order; a
/// single-delta stream broadcasts its value to all four entries when decoded.
/// Every covered MI retains its coding block's segment id and SB delta values.
pub(all) struct Av1LoopFilterBlockMap {
  cols : Int
  rows : Int
  segment_ids : Array[Int]
  deltas : Array[Int]
  segmentation : Av1SegmentationParams
}

///|
fn av1_loop_filter_block_map_valid(
  map : Av1LoopFilterBlockMap,
  cols : Int,
  rows : Int,
) -> Bool {
  if map.cols != cols ||
    map.rows != rows ||
    map.segment_ids.length() != cols * rows ||
    map.deltas.length() != cols * rows * 4 {
    return false
  }
  for id in map.segment_ids {
    if id < 0 || id >= 8 {
      return false
    }
  }
  for delta in map.deltas {
    if delta < -63 || delta > 63 {
      return false
    }
  }
  let segmentation = map.segmentation
  if segmentation.enabled {
    if segmentation.feature_enabled.length() != 8 ||
      segmentation.feature_data.length() != 8 {
      return false
    }
    for segment in 0..<8 {
      if segmentation.feature_enabled[segment].length() != 8 ||
        segmentation.feature_data[segment].length() != 8 {
        return false
      }
      for feature in 1..<5 {
        let delta = segmentation.feature_data[segment][feature]
        if segmentation.feature_enabled[segment][feature] &&
          (delta < -63 || delta > 63) {
          return false
        }
      }
    }
  }
  true
}

///|
/// Chroma selects the bottom-right luma MI of its subsampled group. Luma uses
/// the addressed MI unchanged, regardless of the frame's chroma subsampling.
fn av1_loop_filter_luma_mi(
  plane : Int,
  x : Int,
  y : Int,
  sub_x : Int,
  sub_y : Int,
) -> (Int, Int) {
  if plane == 0 {
    (y / 4, x / 4)
  } else {
    (((y << sub_y) / 4) | sub_y, ((x << sub_x) / 4) | sub_x)
  }
}

///|
/// Select this side's segment and accumulated SB delta, then combine them with
/// its actual reference/mode state. `block_map` was validated before filtering.
fn av1_loop_filter_block_level(
  config : Av1LoopFilterConfig,
  field : Av1MotionField?,
  block_map : Av1LoopFilterBlockMap?,
  plane : Int,
  direction : Int,
  x : Int,
  y : Int,
  sub_x : Int,
  sub_y : Int,
) -> Int? {
  let (reference, mode_type) = av1_loop_filter_block_state(
    field, plane, x, y, sub_x, sub_y,
  )
  let mut segment_delta = 0
  let mut delta_lf = 0
  match block_map {
    Some(map) => {
      let (row, col) = av1_loop_filter_luma_mi(plane, x, y, sub_x, sub_y)
      if row < 0 || col < 0 || row >= map.rows || col >= map.cols {
        return None
      }
      let unit = row * map.cols + col
      let component = if plane == 0 { direction } else { plane + 1 }
      delta_lf = map.deltas[unit * 4 + component]
      let segment = map.segment_ids[unit]
      let feature = component + 1
      if map.segmentation.enabled &&
        map.segmentation.feature_enabled[segment][feature] {
        segment_delta = map.segmentation.feature_data[segment][feature]
      }
    }
    None => ()
  }
  av1_loop_filter_edge_level(
    config,
    plane,
    direction,
    reference,
    mode_type,
    segment_delta~,
    delta_lf~,
  )
}
