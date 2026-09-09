/// Pure MoonBit decoder for the WebP lossless (VP8L) bitstream.
///
/// The decoder accepts a RIFF/WEBP container with a VP8L chunk and produces
/// PixelForge's RGBA8 image.  It implements the VP8L header, canonical
/// Huffman trees (including repeat codes), spatially varying prefix groups,
/// LZ77 distance mapping, color cache, and all four VP8L inverse transforms.

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
        // VP8L transmits canonical codes least-significant bit first.  The
        // stored canonical code is already bit-reversed, so accumulate the
        // first bit at bit 0, then extend toward the high bits.
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
  let mut previous = 8
  while i < max_symbol {
    let token = webp_decode_symbol(bits, code_length_code)
    if token <= 15 {
      lengths[i] = token
      if token != 0 { previous = token }
      i = i + 1
    } else if token == 16 {
      let repeat = 3 + bits.read(2)
      if i + repeat > alphabet {
        raise WebPDecodeError::Invalid
      }
      // The VP8L specification defines an implicit previous length of 8
      // when code 16 appears before any literal code length.
      let repeated = previous
      for _ in 0..<repeat {
        lengths[i] = repeated
        i = i + 1
      }
    } else if token == 17 {
      let repeat = 3 + bits.read(3)
      if i + repeat > alphabet {
        raise WebPDecodeError::Invalid
      }
      previous = 0
      for _ in 0..<repeat {
        lengths[i] = 0
        i = i + 1
      }
    } else if token == 18 {
      let repeat = 11 + bits.read(7)
      if i + repeat > alphabet {
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

fn webp_lz_value(symbol : Int, bits : WebPDecodeBits) -> Int raise WebPDecodeError {
  if symbol < 4 { return symbol + 1 }
  let extra = (symbol - 2) >> 1
  let offset = (2 + (symbol & 1)) << extra
  offset + bits.read(extra) + 1
}

/// The long-distance mapping is direct; close-neighbour codes are rejected
/// until their full VP8L distance map is added.
fn webp_lz_distance(symbol : Int, width : Int, bits : WebPDecodeBits) -> Int raise WebPDecodeError {
  let code = webp_lz_value(symbol, bits)
  if code > 120 { return code - 120 }
  if code <= 0 || code > webp_distance_map.length() { raise WebPDecodeError::Invalid }
  let (dx, dy) = webp_distance_map[code - 1]
  let distance = dx + dy * width
  if distance < 1 { 1 } else { distance }
}

let webp_distance_map : FixedArray[(Int, Int)] = [
  (0, 1), (1, 0), (1, 1), (-1, 1), (0, 2), (2, 0), (1, 2), (-1, 2), (2, 1), (-2, 1),
  (2, 2), (-2, 2), (0, 3), (3, 0), (1, 3), (-1, 3), (3, 1), (-3, 1), (2, 3), (-2, 3),
  (3, 2), (-3, 2), (0, 4), (4, 0), (1, 4), (-1, 4), (4, 1), (-4, 1), (3, 3), (-3, 3),
  (2, 4), (-2, 4), (4, 2), (-4, 2), (0, 5), (3, 4), (-3, 4), (4, 3), (-4, 3), (5, 0),
  (1, 5), (-1, 5), (5, 1), (-5, 1), (2, 5), (-2, 5), (5, 2), (-5, 2), (4, 4), (-4, 4),
  (3, 5), (-3, 5), (5, 3), (-5, 3), (0, 6), (6, 0), (1, 6), (-1, 6), (6, 1), (-6, 1),
  (2, 6), (-2, 6), (6, 2), (-6, 2), (4, 5), (-4, 5), (5, 4), (-5, 4), (3, 6), (-3, 6),
  (6, 3), (-6, 3), (0, 7), (7, 0), (1, 7), (-1, 7), (5, 5), (-5, 5), (7, 1), (-7, 1),
  (4, 6), (-4, 6), (6, 4), (-6, 4), (2, 7), (-2, 7), (7, 2), (-7, 2), (3, 7), (-3, 7),
  (7, 3), (-7, 3), (5, 6), (-5, 6), (6, 5), (-6, 5), (8, 0), (4, 7), (-4, 7), (7, 4),
  (-7, 4), (8, 1), (8, 2), (6, 6), (-6, 6), (8, 3), (5, 7), (-5, 7), (7, 5), (-7, 5),
  (8, 4), (6, 7), (-6, 7), (7, 6), (-7, 6), (8, 5), (7, 7), (-7, 7), (8, 6), (8, 7),
]

///|
priv struct WebPTransform {
  kind : Int
  bits : Int
  width : Int
  data : FixedArray[Byte]
}

priv struct WebPCodeGroup {
  green : WebPDecodeCode
  red : WebPDecodeCode
  blue : WebPDecodeCode
  alpha : WebPDecodeCode
  distance : WebPDecodeCode
}

fn webp_decode_stream(
  bits : WebPDecodeBits,
  width : Int,
  height : Int,
  spatial : Bool,
) -> FixedArray[Byte] raise WebPDecodeError {
  if width <= 0 || height <= 0 || width > MAX_IMAGE_PIXELS / height {
    raise WebPDecodeError::Invalid
  }
  let cache_bits = if bits.read(1) == 1 { bits.read(4) } else { 0 }
  if cache_bits < 0 || cache_bits > 11 {
    raise WebPDecodeError::Invalid
  }
  let green_alphabet = 280 + (if cache_bits > 0 { 1 << cache_bits } else { 0 })
  let mut prefix_bits = 0
  let mut meta = FixedArray::make(0, b'\x00')
  if spatial && bits.read(1) == 1 {
    prefix_bits = bits.read(3) + 2
    let block = 1 << prefix_bits
    let meta_width = (width + block - 1) / block
    let meta_height = (height + block - 1) / block
    meta = webp_decode_stream(bits, meta_width, meta_height, false)
  }
  let mut group_count = 1
  if meta.length() > 0 {
    let mut max_group = 0
    for i in 0..<(meta.length() / 4) {
      let group = (meta[i * 4].to_int() << 8) | meta[i * 4 + 1].to_int()
      if group > max_group { max_group = group }
    }
    group_count = max_group + 1
    if group_count > 256 { raise WebPDecodeError::Invalid }
  }
  let groups = Array::new()
  for _ in 0..<group_count {
    groups.push({
      green: webp_decode_prefix(bits, green_alphabet),
      //
      red: webp_decode_prefix(bits, 256),
      blue: webp_decode_prefix(bits, 256),
      alpha: webp_decode_prefix(bits, 256),
      distance: webp_decode_prefix(bits, 40),
    })
  }
  let total = width * height
  let pixels = FixedArray::make(total * 4, b'\x00')
  let cache_size = if cache_bits > 0 { 1 << cache_bits } else { 0 }
  let cache = FixedArray::make(cache_size, 0)
  let valid = FixedArray::make(cache_size, 0)
  let mut pixel = 0
  while pixel < total {
    let x = pixel % width
    let y = pixel / width
    let group_index = if meta.length() == 0 { 0 } else {
      let mi = (y >> prefix_bits) * ((width + (1 << prefix_bits) - 1) >> prefix_bits) + (x >> prefix_bits)
      let raw = (meta[mi * 4].to_int() << 8) | meta[mi * 4 + 1].to_int()
      if raw >= group_count { raise WebPDecodeError::Invalid }
      raw
    }
    let group = groups[group_index]
    let green_or_cache = webp_decode_symbol(bits, group.green)
    if green_or_cache >= 256 && green_or_cache < 280 {
      let length = webp_lz_value(green_or_cache - 256, bits)
      let distance_symbol = webp_decode_symbol(bits, group.distance)
      let distance = webp_lz_distance(distance_symbol, width, bits)
      if length <= 0 || distance <= 0 || distance > pixel || pixel + length > total {
        raise WebPDecodeError::Invalid
      }
      for _ in 0..<length {
        let src = (pixel - distance) * 4
        let dst = pixel * 4
        for channel in 0..<4 { pixels[dst + channel] = pixels[src + channel] }
        if cache_bits > 0 {
          let color = (pixels[dst + 3].to_int() << 24) |
            (pixels[dst].to_int() << 16) | (pixels[dst + 1].to_int() << 8) |
            pixels[dst + 2].to_int()
          let index = webp_decode_color_cache_index(color, cache_bits)
          cache[index] = color; valid[index] = 1
        }
        pixel = pixel + 1
      }
      continue
    }
    let mut red = 0
    let mut green = 0
    let mut blue = 0
    let mut alpha = 255
    if green_or_cache < 256 {
      green = green_or_cache
      red = webp_decode_symbol(bits, group.red)
      blue = webp_decode_symbol(bits, group.blue)
      alpha = webp_decode_symbol(bits, group.alpha)
    } else if cache_bits > 0 && green_or_cache >= 280 {
      let index = green_or_cache - 280
      if index >= cache_size || valid[index] == 0 { raise WebPDecodeError::Invalid }
      let color = cache[index]
      alpha = (color >> 24) & 0xFF
      red = (color >> 16) & 0xFF
      green = (color >> 8) & 0xFF
      blue = color & 0xFF
    } else {
      raise WebPDecodeError::Invalid
    }
    let offset = pixel * 4
    pixels[offset] = red.to_byte()
    pixels[offset + 1] = green.to_byte()
    pixels[offset + 2] = blue.to_byte()
    pixels[offset + 3] = alpha.to_byte()
    if cache_bits > 0 {
      let color = (alpha << 24) | (red << 16) | (green << 8) | blue
      let index = webp_decode_color_cache_index(color, cache_bits)
      cache[index] = color; valid[index] = 1
    }
    pixel = pixel + 1
  }
  pixels
}

fn webp_u8_signed(v : Int) -> Int { if v >= 128 { v - 256 } else { v } }
fn webp_clamp(v : Int) -> Int { if v < 0 { 0 } else if v > 255 { 255 } else { v } }
fn webp_avg(a : Int, b : Int) -> Int { (a + b) >> 1 }

fn webp_predict_channel(mode : Int, l : Int, t : Int, tr : Int, tl : Int) -> Int {
  if mode == 0 { 0 }
  else if mode == 1 { l }
  else if mode == 2 { t }
  else if mode == 3 { tr }
  else if mode == 4 { tl }
  else if mode == 5 { webp_avg(webp_avg(l, tr), t) }
  else if mode == 6 { webp_avg(l, tl) }
  else if mode == 7 { webp_avg(l, t) }
  else if mode == 8 { webp_avg(tl, t) }
  else if mode == 9 { webp_avg(t, tr) }
  else if mode == 10 { webp_avg(webp_avg(l, tl), webp_avg(t, tr)) }
  else if mode == 12 { webp_clamp(l + t - tl) }
  else if mode == 13 { webp_clamp(webp_avg(l, t) + (webp_avg(l, t) - tl) / 2) }
  else { l }
}

fn webp_select(l : Int, t : Int, tl : Int) -> Int {
  let p = l + t - tl
  let dl = (p - l).abs()
  let dt = (p - t).abs()
  if dl < dt { l } else { t }
}

fn webp_apply_predictor(pixels : FixedArray[Byte], width : Int, height : Int, tx : WebPTransform) -> Unit {
  let out = pixels
  let block = 1 << tx.bits
  let tw = (width + block - 1) / block
  for y in 0..<height {
    for x in 0..<width {
      let i = (y * width + x) * 4
      let mode_i = ((y >> tx.bits) * tw + (x >> tx.bits)) * 4
      let mode = tx.data[mode_i + 1].to_int()
      for c in 0..<4 {
        let border = if c == 3 { 255 } else { 0 }
        let left = if x > 0 { out[i - 4 + c].to_int() } else { border }
        let top = if y > 0 { out[i - width * 4 + c].to_int() } else { border }
        // At the right edge VP8L uses the left-most pixel on this row as TR.
        let p = if x == 0 && y == 0 {
          border
        } else if y == 0 { left } else if x == 0 { top } else if mode == 0 {
          border
        } else if mode == 11 {
          let pl = out[i - 4 + c].to_int(); let pt = out[i - width * 4 + c].to_int(); let ptl = out[i - width * 4 - 4 + c].to_int()
          webp_select(pl, pt, ptl)
        } else {
          let pl = out[i - 4 + c].to_int(); let pt = out[i - width * 4 + c].to_int();
          let ptr = if x + 1 < width { out[i - width * 4 + 4 + c].to_int() } else { out[y * width * 4 + c].to_int() }
          let ptl = out[i - width * 4 - 4 + c].to_int()
          webp_predict_channel(mode, pl, pt, ptr, ptl)
        }
        out[i + c] = ((out[i + c].to_int() + p) & 255).to_byte()
      }
    }
  }
}

fn webp_color_delta(t : Int, c : Int) -> Int { (webp_u8_signed(t) * webp_u8_signed(c)) >> 5 }

fn webp_apply_color(pixels : FixedArray[Byte], width : Int, height : Int, tx : WebPTransform) -> Unit {
  let block = 1 << tx.bits
  let tw = (width + block - 1) / block
  for y in 0..<height {
    for x in 0..<width {
      let i = (y * width + x) * 4
      let j = ((y >> tx.bits) * tw + (x >> tx.bits)) * 4
      let g = pixels[i + 1].to_int()
      // The entropy stream stores bytes in RGBA order.  The CTE maps
      // R=red_to_blue, G=green_to_blue, B=green_to_red.
      let e0 = tx.data[j + 1].to_int() // green_to_blue
      let e1 = tx.data[j + 2].to_int() // green_to_red
      let e2 = tx.data[j].to_int()     // red_to_blue
      let r = (pixels[i].to_int() + webp_color_delta(e1, g)) & 255
      let b = (pixels[i + 2].to_int() + webp_color_delta(e0, g) + webp_color_delta(e2, r)) & 255
      pixels[i] = r.to_byte(); pixels[i + 2] = b.to_byte()
    }
  }
}

fn webp_apply_indexing(pixels : FixedArray[Byte], width : Int, height : Int, tx : WebPTransform) -> (FixedArray[Byte], Int) {
  let factor = 1 << tx.bits
  // tx.width is the packed width seen by the entropy decoder.  Inverse
  // indexing expands each packed pixel back to `factor` source pixels.
  let out_width = tx.width * factor
  let out = FixedArray::make(out_width * height * 4, b'\x00')
  let colors = tx.data.length() / 4
  for y in 0..<height {
    for x in 0..<out_width {
      let packed = pixels[(y * width + (x >> tx.bits)) * 4 + 1].to_int()
      let index = (packed >> ((x & (factor - 1)) * (8 >> tx.bits))) & ((1 << (8 >> tx.bits)) - 1)
      let dst = (y * out_width + x) * 4
      if index < colors {
        let src = index * 4
        for c in 0..<4 { out[dst + c] = tx.data[src + c] }
      }
    }
  }
  (out, out_width)
}

fn webp_decode_impl(data : Array[Byte]) -> Image raise WebPDecodeError {
  if data.length() < 20 || data[0] != b'R' || data[1] != b'I' || data[2] != b'F' || data[3] != b'F' || data[8] != b'W' || data[9] != b'E' || data[10] != b'B' || data[11] != b'P' { raise WebPDecodeError::Invalid }
  let declared = webp_decode_u32(data, 4)
  if declared < 4 || declared + 8 > data.length() { raise WebPDecodeError::Invalid }
  let mut chunk = 12
  let mut payload_start = -1
  let mut payload_end = -1
  while chunk + 8 <= data.length() && chunk < declared + 8 {
    let size = webp_decode_u32(data, chunk + 4); let start = chunk + 8; let end = start + size
    if end < start || end > data.length() || end > declared + 8 { raise WebPDecodeError::Invalid }
    if data[chunk] == b'V' && data[chunk + 1] == b'P' && data[chunk + 2] == b'8' && data[chunk + 3] == b'L' { payload_start = start; payload_end = end; break }
    chunk = end + (size & 1)
  }
  if payload_start < 0 || payload_end - payload_start < 5 { raise WebPDecodeError::Invalid }
  let bits = WebPDecodeBits::new(data, payload_start, payload_end)
  if bits.read(8) != 0x2F { raise WebPDecodeError::Invalid }
  let width = bits.read(14) + 1; let height = bits.read(14) + 1
  ignore(bits.read(1)); if bits.read(3) != 0 { raise WebPDecodeError::Invalid }
  let transforms : Array[WebPTransform] = []
  let mut current_width = width
  while bits.read(1) == 1 {
    let kind = bits.read(2)
    let tx_width = current_width
    if kind == 2 {
      transforms.push({ kind, bits: 0, width: tx_width, data: FixedArray::make(0, b'\x00') })
    } else if kind == 0 || kind == 1 {
      let tb = bits.read(3) + 2; let block = 1 << tb
      let tw = (current_width + block - 1) / block; let th = (height + block - 1) / block
      let td = webp_decode_stream(bits, tw, th, false)
      transforms.push({ kind, bits: tb, width: tx_width, data: td })
    } else if kind == 3 {
      let num = bits.read(8) + 1
      let tb = if num > 16 { 0 } else if num > 4 { 1 } else if num > 2 { 2 } else { 3 }
      let palette = webp_decode_stream(bits, num, 1, false)
      let expanded = FixedArray::make((1 << (8 >> tb)) * 4, b'\x00')
      for i in 0..<num { for c in 0..<4 { expanded[i * 4 + c] = palette[i * 4 + c] } }
      for i in 1..<(expanded.length() / 4) { for c in 0..<4 { expanded[i * 4 + c] = ((expanded[(i - 1) * 4 + c].to_int() + expanded[i * 4 + c].to_int()) & 255).to_byte() } }
      transforms.push({ kind, bits: tb, width: tx_width, data: expanded })
      current_width = (current_width + (1 << tb) - 1) / (1 << tb)
    } else { raise WebPDecodeError::Invalid }
  }
  let pixels = webp_decode_stream(bits, current_width, height, true)
  let mut out = pixels
  let mut out_width = current_width
  for k = transforms.length() - 1; k >= 0; k = k - 1 {
    let tx = transforms[k]
    if tx.kind == 0 {
      webp_apply_predictor(out, out_width, height, tx)
    } else if tx.kind == 1 {
      webp_apply_color(out, out_width, height, tx)
    } else if tx.kind == 2 {
      for i in 0..<(out.length() / 4) { let g = out[i * 4 + 1].to_int(); out[i * 4] = ((out[i * 4].to_int() + g) & 255).to_byte(); out[i * 4 + 2] = ((out[i * 4 + 2].to_int() + g) & 255).to_byte() }
    } else { let (expanded, ew) = webp_apply_indexing(out, out_width, height, tx); out = expanded; out_width = ew }
  }
  let image = Image::new(width, height)
  if out_width != width { raise WebPDecodeError::Invalid }
  for i in 0..<out.length() { image.data[i] = out[i] }
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
/// Pure MoonBit decoding supports the VP8L header, Huffman trees, LZ77,
/// color cache, predictor, cross-color, subtract-green, and color-indexing
/// transforms.
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
