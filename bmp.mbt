///|
/// BMP codec for uncompressed 24-bit (BGR) and 32-bit (BGRA) images:
/// 14-byte file header + 40-byte BITMAPINFOHEADER, bottom-up row order and
/// 4-byte row padding for 24-bit data, exactly as Windows expects.

///|
fn push_u16_le(buf : Array[Byte], v : Int) -> Unit {
  push_u8(buf, v)
  push_u8(buf, v / 256)
}

///|
fn push_u32_le(buf : Array[Byte], v : Int) -> Unit {
  push_u8(buf, v)
  push_u8(buf, v / 256)
  push_u8(buf, v / 65536)
  push_u8(buf, v / 16777216)
}

///|
fn read_u16_le(data : Array[Byte], off : Int) -> Int {
  data[off].to_int() + data[off + 1].to_int() * 256
}

///|
fn read_u32_le(data : Array[Byte], off : Int) -> Int {
  data[off].to_int() +
  data[off + 1].to_int() * 256 +
  data[off + 2].to_int() * 65536 +
  data[off + 3].to_int() * 16777216
}

///|
/// Reads a signed 32-bit little-endian value without overflowing `Int`
/// (BMP height may legitimately be negative for top-down bitmaps).
fn read_i32_le(data : Array[Byte], off : Int) -> Int {
  let b0 = data[off].to_int()
  let b1 = data[off + 1].to_int()
  let b2 = data[off + 2].to_int()
  let b3 = data[off + 3].to_int()
  if b3 < 128 {
    b3 * 16777216 + b2 * 65536 + b1 * 256 + b0
  } else {
    -((255 - b3) * 16777216 +
    (255 - b2) * 65536 +
    (255 - b1) * 256 +
    (255 - b0) +
    1)
  }
}

///|
/// Encodes an image as an uncompressed BMP. `with_alpha = true` writes a
/// 32-bit BGRA bitmap; otherwise a 24-bit BGR bitmap with padded rows.
pub fn bmp_encode(img : Image, with_alpha : Bool) -> Array[Byte] {
  let w = img.width
  let h = img.height
  let bpp = if with_alpha { 32 } else { 24 }
  let stride = if with_alpha { w * 4 } else { (w * 3 + 3) / 4 * 4 }
  let data_size = stride * h
  let out : Array[Byte] = []
  // BITMAPFILEHEADER (14 bytes).
  push_u8(out, 66) // 'B'
  push_u8(out, 77) // 'M'
  push_u32_le(out, 54 + data_size)
  push_u32_le(out, 0)
  push_u32_le(out, 54) // pixel data offset
  // BITMAPINFOHEADER (40 bytes).
  push_u32_le(out, 40)
  push_u32_le(out, w)
  push_u32_le(out, h) // positive height = bottom-up rows
  push_u16_le(out, 1) // planes
  push_u16_le(out, bpp)
  push_u32_le(out, 0) // BI_RGB, no compression
  push_u32_le(out, data_size)
  push_u32_le(out, 2835) // 72 DPI in pixels/metre
  push_u32_le(out, 2835)
  push_u32_le(out, 0)
  push_u32_le(out, 0)
  for row in 0..<h {
    let y = h - 1 - row // bottom row first
    for x in 0..<w {
      let base = (y * w + x) * 4
      push_u8(out, img.data[base + 2].to_int()) // B
      push_u8(out, img.data[base + 1].to_int()) // G
      push_u8(out, img.data[base].to_int()) // R
      if with_alpha {
        push_u8(out, img.data[base + 3].to_int())
      }
    }
    if !with_alpha {
      for _ in 0..<(stride - w * 3) {
        push_u8(out, 0)
      }
    }
  }
  out
}

///|
/// Decodes an uncompressed 24- or 32-bit BMP. Returns `None` on malformed
/// input (bad magic, unsupported bpp/compression, truncated pixel data).
/// 24-bit sources decode with alpha set to 255; top-down bitmaps
/// (negative height) are handled.
pub fn bmp_decode(data : Array[Byte]) -> Image? {
  if data.length() < 54 {
    return None
  }
  if data[0].to_int() != 66 || data[1].to_int() != 77 {
    return None
  }
  let offset = read_u32_le(data, 10)
  let header_size = read_u32_le(data, 14)
  if header_size < 40 {
    return None
  }
  let width = read_i32_le(data, 18)
  let raw_height = read_i32_le(data, 22)
  let top_down = raw_height < 0
  let height = if top_down { -raw_height } else { raw_height }
  let bpp = read_u16_le(data, 28)
  let compression = read_u32_le(data, 30)
  if width <= 0 || height <= 0 || width * height > 100000000 {
    return None
  }
  if (bpp != 24 && bpp != 32) || compression != 0 {
    return None
  }
  let bytes_per_px = bpp / 8
  let stride = (width * bytes_per_px + 3) / 4 * 4
  if offset < 54 || offset + stride * height > data.length() {
    return None
  }
  let img = Image::new(width, height)
  for row in 0..<height {
    let y = if top_down { row } else { height - 1 - row }
    let src = offset + row * stride
    for x in 0..<width {
      let p = src + x * bytes_per_px
      let base = (y * width + x) * 4
      img.data[base] = data[p + 2] // R
      img.data[base + 1] = data[p + 1] // G
      img.data[base + 2] = data[p] // B
      img.data[base + 3] = if bpp == 32 { data[p + 3] } else { b'\xFF' }
    }
  }
  Some(img)
}
