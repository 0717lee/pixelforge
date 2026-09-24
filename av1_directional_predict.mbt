/// Pure directional intra prediction. Availability is resolved by the caller:
/// top/right and bottom/left counts describe legal reconstructed references,
/// not merely samples present in a frame buffer. The private edge arrays keep
/// two leading entries for the negative indices used after upsampling.

///|
fn av1_directional_derivative(angle : Int) -> Int {
  match angle {
    3 => 1023
    6 => 547
    9 => 372
    14 => 273
    17 => 215
    20 => 178
    23 => 151
    26 => 132
    29 => 116
    32 => 102
    36 => 90
    39 => 80
    42 => 71
    45 => 64
    48 => 57
    51 => 51
    54 => 45
    58 => 40
    61 => 35
    64 => 31
    67 => 27
    70 => 23
    73 => 19
    76 => 15
    81 => 11
    84 => 7
    87 => 3
    _ => 0
  }
}

///|
fn av1_directional_filter_strength(
  width : Int,
  height : Int,
  delta : Int,
  neighbor_smooth : Bool,
) -> Int {
  let d = av1_intra_abs(delta)
  let sum = width + height
  if !neighbor_smooth {
    if sum <= 8 {
      if d >= 56 {
        1
      } else {
        0
      }
    } else if sum <= 16 {
      if d >= 40 {
        1
      } else {
        0
      }
    } else if sum <= 24 {
      if d >= 32 {
        3
      } else if d >= 16 {
        2
      } else if d >= 8 {
        1
      } else {
        0
      }
    } else if sum <= 32 {
      if d >= 32 {
        3
      } else if d >= 4 {
        2
      } else if d >= 1 {
        1
      } else {
        0
      }
    } else if d >= 1 {
      3
    } else {
      0
    }
  } else if sum <= 8 {
    if d >= 64 {
      2
    } else if d >= 40 {
      1
    } else {
      0
    }
  } else if sum <= 16 {
    if d >= 48 {
      2
    } else if d >= 20 {
      1
    } else {
      0
    }
  } else if sum <= 24 {
    if d >= 4 {
      3
    } else {
      0
    }
  } else if d >= 1 {
    3
  } else {
    0
  }
}

///|
/// `length` starts at the corner (edge[1]); the first sample is unchanged.
fn av1_directional_filter_edge(
  edge : Array[Int],
  length : Int,
  strength : Int,
) -> Unit {
  if strength == 0 {
    return
  }
  let taps = if strength == 1 {
    [0, 4, 8, 4, 0]
  } else if strength == 2 {
    [0, 5, 6, 5, 0]
  } else {
    [2, 4, 4, 4, 2]
  }
  let original = edge.copy()
  for i in 1..<length {
    let mut sum = 0
    for j in 0..<5 {
      let index = i - 2 + j
      let index = if index < 0 {
        0
      } else if index >= length {
        length - 1
      } else {
        index
      }
      sum = sum + original[index + 1] * taps[j]
    }
    edge[i + 1] = (sum + 8) >> 4
  }
}

///|
fn av1_directional_upsample_edge(
  edge : Array[Int],
  length : Int,
  bit_depth : Int,
) -> Unit {
  let original = Array::make(length + 3, 0)
  original[0] = edge[1]
  original[1] = edge[1]
  for i in 0..<length {
    original[i + 2] = edge[i + 2]
  }
  original[length + 2] = edge[length + 1]
  edge[0] = original[0]
  for i in 0..<length {
    let sum = -original[i] +
      9 * original[i + 1] +
      9 * original[i + 2] -
      original[i + 3]
    edge[2 * i + 1] = av1_intra_clip((sum + 8) >> 4, bit_depth)
    edge[2 * i + 2] = original[i + 2]
  }
}

///|
fn av1_directional_use_upsample(
  width : Int,
  height : Int,
  delta : Int,
  neighbor_smooth : Bool,
) -> Bool {
  let d = av1_intra_abs(delta)
  d > 0 && d < 40 && width + height <= (if neighbor_smooth { 8 } else { 16 })
}

