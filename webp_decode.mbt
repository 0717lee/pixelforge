/// Pure MoonBit decoder for the WebP lossless (VP8L) bitstream.
///
/// The decoder accepts a RIFF/WEBP container with a VP8L chunk and produces
/// PixelForge's RGBA8 image.  It implements the VP8L header, canonical
/// Huffman trees (including repeat codes), the subtract-green transform and
/// the color cache used by PixelForge's lossless encoder.  Spatial predictor
/// and color transforms are parsed and rejected for now; this keeps malformed
/// streams bounded while retaining a deterministic pure implementation for
/// files produced by `webp_encode`.

///|
priv suberror WebPDecodeError { Invalid }

///|
priv struct WebPDecodeBits {
  data : Array[Byte]
  end : Int
  mut pos : Int
  mut bits : Int
  mut value : Int
}

///|
fn WebPDecodeBits::new(data : Array[Byte], start : Int, end : Int) -> WebPDecodeBits {
  { data, end, pos: start, bits: 0, value: 0 }
}

///|
fn WebPDecodeBits::read(self : WebPDecodeBits, count : Int) -> Int raise WebPDecodeError {
  if count < 0 || count > 24 {
    raise WebPDecodeError::Invalid
  }
  while self.bits < count {
    if self.pos >= self.end {
      raise WebPDecodeError::Invalid
    }
    self.value = self.value | (self.data[self.pos].to_int() << self.bits)
    self.pos = self.pos + 1
    self.bits = self.bits + 8
  }
  let mask = if count == 0 { 0 } else { (1 << count) - 1 }
  let out = self.value & mask
  self.value = self.value >> count
  self.bits = self.bits - count
  out
}

///|
priv struct WebPDecodeCode {
  lengths : FixedArray[Int]
  codes : FixedArray[Int]
  single : Int?
  max_length : Int
}

