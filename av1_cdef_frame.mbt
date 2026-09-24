/// Frame CDEF preparation follows libaom cdef_find_dir_c, adjust_strength and
/// av1_cdef_filter_fb at revision 1a4b3aef9b3e5b9251c45e9f986f41894dd45bb2.
/// Source: https://aomedia.googlesource.com/aom/+/1a4b3aef9b3e5b9251c45e9f986f41894dd45bb2/av1/common/cdef_block.c
/// Copyright (c) 2016, Alliance for Open Media. All rights reserved.
/// BSD 2 Clause License and Alliance for Open Media Patent License 1.0:
/// https://www.aomedia.org/license/software and https://www.aomedia.org/license/patent

///|
/// Direction and directional variance for a validated complete luma 8x8 block.
/// Samples normalize to eight bits before the weighted line-cost search.
fn av1_cdef_find_direction(
  plane : Array[Int],
  stride : Int,
  x : Int,
  y : Int,
  bit_depth : Int,
) -> (Int, Int) {
  let partial : Array[Array[Int]] = []
  for _ in 0..<8 {
    partial.push(Array::make(15, 0))
  }
  let cost = Array::make(8, 0)
  let div_table = [0, 840, 420, 280, 210, 168, 140, 120, 105]
  let shift = bit_depth - 8
  for i in 0..<8 {
    for j in 0..<8 {
      let value = (plane[(y + i) * stride + x + j] >> shift) - 128
      partial[0][i + j] += value
      partial[1][i + j / 2] += value
      partial[2][i] += value
      partial[3][3 + i - j / 2] += value
      partial[4][7 + i - j] += value
      partial[5][3 - i / 2 + j] += value
      partial[6][j] += value
      partial[7][i / 2 + j] += value
    }
  }
  for i in 0..<8 {
    cost[2] += partial[2][i] * partial[2][i]
    cost[6] += partial[6][i] * partial[6][i]
  }
  cost[2] *= div_table[8]
  cost[6] *= div_table[8]
  for i in 0..<7 {
    cost[0] += (
        partial[0][i] * partial[0][i] + partial[0][14 - i] * partial[0][14 - i]
      ) *
      div_table[i + 1]
    cost[4] += (
        partial[4][i] * partial[4][i] + partial[4][14 - i] * partial[4][14 - i]
      ) *
      div_table[i + 1]
  }
  cost[0] += partial[0][7] * partial[0][7] * div_table[8]
  cost[4] += partial[4][7] * partial[4][7] * div_table[8]
  for direction in [1, 3, 5, 7] {
    for j in 0..<5 {
      cost[direction] += partial[direction][3 + j] * partial[direction][3 + j]
    }
    cost[direction] *= div_table[8]
    for j in 0..<3 {
      cost[direction] += (
          partial[direction][j] * partial[direction][j] +
          partial[direction][10 - j] * partial[direction][10 - j]
        ) *
        div_table[2 * j + 2]
    }
  }
  let mut best_direction = 0
  let mut best_cost = 0
  for direction in 0..<8 {
    if cost[direction] > best_cost {
      best_direction = direction
      best_cost = cost[direction]
    }
  }
  (best_direction, (best_cost - cost[(best_direction + 4) & 7]) >> 10)
}

///|
/// The input strength has already been scaled to native bit-depth units.
fn av1_cdef_adjust_strength(strength : Int, variance : Int) -> Int {
  if variance == 0 {
    return 0
  }
  let magnitude = variance >> 6
  let log = if magnitude == 0 { 0 } else { av1_cdef_floor_log2(magnitude) }
  let adjustment = if log < 12 { log } else { 12 }
  (strength * (4 + adjustment) + 8) >> 4
}

