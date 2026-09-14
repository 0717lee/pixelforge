///|
/// Resolve every extent before adding offsets, retaining the idat boundary.
fn ga_grid_extents(
  data : Array[Byte],
  item : GaItem,
  idat : GaBox?,
) -> Array[AvifGridExtent] raise GridAnimError {
  if item.offs.length() == 0 {
    raise GridAnimError::Invalid
  }
  let (base, bound) = if item.method_id == 1 {
    match idat {
      Some(box) => (box.payload, box.end)
      None => raise GridAnimError::Invalid
    }
  } else {
    (0, data.length())
  }
  let extents : Array[AvifGridExtent] = []
  for i in 0..<item.offs.length() {
    let offset = item.offs[i]
    let length = item.lens[i]
    if length <= 0 ||
      item.base < 0 ||
      offset < 0 ||
      base > bound - length ||
      item.base > bound - length - base ||
      offset > bound - length - base - item.base {
      raise GridAnimError::Invalid
    }
    extents.push({
      offset: base + item.base + offset,
      length,
      construction_method: item.method_id,
    })
  }
  extents
}

///|
/// Read the primary HEIF grid and sized dimg references. ImageGrid is an item
/// payload (version, flags, rows, columns), not an ISO BMFF FullBox.
fn avif_grid_descriptor_for_item(
  data : Array[Byte],
  item_id : Int?,
) -> AvifGridDescriptor? {
  try {
    let boxes : Array[GaBox] = []
    ga_walk(data, 0, data.length(), -1, boxes)
    let meta = match ga_find(boxes, -1, ga_meta) {
      Some(box) => box
      None => raise GridAnimError::Invalid
    }
    let mi = ga_idx(boxes, meta.start)
    let pitm = match ga_find(boxes, mi, ga_pitm) {
      Some(box) => box
      None => raise GridAnimError::Invalid
    }
    let version = ga_u8(data, pitm.payload, pitm.end)
    if version > 1 {
      raise GridAnimError::Unsupported
    }
    let primary = match item_id {
      Some(value) => value
      None =>
        if version == 0 {
          ga_u16(data, pitm.payload + 4, pitm.end)
        } else {
          ga_u32(data, pitm.payload + 4, pitm.end)
        }
    }
    let items = ga_items(data, boxes, meta)
    let index = ga_item_idx(items, primary)
    if index < 0 || items[index].typ != ga_grid {
      return None
    }
    let iloc = match ga_find(boxes, mi, ga_iloc) {
      Some(box) => box
      None => raise GridAnimError::Invalid
    }
    ga_parse_iloc(data, iloc, items)
    let idat = ga_find(boxes, mi, ga_idat)
    let payload : Array[Byte] = []
    for extent in ga_grid_extents(data, items[index], idat) {
      if extent.length > 12 - payload.length() {
        raise GridAnimError::Invalid
      }
      for i in extent.offset..<(extent.offset + extent.length) {
        payload.push(data[i])
      }
    }
    let end = payload.length()
    if ga_u8(payload, 0, end) != 0 {
      raise GridAnimError::Unsupported
    }
    let flags = ga_u8(payload, 1, end)
    if (flags & 254) != 0 {
      raise GridAnimError::Unsupported
    }
    let rows = ga_u8(payload, 2, end) + 1
    let columns = ga_u8(payload, 3, end) + 1
    let wide = (flags & 1) != 0
    if end != (if wide { 12 } else { 8 }) {
      raise GridAnimError::Invalid
    }
    let width = if wide {
      ga_u32(payload, 4, end)
    } else {
      ga_u16(payload, 4, end)
    }
    let height = if wide {
      ga_u32(payload, 8, end)
    } else {
      ga_u16(payload, 6, end)
    }
    if width <= 0 || height <= 0 {
      raise GridAnimError::Invalid
    }
    let iref = match ga_find(boxes, mi, ga_iref) {
      Some(box) => box
      None => raise GridAnimError::Invalid
    }
    let ref_version = ga_u8(data, iref.payload, iref.end)
    if ref_version > 1 {
      raise GridAnimError::Unsupported
    }
    let references : Array[GaBox] = []
    // iref has a FullBox prefix followed directly by reference boxes.
    ga_walk(data, iref.payload + 4, iref.end, -1, references)
    let ids : Array[Int] = []
    let id_width = if ref_version == 0 { 2 } else { 4 }
    for reference in references {
      if reference.parent != -1 || reference.typ != ga_dimg {
        continue
      }
      let start = reference.payload
      let from = if ref_version == 0 {
        ga_u16(data, start, reference.end)
      } else {
        ga_u32(data, start, reference.end)
      }
      let count = ga_u16(data, start + id_width, reference.end)
      let mut cursor = start + id_width + 2
      if count != (reference.end - cursor) / id_width ||
        (reference.end - cursor) % id_width != 0 {
        raise GridAnimError::Invalid
      }
      for _ in 0..<count {
        let id = if ref_version == 0 {
          ga_u16(data, cursor, reference.end)
        } else {
          ga_u32(data, cursor, reference.end)
        }
        cursor = cursor + id_width
        if from == primary {
          ids.push(id)
        }
      }
    }
    if ids.length() != rows * columns {
      raise GridAnimError::Invalid
    }
    let tiles : Array[AvifGridTile] = []
    for id in ids {
      let tile_index = ga_item_idx(items, id)
      if tile_index < 0 || items[tile_index].typ != 0x61763031 {
        raise GridAnimError::Invalid
      }
      tiles.push({
        item_id: id,
        extents: ga_grid_extents(data, items[tile_index], idat),
      })
    }
    Some({
      item_id: primary,
      rows,
      columns,
      output_width: width,
      output_height: height,
      tiles,
    })
  } catch {
    _ => None
  }
}

