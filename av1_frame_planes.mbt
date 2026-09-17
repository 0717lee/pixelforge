///|
/// Native-depth reconstructed frame. Coded planes retain the MI padding until
/// every tile has been assembled and the frame filters have completed.
priv struct Av1FramePlanes {
  width : Int
  height : Int
  coded_width : Int
  bit_depth : Int
  full_range : Bool
  matrix_coefficients : Int
  planes : Array[Array[Int]]
}

///|
fn av1_frame_crop(frame : Av1FramePlanes, plane : Int) -> Array[Int] {
  let divisor = if plane == 0 { 1 } else { 2 }
  let width = (frame.width + divisor - 1) / divisor
  let height = (frame.height + divisor - 1) / divisor
  let stride = frame.coded_width / divisor
  Array::makei(width * height, fn(i) {
    frame.planes[plane][i / width * stride + i % width]
  })
}

///|
fn av1_frame_to_rgba(frame : Av1FramePlanes) -> Image? {
  if frame.planes.length() == 1 {
    let samples = av1_frame_crop(frame, 0)
    let image = Image::new(frame.width, frame.height)
    let shift = frame.bit_depth - 8
    let black = if frame.full_range { 0 } else { 16 << shift }
    let range = if frame.full_range {
      (1 << frame.bit_depth) - 1
    } else {
      219 << shift
    }
    for i in 0..<samples.length() {
      let gray = clamp_byte(((samples[i] - black) * 255 + range / 2) / range)
      image.set_pixel(
        i % frame.width,
        i / frame.width,
        gray,
        gray,
        gray,
        b'\xFF',
      )
    }
    return Some(image)
  }
  av1_yuv420_highbd_to_rgba(
    frame.width,
    frame.height,
    av1_frame_crop(frame, 0),
    av1_frame_crop(frame, 1),
    av1_frame_crop(frame, 2),
    frame.bit_depth,
    full_range=frame.full_range,
    matrix_coefficients=frame.matrix_coefficients,
  )
}

///|
/// Validate superblock boundaries before multiplying untrusted coordinates.
/// The final boundary covers exactly the frame's superblock count; only its
/// visible pixel coordinate is clipped to the frame edge.
fn av1_frame_tile_starts(
  starts : Array[Int],
  superblock_pixels : Int,
  length : Int,
) -> Array[Int]? {
  if length <= 0 ||
    length > MAX_IMAGE_PIXELS ||
    (superblock_pixels != 64 && superblock_pixels != 128) ||
    starts.length() < 2 ||
    starts.length() > 1025 ||
    starts[0] != 0 {
    return None
  }
  let count = (length - 1) / superblock_pixels + 1
  if starts[starts.length() - 1] != count {
    return None
  }
  let output : Array[Int] = [0]
  for i in 1..<starts.length() {
    if starts[i] <= starts[i - 1] || starts[i] > count {
      return None
    }
    output.push(
      if i == starts.length() - 1 {
        length
      } else {
        starts[i] * superblock_pixels
      },
    )
  }
  Some(output)
}

///|
fn av1_frame_pixel_starts_valid(
  starts : Array[Int],
  length : Int,
  frame_filters : Bool,
) -> Bool {
  if starts.length() < 2 ||
    starts.length() > 1025 ||
    starts[0] != 0 ||
    starts[starts.length() - 1] != length {
    return false
  }
  for i in 1..<starts.length() {
    if starts[i] <= starts[i - 1] || starts[i] > length {
      return false
    }
    if i + 1 < starts.length() &&
      (starts[i] % 8 != 0 || (frame_filters && starts[i] % 64 != 0)) {
      return false
    }
  }
  true
}

