/// Bounded, pure MoonBit AV1 bitstream foundation used by the AVIF decoder.
///
/// Parses low-overhead OBU headers and supported reduced-still sequences,
/// retaining native 8/10/12-bit color configuration and the distinction between
/// entropy-coded and displayed dimensions for the tile reconstruction stage.

///|
/// Parsed AV1 sequence configuration for the stage-one decoder.
pub(all) struct Av1SequenceInfo {
  profile : Int
  width : Int
  height : Int
  bit_depth : Int
  monochrome : Bool
  subsampling_x : Bool
  subsampling_y : Bool
  reduced_still_picture_header : Bool
  use_128x128_superblock : Bool
  enable_filter_intra : Bool
  enable_intra_edge_filter : Bool
  enable_superres : Bool
  enable_cdef : Bool
  enable_restoration : Bool
  full_range : Bool
  separate_uv_delta_q : Bool
  film_grain_params_present : Bool
  color_primaries : Int
  transfer_characteristics : Int
  matrix_coefficients : Int
  /// Inter-frame tool flags (AV1 §5.9.1). A reduced still-picture sequence
  /// signals none of them, so every default below is the reduced-still
  /// derivation rather than an unparse.
  still_picture : Bool
  enable_order_hint : Bool
  order_hint_bits : Int
  enable_ref_frame_mvs : Bool
  enable_warped_motion : Bool
  enable_dual_filter : Bool
  enable_jnt_comp : Bool
  enable_masked_compound : Bool
  enable_interintra_compound : Bool
  /// A `seq_force_*` value of 2 (SELECT) means the frame header picks the tool.
  seq_force_screen_content_tools : Int
  seq_force_integer_mv : Int
  frame_id_numbers_present : Bool
  delta_frame_id_length_minus_2 : Int
  additional_frame_id_length_minus_1 : Int
  decoder_model_info_present : Bool
  equal_picture_interval : Bool
  buffer_delay_length_minus_1 : Int
  buffer_removal_time_length_minus_1 : Int
  frame_presentation_time_length_minus_1 : Int
  operating_points_cnt_minus_1 : Int
  operating_point_idc : Array[Int]
  /// `frame_width_bits_minus_1` / `frame_height_bits_minus_1`: the field widths
  /// a `frame_size_override` re-reads the coded dimensions with.
  frame_width_bits_minus_1 : Int
  frame_height_bits_minus_1 : Int
}

///|
/// AV1 §3: a `seq_force_*` field of 2 defers the choice to the frame header.
let av1_select_screen_content_tools : Int = 2

///|
let av1_select_integer_mv : Int = 2

///|
/// Header facts available before tile entropy decoding. Reduced still-picture
/// headers imply a key frame and one displayed frame by construction.
pub(all) struct Av1FrameInfo {
  key_frame : Bool
  show_frame : Bool
  payload_size : Int
}

///|
/// The bounded input handed to the next AV1 tile-decoding stage. This is a
/// data boundary rather than an image: tile bytes are still entropy-coded and
/// must be reconstructed before an `Image` exists.
pub(all) struct Av1Stage1Input {
  /// Container/display width after superres; tile geometry uses frame_width.
  width : Int
  frame_width : Int
  superres_denom : Int
  height : Int
  bit_depth : Int
  monochrome : Bool
  header_bytes : Int
  base_q_idx : Int
  disable_cdf_update : Bool
  allow_screen_content_tools : Bool
  tx_mode_select : Bool
  reduced_tx_set : Bool
  cdef : Av1CdefConfig?
  loop_filter : Av1LoopFilterConfig?
  restoration : Av1RestorationConfig?
  tile_cols : Int
  tile_rows : Int
  tile_cols_log2 : Int
  tile_rows_log2 : Int
  /// Tile boundaries in superblock units, including the terminal boundary.
  tile_col_starts_sb : Array[Int]
  tile_row_starts_sb : Array[Int]
  tile_size_bytes : Int
  enable_filter_intra : Bool
  enable_intra_edge_filter : Bool
  full_range : Bool
  matrix_coefficients : Int
  use_128x128_superblock : Bool
  tile_payload : Array[Byte]
  /// Film-grain parameters parsed from the frame header, or None when the
  /// sequence disabled the tool. Applied after reconstruction.
  film_grain : Av1FilmGrainParams?
  /// Per-plane quantizer deltas; V differs from U only when the sequence
  /// enables `separate_uv_delta_q`.
  quant_deltas : Av1QuantDeltas
}

