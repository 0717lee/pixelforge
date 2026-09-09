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
}

/// Header facts available before tile entropy decoding. Reduced still-picture
/// headers imply a key frame and one displayed frame by construction.
pub(all) struct Av1FrameInfo {
  key_frame : Bool
  show_frame : Bool
  payload_size : Int
}

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

fn Av1Msac::new(data : Array[Byte]) -> Av1Msac {
  let mut value = 0
  let mut pos = 0
  for _ in 0..<4 {
    let incoming = if pos < data.length() {
      data[pos].to_int()
    } else {
      0
    }
    value = (value << 8) | incoming
    pos = pos + 1
  }
  { data, pos, range: 255, value, input_byte: 0, input_bits: 0 }
}

/// Decodes one AV1 boolean with an 8-bit probability (0..255), normalising the
/// interval as required by the MSAC range coder. Returns None at end of input.
fn Av1Msac::read_bool(self : Av1Msac, probability : Int) -> Int? {
  if probability < 0 || probability > 255 { return None }
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
fn av1_parse_color_config(
  reader : Av1BitReader,
  profile : Int,
) -> (Int, Bool, Bool, Bool)? {
  let high_bitdepth = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  let mut twelve_bit = false
  if profile == 2 && high_bitdepth {
    twelve_bit = match av1_u(reader, 1) {
      Some(v) => v == 1
      None => return None
    }
  }
  let bit_depth = if high_bitdepth {
    if twelve_bit {
      12
    } else {
      10
    }
  } else {
    8
  }
  let monochrome = if profile == 1 {
    false
  } else {
    match av1_u(reader, 1) {
      Some(v) => v == 1
      None => return None
    }
  }
  let color_description_present = match av1_u(reader, 1) {
    Some(v) => v == 1
    None => return None
  }
  if color_description_present {
    if !av1_skip(reader, 24) {
      return None
    }
  }
  if monochrome {
    if !av1_skip(reader, 1) {
      return None
    }
    return Some((bit_depth, true, true, true))
  }
  let (subsampling_x, subsampling_y) : (Bool, Bool) = if profile == 1 {
    (false, false)
  } else if profile == 2 && bit_depth == 12 {
    let sx = match av1_u(reader, 1) {
      Some(v) => v == 1
      None => return None
    }
    let sy = if sx {
      match av1_u(reader, 1) {
        Some(v) => v == 1
        None => return None
      }
    } else {
      false
    }
    if sx && sy {
      if !av1_skip(reader, 2) {
        return None
      }
    }
    (sx, sy)
  } else {
    if !av1_skip(reader, 2) {
      return None
    }
    (true, true)
  }
  if !av1_skip(reader, 1) {
    return None
  }
  Some((bit_depth, subsampling_x, subsampling_y, false))
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
  // Sequence tools preceding color_config().  Stage one accepts the values
  // but keeps them bounded; the frame parser will reject enabled filters or
  // super-resolution until their syntax is implemented.
  if !av1_skip(reader, 3) { return None } // use128x128, filter_intra, edge_filter
  if !av1_skip(reader, 3) { return None } // superres, CDEF, restoration
  let color = av1_parse_color_config(reader, profile)
  let (bit_depth, subsampling_x, subsampling_y, monochrome) = match color {
    Some(v) => v
    None => return None
  }
  if !av1_skip(reader, 1) { return None } // film_grain_params_present
  Some({
    profile,
    width,
    height,
    bit_depth,
    monochrome,
    subsampling_x,
    subsampling_y,
    reduced_still_picture_header: true,
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
/// Stage-one AV1 pixel decode entry point. Sequence parsing is implemented;
/// frame tile entropy decoding is intentionally reported as unavailable by
/// returning `None` until the next milestone lands.
pub fn av1_decode(_data : Array[Byte]) -> Image? {
  None
}
