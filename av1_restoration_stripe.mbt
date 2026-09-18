/// Loop-restoration stripe boundary storage and source view.
///
/// Loop restoration filters each global stripe of a plane against an
/// immutable post-CDEF/upscaled source, except at internal stripe
/// boundaries where the filter taps would read CDEF-modified rows
/// belonging to the neighbouring stripe. The deblocked rows at those
/// boundaries are saved before CDEF and, when superres is active,
/// horizontally upscaled with the same normative scaler and full-frame
/// widths as the frame itself, so the saved rows share the frame's
/// sampling phase (AV1 audit §6; AOM restoration.c:1355-1508).
///
/// Stripe geometry is global per plane and independent of tiles,
/// superblocks and restoration unit sizes: stripe k spans
/// `[max(0, k*S - O), min((k+1)*S - O, plane_height))` with
/// `S = 64 >> ss_y` and `O = 8 >> ss_y`. A 256-row luma plane yields
/// `[0,56),[56,120),[120,184),...`; a 4:2:0 chroma plane of 128 rows
/// yields `[0,28),[28,60),[60,92),...`. The last stripe is clipped to
/// the frame height.

///|
/// Global stripe rectangles for one plane, as (start, end) row pairs.
fn av1_restoration_stripe_bounds(
  plane_height : Int,
  subsampling_y : Bool,
) -> Array[(Int, Int)]? {
  if plane_height <= 0 || plane_height > 65536 {
    return None
  }
  let s = if subsampling_y { 32 } else { 64 }
  let o = if subsampling_y { 4 } else { 8 }
  let count = (plane_height + o + s - 1) / s
  let bounds : Array[(Int, Int)] = []
  for k in 0..<count {
    let start = if k * s > o { k * s - o } else { 0 }
    let end = {
      let raw = (k + 1) * s - o
      if raw < plane_height {
        raw
      } else {
        plane_height
      }
    }
    bounds.push((start, end))
  }
  Some(bounds)
}

///|
/// Saved deblocked rows at every internal stripe boundary of one
/// plane. `top[k]` holds the two rows above stripe k's start (k >= 1)
/// and `bottom[k]` the two rows at or after stripe k's end (non-last
/// stripe), each as `2 * width` native samples: the first saved row
/// occupies `[0, width)`, the second `[width, 2*width)`. Outer
/// boundaries are empty; the source view repeats the frame edge rows
/// there. All rows are stored at the upscaled plane width.
pub(all) struct Av1RestorationPlaneStripes {
  count : Int
  width : Int
  height : Int
  starts : Array[Int]
  ends : Array[Int]
  top : Array[Array[Int]]
  bottom : Array[Array[Int]]
}

///|
/// Per-plane stripe stores for one frame.
pub(all) struct Av1RestorationStripeStore {
  planes : Array[Av1RestorationPlaneStripes]
}

///|
/// One stored boundary pair (two rows at upscaled width), or an empty
/// array when the boundary is absent.
fn av1_restoration_stripe_pair(
  store : Av1RestorationStripeStore,
  plane : Int,
  stripe : Int,
  above : Bool,
) -> Array[Int] {
  if plane < 0 || plane >= store.planes.length() {
    return []
  }
  let info = store.planes[plane]
  if stripe < 0 || stripe >= info.count {
    return []
  }
  if above {
    info.top[stripe]
  } else {
    info.bottom[stripe]
  }
}