///|
/// Small AV1 MSAC boolean decoder. It is kept independent from frame syntax so
/// the tile decoder can adopt it without changing the public image API.
priv struct Av1Msac {
  data : Array[Byte]
  mut pos : Int
  mut range : Int
  mut value : Int
  mut input_byte : Int
  mut input_bits : Int
}

///|
fn Av1Msac::new(data : Array[Byte]) -> Av1Msac {
  let mut value = 0
  let mut pos = 0
  for _ in 0..<4 {
    let incoming = if pos < data.length() { data[pos].to_int() } else { 0 }
    value = (value << 8) | incoming
    pos = pos + 1
  }
  { data, pos, range: 255, value, input_byte: 0, input_bits: 0, }
}

///|
/// Decodes one AV1 boolean with an 8-bit probability (0..255), normalising the
/// interval as required by the MSAC range coder. Returns None at end of input.
fn Av1Msac::read_bool(self : Av1Msac, probability : Int) -> Int? {
  if probability < 0 || probability > 255 {
    return None
  }
  let split = 1 + (((self.range - 1) * probability) >> 8)
  let bit = if self.value < split {
    self.range = split
    0
  } else {
    self.value = self.value - split
    self.range = self.range - split
    1
  }
  while self.range < 128 {
    self.range = self.range << 1
    self.value = self.value << 1
    if self.input_bits == 0 && self.pos < self.data.length() {
      self.input_byte = self.data[self.pos].to_int()
      self.pos = self.pos + 1
      self.input_bits = 8
    }
    if self.input_bits > 0 {
      self.value = self.value | ((self.input_byte >> 7) & 1)
      self.input_byte = (self.input_byte << 1) & 0xFF
      self.input_bits = self.input_bits - 1
    }
  }
  Some(bit)
}

///|
/// Reads one boolean from an isolated MSAC payload. This small public probe is
/// also useful for conformance tests while the full tile decoder is developed.
pub fn av1_msac_read_first(data : Array[Byte], probability : Int) -> Int? {
  let reader = Av1Msac::new(data)
  reader.read_bool(probability)
}

///|
/// Reads AV1 bits in specification (MSB-first) order.
priv struct Av1BitReader {
  data : Array[Byte]
  mut bit_pos : Int
}

///|
fn Av1BitReader::new(data : Array[Byte]) -> Av1BitReader {
  { data, bit_pos: 0, }
}

///|
fn Av1BitReader::read(self : Av1BitReader, count : Int) -> Int? {
  if count < 0 || count > 31 || self.bit_pos + count > self.data.length() * 8 {
    return None
  }
  let mut value = 0
  for _ in 0..<count {
    let byte_pos = self.bit_pos / 8
    let shift = 7 - self.bit_pos % 8
    value = (value << 1) | ((self.data[byte_pos].to_int() >> shift) & 1)
    self.bit_pos = self.bit_pos + 1
  }
  Some(value)
}

///|
fn av1_u(reader : Av1BitReader, count : Int) -> Int? {
  reader.read(count)
}

///|
fn av1_skip(reader : Av1BitReader, count : Int) -> Bool {
  match reader.read(count) {
    Some(_) => true
    None => false
  }
}

///|
fn av1_leb128(data : Array[Byte], start : Int, end : Int) -> (Int, Int)? {
  let mut value = 0
  let mut shift = 0
  let mut pos = start
  while pos < end && shift <= 28 {
    let byte = data[pos].to_int()
    value = value | ((byte & 0x7F) << shift)
    pos = pos + 1
    if (byte & 0x80) == 0 {
      return Some((value, pos))
    }
    shift = shift + 7
  }
  None
}

