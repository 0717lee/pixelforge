///|
/// Geometric measurements for 4-connected foreground components.
///
/// A foreground pixel is one whose Rec.601 luma is strictly greater than the
/// supplied threshold. Components use the same row-major, 4-connectivity
/// semantics as `Image::label_components`.

///|
/// Inclusive pixel bounds for one connected component.
pub(all) struct BoundingBox {
  min_x : Int
  min_y : Int
  max_x : Int
  max_y : Int
}

///|
/// Measurements for one connected foreground component.
///
/// `centroid_x` and `centroid_y` are arithmetic means of the foreground pixel
/// coordinates (pixel centres are represented by their integer coordinates).
/// The bounding box is inclusive: a one-pixel component has equal minimum and
/// maximum coordinates on both axes.
pub(all) struct ComponentStats {
  label : Int
  area : Int
  bbox : BoundingBox
  centroid : (Double, Double)
  // Flattened aliases keep the common scalar access pattern convenient.
  min_x : Int
  min_y : Int
  max_x : Int
  max_y : Int
  centroid_x : Double
  centroid_y : Double
}

///|
/// Computes area, inclusive bounds and centroid for every foreground
/// component. Results are ordered by increasing label, which is the same
/// row-major discovery order returned by `label_components`.
///
/// The threshold comparison is strict (`luma > threshold`) and connectivity
/// is four-way (up, down, left and right). An image with no foreground pixels
/// returns an empty array.
pub fn Image::regionprops(self : Image, threshold : Int) -> Array[ComponentStats] {
  // Validate the public image invariant before indexing through the label map.
  let n = self.pixel_count()
  let (labels, count) = self.label_components(threshold)
  if count == 0 {
    return []
  }
  let areas : Array[Int] = Array::make(count + 1, 0)
  let min_xs : Array[Int] = Array::make(count + 1, self.width)
  let min_ys : Array[Int] = Array::make(count + 1, self.height)
  let max_xs : Array[Int] = Array::make(count + 1, -1)
  let max_ys : Array[Int] = Array::make(count + 1, -1)
  let sum_xs : Array[Int64] = Array::make(count + 1, 0L)
  let sum_ys : Array[Int64] = Array::make(count + 1, 0L)
  for p in 0..<n {
    let label = labels[p]
    if label == 0 {
      continue
    }
    let x = p % self.width
    let y = p / self.width
    areas[label] = areas[label] + 1
    if x < min_xs[label] {
      min_xs[label] = x
    }
    if y < min_ys[label] {
      min_ys[label] = y
    }
    if x > max_xs[label] {
      max_xs[label] = x
    }
    if y > max_ys[label] {
      max_ys[label] = y
    }
    sum_xs[label] = sum_xs[label] + x.to_int64()
    sum_ys[label] = sum_ys[label] + y.to_int64()
  }
  let result : Array[ComponentStats] = []
  for label in 1..<(count + 1) {
    let area = areas[label]
    let cx = sum_xs[label].to_double() / area.to_double()
    let cy = sum_ys[label].to_double() / area.to_double()
    let bbox = {
      min_x: min_xs[label],
      min_y: min_ys[label],
      max_x: max_xs[label],
      max_y: max_ys[label],
    }
    result.push({
      label,
      area,
      bbox,
      centroid: (cx, cy),
      min_x: min_xs[label],
      min_y: min_ys[label],
      max_x: max_xs[label],
      max_y: max_ys[label],
      centroid_x: cx,
      centroid_y: cy,
    })
  }
  result
}
