/// AV1 scalar loop-restoration kernels and frame driver.
///
/// Wiener filters each output pixel as a separable 7-tap horizontal
/// then vertical convolution over the immutable post-CDEF/upscaled
/// source, with the horizontal result clipped to an intermediate
/// range before the vertical pass. SGR computes per-pixel box-filtered
/// projections `flt0`/`flt1` from the same source and combines them
/// with the unshifted center pixel through the coded weights
/// `w0 + w1 + w2 = 128`. Both kernels read their taps through
/// `Av1RestorationSourceView`, so internal stripe boundaries resolve to
/// the saved deblocked rows and frame edges repeat the post-CDEF edge
/// rows (AV1 spec §7.17; go-av1 decode/lr.go:236-268 and decode/sgr.go).
///
/// Filtering follows the audit §7 rectangles: split the visible plane
/// into U-sized cells with the `<1.5U` tail rule, shift each nominal
/// vertical cell by `8>>ss_y` into `[max(0, y0-O), y1 < H ? y1-O : H)`,
/// and process the rectangle as intersections with the global stripes.
/// The unit's parameters cover every stripe piece of its rectangle;
/// None units leave the LR input untouched.

///|
/// SGR parameter sets indexed by the 4-bit `ep`: (r0, eps0, r1, eps1).
let av1_sgr_params_table : Array[(Int, Int, Int, Int)] = [
  (2, 12, 1, 4),
  (2, 15, 1, 6),
  (2, 18, 1, 8),
  (2, 21, 1, 9),
  (2, 24, 1, 10),
  (2, 29, 1, 11),
  (2, 36, 1, 12),
  (2, 45, 1, 13),
  (2, 56, 1, 14),
  (2, 68, 1, 15),
  (0, 0, 1, 5),
  (0, 0, 1, 8),
  (0, 0, 1, 11),
  (0, 0, 1, 14),
  (2, 30, 0, 0),
  (2, 75, 0, 0),
]

///|
/// Look up one SGR parameter set; None outside the 4-bit range.
fn av1_sgr_params(set : Int) -> (Int, Int, Int, Int)? {
  if set < 0 || set >= av1_sgr_params_table.length() {
    return None
  }
  Some(av1_sgr_params_table[set])
}

///|
/// Rounded right shift with a half added first; non-positive shifts
/// pass the value through (go-av1 decode/sgr.go:49-54).
fn av1_lr_round_n(x : Int, n : Int) -> Int {
  if n <= 0 {
    x
  } else {
    (x + (1 << (n - 1))) >> n
  }
}

