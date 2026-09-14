/// Compose decoded grid tiles into one RGBA image.
///
/// Tile bytes are decoded by the caller through the normal AV1 path. This
/// helper only performs bounded placement and crops tiles at the output edge.
pub fn avif_reconstruct_grid(
  rows : Int,
  columns : Int,
  output_width : Int,
  output_height : Int,
  tiles : Array[Image],
) -> Image? {
  if rows <= 0 || columns <= 0 || output_width <= 0 || output_height <= 0 ||
    rows > 32 || columns > 32 || tiles.length() != rows * columns {
    return None
  }
  let first = tiles[0]
  if first.width <= 0 || first.height <= 0 {
    return None
  }
  let out = Image::new(output_width, output_height)
  for index in 0..<tiles.length() {
    let tile = tiles[index]
    if tile.width <= 0 || tile.height <= 0 {
      return None
    }
    let row = index / columns
    let col = index % columns
    let ox = col * first.width
    let oy = row * first.height
    if ox >= output_width || oy >= output_height {
      return None
    }
    let copy_w = if output_width - ox < tile.width {
      output_width - ox
    } else {
      tile.width
    }
    let copy_h = if output_height - oy < tile.height {
      output_height - oy
    } else {
      tile.height
    }
    for y in 0..<copy_h {
      for x in 0..<copy_w {
        let p = tile.get_pixel(x, y)
        out.set_pixel(ox + x, oy + y, p.0, p.1, p.2, p.3)
      }
    }
  }
  Some(out)
}

/// Decode ordered AV1 grid tile samples and compose them into one image.
/// The samples must be in row-major grid order; unsupported tile syntax
/// rejects the whole image instead of returning a partial reconstruction.
pub fn avif_decode_grid_tiles(
  rows : Int,
  columns : Int,
  output_width : Int,
  output_height : Int,
  samples : Array[Array[Byte]],
) -> Image? {
  if rows <= 0 || columns <= 0 || samples.length() != rows * columns {
    return None
  }
  let images : Array[Image] = []
  for sample in samples {
    let image = match av1_decode(sample) {
      Some(value) => value
      None => return None
    }
    images.push(image)
  }
  avif_reconstruct_grid(rows, columns, output_width, output_height, images)
}

/// Decode a grid directly from a BMFF buffer and its parsed descriptor.
/// Each tile may contain one or more iloc extents; extents are concatenated
/// before passing the sample to the pure AV1 decoder.
pub fn avif_decode_grid(
  data : Array[Byte],
  descriptor : AvifGridDescriptor,
) -> Image? {
  let samples : Array[Array[Byte]] = []
  for tile in descriptor.tiles {
    let sample : Array[Byte] = []
    for extent in tile.extents {
      if extent.offset < 0 || extent.length < 0 ||
        extent.offset > data.length() - extent.length {
        return None
      }
      for i in extent.offset..<(extent.offset + extent.length) {
        sample.push(data[i])
      }
    }
    if sample.length() == 0 { return None }
    samples.push(sample)
  }
  avif_decode_grid_tiles(
    descriptor.rows,
    descriptor.columns,
    descriptor.output_width,
    descriptor.output_height,
    samples,
  )
}

/// Decode and compose a grid directly from a BMFF buffer.  This convenience
/// entrypoint performs descriptor extraction and pixel reconstruction as one
/// operation, so callers cannot accidentally skip the `dimg` ordering or
/// extent validation step.
pub fn avif_decode_grid_auto(data : Array[Byte]) -> Image? {
  let descriptor = match avif_grid_descriptor(data) {
    Some(value) => value
    None => return None
  }
  avif_decode_grid(data, descriptor)
}

///|
test "grid reconstruction crops edge tiles and preserves order" {
  let a = Image::new(2, 2)
  a.set_pixel(0, 0, b'\x11', b'\x00', b'\x00', b'\xFF')
  let b = Image::new(2, 2)
  b.set_pixel(0, 0, b'\x22', b'\x00', b'\x00', b'\xFF')
  let out = avif_reconstruct_grid(1, 2, 3, 2, [a, b]).unwrap()
  assert_eq(out.get_pixel(0, 0), (b'\x11', b'\x00', b'\x00', b'\xFF'))
  assert_eq(out.get_pixel(2, 0), (b'\x22', b'\x00', b'\x00', b'\xFF'))
}