///|
/// Save the deblocked rows at every internal stripe boundary before
/// CDEF runs. For each internal stripe top (k >= 1) save LF rows
/// `y0-2, y0-1`; for each internal stripe bottom (y1 < plane height)
/// save LF rows `y1, y1+1`, duplicating `y1` when only one row
/// remains. When superres is active (`output_width != width`) the
/// saved rows are upscaled with the normative scaler at the same
/// full-frame plane widths, preserving the frame's sampling phase.
/// Returns None on invalid geometry or an out-of-range plane.
fn av1_restoration_save_stripes(
  planes : Array[Array[Int]],
  coded_width : Int,
  width : Int,
  output_width : Int,
  height : Int,
  bit_depth : Int,
  monochrome : Bool,
  sub_x? : Int = 1,
  sub_y? : Int = 1,
) -> Av1RestorationStripeStore? {
  let num_planes = if monochrome { 1 } else { 3 }
  if planes.length() != num_planes ||
    width <= 0 ||
    height <= 0 ||
    width > 65536 ||
    height > 65536 ||
    coded_width < width ||
    output_width < width ||
    output_width > 2 * width ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  let superres = output_width != width
  let result : Array[Av1RestorationPlaneStripes] = []
  for plane in 0..<num_planes {
    let divisor_x = if plane == 0 { 1 } else { 1 << sub_x }
    let divisor_y = if plane == 0 { 1 } else { 1 << sub_y }
    let stride = coded_width / divisor_x
    let plane_height = (height + divisor_y - 1) / divisor_y
    let plane_width_coded = (width + divisor_x - 1) / divisor_x
    let plane_width_up = (output_width + divisor_x - 1) / divisor_x
    if stride < plane_width_coded ||
      plane_height <= 0 ||
      planes[plane].length() < plane_height * stride {
      return None
    }
    let bounds = match
      av1_restoration_stripe_bounds(plane_height, plane != 0 && sub_y == 1) {
      Some(value) => value
      None => return None
    }
    let count = bounds.length()
    let starts : Array[Int] = Array::make(count, 0)
    let ends : Array[Int] = Array::make(count, 0)
    let top : Array[Array[Int]] = Array::makei(count, fn(_) { [] })
    let bottom : Array[Array[Int]] = Array::makei(count, fn(_) { [] })
    // One entry per internal boundary pair, in stripe order.
    let entries : Array[(Int, Bool, Int, Int)] = []
    for k in 0..<count {
      let (start, end) = bounds[k]
      starts[k] = start
      ends[k] = end
      if k >= 1 {
        entries.push((k, true, start - 2, start - 1))
      }
      if end < plane_height {
        let second = if end + 1 < plane_height { end + 1 } else { end }
        entries.push((k, false, end, second))
      }
    }
    if !superres {
      for entry in entries {
        let (k, above, row_a, row_b) = entry
        let pair : Array[Int] = Array::make(2 * plane_width_coded, 0)
        for i in 0..<2 {
          let row = if i == 0 { row_a } else { row_b }
          for col in 0..<plane_width_coded {
            pair[i * plane_width_coded + col] = planes[plane][row * stride + col]
          }
        }
        if above {
          top[k] = pair
        } else {
          bottom[k] = pair
        }
      }
    } else if entries.length() > 0 {
      // Pack the coded rows and upscale them in one normative pass so
      // every saved row shares the full-frame sampling phase.
      let row_count = entries.length() * 2
      let temp : Array[Int] = Array::make(row_count * stride, 0)
      let mut index = 0
      for entry in entries {
        let (_, _, row_a, row_b) = entry
        for i in 0..<2 {
          let row = if i == 0 { row_a } else { row_b }
          for col in 0..<stride {
            temp[index * stride + col] = planes[plane][row * stride + col]
          }
          index = index + 1
        }
      }
      let upscaled = match
        av1_superres_upscale_plane(
          temp, stride, stride, plane_width_coded, plane_width_up, row_count, bit_depth,
        ) {
        Some(value) => value
        None => return None
      }
      index = 0
      for entry in entries {
        let (k, above, _, _) = entry
        let pair : Array[Int] = Array::make(2 * plane_width_up, 0)
        for i in 0..<2 {
          for col in 0..<plane_width_up {
            pair[i * plane_width_up + col] = upscaled[(index + i) *
              plane_width_up +
              col]
          }
        }
        if above {
          top[k] = pair
        } else {
          bottom[k] = pair
        }
        index = index + 2
      }
    }
    result.push({
      count,
      width: plane_width_up,
      height: plane_height,
      starts,
      ends,
      top,
      bottom,
    })
  }
  Some({ planes: result, })
}

