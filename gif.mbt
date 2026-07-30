///|
/// GIF decoder (first frame) in pure MoonBit: GIF87a/GIF89a signatures,
/// logical screen descriptor, global and local color tables, the graphic
/// control extension (transparent index), variable-width LSB-first LZW
/// decompression and 4-pass interlacing. Returns `None` on malformed input.

///|
/// Reads the little-endian u16 at `off`.
fn gif_u16(data : Array[Byte], off : Int) -> Int {
  data[off].to_int() + data[off + 1].to_int() * 256
}

///|
/// Concatenates the LZW data sub-blocks starting at `pos`. Returns the
/// payload and the position just past the block terminator, or `None`
/// when the stream is truncated.
fn gif_subblocks(data : Array[Byte], pos : Int) -> (Array[Byte], Int)? {
  let out : Array[Byte] = []
  let mut p = pos
  while true {
    if p >= data.length() {
      return None
    }
    let len = data[p].to_int()
    p = p + 1
    if len == 0 {
      break
    }
    if p + len > data.length() {
      return None
    }
    for i in 0..<len {
      out.push(data[p + i])
    }
    p = p + len
  }
  Some((out, p))
}

///|
/// Decompresses a GIF LZW stream into at most `max_pixels` color indices.
/// Implements the variable code width (LSB-first), CLEAR/END codes and the
/// 4096-entry dictionary limit. Returns `None` on any malformed code.
fn gif_lzw(
  bytes : Array[Byte],
  min_code_size : Int,
  max_pixels : Int,
) -> Array[Int]? {
  if min_code_size < 2 || min_code_size > 8 {
    return None
  }
  let clear = 1 << min_code_size
  let end = clear + 1
  // Dictionary entries as (prefix index, tail byte); roots have prefix -1.
  let prefix : Array[Int] = Array::make(4096, -1)
  let tail : Array[Int] = Array::make(4096, 0)
  let out : Array[Int] = []
  let mut next = end + 1
  let mut width = min_code_size + 1
  let mut prev = -1
  let mut acc = 0
  let mut nbits = 0
  let mut pos = 0
  // Expands one dictionary entry (walking the prefix chain) into `out`.
  fn expand(code : Int) -> Int {
    // Collect the chain, then emit in reverse (chains are stored tail-first).
    let chain : Array[Int] = []
    let mut c = code
    while c >= 0 {
      if c < clear {
        chain.push(c)
        break
      }
      chain.push(tail[c])
      c = prefix[c]
    }
    for i = chain.length() - 1; i >= 0; i = i - 1 {
      out.push(chain[i])
    }
    chain[chain.length() - 1] // first index of the expanded string
  }

  while true {
    // Pull the next variable-width code from the LSB-first bit stream.
    while nbits < width {
      if pos >= bytes.length() {
        return None
      }
      acc = acc + bytes[pos].to_int() * (1 << nbits)
      nbits = nbits + 8
      pos = pos + 1
    }
    let code = acc % (1 << width)
    acc = acc / (1 << width)
    nbits = nbits - width
    if code == clear {
      next = end + 1
      width = min_code_size + 1
      prev = -1
      continue
    }
    if code == end {
      break
    }
    if prev < 0 {
      // First code after a clear must be a root.
      if code >= clear {
        return None
      }
      out.push(code)
      prev = code
    } else {
      let first = if code < next {
        expand(code)
      } else if code == next {
        // The KwKwK case: emit string(prev) followed by its first index.
        let f = expand(prev)
        out.push(f)
        f
      } else {
        return None
      }
      if next < 4096 {
        prefix[next] = prev
        tail[next] = first
        next = next + 1
        if next < 4096 && next == 1 << width {
          width = width + 1
        }
      }
      prev = code
    }
    if out.length() >= max_pixels {
      break
    }
  }
  Some(out)
}

