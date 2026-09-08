/// Binary skeletonization by Zhang--Suen thinning.
///
/// Foreground is defined by BT.601 luma strictly greater than `threshold`.
/// The returned image is a binary grayscale image (RGB is either 0 or 255)
/// with the source alpha channel preserved. Border pixels are kept in place so
/// that every iteration can use a complete 3x3 neighbourhood. `max_iterations`
/// bounds the number of thinning rounds; values above 1024 are clamped and
/// non-positive values return the thresholded image without thinning.

const SKELETON_MAX_ITERATIONS : Int = 1024

fn skeleton_bit(value : Bool) -> Int {
  if value { 1 } else { 0 }
}

fn skeleton_luma(image : Image, pixel : Int) -> Int {
  let base = pixel * 4
  (
    299 * image.data[base].to_int() +
    587 * image.data[base + 1].to_int() +
    114 * image.data[base + 2].to_int()
  ) / 1000
}

fn skeleton_transition(
  p2 : Bool,
  p3 : Bool,
  p4 : Bool,
  p5 : Bool,
  p6 : Bool,
  p7 : Bool,
  p8 : Bool,
  p9 : Bool,
) -> Int {
  let values : FixedArray[Bool] = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
  let mut transitions = 0
  for i in 0..<8 {
    if !values[i] && values[i + 1] {
      transitions = transitions + 1
    }
  }
  transitions
}

fn skeleton_neighbours(mask : Array[Bool], width : Int, pixel : Int) -> (
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
) {
  let p2 = mask[pixel - width]
  let p3 = mask[pixel - width + 1]
  let p4 = mask[pixel + 1]
  let p5 = mask[pixel + width + 1]
  let p6 = mask[pixel + width]
  let p7 = mask[pixel + width - 1]
  let p8 = mask[pixel - 1]
  let p9 = mask[pixel - width - 1]
  (p2, p3, p4, p5, p6, p7, p8, p9)
}

fn skeleton_mark_phase(
  mask : Array[Bool],
  width : Int,
  height : Int,
  phase : Int,
) -> Array[Int] {
  let marked : Array[Int] = []
  if width < 3 || height < 3 {
    return marked
  }
  for y in 1..<(height - 1) {
    for x in 1..<(width - 1) {
      let pixel = y * width + x
      if !mask[pixel] {
        continue
      }
      let (p2, p3, p4, p5, p6, p7, p8, p9) =
        skeleton_neighbours(mask, width, pixel)
      let neighbours =
        skeleton_bit(p2) + skeleton_bit(p3) + skeleton_bit(p4) + skeleton_bit(p5) +
        skeleton_bit(p6) + skeleton_bit(p7) + skeleton_bit(p8) + skeleton_bit(p9)
      if neighbours < 2 || neighbours > 6 {
        continue
      }
      if skeleton_transition(p2, p3, p4, p5, p6, p7, p8, p9) != 1 {
        continue
      }
      let keep = if phase == 0 {
        // p2*p4*p6 == 0 and p4*p6*p8 == 0.
        (!p2 || !p4 || !p6) && (!p4 || !p6 || !p8)
      } else {
        // p2*p4*p8 == 0 and p2*p6*p8 == 0.
        (!p2 || !p4 || !p8) && (!p2 || !p6 || !p8)
      }
      if keep {
        marked.push(pixel)
      }
    }
  }
  marked
}

/// Returns a thinned binary image using a bounded Zhang--Suen iteration.
pub fn Image::skeletonize(self : Image, threshold : Int, max_iterations : Int) -> Image {
  let width = self.width
  let height = self.height
  let count = self.pixel_count()
  let mask : Array[Bool] = Array::make(count, false)
  for pixel in 0..<count {
    mask[pixel] = skeleton_luma(self, pixel) > threshold
  }
  let limit = if max_iterations <= 0 {
    0
  } else if max_iterations > SKELETON_MAX_ITERATIONS {
    SKELETON_MAX_ITERATIONS
  } else {
    max_iterations
  }
  let mut iteration = 0
  while iteration < limit {
    let first = skeleton_mark_phase(mask, width, height, 0)
    for pixel in first {
      mask[pixel] = false
    }
    let second = skeleton_mark_phase(mask, width, height, 1)
    for pixel in second {
      mask[pixel] = false
    }
    iteration = iteration + 1
    if first.length() == 0 && second.length() == 0 {
      break
    }
  }
  let out = Image::new(width, height)
  for pixel in 0..<count {
    let source = pixel * 4
    let value : Byte = if mask[pixel] { b'\xFF' } else { b'\x00' }
    out.data[source] = value
    out.data[source + 1] = value
    out.data[source + 2] = value
    out.data[source + 3] = self.data[source + 3]
  }
  out
}
