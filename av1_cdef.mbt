/// Bounded AV1 Constrained Directional Enhancement Filter (CDEF).
///
/// The tile decoder currently reconstructs planar samples before converting
/// them to `Image`.  This module keeps the CDEF stage at that same planar
/// boundary: callers provide one parameter record per 8x8 block and receive a
/// filtered plane.  It deliberately does not infer block directions or parse
/// frame-header literals; those values are entropy/frame-state concerns.

/// CDEF parameters for one 8x8 block.
///
/// `primary_strength` and `secondary_strength` are the AV1 coded strengths
/// (before bit-depth scaling). `damping` is the coded damping value and
/// `direction` is the AV1 direction index in [0, 7].
pub(all) struct Av1CdefParams {
  primary_strength : Int
  secondary_strength : Int
  damping : Int
  direction : Int
}

/// Return the signed pixel offset for an AV1 CDEF direction and distance.
fn av1_cdef_offset(direction : Int, distance : Int) -> (Int, Int) {
  match direction & 7 {
    0 => (distance, 0)
    1 => (distance, distance)
    2 => (0, distance)
    3 => (-distance, distance)
    4 => (-distance, 0)
    5 => (-distance, -distance)
    6 => (0, -distance)
    _ => (distance, -distance)
  }
}

/// CDEF's clipped difference operator.  The damping shift is applied before
/// clipping, as specified by AV1; keeping this in Int also makes the 10/12-bit
/// path deterministic on all MoonBit targets.
fn av1_cdef_constrain(diff : Int, threshold : Int, damping : Int) -> Int {
  if threshold <= 0 {
    return 0
  }
  let magnitude = if diff < 0 { -diff } else { diff }
  let damped = magnitude >> damping
  let limit = threshold - damped
  let clipped = if limit < 0 {
    0
  } else if magnitude < limit {
    magnitude
  } else {
    limit
  }
  if diff < 0 { -clipped } else { clipped }
}

fn av1_cdef_clamp_coord(value : Int, limit : Int) -> Int {
  if value < 0 { 0 } else if value >= limit { limit - 1 } else { value }
}

fn av1_cdef_sample(
  plane : Array[Int],
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  dx : Int,
  dy : Int,
) -> Int {
  let sx = av1_cdef_clamp_coord(x + dx, width)
  let sy = av1_cdef_clamp_coord(y + dy, height)
  plane[sy * width + sx]
}

