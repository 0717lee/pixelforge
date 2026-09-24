///|
/// AV1 deblocking thresholds in the eight-bit domain. The edge kernel scales
/// them by 1 << (bit_depth - 8). `level` is the effective edge strength after
/// frame/segment/reference deltas, not the raw frame-header level.
fn av1_loop_filter_thresholds(level : Int, sharpness : Int) -> (Int, Int, Int)? {
  if level < 0 || level > 63 || sharpness < 0 || sharpness > 7 {
    return None
  }
  let shift = if sharpness > 4 { 2 } else if sharpness > 0 { 1 } else { 0 }
  let mut limit = level >> shift
  if sharpness > 0 && limit > 9 - sharpness {
    limit = 9 - sharpness
  }
  if limit < 1 {
    limit = 1
  }
  Some((limit, 2 * (level + 2) + limit, level >> 4))
}

///|
fn av1_loop_filter_signed_clamp(value : Int, center : Int) -> Int {
  if value < -center {
    -center
  } else if value >= center {
    center - 1
  } else {
    value
  }
}

///|
/// The common narrow fallback is called only after the selected width's mask
/// passes. It must not recompute a narrower mask for a 6/8/14-tap fallback.
fn av1_loop_filter_narrow(
  samples : Array[Int],
  output : Array[Int],
  threshold : Int,
  bit_depth : Int,
) -> Unit {
  let center = 128 << (bit_depth - 8)
  let p1 = samples[5] - center
  let p0 = samples[6] - center
  let q0 = samples[7] - center
  let q1 = samples[8] - center
  let hev = (p1 - p0).abs() > threshold || (q1 - q0).abs() > threshold
  let outer = if hev {
    av1_loop_filter_signed_clamp(p1 - q1, center)
  } else {
    0
  }
  let filter = av1_loop_filter_signed_clamp(outer + 3 * (q0 - p0), center)
  // These biases stay 4 and 3 at every bit depth. Clamp before shifting.
  let filter1 = av1_loop_filter_signed_clamp(filter + 4, center) >> 3
  let filter2 = av1_loop_filter_signed_clamp(filter + 3, center) >> 3
  output[7] = av1_loop_filter_signed_clamp(q0 - filter1, center) + center
  output[6] = av1_loop_filter_signed_clamp(p0 + filter2, center) + center
  // ROUND_POWER_OF_TWO is arithmetic (value+1)>>1, including negative values.
  let adjustment = if hev { 0 } else { (filter1 + 1) >> 1 }
  output[8] = av1_loop_filter_signed_clamp(q1 - adjustment, center) + center
  output[5] = av1_loop_filter_signed_clamp(p1 + adjustment, center) + center
}