///|
/// Clamp to the inclusive range.
fn av1_lr_clip(lo : Int, hi : Int, v : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Expand the three coded Wiener taps of one axis into the symmetric
/// 7-tap filter `[c0, c1, c2, 128-2*(c0+c1+c2), c2, c1, c0]`. A chroma
/// tap 0 of zero makes the 7-tap loop equivalent to the 5-tap filter.
fn av1_wiener_coeff(taps : Array[Int]) -> Array[Int] {
  let filter : Array[Int] = Array::make(7, 0)
  filter[3] = 128
  for i in 0..<3 {
    let c = taps[i]
    filter[i] = c
    filter[6 - i] = c
    filter[3] = filter[3] - 2 * c
  }
  filter
}

///|
/// One unit's cell along an axis: full units span `index*U` to
/// `(index+1)*U`; the last cell extends to the plane edge, which is
/// the `<1.5U` tail rule of the unit count.
fn av1_lr_unit_cell(
  unit : Int,
  plane_size : Int,
  count : Int,
  index : Int,
) -> (Int, Int) {
  let start = index * unit
  let end = if index + 1 < count { (index + 1) * unit } else { plane_size }
  (start, end)
}

///|
/// Wiener filter over one `[x0, x0+w) x [y0, y0+h)` piece of a
/// stripe. The horizontal pass produces `h+6` intermediate rows so the
/// vertical taps can read three rows above and below the piece; every
/// source sample resolves through the stripe source view.
fn av1_wiener_filter_piece(
  view : Av1RestorationSourceView,
  plane : Int,
  x0 : Int,
  y0 : Int,
  w : Int,
  h : Int,
  stripe : Int,
  vertical : Array[Int],
  horizontal : Array[Int],
  bit_depth : Int,
) -> Array[Int] {
  let round0 = if bit_depth == 12 { 5 } else { 3 }
  let inter_round = if bit_depth == 12 { 9 } else { 11 }
  let vfilter = av1_wiener_coeff(vertical)
  let hfilter = av1_wiener_coeff(horizontal)
  let offset = 1 << (bit_depth + 7 - round0 - 1)
  let limit = (1 << (bit_depth + 1 + 7 - round0)) - 1
  let hi = (1 << bit_depth) - 1
  let intermediate : Array[Int] = Array::make((h + 6) * w, 0)
  for r in 0..<(h + 6) {
    for c in 0..<w {
      let mut s = 0
      for t in 0..<7 {
        s = s +
          hfilter[t] *
          av1_restoration_source_sample(view, plane, x0 + c + t - 3, y0 + r - 3,
            stripe)
      }
      intermediate[r * w + c] = av1_lr_clip(-offset, limit - offset,
        av1_lr_round_n(s, round0))
    }
  }
  let out : Array[Int] = Array::make(w * h, 0)
  for r in 0..<h {
    for c in 0..<w {
      let mut s = 0
      for t in 0..<7 {
        s = s + vfilter[t] * intermediate[(r + t) * w + c]
      }
      out[r * w + c] = av1_lr_clip(0, hi, av1_lr_round_n(s, inter_round))
    }
  }
  out
}

///|
/// One self-guided box-filter pass over a piece: `A`/`B` hold the
/// per-pixel `a2`/`b2` statistics computed over the `(2r+1)^2` source
/// window (with the border row/column), then a 3x3 weighted blend of
/// the statistics with the current pixel produces `flt` in the
/// `center << 4` domain. Returns None only for an invalid radius or
/// bit depth; a zero radius is handled by the caller.
fn av1_sgr_box_pass(
  view : Av1RestorationSourceView,
  plane : Int,
  x0 : Int,
  y0 : Int,
  w : Int,
  h : Int,
  stripe : Int,
  r : Int,
  eps : Int,
  pass : Int,
  bit_depth : Int,
) -> Array[Int]? {
  if r <= 0 || r > 8 || eps < 0 || eps > 255 {
    return None
  }
  let n = (2 * r + 1) * (2 * r + 1)
  let n2e = n * n * eps
  if n2e == 0 {
    return None
  }
  let s = ((1 << 20) + n2e / 2) / n2e
  // A and B carry a one-sample border: index (i+1)*(w+2) + (j+1).
  let a_arr : Array[Int] = Array::make((h + 2) * (w + 2), 0)
  let b_arr : Array[Int] = Array::make((h + 2) * (w + 2), 0)
  for i in -1..<(h + 1) {
    for j in -1..<(w + 1) {
      let mut a = 0
      let mut b = 0
      for dy in -r..<(r + 1) {
        for dx in -r..<(r + 1) {
          let c = av1_restoration_source_sample(view, plane, x0 + j + dx, y0 + i +
            dy, stripe)
          a = a + c * c
          b = b + c
        }
      }
      a = av1_lr_round_n(a, 2 * (bit_depth - 8))
      let d = av1_lr_round_n(b, bit_depth - 8)
      let diff = a * n - d * d
      let p = if diff > 0 { diff } else { 0 }
      let z = av1_lr_round_n(p * s, 20)
      let a2 = if z >= 255 {
        256
      } else if z == 0 {
        1
      } else {
        ((z << 8) + z / 2) / (z + 1)
      }
      let one_over_n = ((1 << 12) + n / 2) / n
      let b2 = ((1 << 8) - a2) * b * one_over_n
      a_arr[(i + 1) * (w + 2) + (j + 1)] = a2
      b_arr[(i + 1) * (w + 2) + (j + 1)] = av1_lr_round_n(b2, 12)
    }
  }
  let out : Array[Int] = Array::make(w * h, 0)
  for i in 0..<h {
    for j in 0..<w {
      let mut wa = 0
      let mut wb = 0
      for dy in -1..<2 {
        for dx in -1..<2 {
          let weight = if pass == 0 {
            if ((i + dy) & 1) != 0 {
              if dx == 0 {
                6
              } else {
                5
              }
            } else {
              0
            }
          } else {
            if dx == 0 || dy == 0 {
              4
            } else {
              3
            }
          }
          wa = wa +
            weight *
            a_arr[(i + dy + 1) * (w + 2) + (j + dx + 1)]
          wb = wb +
            weight *
            b_arr[(i + dy + 1) * (w + 2) + (j + dx + 1)]
        }
      }
      let shift = if pass == 0 && (i & 1) != 0 { 4 } else { 5 }
      let center = av1_restoration_source_sample(view, plane, x0 + j, y0 + i,
        stripe)
      out[i * w + j] = av1_lr_round_n(wa * center + wb, 8 + shift - 4)
    }
  }
  Some(out)
}

///|
/// Self-guided filter over one piece. A zero projection radius
/// substitutes the unshifted center pixel for that box-filtered term,
/// so only the coded weights still contribute.
fn av1_sgr_filter_piece(
  view : Av1RestorationSourceView,
  plane : Int,
  x0 : Int,
  y0 : Int,
  w : Int,
  h : Int,
  stripe : Int,
  set : Int,
  xqd : Array[Int],
  bit_depth : Int,
) -> Array[Int]? {
  if xqd.length() != 2 {
    return None
  }
  let (r0, eps0, r1, eps1) = match av1_sgr_params(set) {
    Some(value) => value
    None => return None
  }
  let w0 = xqd[0]
  let w1 = xqd[1]
  let w2 = (1 << 7) - w0 - w1
  let hi = (1 << bit_depth) - 1
  let flt0 = if r0 != 0 {
    match av1_sgr_box_pass(view, plane, x0, y0, w, h, stripe, r0, eps0, 0, bit_depth) {
      Some(value) => value
      None => return None
    }
  } else {
    Array::make(0, 0)
  }
  let flt1 = if r1 != 0 {
    match av1_sgr_box_pass(view, plane, x0, y0, w, h, stripe, r1, eps1, 1, bit_depth) {
      Some(value) => value
      None => return None
    }
  } else {
    Array::make(0, 0)
  }
  let out : Array[Int] = Array::make(w * h, 0)
  for i in 0..<h {
    for j in 0..<w {
      let u = av1_restoration_source_sample(view, plane, x0 + j, y0 + i, stripe) <<
        4
      let mut v = w1 * u
      if r0 != 0 {
        v = v + w0 * flt0[i * w + j]
      } else {
        v = v + w0 * u
      }
      if r1 != 0 {
        v = v + w2 * flt1[i * w + j]
      } else {
        v = v + w2 * u
      }
      out[i * w + j] = av1_lr_clip(0, hi, av1_lr_round_n(v, 4 + 7))
    }
  }
  Some(out)
}

///|
/// Filter one plane. The output starts as a copy of the input so None
/// units and None modes pass through unchanged; active units overwrite
/// their stripe-intersected filter rectangles. Returns None on invalid
/// unit parameters or geometry.
fn av1_restoration_filter_plane(
  plane_data : Array[Int],
  view : Av1RestorationSourceView,
  units : Array[Av1RestorationUnit?],
  layout : Av1RestorationLayout,
  plane : Int,
  subsampling_x : Bool,
  subsampling_y : Bool,
  bit_depth : Int,
) -> Array[Int]? {
  if plane < 0 || plane >= layout.config.modes.length() {
    return None
  }
  let mode = layout.config.modes[plane]
  if mode is Av1RestorationNone {
    return Some(plane_data)
  }
  let shift_x = if plane != 0 && subsampling_x { 1 } else { 0 }
  let shift_y = if plane != 0 && subsampling_y { 1 } else { 0 }
  let plane_width = (layout.upscaled_width + (1 << shift_x) - 1) >> shift_x
  let plane_height = (layout.frame_height + (1 << shift_y) - 1) >> shift_y
  if plane_width <= 0 || plane_height <= 0 {
    return None
  }
  let unit = layout.config.unit_sizes[plane]
  let cols = layout.unit_cols[plane]
  let rows = layout.unit_rows[plane]
  if cols <= 0 || rows <= 0 || units.length() != cols * rows {
    return None
  }
  if plane >= view.store.planes.length() {
    return None
  }
  let stripes = view.store.planes[plane]
  let o = if shift_y != 0 { 4 } else { 8 }
  let out : Array[Int] = plane_data.copy()
  for r in 0..<rows {
    let (ny0, ny1) = av1_lr_unit_cell(unit, plane_height, rows, r)
    let v_start = if ny0 > o { ny0 - o } else { 0 }
    let v_end = if ny1 < plane_height { ny1 - o } else { plane_height }
    if v_end <= v_start {
      continue
    }
    for c in 0..<cols {
      let (nx0, nx1) = av1_lr_unit_cell(unit, plane_width, cols, c)
      let w = nx1 - nx0
      if w <= 0 {
        continue
      }
      let entry = units[r * cols + c]
      let filtered : Array[(Int, Int, Array[Int])]? = match entry {
        Some(Av1RestorationUnitWiener(vertical, horizontal)) => {
          if vertical.length() != 3 || horizontal.length() != 3 {
            return None
          }
          Some(av1_wiener_collect_pieces(view, plane, nx0, w, v_start, v_end,
            stripes, vertical, horizontal, bit_depth))
        }
        Some(Av1RestorationUnitSgrproj(set, xqd)) => {
          if xqd.length() != 2 {
            return None
          }
          if xqd[0] < -96 || xqd[0] > 31 || xqd[1] < -32 || xqd[1] > 95 {
            return None
          }
          av1_sgr_collect_pieces(view, plane, nx0, w, v_start, v_end,
            stripes, set, xqd, bit_depth)
        }
        _ => continue
      }
      match filtered {
        Some(pieces) => {
          for piece in pieces {
            let (py0, py1, data) = piece
            let ph = py1 - py0
            for i in 0..<ph {
              for j in 0..<w {
                out[(py0 + i) * view.frame_strides[plane] + nx0 + j] = data[i * w +
                  j]
              }
            }
          }
        }
        None => return None
      }
    }
  }
  Some(out)
}

///|
/// Wiener-filter every stripe piece of one unit rectangle and return
/// the non-empty pieces as (y0, y1, data) triples.
fn av1_wiener_collect_pieces(
  view : Av1RestorationSourceView,
  plane : Int,
  nx0 : Int,
  w : Int,
  v_start : Int,
  v_end : Int,
  stripes : Av1RestorationPlaneStripes,
  vertical : Array[Int],
  horizontal : Array[Int],
  bit_depth : Int,
) -> Array[(Int, Int, Array[Int])] {
  let pieces : Array[(Int, Int, Array[Int])] = []
  for k in 0..<stripes.count {
    let py0 = if v_start > stripes.starts[k] {
      v_start
    } else {
      stripes.starts[k]
    }
    let py1 = if v_end < stripes.ends[k] {
      v_end
    } else {
      stripes.ends[k]
    }
    if py1 <= py0 {
      continue
    }
    let data = av1_wiener_filter_piece(view, plane, nx0, py0, w, py1 - py0, k,
      vertical, horizontal, bit_depth)
    pieces.push((py0, py1, data))
  }
  pieces
}

///|
/// SGR-filter every stripe piece of one unit rectangle.
fn av1_sgr_collect_pieces(
  view : Av1RestorationSourceView,
  plane : Int,
  nx0 : Int,
  w : Int,
  v_start : Int,
  v_end : Int,
  stripes : Av1RestorationPlaneStripes,
  set : Int,
  xqd : Array[Int],
  bit_depth : Int,
) -> Array[(Int, Int, Array[Int])]? {
  let pieces : Array[(Int, Int, Array[Int])] = []
  for k in 0..<stripes.count {
    let py0 = if v_start > stripes.starts[k] {
      v_start
    } else {
      stripes.starts[k]
    }
    let py1 = if v_end < stripes.ends[k] {
      v_end
    } else {
      stripes.ends[k]
    }
    if py1 <= py0 {
      continue
    }
    let data = match
      av1_sgr_filter_piece(view, plane, nx0, py0, w, py1 - py0, k, set, xqd,
        bit_depth) {
      Some(value) => value
      None => return None
    }
    pieces.push((py0, py1, data))
  }
  Some(pieces)
}

///|
/// Filter every plane of one frame into fresh output planes. The
/// source planes stay immutable; None-mode planes are returned as-is.
/// Returns None on invalid unit parameters, unit maps or geometry.
fn av1_restoration_filter_frame(
  view : Av1RestorationSourceView,
  units : Array[Array[Av1RestorationUnit?]],
  layout : Av1RestorationLayout,
  bit_depth : Int,
  monochrome : Bool,
  subsampling_x? : Bool = false,
  subsampling_y? : Bool = false,
) -> Array[Array[Int]]? {
  let num_planes = if monochrome { 1 } else { 3 }
  if units.length() != num_planes ||
    view.frame.length() != num_planes ||
    view.frame_strides.length() != num_planes ||
    layout.config.modes.length() != num_planes {
    return None
  }
  let out : Array[Array[Int]] = []
  for plane in 0..<num_planes {
    let filtered = match
      av1_restoration_filter_plane(view.frame[plane], view, units[plane], layout,
        plane, subsampling_x, subsampling_y, bit_depth) {
      Some(value) => value
      None => return None
    }
    out.push(filtered)
  }
  Some(out)
}
