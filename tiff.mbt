/// Restricted baseline TIFF decoder.
///
/// Supports little/big-endian classic TIFF (magic 42), multiple strips, tiled
/// images, PackBits/LZW compression, and a bounded BigTIFF subset. Samples are
/// chunky 8-bit grayscale/RGB/RGBA with photometric interpretation 0/1 or 2.
/// Deflate compression, palettes, predictors and BigTIFF files requiring
/// offsets above the host Int range return `None`.

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

fn tiff_range(data : Array[Byte], start : Int, length : Int) -> Bool {
  start >= 0 && length >= 0 && start <= data.length() && length <= data.length() - start
}

fn tiff_values(
  data : Array[Byte],
  entry : Int,
  kind : Int,
  count : Int,
  little : Bool,
) -> Array[Int]? {
  if count <= 0 || (kind != 3 && kind != 4) { return None }
  let size = if kind == 3 { 2 } else { 4 }
  if count > data.length() / size { return None }
  let total = count * size
  let start = if total <= 4 { entry + 8 } else { tiff_u32(data, entry + 8, little) }
  if !tiff_range(data, start, total) { return None }
  let values : Array[Int] = []
  for i in 0..<count {
    values.push(if kind == 3 { tiff_u16(data, start + i * size, little) } else { tiff_u32(data, start + i * size, little) })
  }
  Some(values)
}

fn tiff_packbits(data : Array[Byte], start : Int, length : Int, limit : Int) -> Array[Byte]? {
  if !tiff_range(data, start, length) || limit < 0 { return None }
  let out : Array[Byte] = []
  let end = start + length
  let mut p = start
  while p < end {
    let header = data[p].to_int()
    p = p + 1
    if header <= 127 {
      let count = header + 1
      if count > end - p || count > limit - out.length() { return None }
      for i in 0..<count { out.push(data[p + i]) }
      p = p + count
    } else if header >= 129 {
      if p >= end { return None }
      let value = data[p]
      p = p + 1
      let count = 257 - header
      if count > limit - out.length() { return None }
      for _ in 0..<count { out.push(value) }
    }
  }
  if out.length() != limit { None } else { Some(out) }
}

/// TIFF LZW uses MSB-first codes with a 9..12 bit code width.
fn tiff_lzw(data : Array[Byte], start : Int, length : Int, limit : Int) -> Array[Byte]? {
  if !tiff_range(data, start, length) || limit < 0 { return None }
  let dictionary : Array[Array[Byte]] = Array::make(4096, [])
  let mut bit_pos = 0
  let mut code_bits = 9
  let mut next_code = 258
  let mut previous : Array[Byte]? = None
  let out : Array[Byte] = []
  let read_code = () => {
    if bit_pos + code_bits > length * 8 { return None }
    let mut value = 0
    for _ in 0..<code_bits {
      let byte = data[start + bit_pos / 8].to_int()
      value = (value << 1) | ((byte >> (7 - bit_pos % 8)) & 1)
      bit_pos = bit_pos + 1
    }
    Some(value)
  }
  let mut finished = false
  while !finished {
    let code = match read_code() { Some(v) => v; None => return None }
    if code == 256 {
      for i in 0..<4096 { dictionary[i] = [] }
      code_bits = 9; next_code = 258; previous = None
      continue
    }
    if code == 257 { finished = true; continue }
    let sequence = if code < 256 {
      [code.to_byte()]
    } else if code < next_code {
      dictionary[code]
    } else if code == next_code && previous is Some(prev) {
      let candidate = prev.copy(); candidate.push(prev[0]); candidate
    } else { return None }
    if sequence.length() > limit - out.length() { return None }
    for byte in sequence { out.push(byte) }
    if previous is Some(prev) && next_code < 4096 {
      let entry = prev.copy(); entry.push(sequence[0]); dictionary[next_code] = entry
      next_code = next_code + 1
      if next_code == (1 << code_bits) - 1 && code_bits < 12 { code_bits = code_bits + 1 }
    }
    previous = Some(sequence)
  }
  if out.length() == limit && finished { Some(out) } else { None }
}

