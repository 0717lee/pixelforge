///|
/// Decode each coded grid cell independently, then retain its native samples
/// while placing the visible rectangle. Color conversion and alpha UNORM
/// narrowing belong to the caller, after the grid has been assembled.
fn avif_decode_grid_frame(
  data : Array[Byte],
  descriptor : AvifGridDescriptor,
) -> Av1FramePlanes? {
  let width = descriptor.output_width
  let height = descriptor.output_height
  let rows = descriptor.rows
  let columns = descriptor.columns
  if width <= 0 ||
    height <= 0 ||
    rows <= 0 ||
    columns <= 0 ||
    rows > 256 ||
    columns > 256 ||
    descriptor.tiles.length() != rows * columns {
    return None
  }
  if width > MAX_IMAGE_PIXELS / height {
    return None
  }
  let decode_cell = fn(tile : AvifGridTile) -> Av1FramePlanes? {
    let sample : Array[Byte] = []
    for extent in tile.extents {
      if extent.offset < 0 ||
        extent.length < 0 ||
        extent.offset > data.length() - extent.length ||
        extent.length > 0x7FFFFFFF - sample.length() {
        return None
      }
      for index in extent.offset..<(extent.offset + extent.length) {
        sample.push(data[index])
      }
    }
    if sample.length() == 0 {
      return None
    }
    av1_decode_frame_planes(sample, allow_monochrome=true)
  }
  let first = match decode_cell(descriptor.tiles[0]) {
    Some(value) => value
    None => return None
  }
  let plane_count = first.planes.length()
  // MIAF 7.3.11.4.2 requires both cell dimensions to be at least 64,
  // including monochrome and alpha cells. Only the output can be smaller.
  if first.width < 64 ||
    first.height < 64 ||
    (plane_count != 1 && plane_count != 3) ||
    (first.bit_depth != 8 && first.bit_depth != 10 && first.bit_depth != 12) {
    return None
  }
  // Division checks complete coverage and ensures that the final row and
  // column actually intersect the output without overflowing coordinates.
  if (width - 1) / first.width != columns - 1 ||
    (height - 1) / first.height != rows - 1 {
    return None
  }
  if plane_count == 3 &&
    ((first.width | first.height | width | height) & 1) != 0 {
    return None
  }
  let planes : Array[Array[Int]] = Array::makei(plane_count, fn(plane) {
    let divisor = if plane == 0 { 1 } else { 2 }
    Array::make(width / divisor * (height / divisor), 0)
  })
  for index in 0..<descriptor.tiles.length() {
    let frame = if index == 0 {
      first
    } else {
      match decode_cell(descriptor.tiles[index]) {
        Some(value) => value
        None => return None
      }
    }
    if frame.width != first.width ||
      frame.height != first.height ||
      frame.bit_depth != first.bit_depth ||
      frame.planes.length() != plane_count ||
      frame.full_range != first.full_range ||
      frame.matrix_coefficients != first.matrix_coefficients {
      return None
    }
    let ox = index % columns * first.width
    let oy = index / columns * first.height
    let copy_width = if width - ox < first.width {
      width - ox
    } else {
      first.width
    }
    let copy_height = if height - oy < first.height {
      height - oy
    } else {
      first.height
    }
    for plane in 0..<plane_count {
      let divisor = if plane == 0 { 1 } else { 2 }
      let stride = width / divisor
      let source_stride = frame.coded_width / divisor
      let source = frame.planes[plane]
      let target = planes[plane]
      for y in 0..<(copy_height / divisor) {
        let destination = (oy / divisor + y) * stride + ox / divisor
        let start = y * source_stride
        for x in 0..<(copy_width / divisor) {
          target[destination + x] = source[start + x]
        }
      }
    }
  }
  Some({
    width,
    height,
    coded_width: width,
    bit_depth: first.bit_depth,
    full_range: first.full_range,
    matrix_coefficients: first.matrix_coefficients,
    planes,
  })
}
