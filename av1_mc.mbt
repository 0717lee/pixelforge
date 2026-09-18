/// Eight-tap subpel motion compensation (AV1 §7.11.3.4).
///
/// The kernel reads a stored reference plane with edge clamping rather than a
/// border extension: the specification's extension is itself a replication, and
/// the block-stage MV clamping keeps every access within reach, so clamping at
/// read time produces identical samples without widening any allocation.
///
/// Reference scaling is carried by the `xScale`/`yScale` terms and degenerates
/// exactly to a shift of `1 << 14` when the reference and the current frame
/// share dimensions.

///|
/// §7.11.3.4 fixed-point widths: reference scale, 1/16-pel block position and
/// the 1/1024-pel accumulator used for the two-pass walk.
let av1_ref_scale_shift : Int = 14

///|
let av1_subpel_bits : Int = 4

///|
let av1_scale_subpel_bits : Int = 10

///|
/// A walk position carries 1/16-pel in its low bits once the reference scale is
/// factored out.
let av1_subpel_phase_shift : Int = av1_scale_subpel_bits - av1_subpel_bits

///|
/// `EIGHTTAP_SMOOTH`, `EIGHTTAP`, `EIGHTTAP_SHARP`, `BILINEAR` and the two
/// four-tap substitutes that narrow blocks are forced onto.
let av1_interp_eighttap : Int = 0

///|
let av1_interp_eighttap_smooth : Int = 1

///|
let av1_interp_eighttap_sharp : Int = 2

///|
let av1_interp_fourtap : Int = 4

///|
let av1_interp_fourtap_smooth : Int = 5

///|
/// `SEL_SWITCHABLE`: the block codes its own filter, so the frame-level value
/// never reaches the kernel.
let av1_interp_switchable : Int = 4

///|
fn av1_mc_round2(value : Int, shift : Int) -> Int {
  (value + (1 << (shift - 1))) >> shift
}

///|
/// Sign-symmetric rounding: half-way values move away from zero.
fn av1_mc_round2_signed(value : Int, shift : Int) -> Int {
  if value >= 0 {
    av1_mc_round2(value, shift)
  } else {
    -av1_mc_round2(-value, shift)
  }
}

