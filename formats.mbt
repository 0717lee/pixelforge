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

///|
/// Width, height and animation hint read from an image container header.
pub(all) struct ImageMetadata {
  format : ImageFormat
  width : Int
  height : Int
  animated : Bool
}

///|
fn be16(data : Array[Byte], p : Int) -> Int {
  (data[p].to_int() << 8) | data[p + 1].to_int()
}

///|
fn be32(data : Array[Byte], p : Int) -> Int {
  (data[p].to_int() << 24) |
  (data[p + 1].to_int() << 16) |
  (data[p + 2].to_int() << 8) |
  data[p + 3].to_int()
}

///|
fn le16(data : Array[Byte], p : Int) -> Int {
  data[p].to_int() | (data[p + 1].to_int() << 8)
}

///|
fn le32(data : Array[Byte], p : Int) -> Int {
  data[p].to_int() |
  (data[p + 1].to_int() << 8) |
  (data[p + 2].to_int() << 16) |
  (data[p + 3].to_int() << 24)
}

///|
fn ascii4(
  data : Array[Byte],
  p : Int,
  a : Int,
  b : Int,
  c : Int,
  d : Int,
) -> Bool {
  data.length() >= p + 4 &&
  data[p].to_int() == a &&
  data[p + 1].to_int() == b &&
  data[p + 2].to_int() == c &&
  data[p + 3].to_int() == d
}

///|
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
  } else if data.length() >= 12 &&
    ascii4(data, 0, 82, 73, 70, 70) &&
    ascii4(data, 8, 87, 69, 66, 80) {
    Some(Webp)
  } else if bmff_avif_brand(data) is Some(_) {
    Some(Avif)
  } else if data.length() >= 4 &&
    (
      (
        data[0] == b'I' &&
        data[1] == b'I' &&
        data[2] == b'*' &&
        data[3] == b'\x00'
      ) ||
      (
        data[0] == b'M' &&
        data[1] == b'M' &&
        data[2] == b'\x00' &&
        data[3] == b'*'
      )
    ) {
    Some(Tiff)
  } else {
    None
  }
}

///|
priv struct BmffMetadataBox {
  kind : Int
  payload : Int
  end : Int
}

///|
// Bound each box by its parent before adding offsets. A 64-bit length larger
// than the input's Int-sized address space cannot describe an in-memory box.
fn bmff_metadata_box(
  data : Array[Byte],
  p : Int,
  end : Int,
) -> BmffMetadataBox? {
  if p < 0 || end > data.length() || end - p < 8 {
    return None
  }
  let mut size = be32(data, p)
  let mut header = 8
  if size == 1 {
    if end - p < 16 || be32(data, p + 8) != 0 {
      return None
    }
    size = be32(data, p + 12)
    header = 16
  } else if size == 0 {
    size = end - p
  }
  if size < header || size > end - p {
    return None
  }
  Some({ kind: be32(data, p + 4), payload: p + header, end: p + size, })
}

///|
fn bmff_metadata_boxes(
  data : Array[Byte],
  start : Int,
  end : Int,
) -> Array[BmffMetadataBox]? {
  let boxes = []
  let mut p = start
  while p < end {
    let box = match bmff_metadata_box(data, p, end) {
      Some(box) => box
      None => return None
    }
    boxes.push(box)
    p = box.end
  }
  Some(boxes)
}

///|
fn bmff_metadata_unique(
  boxes : Array[BmffMetadataBox],
  kind : Int,
) -> BmffMetadataBox? {
  let mut found = None
  for box in boxes {
    if box.kind == kind {
      if found is Some(_) {
        return None
      }
      found = Some(box)
    }
  }
  found
}

///|
// Some(animated) means an AVIF brand was declared. General HEIF brands such
// as mif1 and heic do not identify AVIF without an avif/avis compatible brand.
fn bmff_avif_brand(data : Array[Byte]) -> Bool? {
  let box = match bmff_metadata_box(data, 0, data.length()) {
    Some(box) => box
    None => return None
  }
  if box.kind != 0x66747970 ||
    box.end - box.payload < 8 ||
    (box.end - box.payload) % 4 != 0 {
    return None
  }
  let mut found = false
  let mut animated = false
  let mut p = box.payload
  while p < box.end {
    let brand = be32(data, p)
    if brand == 0x61766966 {
      found = true
    }
    if brand == 0x61766973 {
      found = true
      animated = true
    }
    // The word after major_brand is minor_version, not another brand.
    p += if p == box.payload { 8 } else { 4 }
  }
  if found {
    Some(animated)
  } else {
    None
  }
}

