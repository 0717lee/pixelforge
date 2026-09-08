///| 
/// Histogram of Oriented Gradients (HOG) descriptor.
///
/// `Image::hog` converts pixels to BT.601 luma, computes a central-difference
/// gradient (forward/backward difference at the image boundary), and builds
/// unsigned orientation histograms in square cells.  A pixel contributes its
/// gradient magnitude with linear interpolation between the two neighbouring
/// orientation bins; orientations are wrapped into `[0, pi)`, so an edge has
/// no direction.  Pixels in incomplete cells at the right or bottom edge are
/// ignored.
///
/// Histograms are normalized per overlapping block.  Blocks are laid out in
/// row-major cell order.  Inside each block values are laid out as
/// `(cell_y, cell_x, bin)`, also in row-major order.  Normalization is L2 with
/// epsilon `1e-12`: each block is divided by
/// `sqrt(sum(value * value) + epsilon * epsilon)`.  A constant image therefore
/// produces an all-zero descriptor.  Invalid parameters abort; when the image
/// has fewer complete cells than one block, the result is empty.

///| BT.601 luma used by the HOG gradient loop.
fn hog_luma(image : Image, x : Int, y : Int) -> Int {
  let i = (y * image.width + x) * 4
  (299 * image.data[i].to_int() + 587 * image.data[i + 1].to_int() +
    114 * image.data[i + 2].to_int()) /
    1000
}

///| Clamped central/one-sided gradient for one pixel.
fn hog_gradient(image : Image, x : Int, y : Int) -> (Int, Int) {
  let left = if x == 0 { hog_luma(image, x, y) } else {
    hog_luma(image, x - 1, y)
  }
  let right = if x + 1 >= image.width { hog_luma(image, x, y) } else {
    hog_luma(image, x + 1, y)
  }
  let top = if y == 0 { hog_luma(image, x, y) } else {
    hog_luma(image, x, y - 1)
  }
  let bottom = if y + 1 >= image.height { hog_luma(image, x, y) } else {
    hog_luma(image, x, y + 1)
  }
  (right - left, bottom - top)
}

///| Returns a normalized unsigned HOG descriptor.
///
/// `cell_size` is the side length of one cell in pixels. `bins` is the number
/// of evenly spaced orientation bins over `[0, pi)`. `block_size` is the side
/// length of each normalization block in cells.  The output is an `Array[Double]`
/// in block-major order; its length is
/// `(cells_x - block_size + 1) * (cells_y - block_size + 1) *
/// block_size * block_size * bins` when enough complete cells are present.
pub fn Image::hog(
  self : Image,
  cell_size : Int,
  bins : Int,
  block_size : Int,
) -> Array[Double] {
  if cell_size <= 0 {
    abort("Image::hog: cell_size must be positive")
  }
  if bins <= 0 {
    abort("Image::hog: bins must be positive")
  }
  if block_size <= 0 {
    abort("Image::hog: block_size must be positive")
  }
  let cells_x = self.width / cell_size
  let cells_y = self.height / cell_size
  if cells_x < block_size || cells_y < block_size {
    return []
  }
  let cell_hist : Array[Double] = Array::make(cells_x * cells_y * bins, 0.0)
  let pi = 3.141592653589793
  let bin_width = pi / bins.to_double()
  for y in 0..<(cells_y * cell_size) {
    for x in 0..<(cells_x * cell_size) {
      let (gx, gy) = hog_gradient(self, x, y)
      let magnitude = (gx.to_double() * gx.to_double() +
        gy.to_double() * gy.to_double()).sqrt()
      if magnitude == 0.0 {
        continue
      }
      let mut angle = @math.atan2(gy.to_double(), gx.to_double())
      if angle < 0.0 {
        angle = angle + pi
      }
      if angle >= pi {
        angle = angle - pi
      }
      let position = angle / bin_width
      let lower = position.to_int()
      let fraction = position - lower.to_double()
      let cell_x = x / cell_size
      let cell_y = y / cell_size
      let base = (cell_y * cells_x + cell_x) * bins
      let next = if lower + 1 == bins { 0 } else { lower + 1 }
      cell_hist[base + lower] = cell_hist[base + lower] + magnitude *
        (1.0 - fraction)
      cell_hist[base + next] = cell_hist[base + next] + magnitude * fraction
    }
  }
  let blocks_x = cells_x - block_size + 1
  let blocks_y = cells_y - block_size + 1
  let block_width = block_size * block_size * bins
  let result : Array[Double] = Array::make(blocks_x * blocks_y * block_width, 0.0)
  let epsilon = 1.0e-12
  for by in 0..<blocks_y {
    for bx in 0..<blocks_x {
      let output_base = (by * blocks_x + bx) * block_width
      let mut norm_squared = 0.0
      for dy in 0..<block_size {
        for dx in 0..<block_size {
          let source = ((by + dy) * cells_x + bx + dx) * bins
          for bin in 0..<bins {
            let value = cell_hist[source + bin]
            result[output_base + (dy * block_size + dx) * bins + bin] = value
            norm_squared = norm_squared + value * value
          }
        }
      }
      let norm = (norm_squared + epsilon * epsilon).sqrt()
      for i in 0..<block_width {
        result[output_base + i] = result[output_base + i] / norm
      }
    }
  }
  result
}
