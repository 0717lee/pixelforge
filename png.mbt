///|
/// PNG codec in pure MoonBit.
///
/// Encoder: 8-bit RGBA, non-interlaced, adaptive row filters and a fixed
/// Huffman DEFLATE stream. Decoder accepts stored, fixed and dynamic blocks.
/// Decoder: full DEFLATE inflate (stored, fixed and dynamic Huffman),
/// zlib + Adler-32 and per-chunk CRC-32 verification, all five row filters
/// (None/Sub/Up/Average/Paeth), 8-bit truecolor, grayscale, and indexed
/// color with optional transparency.

///|
/// CRC-32 (ISO-HDLC) over `data[from..<to]`, bitwise implementation.
fn crc32(data : Array[Byte], from : Int, to : Int) -> UInt {
  let mut crc = 0xFFFFFFFFU
  for i in from..<to {
    crc = crc ^ data[i].to_uint()
    for _ in 0..<8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ 0xEDB88320U
      } else {
        crc = crc >> 1
      }
    }
  }
  crc ^ 0xFFFFFFFFU
}

///|
/// Adler-32 over `data[from..<to]` (the zlib checksum).
fn adler32(data : Array[Byte], from : Int, to : Int) -> UInt {
  let mut a = 1U
  let mut b = 0U
  for i in from..<to {
    a = (a + data[i].to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

///|
fn push_uint_be(buf : Array[Byte], v : UInt) -> Unit {
  buf.push(((v >> 24) & 0xFFU).to_byte())
  buf.push(((v >> 16) & 0xFFU).to_byte())
  buf.push(((v >> 8) & 0xFFU).to_byte())
  buf.push((v & 0xFFU).to_byte())
}

///|
/// Appends a complete PNG chunk: length, 4-byte type, payload, CRC-32
/// computed over type + payload.
fn push_chunk(
  out : Array[Byte],
  ctype : Array[Int],
  payload : Array[Byte],
) -> Unit {
  push_u32_be(out, payload.length())
  let crc_start = out.length()
  for t in ctype {
    push_u8(out, t)
  }
  for b in payload {
    out.push(b)
  }
  push_uint_be(out, crc32(out, crc_start, out.length()))
}

/// Reverse the low `n` bits of a canonical DEFLATE code.
fn reverse_bits(code : Int, n : Int) -> Int {
  let mut value = 0
  let mut remaining = code
  for _ in 0..<n {
    value = (value << 1) | (remaining & 1)
    remaining = remaining >> 1
  }
  value
}

/// Returns a fixed-Huffman literal/length code and its bit length.
fn fixed_code(symbol : Int) -> (Int, Int) {
  if symbol <= 143 {
    (reverse_bits(0x30 + symbol, 8), 8)
  } else if symbol <= 255 {
    (reverse_bits(0x190 + symbol - 144, 9), 9)
  } else if symbol <= 279 {
    (reverse_bits(symbol - 256, 7), 7)
  } else {
    (reverse_bits(0xC0 + symbol - 280, 8), 8)
  }
}

fn fixed_dist_code(symbol : Int) -> (Int, Int) {
  (reverse_bits(symbol, 5), 5)
}

priv struct BitWriter {
  out : Array[Byte]
  mut current : Int
  mut bits : Int
}

fn BitWriter::write(self : BitWriter, value : Int, count : Int) -> Unit {
  let mut remaining = value
  for _ in 0..<count {
    self.current = self.current | ((remaining & 1) << self.bits)
    self.bits = self.bits + 1
    remaining = remaining >> 1
    if self.bits == 8 {
      self.out.push(self.current.to_byte())
      self.current = 0
      self.bits = 0
    }
  }
}

fn BitWriter::finish(self : BitWriter) -> Unit {
  if self.bits > 0 {
    self.out.push(self.current.to_byte())
    self.current = 0
    self.bits = 0
  }
}

/// Encodes filtered scanlines as one deterministic fixed-Huffman block.
/// A distance-one match is used only when the preceding byte is identical;
/// otherwise a literal is emitted to preserve the exact byte stream.
fn deflate_fixed(raw : Array[Byte]) -> Array[Byte] {
  let writer : BitWriter = { out: [], current: 0, bits: 0, }
  writer.write(1, 1) // BFINAL
  writer.write(1, 2) // BTYPE=01 (fixed Huffman)
  let length_base = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
    83, 99, 115, 131, 163, 195, 227, 258,
  ]
  let length_extra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 0,
  ]
  let mut pos = 0
  while pos < raw.length() {
    let mut run = 1
    while pos + run < raw.length() && run < 258 && raw[pos + run] == raw[pos] {
      run = run + 1
    }
    if pos > 0 && run >= 3 && raw[pos - 1] == raw[pos] {
      let mut index = 0
      while index < 28 && run > length_base[index] + ((1 << length_extra[index]) - 1) {
        index = index + 1
      }
      let (code, bits) = fixed_code(257 + index)
      writer.write(code, bits)
      writer.write(run - length_base[index], length_extra[index])
      let (distance_code, distance_bits) = fixed_dist_code(0)
      writer.write(distance_code, distance_bits)
      pos = pos + run
    } else {
      let (code, bits) = fixed_code(raw[pos].to_int())
      writer.write(code, bits)
      pos = pos + 1
    }
  }
  let (end_code, end_bits) = fixed_code(256)
  writer.write(end_code, end_bits)
  writer.finish()
  writer.out
}

///|
/// Encodes an image as an 8-bit RGBA non-interlaced PNG. Each row chooses
/// the filter with the smallest sum of absolute signed residuals, then the
/// filtered scanlines are written as one fixed-Huffman DEFLATE block.
pub fn png_encode(img : Image) -> Array[Byte] {
  let out : Array[Byte] = []
  // Signature.
  for s in [137, 80, 78, 71, 13, 10, 26, 10] {
    push_u8(out, s)
  }
  // IHDR: width, height, depth 8, color 6 (RGBA), compression/filter 0,
  // no interlace.
  let ihdr : Array[Byte] = []
  push_u32_be(ihdr, img.width)
  push_u32_be(ihdr, img.height)
  for v in [8, 6, 0, 0, 0] {
    push_u8(ihdr, v)
  }
  push_chunk(out, [73, 72, 68, 82], ihdr)
  // Raw scanlines: choose among PNG's five filters per row.
  let raw : Array[Byte] = []
  let bpp = 4
  let stride = img.width * bpp
  let prev : Array[Int] = Array::make(stride, 0)
  let cur : Array[Int] = Array::make(stride, 0)
  for y in 0..<img.height {
    let mut best_filter = 0
    let mut best_score = -1
    for filter in 0..<5 {
      let mut score = 0
      for i in 0..<stride {
        let x = img.data[y * stride + i].to_int()
        let a = if i >= bpp {
          img.data[y * stride + i - bpp].to_int()
        } else {
          0
        }
        let b = prev[i]
        let c = if i >= bpp { prev[i - bpp] } else { 0 }
        let pred = match filter {
          0 => 0
          1 => a
          2 => b
          3 => (a + b) / 2
          _ => paeth(a, b, c)
        }
        let d = ((x - pred) % 256 + 256) % 256
        let signed = if d > 127 { d - 256 } else { d }
        score = score + iabs(signed)
      }
      if best_score < 0 || score < best_score {
        best_score = score
        best_filter = filter
      }
    }
    raw.push(best_filter.to_byte())
    for i in 0..<stride {
      let x = img.data[y * stride + i].to_int()
      let a = if i >= bpp { img.data[y * stride + i - bpp].to_int() } else { 0 }
      let b = prev[i]
      let c = if i >= bpp { prev[i - bpp] } else { 0 }
      let pred = match best_filter {
        0 => 0
        1 => a
        2 => b
        3 => (a + b) / 2
        _ => paeth(a, b, c)
      }
      raw.push((((x - pred) % 256 + 256) % 256).to_byte())
      cur[i] = x
    }
    for i in 0..<stride {
      prev[i] = cur[i]
    }
  }
  // zlib wrapper with a deterministic fixed-Huffman DEFLATE block.
  let idat : Array[Byte] = []
  idat.push(b'\x78')
  idat.push(b'\x9C')
  for b in deflate_fixed(raw) {
    idat.push(b)
  }
  push_uint_be(idat, adler32(raw, 0, raw.length()))
  push_chunk(out, [73, 68, 65, 84], idat)
  push_chunk(out, [73, 69, 78, 68], [])
  out
}

///|
/// LSB-first bit reader over a byte slice, as DEFLATE requires.
priv struct BitReader {
  data : Array[Byte]
  limit : Int
  mut pos : Int
  mut bit : Int
}

///|
/// Reads `need` bits (LSB first). Returns -1 past the end of input.
fn BitReader::take(self : BitReader, need : Int) -> Int {
  let mut v = 0
  for i in 0..<need {
    if self.pos >= self.limit {
      return -1
    }
    let b = (self.data[self.pos].to_int() >> self.bit) & 1
    self.bit = self.bit + 1
    if self.bit == 8 {
      self.bit = 0
      self.pos = self.pos + 1
    }
    v = v | (b << i)
  }
  v
}

///|
/// Canonical Huffman table in the compact "counts + sorted symbols" form
/// used by zlib's puff: `count[len]` is how many codes have that length and
/// `symbol` lists symbols ordered by (length, symbol).
priv struct Huffman {
  count : FixedArray[Int]
  symbol : FixedArray[Int]
}

///|
/// Builds a canonical Huffman table from code lengths. Returns `None` when
/// the lengths are over-subscribed (an invalid stream).
fn huff_build(lengths : Array[Int], n : Int) -> Huffman? {
  let count = FixedArray::make(16, 0)
  for i in 0..<n {
    count[lengths[i]] = count[lengths[i]] + 1
  }
  if count[0] == n {
    // No codes at all — legal for an unused distance table.
    return Some({ count, symbol: FixedArray::make(n, 0), })
  }
  let mut left = 1
  for len in 1..<16 {
    left = left * 2 - count[len]
    if left < 0 {
      return None
    }
  }
  let offs = FixedArray::make(16, 0)
  for len in 1..<15 {
    offs[len + 1] = offs[len] + count[len]
  }
  let symbol = FixedArray::make(n, 0)
  for i in 0..<n {
    if lengths[i] != 0 {
      symbol[offs[lengths[i]]] = i
      offs[lengths[i]] = offs[lengths[i]] + 1
    }
  }
  Some({ count, symbol, })
}

///|
/// Inflates a raw DEFLATE stream starting at `br`. Returns `None` on any
/// malformed structure.
fn inflate(br : BitReader) -> Array[Byte]? {
  let out : Array[Byte] = []
  let len_base = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
    83, 99, 115, 131, 163, 195, 227, 258,
  ]
  let len_extra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 0,
  ]
  let dist_base = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  let dist_extra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
    11, 12, 12, 13, 13,
  ]
  while true {
    let bfinal = br.take(1)
    let btype = br.take(2)
    if bfinal < 0 || btype < 0 || btype == 3 {
      return None
    }
    if btype == 0 {
      // Stored block: align to a byte boundary, LEN/NLEN, raw copy.
      if br.bit != 0 {
        br.bit = 0
        br.pos = br.pos + 1
      }
      if br.pos + 4 > br.limit {
        return None
      }
      let len = br.data[br.pos].to_int() + br.data[br.pos + 1].to_int() * 256
      let nlen = br.data[br.pos + 2].to_int() +
        br.data[br.pos + 3].to_int() * 256
      if len + nlen != 65535 {
        return None
      }
      br.pos = br.pos + 4
      if br.pos + len > br.limit {
        return None
      }
      for i in 0..<len {
        out.push(br.data[br.pos + i])
      }
      br.pos = br.pos + len
    } else {
      let mut litlen : Huffman = {
        count: FixedArray::make(16, 0),
        symbol: FixedArray::make(1, 0),
      }
      let mut dist : Huffman = {
        count: FixedArray::make(16, 0),
        symbol: FixedArray::make(1, 0),
      }
      if btype == 1 {
        // Fixed tables straight from the spec.
        let ll : Array[Int] = []
        for i in 0..<288 {
          ll.push(
            if i < 144 {
              8
            } else if i < 256 {
              9
            } else if i < 280 {
              7
            } else {
              8
            },
          )
        }
        let dd : Array[Int] = []
        for _ in 0..<30 {
          dd.push(5)
        }
        litlen = match huff_build(ll, 288) {
          Some(h) => h
          None => return None
        }
        dist = match huff_build(dd, 30) {
          Some(h) => h
          None => return None
        }
      } else {
        // Dynamic tables: code-length code first, then the real tables.
        let hlit = br.take(5)
        let hdist = br.take(5)
        let hclen = br.take(4)
        if hlit < 0 || hdist < 0 || hclen < 0 {
          return None
        }
        let nlit = hlit + 257
        let ndist = hdist + 1
        let order = [
          16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
        ]
        let cl_lengths = Array::make(19, 0)
        for i in 0..<(hclen + 4) {
          let v = br.take(3)
          if v < 0 {
            return None
          }
          cl_lengths[order[i]] = v
        }
        let cl_huff = match huff_build(cl_lengths, 19) {
          Some(h) => h
          None => return None
        }
        let lengths = Array::make(nlit + ndist, 0)
        let mut idx = 0
        while idx < nlit + ndist {
          let sym = br.huff_decode(cl_huff)
          if sym < 0 {
            return None
          }
          if sym < 16 {
            lengths[idx] = sym
            idx = idx + 1
          } else if sym == 16 {
            if idx == 0 {
              return None
            }
            let rep = br.take(2)
            if rep < 0 {
              return None
            }
            let prev = lengths[idx - 1]
            for _ in 0..<(rep + 3) {
              if idx >= nlit + ndist {
                return None
              }
              lengths[idx] = prev
              idx = idx + 1
            }
          } else {
            let (bits, base) = if sym == 17 { (3, 3) } else { (7, 11) }
            let rep = br.take(bits)
            if rep < 0 {
              return None
            }
            for _ in 0..<(rep + base) {
              if idx >= nlit + ndist {
                return None
              }
              lengths[idx] = 0
              idx = idx + 1
            }
          }
        }
        let ll : Array[Int] = []
        for i in 0..<nlit {
          ll.push(lengths[i])
        }
        let dd : Array[Int] = []
        for i in 0..<ndist {
          dd.push(lengths[nlit + i])
        }
        litlen = match huff_build(ll, nlit) {
          Some(h) => h
          None => return None
        }
        dist = match huff_build(dd, ndist) {
          Some(h) => h
          None => return None
        }
      }
      // Compressed data: literals, length/distance copies, 256 = end.
      while true {
        let sym = br.huff_decode(litlen)
        if sym < 0 {
          return None
        }
        if sym < 256 {
          out.push(sym.to_byte())
        } else if sym == 256 {
          break
        } else {
          if sym > 285 {
            return None
          }
          let li = sym - 257
          let extra = br.take(len_extra[li])
          if extra < 0 {
            return None
          }
          let length = len_base[li] + extra
          let dsym = br.huff_decode(dist)
          if dsym < 0 || dsym > 29 {
            return None
          }
          let dextra = br.take(dist_extra[dsym])
          if dextra < 0 {
            return None
          }
          let distance = dist_base[dsym] + dextra
          if distance > out.length() {
            return None
          }
          for _ in 0..<length {
            out.push(out[out.length() - distance])
          }
        }
      }
    }
    if bfinal == 1 {
      break
    }
  }
  Some(out)
}

