///|
/// Frame-level AV1 loop-filter parameters. Reduced still frames begin with
/// default reference deltas; lossless frames omit this configuration entirely.
pub(all) struct Av1LoopFilterConfig {
  levels : Array[Int]
  sharpness : Int
  delta_enabled : Bool
  ref_deltas : Array[Int]
  mode_deltas : Array[Int]
}

///|
fn av1_loop_filter_config_valid(config : Av1LoopFilterConfig) -> Bool {
  if config.levels.length() != 4 ||
    config.ref_deltas.length() != 8 ||
    config.mode_deltas.length() != 2 ||
    config.sharpness < 0 ||
    config.sharpness > 7 {
    return false
  }
  for level in config.levels {
    if level < 0 || level > 63 {
      return false
    }
  }
  for delta in config.ref_deltas {
    if delta < -64 || delta > 63 {
      return false
    }
  }
  for delta in config.mode_deltas {
    if delta < -64 || delta > 63 {
      return false
    }
  }
  true
}

///|
/// Parse loop_filter_params after coded-lossless and delta-LF gates have been
/// handled. UV levels exist only for color with at least one nonzero Y level.
fn av1_parse_loop_filter_config(
  reader : Av1FrameBits,
  monochrome : Bool,
  ref_deltas? : Array[Int] = [],
  mode_deltas? : Array[Int] = [],
) -> Av1LoopFilterConfig? {
  let levels = [0, 0, 0, 0]
  for i in 0..<2 {
    levels[i] = match reader.take(6) {
      Some(value) => value
      None => return None
    }
  }
  if !monochrome && (levels[0] != 0 || levels[1] != 0) {
    for i in 2..<4 {
      levels[i] = match reader.take(6) {
        Some(value) => value
        None => return None
      }
    }
  }
  let sharpness = match reader.take(3) {
    Some(value) => value
    None => return None
  }
  let delta_enabled = match reader.take(1) {
    Some(value) => value == 1
    None => return None
  }
  // `setup_past_independence` or `load_previous` seeds these; the update bits
  // below only override the entries the frame re-codes (AV1 7.20, 7.21).
  let ref_deltas = if ref_deltas.length() == 8 {
    ref_deltas
  } else {
    av1_default_loop_filter_ref_deltas()
  }
  let mode_deltas = if mode_deltas.length() == 2 { mode_deltas } else { [0, 0] }
  if delta_enabled {
    let update = match reader.take(1) {
      Some(value) => value == 1
      None => return None
    }
    if update {
      for i in 0..<8 {
        match reader.take(1) {
          Some(1) =>
            ref_deltas[i] = match reader.signed(7) {
              Some(value) => value
              None => return None
            }
          Some(_) => ()
          None => return None
        }
      }
      for i in 0..<2 {
        match reader.take(1) {
          Some(1) =>
            mode_deltas[i] = match reader.signed(7) {
              Some(value) => value
              None => return None
            }
          Some(_) => ()
          None => return None
        }
      }
    }
  }
  Some({ levels, sharpness, delta_enabled, ref_deltas, mode_deltas, })
}

///|
/// Strength selected for one edge (AV1 §7.14.5). Clamp the frame level plus
/// delta-LF first, then add and clamp the segment ALT_LF feature. Reference and
/// mode deltas scale from that resulting level, not the original frame level.
///
/// The two gates below sit *outside* the delta arithmetic: a frame whose two Y
/// levels are both zero is not deblocked at all, and §7.14.1 skips a chroma plane
/// whose own level is zero. So a delta can lift an edge whose base is zero only
/// when that plane is already being filtered; both gates were pinned down by
/// measuring dav1d, since a positive delta on a zero level would otherwise start
/// deblocking.
/// Intra blocks and unwritten neighbourhoods take the `reference == INTRA_FRAME`
/// branch and never see a mode delta, because §7.14.5 adds one only when the
/// block codes from a reference frame.
fn av1_loop_filter_edge_level(
  config : Av1LoopFilterConfig,
  plane : Int,
  direction : Int,
  reference : Int,
  mode_type : Int,
  segment_delta? : Int = 0,
  delta_lf? : Int = 0,
) -> Int? {
  if !av1_loop_filter_config_valid(config) ||
    plane < 0 ||
    plane > 2 ||
    direction < 0 ||
    direction > 1 ||
    segment_delta < -63 ||
    segment_delta > 63 ||
    delta_lf < -63 ||
    delta_lf > 63 ||
    ((mode_type < 0 || mode_type > 1) && reference > av1_intra_frame) {
    return None
  }
  if plane == 0 {
    if config.levels[0] == 0 && config.levels[1] == 0 {
      return Some(0)
    }
  } else if config.levels[plane + 1] == 0 {
    return Some(0)
  }
  let frame_level = config.levels[if plane == 0 {
      direction
    } else {
      plane + 1
    }]
  let delta_level = av1_loop_filter_level_clip(frame_level + delta_lf)
  let base = av1_loop_filter_level_clip(delta_level + segment_delta)
  let shift = base >> 5
  let level = if !config.delta_enabled {
    base
  } else if reference <= av1_intra_frame {
    base + (config.ref_deltas[0] << shift)
  } else if reference >= 8 {
    return None
  } else {
    base +
    (config.ref_deltas[reference] << shift) +
    (config.mode_deltas[mode_type] << shift)
  }
  Some(av1_loop_filter_level_clip(level))
}

///|
fn av1_loop_filter_level_clip(level : Int) -> Int {
  if level < 0 {
    0
  } else if level > 63 {
    63
  } else {
    level
  }
}

///|
/// Effective strength for a pure-intra, segment-zero, no-delta-LF frame.
/// Y gates both directions together; U and V each gate their own base level.
/// Mode deltas apply to inter blocks only and therefore do not enter this sum.
fn av1_loop_filter_intra_level(
  config : Av1LoopFilterConfig,
  plane : Int,
  direction : Int,
) -> Int? {
  if plane < 0 || plane > 2 || direction < 0 || direction > 1 {
    return None
  }
  av1_loop_filter_edge_level(config, plane, direction, av1_intra_frame, 0)
}
