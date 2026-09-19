///|
/// Reference and mode type of the block that owns the samples on the current
/// side of one edge (AV1 §7.14.4 inputs `RefFrames[row][col][0]` and
/// `YModes[row][col]`). Plane coordinates are converted back to the luma 4x4
/// grid the motion field lives on, and §7.14.2 then widens a chroma edge to the
/// bottom-right luma unit of its 2x2 group with `row | subY`, `col | subX`.
/// `modeType` is the normative one: any coded mode from NEARESTMV upwards except
/// the two global-motion modes, so intra blocks, GLOBALMV and never-written
/// neighbourhoods all report 0.
fn av1_loop_filter_block_state(
  field : Av1MotionField?,
  plane : Int,
  x : Int,
  y : Int,
  sub_x : Int,
  sub_y : Int,
) -> (Int, Int) {
  match field {
    None => (av1_intra_frame, 0)
    Some(motion) => {
      let scale_x = if plane == 0 { 1 } else { 1 << sub_x }
      let scale_y = if plane == 0 { 1 } else { 1 << sub_y }
      let col = (x * scale_x / 4) | sub_x
      let row = (y * scale_y / 4) | sub_y
      if row < 0 ||
        row >= motion.rows ||
        col < 0 ||
        col >= motion.cols {
        (av1_intra_frame, 0)
      } else {
        let unit = row * motion.cols + col
        let mode = motion.y_modes[unit]
        let mode_type = if mode >= av1_mode_nearest_mv &&
          mode != av1_mode_global_mv && mode != av1_mode_global_global_mv {
          1
        } else {
          0
        }
        (motion.refs[unit * 2], mode_type)
      }
    }
  }
}

///|
/// Filter one four-sample edge segment. The scalar kernel receives only the
/// selected filter's footprint: a four-tap edge must not inspect p2/q2.
fn av1_loop_filter_frame_segment(
  pixels : Array[Int],
  stride : Int,
  x : Int,
  y : Int,
  direction : Int,
  filter_width : Int,
  level : Int,
  sharpness : Int,
  bit_depth : Int,
) -> Bool {
  let radius = if filter_width == 4 {
    2
  } else if filter_width == 6 {
    3
  } else if filter_width == 8 {
    4
  } else {
    7
  }
  let normal_step = if direction == 0 { 1 } else { stride }
  let along_step = if direction == 0 { stride } else { 1 }
  for lane in 0..<4 {
    let origin = y * stride + x + lane * along_step
    let samples = Array::make(14, 0)
    for distance in (0 - radius)..<radius {
      let index = origin + distance * normal_step
      if index < 0 || index >= pixels.length() {
        return false
      }
      samples[7 + distance] = pixels[index]
    }
    let output = match
      av1_loop_filter_edge(samples, filter_width, level, sharpness, bit_depth) {
      Some(value) => value
      None => return false
    }
    for distance in (0 - radius)..<radius {
      pixels[origin + distance * normal_step] = output[7 + distance]
    }
  }
  true
}