///|
fn av1_obu_payloads(
  data : Array[Byte],
  wanted_type : Int,
) -> Array[Array[Byte]] {
  let out : Array[Array[Byte]] = []
  let mut pos = 0
  while pos < data.length() {
    if pos >= data.length() {
      break
    }
    let header = data[pos].to_int()
    pos = pos + 1
    if (header & 0x80) != 0 || (header & 0x01) != 0 {
      break
    }
    let obu_type = (header >> 3) & 0x0F
    let extension = (header >> 2) & 1
    let has_size = (header >> 1) & 1
    if extension == 1 {
      if pos >= data.length() {
        break
      }
      pos = pos + 1
    }
    let payload_len = if has_size == 1 {
      match av1_leb128(data, pos, data.length()) {
        Some((n, next)) => {
          pos = next
          n
        }
        None => break
      }
    } else {
      data.length() - pos
    }
    if payload_len < 0 || pos + payload_len > data.length() {
      break
    }
    if obu_type == wanted_type {
      let payload : Array[Byte] = []
      for i in pos..<(pos + payload_len) {
        payload.push(data[i])
      }
      out.push(payload)
    }
    pos = pos + payload_len
    if has_size == 0 {
      break
    }
  }
  out
}

///|
priv struct Av1ColorConfig {
  bit_depth : Int
  monochrome : Bool
  subsampling_x : Bool
  subsampling_y : Bool
  full_range : Bool
  separate_uv_delta_q : Bool
  primaries : Int
  transfer : Int
  matrix : Int
}

///|
fn av1_parse_color_config(
  reader : Av1BitReader,
  profile : Int,
) -> Av1ColorConfig? {
  let high = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  let twelve = if profile == 2 && high {
    match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
  } else {
    false
  }
  let bit_depth = if twelve { 12 } else if high { 10 } else { 8 }
  let monochrome = if profile == 1 {
    false
  } else {
    match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
  }
  let desc = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  let primaries = if desc {
    match reader.read(8) {
      Some(v) => v
      None => return None
    }
  } else {
    2
  }
  let transfer = if desc {
    match reader.read(8) {
      Some(v) => v
      None => return None
    }
  } else {
    2
  }
  let matrix = if desc {
    match reader.read(8) {
      Some(v) => v
      None => return None
    }
  } else {
    2
  }
  if monochrome {
    let full_range = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    return Some({
      bit_depth,
      monochrome,
      subsampling_x: true,
      subsampling_y: true,
      full_range,
      separate_uv_delta_q: false,
      primaries,
      transfer,
      matrix,
    })
  }
  let identity = primaries == 1 && transfer == 13 && matrix == 0
  let full_range = if identity {
    true
  } else {
    match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
  }
  let (sx, sy) = if identity || profile == 1 {
    (false, false)
  } else if profile == 0 {
    (true, true)
  } else if bit_depth == 12 {
    let x = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    let y = if x {
      match reader.read(1) {
        Some(v) => v == 1
        None => return None
      }
    } else {
      false
    }
    (x, y)
  } else {
    (true, false)
  }
  if sx && sy && reader.read(2) is None {
    return None
  }
  let separate = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  Some({
    bit_depth,
    monochrome,
    subsampling_x: sx,
    subsampling_y: sy,
    full_range,
    separate_uv_delta_q: separate,
    primaries,
    transfer,
    matrix,
  })
}

///|
/// Skips a 32-bit syntax element. `Av1BitReader::read` caps single reads at 31
/// bits, so wide fields are consumed as two halves.
fn av1_skip32(reader : Av1BitReader) -> Bool {
  av1_skip(reader, 16) && av1_skip(reader, 16)
}

///|
/// Skips `num_ticks_per_picture_minus_1`, coded as uvlc (AV1 §4.11): a run of
/// one bits counted as `i`, terminated by a zero bit, then `i` value bits.
fn av1_skip_uvlc(reader : Av1BitReader) -> Bool {
  let mut i = 0
  while i < 32 {
    match reader.read(1) {
      Some(0) => return av1_skip(reader, i)
      Some(_) => i = i + 1
      None => return false
    }
  }
  false
}