///|
/// Filter MI-padded monochrome or 4:2:0 planes before visible-frame cropping.
/// Skip flags use the luma 4x4 grid; indices use the frame's 64x64 grid.
fn av1_cdef_filter_frame(
  width : Int,
  height : Int,
  planes : Array[Array[Int]],
  skips : Array[Int],
  indices : Array[Int],
  config : Av1CdefConfig,
  bit_depth : Int,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
) -> Array[Array[Int]]? {
  let monochrome = planes.length() == 1
  if width <= 0 ||
    height <= 0 ||
    width % 8 != 0 ||
    height % 8 != 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    (!monochrome && planes.length() != 3) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    !av1_cdef_config_valid(config, monochrome~) {
    return None
  }
  let mi_cols = width / 4
  let mi_rows = height / 4
  let region_cols = (width + 63) / 64
  let region_rows = (height + 63) / 64
  if skips.length() != mi_cols * mi_rows ||
    indices.length() != region_cols * region_rows {
    return None
  }
  for skip in skips {
    if skip != 0 && skip != 1 {
      return None
    }
  }
  for index in indices {
    if index < -1 || index >= config.y_primary.length() {
      return None
    }
  }
  let maximum = (1 << bit_depth) - 1
  for plane_index in 0..<planes.length() {
    let divisor_x = if plane_index == 0 { 1 } else { 1 << sub_x }
    let divisor_y = if plane_index == 0 { 1 } else { 1 << sub_y }
    if planes[plane_index].length() !=
      (width + divisor_x - 1) /
      divisor_x *
      ((height + divisor_y - 1) / divisor_y) {
      return None
    }
    for value in planes[plane_index] {
      if value < 0 || value > maximum {
        return None
      }
    }
  }
  let shift = bit_depth - 8
  let y_params : Array[Av1CdefNativeParams] = []
  let uv_params : Array[Av1CdefNativeParams] = []
  let disabled : Av1CdefNativeParams = {
    primary_strength: 0,
    secondary_strength: 0,
    damping: 0,
    direction: 0,
  }
  for by in 0..<(height / 8) {
    for bx in 0..<(width / 8) {
      let x = bx * 8
      let y = by * 8
      let index = indices[y / 64 * region_cols + x / 64]
      let mi = by * 2 * mi_cols + bx * 2
      let all_skip = skips[mi] == 1 &&
        skips[mi + 1] == 1 &&
        skips[mi + mi_cols] == 1 &&
        skips[mi + mi_cols + 1] == 1
      if index == -1 || all_skip {
        y_params.push(disabled)
        if !monochrome {
          uv_params.push(disabled)
        }
        continue
      }
      let (direction, variance) = av1_cdef_find_direction(
        planes[0],
        width,
        x,
        y,
        bit_depth,
      )
      let primary_y = config.y_primary[index] << shift
      y_params.push({
        primary_strength: av1_cdef_adjust_strength(primary_y, variance),
        secondary_strength: config.y_secondary[index] << shift,
        damping: config.damping + shift,
        direction: if primary_y == 0 {
          0
        } else {
          direction
        },
      })
      if !monochrome {
        let primary_uv = config.uv_primary[index] << shift
        uv_params.push({
          primary_strength: primary_uv,
          secondary_strength: config.uv_secondary[index] << shift,
          damping: config.damping + shift - 1,
          direction: if primary_uv == 0 {
            0
          } else if sub_x == 1 && sub_y == 0 {
            // CDEF maps luma directions to the horizontally subsampled
            // 4:2:2 chroma grid (dav1d cdef_apply_tmpl.c uv_dirs[1]).
            [7, 0, 2, 4, 5, 6, 6, 6][direction]
          } else {
            direction
          },
        })
      }
    }
  }
  let filtered_y = av1_cdef_filter_native_blocks(
    width,
    height,
    planes[0],
    y_params,
    bit_depth,
    8,
    8,
  )
  if monochrome {
    return Some([filtered_y])
  }
  let chroma_w = (width + (1 << sub_x) - 1) >> sub_x
  let chroma_h = (height + (1 << sub_y) - 1) >> sub_y
  let block_w = 8 >> sub_x
  let block_h = 8 >> sub_y
  Some([
    filtered_y,
    av1_cdef_filter_native_blocks(
      chroma_w,
      chroma_h,
      planes[1],
      uv_params,
      bit_depth,
      block_w,
      block_h,
    ),
    av1_cdef_filter_native_blocks(
      chroma_w,
      chroma_h,
      planes[2],
      uv_params,
      bit_depth,
      block_w,
      block_h,
    ),
  ])
}
