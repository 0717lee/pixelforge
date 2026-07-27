///|
/// Canny edge detector: the full classic pipeline — Gaussian smoothing,
/// Sobel gradients, non-maximum suppression along the quantized gradient
/// direction, then double thresholding with hysteresis edge tracking.
/// Output is a binary map (255 = edge, 0 = background).

///|
/// Runs Canny edge detection with the given hysteresis thresholds
/// (`low < high`, both compared against the L1 gradient magnitude
/// `|Gx| + |Gy|`). Pixels above `high` seed edges; pixels above `low`
/// survive only when 8-connected to a seed. Alpha is preserved.
pub fn Image::canny(self : Image, low : Int, high : Int) -> Image {
  let w = self.width
  let h = self.height
  let n = w * h
  // 1) Smooth luma to suppress noise before differentiation.
  let gray = self.grayscale().blur()
  // 2) Sobel gradients kept as raw signed values for direction info.
  let gx : Array[Int] = Array::make(n, 0)
  let gy : Array[Int] = Array::make(n, 0)
  let mag : Array[Int] = Array::make(n, 0)
  let kx = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
  let ky = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
  for y in 0..<h {
    for x in 0..<w {
      let mut sx = 0
      let mut sy = 0
      for j in 0..<3 {
        for i in 0..<3 {
          let px = clamp_coord(x + i - 1, w)
          let py = clamp_coord(y + j - 1, h)
          let lum = gray.data[(py * w + px) * 4].to_int()
          sx = sx + lum * kx[j * 3 + i]
          sy = sy + lum * ky[j * 3 + i]
        }
      }
      let p = y * w + x
      gx[p] = sx
      gy[p] = sy
      mag[p] = iabs(sx) + iabs(sy)
    }
  }
  // 3) Non-maximum suppression: keep a pixel only if it is at least as
  // strong as both neighbors along its gradient direction. Directions are
  // quantized with tan(22.5 deg) ~= 0.4142 into 0/45/90/135 degree bins.
  let thin : Array[Int] = Array::make(n, 0)
  for y in 0..<h {
    for x in 0..<w {
      let p = y * w + x
      let m = mag[p]
      if m == 0 {
        continue
      }
      let ax = iabs(gx[p]).to_double()
      let ay = iabs(gy[p]).to_double()
      let mut dx = 1
      let mut dy = 0
      if ay <= 0.41421356 * ax {
        dx = 1 // horizontal gradient -> compare left/right
        dy = 0
      } else if ax <= 0.41421356 * ay {
        dx = 0 // vertical gradient -> compare up/down
        dy = 1
      } else if gx[p] * gy[p] > 0 {
        dx = 1 // 45 deg diagonal
        dy = 1
      } else {
        dx = 1 // 135 deg diagonal
        dy = -1
      }
      let q1 = clamp_coord(y + dy, h) * w + clamp_coord(x + dx, w)
      let q2 = clamp_coord(y - dy, h) * w + clamp_coord(x - dx, w)
      if m >= mag[q1] && m >= mag[q2] {
        thin[p] = m
      }
    }
  }
  // 4) Double threshold + hysteresis: flood from strong pixels through
  // weak ones using an explicit stack and 8-connectivity.
  // state: 0 = none, 1 = weak candidate, 2 = confirmed edge.
  let state : Array[Int] = Array::make(n, 0)
  let stack : Array[Int] = []
  for p in 0..<n {
    if thin[p] >= high {
      state[p] = 2
      stack.push(p)
    } else if thin[p] >= low {
      state[p] = 1
    }
  }
  while stack.length() > 0 {
    let p = stack.unsafe_pop()
    let px = p % w
    let py = p / w
    for dy in -1..<2 {
      for dx in -1..<2 {
        let nx = px + dx
        let ny = py + dy
        if nx < 0 || nx >= w || ny < 0 || ny >= h {
          continue
        }
        let q = ny * w + nx
        if state[q] == 1 {
          state[q] = 2
          stack.push(q)
        }
      }
    }
  }
  let out = Image::new(w, h)
  for p in 0..<n {
    let v : Byte = if state[p] == 2 { b'\xFF' } else { b'\x00' }
    let base = p * 4
    out.data[base] = v
    out.data[base + 1] = v
    out.data[base + 2] = v
    out.data[base + 3] = self.data[base + 3]
  }
  out
}