///|
/// Parses `sequence_header_obu` (AV1 §5.5.1). Both the reduced still-picture
/// and the general grammar are supported; the timing and operating-point fields
/// the frame header needs to skip its own optional sections are retained.
fn av1_parse_sequence_payload(payload : Array[Byte]) -> Av1SequenceInfo? {
  let reader = Av1BitReader::new(payload)
  let profile = match av1_u(reader, 3) {
    Some(v) => v
    None => return None
  }
  if profile > 2 {
    return None
  }
  let still_picture = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  let reduced = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  // Operating points (AV1 §5.5.1). A reduced still-picture header fixes the
  // single operating point at idc 0 and reads no presence flags at all.
  let mut decoder_model_info_present = false
  let mut equal_picture_interval = false
  let mut buffer_delay_length_minus_1 = 0
  let mut buffer_removal_time_length_minus_1 = 0
  let mut frame_presentation_time_length_minus_1 = 0
  let mut operating_points_cnt_minus_1 = 0
  let mut operating_point_idc : Array[Int] = [0]
  if reduced {
    if !av1_skip(reader, 5) {
      return None
    } // seq_level_idx[0]
  } else {
    let timing_info_present = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    if timing_info_present {
      if !av1_skip32(reader) {
        return None
      } // num_units_in_display_tick
      if !av1_skip32(reader) {
        return None
      } // time_scale
      equal_picture_interval = match reader.read(1) {
        Some(v) => v == 1
        None => return None
      }
      if equal_picture_interval && !av1_skip_uvlc(reader) {
        return None
      }
      decoder_model_info_present = match reader.read(1) {
        Some(v) => v == 1
        None => return None
      }
      if decoder_model_info_present {
        buffer_delay_length_minus_1 = match av1_u(reader, 5) {
          Some(v) => v
          None => return None
        }
        if !av1_skip32(reader) {
          return None
        } // num_units_in_decoding_tick
        buffer_removal_time_length_minus_1 = match av1_u(reader, 5) {
          Some(v) => v
          None => return None
        }
        frame_presentation_time_length_minus_1 = match av1_u(reader, 5) {
          Some(v) => v
          None => return None
        }
      }
    }
    let initial_display_delay_present = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    operating_points_cnt_minus_1 = match av1_u(reader, 5) {
      Some(v) => v
      None => return None
    }
    if operating_points_cnt_minus_1 >= 32 {
      return None
    }
    let idcs : Array[Int] = []
    for _ in 0..<=operating_points_cnt_minus_1 {
      let idc = match av1_u(reader, 12) {
        Some(v) => v
        None => return None
      }
      let level = match av1_u(reader, 5) {
        Some(v) => v
        None => return None
      }
      if level > 7 && !av1_skip(reader, 1) {
        return None
      } // seq_tier
      if decoder_model_info_present {
        let present = match reader.read(1) {
          Some(v) => v == 1
          None => return None
        }
        if present {
          let width = buffer_delay_length_minus_1 + 1
          if width > 31 ||
            !av1_skip(reader, width) ||
            !av1_skip(reader, width) ||
            !av1_skip(reader, 1) {
            return None
          }
        }
      }
      if initial_display_delay_present {
        let present = match reader.read(1) {
          Some(v) => v == 1
          None => return None
        }
        if present && !av1_skip(reader, 4) {
          return None
        } // initial_display_delay_minus_1
      }
      idcs.push(idc)
    }
    operating_point_idc = idcs
  }
  let width_bits = match av1_u(reader, 4) {
    Some(v) => v + 1
    None => return None
  }
  let height_bits = match av1_u(reader, 4) {
    Some(v) => v + 1
    None => return None
  }
  let frame_width_bits_minus_1 = width_bits - 1
  let frame_height_bits_minus_1 = height_bits - 1
  let width_minus_one = match av1_u(reader, width_bits) {
    Some(v) => v
    None => return None
  }
  let height_minus_one = match av1_u(reader, height_bits) {
    Some(v) => v
    None => return None
  }
  let width = width_minus_one + 1
  let height = height_minus_one + 1
  if width <= 0 || height <= 0 || width > 65536 || height > 65536 {
    return None
  }
  // Frame identification (AV1 §5.5.1). Absent from a reduced still header.
  let mut frame_id_numbers_present = false
  let mut delta_frame_id_length_minus_2 = 0
  let mut additional_frame_id_length_minus_1 = 0
  if !reduced {
    frame_id_numbers_present = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    if frame_id_numbers_present {
      delta_frame_id_length_minus_2 = match av1_u(reader, 4) {
        Some(v) => v
        None => return None
      }
      additional_frame_id_length_minus_1 = match av1_u(reader, 3) {
        Some(v) => v
        None => return None
      }
    }
  }
  // Sequence tools preceding color_config(). Keep each flag explicit so the
  // frame stage can make a capability decision without guessing bit offsets.
  let use128 = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let filter_intra = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let edge_filter = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let mut interintra_compound = false
  let mut masked_compound = false
  let mut warped_motion = false
  let mut dual_filter = false
  let mut order_hint = false
  let mut jnt_comp = false
  let mut ref_frame_mvs = false
  let mut force_screen_content = av1_select_screen_content_tools
  let mut force_integer_mv = av1_select_integer_mv
  let mut order_hint_bits = 0
  if !reduced {
    interintra_compound = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    masked_compound = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    warped_motion = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    dual_filter = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    order_hint = match reader.read(1) {
      Some(v) => v == 1
      None => return None
    }
    if order_hint {
      jnt_comp = match reader.read(1) {
        Some(v) => v == 1
        None => return None
      }
      ref_frame_mvs = match reader.read(1) {
        Some(v) => v == 1
        None => return None
      }
    }
    // seq_choose_screen_content_tools: 1 defers the choice to every frame.
    force_screen_content = if reader.read(1) == Some(1) {
      av1_select_screen_content_tools
    } else {
      match av1_u(reader, 1) {
        Some(v) => v
        None => return None
      }
    }
    force_integer_mv = if force_screen_content > 0 {
      if reader.read(1) == Some(1) {
        av1_select_integer_mv
      } else {
        match av1_u(reader, 1) {
          Some(v) => v
          None => return None
        }
      }
    } else {
      av1_select_integer_mv
    }
    if order_hint {
      order_hint_bits = match av1_u(reader, 3) {
        Some(v) => v + 1
        None => return None
      }
    }
  }
  let superres = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let cdef = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let restoration = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let color = match av1_parse_color_config(reader, profile) {
    Some(v) => v
    None => return None
  }
  let film_grain = match reader.read(1) {
    Some(v) => v == 1
    None => return None
  }
  // sequence_header_obu ends with trailing_one_bit and zero padding.
  if reader.read(1) != Some(1) {
    return None
  }
  while reader.bit_pos % 8 != 0 {
    if reader.read(1) != Some(0) {
      return None
    }
  }
  Some({
    profile,
    width,
    height,
    bit_depth: color.bit_depth,
    monochrome: color.monochrome,
    subsampling_x: color.subsampling_x,
    subsampling_y: color.subsampling_y,
    reduced_still_picture_header: reduced,
    use_128x128_superblock: use128,
    enable_filter_intra: filter_intra,
    enable_intra_edge_filter: edge_filter,
    enable_superres: superres,
    enable_cdef: cdef,
    enable_restoration: restoration,
    full_range: color.full_range,
    separate_uv_delta_q: color.separate_uv_delta_q,
    film_grain_params_present: film_grain,
    color_primaries: color.primaries,
    transfer_characteristics: color.transfer,
    matrix_coefficients: color.matrix,
    still_picture,
    enable_order_hint: order_hint,
    order_hint_bits,
    enable_ref_frame_mvs: ref_frame_mvs,
    enable_warped_motion: warped_motion,
    enable_dual_filter: dual_filter,
    enable_jnt_comp: jnt_comp,
    enable_masked_compound: masked_compound,
    enable_interintra_compound: interintra_compound,
    seq_force_screen_content_tools: force_screen_content,
    seq_force_integer_mv: force_integer_mv,
    frame_id_numbers_present,
    delta_frame_id_length_minus_2,
    additional_frame_id_length_minus_1,
    decoder_model_info_present,
    equal_picture_interval,
    buffer_delay_length_minus_1,
    buffer_removal_time_length_minus_1,
    frame_presentation_time_length_minus_1,
    operating_points_cnt_minus_1,
    operating_point_idc,
    frame_width_bits_minus_1,
    frame_height_bits_minus_1,
  })
}

