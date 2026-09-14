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
  cdef_enabled : Bool,
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
      (starts[i] % 8 != 0 || (cdef_enabled && starts[i] % 64 != 0)) {
      return false
    }
  }
  true
}

///|
/// Entropy and prediction stay tile-local. Filtering reads a snapshot of the
/// complete frame, so taps may cross tile boundaries without observing an
/// already-filtered neighbour. There is no intermediate RGB conversion.
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
) -> Av1FramePlanes? {
  if width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    !av1_frame_pixel_starts_valid(col_starts, width, cdef is Some(_)) ||
    !av1_frame_pixel_starts_valid(row_starts, height, cdef is Some(_)) {
    return None
  }
  if cdef is Some(config) {
    if base_q_idx == 0 || !av1_cdef_config_valid(config, monochrome~) {
      return None
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
      ) {
      Some(value) => value
      None => return None
    }
    for p in 0..<planes.length() {
      let divisor = if p == 0 { 1 } else { 2 }
      let source = state.planes[p]
      let stride = coded_width / divisor
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
  Some({
    width,
    height,
    coded_width,
    bit_depth,
    full_range,
    matrix_coefficients,
    planes: filtered,
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
    av1_frame_tile_starts(frame.tile_col_starts_sb, sb_size, seq.width) {
    Some(value) => value
    None => return None
  }
  let rows = match
    av1_frame_tile_starts(frame.tile_row_starts_sb, sb_size, seq.height) {
    Some(value) => value
    None => return None
  }
  av1_decode_tile_planes(
    seq.width,
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
  )
}