fn tiff_write_pixel(out : Image, dst : Int, raw : Array[Byte], src : Int, samples : Int, photometric : Int) -> Unit {
  if samples == 1 {
    let value = raw[src]
    let v = if photometric == 0 { clamp_byte(255 - value.to_int()) } else { value }
    out.data[dst] = v; out.data[dst + 1] = v; out.data[dst + 2] = v; out.data[dst + 3] = b'\xFF'
  } else {
    out.data[dst] = raw[src]; out.data[dst + 1] = raw[src + 1]; out.data[dst + 2] = raw[src + 2]
    out.data[dst + 3] = if samples == 4 { raw[src + 3] } else { b'\xFF' }
  }
}

fn tiff_bits_ok(
  data : Array[Byte],
  entry : Int,
  kind : Int,
  count : Int,
  little : Bool,
) -> Bool {
  if kind != 3 || count <= 0 { return false }
  if count > data.length() / 2 { return false }
  let bytes = count * 2
  let start = if bytes <= 4 { entry + 8 } else { tiff_u32(data, entry + 8, little) }
  if !tiff_range(data, start, bytes) { return false }
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
  let magic = tiff_u16(data, 2, little)
  if magic == 43 { return tiff_decode_bigtiff(data) }
  if magic != 42 { return None }
  let ifd = tiff_u32(data, 4, little)
  if ifd < 8 || !tiff_range(data, ifd, 2) { return None }
  let count = tiff_u16(data, ifd, little)
  if !tiff_range(data, ifd, 2 + count * 12 + 4) { return None }
  let mut width = 0
  let mut height = 0
  let mut compression = 1
  let mut photometric = 2
  let mut samples = 0
  let mut strip_offsets : Array[Int] = []
  let mut strip_byte_counts : Array[Int] = []
  let mut rows_per_strip = 0
  let mut tile_width = 0
  let mut tile_height = 0
  let mut tile_offsets : Array[Int] = []
  let mut tile_byte_counts : Array[Int] = []
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
      273 => match tiff_values(data, entry, kind, n, little) { Some(v) => strip_offsets = v; None => () }
      277 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => samples = v; None => () }
      278 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => rows_per_strip = v; None => () }
      279 => match tiff_values(data, entry, kind, n, little) { Some(v) => strip_byte_counts = v; None => () }
      322 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => tile_width = v; None => () }
      323 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => tile_height = v; None => () }
      324 => match tiff_values(data, entry, kind, n, little) { Some(v) => tile_offsets = v; None => () }
      325 => match tiff_values(data, entry, kind, n, little) { Some(v) => tile_byte_counts = v; None => () }
      284 => match tiff_entry_value(data, entry, kind, n, little) { Some(v) => if v != 1 { return None }; None => () }
      _ => ()
    }
  }
  if width <= 0 || height <= 0 || (compression != 1 && compression != 5 && compression != 32773) || (photometric != 0 && photometric != 1 && photometric != 2) {
    return None
  }
  if width > MAX_IMAGE_PIXELS / height { return None }
  if samples == 0 { samples = if photometric == 2 { 3 } else { 1 } }
  if samples != 1 && samples != 3 && samples != 4 { return None }
  if (photometric == 2 && samples == 1) || (photometric != 2 && samples != 1) || bits_count != samples { return None }
  if bits_entry < 0 || !tiff_bits_ok(data, bits_entry, bits_kind, bits_count, little) { return None }
  let tile_mode = tile_width > 0 || tile_height > 0 || tile_offsets.length() > 0 || tile_byte_counts.length() > 0
  if tile_mode {
    if tile_width <= 0 || tile_height <= 0 || tile_offsets.length() == 0 || tile_offsets.length() != tile_byte_counts.length() ||
      width > MAX_IMAGE_PIXELS / height || tile_width > MAX_IMAGE_PIXELS / tile_height { return None }
    let tiles_x = (width + tile_width - 1) / tile_width
    let tiles_y = (height + tile_height - 1) / tile_height
    if tile_offsets.length() != tiles_x * tiles_y { return None }
    let tile_expected = tile_width * tile_height * samples
    let out = Image::new(width, height)
    for tile in 0..<tile_offsets.length() {
      let raw = if compression == 1 {
        let start = tile_offsets[tile]; let length = tile_byte_counts[tile]
        if !tiff_range(data, start, length) || length != tile_expected { return None }
        let bytes : Array[Byte] = []
        for i in 0..<tile_expected { bytes.push(data[start + i]) }
        Some(bytes)
      } else if compression == 32773 {
        tiff_packbits(data, tile_offsets[tile], tile_byte_counts[tile], tile_expected)
      } else if compression == 5 {
        tiff_lzw(data, tile_offsets[tile], tile_byte_counts[tile], tile_expected)
      } else { None }
      let raw = match raw { Some(v) => v; None => return None }
      let tx = tile % tiles_x; let ty = tile / tiles_x
      let actual_width = if tx * tile_width + tile_width > width { width - tx * tile_width } else { tile_width }
      let actual_height = if ty * tile_height + tile_height > height { height - ty * tile_height } else { tile_height }
      for y in 0..<actual_height {
        for x in 0..<actual_width {
          let src = (y * tile_width + x) * samples
          let dst = ((ty * tile_height + y) * width + tx * tile_width + x) * 4
          tiff_write_pixel(out, dst, raw, src, samples, photometric)
        }
      }
    }
    return Some(out)
  }
  if strip_offsets.length() == 0 || strip_offsets.length() != strip_byte_counts.length() { return None }
  if rows_per_strip <= 0 { rows_per_strip = height }
  if strip_offsets.length() != (height - 1) / rows_per_strip + 1 { return None }
  let out = Image::new(width, height)
  let row_bytes = width * samples
  let mut row = 0
  for strip in 0..<strip_offsets.length() {
    if row >= height { break }
    let strip_rows = if rows_per_strip > height - row { height - row } else { rows_per_strip }
    let expected = strip_rows * row_bytes
    let raw = if compression == 1 {
      let start = strip_offsets[strip]
      let length = strip_byte_counts[strip]
      if !tiff_range(data, start, length) || length != expected { return None }
      let bytes : Array[Byte] = []
      for i in 0..<expected { bytes.push(data[start + i]) }
      Some(bytes)
    } else if compression == 32773 {
      tiff_packbits(data, strip_offsets[strip], strip_byte_counts[strip], expected)
    } else if compression == 5 {
      tiff_lzw(data, strip_offsets[strip], strip_byte_counts[strip], expected)
    } else {
      None
    }
    let raw = match raw { Some(bytes) => bytes; None => return None }
    for p in 0..<expected {
      let src = p
      let dst = ((row * width * samples + p) / samples) * 4
      let channel = p % samples
      if channel == 0 { tiff_write_pixel(out, dst, raw, src, samples, photometric) }
    }
    row = row + strip_rows
  }
  if row < height { return None }
  Some(out)
}