/// Apply CDEF to one integer plane.
///
/// Blocks are visited in raster order and are clamped at frame edges.  This
/// bounded edge policy is equivalent to the AV1 frame boundary policy for a
/// standalone plane and avoids reading outside an independently decoded tile.
/// The returned plane is always a fresh array; a zero-strength parameter is a
/// true no-op copy.
pub fn av1_cdef_filter_plane(
  width : Int,
  height : Int,
  plane : Array[Int],
  params : Array[Av1CdefParams],
  bit_depth? : Int = 8,
) -> Array[Int]? {
  if width <= 0 || height <= 0 || plane.length() != width * height {
    return None
  }
  if bit_depth != 8 && bit_depth != 10 && bit_depth != 12 {
    return None
  }
  let blocks_x = (width + 7) / 8
  let blocks_y = (height + 7) / 8
  if params.length() != blocks_x * blocks_y {
    return None
  }
  for p in params {
    if p.primary_strength < 0 || p.primary_strength > 15 ||
      p.secondary_strength < 0 || p.secondary_strength > 15 ||
      p.damping < 0 || p.damping > 15 || p.direction < 0 || p.direction > 7 {
      return None
    }
  }
  let mut scale = 1
  if bit_depth > 8 {
    scale = 1 << (bit_depth - 8)
  }
  let max_value = (1 << bit_depth) - 1
  let out = plane.copy()
  for by in 0..<blocks_y {
    for bx in 0..<blocks_x {
      let p = params[by * blocks_x + bx]
      let pri = p.primary_strength * scale
      let sec = p.secondary_strength * scale
      let damping = p.damping + (bit_depth - 8)
      let row_end = if (by + 1) * 8 < height { (by + 1) * 8 } else { height }
      let col_end = if (bx + 1) * 8 < width { (bx + 1) * 8 } else { width }
      for y in (by * 8)..<row_end {
        for x in (bx * 8)..<col_end {
          let center = plane[y * width + x]
          if pri == 0 && sec == 0 {
            out[y * width + x] = center
          } else {
            let (p1x, p1y) = av1_cdef_offset(p.direction, 1)
            let (p2x, p2y) = av1_cdef_offset(p.direction, 2)
            let mut sum = 8 * center
            let p1a = av1_cdef_sample(plane, width, height, x, y, p1x, p1y)
            let p1b = av1_cdef_sample(plane, width, height, x, y, -p1x, -p1y)
            let p2a = av1_cdef_sample(plane, width, height, x, y, p2x, p2y)
            let p2b = av1_cdef_sample(plane, width, height, x, y, -p2x, -p2y)
            sum = sum + 4 * av1_cdef_constrain(p1a - center, pri, damping)
            sum = sum + 4 * av1_cdef_constrain(p1b - center, pri, damping)
            sum = sum + 2 * av1_cdef_constrain(p2a - center, pri, damping)
            sum = sum + 2 * av1_cdef_constrain(p2b - center, pri, damping)
            let d0 = (p.direction + 2) & 7
            let d1 = (p.direction + 6) & 7
            let (s0x, s0y) = av1_cdef_offset(d0, 1)
            let (s1x, s1y) = av1_cdef_offset(d0, 2)
            let (s2x, s2y) = av1_cdef_offset(d1, 1)
            let (s3x, s3y) = av1_cdef_offset(d1, 2)
            let s0a = av1_cdef_sample(plane, width, height, x, y, s0x, s0y)
            let s0b = av1_cdef_sample(plane, width, height, x, y, -s0x, -s0y)
            let s1a = av1_cdef_sample(plane, width, height, x, y, s1x, s1y)
            let s1b = av1_cdef_sample(plane, width, height, x, y, -s1x, -s1y)
            let s2a = av1_cdef_sample(plane, width, height, x, y, s2x, s2y)
            let s2b = av1_cdef_sample(plane, width, height, x, y, -s2x, -s2y)
            let s3a = av1_cdef_sample(plane, width, height, x, y, s3x, s3y)
            let s3b = av1_cdef_sample(plane, width, height, x, y, -s3x, -s3y)
            sum = sum + 2 * av1_cdef_constrain(s0a - center, sec, damping)
            sum = sum + 2 * av1_cdef_constrain(s0b - center, sec, damping)
            sum = sum + av1_cdef_constrain(s1a - center, sec, damping)
            sum = sum + av1_cdef_constrain(s1b - center, sec, damping)
            sum = sum + 2 * av1_cdef_constrain(s2a - center, sec, damping)
            sum = sum + 2 * av1_cdef_constrain(s2b - center, sec, damping)
            sum = sum + av1_cdef_constrain(s3a - center, sec, damping)
            sum = sum + av1_cdef_constrain(s3b - center, sec, damping)
            let filtered = (sum + 8) >> 4
            out[y * width + x] = if filtered < 0 {
              0
            } else if filtered > max_value {
              max_value
            } else {
              filtered
            }
          }
        }
      }
    }
  }
  Some(out)
}

/// Apply the same CDEF parameter grid to Y and a separate grid to 4:2:0 U/V.
/// This is the composition boundary used by the AVIF decoder before YUV to
/// RGBA conversion.
pub fn av1_cdef_filter_yuv420(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  y_params : Array[Av1CdefParams],
  uv_params : Array[Av1CdefParams],
  bit_depth? : Int = 8,
) -> ((Array[Int], Array[Int], Array[Int]))? {
  let cw = (width + 1) / 2
  let ch = (height + 1) / 2
  if u.length() != cw * ch || v.length() != cw * ch {
    return None
  }
  let yf = match av1_cdef_filter_plane(width, height, y, y_params, bit_depth~) {
    Some(value) => value
    None => return None
  }
  let uf = match av1_cdef_filter_plane(cw, ch, u, uv_params, bit_depth~) {
    Some(value) => value
    None => return None
  }
  let vf = match av1_cdef_filter_plane(cw, ch, v, uv_params, bit_depth~) {
    Some(value) => value
    None => return None
  }
  Some((yf, uf, vf))
}