///|
test "grid reconstruction rejects mismatched tile counts" {
  assert_true(avif_reconstruct_grid(2, 2, 4, 4, []) is None)
}

/// Multiple iloc extents are concatenated before AV1 decoding.  Construction
/// method is metadata only at this stage; the descriptor has already resolved
/// each extent to a data-relative offset.
test "grid decoder concatenates split construction-method extents" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
    b'\x32', b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00',
    b'\x00', b'\x00', b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43',
    b'\xD9', b'\x3A', b'\x46', b'\x02', b'\x28',
  ]
  let data : Array[Byte] = []
  for b in sample { data.push(b) }
  let descriptor : AvifGridDescriptor = {
    item_id: 1,
    rows: 1,
    columns: 1,
    output_width: 64,
    output_height: 64,
    tiles: [{
      item_id: 2,
      extents: [
        { offset: 0, length: 8, construction_method: 1 },
        { offset: 8, length: sample.length() - 8, construction_method: 1 },
      ],
    }],
  }
  let image = avif_decode_grid(data, descriptor).unwrap()
  assert_eq((image.width, image.height), (64, 64))
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}

///|
test "grid tile decoder composes ordered AV1 samples" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
    b'\x32', b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00',
    b'\x00', b'\x00', b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43',
    b'\xD9', b'\x3A', b'\x46', b'\x02', b'\x28',
  ]
  let image = avif_decode_grid_tiles(1, 2, 128, 64, [sample, sample]).unwrap()
  assert_eq(image.width, 128)
  assert_eq(image.height, 64)
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}

/// Build a minimal self-contained ISO BMFF grid.  The tile payloads are real
/// AV1 OBUs; the grid descriptor and references are carried in `meta` and the
/// item extents point into the following `mdat` box.
fn grid_e2e_u32(x : Int) -> Array[Byte] {
  [(x >> 24).to_byte(), (x >> 16).to_byte(), (x >> 8).to_byte(), x.to_byte()]
}

fn grid_e2e_box(typ : Array[Byte], payload : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  for b in grid_e2e_u32(payload.length() + 8) { out.push(b) }
  for b in typ { out.push(b) }
  for b in payload { out.push(b) }
  out
}

fn grid_e2e_type(a : Int, b : Int, c : Int, d : Int) -> Array[Byte] {
  [a.to_byte(), b.to_byte(), c.to_byte(), d.to_byte()]
}

