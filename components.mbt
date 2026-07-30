///|
/// Connected-component labeling on a thresholded image. Foreground pixels
/// (luma strictly greater than the threshold) are grouped by 4-connectivity
/// with an explicit-stack flood fill, giving each blob a positive label.

///|
/// Labels 4-connected foreground components. Returns `(labels, count)`
/// where `labels` has one entry per pixel — `0` for background, `1..count`
/// for each component — in row-major order.
pub fn Image::label_components(
  self : Image,
  threshold : Int,
) -> (Array[Int], Int) {
  let w = self.width
  let h = self.height
  let n = w * h
  // Foreground mask from luma.
  let fg : Array[Bool] = Array::make(n, false)
  for p in 0..<n {
    let base = p * 4
    let y = (
        299 * self.data[base].to_int() +
        587 * self.data[base + 1].to_int() +
        114 * self.data[base + 2].to_int()
      ) /
      1000
    fg[p] = y > threshold
  }
  let labels : Array[Int] = Array::make(n, 0)
  let stack : Array[Int] = []
  let mut count = 0
  for start in 0..<n {
    if !fg[start] || labels[start] != 0 {
      continue
    }
    count = count + 1
    labels[start] = count
    stack.push(start)
    while stack.length() > 0 {
      let p = stack.unsafe_pop()
      let px = p % w
      let py = p / w
      // 4-neighborhood.
      if px > 0 && fg[p - 1] && labels[p - 1] == 0 {
        labels[p - 1] = count
        stack.push(p - 1)
      }
      if px + 1 < w && fg[p + 1] && labels[p + 1] == 0 {
        labels[p + 1] = count
        stack.push(p + 1)
      }
      if py > 0 && fg[p - w] && labels[p - w] == 0 {
        labels[p - w] = count
        stack.push(p - w)
      }
      if py + 1 < h && fg[p + w] && labels[p + w] == 0 {
        labels[p + w] = count
        stack.push(p + w)
      }
    }
  }
  (labels, count)
}

///|
/// Counts the 4-connected foreground blobs (luma > `threshold`).
pub fn Image::count_components(self : Image, threshold : Int) -> Int {
  self.label_components(threshold).1
}