///|
/// Entropy and prediction stay tile-local. Deblocking updates the assembled
/// native frame vertically then horizontally; CDEF reads that completed result.
/// Cropping and color conversion follow the frame filters.
fn av1_decode_tile_planes(
  width : Int,
  height : Int,
  col_starts : Array[Int],
  row_starts : Array[Int],
  payload : Array[Byte],
  tile_size_bytes : Int,
  base_q_idx : Int,
  disable_cdf_update : Bool,
  allow_screen_content_tools : Bool,
  full_range : Bool,
  matrix_coefficients : Int,
  use_128x128_superblock : Bool,
  bit_depth : Int,
  reduced_tx_set : Bool,
  enable_filter_intra : Bool,
  tx_mode_select : Bool,
  cdef : Av1CdefConfig?,
  monochrome? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  loop_filter? : Av1LoopFilterConfig? = None,
  restoration? : Av1RestorationConfig? = None,
  upscaled_width? : Int = 0,
) -> Av1FramePlanes? {
  let output_width = if upscaled_width == 0 { width } else { upscaled_width }
  if width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    output_width < width ||
    output_width > 65536 ||
    output_width > MAX_IMAGE_PIXELS / height ||
    output_width > width * 2 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    !av1_frame_pixel_starts_valid(
      col_starts,
      width,
      cdef is Some(_) || loop_filter is Some(_) || output_width != width,
    ) ||
    !av1_frame_pixel_starts_valid(
      row_starts,
      height,
      cdef is Some(_) || loop_filter is Some(_) || output_width != width,
    ) {
    return None
  }
  if cdef is Some(config) {
    if base_q_idx == 0 || !av1_cdef_config_valid(config, monochrome~) {
      return None
    }
  }
  if restoration is Some(config) {
    if !av1_restoration_config_valid(config, monochrome~) {
      return None
    }
  }
  let mut filter_active = false
  if loop_filter is Some(config) {
    if base_q_idx == 0 || !av1_loop_filter_config_valid(config) {
      return None
    }
    for plane in 0..<(if monochrome { 1 } else { 3 }) {
      for direction in 0..<2 {
        if av1_loop_filter_intra_level(config, plane, direction).unwrap() > 0 {
          filter_active = true
        }
      }
    }
  }
  let coded_width = av1_partition_coded_extent(width)
  let coded_height = av1_partition_coded_extent(height)
  if coded_width > MAX_IMAGE_PIXELS / coded_height {
    return None
  }
  let tiles = match
    av1_extract_tile_payloads(
      payload,
      col_starts.length() - 1,
      row_starts.length() - 1,
      tile_size_bytes,
    ) {
    Some(value) => value
    None => return None
  }
  let planes : Array[Array[Int]] = [Array::make(coded_width * coded_height, 0)]
  if !monochrome {
    planes.push(Array::make(coded_width / 2 * (coded_height / 2), 0))
    planes.push(Array::make(coded_width / 2 * (coded_height / 2), 0))
  }
  let tx_sizes : Array[Array[Int]] = []
  if filter_active {
    for plane in 0..<planes.length() {
      let divisor = if plane == 0 { 1 } else { 2 }
      tx_sizes.push(
        Array::make(coded_width / divisor / 4 * (coded_height / divisor / 4), 0),
      )
    }
  }
  let mi_cols = coded_width / 4
  let skips = Array::make(mi_cols * (coded_height / 4), 0)
  let cdef_cols = (coded_width + 63) / 64
  let indices = Array::make(cdef_cols * ((coded_height + 63) / 64), -1)
  for tile in tiles {
    let left = col_starts[tile.col]
    let top = row_starts[tile.row]
    let tile_width = col_starts[tile.col + 1] - left
    let tile_height = row_starts[tile.row + 1] - top
    let state = match
      av1_decode_intra_tile_state(
        tile_width,
        tile_height,
        tile.bytes,
        base_q_idx,
        disable_cdf_update,
        allow_screen_content_tools,
        use_128x128_superblock,
        bit_depth,
        reduced_tx_set,
        enable_filter_intra,
        tx_mode_select,
        cdef~,
        monochrome~,
        enable_intra_edge_filter~,
        track_loop_filter=filter_active,
      ) {
      Some(value) => value
      None => return None
    }
    for p in 0..<planes.length() {
      let divisor = if p == 0 { 1 } else { 2 }
      let source = state.planes[p]
      let stride = coded_width / divisor
      if filter_active {
        let source_cols = source.width / 4
        let target_cols = coded_width / divisor / 4
        for row in 0..<(source.height / 4) {
          for col in 0..<source_cols {
            tx_sizes[p][(top / divisor / 4 + row) * target_cols +
            left / divisor / 4 +
            col] = source.tx_sizes[row * source_cols + col]
          }
        }
      }
      for row in 0..<source.height {
        for col in 0..<source.width {
          planes[p][(top / divisor + row) * stride + left / divisor + col] = source.pixels[row *
            source.width +
            col]
        }
      }
    }
    for row in 0..<state.rows {
      for col in 0..<state.cols {
        skips[(top / 4 + row) * mi_cols + left / 4 + col] = state.skips[row *
          state.cols +
          col]
      }
    }
    if cdef is Some(_) {
      let tile_cdef_cols = (state.cols * 4 + 63) / 64
      for i in 0..<state.cdef_indices.length() {
        indices[(top / 64 + i / tile_cdef_cols) * cdef_cols +
        left / 64 +
        i % tile_cdef_cols] = state.cdef_indices[i]
      }
    }
  }
  if filter_active &&
    !av1_loop_filter_frame(
      loop_filter.unwrap(),
      width,
      height,
      coded_width,
      coded_height,
      bit_depth,
      planes,
      tx_sizes,
    ) {
    return None
  }
  let filtered = match cdef {
    None => planes
    Some(config) =>
      match
        av1_cdef_filter_frame(
          coded_width, coded_height, planes, skips, indices, config, bit_depth,
        ) {
        Some(value) => value
        None => return None
      }
  }
  let frame : Av1FramePlanes = {
    width,
    height,
    coded_width,
    bit_depth,
    full_range,
    matrix_coefficients,
    planes: filtered,
  }
  if output_width == width {
    Some(frame)
  } else {
    av1_frame_upscale(frame, output_width)
  }
}

