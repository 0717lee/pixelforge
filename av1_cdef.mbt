/// CDEF pixel kernel for caller-supplied block directions and strengths.
///
/// Direction search, luma variance adjustment, skipped-block selection and
/// frame-header parsing are performed by the caller before this kernel.

///|
/// Effective CDEF parameters for one luma 8x8 block (chroma 4x4 in 4:2:0).
/// Strengths use 8-bit units: primary is already variance-adjusted and
/// secondary is decoded to 0, 1, 2 or 4. Damping is CdefDamping (3..6).
pub(all) struct Av1CdefParams {
  primary_strength : Int
  secondary_strength : Int
  damping : Int
  direction : Int
}

///|
/// Native sample units preserve fractional 8-bit-unit luma strengths after
/// variance adjustment. Damping includes bit-depth and chroma adjustments.
priv struct Av1CdefNativeParams {
  primary_strength : Int
  secondary_strength : Int
  damping : Int
  direction : Int
}

///|
fn av1_cdef_offset(direction : Int, distance : Int) -> (Int, Int) {
  match direction {
    0 => (distance, -distance)
    1 => (distance, -(distance / 2))
    2 => (distance, 0)
    3 => (distance, distance / 2)
    4 => (distance, distance)
    5 => (distance / 2, distance)
    6 => (0, distance)
    _ => (-(distance / 2), distance)
  }
}

///|
fn av1_cdef_floor_log2(value : Int) -> Int {
  let mut n = value
  let mut log = 0
  while n > 1 {
    n = n >> 1
    log += 1
  }
  log
}

///|
fn av1_cdef_constrain(diff : Int, threshold : Int, damping : Int) -> Int {
  if threshold == 0 {
    return 0
  }
  let magnitude = if diff < 0 { -diff } else { diff }
  let shift = damping - av1_cdef_floor_log2(threshold)
  let limit = threshold - (magnitude >> (if shift > 0 { shift } else { 0 }))
  let clipped = if limit < 0 {
    0
  } else if magnitude < limit {
    magnitude
  } else {
    limit
  }
  if diff < 0 {
    -clipped
  } else {
    clipped
  }
}

///|
/// Filter from the source snapshot. Taps beyond the frame are unavailable;
/// valid taps across block boundaries still read the unfiltered source.
fn av1_cdef_filter_blocks(
  width : Int,
  height : Int,
  plane : Array[Int],
  params : Array[Av1CdefParams],
  bit_depth : Int,
  block_size : Int,
  damping_offset : Int,
) -> Array[Int]? {
  if width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    plane.length() != width * height {
    return None
  }
  if bit_depth != 8 && bit_depth != 10 && bit_depth != 12 {
    return None
  }
  let blocks_x = (width + block_size - 1) / block_size
  let blocks_y = (height + block_size - 1) / block_size
  if params.length() != blocks_x * blocks_y {
    return None
  }
  for p in params {
    if p.primary_strength < 0 ||
      p.primary_strength > 15 ||
      !(p.secondary_strength == 0 ||
      p.secondary_strength == 1 ||
      p.secondary_strength == 2 ||
      p.secondary_strength == 4) ||
      p.damping < 3 ||
      p.damping > 6 ||
      p.direction < 0 ||
      p.direction > 7 {
      return None
    }
  }
  let max_value = (1 << bit_depth) - 1
  for value in plane {
    if value < 0 || value > max_value {
      return None
    }
  }
  let shift = bit_depth - 8
  let native : Array[Av1CdefNativeParams] = []
  for p in params {
    native.push({
      primary_strength: p.primary_strength << shift,
      secondary_strength: p.secondary_strength << shift,
      damping: p.damping + shift + damping_offset,
      direction: p.direction,
    })
  }
  Some(
    av1_cdef_filter_native_blocks(
      width, height, plane, native, bit_depth, block_size,
    ),
  )
}

