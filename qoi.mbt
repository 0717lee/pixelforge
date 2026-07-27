///|
/// QOI ("Quite OK Image") codec — a complete, dependency-free implementation
/// of the QOI specification (https://qoiformat.org/qoi-specification.pdf):
/// 14-byte header, RGB/RGBA/INDEX/DIFF/LUMA/RUN ops, the 64-entry color index
/// with hash (r*3+g*5+b*7+a*11) % 64, and the 8-byte end marker.

///|
fn push_u8(buf : Array[Byte], v : Int) -> Unit {
  buf.push(((v % 256 + 256) % 256).to_byte())
}

///|
fn push_u32_be(buf : Array[Byte], v : Int) -> Unit {
  push_u8(buf, v / 16777216)
  push_u8(buf, v / 65536)
  push_u8(buf, v / 256)
  push_u8(buf, v)
}

///|
/// Wraps a channel difference into the signed byte range `[-128, 127]`, the
/// wraparound arithmetic the QOI spec mandates for DIFF/LUMA ops.
fn wrap_diff(cur : Int, prev : Int) -> Int {
  let d = ((cur - prev) % 256 + 256) % 256
  if d >= 128 {
    d - 256
  } else {
    d
  }
}

///|
fn qoi_hash(r : Int, g : Int, b : Int, a : Int) -> Int {
  (r * 3 + g * 5 + b * 7 + a * 11) % 64
}

///|
/// Encodes an image as a QOI byte stream (channels = 4, sRGB colorspace tag).
pub fn qoi_encode(img : Image) -> Array[Byte] {
  let out : Array[Byte] = []
  // "qoif" magic, dimensions, 4 channels, colorspace 0 (sRGB + linear alpha).
  push_u8(out, 113)
  push_u8(out, 111)
  push_u8(out, 105)
  push_u8(out, 102)
  push_u32_be(out, img.width)
  push_u32_be(out, img.height)
  push_u8(out, 4)
  push_u8(out, 0)
  let index = FixedArray::make(64 * 4, 0)
  let mut pr = 0
  let mut pg = 0
  let mut pb = 0
  let mut pa = 255
  let mut run = 0
  let n = img.pixel_count()
  for p in 0..<n {
    let base = p * 4
    let r = img.data[base].to_int()
    let g = img.data[base + 1].to_int()
    let b = img.data[base + 2].to_int()
    let a = img.data[base + 3].to_int()
    if r == pr && g == pg && b == pb && a == pa {
      run = run + 1
      if run == 62 {
        push_u8(out, 192 + run - 1) // QOI_OP_RUN
        run = 0
      }
    } else {
      if run > 0 {
        push_u8(out, 192 + run - 1)
        run = 0
      }
      let pos = qoi_hash(r, g, b, a) * 4
      if index[pos] == r &&
        index[pos + 1] == g &&
        index[pos + 2] == b &&
        index[pos + 3] == a {
        push_u8(out, pos / 4) // QOI_OP_INDEX
      } else {
        index[pos] = r
        index[pos + 1] = g
        index[pos + 2] = b
        index[pos + 3] = a
        if a == pa {
          let dr = wrap_diff(r, pr)
          let dg = wrap_diff(g, pg)
          let db = wrap_diff(b, pb)
          if dr >= -2 && dr <= 1 && dg >= -2 && dg <= 1 && db >= -2 && db <= 1 {
            push_u8(out, 64 + (dr + 2) * 16 + (dg + 2) * 4 + (db + 2)) // DIFF
          } else if dg >= -32 &&
            dg <= 31 &&
            dr - dg >= -8 &&
            dr - dg <= 7 &&
            db - dg >= -8 &&
            db - dg <= 7 {
            push_u8(out, 128 + (dg + 32)) // QOI_OP_LUMA
            push_u8(out, (dr - dg + 8) * 16 + (db - dg + 8))
          } else {
            push_u8(out, 254) // QOI_OP_RGB
            push_u8(out, r)
            push_u8(out, g)
            push_u8(out, b)
          }
        } else {
          push_u8(out, 255) // QOI_OP_RGBA
          push_u8(out, r)
          push_u8(out, g)
          push_u8(out, b)
          push_u8(out, a)
        }
      }
      pr = r
      pg = g
      pb = b
      pa = a
    }
  }
  if run > 0 {
    push_u8(out, 192 + run - 1)
  }
  // End marker: seven 0x00 bytes followed by 0x01.
  for _ in 0..<7 {
    push_u8(out, 0)
  }
  push_u8(out, 1)
  out
}

///|
/// Decodes a QOI byte stream. Returns `None` on malformed input (bad magic,
/// zero dimensions, truncated stream or unsupported channel count).
pub fn qoi_decode(data : Array[Byte]) -> Image? {
  if data.length() < 22 {
    return None
  }
  let u8 = fn(i : Int) -> Int { data[i].to_int() }
  if u8(0) != 113 || u8(1) != 111 || u8(2) != 105 || u8(3) != 102 {
    return None
  }
  let width = u8(4) * 16777216 + u8(5) * 65536 + u8(6) * 256 + u8(7)
  let height = u8(8) * 16777216 + u8(9) * 65536 + u8(10) * 256 + u8(11)
  let channels = u8(12)
  if width <= 0 || height <= 0 || (channels != 3 && channels != 4) {
    return None
  }
  if width * height > 100000000 {
    return None
  }
  let img = Image::new(width, height)
  let index = FixedArray::make(64 * 4, 0)
  let mut r = 0
  let mut g = 0
  let mut b = 0
  let mut a = 255
  let mut run = 0
  let mut pos = 14
  let limit = data.length() - 8 // reserve the end marker
  let n = width * height
  for p in 0..<n {
    if run > 0 {
      run = run - 1
    } else {
      if pos >= limit {
        return None
      }
      let b1 = u8(pos)
      pos = pos + 1
      if b1 == 254 {
        if pos + 3 > limit {
          return None
        }
        r = u8(pos)
        g = u8(pos + 1)
        b = u8(pos + 2)
        pos = pos + 3
      } else if b1 == 255 {
        if pos + 4 > limit {
          return None
        }
        r = u8(pos)
        g = u8(pos + 1)
        b = u8(pos + 2)
        a = u8(pos + 3)
        pos = pos + 4
      } else if b1 / 64 == 0 {
        let i = b1 * 4
        r = index[i]
        g = index[i + 1]
        b = index[i + 2]
        a = index[i + 3]
      } else if b1 / 64 == 1 {
        let payload = b1 % 64
        r = (r + payload / 16 - 2 + 256) % 256
        g = (g + payload / 4 % 4 - 2 + 256) % 256
        b = (b + payload % 4 - 2 + 256) % 256
      } else if b1 / 64 == 2 {
        if pos + 1 > limit {
          return None
        }
        let dg = b1 % 64 - 32
        let b2 = u8(pos)
        pos = pos + 1
        let dr = dg + b2 / 16 - 8
        let db = dg + b2 % 16 - 8
        r = (r + dr + 512) % 256
        g = (g + dg + 512) % 256
        b = (b + db + 512) % 256
      } else {
        run = b1 % 64
      }
      let hp = qoi_hash(r, g, b, a) * 4
      index[hp] = r
      index[hp + 1] = g
      index[hp + 2] = b
      index[hp + 3] = a
    }
    let base = p * 4
    img.data[base] = clamp_byte(r)
    img.data[base + 1] = clamp_byte(g)
    img.data[base + 2] = clamp_byte(b)
    img.data[base + 3] = clamp_byte(a)
  }
  Some(img)
}
