///|
/// Perceptual hashes: compact 64-bit fingerprints that survive resizing,
/// recompression and mild tonal shifts, so visually similar images map to
/// nearby hashes. `average_hash` thresholds an 8x8 luma thumbnail against
/// its mean; `difference_hash` compares horizontal neighbors on a 9x8
/// thumbnail. Similarity is measured with `hamming_distance` (0 = same,
/// 64 = opposite).

///|
/// Mean luma of the source-image region covering thumbnail cell
/// `(cx, cy)` in a `cols` x `rows` grid. Uses exact integer accumulation
/// over the (possibly clipped, always non-empty) pixel block.
fn Image::cell_luma(
  self : Image,
  cx : Int,
  cy : Int,
  cols : Int,
  rows : Int,
) -> Int {
  let x0 = cx * self.width / cols
  let x1_raw = (cx + 1) * self.width / cols
  let y0 = cy * self.height / rows
  let y1_raw = (cy + 1) * self.height / rows
  // Guarantee at least one pixel per cell even when the image is smaller
  // than the grid.
  let x1 = if x1_raw <= x0 { x0 + 1 } else { x1_raw }
  let y1 = if y1_raw <= y0 { y0 + 1 } else { y1_raw }
  let xe = if x1 > self.width { self.width } else { x1 }
  let ye = if y1 > self.height { self.height } else { y1 }
  let xs = if x0 >= xe { xe - 1 } else { x0 }
  let ys = if y0 >= ye { ye - 1 } else { y0 }
  let mut sum = 0
  let mut count = 0
  for y in ys..<ye {
    for x in xs..<xe {
      let base = (y * self.width + x) * 4
      sum = sum +
        (
          299 * self.data[base].to_int() +
          587 * self.data[base + 1].to_int() +
          114 * self.data[base + 2].to_int()
        ) /
        1000
      count = count + 1
    }
  }
  sum / count
}

///|
/// Average hash (aHash): bit `i = y*8 + x` is set when the luma of cell
/// `(x, y)` in the 8x8 thumbnail is strictly greater than the thumbnail
/// mean. Robust to scaling and mild blur; brightness inversion flips
/// every bit.
pub fn Image::average_hash(self : Image) -> UInt64 {
  let cells = FixedArray::make(64, 0)
  let mut total = 0
  for cy in 0..<8 {
    for cx in 0..<8 {
      let l = self.cell_luma(cx, cy, 8, 8)
      cells[cy * 8 + cx] = l
      total = total + l
    }
  }
  let mean = total / 64
  let mut hash = 0UL
  for i in 0..<64 {
    if cells[i] > mean {
      hash = hash | (1UL << i)
    }
  }
  hash
}

///|
/// Difference hash (dHash): bit `i = y*8 + x` is set when cell `(x+1, y)`
/// of a 9x8 luma thumbnail is brighter than cell `(x, y)` — a horizontal
/// gradient signature that is highly robust to global tonal changes.
pub fn Image::difference_hash(self : Image) -> UInt64 {
  let mut hash = 0UL
  for cy in 0..<8 {
    for cx in 0..<8 {
      let left = self.cell_luma(cx, cy, 9, 8)
      let right = self.cell_luma(cx + 1, cy, 9, 8)
      if right > left {
        hash = hash | (1UL << (cy * 8 + cx))
      }
    }
  }
  hash
}

///|
/// Number of differing bits between two 64-bit hashes (0..64). As a rule
/// of thumb for aHash/dHash: <= 5 means "very likely the same image",
/// >= 20 means "clearly different".
pub fn hamming_distance(a : UInt64, b : UInt64) -> Int {
  let mut x = a ^ b
  let mut count = 0
  while x != 0UL {
    count = count + 1
    x = x & (x - 1UL) // clear the lowest set bit
  }
  count
}
