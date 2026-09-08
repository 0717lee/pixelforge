///|
/// Deterministic contours for thresholded foreground components.
///
/// A foreground pixel is one whose Rec.601 luma is strictly greater than
/// `threshold`, matching `Image::label_components` and `Image::regionprops`.
/// Components use four-connectivity. The returned contour for each component
/// contains its boundary pixels (not interpolated geometric vertices) in
/// row-major order, and the outer array follows component label order. A
/// foreground pixel is on the boundary when at least one of its four
/// neighbours is outside the image or background. This representation keeps
/// the result bounded by the number of input pixels and is stable across
/// targets and runs.

///|
/// One boundary pixel in a component contour. Coordinates are integer pixel
/// positions with `(0, 0)` at the image's top-left corner.
pub(all) struct ContourPoint {
  x : Int
  y : Int
}

///|
/// Returns one deterministic boundary-pixel list for every 4-connected
/// foreground component. Empty images and images without foreground return an
/// empty array. A one-pixel component therefore has a one-point contour.
pub fn Image::contours(self : Image, threshold : Int) -> Array[Array[ContourPoint]] {
  let w = self.width
  let h = self.height
  if w == 0 || h == 0 {
    return []
  }
  let (labels, count) = self.label_components(threshold)
  if count == 0 {
    return []
  }
  let contours : Array[Array[ContourPoint]] = []
  for _ in 0..<count {
    contours.push([])
  }
  // Scanning row-major makes both component and point ordering deterministic.
  for p in 0..<(w * h) {
    let label = labels[p]
    if label == 0 {
      continue
    }
    let x = p % w
    let y = p / w
    let boundary =
      x == 0 || labels[p - 1] != label || x + 1 >= w || labels[p + 1] != label ||
      y == 0 || labels[p - w] != label || y + 1 >= h || labels[p + w] != label
    if boundary {
      let contour = contours[label - 1]
      contour.push({ x, y })
    }
  }
  contours
}
