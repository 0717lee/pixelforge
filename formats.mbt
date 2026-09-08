/// Image container identification and lightweight metadata parsing.
///
/// This module deliberately does not decode compressed JPEG/WebP/AVIF/TIFF
/// pixels. It gives callers a deterministic, allocation-light way to inspect
/// uploads before selecting a backend decoder.

///|
pub(all) enum ImageFormat {
  Png
  Gif
  Qoi
  Bmp
  Jpeg
  Webp
  Avif
  Tiff
}

///|
pub fn ImageFormat::name(self : ImageFormat) -> String {
  match self {
    Png => "png"
    Gif => "gif"
    Qoi => "qoi"
    Bmp => "bmp"
    Jpeg => "jpeg"
    Webp => "webp"
    Avif => "avif"
    Tiff => "tiff"
  }
}

/// Width, height and animation hint read from an image container header.
pub(all) struct ImageMetadata {
  format : ImageFormat
  width : Int
  height : Int
  animated : Bool
}

fn be16(data : Array[Byte], p : Int) -> Int {
  (data[p].to_int() << 8) | data[p + 1].to_int()
}

fn be32(data : Array[Byte], p : Int) -> Int {
  (data[p].to_int() << 24) | (data[p + 1].to_int() << 16) |
    (data[p + 2].to_int() << 8) | data[p + 3].to_int()
}

fn le16(data : Array[Byte], p : Int) -> Int {
  data[p].to_int() | (data[p + 1].to_int() << 8)
}

fn le32(data : Array[Byte], p : Int) -> Int {
  data[p].to_int() | (data[p + 1].to_int() << 8) |
    (data[p + 2].to_int() << 16) | (data[p + 3].to_int() << 24)
}

fn ascii4(data : Array[Byte], p : Int, a : Int, b : Int, c : Int, d : Int) -> Bool {
  data.length() >= p + 4 && data[p].to_int() == a && data[p + 1].to_int() == b &&
    data[p + 2].to_int() == c && data[p + 3].to_int() == d
}

/// Identifies common raster containers from their signatures and brands.
pub fn detect_image_format(data : Array[Byte]) -> ImageFormat? {
  if data.length() >= 8 && data[0] == b'\x89' && ascii4(data, 1, 80, 78, 71, 13) {
    Some(Png)
  } else if data.length() >= 6 && ascii4(data, 0, 71, 73, 70, 56) {
    Some(Gif)
  } else if data.length() >= 4 && ascii4(data, 0, 113, 111, 105, 102) {
    Some(Qoi)
  } else if data.length() >= 2 && data[0] == b'B' && data[1] == b'M' {
    Some(Bmp)
  } else if data.length() >= 2 && data[0] == b'\xFF' && data[1] == b'\xD8' {
    Some(Jpeg)
  } else if data.length() >= 12 && ascii4(data, 0, 82, 73, 70, 70) && ascii4(data, 8, 87, 69, 66, 80) {
    Some(Webp)
  } else if data.length() >= 8 && ascii4(data, 4, 102, 116, 121, 112) && is_avif_brand(data, 8) {
    Some(Avif)
  } else if data.length() >= 4 &&
    ((data[0] == b'I' && data[1] == b'I' && data[2] == b'*' && data[3] == b'\x00') ||
      (data[0] == b'M' && data[1] == b'M' && data[2] == b'\x00' && data[3] == b'*')) {
    Some(Tiff)
  } else {
    None
  }
}

fn is_avif_brand(data : Array[Byte], p : Int) -> Bool {
  ascii4(data, p, 97, 118, 105, 102) || ascii4(data, p, 97, 118, 105, 115) ||
    ascii4(data, p, 104, 101, 105, 99) || ascii4(data, p, 104, 101, 105, 120) ||
    ascii4(data, p, 109, 105, 102, 49)
}