///|
/// Parses dimensions for supported headers. Returns `None` for truncated or
/// valid-but-unhandled variants whose dimensions are not present in the probe.
pub fn image_metadata(data : Array[Byte]) -> ImageMetadata? {
  let format = match detect_image_format(data) {
    Some(value) => value
    None => return None
  }
  match format {
    Png =>
      if data.length() >= 24 {
        Some({
          format,
          width: be32(data, 16),
          height: be32(data, 20),
          animated: false,
        })
      } else {
        None
      }
    Gif =>
      if data.length() >= 10 {
        Some({
          format,
          width: le16(data, 6),
          height: le16(data, 8),
          animated: gif_has_animation(data),
        })
      } else {
        None
      }
    Qoi =>
      if data.length() >= 14 {
        Some({
          format,
          width: be32(data, 4),
          height: be32(data, 8),
          animated: false,
        })
      } else {
        None
      }
    Bmp =>
      if data.length() >= 26 {
        let w = le32(data, 18)
        let h0 = le32(data, 22)
        let h = if h0 < 0 { -h0 } else { h0 }
        Some({ format, width: w, height: h, animated: false, })
      } else {
        None
      }
    Jpeg => jpeg_metadata(data, format)
    Webp => webp_metadata(data, format)
    Avif => bmff_metadata(data, format)
    Tiff => tiff_metadata(data, format)
  }
}

///|
fn gif_has_animation(data : Array[Byte]) -> Bool {
  let marker : Array[Byte] = [
    b'N', b'E', b'T', b'S', b'C', b'A', b'P', b'E', b'2', b'.', b'0',
  ]
  if data.length() < marker.length() {
    return false
  }
  for p in 0..<(data.length() - marker.length() + 1) {
    let mut found = true
    for i in 0..<marker.length() {
      if data[p + i] != marker[i] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}

///|
fn jpeg_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let mut p = 2
  while p + 9 < data.length() {
    if data[p] != b'\xFF' {
      p += 1
      continue
    }
    let marker = data[p + 1].to_int()
    if marker == 0xD9 || marker == 0xDA {
      return None
    }
    if (marker >= 0xC0 && marker <= 0xC3) ||
      (marker >= 0xC5 && marker <= 0xC7) ||
      (marker >= 0xC9 && marker <= 0xCB) ||
      (marker >= 0xCD && marker <= 0xCF) {
      let h = be16(data, p + 5)
      let w = be16(data, p + 7)
      return Some({ format, width: w, height: h, animated: false, })
    }
    if p + 4 > data.length() {
      return None
    }
    let segment = be16(data, p + 2)
    if segment < 2 {
      return None
    }
    p = p + 2 + segment
  }
  None
}

///|
fn webp_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  if data.length() >= 30 && ascii4(data, 12, 86, 80, 56, 88) {
    let w = 1 +
      (data[24].to_int() | (data[25].to_int() << 8) | (data[26].to_int() << 16))
    let h = 1 +
      (data[27].to_int() | (data[28].to_int() << 8) | (data[29].to_int() << 16))
    Some({
      format,
      width: w,
      height: h,
      animated: (data[20].to_int() & 2) != 0,
    })
  } else {
    None
  }
}