fn tiff_u64_int(data : Array[Byte], p : Int, little : Bool) -> Int? {
  if !tiff_range(data, p, 8) { return None }
  let low = if little { tiff_u32(data, p, true) } else { tiff_u32(data, p + 4, false) }
  let high = if little { tiff_u32(data, p + 4, true) } else { tiff_u32(data, p, false) }
  if high != 0 || low < 0 { None } else { Some(low) }
}

fn tiff_big_values(
  data : Array[Byte],
  entry : Int,
  kind : Int,
  count : Int,
  little : Bool,
) -> Array[Int]? {
  if count <= 0 { return None }
  let size = if kind == 3 { 2 } else if kind == 4 { 4 } else if kind == 16 { 8 } else { 0 }
  if size == 0 { return None }
  if count > data.length() / size { return None }
  let total = count * size
  let start = if total <= 8 {
    entry + 12
  } else {
    match tiff_u64_int(data, entry + 12, little) { Some(v) => v; None => return None }
  }
  if !tiff_range(data, start, total) { return None }
  let values : Array[Int] = []
  for i in 0..<count {
    let p = start + i * size
    let value = if kind == 3 { tiff_u16(data, p, little) } else if kind == 4 { tiff_u32(data, p, little) } else {
      match tiff_u64_int(data, p, little) { Some(v) => v; None => return None }
    }
    values.push(value)
  }
  Some(values)
}