///|
let webp_decode_code_order : FixedArray[Int] = [
  17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

///|
fn webp_decode_reverse_bits(value : Int, count : Int) -> Int {
  let mut result = 0
  let mut remaining = value
  for _ in 0..<count {
    result = (result << 1) | (remaining & 1)
    remaining = remaining >> 1
  }
  result
}

///|
fn webp_decode_make_code(lengths : FixedArray[Int]) -> WebPDecodeCode {
  let codes = FixedArray::make(lengths.length(), 0)
  let mut used = 0
  let mut only = 0
  let mut max_length = 0
  for symbol in 0..<lengths.length() {
    let length = lengths[symbol]
    if length > 0 {
      used = used + 1
      only = symbol
      if length > max_length {
        max_length = length
      }
    }
  }
  if used <= 1 {
    { lengths, codes, single: Some(only), max_length: 0 }
  } else {
    let count = FixedArray::make(max_length + 1, 0)
    for symbol in 0..<lengths.length() {
      let length = lengths[symbol]
      if length > 0 {
        count[length] = count[length] + 1
      }
    }
    let next = FixedArray::make(max_length + 1, 0)
    let mut code = 0
    for length in 1..<=max_length {
      code = (code + count[length - 1]) << 1
      next[length] = code
    }
    for symbol in 0..<lengths.length() {
      let length = lengths[symbol]
      if length > 0 {
        codes[symbol] = webp_decode_reverse_bits(next[length], length)
        next[length] = next[length] + 1
      }
    }
    { lengths, codes, single: None, max_length }
  }
}

///|
fn webp_decode_symbol(
  bits : WebPDecodeBits,
  code : WebPDecodeCode,
) -> Int raise WebPDecodeError {
  match code.single {
    Some(symbol) => symbol
    None => {
      let mut value = 0
      for length in 1..<=code.max_length {
        value = value | (bits.read(1) << (length - 1))
        for symbol in 0..<code.lengths.length() {
          if code.lengths[symbol] == length && code.codes[symbol] == value {
            return symbol
          }
        }
      }
      raise WebPDecodeError::Invalid
    }
  }
}

///|
fn webp_decode_prefix(
  bits : WebPDecodeBits,
  alphabet : Int,
) -> WebPDecodeCode raise WebPDecodeError {
  let lengths = FixedArray::make(alphabet, 0)
  if bits.read(1) == 1 {
    let count = bits.read(1) + 1
    let wide = bits.read(1)
    let first = bits.read(1 + 7 * wide)
    if first >= alphabet {
      raise WebPDecodeError::Invalid
    }
    lengths[first] = 1
    if count == 2 {
      let second = bits.read(8)
      if second >= alphabet || second == first {
        raise WebPDecodeError::Invalid
      }
      lengths[second] = 1
    }
    return webp_decode_make_code(lengths)
  }
  let code_lengths = FixedArray::make(19, 0)
  let count = 4 + bits.read(4)
  for i in 0..<count {
    code_lengths[webp_decode_code_order[i]] = bits.read(3)
  }
  let code_length_code = webp_decode_make_code(code_lengths)
  let use_default = bits.read(1) == 0
  let max_symbol = if use_default {
    alphabet
  } else {
    let nbits = 2 + 2 * bits.read(3)
    2 + bits.read(nbits)
  }
  if max_symbol < 0 || max_symbol > alphabet {
    raise WebPDecodeError::Invalid
  }
  let mut i = 0
  let mut previous = 0
  while i < max_symbol {
    let token = webp_decode_symbol(bits, code_length_code)
    if token <= 15 {
      lengths[i] = token
      previous = token
      i = i + 1
    } else if token == 16 {
      if i == 0 {
        raise WebPDecodeError::Invalid
      }
      let repeat = 3 + bits.read(2)
      if i + repeat > max_symbol {
        raise WebPDecodeError::Invalid
      }
      for _ in 0..<repeat {
        lengths[i] = previous
        i = i + 1
      }
    } else if token == 17 {
      let repeat = 3 + bits.read(3)
      if i + repeat > max_symbol {
        raise WebPDecodeError::Invalid
      }
      previous = 0
      for _ in 0..<repeat {
        lengths[i] = 0
        i = i + 1
      }
    } else if token == 18 {
      let repeat = 11 + bits.read(7)
      if i + repeat > max_symbol {
        raise WebPDecodeError::Invalid
      }
      previous = 0
      for _ in 0..<repeat {
        lengths[i] = 0
        i = i + 1
      }
    } else {
      raise WebPDecodeError::Invalid
    }
  }
  webp_decode_make_code(lengths)
}

///|
fn webp_decode_u32(data : Array[Byte], offset : Int) -> Int {
  data[offset].to_int() |
    (data[offset + 1].to_int() << 8) |
    (data[offset + 2].to_int() << 16) |
    (data[offset + 3].to_int() << 24)
}

///|
fn webp_decode_color_cache_index(color : Int, bits : Int) -> Int {
  ((color * 0x1E35A7BD) >> (32 - bits)) & ((1 << bits) - 1)
}

///|
fn webp_decode_impl(data : Array[Byte]) -> Image raise WebPDecodeError {
  if data.length() < 20 ||
    data[0] != b'R' || data[1] != b'I' || data[2] != b'F' || data[3] != b'F' ||
    data[8] != b'W' || data[9] != b'E' || data[10] != b'B' || data[11] != b'P' {
    raise WebPDecodeError::Invalid
  }
  let declared = webp_decode_u32(data, 4)
  if declared < 4 || declared + 8 > data.length() {
    raise WebPDecodeError::Invalid
  }
  let mut chunk = 12
  let mut payload_start = -1
  let mut payload_end = -1
  while chunk + 8 <= data.length() && chunk < declared + 8 {
    let size = webp_decode_u32(data, chunk + 4)
    let start = chunk + 8
    let end = start + size
    if end < start || end > data.length() || end > declared + 8 {
      raise WebPDecodeError::Invalid
    }
    if data[chunk] == b'V' && data[chunk + 1] == b'P' &&
      data[chunk + 2] == b'8' && data[chunk + 3] == b'L' {
      payload_start = start
      payload_end = end
      break
    }
    chunk = end + (size & 1)
  }
  if payload_start < 0 || payload_end - payload_start < 5 {
    raise WebPDecodeError::Invalid
  }
  let bits = WebPDecodeBits::new(data, payload_start, payload_end)
  if bits.read(8) != 0x2F {
    raise WebPDecodeError::Invalid
  }
  let width = bits.read(14) + 1
  let height = bits.read(14) + 1
  if width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
    width > MAX_IMAGE_PIXELS / height {
    raise WebPDecodeError::Invalid
  }
  ignore(bits.read(1)) // alpha_is_used; the alpha tree is always present
  if bits.read(3) != 0 {
    raise WebPDecodeError::Invalid
  }
  let mut subtract_green = false
  while bits.read(1) == 1 {
    let transform = bits.read(2)
    if transform == 2 {
      subtract_green = true
    } else {
      // Predictor and color transforms require a second image and are not
      // silently guessed.  Rejecting them is safer than returning pixels in
      // the wrong colors.
      raise WebPDecodeError::Invalid
    }
  }
  let cache_bits = if bits.read(1) == 1 { bits.read(4) } else { 0 }
  if cache_bits < 0 || cache_bits > 11 || bits.read(1) != 0 {
    raise WebPDecodeError::Invalid
  }
  let green_alphabet = 256 + 24 + (if cache_bits > 0 { 1 << cache_bits } else { 0 })
  let green_code = webp_decode_prefix(bits, green_alphabet)
  let red_code = webp_decode_prefix(bits, 256)
  let blue_code = webp_decode_prefix(bits, 256)
  let alpha_code = webp_decode_prefix(bits, 256)
  ignore(webp_decode_prefix(bits, 40))
  let image = Image::new(width, height)
  let cache_size = if cache_bits > 0 { 1 << cache_bits } else { 0 }
  let cache = FixedArray::make(cache_size, 0)
  let valid = FixedArray::make(cache_size, 0)
  for pixel in 0..<(width * height) {
    let green_or_cache = webp_decode_symbol(bits, green_code)
    let mut red = 0
    let mut green = 0
    let mut blue = 0
    let mut alpha = 255
    let mut encoded_red = 0
    let mut encoded_blue = 0
    if green_or_cache < 256 {
      green = green_or_cache
      encoded_red = webp_decode_symbol(bits, red_code)
      encoded_blue = webp_decode_symbol(bits, blue_code)
      alpha = webp_decode_symbol(bits, alpha_code)
      red = if subtract_green { (encoded_red + green) & 0xFF } else { encoded_red }
      blue = if subtract_green { (encoded_blue + green) & 0xFF } else { encoded_blue }
    } else if cache_bits > 0 && green_or_cache >= 280 {
      let index = green_or_cache - 280
      if index >= cache_size || valid[index] == 0 {
        raise WebPDecodeError::Invalid
      }
      let color = cache[index]
      alpha = (color >> 24) & 0xFF
      red = (color >> 16) & 0xFF
      green = (color >> 8) & 0xFF
      blue = color & 0xFF
      encoded_red = if subtract_green { (red - green) & 0xFF } else { red }
      encoded_blue = if subtract_green { (blue - green) & 0xFF } else { blue }
    } else {
      raise WebPDecodeError::Invalid
    }
    let offset = pixel * 4
    image.data[offset] = red.to_byte()
    image.data[offset + 1] = green.to_byte()
    image.data[offset + 2] = blue.to_byte()
    image.data[offset + 3] = alpha.to_byte()
    if cache_bits > 0 {
      let color = (alpha << 24) | (encoded_red << 16) | (green << 8) | encoded_blue
      let index = webp_decode_color_cache_index(color, cache_bits)
      cache[index] = color
      valid[index] = 1
    }
  }
  image
}

fn webp_decode_has_vp8l(data : Array[Byte]) -> Bool {
  if data.length() < 20 || data[0] != b'R' || data[1] != b'I' || data[2] != b'F' || data[3] != b'F' ||
    data[8] != b'W' || data[9] != b'E' || data[10] != b'B' || data[11] != b'P' { return false }
  let declared = webp_decode_u32(data, 4)
  if declared < 4 || declared > data.length() - 8 { return false }
  let mut chunk = 12
  while chunk + 8 <= declared + 8 {
    let size = webp_decode_u32(data, chunk + 4)
    let start = chunk + 8
    if start > declared + 8 || size > data.length() - start || size > declared + 8 - start {
      return false
    }
    if data[chunk] == b'V' && data[chunk + 1] == b'P' && data[chunk + 2] == b'8' && data[chunk + 3] == b'L' {
      return size >= 5
    }
    let advance = size + (size & 1) + 8
    if advance > data.length() - chunk { return false }
    chunk = chunk + advance
  }
  false
}

/// Decodes a RIFF/WEBP lossless VP8L image into RGBA8 pixels.
///
/// Pure MoonBit decoding currently supports the VP8L header, Huffman trees,
/// subtract-green transform and color cache. Streams using predictor or color
/// transforms return `None` until their inverse image transforms are added.
pub fn webp_decode(data : Array[Byte]) -> Image? {
  if !webp_decode_has_vp8l(data) {
    None
  } else {
    try {
      Some(webp_decode_impl(data))
    } catch {
      _ => None
    }
  }
}