///|
/// Decodes one Huffman symbol bit by bit. Returns -1 on malformed input.
fn BitReader::huff_decode(self : BitReader, h : Huffman) -> Int {
  let mut code = 0
  let mut first = 0
  let mut index = 0
  for len in 1..<16 {
    let b = self.take(1)
    if b < 0 {
      return -1
    }
    code = code | b
    let cnt = h.count[len]
    if code - first < cnt {
      return h.symbol[index + code - first]
    }
    index = index + cnt
    first = (first + cnt) << 1
    code = code << 1
  }
  -1
}

///|
/// Inflates a zlib stream (`data[from..<to]`) and verifies its Adler-32
/// trailer. Returns `None` on bad headers, bad DEFLATE data or checksum
/// mismatch.
fn zlib_inflate(data : Array[Byte], from : Int, to : Int) -> Array[Byte]? {
  if to - from < 6 {
    return None
  }
  let cmf = data[from].to_int()
  let flg = data[from + 1].to_int()
  if cmf % 16 != 8 || (cmf * 256 + flg) % 31 != 0 {
    return None
  }
  if flg / 32 % 2 == 1 {
    return None // preset dictionaries are not used by PNG
  }
  let br : BitReader = { data, limit: to - 4, pos: from + 2, bit: 0, }
  let raw = match inflate(br) {
    Some(r) => r
    None => return None
  }
  let expect = (data[to - 4].to_uint() << 24) |
    (data[to - 3].to_uint() << 16) |
    (data[to - 2].to_uint() << 8) |
    data[to - 1].to_uint()
  if adler32(raw, 0, raw.length()) != expect {
    return None
  }
  Some(raw)
}