///|
/// Strong filters use the original samples on both sides. Mirroring the
/// positive-side formula supplies the opposite side without reading writes.
fn av1_loop_filter_wide(
  samples : Array[Int],
  output : Array[Int],
  width : Int,
) -> Unit {
  for side in 0..<2 {
    let center = if side == 0 { 6 } else { 7 }
    let step = if side == 0 { -1 } else { 1 }
    let p0 = samples[center]
    let p1 = samples[center + step]
    let p2 = samples[center + 2 * step]
    let q0 = samples[center - step]
    let q1 = samples[center - 2 * step]
    if width == 6 {
      output[center + step] = (3 * p2 + 2 * p1 + 2 * p0 + q0 + 4) >> 3
      output[center] = (p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3
    } else {
      let p3 = samples[center + 3 * step]
      let q2 = samples[center - 3 * step]
      if width == 8 {
        output[center + 2 * step] = (3 * p3 + 2 * p2 + p1 + p0 + q0 + 4) >> 3
        output[center + step] = (2 * p3 + p2 + 2 * p1 + p0 + q0 + q1 + 4) >> 3
        output[center] = (p3 + p2 + p1 + 2 * p0 + q0 + q1 + q2 + 4) >> 3
      } else {
        let p4 = samples[center + 4 * step]
        let p5 = samples[center + 5 * step]
        let p6 = samples[center + 6 * step]
        let q3 = samples[center - 4 * step]
        let q4 = samples[center - 5 * step]
        let q5 = samples[center - 6 * step]
        output[center + 5 * step] = (
            7 * p6 + 2 * p5 + 2 * p4 + p3 + p2 + p1 + p0 + q0 + 8
          ) >>
          4
        output[center + 4 * step] = (
            5 * p6 + 2 * p5 + 2 * p4 + 2 * p3 + p2 + p1 + p0 + q0 + q1 + 8
          ) >>
          4
        output[center + 3 * step] = (
            4 * p6 + p5 + 2 * p4 + 2 * p3 + 2 * p2 + p1 + p0 + q0 + q1 + q2 + 8
          ) >>
          4
        output[center + 2 * step] = (
            3 * p6 +
            p5 +
            p4 +
            2 * p3 +
            2 * p2 +
            2 * p1 +
            p0 +
            q0 +
            q1 +
            q2 +
            q3 +
            8
          ) >>
          4
        output[center + step] = (
            2 * p6 +
            p5 +
            p4 +
            p3 +
            2 * p2 +
            2 * p1 +
            2 * p0 +
            q0 +
            q1 +
            q2 +
            q3 +
            q4 +
            8
          ) >>
          4
        output[center] = (
            p6 +
            p5 +
            p4 +
            p3 +
            p2 +
            2 * p1 +
            2 * p0 +
            2 * q0 +
            q1 +
            q2 +
            q3 +
            q4 +
            q5 +
            8
          ) >>
          4
      }
    }
  }
}

///|
/// Filter one AV1 edge lane at native 8/10/12-bit precision. Samples are
/// [p6,p5,p4,p3,p2,p1,p0,q0,q1,q2,q3,q4,q5,q6]; untouched slots are preserved.
/// Direct widths 4/6/8 depend on p1/p2/p3 through q1/q2/q3 respectively;
/// width14 additionally reads p4..p6/q4..q6 for flat2 and its strong filter.
/// A width8/14 fallback to the narrow filter retains its original wider mask.
/// No frame traversal, edge-strength deltas or pixel-coordinate clamping is
/// performed here. The caller supplies an effective level; level0 is a no-op.
/// Reference: pinned libaom 8e7b6a567df174d795479b92b4ac766d271add73,
/// aom_dsp/loopfilter.c scalar 4/6/8/14 and highbd functions.
fn av1_loop_filter_edge(
  samples : Array[Int],
  filter_width : Int,
  level : Int,
  sharpness : Int,
  bit_depth : Int,
) -> Array[Int]? {
  if samples.length() != 14 ||
    (
      filter_width != 4 &&
      filter_width != 6 &&
      filter_width != 8 &&
      filter_width != 14
    ) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  let (limit8, blimit8, threshold8) = match
    av1_loop_filter_thresholds(level, sharpness) {
    Some(value) => value
    None => return None
  }
  let maximum = (1 << bit_depth) - 1
  for sample in samples {
    if sample < 0 || sample > maximum {
      return None
    }
  }
  let output = samples.copy()
  if level == 0 {
    return Some(output)
  }
  let scale = 1 << (bit_depth - 8)
  let limit = limit8 * scale
  let blimit = blimit8 * scale
  let p0 = samples[6]
  let q0 = samples[7]
  if 2 * (p0 - q0).abs() + (samples[5] - samples[8]).abs() / 2 > blimit {
    return Some(output)
  }
  let radius = if filter_width == 4 {
    1
  } else if filter_width == 6 {
    2
  } else {
    3
  }
  for i in 1..<(radius + 1) {
    if (samples[6 - i] - samples[7 - i]).abs() > limit ||
      (samples[7 + i] - samples[6 + i]).abs() > limit {
      return Some(output)
    }
  }
  let mut flat = filter_width != 4
  if flat {
    for i in 1..<(radius + 1) {
      if (samples[6 - i] - p0).abs() > scale ||
        (samples[7 + i] - q0).abs() > scale {
        flat = false
      }
    }
  }
  let mut flat2 = filter_width == 14
  if flat2 {
    for i in 4..<7 {
      if (samples[6 - i] - p0).abs() > scale ||
        (samples[7 + i] - q0).abs() > scale {
        flat2 = false
      }
    }
  }
  if flat {
    let width = if filter_width == 14 && !flat2 { 8 } else { filter_width }
    av1_loop_filter_wide(samples, output, width)
  } else {
    av1_loop_filter_narrow(samples, output, threshold8 * scale, bit_depth)
  }
  Some(output)
}