///|
/// Extract the primary grid and its ordered, validated item extents.
pub fn avif_grid_descriptor(data : Array[Byte]) -> AvifGridDescriptor? {
  avif_grid_descriptor_for_item(data, None)
}

///|
/// Tie grid declarations to the actual tile sequences before automatic decode.
/// The public extent-based composition helper also serves callers that already
/// parsed their container, so its lower-level API does not reparse properties.
fn avif_grid_properties_match(
  data : Array[Byte],
  descriptor : AvifGridDescriptor,
) -> Bool {
  try {
    let boxes : Array[AuxBox] = []
    aux_walk(data, 0, data.length(), -1, boxes)
    let meta = match aux_find(boxes, -1, aux_t_meta) {
      Some(box) => box
      None => raise AuxParseError::Invalid
    }
    let parsed = aux_parse_items(data, boxes, meta)
    let items = parsed.0
    aux_parse_ipma(data, boxes, parsed.2, items)
    let props = aux_parse_props(data, boxes, parsed.2)
    let primary = aux_item_index(items, descriptor.item_id)
    if primary < 0 {
      return false
    }
    let mut seen_ispe = false
    for ai in items[primary].props {
      if ai <= 0 || ai > props.length() {
        return false
      }
      let prop = props[ai - 1]
      if prop.kind == aux_t_ispe {
        if seen_ispe ||
          prop.width != descriptor.output_width ||
          prop.height != descriptor.output_height {
          return false
        }
        seen_ispe = true
      }
    }
    if !seen_ispe {
      return false
    }
    let mut first : (Int, Int, Int, Bool)? = None
    let mut color : (Bool, Int)? = None
    for tile in descriptor.tiles {
      let ti = aux_item_index(items, tile.item_id)
      if ti < 0 {
        return false
      }
      let info = aux_image_info(items[ti], props)
      if info.0 < 64 || info.1 < 64 {
        return false
      }
      // MIAF grids align both cell and output edges to chroma samples.
      // The currently supported color sequence path is 4:2:0.
      if !info.3 &&
        (
          (info.0 | info.1 | descriptor.output_width | descriptor.output_height) &
          1
        ) !=
        0 {
        return false
      }
      match first {
        None => first = Some(info)
        Some(previous) => if previous != info { return false }
      }
      let payload : Array[Byte] = []
      for extent in tile.extents {
        for i in extent.offset..<(extent.offset + extent.length) {
          payload.push(data[i])
        }
      }
      let sequence = match av1_sequence_info(payload) {
        Some(value) => value
        None => return false
      }
      if (
          sequence.width,
          sequence.height,
          sequence.bit_depth,
          sequence.monochrome,
        ) !=
        info {
        return false
      }
      let tile_color = (sequence.full_range, sequence.matrix_coefficients)
      match color {
        None => color = Some(tile_color)
        Some(previous) => if previous != tile_color { return false }
      }
    }
    true
  } catch {
    _ => false
  }
}
