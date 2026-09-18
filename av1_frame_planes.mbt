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
  /// Chroma subsampling shifts (0 or 1) for planes 1 and 2.
  sub_x : Int
  sub_y : Int
  planes : Array[Array[Int]]
}

///|
/// Per-axis chroma divisors for a plane: (1, 1) for luma, 2^sub otherwise.
/// The coded luma extent is always a multiple of eight, so a shift is exact.
fn av1_frame_plane_divisor(frame : Av1FramePlanes, plane : Int) -> (Int, Int) {
  if plane == 0 {
    (1, 1)
  } else {
    (1 << frame.sub_x, 1 << frame.sub_y)
  }
}

///|
fn av1_frame_crop(frame : Av1FramePlanes, plane : Int) -> Array[Int] {
  let (divisor_x, divisor_y) = av1_frame_plane_divisor(frame, plane)
  let width = (frame.width + divisor_x - 1) / divisor_x
  let height = (frame.height + divisor_y - 1) / divisor_y
  let stride = frame.coded_width / divisor_x
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
  av1_yuv_highbd_to_rgba(
    frame.width,
    frame.height,
    av1_frame_crop(frame, 0),
    av1_frame_crop(frame, 1),
    av1_frame_crop(frame, 2),
    frame.bit_depth,
    subsampling_x=frame.sub_x == 1,
    subsampling_y=frame.sub_y == 1,
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
/// Apply film grain to the visible picture after reconstruction.
///
/// Grain synthesis (AV1 §7.18.3) runs on the output picture, so the planes are
/// cropped first. The grained samples are scattered back into the same padded
/// layout, leaving the crop-on-convert path unchanged.
fn av1_frame_apply_grain(
  frame : Av1FramePlanes,
  params : Av1FilmGrainParams,
  monochrome : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
) -> Av1FramePlanes? {
  if !params.apply_grain {
    return Some(frame)
  }
  let cropped : Array[Array[Int]] = []
  for p in 0..<frame.planes.length() {
    cropped.push(av1_frame_crop(frame, p))
  }
  match
    av1_apply_film_grain_planes(
      cropped,
      frame.width,
      frame.height,
      frame.bit_depth,
      monochrome,
      subsampling_x,
      subsampling_y,
      frame.matrix_coefficients,
      params,
    ) {
    None => None
    Some(_) => {
      for p in 0..<frame.planes.length() {
        let (divisor_x, divisor_y) = av1_frame_plane_divisor(frame, p)
        let w = (frame.width + divisor_x - 1) / divisor_x
        let h = (frame.height + divisor_y - 1) / divisor_y
        let stride = frame.coded_width / divisor_x
        for y in 0..<h {
          for x in 0..<w {
            frame.planes[p][y * stride + x] = cropped[p][y * w + x]
          }
        }
      }
      Some(frame)
    }
  }
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
  superres_denom? : Int = 8,
  quant_deltas? : Av1QuantDeltas = {
    y_dc: 0,
    u_dc: 0,
    u_ac: 0,
    v_dc: 0,
    v_ac: 0,
  },
  subsampling_x? : Bool = true,
  subsampling_y? : Bool = true,
  inter? : Av1InterFrame? = None,
) -> (Av1FramePlanes, Av1RestorationStripeStore?)? {
  let output_width = if upscaled_width == 0 { width } else { upscaled_width }
  let sub_x = if subsampling_x { 1 } else { 0 }
  let sub_y = if subsampling_y { 1 } else { 0 }
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
  let chroma_coded_w = (coded_width + (1 << sub_x) - 1) >> sub_x
  let chroma_coded_h = (coded_height + (1 << sub_y) - 1) >> sub_y
  let planes : Array[Array[Int]] = [Array::make(coded_width * coded_height, 0)]
  if !monochrome {
    planes.push(Array::make(chroma_coded_w * chroma_coded_h, 0))
    planes.push(Array::make(chroma_coded_w * chroma_coded_h, 0))
  }
  let tx_sizes : Array[Array[Int]] = []
  if filter_active {
    for plane in 0..<planes.length() {
      let divisor_x = if plane == 0 { 1 } else { 1 << sub_x }
      let divisor_y = if plane == 0 { 1 } else { 1 << sub_y }
      tx_sizes.push(
        Array::make(
          coded_width / divisor_x / 4 * (coded_height / divisor_y / 4),
          0,
        ),
      )
    }
  }
  let mi_cols = coded_width / 4
  let skips = Array::make(mi_cols * (coded_height / 4), 0)
  let cdef_cols = (coded_width + 63) / 64
  let indices = Array::make(cdef_cols * ((coded_height + 63) / 64), -1)
  // Global loop-restoration unit grid, computed once for the frame. The
  // entropy ownership uses the unshifted grid against the upscaled
  // visible geometry; filtering later shifts vertical boundaries.
  let lr_layout = match restoration {
    Some(config) =>
      av1_restoration_layout(
        config,
        width,
        output_width,
        height,
        monochrome,
        !monochrome && sub_x == 1,
        !monochrome && sub_y == 1,
        superres_denom,
      )
    None => None
  }
  // Per-plane unit map indexed by unit_row * unit_cols + unit_col. None
  // marks an unread grid position, distinct from a decoded-None unit.
  let lr_units : Array[Array[Av1RestorationUnit?]] = []
  match lr_layout {
    Some(layout) =>
      for plane in 0..<layout.config.modes.length() {
        let count = layout.unit_cols[plane] * layout.unit_rows[plane]
        let column : Array[Av1RestorationUnit?] = Array::make(count, None)
        lr_units.push(column)
      }
    None => ()
  }
  for tile in tiles {
    let left = col_starts[tile.col]
    let top = row_starts[tile.row]
    let tile_width = col_starts[tile.col + 1] - left
    let tile_height = row_starts[tile.row + 1] - top
    let tile_inter = match inter {
      Some(config) =>
        Some(
          av1_inter_info(
            config,
            top / 4,
            left / 4,
            (top + av1_partition_coded_extent(tile_height)) / 4,
            (left + av1_partition_coded_extent(tile_width)) / 4,
          ),
        )
      None => None
    }
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
        restoration_layout=lr_layout,
        tile_origin_row_mi=top / 4,
        tile_origin_col_mi=left / 4,
        quant_deltas~,
        sub_x~,
        sub_y~,
        inter=tile_inter,
      ) {
      Some(value) => value
      None => return None
    }
    for p in 0..<planes.length() {
      let divisor_x = if p == 0 { 1 } else { 1 << sub_x }
      let divisor_y = if p == 0 { 1 } else { 1 << sub_y }
      let source = state.planes[p]
      let stride = coded_width / divisor_x
      if filter_active {
        let source_cols = source.width / 4
        let target_cols = coded_width / divisor_x / 4
        for row in 0..<(source.height / 4) {
          for col in 0..<source_cols {
            tx_sizes[p][(top / divisor_y / 4 + row) * target_cols +
            left / divisor_x / 4 +
            col] = source.tx_sizes[row * source_cols + col]
          }
        }
      }
      for row in 0..<source.height {
        for col in 0..<source.width {
          planes[p][(top / divisor_y + row) * stride + left / divisor_x + col] = source.pixels[row *
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
    if lr_layout is Some(_) {
      for record in state.restoration_units {
        let cols = lr_layout.unwrap().unit_cols[record.plane]
        let index = record.unit_row * cols + record.unit_col
        if lr_units[record.plane][index] is Some(_) {
          return None
        }
        lr_units[record.plane][index] = Some(record.unit)
      }
    }
  }
  // Every active plane's unit grid must be fully covered; an unread
  // position means missing syntax, not a decoded-None unit.
  if lr_layout is Some(layout) {
    for plane in 0..<lr_units.length() {
      if layout.config.modes[plane] is Av1RestorationNone {
        continue
      }
      for entry in lr_units[plane] {
        if entry is None {
          return None
        }
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
      sub_x~,
      sub_y~,
    ) {
    return None
  }
  // Save the deblocked rows at every internal stripe boundary before
  // CDEF modifies them: loop restoration reads these rows instead of
  // the neighbouring stripe's post-CDEF output. Only active when some
  // plane carries a non-None restoration mode; a failed save aborts the
  // decode because the boundary context would be lost.
  let stripe_store : Av1RestorationStripeStore? = match restoration {
    Some(config) =>
      if av1_restoration_active(config) {
        match
          av1_restoration_save_stripes(
            planes,
            coded_width,
            width,
            output_width,
            height,
            bit_depth,
            monochrome,
            sub_x~,
            sub_y~,
          ) {
          Some(value) => Some(value)
          None => return None
        }
      } else {
        None
      }
    None => None
  }
  let filtered = match cdef {
    None => planes
    Some(config) =>
      match
        av1_cdef_filter_frame(
          coded_width,
          coded_height,
          planes,
          skips,
          indices,
          config,
          bit_depth,
          sub_x~,
          sub_y~,
        ) {
        Some(value) => value
        None => return None
      }
  }
  let base : Av1FramePlanes = {
    width,
    height,
    coded_width,
    bit_depth,
    full_range,
    matrix_coefficients,
    sub_x,
    sub_y,
    planes: filtered,
  }
  let frame = if output_width == width {
    base
  } else {
    match av1_frame_upscale(base, output_width) {
      Some(value) => value
      None => return None
    }
  }
  // Apply loop restoration on the upscaled post-CDEF frame. The source
  // view keeps the saved deblocked rows and the unit parameters come
  // from the per-tile entropy state; an active configuration always
  // has a saved store, and filtering failure aborts the decode.
  let frame = match (stripe_store, lr_layout) {
    (Some(store), Some(layout)) => {
      let strides : Array[Int] = Array::makei(frame.planes.length(), fn(i) {
        if i == 0 {
          frame.coded_width
        } else {
          frame.coded_width >> frame.sub_x
        }
      })
      let view : Av1RestorationSourceView = {
        store,
        frame: frame.planes,
        frame_strides: strides,
      }
      match
        av1_restoration_filter_frame(
          view,
          lr_units,
          layout,
          bit_depth,
          monochrome,
          subsampling_x=!monochrome && frame.sub_x == 1,
          subsampling_y=!monochrome && frame.sub_y == 1,
        ) {
        Some(value) => {
          let planes = frame.planes
          for plane in 0..<value.length() {
            planes[plane] = value[plane]
          }
          {
            width: frame.width,
            height: frame.height,
            coded_width: frame.coded_width,
            bit_depth: frame.bit_depth,
            full_range: frame.full_range,
            matrix_coefficients: frame.matrix_coefficients,
            sub_x: frame.sub_x,
            sub_y: frame.sub_y,
            planes,
          }
        }
        None => return None
      }
    }
    _ => frame
  }
  Some((frame, stripe_store))
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
    sub_x: frame.sub_x,
    sub_y: frame.sub_y,
  })
}

///|
fn av1_decode_frame_planes(
  data : Array[Byte],
  allow_monochrome? : Bool = false,
  map? : Av1FrameMap,
  sequence? : Av1SequenceInfo,
) -> Av1FramePlanes? {
  // An AVIF image sequence carries the sequence header in the first item only,
  // so a later temporal unit may legitimately have none of its own.
  let seq = match sequence {
    Some(value) => value
    None => match av1_sequence_info(data) {
      Some(value) => value
      None => return None
    }
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
  // A caller decoding a whole sequence supplies its own buffer; a one-shot
  // image decode gets a scratch one, which is all a key frame needs.
  let state = match map {
    Some(value) => value
    None => av1_frame_map()
  }
  let header = match
    av1_parse_stage1_frame(
      frames[0],
      seq,
      allow_highbd=true,
      allow_monochrome~,
      map=state,
    ) {
    Some(value) => value
    None => return None
  }
  // An inter frame is only decodable once every tool it signals can be acted
  // on; a frame that uses one the block stage lacks is refused whole rather
  // than decoded as a prefix of itself.
  let inter = if header.frame_is_intra {
    None
  } else if !av1_inter_frame_supported(header, seq) {
    return None
  } else {
    match av1_inter_frame_of(header, seq, state) {
      Some(value) => Some(value)
      None => return None
    }
  }
  let film_grain = header.film_grain
  let frame_height = header.frame_height
  let sb_size = if seq.use_128x128_superblock { 128 } else { 64 }
  let cols = match
    av1_frame_tile_starts(
      header.tile_col_starts_sb,
      sb_size,
      header.frame_width,
    ) {
    Some(value) => value
    None => return None
  }
  let rows = match
    av1_frame_tile_starts(header.tile_row_starts_sb, sb_size, frame_height) {
    Some(value) => value
    None => return None
  }
  let (decoded, _stripe_store) = match
    av1_decode_tile_planes(
      header.frame_width,
      frame_height,
      cols,
      rows,
      header.tile_payload,
      header.tile_size_bytes,
      header.base_q_idx,
      header.disable_cdf_update,
      header.allow_screen_content_tools,
      seq.full_range,
      seq.matrix_coefficients,
      seq.use_128x128_superblock,
      seq.bit_depth,
      header.reduced_tx_set,
      seq.enable_filter_intra,
      header.tx_mode_select,
      header.cdef,
      monochrome=seq.monochrome,
      enable_intra_edge_filter=seq.enable_intra_edge_filter,
      loop_filter=header.loop_filter,
      restoration=header.restoration,
      upscaled_width=header.upscaled_width,
      superres_denom=header.superres_denom,
      quant_deltas=header.quant_deltas,
      subsampling_x=seq.subsampling_x,
      subsampling_y=seq.subsampling_y,
      inter~,
    ) {
    Some(value) => value
    None => return None
  }
  // The reference buffer keeps the grain-free reconstruction: AV1 applies film
  // grain only on the displayed picture, so a later frame must not predict
  // from noisy samples.
  av1_frame_map_update(state, header, decoded)
  // Film grain is the last step before colour conversion: it modifies the
  // displayed picture while the stored reference samples stay grain free.
  match film_grain {
    None => Some(decoded)
    Some(params) =>
      av1_frame_apply_grain(
        decoded,
        params,
        seq.monochrome,
        seq.subsampling_x,
        seq.subsampling_y,
      )
  }
}
