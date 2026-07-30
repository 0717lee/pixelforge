///|
/// Distance transform: for every foreground pixel (luma > threshold), the
/// approximate Euclidean distance to the nearest background pixel. Uses the
/// two-pass chamfer algorithm with (3, 4) weights — 3 for orthogonal steps,
/// 4 for diagonal — which approximates true distance scaled by 3 in integer
/// arithmetic. The result is normalized to a 0..255 grayscale image where
/// brighter means deeper inside the shape.

///|
/// Computes the raw chamfer (3,4) distance map (in thirds of a pixel) from
/// each foreground pixel to the nearest background. Background pixels are 0.
fn Image::chamfer_map(self : Image, threshold : Int) -> Array[Int] {
  let w = self.width
  let h = self.height
  let n = w * h
  // A large sentinel that any real path stays below.
  let inf = 1 << 28
  let dist : Array[Int] = Array::make(n, 0)
  for p in 0..<n {
    let base = p * 4
    let y = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
    dist[p] = if y > threshold { inf } else { 0 }
  }
  // Forward pass: top-left to bottom-right, looking at already-processed
  // neighbors (W, NW, N, NE).
  for y in 0..<h {
    for x in 0..<w {
      let p = y * w + x
      if dist[p] == 0 {
        continue
      }
      let mut best = dist[p]
      if x > 0 && dist[p - 1] + 3 < best {
        best = dist[p - 1] + 3
      }
      if x > 0 && y > 0 && dist[p - w - 1] + 4 < best {
        best = dist[p - w - 1] + 4
      }
      if y > 0 && dist[p - w] + 3 < best {
        best = dist[p - w] + 3
      }
      if x + 1 < w && y > 0 && dist[p - w + 1] + 4 < best {
        best = dist[p - w + 1] + 4
      }
      dist[p] = best
    }
  }
  // Backward pass: bottom-right to top-left, looking at the other four
  // neighbors (E, SE, S, SW).
  for y = h - 1; y >= 0; y = y - 1 {
    for x = w - 1; x >= 0; x = x - 1 {
      let p = y * w + x
      if dist[p] == 0 {
        continue
      }
      let mut best = dist[p]
      if x + 1 < w && dist[p + 1] + 3 < best {
        best = dist[p + 1] + 3
      }
      if x + 1 < w && y + 1 < h && dist[p + w + 1] + 4 < best {
        best = dist[p + w + 1] + 4
      }
      if y + 1 < h && dist[p + w] + 3 < best {
        best = dist[p + w] + 3
      }
      if x > 0 && y + 1 < h && dist[p + w - 1] + 4 < best {
        best = dist[p + w - 1] + 4
      }
      dist[p] = best
    }
  }
  dist
}

///|
/// Distance transform normalized to a grayscale image: background stays
/// black, and foreground brightness grows with distance from the edge,
/// scaled so the deepest pixel maps to 255. Alpha is preserved.
pub fn Image::distance_transform(self : Image, threshold : Int) -> Image {
  let w = self.width
  let h = self.height
  let dist = self.chamfer_map(threshold)
  let mut max = 0
  for d in dist {
    if d < 1 << 28 && d > max {
      max = d
    }
  }
  let out = Image::new(w, h)
  for p in 0..<(w * h) {
    let base = p * 4
    let v = if max == 0 { 0 } else { dist[p] * 255 / max }
    let g = clamp_byte(v)
    out.data[base] = g
    out.data[base + 1] = g
    out.data[base + 2] = g
    out.data[base + 3] = self.data[base + 3]
  }
  out
}
