///|
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
  if rows <= 0 ||
    columns <= 0 ||
    output_width <= 0 ||
    output_height <= 0 ||
    rows > 256 ||
    columns > 256 ||
    tiles.length() != rows * columns {
    return None
  }
  if output_width > MAX_IMAGE_PIXELS / output_height {
    return None
  }
  let first = tiles[0]
  if first.width <= 0 || first.height <= 0 {
    return None
  }
  // Every cell has the same coded dimensions. Only the output rectangle is
  // cropped; it must include part of the final row and column, without holes.
  if (output_width - 1) / first.width != columns - 1 ||
    (output_height - 1) / first.height != rows - 1 {
    return None
  }
  for tile in tiles {
    if tile.width != first.width || tile.height != first.height {
      return None
    }
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

///|
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
  if rows <= 0 ||
    columns <= 0 ||
    rows > 256 ||
    columns > 256 ||
    samples.length() != rows * columns {
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

///|
/// Decode a grid directly from a BMFF buffer and its parsed descriptor.
/// Each tile may contain one or more iloc extents; extents are concatenated
/// before passing the sample to the pure AV1 decoder.
pub fn avif_decode_grid(
  data : Array[Byte],
  descriptor : AvifGridDescriptor,
) -> Image? {
  match avif_decode_grid_frame(data, descriptor) {
    Some(frame) => {
      let colored = match avif_grid_descriptor(data) {
        Some(primary) if primary.item_id == descriptor.item_id => {
          let container = match avif_container_parse(data) {
            Some(value) => value
            None => return None
          }
          avif_frame_apply_color(frame, container)
        }
        _ => frame
      }
      av1_frame_to_rgba(colored)
    }
    None => None
  }
}

///|
/// Decode and compose a grid directly from a BMFF buffer.  This convenience
/// entrypoint performs descriptor extraction and pixel reconstruction as one
/// operation, so callers cannot accidentally skip the `dimg` ordering or
/// extent validation step.
pub fn avif_decode_grid_auto(data : Array[Byte]) -> Image? {
  let descriptor = match avif_grid_descriptor(data) {
    Some(value) => value
    None => return None
  }
  if !avif_grid_properties_match(data, descriptor) {
    return None
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

///|
test "grid reconstruction rejects unequal cells and uncovered output" {
  let tile = Image::new(2, 2)
  assert_true(
    avif_reconstruct_grid(1, 2, 4, 2, [tile, Image::new(1, 2)]) is None,
  )
  assert_true(avif_reconstruct_grid(1, 2, 5, 2, [tile, tile]) is None)
  assert_true(avif_reconstruct_grid(2, 1, 2, 5, [tile, tile]) is None)
  assert_true(avif_reconstruct_grid(1, 2, 2, 2, [tile, tile]) is None)
}

///|
/// Multiple iloc extents are concatenated before AV1 decoding.  Construction
/// method is metadata only at this stage; the descriptor has already resolved
/// each extent to a data-relative offset.
test "grid decoder concatenates split construction-method extents" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00',
    b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46',
    b'\x02', b'\x28',
  ]
  let data : Array[Byte] = []
  for b in sample {
    data.push(b)
  }
  let descriptor : AvifGridDescriptor = {
    item_id: 1,
    rows: 1,
    columns: 1,
    output_width: 64,
    output_height: 64,
    tiles: [
      {
        item_id: 2,
        extents: [
          { offset: 0, length: 8, construction_method: 1, },
          { offset: 8, length: sample.length() - 8, construction_method: 1, },
        ],
      },
    ],
  }
  let image = avif_decode_grid(data, descriptor).unwrap()
  assert_eq((image.width, image.height), (64, 64))
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}

///|
test "grid tile decoder composes ordered AV1 samples" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFD', b'\xB0', b'\x08', b'\x32',
    b'\x13', b'\x18', b'\x00', b'\x00', b'\x00', b'\x50', b'\x00', b'\x00', b'\x00',
    b'\x0A', b'\x05', b'\x79', b'\x52', b'\x6E', b'\x43', b'\xD9', b'\x3A', b'\x46',
    b'\x02', b'\x28',
  ]
  let image = avif_decode_grid_tiles(1, 2, 128, 64, [sample, sample]).unwrap()
  assert_eq(image.width, 128)
  assert_eq(image.height, 64)
  assert_eq(image.get_pixel(0, 0).3, b'\xFF')
}