///|
fn av1_mc_clip(low : Int, high : Int, value : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// Blocks of four samples or fewer substitute a shorter kernel, because the
/// eight-tap support would reach further than the block is wide (AV1 §7.11.3.4).
fn av1_adjust_filter(interp : Int, size : Int) -> Int {
  if size > 4 {
    interp
  } else if interp == av1_interp_eighttap || interp == av1_interp_eighttap_sharp {
    av1_interp_fourtap
  } else if interp == av1_interp_eighttap_smooth {
    av1_interp_fourtap_smooth
  } else {
    interp
  }
}

///|
/// Everything the kernel needs about one block's prediction. `x`/`y` are the
/// block origin in the target plane's own units, and the motion vector is in
/// eighth-pel of the *reference* frame.
pub(all) struct Av1MotionRequest {
  reference : Av1RefFrame
  /// Current frame's entropy-coded dimensions; the scale ratios are formed
  /// against these.
  frame_width : Int
  frame_height : Int
  plane : Int
  x : Int
  y : Int
  width : Int
  height : Int
  mv_row : Int
  mv_col : Int
  /// Per-direction filter selection for the block being predicted. For OBMC the
  /// caller must pass the *neighbour's* filters, not the current block's.
  filter_vertical : Int
  filter_horizontal : Int
  compound : Bool
}

///|
/// Intermediate rounding exponents. Single-reference prediction keeps more
/// precision on the second pass because the result is written straight out;
/// a compound blend gives two of those bits back to the averaging stage.
fn av1_inter_rounds(bit_depth : Int, compound : Bool) -> (Int, Int) {
  let mut round0 = 3
  let mut round1 = if compound { 7 } else { 11 }
  if bit_depth == 12 {
    round0 = round0 + 2
    if !compound {
      round1 = round1 - 2
    }
  }
  (round0, round1)
}

///|
/// Stride of one plane inside a stored reference frame.
fn av1_ref_plane_stride(reference : Av1RefFrame, plane : Int) -> Int {
  if plane == 0 {
    reference.coded_width
  } else {
    (reference.coded_width + 1) >> reference.sub_x
  }
}

///|
/// Two-pass 8-tap interpolation of one reference list for one block, returned
/// row-major and unclipped: a compound blend or residual add decides where the
/// sample range is applied (AV1 §7.11.3.4).
fn av1_motion_compensate(request : Av1MotionRequest) -> Array[Int] {
  let reference = request.reference
  let (sub_x, sub_y) = if request.plane == 0 {
    (0, 0)
  } else {
    (reference.sub_x, reference.sub_y)
  }
  let (round0, round1) = av1_inter_rounds(reference.bit_depth, request.compound)
  let samples = reference.planes[request.plane]
  let stride = av1_ref_plane_stride(reference, request.plane)
  // Clamp against the visible reference extent, not the MI-padded allocation:
  // padding beyond the frame is undefined and must never be sampled.
  let last_x = ((reference.width + sub_x) >> sub_x) - 1
  let last_y = ((reference.height + sub_y) >> sub_y) - 1
  let half_sample = 1 << (av1_subpel_bits - 1)
  // A motion vector is eighth-pel; the walk is in 1/16-pel, hence the doubling.
  // Doubling first also makes the subsampling shift exact.
  let origin_x = (request.x << av1_subpel_bits) +
    ((2 * request.mv_col) >> sub_x) +
    half_sample
  let origin_y = (request.y << av1_subpel_bits) +
    ((2 * request.mv_row) >> sub_y) +
    half_sample
  let x_scale = (
      (reference.width << av1_ref_scale_shift) + request.frame_width / 2
    ) /
    request.frame_width
  let y_scale = (
      (reference.height << av1_ref_scale_shift) + request.frame_height / 2
    ) /
    request.frame_height
  let base_x = origin_x * x_scale - (half_sample << av1_ref_scale_shift)
  let base_y = origin_y * y_scale - (half_sample << av1_ref_scale_shift)
  let offset = (1 << (av1_scale_subpel_bits - av1_subpel_bits)) / 2
  let start_x = av1_mc_round2_signed(
      base_x,
      av1_ref_scale_shift + av1_subpel_bits - av1_scale_subpel_bits,
    ) +
    offset
  let start_y = av1_mc_round2_signed(
      base_y,
      av1_ref_scale_shift + av1_subpel_bits - av1_scale_subpel_bits,
    ) +
    offset
  let step_x = av1_mc_round2_signed(
    x_scale,
    av1_ref_scale_shift - av1_scale_subpel_bits,
  )
  let step_y = av1_mc_round2_signed(
    y_scale,
    av1_ref_scale_shift - av1_scale_subpel_bits,
  )
  let filter_h = av1_adjust_filter(request.filter_horizontal, request.width)
  let filter_v = av1_adjust_filter(request.filter_vertical, request.height)
  // Pass one filters horizontally over the rows the vertical pass will need,
  // which is why the intermediate buffer carries eight extra rows.
  let intermediate_height = (
      ((request.height - 1) * step_y + ((1 << av1_scale_subpel_bits) - 1)) >>
      av1_scale_subpel_bits
    ) +
    8
  let intermediate : Array[Int] = Array::make(
    intermediate_height * request.width,
    0,
  )
  for row in 0..<intermediate_height {
    let source_y = av1_mc_clip(
      0,
      last_y,
      (start_y >> av1_scale_subpel_bits) + row - 3,
    )
    for column in 0..<request.width {
      let position = start_x + step_x * column
      let phase = (position >> av1_subpel_phase_shift) & 15
      let taps = av1_subpel_filters[filter_h][phase]
      let mut sum = 0
      for tap in 0..<8 {
        let source_x = av1_mc_clip(
          0,
          last_x,
          (position >> av1_scale_subpel_bits) + tap - 3,
        )
        sum = sum + taps[tap] * samples[source_y * stride + source_x]
      }
      intermediate[row * request.width + column] = av1_mc_round2(sum, round0)
    }
  }
  // Pass two filters vertically out of the intermediate buffer. Only the
  // fractional part of the start position survives.
  let prediction : Array[Int] = Array::make(request.width * request.height, 0)
  for row in 0..<request.height {
    let position = (start_y & ((1 << av1_scale_subpel_bits) - 1)) + step_y * row
    let phase = (position >> av1_subpel_phase_shift) & 15
    let taps = av1_subpel_filters[filter_v][phase]
    let base = position >> av1_scale_subpel_bits
    for column in 0..<request.width {
      let mut sum = 0
      for tap in 0..<8 {
        sum = sum +
          taps[tap] * intermediate[(base + tap) * request.width + column]
      }
      prediction[row * request.width + column] = av1_mc_round2(sum, round1)
    }
  }
  prediction
}

///|
/// Write an unclipped prediction into a plane, replicating the frame edges the
/// way the reference reader does. Used by the block stage once the mode tree
/// can ask for it.
fn av1_motion_store(
  plane : Array[Int],
  plane_stride : Int,
  prediction : Array[Int],
  width : Int,
  height : Int,
  origin_x : Int,
  origin_y : Int,
  limit : Int,
) -> Unit {
  for row in 0..<height {
    for column in 0..<width {
      plane[(origin_y + row) * plane_stride + origin_x + column] = av1_mc_clip(
        0,
        limit,
        prediction[row * width + column],
      )
    }
  }
}