///|
/// Parses a raw AV1 low-overhead bitstream and returns its reduced sequence
/// header. The input is OBU data (the AVIF `av1C` configuration is not needed).
pub fn av1_sequence_info(data : Array[Byte]) -> Av1SequenceInfo? {
  let mut pos = 0
  while pos < data.length() {
    if pos >= data.length() {
      return None
    }
    let header = data[pos].to_int()
    pos = pos + 1
    if (header & 0x80) != 0 || (header & 0x01) != 0 {
      return None
    }
    let obu_type = (header >> 3) & 0x0F
    let extension = (header >> 2) & 1
    let has_size = (header >> 1) & 1
    if extension == 1 {
      if pos >= data.length() {
        return None
      }
      pos = pos + 1
    }
    let payload_len = if has_size == 1 {
      let size = av1_leb128(data, pos, data.length())
      match size {
        Some((n, next)) => {
          pos = next
          n
        }
        None => return None
      }
    } else {
      data.length() - pos
    }
    if payload_len < 0 || pos + payload_len > data.length() {
      return None
    }
    if obu_type == 1 {
      let payload : Array[Byte] = []
      for i in pos..<(pos + payload_len) {
        payload.push(data[i])
      }
      return av1_parse_sequence_payload(payload)
    }
    pos = pos + payload_len
    if has_size == 0 {
      break
    }
  }
  None
}