///|
fn bmff_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let animated = match bmff_avif_brand(data) {
    Some(animated) => animated
    None => return None
  }
  let boxes = match bmff_metadata_boxes(data, 0, data.length()) {
    Some(boxes) => boxes
    None => return None
  }
  let meta = match bmff_metadata_unique(boxes, 0x6D657461) { // meta
    Some(box) => box
    None => return None
  }
  if meta.end - meta.payload < 4 || be32(data, meta.payload) != 0 {
    return None
  }
  let children = match bmff_metadata_boxes(data, meta.payload + 4, meta.end) {
    Some(boxes) => boxes
    None => return None
  }
  let pitm = match bmff_metadata_unique(children, 0x7069746D) { // pitm
    Some(box) => box
    None => return None
  }
  if pitm.end - pitm.payload < 6 {
    return None
  }
  let primary = match be32(data, pitm.payload) {
    0 => {
      if pitm.end - pitm.payload != 6 {
        return None
      }
      be16(data, pitm.payload + 4)
    }
    0x01000000 => {
      if pitm.end - pitm.payload != 8 {
        return None
      }
      be32(data, pitm.payload + 4)
    }
    _ => return None
  }
  if primary == 0 {
    return None
  }
  let iprp = match bmff_metadata_unique(children, 0x69707270) { // iprp
    Some(box) => box
    None => return None
  }
  let property_boxes = match bmff_metadata_boxes(data, iprp.payload, iprp.end) {
    Some(boxes) => boxes
    None => return None
  }
  let ipco = match bmff_metadata_unique(property_boxes, 0x6970636F) { // ipco
    Some(box) => box
    None => return None
  }
  let properties = match bmff_metadata_boxes(data, ipco.payload, ipco.end) {
    Some(boxes) => boxes
    None => return None
  }
  let mut dimensions = None
  for ipma in property_boxes {
    if ipma.kind != 0x69706D61 {
      continue
    } // ipma
    if ipma.end - ipma.payload < 8 {
      return None
    }
    let version_flags = be32(data, ipma.payload)
    let version = version_flags >> 24
    if (version != 0 && version != 1) || (version_flags & 0xFFFFFE) != 0 {
      return None
    }
    let item_bytes = if version == 0 { 2 } else { 4 }
    let association_bytes = if (version_flags & 1) == 0 { 1 } else { 2 }
    let count = be32(data, ipma.payload + 4)
    let mut p = ipma.payload + 8
    if count < 0 || count > (ipma.end - p) / (item_bytes + 1) {
      return None
    }
    for _ in 0..<count {
      if ipma.end - p < item_bytes + 1 {
        return None
      }
      let item = if version == 0 { be16(data, p) } else { be32(data, p) }
      let associations = data[p + item_bytes].to_int()
      p += item_bytes + 1
      if associations > (ipma.end - p) / association_bytes {
        return None
      }
      for _ in 0..<associations {
        let index = if association_bytes == 1 {
          data[p].to_int() & 0x7F
        } else {
          be16(data, p) & 0x7FFF
        }
        p += association_bytes
        // Index zero is the explicit "no property" association.
        if index > properties.length() {
          return None
        }
        if item != primary || index == 0 {
          continue
        }
        let property = properties[index - 1]
        if property.kind != 0x69737065 {
          continue
        } // ispe
        if dimensions is Some(_) {
          return None
        }
        if property.end - property.payload != 12 ||
          be32(data, property.payload) != 0 {
          return None
        }
        let width = be32(data, property.payload + 4)
        let height = be32(data, property.payload + 8)
        if width <= 0 || height <= 0 {
          return None
        }
        dimensions = Some((width, height))
      }
    }
    if p != ipma.end {
      return None
    }
  }
  match dimensions {
    Some((width, height)) => Some({ format, width, height, animated, })
    None => None
  }
}

///|
fn tiff_metadata(data : Array[Byte], format : ImageFormat) -> ImageMetadata? {
  let little = data[0] == b'I'
  let rd16 = (p : Int) => if little { le16(data, p) } else { be16(data, p) }
  let rd32 = (p : Int) => if little { le32(data, p) } else { be32(data, p) }
  if data.length() < 8 {
    return None
  }
  let ifd = rd32(4)
  if ifd < 8 || ifd + 2 > data.length() {
    return None
  }
  let count = rd16(ifd)
  let mut p = ifd + 2
  let mut w = 0
  let mut h = 0
  for _ in 0..<count {
    if p + 12 > data.length() {
      return None
    }
    let tag = rd16(p)
    let value = if rd16(p + 2) == 3 { rd16(p + 8) } else { rd32(p + 8) }
    if tag == 256 {
      w = value
    }
    if tag == 257 {
      h = value
    }
    p += 12
  }
  if w > 0 && h > 0 {
    Some({ format, width: w, height: h, animated: false, })
  } else {
    None
  }
}
