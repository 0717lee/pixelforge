/// Restricted baseline TIFF decoder.
///
/// Supports little/big-endian classic TIFF (magic 42), one uncompressed strip,
/// chunky 8-bit grayscale/RGB/RGBA samples and photometric interpretation 0/1
/// or 2. Compression, tiled images, palettes, predictors, BigTIFF and multiple
/// strips return `None` so callers can choose a more capable host decoder.

fn tiff_u16(data : Array[Byte], p : Int, little : Bool) -> Int {
  if little {
    data[p].to_int() | (data[p + 1].to_int() << 8)
  } else {
    (data[p].to_int() << 8) | data[p + 1].to_int()
  }
}

fn tiff_u32(data : Array[Byte], p : Int, little : Bool) -> Int {
  if little {
    data[p].to_int() | (data[p + 1].to_int() << 8) |
      (data[p + 2].to_int() << 16) | (data[p + 3].to_int() << 24)
  } else {
    (data[p].to_int() << 24) | (data[p + 1].to_int() << 16) |
      (data[p + 2].to_int() << 8) | data[p + 3].to_int()
  }
}

fn tiff_entry_value(
  data : Array[Byte],
  entry : Int,
  kind : Int,
  count : Int,
  little : Bool,
) -> Int? {
  if count != 1 { return None }
  if kind == 3 { Some(tiff_u16(data, entry + 8, little)) }
  else if kind == 4 { Some(tiff_u32(data, entry + 8, little)) }
  else if kind == 1 { Some(data[entry + 8].to_int()) }
  else { None }
}

fn tiff_bits_ok(
  data : Array[Byte],
  entry : Int,
  kind : Int,
  count : Int,
  little : Bool,
) -> Bool {
  if kind != 3 || count <= 0 { return false }
  let bytes = count * 2
  let start = if bytes <= 4 { entry + 8 } else { tiff_u32(data, entry + 8, little) }
  if start < 0 || start + bytes > data.length() { return false }
  for i in 0..<count {
    if tiff_u16(data, start + i * 2, little) != 8 { return false }
  }
  true
}

/// Decodes a classic uncompressed baseline TIFF into RGBA8 pixels.
pub fn tiff_decode(data : Array[Byte]) -> Image? {
  if data.length() < 8 { return None }
  let little = data[0] == b'I' && data[1] == b'I'
  if !little && !(data[0] == b'M' && data[1] == b'M') { return None }
  if tiff_u16(data, 2, little) != 42 { return None }
  let ifd = tiff_u32(data, 4, little)
  if ifd < 8 || ifd + 2 > data.length() { return None }
  let count = tiff_u16(data, ifd, little)
  let entries_end = ifd + 2 + count * 12
  if entries_end + 4 > data.length() { return None }
  let mut width = 0
  let mut height = 0
  let mut compression = 1
  let mut photometric = 2
  let mut samples = 0
  let mut strip_offset = 0
  let mut strip_bytes = 0
  let mut bits_entry = -1
  let mut bits_kind = 0
  let mut bits_count = 0
  for i in 0..<count {
    let entry = ifd + 2 + i * 12
    let tag = tiff_u16(data, entry, little)
    let kind = tiff_u16(data, entry + 2, little)
    let n = tiff_u32(data, entry + 4, little)
    match tag {
      256 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => width = v; None => () }
      257 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => height = v; None => () }
      258 => { bits_entry = entry; bits_kind = kind; bits_count = n }
      259 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => compression = v; None => () }
      262 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => photometric = v; None => () }
      273 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => strip_offset = v; None => () }
      277 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => samples = v; None => () }
      278 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => if v != height { return None }; None => () }
      279 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => strip_bytes = v; None => () }
      284 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => if v != 1 { return None }; None => () }
      _ => ()
    }
  }
  if width <= 0 || height <= 0 || compression != 1 || (photometric != 0 && photometric != 1 && photometric != 2) {
    return None
  }
  if samples == 0 { samples = if photometric == 2 { 3 } else { 1 } }
  if samples != 1 && samples != 3 && samples != 4 { return None }
  if bits_entry < 0 || !tiff_bits_ok(data, bits_entry, bits_kind, bits_count, little) { return None }
  if strip_offset < 0 || strip_bytes < 0 || strip_offset + strip_bytes > data.length() { return None }
  let expected = width * height * samples
  if strip_bytes < expected { return None }
  let out = Image::new(width, height)
  for p in 0..<(width * height) {
    let src = strip_offset + p * samples
    let dst = p * 4
    if samples == 1 {
      let value = data[src]
      let v = if photometric == 0 { clamp_byte(255 - value.to_int()) } else { value }
      out.data[dst] = v; out.data[dst + 1] = v; out.data[dst + 2] = v
    } else {
      out.data[dst] = data[src]; out.data[dst + 1] = data[src + 1]; out.data[dst + 2] = data[src + 2]
    }
    out.data[dst + 3] = if samples == 4 { data[src + 3] } else { b'\xFF' }
  }
  Some(out)
}
