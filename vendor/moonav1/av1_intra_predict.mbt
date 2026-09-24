/// Pure 8-bit AV1 intra prediction (§7.11.2).
///
/// References are supplied explicitly so block traversal can decide frame
/// availability. `above` and `left` contain at least width/height samples when
/// available; unavailable edges may be empty. Output is a row-major block.

///|
pub const AV1_INTRA_DC : Int = 0

///|
pub const AV1_INTRA_V : Int = 1

///|
pub const AV1_INTRA_H : Int = 2

///|
pub const AV1_INTRA_SMOOTH : Int = 9

///|
pub const AV1_INTRA_SMOOTH_V : Int = 10

///|
pub const AV1_INTRA_SMOOTH_H : Int = 11

///|
pub const AV1_INTRA_PAETH : Int = 12

///|
fn av1_intra_log2(size : Int) -> Int? {
  if size == 4 {
    Some(2)
  } else if size == 8 {
    Some(3)
  } else if size == 16 {
    Some(4)
  } else if size == 32 {
    Some(5)
  } else if size == 64 {
    Some(6)
  } else {
    None
  }
}

///|
fn av1_intra_clip(value : Int, bit_depth : Int) -> Int {
  let hi = (1 << bit_depth) - 1
  if value < 0 {
    0
  } else if value > hi {
    hi
  } else {
    value
  }
}

///|
fn av1_intra_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn av1_intra_round2(value : Int64, shift : Int) -> Int {
  ((value + (1L << (shift - 1))) >> shift).to_int()
}

///|
fn av1_smooth_weights(log2 : Int) -> Array[Int] {
  if log2 == 2 {
    [255, 149, 85, 64]
  } else if log2 == 3 {
    [255, 197, 146, 105, 73, 50, 37, 32]
  } else if log2 == 4 {
    [255, 225, 196, 170, 145, 123, 102, 84, 68, 54, 43, 33, 26, 20, 17, 16]
  } else if log2 == 5 {
    [
      255, 240, 225, 210, 196, 182, 169, 157, 145, 133, 122, 111, 101, 92, 83, 74,
      66, 59, 52, 45, 39, 34, 29, 25, 21, 17, 14, 12, 10, 9, 8, 8,
    ]
  } else {
    [
      255, 248, 240, 233, 225, 218, 210, 203, 196, 189, 182, 176, 169, 163, 156,
      150, 144, 138, 133, 127, 121, 116, 111, 106, 101, 96, 91, 86, 82, 77, 73, 69,
      65, 61, 57, 54, 50, 47, 44, 41, 38, 35, 32, 29, 27, 25, 22, 20, 18, 16, 15,
      13, 12, 10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 4,
    ]
  }
}

///|
fn av1_intra_edges(
  above : Array[Int],
  left : Array[Int],
  top_left : Int,
  width : Int,
  height : Int,
  have_above : Bool,
  have_left : Bool,
  bit_depth : Int,
) -> (Array[Int], Array[Int], Int)? {
  if have_above && above.length() < width {
    return None
  }
  if have_left && left.length() < height {
    return None
  }
  let base = 1 << (bit_depth - 1)
  let above_out : Array[Int] = Array::make(width, 0)
  let left_out : Array[Int] = Array::make(height, 0)
  if have_above {
    for j in 0..<width {
      above_out[j] = av1_intra_clip(above[j], bit_depth)
    }
  } else if have_left {
    let fill = av1_intra_clip(left[0], bit_depth)
    for j in 0..<width {
      above_out[j] = fill
    }
  } else {
    for j in 0..<width {
      above_out[j] = base - 1
    }
  }
  if have_left {
    for i in 0..<height {
      left_out[i] = av1_intra_clip(left[i], bit_depth)
    }
  } else if have_above {
    let fill = av1_intra_clip(above[0], bit_depth)
    for i in 0..<height {
      left_out[i] = fill
    }
  } else {
    for i in 0..<height {
      left_out[i] = base + 1
    }
  }
  let tl = if have_above && have_left {
    av1_intra_clip(top_left, bit_depth)
  } else if have_above {
    above_out[0]
  } else if have_left {
    left_out[0]
  } else {
    base
  }
  Some((above_out, left_out, tl))
}

