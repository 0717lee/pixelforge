/// Film-grain synthesis for reconstructed AV1 frames (AV1 spec section 7.18.3).
///
/// Synthesis runs on the visible output picture after the loop filters and
/// superres upscaling and before the colour conversion. Reference frames keep
/// grain-free samples, so the caller's planes are copied and never mutated.
///
/// The implementation mirrors the go-av1 reference (decode/filmgrain.go), whose
/// AR coefficient counts are confirmed by byte alignment on encoder output:
/// `numPosLuma = 2 * lag * (lag + 1)` for the luma coefficients plus one extra
/// chroma coefficient (the centre tap, used for the luma-average term) whenever
/// `num_y_points > 0`. See _refs/film_grain_sim.py.

///|
pub(all) struct Av1FilmGrainParams {
  apply_grain : Bool
  grain_seed : Int
  num_y_points : Int
  point_y_value : Array[Int]
  point_y_scaling : Array[Int]
  chroma_scaling_from_luma : Bool
  num_cb_points : Int
  point_cb_value : Array[Int]
  point_cb_scaling : Array[Int]
  num_cr_points : Int
  point_cr_value : Array[Int]
  point_cr_scaling : Array[Int]
  grain_scaling_minus8 : Int
  ar_coeff_lag : Int
  /// AR coefficients exactly as coded; the signed value is `entry - 128`.
  ar_coeffs_y : Array[Int]
  ar_coeffs_cb : Array[Int]
  ar_coeffs_cr : Array[Int]
  ar_coeff_shift_minus6 : Int
  grain_scale_shift : Int
  cb_mult : Int
  cb_luma_mult : Int
  cb_offset : Int
  cr_mult : Int
  cr_luma_mult : Int
  cr_offset : Int
  overlap_flag : Bool
  clip_to_restricted_range : Bool
}

///|
/// `(x + (1 << (n - 1))) >> n`, the AV1 round2() helper. Shifting by zero is
/// the identity, which 12-bit streams reach through `grain_scale_shift`.
fn av1_grain_round2(value : Int, shift : Int) -> Int {
  if shift <= 0 {
    value
  } else {
    (value + (1 << (shift - 1))) >> shift
  }
}