test "grid decoder parses BMFF metadata and decodes tile pixels" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08',
    b'\x32', b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00',
    b'\x00', b'\x00', b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43',
    b'\xD9', b'\x3A', b'\x46', b'\x02', b'\x28',
  ]
  let grid_item : Array[Byte] = [0, 0, 0, 0, 0, 1, 0, 128, 0, 64]
  let infe_grid = grid_e2e_box(grid_e2e_type(0x69, 0x6E, 0x66, 0x65),
    [0, 0, 0, 2, 0, 1, 0, 0, 0x67, 0x72, 0x69, 0x64])
  let infe_tile1 = grid_e2e_box(grid_e2e_type(0x69, 0x6E, 0x66, 0x65),
    [0, 0, 0, 2, 0, 2, 0, 0, 0x61, 0x76, 0x30, 0x31])
  let infe_tile2 = grid_e2e_box(grid_e2e_type(0x69, 0x6E, 0x66, 0x65),
    [0, 0, 0, 2, 0, 3, 0, 0, 0x61, 0x76, 0x30, 0x31])
  let iinf_payload : Array[Byte] = [0, 0, 0, 0, 0, 3]
  for b in infe_grid { iinf_payload.push(b) }
  for b in infe_tile1 { iinf_payload.push(b) }
  for b in infe_tile2 { iinf_payload.push(b) }
  let iinf = grid_e2e_box(grid_e2e_type(0x69, 0x69, 0x6E, 0x66), iinf_payload)

  // meta is assembled once to determine the absolute mdat offsets.
  let dummy_iloc : Array[Byte] = [0, 0, 0, 0, 0x44, 0, 0, 3]
  for id in [1, 2, 3] {
    dummy_iloc.push(0); dummy_iloc.push(id.to_byte());
    dummy_iloc.push(0); dummy_iloc.push(0)
    dummy_iloc.push(0); dummy_iloc.push(1)
    for _ in 0..<4 { dummy_iloc.push(0) }
    for _ in 0..<4 { dummy_iloc.push(0) }
  }
  let dummy_meta_payload : Array[Byte] = [0, 0, 0, 0]
  for b in iinf { dummy_meta_payload.push(b) }
  let dummy_iloc_box = grid_e2e_box(grid_e2e_type(0x69, 0x6C, 0x6F, 0x63), dummy_iloc)
  for b in dummy_iloc_box { dummy_meta_payload.push(b) }
  let dimg_payload : Array[Byte] = [0, 1, 0, 2, 0, 2, 0, 3]
  let dimg = grid_e2e_box(grid_e2e_type(0x64, 0x69, 0x6D, 0x67), dimg_payload)
  let iref_payload : Array[Byte] = [0, 0, 0, 0, 0, 0, 0, 1]
  for b in dimg { iref_payload.push(b) }
  let iref = grid_e2e_box(grid_e2e_type(0x69, 0x72, 0x65, 0x66), iref_payload)
  for b in iref { dummy_meta_payload.push(b) }
  let dummy_meta = grid_e2e_box(grid_e2e_type(0x6D, 0x65, 0x74, 0x61), dummy_meta_payload)
  let mdat_start = dummy_meta.length() + 8
  let grid_off = mdat_start
  let tile1_off = grid_off + grid_item.length()
  // Rebuild iloc with absolute offsets and exact lengths.
  let iloc_payload : Array[Byte] = [0, 0, 0, 0, 0x44, 0, 0, 3]
  let offsets = [grid_off, tile1_off, tile1_off + sample.length()]
  let lengths = [grid_item.length(), sample.length(), sample.length()]
  for i in 0..<3 {
    let id = i + 1
    let off = offsets[i]
    let len = lengths[i]
    iloc_payload.push(0); iloc_payload.push(id.to_byte()); iloc_payload.push(0); iloc_payload.push(0)
    iloc_payload.push(0); iloc_payload.push(1)
    for b in grid_e2e_u32(off) { iloc_payload.push(b) }
    for b in grid_e2e_u32(len) { iloc_payload.push(b) }
  }
  // Reuse the metadata prefix and replace the placeholder iloc box.
  let meta_payload : Array[Byte] = [0, 0, 0, 0]
  for b in iinf { meta_payload.push(b) }
  let iloc_box = grid_e2e_box(grid_e2e_type(0x69, 0x6C, 0x6F, 0x63), iloc_payload)
  for b in iloc_box { meta_payload.push(b) }
  for b in iref { meta_payload.push(b) }
  let meta = grid_e2e_box(grid_e2e_type(0x6D, 0x65, 0x74, 0x61), meta_payload)
  let data : Array[Byte] = []
  for b in meta { data.push(b) }
  let mdat_payload : Array[Byte] = []
  for b in grid_item { mdat_payload.push(b) }
  for b in sample { mdat_payload.push(b) }
  for b in sample { mdat_payload.push(b) }
  let mdat = grid_e2e_box(grid_e2e_type(0x6D, 0x64, 0x61, 0x74), mdat_payload)
  for b in mdat { data.push(b) }
  let descriptor = avif_grid_descriptor(data).unwrap()
  assert_eq((descriptor.rows, descriptor.columns, descriptor.output_width, descriptor.output_height), (1, 2, 128, 64))
  let image = avif_decode_grid(data, descriptor).unwrap()
  assert_eq((image.width, image.height), (128, 64))
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
  let automatic = avif_decode_grid_auto(data).unwrap()
  assert_eq((automatic.width, automatic.height), (128, 64))
  assert_eq(automatic.get_pixel(127, 63).3, b'\xFF')
}
