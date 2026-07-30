///|
/// Flood fill (seed fill): starting from a seed pixel, replaces the
/// 4-connected region whose color matches the seed's — within a per-channel
/// tolerance — with a new color. Uses an explicit stack (no recursion), so
/// it handles large regions without overflowing the call stack.

///|
/// Absolute per-channel difference test: true when every channel of the two
/// RGBA pixels is within `tol`.
fn within_tol(
  data : FixedArray[Byte],
  i : Int,
  sr : Int,
  sg : Int,
  sb : Int,
  sa : Int,
  tol : Int,
) -> Bool {
  iabs(data[i].to_int() - sr) <= tol &&
  iabs(data[i + 1].to_int() - sg) <= tol &&
  iabs(data[i + 2].to_int() - sb) <= tol &&
  iabs(data[i + 3].to_int() - sa) <= tol
}

///|
/// Fills the 4-connected region around `(x, y)` matching the seed color
/// (within `tolerance` per channel) with `(r, g, b, a)`. Returns a new image;
/// the original is untouched. An out-of-bounds seed returns a plain copy. If
/// the fill color already matches the seed, the copy is returned unchanged
/// (nothing to do), which also avoids an infinite revisit.
pub fn Image::flood_fill(
  self : Image,
  x : Int,
  y : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
  tolerance : Int,
) -> Image {
  let out = self.copy()
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    return out
  }
  let w = self.width
  let h = self.height
  let seed = (y * w + x) * 4
  let sr = self.data[seed].to_int()
  let sg = self.data[seed + 1].to_int()
  let sb = self.data[seed + 2].to_int()
  let sa = self.data[seed + 3].to_int()
  // If the target color already matches the seed, there is nothing to do.
  if iabs(r.to_int() - sr) == 0 &&
    iabs(g.to_int() - sg) == 0 &&
    iabs(b.to_int() - sb) == 0 &&
    iabs(a.to_int() - sa) == 0 {
    return out
  }
  let visited = Array::make(w * h, false)
  let stack : Array[Int] = []
  stack.push(y * w + x)
  visited[y * w + x] = true
  while stack.length() > 0 {
    let p = stack.unsafe_pop()
    let base = p * 4
    // Paint this pixel.
    out.data[base] = r
    out.data[base + 1] = g
    out.data[base + 2] = b
    out.data[base + 3] = a
    let px = p % w
    let py = p / w
    // Enqueue 4-neighbors that match the seed color and are unvisited.
    if px > 0 &&
      !visited[p - 1] &&
      within_tol(self.data, (p - 1) * 4, sr, sg, sb, sa, tolerance) {
      visited[p - 1] = true
      stack.push(p - 1)
    }
    if px + 1 < w &&
      !visited[p + 1] &&
      within_tol(self.data, (p + 1) * 4, sr, sg, sb, sa, tolerance) {
      visited[p + 1] = true
      stack.push(p + 1)
    }
    if py > 0 &&
      !visited[p - w] &&
      within_tol(self.data, (p - w) * 4, sr, sg, sb, sa, tolerance) {
      visited[p - w] = true
      stack.push(p - w)
    }
    if py + 1 < h &&
      !visited[p + w] &&
      within_tol(self.data, (p + w) * 4, sr, sg, sb, sa, tolerance) {
      visited[p + w] = true
      stack.push(p + w)
    }
  }
  out
}