///|
/// Modes 1..8 use base angles 90,180,45,135,113,157,203,67. Angle delta is
/// the decoded symbol minus three, not an angle in degrees. `n_topright` and
/// `n_bottomleft` are -1 when that extension is not needed, zero when needed
/// but unavailable, and otherwise the available sample count. The caller
/// decides whether angle-delta syntax exists for the containing coding block.
fn av1_directional_predict(
  mode : Int,
  angle_delta : Int,
  width : Int,
  height : Int,
  above : Array[Int],
  left : Array[Int],
  top_left : Int,
  bit_depth : Int,
  n_top : Int,
  n_left : Int,
  n_topright : Int,
  n_bottomleft : Int,
  enable_intra_edge_filter : Bool,
  neighbor_smooth : Bool,
) -> Array[Int]? {
  if mode < 1 ||
    mode > 8 ||
    angle_delta < -3 ||
    angle_delta > 3 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    av1_intra_log2(width) is None ||
    av1_intra_log2(height) is None ||
    (width != height && !av1_tx_rect_supported(width, height)) {
    return None
  }
  let base_angles = [90, 180, 45, 135, 113, 157, 203, 67]
  let angle = base_angles[mode - 1] + 3 * angle_delta
  let need_right = angle < 90
  let need_bottom = angle > 180
  if n_top < 0 ||
    n_top > width ||
    n_left < 0 ||
    n_left > height ||
    n_topright < -1 ||
    n_topright > width ||
    n_bottomleft < -1 ||
    n_bottomleft > height ||
    need_right != (n_topright >= 0) ||
    need_bottom != (n_bottomleft >= 0) ||
    above.length() < n_top ||
    left.length() < n_left ||
    (n_topright > 0 && (n_top != width || above.length() < width + n_topright)) ||
    (
      n_bottomleft > 0 &&
      (n_left != height || left.length() < height + n_bottomleft)
    ) {
    return None
  }
  let maximum = (1 << bit_depth) - 1
  if top_left < 0 || top_left > maximum {
    return None
  }
  for sample in above {
    if sample < 0 || sample > maximum {
      return None
    }
  }
  for sample in left {
    if sample < 0 || sample > maximum {
      return None
    }
  }
  let base = 1 << (bit_depth - 1)
  let need_above = angle < 180
  let need_left = angle > 90
  if (!need_above && n_left == 0) || (!need_left && n_top == 0) {
    let value = if need_left {
      if n_top > 0 {
        above[0]
      } else {
        base + 1
      }
    } else if n_left > 0 {
      left[0]
    } else {
      base - 1
    }
    return Some(Array::make(width * height, value))
  }
  let edge_size = 2 * (width + height) + 4
  let a = Array::make(edge_size, base - 1)
  let l = Array::make(edge_size, base + 1)
  if need_left {
    let needed = height + (if n_bottomleft >= 0 { width } else { 0 })
    if n_left > 0 {
      for i in 0..<n_left {
        l[i + 2] = left[i]
      }
      let copied = if n_bottomleft > 0 {
        for i in 0..<n_bottomleft {
          l[height + i + 2] = left[height + i]
        }
        height + n_bottomleft
      } else {
        n_left
      }
      for i in copied..<needed {
        l[i + 2] = l[copied + 1]
      }
    } else if n_top > 0 {
      for i in 0..<needed {
        l[i + 2] = above[0]
      }
    }
  }
  if need_above {
    let needed = width + (if n_topright >= 0 { height } else { 0 })
    if n_top > 0 {
      for i in 0..<n_top {
        a[i + 2] = above[i]
      }
      let copied = if n_topright > 0 {
        for i in 0..<n_topright {
          a[width + i + 2] = above[width + i]
        }
        width + n_topright
      } else {
        n_top
      }
      for i in copied..<needed {
        a[i + 2] = a[copied + 1]
      }
    } else if n_left > 0 {
      for i in 0..<needed {
        a[i + 2] = left[0]
      }
    }
  }
  let corner = if n_top > 0 && n_left > 0 {
    top_left
  } else if n_top > 0 {
    above[0]
  } else if n_left > 0 {
    left[0]
  } else {
    base
  }
  a[1] = corner
  l[1] = corner
  let mut up_above = 0
  let mut up_left = 0
  if enable_intra_edge_filter {
    if angle != 90 && angle != 180 {
      if need_above && need_left && width + height >= 24 {
        let filtered_corner = (5 * l[2] + 6 * a[1] + 5 * a[2] + 8) >> 4
        a[1] = filtered_corner
        l[1] = filtered_corner
      }
      if need_above && n_top > 0 {
        av1_directional_filter_edge(
          a,
          n_top + 1 + (if need_right { height } else { 0 }),
          av1_directional_filter_strength(
            width,
            height,
            angle - 90,
            neighbor_smooth,
          ),
        )
      }
      if need_left && n_left > 0 {
        av1_directional_filter_edge(
          l,
          n_left + 1 + (if need_bottom { width } else { 0 }),
          av1_directional_filter_strength(
            height,
            width,
            angle - 180,
            neighbor_smooth,
          ),
        )
      }
    }
    if need_above &&
      av1_directional_use_upsample(width, height, angle - 90, neighbor_smooth) {
      av1_directional_upsample_edge(
        a,
        width + (if need_right { height } else { 0 }),
        bit_depth,
      )
      up_above = 1
    }
    if need_left &&
      av1_directional_use_upsample(width, height, angle - 180, neighbor_smooth) {
      av1_directional_upsample_edge(
        l,
        height + (if need_bottom { width } else { 0 }),
        bit_depth,
      )
      up_left = 1
    }
  }
  let out = Array::make(width * height, 0)
  if angle == 90 {
    for row in 0..<height {
      for col in 0..<width {
        out[row * width + col] = a[col + 2]
      }
    }
    return Some(out)
  }
  if angle == 180 {
    for row in 0..<height {
      for col in 0..<width {
        out[row * width + col] = l[row + 2]
      }
    }
    return Some(out)
  }
  let dx = if angle < 90 {
    av1_directional_derivative(angle)
  } else if angle < 180 {
    av1_directional_derivative(180 - angle)
  } else {
    1
  }
  let dy = if angle < 90 {
    1
  } else if angle < 180 {
    av1_directional_derivative(angle - 90)
  } else {
    av1_directional_derivative(270 - angle)
  }
  if dx <= 0 || dy <= 0 {
    return None
  }
  for row in 0..<height {
    for col in 0..<width {
      let value = if angle < 90 {
        let x = (row + 1) * dx
        let index = (x >> (6 - up_above)) + (col << up_above)
        let maximum_index = (width + height - 1) << up_above
        if index >= maximum_index {
          a[maximum_index + 2]
        } else {
          let shift = ((x << up_above) & 63) >> 1
          (a[index + 2] * (32 - shift) + a[index + 3] * shift + 16) >> 5
        }
      } else if angle > 180 {
        let y = (col + 1) * dy
        let index = (y >> (6 - up_left)) + (row << up_left)
        let maximum_index = (width + height - 1) << up_left
        if index >= maximum_index {
          l[maximum_index + 2]
        } else {
          let shift = ((y << up_left) & 63) >> 1
          (l[index + 2] * (32 - shift) + l[index + 3] * shift + 16) >> 5
        }
      } else {
        let x = (col << 6) - (row + 1) * dx
        let index = x >> (6 - up_above)
        if index >= -(1 << up_above) {
          let shift = ((x * (1 << up_above)) & 63) >> 1
          (a[index + 2] * (32 - shift) + a[index + 3] * shift + 16) >> 5
        } else {
          let y = (row << 6) - (col + 1) * dy
          let index = y >> (6 - up_left)
          let shift = ((y * (1 << up_left)) & 63) >> 1
          (l[index + 2] * (32 - shift) + l[index + 3] * shift + 16) >> 5
        }
      }
      out[row * width + col] = value
    }
  }
  Some(out)
}