///|
/// Contract check for a saved store: stripe counts match the
/// normative bounds, every stored pair holds exactly two rows at the
/// plane's upscaled width, internal boundaries are populated and
/// outer boundaries are empty.
fn av1_restoration_stripe_store_valid(
  store : Av1RestorationStripeStore,
) -> Bool {
  if store.planes.length() == 0 {
    return false
  }
  for info in store.planes {
    if info.count <= 0 || info.width <= 0 || info.height <= 0 {
      return false
    }
    if info.starts.length() != info.count ||
      info.ends.length() != info.count ||
      info.top.length() != info.count ||
      info.bottom.length() != info.count {
      return false
    }
    for k in 0..<info.count {
      if info.starts[k] < 0 ||
        info.ends[k] <= info.starts[k] ||
        info.ends[k] > info.height {
        return false
      }
      for pair in [info.top[k], info.bottom[k]] {
        if pair.length() != 0 && pair.length() != 2 * info.width {
          return false
        }
      }
    }
    if info.top[0].length() != 0 || info.bottom[info.count - 1].length() != 0 {
      return false
    }
    for k in 1..<info.count {
      if info.top[k].length() != 2 * info.width {
        return false
      }
    }
    for k in 0..<(info.count - 1) {
      if info.bottom[k].length() != 2 * info.width {
        return false
      }
    }
  }
  true
}

///|
/// Immutable view over the post-CDEF/upscaled frame plus the saved
/// stripe rows. Samples resolve under the stripe rules: inside the
/// stripe read the frame; above an internal start read the saved top
/// pair as `[top0, top0, top1]` at offsets -3, -2, -1; below a
/// non-last end read the saved bottom pair as `[bottom0, bottom1,
/// bottom1]` at offsets 0, 1, 2; at the frame top/bottom repeat the
/// frame edge rows. x is clamped to the visible plane width, so coded
/// MI padding never surfaces.
pub(all) struct Av1RestorationSourceView {
  store : Av1RestorationStripeStore
  frame : Array[Array[Int]]
  frame_strides : Array[Int]
}

///|
fn av1_restoration_source_sample(
  view : Av1RestorationSourceView,
  plane : Int,
  x : Int,
  y : Int,
  stripe : Int,
) -> Int {
  let store = view.store
  if plane < 0 ||
    plane >= store.planes.length() ||
    plane >= view.frame.length() ||
    plane >= view.frame_strides.length() {
    return 0
  }
  let info = store.planes[plane]
  if stripe < 0 || stripe >= info.count || info.width <= 0 {
    return 0
  }
  let px = if x < 0 { 0 } else if x >= info.width { info.width - 1 } else { x }
  let stride = view.frame_strides[plane]
  let start = info.starts[stripe]
  let end = info.ends[stripe]
  if y < start {
    // Above the current stripe's start. Stripe 0 starts at row 0, so
    // this is only reached by out-of-frame taps: the frame top repeats
    // the post-CDEF/upscaled edge row. Internal starts read the saved
    // top pair as [top0, top0, top1] at offsets -3, -2, -1.
    if stripe == 0 {
      return view.frame[plane][px]
    }
    let pair = info.top[stripe]
    let row = if start - y >= 2 { 0 } else { 1 }
    return pair[row * info.width + px]
  }
  if y >= end {
    // Below the current stripe's end. Only the last stripe ends at the
    // frame bottom; its out-of-frame taps repeat the post-CDEF edge
    // row. Non-last stripes read the saved bottom pair as
    // [bottom0, bottom1, bottom1] at offsets 0, 1, 2, whose duplicated
    // second row also covers taps past the frame bottom.
    if stripe == info.count - 1 {
      return view.frame[plane][(info.height - 1) * stride + px]
    }
    let pair = info.bottom[stripe]
    let row = if y - end <= 0 { 0 } else { 1 }
    return pair[row * info.width + px]
  }
  view.frame[plane][y * stride + px]
}