///|
/// Returns the reduced-still frame header envelope when a frame OBU follows a
/// supported sequence header. Tile payload bytes are retained only as a size
/// check; they are not interpreted as pixels by this milestone.
pub fn av1_frame_info(data : Array[Byte]) -> Av1FrameInfo? {
  let sequence = av1_sequence_info(data)
  match sequence {
    None => None
    Some(_) => {
      let frames = av1_obu_payloads(data, 6)
      if frames.length() == 0 {
        None
      } else {
        Some({
          key_frame: true,
          show_frame: true,
          payload_size: frames[0].length(),
        })
      }
    }
  }
}

///|
/// Extracts the first supported AV1 tile payload from an AVIF container.
///
/// The function validates the container, reduced-still sequence header, and
/// bounded frame envelope. It does not decode entropy symbols or fabricate
/// pixels; callers in the next milestone consume `tile_payload` with the
/// intra tile reconstruction pipeline.
pub fn avif_stage1_input(data : Array[Byte]) -> Av1Stage1Input? {
  let container = avif_container_parse(data)
  match container {
    None => None
    Some(c) => {
      let sequence = av1_sequence_info(c.payload)
      let seq = match sequence {
        None => return None
        Some(value) => value
      }
      if (c.bit_depth != 8 && c.bit_depth != 10 && c.bit_depth != 12) ||
        c.bit_depth != seq.bit_depth ||
        c.monochrome != seq.monochrome ||
        (
          !c.monochrome &&
          (
            c.subsampling_x != seq.subsampling_x ||
            c.subsampling_y != seq.subsampling_y
          )
        ) {
        return None
      }
      if c.width != seq.width ||
        c.height != seq.height ||
        (
          !seq.monochrome &&
          seq.matrix_coefficients != 1 &&
          seq.matrix_coefficients != 2 &&
          seq.matrix_coefficients != 5 &&
          seq.matrix_coefficients != 6
        ) {
        return None
      }
      let frames = av1_obu_payloads(c.payload, 6)
      if frames.length() == 0 {
        return None
      }
      let header = av1_parse_stage1_frame(
        frames[0],
        seq,
        allow_monochrome=true,
        allow_highbd=true,
      )
      match header {
        None => None
        Some(frame) =>
          Some({
            width: c.width,
            frame_width: frame.frame_width,
            superres_denom: frame.superres_denom,
            height: c.height,
            bit_depth: c.bit_depth,
            monochrome: seq.monochrome,
            header_bytes: frame.header_bytes,
            base_q_idx: frame.base_q_idx,
            disable_cdf_update: frame.disable_cdf_update,
            allow_screen_content_tools: frame.allow_screen_content_tools,
            tx_mode_select: frame.tx_mode_select,
            reduced_tx_set: frame.reduced_tx_set,
            cdef: frame.cdef,
            loop_filter: frame.loop_filter,
            restoration: frame.restoration,
            tile_cols: frame.tile_cols,
            tile_rows: frame.tile_rows,
            tile_cols_log2: frame.tile_cols_log2,
            tile_rows_log2: frame.tile_rows_log2,
            tile_col_starts_sb: frame.tile_col_starts_sb,
            tile_row_starts_sb: frame.tile_row_starts_sb,
            tile_size_bytes: frame.tile_size_bytes,
            enable_filter_intra: seq.enable_filter_intra,
            enable_intra_edge_filter: seq.enable_intra_edge_filter,
            full_range: seq.full_range,
            matrix_coefficients: seq.matrix_coefficients,
            use_128x128_superblock: seq.use_128x128_superblock,
            tile_payload: frame.tile_payload,
            film_grain: frame.film_grain,
            quant_deltas: frame.quant_deltas,
          })
      }
    }
  }
}