///|
/// Frame deblocking after tiles have been assembled and before CDEF. Maps store
/// each actual TX's width | (height << 8) in every covered plane 4x4 cell,
/// including skipped transforms and coded MI padding.
///
/// The pinned libaom set_lpf_parameters uses the current transform's normal
/// dimension mask to locate a TU edge, then the smaller normal dimension of
/// its two transforms to choose Y 4/8/14 or UV 4/6. Intra skip flags never
/// suppress these edges. Tile boundaries participate like other TU edges.
///
/// `field` is the frame's motion field: an inter frame selects each edge's
/// strength from the reference and mode of the block beside it, so passing None
/// on an inter frame would silently deblock it with the intra deltas.
fn av1_loop_filter_frame(
  config : Av1LoopFilterConfig,
  width : Int,
  height : Int,
  coded_width : Int,
  coded_height : Int,
  bit_depth : Int,
  planes : Array[Array[Int]],
  tx_sizes : Array[Array[Int]],
  sub_x? : Int = 1,
  sub_y? : Int = 1,
  field? : Av1MotionField? = None,
) -> Bool {
  if !av1_loop_filter_config_valid(config) ||
    width <= 0 ||
    height <= 0 ||
    coded_width <= 0 ||
    coded_height <= 0 ||
    coded_width > MAX_IMAGE_PIXELS / coded_height ||
    width > coded_width ||
    height > coded_height ||
    coded_width % 8 != 0 ||
    coded_height % 8 != 0 ||
    coded_width - width >= 8 ||
    coded_height - height >= 8 ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    (planes.length() != 1 && planes.length() != 3) ||
    tx_sizes.length() != planes.length() {
    return false
  }
  for plane in 0..<planes.length() {
    let scale_x = if plane == 0 { 1 } else { 1 << sub_x }
    let scale_y = if plane == 0 { 1 } else { 1 << sub_y }
    let stride = coded_width / scale_x
    let rows = coded_height / scale_y
    if planes[plane].length() != stride * rows ||
      tx_sizes[plane].length() != stride / 4 * (rows / 4) {
      return false
    }
    for packed in tx_sizes[plane] {
      let tx_width = packed & 255
      let tx_height = packed >> 8
      let maximum = if plane == 0 { 64 } else { 32 }
      if !av1_tx_block_geometry_valid(tx_width, tx_height) ||
        tx_width > maximum ||
        tx_height > maximum {
        return false
      }
    }
  }
  for plane in 0..<planes.length() {
    let scale_x = if plane == 0 { 1 } else { 1 << sub_x }
    let scale_y = if plane == 0 { 1 } else { 1 << sub_y }
    let stride = coded_width / scale_x
    let visible_width = (width + scale_x - 1) / scale_x
    let visible_height = (height + scale_y - 1) / scale_y
    let cols = stride / 4
    let map = tx_sizes[plane]
    for direction in 0..<2 {
      // A whole direction can only be skipped when no reference and no mode
      // delta could lift any of its edges above zero.
      let mut inert = true
      for reference in 0..<8 {
        for mode_type in 0..<2 {
          match av1_loop_filter_edge_level(
              config,
              plane,
              direction,
              reference,
              mode_type,
            ) {
            Some(value) => if value > 0 { inert = false }
            None => return false
          }
        }
      }
      if inert {
        continue
      }
      let normal_extent = if direction == 0 {
        visible_width
      } else {
        visible_height
      }
      let along_extent = if direction == 0 {
        visible_height
      } else {
        visible_width
      }
      let mut along = 0
      while along < along_extent {
        let mut normal = 4
        while normal < normal_extent {
          let x = if direction == 0 { normal } else { along }
          let y = if direction == 0 { along } else { normal }
          let index = y / 4 * cols + x / 4
          let current = map[index]
          let dimension = if direction == 0 {
            current & 255
          } else {
            current >> 8
          }
          if (normal & (dimension - 1)) == 0 {
            let (reference, mode_type) = av1_loop_filter_block_state(
              field,
              plane,
              x,
              y,
              sub_x,
              sub_y,
            )
            let edge_level = match av1_loop_filter_edge_level(
                config,
                plane,
                direction,
                reference,
                mode_type,
              ) {
              Some(value) => value
              None => return false
            }
            let previous = map[index - (if direction == 0 { 1 } else { cols })]
            let previous_dimension = if direction == 0 {
              previous & 255
            } else {
              previous >> 8
            }
            let minimum = if dimension < previous_dimension {
              dimension
            } else {
              previous_dimension
            }
            let filter_width = if minimum == 4 {
              4
            } else if plane != 0 {
              6
            } else if minimum == 8 {
              8
            } else {
              14
            }
            if edge_level > 0 &&
              !av1_loop_filter_frame_segment(
                planes[plane],
                stride,
                x,
                y,
                direction,
                filter_width,
                edge_level,
                config.sharpness,
                bit_depth,
              ) {
              return false
            }
          }
          normal = normal + 4
        }
        along = along + 4
      }
    }
  }
  true
}
