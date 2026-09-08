///|
/// Local Binary Pattern (LBP) descriptors.
///
/// The implementation uses the classic 8-neighbour, radius-one operator.
/// Bits are assigned clockwise starting at the top-left neighbour.  Border
/// pixels do not have a complete neighbourhood: their code is zero and they
/// are omitted from the histogram.  Keeping this convention explicit makes
/// histograms comparable across images of different sizes without inventing
/// out-of-bounds sample values.

///| Internal BT.601 luma helper used by the descriptor hot loop.
fn lbp_luma(image : Image, x : Int, y : Int) -> Int {
  let i = (y * image.width + x) * 4
  (
    299 * image.data[i].to_int() +
    587 * image.data[i + 1].to_int() +
    114 * image.data[i + 2].to_int()
  ) / 1000
}

///| Returns one 8-bit LBP code for every pixel in row-major order.
///
/// For an interior pixel, bit `0` is top-left and subsequent bits proceed
/// clockwise (`top`, `top-right`, ..., `left`).  A bit is set when its
/// neighbour's luma is greater than or equal to the centre luma.  Border
/// entries are zero because they cannot provide eight samples.
pub fn Image::lbp_codes(self : Image) -> FixedArray[Byte] {
  let n = self.pixel_count()
  let codes = FixedArray::make(n, b'\x00')
  if self.width < 3 || self.height < 3 {
    return codes
  }
  let offsets : FixedArray[(Int, Int)] = [
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
  ]
  for y in 1..<(self.height - 1) {
    for x in 1..<(self.width - 1) {
      let centre = lbp_luma(self, x, y)
      let mut code = 0
      for bit in 0..<8 {
        let (dx, dy) = offsets[bit]
        if lbp_luma(self, x + dx, y + dy) >= centre {
          code = code | (1 << bit)
        }
      }
      codes[y * self.width + x] = code.to_byte()
    }
  }
  codes
}

///| Returns the 256-bin histogram of radius-one LBP codes.
///
/// Only pixels with a complete 3x3 neighbourhood contribute, so the bin sum
/// is `max(width - 2, 0) * max(height - 2, 0)`.  The histogram is useful as a
/// compact texture descriptor and is invariant to the image's absolute
/// brightness when local ordering is preserved.
pub fn Image::lbp_histogram(self : Image) -> FixedArray[Int] {
  let histogram = FixedArray::make(256, 0)
  let codes = self.lbp_codes()
  if self.width < 3 || self.height < 3 {
    return histogram
  }
  for y in 1..<(self.height - 1) {
    for x in 1..<(self.width - 1) {
      let code = codes[y * self.width + x].to_int()
      histogram[code] = histogram[code] + 1
    }
  }
  histogram
}