///|
/// Decodes the first frame of a GIF87a/GIF89a file into an RGBA image.
/// Supports global/local color tables, interlacing and the transparent
/// index from the graphic control extension. Returns `None` on anything
/// malformed (bad signature, truncated blocks, invalid LZW data).
pub fn gif_decode(data : Array[Byte]) -> Image? {
  // "GIF87a" or "GIF89a".
  if data.length() < 13 {
    return None
  }
  if data[0].to_int() != 71 || data[1].to_int() != 73 || data[2].to_int() != 70 {
    return None
  }
  if data[3].to_int() != 56 ||
    (data[4].to_int() != 55 && data[4].to_int() != 57) ||
    data[5].to_int() != 97 {
    return None
  }
  let packed = data[10].to_int()
  let has_gct = packed / 128 == 1
  let gct_size = 2 << (packed % 8) // 2^(N+1) entries
  let mut pos = 13
  let mut gct_at = -1
  if has_gct {
    gct_at = pos
    pos = pos + gct_size * 3
    if pos > data.length() {
      return None
    }
  }
  let mut transparent = -1
  while true {
    if pos >= data.length() {
      return None
    }
    let block = data[pos].to_int()
    pos = pos + 1
    if block == 0x3B {
      return None // trailer before any image
    } else if block == 0x21 {
      // Extension: remember the transparent index from GCE, skip the rest.
      if pos >= data.length() {
        return None
      }
      let label = data[pos].to_int()
      pos = pos + 1
      if label == 0xF9 {
        if pos + 6 > data.length() {
          return None
        }
        let flags = data[pos + 1].to_int()
        if flags % 2 == 1 {
          transparent = data[pos + 4].to_int()
        }
      }
      match gif_subblocks(data, pos) {
        Some((_, p2)) => pos = p2
        None => return None
      }
    } else if block == 0x2C {
      // Image descriptor: the frame we decode.
      if pos + 9 > data.length() {
        return None
      }
      let width = gif_u16(data, pos + 4)
      let height = gif_u16(data, pos + 6)
      let ipacked = data[pos + 8].to_int()
      pos = pos + 9
      if width <= 0 || height <= 0 || width * height > 100000000 {
        return None
      }
      let interlaced = ipacked / 64 % 2 == 1
      let mut table_at = gct_at
      let mut table_len = gct_size
      if ipacked / 128 == 1 {
        table_at = pos
        table_len = 2 << (ipacked % 8)
        pos = pos + table_len * 3
        if pos > data.length() {
          return None
        }
      }
      if table_at < 0 {
        return None // no color table at all
      }
      if pos >= data.length() {
        return None
      }
      let min_code = data[pos].to_int()
      pos = pos + 1
      let (lzw, _) = match gif_subblocks(data, pos) {
        Some(r) => r
        None => return None
      }
      let indices = match gif_lzw(lzw, min_code, width * height) {
        Some(ix) => ix
        None => return None
      }
      if indices.length() < width * height {
        return None
      }
      // Row order: sequential, or the 4 interlace passes.
      let rows : Array[Int] = []
      if interlaced {
        for y = 0; y < height; y = y + 8 {
          rows.push(y)
        }
        for y = 4; y < height; y = y + 8 {
          rows.push(y)
        }
        for y = 2; y < height; y = y + 4 {
          rows.push(y)
        }
        for y = 1; y < height; y = y + 2 {
          rows.push(y)
        }
      } else {
        for y in 0..<height {
          rows.push(y)
        }
      }
      let img = Image::new(width, height)
      for r in 0..<height {
        let y = rows[r]
        for x in 0..<width {
          let idx = indices[r * width + x]
          if idx >= table_len {
            return None
          }
          let c = table_at + idx * 3
          let base = (y * width + x) * 4
          img.data[base] = data[c]
          img.data[base + 1] = data[c + 1]
          img.data[base + 2] = data[c + 2]
          img.data[base + 3] = if idx == transparent {
            b'\x00'
          } else {
            b'\xFF'
          }
        }
      }
      return Some(img)
    } else {
      return None // unknown block type
    }
  }
  None
}
