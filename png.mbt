///|
/// PNG codec in pure MoonBit.
///
/// Encoder: 8-bit RGBA, non-interlaced, filter 0 rows, zlib stream with
/// stored DEFLATE blocks — small, spec-valid files every viewer opens.
/// Decoder: full DEFLATE inflate (stored, fixed and dynamic Huffman),
/// zlib + Adler-32 and per-chunk CRC-32 verification, all five row filters
/// (None/Sub/Up/Average/Paeth), 8-bit truecolor with or without alpha.

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

///|
/// Encodes an image as an 8-bit RGBA non-interlaced PNG. Rows use filter 0
/// and the zlib stream holds stored (uncompressed) DEFLATE blocks, so the
/// output is spec-valid and byte-size predictable rather than small.
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
  // Raw scanlines: one filter byte (0) then w*4 RGBA bytes per row.
  let raw : Array[Byte] = []
  for y in 0..<img.height {
    raw.push(b'\x00')
    for x in 0..<(img.width * 4) {
      raw.push(img.data[y * img.width * 4 + x])
    }
  }
  // zlib wrapper with stored DEFLATE blocks (max 65535 bytes each).
  let idat : Array[Byte] = []
  idat.push(b'\x78')
  idat.push(b'\x01')
  let mut off = 0
  while off < raw.length() || raw.length() == 0 {
    let chunk = if raw.length() - off > 65535 {
      65535
    } else {
      raw.length() - off
    }
    let last = off + chunk >= raw.length()
    idat.push(if last { b'\x01' } else { b'\x00' })
    push_u8(idat, chunk % 256)
    push_u8(idat, chunk / 256)
    push_u8(idat, 255 - chunk % 256)
    push_u8(idat, 255 - chunk / 256)
    for i in 0..<chunk {
      idat.push(raw[off + i])
    }
    off = off + chunk
    if last {
      break
    }
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
    return Some({ count, symbol: FixedArray::make(n, 0) })
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
  Some({ count, symbol })
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
  let br : BitReader = { data, limit: to - 4, pos: from + 2, bit: 0 }
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
/// Decodes an 8-bit truecolor PNG (color type 6 RGBA or 2 RGB, no
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
  let idat : Array[Byte] = []
  let mut seen_ihdr = false
  let mut seen_iend = false
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
      let depth = data[d + 8].to_int()
      color = data[d + 9].to_int()
      let interlace = data[d + 12].to_int()
      if width <= 0 || height <= 0 || width * height > 100000000 {
        return None
      }
      if depth != 8 || (color != 6 && color != 2) || interlace != 0 {
        return None
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
  let raw = match zlib_inflate(idat, 0, idat.length()) {
    Some(r) => r
    None => return None
  }
  let bpp = if color == 6 { 4 } else { 3 }
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
      img.data[base] = cur[x * bpp].to_byte()
      img.data[base + 1] = cur[x * bpp + 1].to_byte()
      img.data[base + 2] = cur[x * bpp + 2].to_byte()
      img.data[base + 3] = if bpp == 4 {
        cur[x * bpp + 3].to_byte()
      } else {
        b'\xFF'
      }
    }
    for i in 0..<stride {
      prev[i] = cur[i]
    }
  }
  Some(img)
}