/// Minimal BigTIFF subset: classic RGBA sample semantics, one uncompressed,
/// PackBits or LZW strip, and 64-bit offsets whose high word fits the host Int.
fn tiff_decode_bigtiff(data : Array[Byte]) -> Image? {
  if data.length() < 16 { return None }
  let little = data[0] == b'I' && data[1] == b'I'
  if !little && !(data[0] == b'M' && data[1] == b'M') { return None }
  if tiff_u16(data, 2, little) != 43 || tiff_u16(data, 4, little) != 8 || tiff_u16(data, 6, little) != 0 { return None }
  let ifd = match tiff_u64_int(data, 8, little) { Some(v) => v; None => return None }
  if ifd < 16 || !tiff_range(data, ifd, 8) { return None }
  let count = match tiff_u64_int(data, ifd, little) { Some(v) => v; None => return None }
  if count <= 0 || count > (data.length() - ifd - 8) / 20 || !tiff_range(data, ifd, 8 + count * 20 + 8) { return None }
  let mut width = 0
  let mut height = 0
  let mut compression = 1
  let mut photometric = 2
  let mut samples = 0
  let mut rows_per_strip = 0
  let mut bits_ok = false
  let mut bits_count = 0
  let mut strip_offset = 0
  let mut strip_bytes = 0
  for i in 0..<count {
    let entry = ifd + 8 + i * 20
    let tag = tiff_u16(data, entry, little)
    let kind = tiff_u16(data, entry + 2, little)
    let n = match tiff_u64_int(data, entry + 4, little) { Some(v) => v; None => return None }
    let values = match tiff_big_values(data, entry, kind, n, little) { Some(v) => v; None => continue }
    match tag {
      256 => width = values[0]
      257 => height = values[0]
      258 => { bits_count = values.length(); bits_ok = values.length() > 0; for value in values { if value != 8 { bits_ok = false } } }
      259 => compression = values[0]
      262 => photometric = values[0]
      273 => { if values.length() != 1 { return None }; strip_offset = values[0] }
      277 => samples = values[0]
      278 => rows_per_strip = values[0]
      279 => { if values.length() != 1 { return None }; strip_bytes = values[0] }
      284 => if values[0] != 1 { return None }
      _ => ()
    }
  }
  if width <= 0 || height <= 0 || !bits_ok || rows_per_strip < height ||
    !tiff_range(data, strip_offset, strip_bytes) || (compression != 1 && compression != 5 && compression != 32773) ||
    (photometric != 0 && photometric != 1 && photometric != 2) { return None }
  if samples == 0 { samples = if photometric == 2 { 3 } else { 1 } }
  if width > MAX_IMAGE_PIXELS / height { return None }
  if samples != 1 && samples != 3 && samples != 4 { return None }
  if (photometric == 2 && samples == 1) || (photometric != 2 && samples != 1) || bits_count != samples { return None }
  let expected = width * height * samples
  let raw = if compression == 1 {
    if strip_bytes != expected { return None }
    let bytes : Array[Byte] = []
    for i in 0..<expected { bytes.push(data[strip_offset + i]) }
    Some(bytes)
  } else if compression == 32773 { tiff_packbits(data, strip_offset, strip_bytes, expected) }
  else { tiff_lzw(data, strip_offset, strip_bytes, expected) }
  let raw = match raw { Some(v) => v; None => return None }
  let out = Image::new(width, height)
  for p in 0..<(width * height) {
    let src = p * samples
    let dst = p * 4
    if samples == 1 {
      let value = raw[src]
      let v = if photometric == 0 { clamp_byte(255 - value.to_int()) } else { value }
      out.data[dst] = v; out.data[dst + 1] = v; out.data[dst + 2] = v; out.data[dst + 3] = b'\xFF'
    } else {
      out.data[dst] = raw[src]; out.data[dst + 1] = raw[src + 1]; out.data[dst + 2] = raw[src + 2]
      out.data[dst + 3] = if samples == 4 { raw[src + 3] } else { b'\xFF' }
    }
  }
  Some(out)
}