/// Parses dimensions for supported headers. Returns `None` for truncated or
/// valid-but-unhandled variants whose dimensions are not present in the probe.
pub fn image_metadata(data : Array[Byte]) -> ImageMetadata? {
  let format = match detect_image_format(data) {
    Some(value) => value
    None => return None
  }
  match format {
    Png => if data.length() >= 24 {
      Some({ format, width: be32(data, 16), height: be32(data, 20), animated: false })
    } else { None }
    Gif => if data.length() >= 10 {
      Some({ format, width: le16(data, 6), height: le16(data, 8), animated: gif_has_animation(data) })
    } else { None }
    Qoi => if data.length() >= 14 {
      Some({ format, width: be32(data, 4), height: be32(data, 8), animated: false })
    } else { None }
    Bmp => if data.length() >= 26 {
      let w = le32(data, 18)
      let h0 = le32(data, 22)
      let h = if h0 < 0 { -h0 } else { h0 }
      Some({ format, width: w, height: h, animated: false })
    } else { None }
    Jpeg => jpeg_metadata(data, format)
    Webp => webp_metadata(data, format)
    Avif => bmff_metadata(data, format)
    Tiff => tiff_metadata(data, format)
  }
}

fn gif_has_animation(data : Array[Byte]) -> Bool {
  let marker : Array[Byte] = [
    b'N', b'E', b'T', b'S', b'C', b'A', b'P', b'E', b'2', b'.', b'0',
  ]
  if data.length() < marker.length() { return false }
  for p in 0..<(data.length() - marker.length() + 1) {
    let mut found = true
    for i in 0..<marker.length() {
      if data[p + i] != marker[i] { found = false; break }
    }
    if found { return true }
  }
  false
}

fn jpeg_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let mut p = 2
  while p + 9 < data.length() {
    if data[p] != b'\xFF' { p += 1; continue }
    let marker = data[p + 1].to_int()
    if marker == 0xD9 || marker == 0xDA { return None }
    if (marker >= 0xC0 && marker <= 0xC3) || (marker >= 0xC5 && marker <= 0xC7) || (marker >= 0xC9 && marker <= 0xCB) || (marker >= 0xCD && marker <= 0xCF) {
      let h = be16(data, p + 5)
      let w = be16(data, p + 7)
      return Some({ format, width: w, height: h, animated: false })
    }
    if p + 4 > data.length() { return None }
    let segment = be16(data, p + 2)
    if segment < 2 { return None }
    p = p + 2 + segment
  }
  None
}

fn webp_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  if data.length() >= 30 && ascii4(data, 12, 86, 80, 56, 88) {
    let w = 1 + (data[24].to_int() | (data[25].to_int() << 8) | (data[26].to_int() << 16))
    let h = 1 + (data[27].to_int() | (data[28].to_int() << 8) | (data[29].to_int() << 16))
    Some({ format, width: w, height: h, animated: (data[20].to_int() & 2) != 0 })
  } else { None }
}

fn bmff_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let mut p = 8
  while p + 12 <= data.length() {
    let size = be32(data, p)
    if size < 8 || p + size > data.length() { return None }
    if ascii4(data, p + 4, 105, 115, 112, 101) && size >= 28 {
      return Some({ format, width: be32(data, p + 20), height: be32(data, p + 24), animated: false })
    } else {
      p = p + size
      continue
    }
  }
  None
}

fn tiff_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let little = data[0] == b'I'
  let rd16 = (p : Int) => if little { le16(data, p) } else { be16(data, p) }
  let rd32 = (p : Int) => if little { le32(data, p) } else { be32(data, p) }
  if data.length() < 8 { return None }
  let ifd = rd32(4)
  if ifd < 8 || ifd + 2 > data.length() { return None }
  let count = rd16(ifd)
  let mut p = ifd + 2
  let mut w = 0
  let mut h = 0
  for _ in 0..<count {
    if p + 12 > data.length() { return None }
    let tag = rd16(p)
    let value = if rd16(p + 2) == 3 { rd16(p + 8) } else { rd32(p + 8) }
    if tag == 256 { w = value }
    if tag == 257 { h = value }
    p += 12
  }
  if w > 0 && h > 0 { Some({ format, width: w, height: h, animated: false }) } else { None }
}