///|
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = iabs(p - a)
  let pb = iabs(p - b)
  let pc = iabs(p - c)
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// Decodes an 8-bit PNG (color type 6 RGBA, 2 RGB, 0 grayscale, 4
/// grayscale+alpha, or 3 indexed palette, no
/// interlacing). Verifies the signature, every chunk CRC and the zlib
/// checksum; understands all five row filters. Returns `None` on anything
/// malformed or unsupported.
pub fn png_decode(data : Array[Byte]) -> Image? {
  let sig = [137, 80, 78, 71, 13, 10, 26, 10]
  if data.length() < 8 {
    return None
  }
  for i in 0..<8 {
    if data[i].to_int() != sig[i] {
      return None
    }
  }
  let mut pos = 8
  let mut width = 0
  let mut height = 0
  let mut color = -1
  let mut depth = 0
  let idat : Array[Byte] = []
  let palette : Array[Byte] = []
  let trns : Array[Byte] = []
  let mut seen_ihdr = false
  let mut seen_iend = false
  let mut seen_plte = false
  let mut seen_trns = false
  while pos + 12 <= data.length() && !seen_iend {
    let len = data[pos].to_int() * 16777216 +
      data[pos + 1].to_int() * 65536 +
      data[pos + 2].to_int() * 256 +
      data[pos + 3].to_int()
    if len < 0 || pos + 12 + len > data.length() {
      return None
    }
    let type_start = pos + 4
    let crc_pos = pos + 8 + len
    let expect = (data[crc_pos].to_uint() << 24) |
      (data[crc_pos + 1].to_uint() << 16) |
      (data[crc_pos + 2].to_uint() << 8) |
      data[crc_pos + 3].to_uint()
    if crc32(data, type_start, crc_pos) != expect {
      return None
    }
    let t0 = data[type_start].to_int()
    let t1 = data[type_start + 1].to_int()
    let t2 = data[type_start + 2].to_int()
    let t3 = data[type_start + 3].to_int()
    if t0 == 73 && t1 == 72 && t2 == 68 && t3 == 82 {
      // IHDR
      if len != 13 || seen_ihdr {
        return None
      }
      seen_ihdr = true
      let d = pos + 8
      width = data[d].to_int() * 16777216 +
        data[d + 1].to_int() * 65536 +
        data[d + 2].to_int() * 256 +
        data[d + 3].to_int()
      height = data[d + 4].to_int() * 16777216 +
        data[d + 5].to_int() * 65536 +
        data[d + 6].to_int() * 256 +
        data[d + 7].to_int()
      depth = data[d + 8].to_int()
      color = data[d + 9].to_int()
      let interlace = data[d + 12].to_int()
      if width <= 0 || height <= 0 || width * height > MAX_IMAGE_PIXELS {
        return None
      }
      if depth != 8 ||
        (color != 6 && color != 2 && color != 0 && color != 4 && color != 3) ||
        interlace != 0 {
        return None
      }
    } else if t0 == 80 && t1 == 76 && t2 == 84 && t3 == 69 {
      // PLTE: RGB triples, with at most 256 entries.
      if !seen_ihdr || seen_plte || len == 0 || len % 3 != 0 || len > 768 {
        return None
      }
      seen_plte = true
      for i in 0..<len {
        palette.push(data[pos + 8 + i])
      }
    } else if t0 == 116 && t1 == 82 && t2 == 78 && t3 == 83 {
      // tRNS: transparent sample/color or indexed alpha table.
      if !seen_ihdr || seen_trns || color == 4 || color == 6 || len == 0 {
        return None
      }
      if (color == 0 && len != 2) || (color == 2 && len != 6) ||
        (color == 3 && len > 256) {
        return None
      }
      // For 8-bit samples, the 16-bit tRNS values must have zero high bytes.
      if (color == 0 && data[pos + 8] != b'\x00') ||
        (color == 2 &&
          (data[pos + 8] != b'\x00' || data[pos + 10] != b'\x00' ||
            data[pos + 12] != b'\x00')) {
        return None
      }
      seen_trns = true
      for i in 0..<len {
        trns.push(data[pos + 8 + i])
      }
    } else if t0 == 73 && t1 == 68 && t2 == 65 && t3 == 84 {
      // IDAT — concatenate; the zlib stream spans all IDAT chunks.
      if !seen_ihdr {
        return None
      }
      for i in 0..<len {
        idat.push(data[pos + 8 + i])
      }
    } else if t0 == 73 && t1 == 69 && t2 == 78 && t3 == 68 {
      seen_iend = true
    }
    pos = crc_pos + 4
  }
  if !seen_ihdr || !seen_iend || idat.length() == 0 {
    return None
  }
  if color == 3 && (!seen_plte || palette.length() == 0) {
    return None
  }
  if color == 3 && seen_trns && trns.length() > palette.length() / 3 {
    return None
  }
  let raw = match zlib_inflate(idat, 0, idat.length()) {
    Some(r) => r
    None => return None
  }
  let bpp = match color {
    6 => 4
    2 => 3
    4 => 2
    _ => 1
  }
  let stride = width * bpp
  if raw.length() != (stride + 1) * height {
    return None
  }
  // Unfilter into recon, then expand to RGBA.
  let img = Image::new(width, height)
  let prev = Array::make(stride, 0)
  let cur = Array::make(stride, 0)
  for y in 0..<height {
    let ft = raw[y * (stride + 1)].to_int()
    if ft > 4 {
      return None
    }
    for i in 0..<stride {
      let x = raw[y * (stride + 1) + 1 + i].to_int()
      let a = if i >= bpp { cur[i - bpp] } else { 0 }
      let b = prev[i]
      let c = if i >= bpp { prev[i - bpp] } else { 0 }
      let pred = match ft {
        0 => 0
        1 => a
        2 => b
        3 => (a + b) / 2
        _ => paeth(a, b, c)
      }
      cur[i] = (x + pred) % 256
    }
    for x in 0..<width {
      let base = (y * width + x) * 4
      let sample = x * bpp
      if color == 3 {
        let palette_index = cur[sample]
        if palette_index >= palette.length() / 3 {
          return None
        }
        let p = palette_index * 3
        img.data[base] = palette[p]
        img.data[base + 1] = palette[p + 1]
        img.data[base + 2] = palette[p + 2]
        img.data[base + 3] = if seen_trns && palette_index < trns.length() {
          trns[palette_index]
        } else {
          b'\xFF'
        }
      } else if color == 0 {
        let gray = cur[sample].to_byte()
        img.data[base] = gray
        img.data[base + 1] = gray
        img.data[base + 2] = gray
        img.data[base + 3] = if seen_trns && trns[0].to_int() == 0 &&
          trns[1] == gray {
          b'\x00'
        } else {
          b'\xFF'
        }
      } else if color == 4 {
        let gray = cur[sample].to_byte()
        img.data[base] = gray
        img.data[base + 1] = gray
        img.data[base + 2] = gray
        img.data[base + 3] = cur[sample + 1].to_byte()
      } else {
        img.data[base] = cur[sample].to_byte()
        img.data[base + 1] = cur[sample + 1].to_byte()
        img.data[base + 2] = cur[sample + 2].to_byte()
        img.data[base + 3] = if color == 6 {
          cur[sample + 3].to_byte()
        } else if seen_trns && trns[0].to_int() == 0 &&
          trns[1] == cur[sample].to_byte() && trns[2].to_int() == 0 &&
          trns[3] == cur[sample + 1].to_byte() && trns[4].to_int() == 0 &&
          trns[5] == cur[sample + 2].to_byte() {
          b'\x00'
        } else {
          b'\xFF'
        }
      }
    }
    for i in 0..<stride {
      prev[i] = cur[i]
    }
  }
  Some(img)
}
