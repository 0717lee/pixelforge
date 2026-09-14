/// Bounded AV1 tile-group payload extraction.
///
/// The frame-header parser still exposes the legacy one-tile payload directly.
/// This helper is a separate, side-effect-free boundary for the next multi-tile
/// stage: it validates the tile-count and size-prefix envelope, then returns
/// independent byte arrays for each tile.  It does not attempt entropy decoding.

///|
/// A validated tile payload and its position in a row-major tile group.
pub(all) struct Av1TilePayload {
  index : Int
  row : Int
  col : Int
  offset : Int
  length : Int
  bytes : Array[Byte]
}

///|
/// Extract tile payloads from a tile-group byte range.
///
/// `tile_size_bytes` is the AV1 `tile_size_bytes` value (1..4).  Every tile
/// except the last is preceded by a big-endian `tile_size_minus_1` field of
/// that width; the last tile consumes the remaining bytes.  A zero value is
/// accepted only for a single tile and means that the caller supplied the
/// already isolated legacy payload.  All arithmetic is checked before slicing
/// so malformed prefixes cannot expose out-of-range data.
pub fn av1_extract_tile_payloads(
  payload : Array[Byte],
  tile_cols : Int,
  tile_rows : Int,
  tile_size_bytes : Int,
) -> Array[Av1TilePayload]? {
  if tile_cols <= 0 || tile_rows <= 0 || tile_cols > 1024 || tile_rows > 1024 {
    return None
  }
  if tile_size_bytes < 0 ||
    tile_size_bytes > 4 ||
    (tile_size_bytes == 0 && (tile_cols != 1 || tile_rows != 1)) {
    return None
  }
  let tile_count = tile_cols * tile_rows
  if tile_count <= 0 || tile_count > 1_048_576 || payload.length() == 0 {
    return None
  }
  if tile_count == 1 && tile_size_bytes == 0 {
    let bytes : Array[Byte] = []
    for b in payload {
      bytes.push(b)
    }
    return Some([
      { index: 0, row: 0, col: 0, offset: 0, length: bytes.length(), bytes, },
    ])
  }
  if tile_size_bytes == 0 {
    return None
  }
  let mut cursor = 0
  let out : Array[Av1TilePayload] = []
  for index in 0..<tile_count {
    let prefix = if index + 1 < tile_count { tile_size_bytes } else { 0 }
    if cursor + prefix > payload.length() {
      return None
    }
    let length = if prefix == 0 {
      payload.length() - cursor
    } else {
      let mut minus_one = 0
      for i in 0..<prefix {
        minus_one = (minus_one << 8) | payload[cursor + i].to_int()
      }
      // `tile_size_minus_1` is bounded by the remaining bytes before adding 1.
      if minus_one < 0 || minus_one >= payload.length() - cursor - prefix {
        return None
      }
      minus_one + 1
    }
    let data_start = cursor + prefix
    if length <= 0 || data_start + length > payload.length() {
      return None
    }
    let bytes : Array[Byte] = []
    for i in data_start..<(data_start + length) {
      bytes.push(payload[i])
    }
    out.push({
      index,
      row: index / tile_cols,
      col: index % tile_cols,
      offset: data_start,
      length,
      bytes,
    })
    cursor = data_start + length
  }
  if cursor != payload.length() {
    return None
  }
  Some(out)
}
