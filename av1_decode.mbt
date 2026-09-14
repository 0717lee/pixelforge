/// Bounded, pure MoonBit AV1 bitstream foundation used by the AVIF decoder.
///
/// This module deliberately keeps the first AV1 milestone small and explicit:
/// it parses low-overhead OBU headers and a reduced-still-picture sequence
/// header, validates the stage-one profile (8-bit 4:2:0), and exposes the
/// dimensions and colour configuration to the container layer.  Tile entropy
/// decoding and inverse transforms are not silently approximated; `av1_decode`
/// returns `None` until those stages are available.

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
}

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
  width : Int
  height : Int
  bit_depth : Int
  header_bytes : Int
  base_q_idx : Int
  disable_cdf_update : Bool
  allow_screen_content_tools : Bool
  tx_mode_select : Bool
  reduced_tx_set : Bool
  tile_cols : Int
  tile_rows : Int
  tile_cols_log2 : Int
  tile_rows_log2 : Int
  /// Tile boundaries in superblock units, including the terminal boundary.
  tile_col_starts_sb : Array[Int]
  tile_row_starts_sb : Array[Int]
  tile_size_bytes : Int
  enable_filter_intra : Bool
  full_range : Bool
  matrix_coefficients : Int
  use_128x128_superblock : Bool
  tile_payload : Array[Byte]
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
fn av1_parse_sequence_payload(payload : Array[Byte]) -> Av1SequenceInfo? {
  let reader = Av1BitReader::new(payload)
  let profile = match av1_u(reader, 3) {
    Some(v) => v
    None => return None
  }
  if profile > 2 {
    return None
  }
  let _still_picture = match av1_u(reader, 1) {
    Some(v) => v
    None => return None
  }
  let reduced = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  // Stage one intentionally accepts only the reduced still-picture header.
  if !reduced {
    return None
  }
  // reduced_still_picture_header carries operating_point_idc=0 and a
  // five-bit seq_level_idx before the frame dimension fields.
  if !av1_skip(reader, 5) {
    return None
  }
  let width_bits = match av1_u(reader, 4) {
    Some(v) => v + 1
    None => return None
  }
  let height_bits = match av1_u(reader, 4) {
    Some(v) => v + 1
    None => return None
  }
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
    reduced_still_picture_header: true,
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
        c.monochrome ||
        !c.yuv420 {
        return None
      }
      if c.width != seq.width ||
        c.height != seq.height ||
        (
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
      let header = av1_parse_stage1_frame(frames[0], seq, allow_highbd=true)
      match header {
        None => None
        Some(frame) =>
          Some({
            width: c.width,
            height: c.height,
            bit_depth: c.bit_depth,
            header_bytes: frame.header_bytes,
            base_q_idx: frame.base_q_idx,
            disable_cdf_update: frame.disable_cdf_update,
            allow_screen_content_tools: frame.allow_screen_content_tools,
            tx_mode_select: frame.tx_mode_select,
            reduced_tx_set: frame.reduced_tx_set,
            tile_cols: frame.tile_cols,
            tile_rows: frame.tile_rows,
            tile_cols_log2: frame.tile_cols_log2,
            tile_rows_log2: frame.tile_rows_log2,
            tile_col_starts_sb: frame.tile_col_starts_sb,
            tile_row_starts_sb: frame.tile_row_starts_sb,
            tile_size_bytes: frame.tile_size_bytes,
            enable_filter_intra: seq.enable_filter_intra,
            full_range: seq.full_range,
            matrix_coefficients: seq.matrix_coefficients,
            use_128x128_superblock: seq.use_128x128_superblock,
            tile_payload: frame.tile_payload,
          })
      }
    }
  }
}
