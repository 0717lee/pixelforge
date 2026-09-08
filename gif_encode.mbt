/// Deterministic single-frame GIF89a encoder.

///|
fn gif_encode_u16(buf : Array[Byte], value : Int) -> Unit {
  buf.push((value % 256).to_byte())
  buf.push((value / 256).to_byte())
}

priv struct GifCodeWriter {
  out : Array[Byte]
  mut acc : Int
  mut bits : Int
}

fn GifCodeWriter::write9(self : GifCodeWriter, code : Int) -> Unit {
  self.acc = self.acc | (code << self.bits)
  self.bits = self.bits + 9
  while self.bits >= 8 {
    self.out.push((self.acc % 256).to_byte())
    self.acc = self.acc / 256
    self.bits = self.bits - 8
  }
}

fn GifCodeWriter::finish(self : GifCodeWriter) -> Unit {
  if self.bits > 0 {
    self.out.push(self.acc.to_byte())
    self.acc = 0
    self.bits = 0
  }
}

/// Encodes one RGBA image as GIF89a.
///
/// The encoder supports up to 256 RGB entries. Alpha values below 128 share
/// one transparent palette entry. The LZW stream is deliberately literal-only
/// with a clear code before each pixel, making the output deterministic and
/// easy to validate across backends.
pub fn gif_encode(img : Image) -> Array[Byte] {
  let _ = img.pixel_count()
  if img.width <= 0 || img.height <= 0 || img.width > 65535 || img.height > 65535 {
    abort("gif_encode: dimensions must fit GIF limits")
  }
  let palette : Array[Byte] = []
  let indices : Array[Int] = []
  let mut transparent = -1
  let n = img.pixel_count()
  for p in 0..<n {
    let base = p * 4
    let alpha = if img.data[base + 3].to_int() < 128 { 0 } else { 255 }
    let r = if alpha == 0 { 0 } else { img.data[base].to_int() }
    let g = if alpha == 0 { 0 } else { img.data[base + 1].to_int() }
    let b = if alpha == 0 { 0 } else { img.data[base + 2].to_int() }
    let mut found = -1
    for i in 0..<(palette.length() / 4) {
      let off = i * 4
      if palette[off].to_int() == r && palette[off + 1].to_int() == g &&
        palette[off + 2].to_int() == b && palette[off + 3].to_int() == alpha {
        found = i
        break
      }
    }
    if found < 0 {
      if palette.length() / 4 >= 256 {
        abort("gif_encode: more than 256 palette entries")
      }
      found = palette.length() / 4
      palette.push(r.to_byte())
      palette.push(g.to_byte())
      palette.push(b.to_byte())
      palette.push(alpha.to_byte())
    }
    if alpha == 0 && transparent < 0 {
      transparent = found
    }
    indices.push(found)
  }
  while palette.length() < 256 * 4 {
    palette.push(b'\x00')
  }
  let out : Array[Byte] = []
  for c in [71, 73, 70, 56, 57, 97] { push_u8(out, c) }
  gif_encode_u16(out, img.width)
  gif_encode_u16(out, img.height)
  push_u8(out, 0xF7) // global table, 256 entries
  push_u8(out, 0)
  push_u8(out, 0)
  for i in 0..<256 {
    let off = i * 4
    push_u8(out, palette[off].to_int())
    push_u8(out, palette[off + 1].to_int())
    push_u8(out, palette[off + 2].to_int())
  }
  if transparent >= 0 {
    push_u8(out, 0x21); push_u8(out, 0xF9); push_u8(out, 4)
    push_u8(out, 1)
    gif_encode_u16(out, 0)
    push_u8(out, transparent)
    push_u8(out, 0)
  }
  push_u8(out, 0x2C)
  gif_encode_u16(out, 0); gif_encode_u16(out, 0)
  gif_encode_u16(out, img.width); gif_encode_u16(out, img.height)
  push_u8(out, 0)
  push_u8(out, 8) // minimum code size
  let writer : GifCodeWriter = { out: [], acc: 0, bits: 0, }
  writer.write9(256)
  for index in indices {
    writer.write9(index)
    writer.write9(256)
  }
  writer.write9(257)
  writer.finish()
  let mut pos = 0
  while pos < writer.out.length() {
    let count = if writer.out.length() - pos > 255 { 255 } else { writer.out.length() - pos }
    push_u8(out, count)
    for i in 0..<count { out.push(writer.out[pos + i]) }
    pos = pos + count
  }
  push_u8(out, 0)
  push_u8(out, 0x3B)
  out
}
