/// AV1 filter-intra prediction (section 7.11.2.3). The seven coefficients
/// generate each of eight outputs in a 4x2 group. The eighth table entry in
/// libaom is alignment padding and is not part of the prediction equation.

///|
let av1_filter_intra_taps : Array[Array[Array[Int]]] = [
  [
    [-6, 10, 0, 0, 0, 12, 0],
    [-5, 2, 10, 0, 0, 9, 0],
    [-3, 1, 1, 10, 0, 7, 0],
    [-3, 1, 1, 2, 10, 5, 0],
    [-4, 6, 0, 0, 0, 2, 12],
    [-3, 2, 6, 0, 0, 2, 9],
    [-3, 2, 2, 6, 0, 2, 7],
    [-3, 1, 2, 2, 6, 3, 5],
  ],
  [
    [-10, 16, 0, 0, 0, 10, 0],
    [-6, 0, 16, 0, 0, 6, 0],
    [-4, 0, 0, 16, 0, 4, 0],
    [-2, 0, 0, 0, 16, 2, 0],
    [-10, 16, 0, 0, 0, 0, 10],
    [-6, 0, 16, 0, 0, 0, 6],
    [-4, 0, 0, 16, 0, 0, 4],
    [-2, 0, 0, 0, 16, 0, 2],
  ],
  [
    [-8, 8, 0, 0, 0, 16, 0],
    [-8, 0, 8, 0, 0, 16, 0],
    [-8, 0, 0, 8, 0, 16, 0],
    [-8, 0, 0, 0, 8, 16, 0],
    [-4, 4, 0, 0, 0, 0, 16],
    [-4, 0, 4, 0, 0, 0, 16],
    [-4, 0, 0, 4, 0, 0, 16],
    [-4, 0, 0, 0, 4, 0, 16],
  ],
  [
    [-2, 8, 0, 0, 0, 10, 0],
    [-1, 3, 8, 0, 0, 6, 0],
    [-1, 2, 3, 8, 0, 4, 0],
    [0, 1, 2, 3, 8, 2, 0],
    [-1, 4, 0, 0, 0, 3, 10],
    [-1, 3, 4, 0, 0, 4, 6],
    [-1, 2, 3, 4, 0, 4, 4],
    [-1, 2, 2, 3, 4, 3, 3],
  ],
  [
    [-12, 14, 0, 0, 0, 14, 0],
    [-10, 0, 14, 0, 0, 12, 0],
    [-9, 0, 0, 14, 0, 11, 0],
    [-8, 0, 0, 0, 14, 10, 0],
    [-10, 12, 0, 0, 0, 0, 14],
    [-9, 1, 12, 0, 0, 0, 12],
    [-8, 0, 0, 12, 0, 1, 11],
    [-7, 0, 0, 1, 12, 1, 9],
  ],
]

///|
/// Modes 0..4 are FILTER_DC, FILTER_V, FILTER_H, FILTER_D157 and FILTER_PAETH.
/// Counts specify the available prefixes of each reference edge. Missing
/// samples extend the last available sample, or use the opposite edge's first
/// sample. With both edges absent the native-depth defaults are mid-1 above,
/// mid+1 left and mid at the corner. No directional edge filtering is applied.
fn av1_filter_intra_predict(
  mode : Int,
  width : Int,
  height : Int,
  above : Array[Int],
  left : Array[Int],
  top_left : Int,
  bit_depth : Int,
  n_top : Int,
  n_left : Int,
) -> Array[Int]? {
  if mode < 0 ||
    mode >= 5 ||
    width > 32 ||
    height > 32 ||
    av1_intra_log2(width) is None ||
    av1_intra_log2(height) is None ||
    (width != height && !av1_tx_rect_supported(width, height)) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    n_top < 0 ||
    n_top > width ||
    n_left < 0 ||
    n_left > height ||
    above.length() < n_top ||
    left.length() < n_left {
    return None
  }
  let maximum = (1 << bit_depth) - 1
  if top_left < 0 || top_left > maximum {
    return None
  }
  for value in above {
    if value < 0 || value > maximum {
      return None
    }
  }
  for value in left {
    if value < 0 || value > maximum {
      return None
    }
  }
  let mid = 1 << (bit_depth - 1)
  let stride = width + 1
  let buffer = Array::make(stride * (height + 1), 0)
  buffer[0] = if n_top > 0 && n_left > 0 {
    top_left
  } else if n_top > 0 {
    above[0]
  } else if n_left > 0 {
    left[0]
  } else {
    mid
  }
  for col in 0..<width {
    buffer[col + 1] = if n_top > 0 {
      above[if col < n_top { col } else { n_top - 1 }]
    } else if n_left > 0 {
      left[0]
    } else {
      mid - 1
    }
  }
  for row in 0..<height {
    buffer[(row + 1) * stride] = if n_left > 0 {
      left[if row < n_left { row } else { n_left - 1 }]
    } else if n_top > 0 {
      above[0]
    } else {
      mid + 1
    }
  }
  let taps = av1_filter_intra_taps[mode]
  let mut row = 1
  while row <= height {
    let mut col = 1
    while col <= width {
      // Freeze all seven inputs before writing any output from this group.
      // The next group consumes these newly generated, already clipped pixels.
      let p0 = buffer[(row - 1) * stride + col - 1]
      let p1 = buffer[(row - 1) * stride + col]
      let p2 = buffer[(row - 1) * stride + col + 1]
      let p3 = buffer[(row - 1) * stride + col + 2]
      let p4 = buffer[(row - 1) * stride + col + 3]
      let p5 = buffer[row * stride + col - 1]
      let p6 = buffer[(row + 1) * stride + col - 1]
      for k in 0..<8 {
        let tap = taps[k]
        let value = tap[0] * p0 +
          tap[1] * p1 +
          tap[2] * p2 +
          tap[3] * p3 +
          tap[4] * p4 +
          tap[5] * p5 +
          tap[6] * p6
        // Negative signed-round differences disappear under the required clip.
        buffer[(row + (k >> 2)) * stride + col + (k & 3)] = av1_intra_clip(
          (value + 8) >> 4,
          bit_depth,
        )
      }
      col = col + 4
    }
    row = row + 2
  }
  let output = Array::make(width * height, 0)
  for row in 0..<height {
    for col in 0..<width {
      output[row * width + col] = buffer[(row + 1) * stride + col + 1]
    }
  }
  Some(output)
}