///|
/// Internal kernel; callers validate geometry, samples and parameter counts.
/// All taps read the immutable source plane, including across 64x64 regions.
fn av1_cdef_filter_native_blocks(
  width : Int,
  height : Int,
  plane : Array[Int],
  params : Array[Av1CdefNativeParams],
  bit_depth : Int,
  block_size : Int,
) -> Array[Int] {
  let blocks_x = (width + block_size - 1) / block_size
  let out = plane.copy()
  let shift = bit_depth - 8
  for y in 0..<height {
    for x in 0..<width {
      let p = params[y / block_size * blocks_x + x / block_size]
      let pri = p.primary_strength
      let sec = p.secondary_strength
      if pri == 0 && sec == 0 {
        continue
      }
      let damping = p.damping
      let center = plane[y * width + x]
      let mut sum = 0
      let mut minimum = center
      let mut maximum = center
      for distance in 1..<3 {
        for branch in 0..<3 {
          let direction = if branch == 0 {
            p.direction
          } else if branch == 1 {
            (p.direction + 2) & 7
          } else {
            (p.direction + 6) & 7
          }
          let (dx, dy) = av1_cdef_offset(direction, distance)
          let strength = if branch == 0 { pri } else { sec }
          let weight = if branch == 0 {
            if ((p.primary_strength >> shift) & 1) != 0 {
              3
            } else if distance == 1 {
              4
            } else {
              2
            }
          } else if distance == 1 {
            2
          } else {
            1
          }
          for sign_index in 0..<2 {
            let sign = if sign_index == 0 { -1 } else { 1 }
            let sx = x + sign * dx
            let sy = y + sign * dy
            if sx < 0 || sx >= width || sy < 0 || sy >= height {
              continue
            }
            let sample = plane[sy * width + sx]
            if sample < minimum {
              minimum = sample
            }
            if sample > maximum {
              maximum = sample
            }
            sum += weight *
              av1_cdef_constrain(sample - center, strength, damping)
          }
        }
      }
      let filtered = center + ((8 + sum - (if sum < 0 { 1 } else { 0 })) >> 4)
      out[y * width + x] = if filtered < minimum {
        minimum
      } else if filtered > maximum {
        maximum
      } else {
        filtered
      }
    }
  }
  out
}

///|
/// Apply CDEF to a plane using one parameter record per 8x8 block.
/// Frame-edge taps are excluded and the input plane remains unchanged.
pub fn av1_cdef_filter_plane(
  width : Int,
  height : Int,
  plane : Array[Int],
  params : Array[Av1CdefParams],
  bit_depth? : Int = 8,
) -> Array[Int]? {
  av1_cdef_filter_blocks(width, height, plane, params, bit_depth, 8, 0)
}

///|
/// Filter 4:2:0 planes. Both parameter arrays follow the luma 8x8 grid;
/// each UV record controls the corresponding chroma 4x4 block.
/// Chroma uses the normative damping decrement of one.
pub fn av1_cdef_filter_yuv420(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  y_params : Array[Av1CdefParams],
  uv_params : Array[Av1CdefParams],
  bit_depth? : Int = 8,
) -> (Array[Int], Array[Int], Array[Int])? {
  if width <= 0 || height <= 0 || width > MAX_IMAGE_PIXELS / height {
    return None
  }
  let cw = (width + 1) / 2
  let ch = (height + 1) / 2
  let yf = match
    av1_cdef_filter_blocks(width, height, y, y_params, bit_depth, 8, 0) {
    Some(value) => value
    None => return None
  }
  let uf = match
    av1_cdef_filter_blocks(cw, ch, u, uv_params, bit_depth, 4, -1) {
    Some(value) => value
    None => return None
  }
  let vf = match
    av1_cdef_filter_blocks(cw, ch, v, uv_params, bit_depth, 4, -1) {
    Some(value) => value
    None => return None
  }
  Some((yf, uf, vf))
}