///|
/// Produce one AV1 intra-predicted block. Modes implemented are DC, V, H,
/// PAETH, SMOOTH, SMOOTH_V and SMOOTH_H. Width and height must be powers of two
/// from 4 through 64. Samples are clipped to `bit_depth` (8..12).
pub fn av1_intra_predict(
  mode : Int,
  width : Int,
  height : Int,
  above : Array[Int],
  left : Array[Int],
  top_left : Int,
  bit_depth : Int,
  have_above? : Bool = true,
  have_left? : Bool = true,
) -> Array[Int]? {
  let logw = match av1_intra_log2(width) {
    Some(v) => v
    None => return None
  }
  let logh = match av1_intra_log2(height) {
    Some(v) => v
    None => return None
  }
  if bit_depth < 8 || bit_depth > 12 {
    return None
  }
  let (a, l, tl) = match
    av1_intra_edges(
      above, left, top_left, width, height, have_above, have_left, bit_depth,
    ) {
    Some(v) => v
    None => return None
  }
  let out : Array[Int] = Array::make(width * height, 0)
  if mode == AV1_INTRA_DC {
    let mut sum = 0
    if have_above {
      for j in 0..<width {
        sum = sum + a[j]
      }
    }
    if have_left {
      for i in 0..<height {
        sum = sum + l[i]
      }
    }
    let dc = if have_above && have_left {
      (sum + ((width + height) >> 1)) / (width + height)
    } else if have_above {
      av1_intra_clip((sum + (width >> 1)) >> logw, bit_depth)
    } else if have_left {
      av1_intra_clip((sum + (height >> 1)) >> logh, bit_depth)
    } else {
      1 << (bit_depth - 1)
    }
    for i in 0..<out.length() {
      out[i] = dc
    }
    return Some(out)
  }
  if mode == AV1_INTRA_V {
    for i in 0..<height {
      for j in 0..<width {
        out[i * width + j] = a[j]
      }
    }
    return Some(out)
  }
  if mode == AV1_INTRA_H {
    for i in 0..<height {
      for j in 0..<width {
        out[i * width + j] = l[i]
      }
    }
    return Some(out)
  }
  if mode == AV1_INTRA_PAETH {
    for i in 0..<height {
      for j in 0..<width {
        let base = a[j] + l[i] - tl
        let pl = av1_intra_abs(base - l[i])
        let pt = av1_intra_abs(base - a[j])
        let ptl = av1_intra_abs(base - tl)
        out[i * width + j] = if pl <= pt && pl <= ptl {
          l[i]
        } else if pt <= ptl {
          a[j]
        } else {
          tl
        }
      }
    }
    return Some(out)
  }
  if mode == AV1_INTRA_SMOOTH ||
    mode == AV1_INTRA_SMOOTH_V ||
    mode == AV1_INTRA_SMOOTH_H {
    let wx = av1_smooth_weights(logw)
    let wy = av1_smooth_weights(logh)
    for i in 0..<height {
      for j in 0..<width {
        let value : Int64 = if mode == AV1_INTRA_SMOOTH {
          wy[i].to_int64() * a[j].to_int64() +
          (256 - wy[i]).to_int64() * l[height - 1].to_int64() +
          wx[j].to_int64() * l[i].to_int64() +
          (256 - wx[j]).to_int64() * a[width - 1].to_int64()
        } else if mode == AV1_INTRA_SMOOTH_V {
          wy[i].to_int64() * a[j].to_int64() +
          (256 - wy[i]).to_int64() * l[height - 1].to_int64()
        } else {
          wx[j].to_int64() * l[i].to_int64() +
          (256 - wx[j]).to_int64() * a[width - 1].to_int64()
        }
        out[i * width + j] = av1_intra_round2(
          value,
          if mode == AV1_INTRA_SMOOTH {
            9
          } else {
            8
          },
        )
      }
    }
    return Some(out)
  }
  None
}
