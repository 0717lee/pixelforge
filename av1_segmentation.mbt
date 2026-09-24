///|
/// The feature tables saved by update_reference_map do not alias header arrays.
fn av1_segmentation_copy(
  params : Av1SegmentationParams,
) -> Av1SegmentationParams {
  {
    ..params,
    feature_enabled: params.feature_enabled.map(row => row.copy()),
    feature_data: params.feature_data.map(row => row.copy()),
  }
}

///|
fn av1_segmentation_primary(
  map : Av1FrameMap?,
  primary : Int,
  indices : Array[Int],
) -> Av1SegmentationParams? {
  if primary < 0 ||
    primary >= av1_primary_ref_none ||
    primary >= indices.length() {
    return None
  }
  let state = match map {
    Some(value) => value
    None => return None
  }
  let slot = indices[primary]
  if slot < 0 || slot >= av1_num_ref_frames || !state.valid[slot] {
    return None
  }
  Some(av1_segmentation_copy(state.saved_segmentation[slot]))
}

///|
fn av1_segment_feature(
  params : Av1SegmentationParams,
  id : Int,
  feature : Int,
) -> Bool {
  params.enabled &&
  id >= 0 &&
  id < av1_segments &&
  feature >= 0 &&
  feature < av1_segment_levels &&
  params.feature_enabled[id][feature]
}

///|
/// Segment map prediction uses the minimum id over the whole block footprint.
fn av1_segment_previous_id(
  state : Av1IntraState,
  row : Int,
  col : Int,
  width4 : Int,
  height4 : Int,
) -> Int {
  if state.previous_seg_ids.length() != state.cols * state.rows {
    return 0
  }
  let mut predicted = 7
  for y in row..<(row + height4) {
    for x in col..<(col + width4) {
      if y >= 0 && y < state.rows && x >= 0 && x < state.cols {
        let id = state.previous_seg_ids[y * state.cols + x]
        if id < predicted {
          predicted = id
        }
      }
    }
  }
  predicted
}