///|
/// Upscale complete native rows after deblocking and CDEF. Source MI padding
/// participates in the horizontal taps; output padding is only buffer layout.
fn av1_frame_upscale(frame : Av1FramePlanes, width : Int) -> Av1FramePlanes? {
  let coded_width = av1_partition_coded_extent(width)
  let coded_height = av1_partition_coded_extent(frame.height)
  if coded_width > MAX_IMAGE_PIXELS / coded_height {
    return None
  }
  let planes : Array[Array[Int]] = []
  for plane in 0..<frame.planes.length() {
    let divisor = if plane == 0 { 1 } else { 2 }
    let source_width = (frame.width + divisor - 1) / divisor
    let target_width = (width + divisor - 1) / divisor
    let height = (frame.height + divisor - 1) / divisor
    let stride = coded_width / divisor
    let samples = match
      av1_superres_upscale_plane(
        frame.planes[plane],
        frame.coded_width / divisor,
        frame.coded_width / divisor,
        source_width,
        target_width,
        height,
        frame.bit_depth,
      ) {
      Some(value) => value
      None => return None
    }
    let padded = Array::makei(stride * (coded_height / divisor), i => {
      let row = if i / stride < height { i / stride } else { height - 1 }
      let col = if i % stride < target_width {
        i % stride
      } else {
        target_width - 1
      }
      samples[row * target_width + col]
    })
    planes.push(padded)
  }
  Some({
    width,
    height: frame.height,
    coded_width,
    planes,
    bit_depth: frame.bit_depth,
    full_range: frame.full_range,
    matrix_coefficients: frame.matrix_coefficients,
  })
}

///|
fn av1_decode_frame_planes(
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Av1FramePlanes? {
  let seq = match av1_sequence_info(data) {
    Some(value) => value
    None => return None
  }
  if !seq.monochrome &&
    seq.matrix_coefficients != 1 &&
    seq.matrix_coefficients != 2 &&
    seq.matrix_coefficients != 5 &&
    seq.matrix_coefficients != 6 {
    return None
  }
  let frames = av1_obu_payloads(data, 6)
  if frames.length() == 0 {
    return None
  }
  let frame = match
    av1_parse_stage1_frame(frames[0], seq, allow_highbd=true, allow_monochrome~) {
    Some(value) => value
    None => return None
  }
  let sb_size = if seq.use_128x128_superblock { 128 } else { 64 }
  let cols = match
    av1_frame_tile_starts(frame.tile_col_starts_sb, sb_size, frame.frame_width) {
    Some(value) => value
    None => return None
  }
  let rows = match
    av1_frame_tile_starts(frame.tile_row_starts_sb, sb_size, seq.height) {
    Some(value) => value
    None => return None
  }
  av1_decode_tile_planes(
    frame.frame_width,
    seq.height,
    cols,
    rows,
    frame.tile_payload,
    frame.tile_size_bytes,
    frame.base_q_idx,
    frame.disable_cdf_update,
    frame.allow_screen_content_tools,
    seq.full_range,
    seq.matrix_coefficients,
    seq.use_128x128_superblock,
    seq.bit_depth,
    frame.reduced_tx_set,
    seq.enable_filter_intra,
    frame.tx_mode_select,
    frame.cdef,
    monochrome=seq.monochrome,
    enable_intra_edge_filter=seq.enable_intra_edge_filter,
    loop_filter=frame.loop_filter,
    restoration=frame.restoration,
    upscaled_width=frame.upscaled_width,
  )
}
