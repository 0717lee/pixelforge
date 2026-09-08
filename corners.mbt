///| 
/// Harris corner response and non-maximum suppression.
///
/// The detector uses Sobel gradients of Rec.601 luma, a 3x3 structure tensor,
/// and the classic Harris score `det(M) - 0.04 * trace(M)^2`. Responses are
/// evaluated only where a complete neighbourhood exists. A candidate must be
/// strictly greater than `threshold` and be a local maximum in its 3x3
/// neighbourhood. Results are ordered by descending response; ties are stable
/// in row-major order. `max_corners <= 0` returns an empty array.

///| 
/// One detected Harris corner. Coordinates use integer pixel positions.
pub(all) struct Corner {
  x : Int
  y : Int
  response : Double
}

///| Internal luma accessor that avoids allocating a temporary grayscale image.
fn corner_luma(image : Image, x : Int, y : Int) -> Int {
  let i = (y * image.width + x) * 4
  (299 * image.data[i].to_int() + 587 * image.data[i + 1].to_int() +
    114 * image.data[i + 2].to_int()) /
    1000
}

///| Sobel x/y gradients for one interior pixel.
fn corner_gradient(image : Image, x : Int, y : Int) -> (Int, Int) {
  // Expand the fixed Sobel stencil arithmetically so the hot loop allocates
  // no kernel arrays. The names follow rows a..i from top-left to bottom-right.
  let a = corner_luma(image, x - 1, y - 1)
  let b = corner_luma(image, x, y - 1)
  let c = corner_luma(image, x + 1, y - 1)
  let d = corner_luma(image, x - 1, y)
  let f = corner_luma(image, x + 1, y)
  let g = corner_luma(image, x - 1, y + 1)
  let h = corner_luma(image, x, y + 1)
  let i = corner_luma(image, x + 1, y + 1)
  (-a + c - 2 * d + 2 * f - g + i,
    -a - 2 * b - c + g + 2 * h + i)
}

///| 
/// Detects Harris corners using `threshold` as the minimum raw response and
/// returns at most `max_corners` strongest local maxima.
pub fn Image::harris_corners(
  self : Image,
  threshold : Double,
  max_corners : Int,
) -> Array[Corner] {
  let w = self.width
  let h = self.height
  let n = w * h
  if max_corners <= 0 || w < 3 || h < 3 {
    return []
  }
  // Keep gradient fields so the tensor pass does not recompute Sobel windows.
  let gx : Array[Int] = Array::make(n, 0)
  let gy : Array[Int] = Array::make(n, 0)
  for y in 1..<(h - 1) {
    for x in 1..<(w - 1) {
      let (dx, dy) = corner_gradient(self, x, y)
      let p = y * w + x
      gx[p] = dx
      gy[p] = dy
    }
  }
  let response : Array[Double] = Array::make(n, 0.0)
  for y in 1..<(h - 1) {
    for x in 1..<(w - 1) {
      let mut xx = 0L
      let mut xy = 0L
      let mut yy = 0L
      for dy in -1..<2 {
        for dx in -1..<2 {
          let p = (y + dy) * w + x + dx
          let sx = gx[p].to_int64()
          let sy = gy[p].to_int64()
          xx = xx + sx * sx
          xy = xy + sx * sy
          yy = yy + sy * sy
        }
      }
      let xx_f = xx.to_double()
      let xy_f = xy.to_double()
      let yy_f = yy.to_double()
      let trace = xx_f + yy_f
      response[y * w + x] = xx_f * yy_f - xy_f * xy_f - 0.04 * trace * trace
    }
  }
  // Collect local maxima first. A separate consumed map keeps selection
  // deterministic while avoiding a dependency on a sorting package.
  let candidates : Array[Corner] = []
  for y in 1..<(h - 1) {
    for x in 1..<(w - 1) {
      let p = y * w + x
      let score = response[p]
      if score <= threshold {
        continue
      }
      let mut maximum = true
      for dy in -1..<2 {
        for dx in -1..<2 {
          if dx == 0 && dy == 0 {
            continue
          }
          if response[(y + dy) * w + x + dx] > score {
            maximum = false
          }
        }
      }
      if maximum {
        candidates.push({ x, y, response: score })
      }
    }
  }
  let used : Array[Bool] = Array::make(candidates.length(), false)
  let result : Array[Corner] = []
  let limit = if max_corners < candidates.length() {
    max_corners
  } else {
    candidates.length()
  }
  for _ in 0..<limit {
    let mut best = -1
    for i in 0..<candidates.length() {
      if used[i] {
        continue
      }
      if best < 0 || candidates[i].response > candidates[best].response {
        best = i
      }
    }
    if best < 0 {
      break
    }
    used[best] = true
    result.push(candidates[best])
  }
  result
}