///|
fn av1_grain_clip3(low : Int, high : Int, value : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// Read an AR coefficient as a signed value, treating an unwritten entry as the
/// zero-valued `0 - 128` the reference's fixed-size arrays would supply.
fn av1_grain_coeff(coeffs : Array[Int], index : Int) -> Int {
  if index >= 0 && index < coeffs.length() {
    coeffs[index] - 128
  } else {
    -128
  }
}

///|
priv struct Av1GrainState {
  fg : Av1FilmGrainParams
  bit_depth : Int
  sub_x : Int
  sub_y : Int
  grain_min : Int
  grain_max : Int
  monochrome : Bool
  num_planes : Int
  mut random_register : Int
  /// Row-major 73x82 grain blocks; chroma keeps the same stride.
  luma_grain : Array[Int]
  cb_grain : Array[Int]
  cr_grain : Array[Int]
  /// Per-plane 256-entry scaling lookup tables, flattened.
  scaling : Array[Int]
}

///|
/// The 16-bit LFSR from section 7.18.3.1. `bits` selects the high bits of the
/// advanced register.
fn Av1GrainState::get_random_number(self : Av1GrainState, bits : Int) -> Int {
  let r = self.random_register
  let bit = ((r >> 0) ^ (r >> 1) ^ (r >> 3) ^ (r >> 12)) & 1
  let next = (r >> 1) | (bit << 15)
  let result = (next >> (16 - bits)) & ((1 << bits) - 1)
  self.random_register = next
  result
}

///|
/// Gaussian grain blocks plus the autoregressive pass (section 7.18.3.3).
fn Av1GrainState::generate(self : Av1GrainState) -> Unit {
  let fg = self.fg
  let shift = 12 - self.bit_depth + fg.grain_scale_shift
  self.random_register = fg.grain_seed
  for y in 0..<73 {
    for x in 0..<82 {
      let v = if fg.num_y_points > 0 {
        av1_gaussian_sequence[self.get_random_number(11)]
      } else {
        0
      }
      self.luma_grain[y * 82 + x] = av1_grain_round2(v, shift)
    }
  }
  let ar_shift = fg.ar_coeff_shift_minus6 + 6
  let lag = fg.ar_coeff_lag
  for y in 3..<73 {
    for x in 3..<79 {
      let mut s = 0
      let mut pos = 0
      let mut done = false
      let mut dr = 0 - lag
      while dr <= 0 && !done {
        let mut dc = 0 - lag
        while dc <= lag {
          if dr == 0 && dc == 0 {
            // The centre tap is never applied to luma; it terminates the scan.
            done = true
            break
          }
          let c = av1_grain_coeff(fg.ar_coeffs_y, pos)
          s = s + self.luma_grain[(y + dr) * 82 + (x + dc)] * c
          pos = pos + 1
          dc = dc + 1
        }
        dr = dr + 1
      }
      let idx = y * 82 + x
      self.luma_grain[idx] = av1_grain_clip3(
        self.grain_min,
        self.grain_max,
        self.luma_grain[idx] + av1_grain_round2(s, ar_shift),
      )
    }
  }
  if self.monochrome {
    return
  }
  let chroma_w = if self.sub_x == 1 { 44 } else { 82 }
  let chroma_h = if self.sub_y == 1 { 38 } else { 73 }
  self.random_register = fg.grain_seed ^ 0xb524
  for y in 0..<chroma_h {
    for x in 0..<chroma_w {
      let v = if fg.num_cb_points > 0 || fg.chroma_scaling_from_luma {
        av1_gaussian_sequence[self.get_random_number(11)]
      } else {
        0
      }
      self.cb_grain[y * 82 + x] = av1_grain_round2(v, shift)
    }
  }
  self.random_register = fg.grain_seed ^ 0x49d8
  for y in 0..<chroma_h {
    for x in 0..<chroma_w {
      let v = if fg.num_cr_points > 0 || fg.chroma_scaling_from_luma {
        av1_gaussian_sequence[self.get_random_number(11)]
      } else {
        0
      }
      self.cr_grain[y * 82 + x] = av1_grain_round2(v, shift)
    }
  }
  for y in 3..<chroma_h {
    for x in 3..<(chroma_w - 3) {
      let mut s0 = 0
      let mut s1 = 0
      let mut pos = 0
      let mut done = false
      let mut dr = 0 - lag
      while dr <= 0 && !done {
        let mut dc = 0 - lag
        while dc <= lag {
          let c0 = av1_grain_coeff(fg.ar_coeffs_cb, pos)
          let c1 = av1_grain_coeff(fg.ar_coeffs_cr, pos)
          if dr == 0 && dc == 0 {
            if fg.num_y_points > 0 {
              let luma_x = ((x - 3) << self.sub_x) + 3
              let luma_y = ((y - 3) << self.sub_y) + 3
              let mut luma = 0
              for i in 0..<(self.sub_y + 1) {
                for j in 0..<(self.sub_x + 1) {
                  luma = luma +
                    self.luma_grain[(luma_y + i) * 82 + (luma_x + j)]
                }
              }
              luma = av1_grain_round2(luma, self.sub_x + self.sub_y)
              s0 = s0 + luma * c0
              s1 = s1 + luma * c1
            }
            done = true
            break
          }
          s0 = s0 + self.cb_grain[(y + dr) * 82 + (x + dc)] * c0
          s1 = s1 + self.cr_grain[(y + dr) * 82 + (x + dc)] * c1
          pos = pos + 1
          dc = dc + 1
        }
        dr = dr + 1
      }
      let idx = y * 82 + x
      self.cb_grain[idx] = av1_grain_clip3(
        self.grain_min,
        self.grain_max,
        self.cb_grain[idx] + av1_grain_round2(s0, ar_shift),
      )
      self.cr_grain[idx] = av1_grain_clip3(
        self.grain_min,
        self.grain_max,
        self.cr_grain[idx] + av1_grain_round2(s1, ar_shift),
      )
    }
  }
}

///|
/// Interpolate the per-plane scaling function (section 7.18.3.5).
fn Av1GrainState::init_scaling(self : Av1GrainState) -> Unit {
  let fg = self.fg
  for plane in 0..<self.num_planes {
    let num_points = if plane == 0 || fg.chroma_scaling_from_luma {
      fg.num_y_points
    } else if plane == 1 {
      fg.num_cb_points
    } else {
      fg.num_cr_points
    }
    if num_points == 0 {
      continue
    }
    let xs = if plane == 0 || fg.chroma_scaling_from_luma {
      fg.point_y_value
    } else if plane == 1 {
      fg.point_cb_value
    } else {
      fg.point_cr_value
    }
    let ys = if plane == 0 || fg.chroma_scaling_from_luma {
      fg.point_y_scaling
    } else if plane == 1 {
      fg.point_cb_scaling
    } else {
      fg.point_cr_scaling
    }
    let base = plane * 256
    for x in 0..<xs[0] {
      self.scaling[base + x] = ys[0]
    }
    for i in 0..<(num_points - 1) {
      let delta_y = ys[i + 1] - ys[i]
      let delta_x = xs[i + 1] - xs[i]
      if delta_x <= 0 {
        continue
      }
      let delta = delta_y * ((65536 + (delta_x >> 1)) / delta_x)
      for x in 0..<delta_x {
        let v = ys[i] + ((x * delta + 32768) >> 16)
        self.scaling[base + xs[i] + x] = v
      }
    }
    let last_x = xs[num_points - 1]
    let last_y = ys[num_points - 1]
    for x in last_x..<256 {
      self.scaling[base + x] = last_y
    }
  }
}

///|
/// Sample the scaling table, interpolating between entries for high bit depths.
fn Av1GrainState::scale_lut(
  self : Av1GrainState,
  plane : Int,
  index : Int,
) -> Int {
  let shift = self.bit_depth - 8
  let x = index >> shift
  let rem = index - (x << shift)
  let base = plane * 256
  if self.bit_depth == 8 || x >= 255 {
    self.scaling[base + x]
  } else {
    let start = self.scaling[base + x]
    let end = self.scaling[base + x + 1]
    start + av1_grain_round2((end - start) * rem, shift)
  }
}

///|
/// Build the noise image from pseudo-random grain blocks and add it to the
/// frame (section 7.18.3.6). The 32-row luma stripes (16 chroma rows) are
/// streamed: only the previous stripe is retained for the vertical overlap,
/// which keeps the working set proportional to one stripe instead of the
/// whole picture.
fn Av1GrainState::add_noise(
  self : Av1GrainState,
  planes : Array[Array[Int]],
  w : Int,
  h : Int,
  matrix_coefficients : Int,
) -> Unit {
  let fg = self.fg
  let sub_x = self.sub_x
  let sub_y = self.sub_y
  let overlap = fg.overlap_flag
  let gmin = self.grain_min
  let gmax = self.grain_max
  let plane_sub_x = fn(plane : Int) -> Int { if plane > 0 { sub_x } else { 0 } }
  let plane_sub_y = fn(plane : Int) -> Int { if plane > 0 { sub_y } else { 0 } }
  let grain_at = fn(plane : Int, y : Int, x : Int) -> Int {
    if plane == 0 {
      self.luma_grain[y * 82 + x]
    } else if plane == 1 {
      self.cb_grain[y * 82 + x]
    } else {
      self.cr_grain[y * 82 + x]
    }
  }
  let mut num_stripes = 0
  let mut probe = 0
  while probe < (h + 1) / 2 {
    num_stripes = num_stripes + 1
    probe = probe + 16
  }
  if num_stripes <= 0 {
    return
  }
  // Stripe geometry per plane: 32 rows (16 for vertically subsampled chroma)
  // extended by two (one for subsampled) overlap rows.
  let stripe_rows : Array[Int] = []
  let stripe_height : Array[Int] = []
  let stripe_width : Array[Int] = []
  for plane in 0..<self.num_planes {
    let psx = plane_sub_x(plane)
    let psy = plane_sub_y(plane)
    stripe_rows.push(34 >> psy)
    stripe_height.push(1 << (5 - psy))
    stripe_width.push(((w + psx) >> psx) + 64)
  }
  let plane_w : Array[Int] = []
  let plane_h : Array[Int] = []
  for plane in 0..<self.num_planes {
    let psx = plane_sub_x(plane)
    let psy = plane_sub_y(plane)
    plane_w.push((w + psx) >> psx)
    plane_h.push((h + psy) >> psy)
  }
  let noise : Array[Array[Int]] = []
  for plane in 0..<self.num_planes {
    noise.push(Array::make(plane_w[plane] * plane_h[plane], 0))
  }
  let mut prev : Array[Array[Int]] = []
  let mut cur : Array[Array[Int]] = []
  for plane in 0..<self.num_planes {
    prev.push(Array::make(stripe_rows[plane] * stripe_width[plane], 0))
    cur.push(Array::make(stripe_rows[plane] * stripe_width[plane], 0))
  }
  let mut luma_num = 0
  let mut sy = 0
  while sy < (h + 1) / 2 {
    self.random_register = fg.grain_seed
    self.random_register = self.random_register ^
      (((luma_num * 37 + 178) & 255) << 8)
    self.random_register = self.random_register ^ ((luma_num * 173 + 105) & 255)
    let mut x = 0
    while x < (w + 1) / 2 {
      let rand = self.get_random_number(8)
      let offset_x = rand >> 4
      let offset_y = rand & 15
      for plane in 0..<self.num_planes {
        let psx = plane_sub_x(plane)
        let psy = plane_sub_y(plane)
        let off_x = if psx == 1 { 6 + offset_x } else { 9 + offset_x * 2 }
        let off_y = if psy == 1 { 6 + offset_y } else { 9 + offset_y * 2 }
        let dest = cur[plane]
        let dest_w = stripe_width[plane]
        for i in 0..<(34 >> psy) {
          for j in 0..<(34 >> psx) {
            let mut gg = grain_at(plane, off_y + i, off_x + j)
            if psx == 0 {
              let idx = x * 2 + j
              if j < 2 && overlap && x > 0 {
                let old = dest[i * dest_w + idx]
                gg = if j == 0 {
                  old * 27 + gg * 17
                } else {
                  old * 17 + gg * 27
                }
                gg = av1_grain_clip3(gmin, gmax, av1_grain_round2(gg, 5))
              }
              dest[i * dest_w + idx] = gg
            } else {
              let idx = x + j
              if j == 0 && overlap && x > 0 {
                let old = dest[i * dest_w + idx]
                gg = old * 23 + gg * 22
                gg = av1_grain_clip3(gmin, gmax, av1_grain_round2(gg, 5))
              }
              dest[i * dest_w + idx] = gg
            }
          }
        }
      }
      x = x + 16
    }
    // Blend this stripe's rows into the noise image, overlapping vertically
    // with the previous stripe when the flag is set.
    for plane in 0..<self.num_planes {
      let psy = plane_sub_y(plane)
      let dest = noise[plane]
      let dest_w = plane_w[plane]
      let rows = stripe_height[plane]
      let stripe_w = stripe_width[plane]
      for i in 0..<rows {
        let y = (luma_num << (5 - psy)) + i
        if y >= plane_h[plane] {
          continue
        }
        for x in 0..<dest_w {
          let mut gg = cur[plane][i * stripe_w + x]
          if psy == 0 {
            if i < 2 && luma_num > 0 && overlap {
              let old = prev[plane][(i + 32) * stripe_w + x]
              gg = if i == 0 { old * 27 + gg * 17 } else { old * 17 + gg * 27 }
              gg = av1_grain_clip3(gmin, gmax, av1_grain_round2(gg, 5))
            }
          } else if i < 1 && luma_num > 0 && overlap {
            let old = prev[plane][(i + 16) * stripe_w + x]
            gg = old * 23 + gg * 22
            gg = av1_grain_clip3(gmin, gmax, av1_grain_round2(gg, 5))
          }
          dest[y * dest_w + x] = gg
        }
      }
    }
    let swap = prev
    prev = cur
    cur = swap
    luma_num = luma_num + 1
    sy = sy + 16
  }
  // Final blend with the reconstructed samples.
  let bd_shift = self.bit_depth - 8
  let full_max = (256 << bd_shift) - 1
  let min_value = if fg.clip_to_restricted_range { 16 << bd_shift } else { 0 }
  let max_luma = if fg.clip_to_restricted_range {
    235 << bd_shift
  } else {
    full_max
  }
  let max_chroma = if !fg.clip_to_restricted_range {
    full_max
  } else if matrix_coefficients == 0 {
    max_luma
  } else {
    240 << bd_shift
  }
  let sample_max = (1 << self.bit_depth) - 1
  let scaling_shift = fg.grain_scaling_minus8 + 8
  let out_y = planes[0]
  let chroma_active = self.num_planes > 1 &&
    (
      fg.num_cb_points > 0 ||
      fg.num_cr_points > 0 ||
      fg.chroma_scaling_from_luma
    )
  if chroma_active {
    let cw = (w + sub_x) >> sub_x
    let ch = (h + sub_y) >> sub_y
    let out_u = planes[1]
    let out_v = planes[2]
    for y in 0..<ch {
      for x in 0..<cw {
        let luma_x = x << sub_x
        let luma_y = y << sub_y
        let mut average_luma = out_y[luma_y * w + luma_x]
        if sub_x == 1 {
          let next_x = if luma_x + 1 < w { luma_x + 1 } else { w - 1 }
          average_luma = av1_grain_round2(
            out_y[luma_y * w + luma_x] + out_y[luma_y * w + next_x],
            1,
          )
        }
        if fg.num_cb_points > 0 || fg.chroma_scaling_from_luma {
          let orig = out_u[y * cw + x]
          let mut merged = average_luma
          if !fg.chroma_scaling_from_luma {
            let combined = average_luma * (fg.cb_luma_mult - 128) +
              orig * (fg.cb_mult - 128)
            merged = av1_grain_clip3(
              0,
              sample_max,
              (combined >> 6) + ((fg.cb_offset - 256) << bd_shift),
            )
          }
          let n = av1_grain_round2(
            self.scale_lut(1, merged) * noise[1][y * cw + x],
            scaling_shift,
          )
          out_u[y * cw + x] = av1_grain_clip3(min_value, max_chroma, orig + n)
        }
        if fg.num_cr_points > 0 || fg.chroma_scaling_from_luma {
          let orig = out_v[y * cw + x]
          let mut merged = average_luma
          if !fg.chroma_scaling_from_luma {
            let combined = average_luma * (fg.cr_luma_mult - 128) +
              orig * (fg.cr_mult - 128)
            merged = av1_grain_clip3(
              0,
              sample_max,
              (combined >> 6) + ((fg.cr_offset - 256) << bd_shift),
            )
          }
          let n = av1_grain_round2(
            self.scale_lut(2, merged) * noise[2][y * cw + x],
            scaling_shift,
          )
          out_v[y * cw + x] = av1_grain_clip3(min_value, max_chroma, orig + n)
        }
      }
    }
  }
  if fg.num_y_points > 0 {
    for y in 0..<h {
      for x in 0..<w {
        let orig = out_y[y * w + x]
        let n = av1_grain_round2(
          self.scale_lut(0, orig) * noise[0][y * w + x],
          scaling_shift,
        )
        out_y[y * w + x] = av1_grain_clip3(min_value, max_luma, orig + n)
      }
    }
  }
}

///|
/// Apply film grain to already-cropped, tightly packed planes.
///
/// `planes` holds one (monochrome) or three planes at their visible sizes; the
/// arrays are modified in place. Returns None for unsupported geometry.
pub fn av1_apply_film_grain_planes(
  planes : Array[Array[Int]],
  width : Int,
  height : Int,
  bit_depth : Int,
  monochrome : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
  matrix_coefficients : Int,
  fg : Av1FilmGrainParams,
) -> Unit? {
  if !fg.apply_grain {
    return Some(())
  }
  if width <= 0 || height <= 0 || planes.length() == 0 {
    return None
  }
  if bit_depth != 8 && bit_depth != 10 && bit_depth != 12 {
    return None
  }
  let num_planes = if monochrome { 1 } else { 3 }
  if planes.length() < num_planes {
    return None
  }
  let sub_x = if monochrome || subsampling_x { 1 } else { 0 }
  let sub_y = if monochrome || subsampling_y { 1 } else { 0 }
  let grain_center = 128 << (bit_depth - 8)
  let state : Av1GrainState = {
    fg,
    bit_depth,
    sub_x,
    sub_y,
    grain_min: 0 - grain_center,
    grain_max: (256 << (bit_depth - 8)) - 1 - grain_center,
    monochrome,
    num_planes,
    random_register: 0,
    luma_grain: Array::make(73 * 82, 0),
    cb_grain: Array::make(73 * 82, 0),
    cr_grain: Array::make(73 * 82, 0),
    scaling: Array::make(3 * 256, 0),
  }
  state.generate()
  state.init_scaling()
  state.add_noise(planes, width, height, matrix_coefficients)
  Some(())
}
