///|
/// Bounded metadata for an AVIF auxiliary alpha item.
///
/// This API only identifies the auxiliary item and validates its BMFF extents.
/// Pixel reconstruction is performed by avif_decode_alpha, including grids;
/// native alpha precision is retained until the assembled plane is normalized.
pub struct AvifAlphaExtent {
  offset : Int
  length : Int
  construction_method : Int
}

///|
/// A validated `auxl`/`auxC` item descriptor extracted from an AVIF container.
pub struct AvifAlphaItemDescriptor {
  item_id : Int
  width : Int
  height : Int
  bit_depth : Int
  auxiliary_property : Bool
  premultiplied : Bool
  extents : Array[AvifAlphaExtent]
}

///|
priv suberror AuxParseError {
  Invalid
  Unsupported
}

///|
priv struct AuxBox {
  typ : Int
  start : Int
  payload : Int
  end : Int
  parent : Int
}

///|
priv struct AuxItem {
  id : Int
  typ : Int
  props : Array[Int]
  mut method_id : Int
  mut base : Int
  offsets : Array[Int]
  lengths : Array[Int]
}

///|
priv struct AuxProp {
  kind : Int
  width : Int
  height : Int
  bit_depth : Int
  data : Array[Byte]
}

///|
let aux_t_meta = 0x6D657461

///|
let aux_t_iinf = 0x69696E66

///|
let aux_t_infe = 0x696E6665

///|
let aux_t_iloc = 0x696C6F63

///|
let aux_t_iprp = 0x69707270

///|
let aux_t_ipco = 0x6970636F

///|
let aux_t_ipma = 0x69706D61

///|
let aux_t_ispe = 0x69737065

///|
let aux_t_av1c = 0x61763143

///|
let aux_t_auxc = 0x61757843

///|
let aux_t_auxl = 0x6175786C

///|
let aux_t_prem = 0x7072656D

///|
let aux_t_idat = 0x69646174

///|
let aux_t_pitm = 0x7069746D

///|
let aux_t_iref = 0x69726566

///|
let aux_t_av01 = 0x61763031

///|
fn aux_u8(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  if p < 0 || p >= e || p >= d.length() {
    raise AuxParseError::Invalid
  }
  d[p].to_int()
}

///|
fn aux_u16(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  aux_u8(d, p, e) * 256 + aux_u8(d, p + 1, e)
}

///|
fn aux_u32(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  aux_u8(d, p, e) * 16777216 +
  aux_u8(d, p + 1, e) * 65536 +
  aux_u8(d, p + 2, e) * 256 +
  aux_u8(d, p + 3, e)
}

///|
fn aux_u64(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  // Array offsets use Int. Reject unrepresentable values before narrowing.
  for i in 0..<4 {
    if aux_u8(d, p + i, e) != 0 {
      raise AuxParseError::Unsupported
    }
  }
  if aux_u8(d, p + 4, e) > 127 {
    raise AuxParseError::Unsupported
  }
  aux_u32(d, p + 4, e)
}

///|
fn aux_box_index(bs : Array[AuxBox], start : Int) -> Int {
  for i in 0..<bs.length() {
    if bs[i].start == start {
      return i
    }
  }
  -1
}

///|
fn aux_find(bs : Array[AuxBox], parent : Int, typ : Int) -> AuxBox? {
  for b in bs {
    if b.parent == parent && b.typ == typ {
      return Some(b)
    }
  }
  None
}

///|
fn aux_item_index(xs : Array[AuxItem], id : Int) -> Int {
  for i in 0..<xs.length() {
    if xs[i].id == id {
      return i
    }
  }
  -1
}

///|
fn aux_walk(
  d : Array[Byte],
  from : Int,
  to : Int,
  parent : Int,
  out : Array[AuxBox],
) -> Unit raise AuxParseError {
  let mut p = from
  while p < to {
    if to - p < 8 {
      raise AuxParseError::Invalid
    }
    let s32 = aux_u32(d, p, to)
    let typ = aux_u32(d, p + 4, to)
    let mut header = 8
    let mut size = s32
    if s32 == 1 {
      header = 16
      size = aux_u64(d, p + 8, to)
    } else if s32 == 0 {
      size = to - p
    }
    if size < header || size > to - p {
      raise AuxParseError::Invalid
    }
    let end = p + size
    let payload = p + header
    let index = out.length()
    out.push({ typ, start: p, payload, end, parent, })
    if typ == aux_t_meta || typ == aux_t_iref {
      if end - payload < 4 {
        raise AuxParseError::Invalid
      }
      aux_walk(d, payload + 4, end, index, out)
    } else if typ == aux_t_iprp || typ == aux_t_ipco {
      aux_walk(d, payload, end, index, out)
    } else if typ == aux_t_iinf {
      let version = aux_u8(d, payload, end)
      let child = if version == 0 { payload + 6 } else { payload + 8 }
      if child > end {
        raise AuxParseError::Invalid
      }
      aux_walk(d, child, end, index, out)
    }
    p = end
  }
}

///|
fn aux_parse_items(
  d : Array[Byte],
  bs : Array[AuxBox],
  meta : AuxBox,
) -> (Array[AuxItem], AuxBox?, AuxBox?) raise AuxParseError {
  let mi = aux_box_index(bs, meta.start)
  let iinf = match aux_find(bs, mi, aux_t_iinf) {
    Some(x) => x
    None => raise AuxParseError::Invalid
  }
  let ii = aux_box_index(bs, iinf.start)
  let items : Array[AuxItem] = []
  for b in bs {
    if b.parent != ii || b.typ != aux_t_infe {
      continue
    }
    let v = aux_u8(d, b.payload, b.end)
    if v < 2 {
      raise AuxParseError::Unsupported
    }
    let id = if v >= 3 {
      aux_u32(d, b.payload + 4, b.end)
    } else {
      aux_u16(d, b.payload + 4, b.end)
    }
    let typ = aux_u32(d, b.payload + (if v >= 3 { 10 } else { 8 }), b.end)
    items.push({
      id,
      typ,
      props: [],
      method_id: 0,
      base: 0,
      offsets: [],
      lengths: [],
    })
  }
  let iloc = aux_find(bs, mi, aux_t_iloc)
  let iprp = aux_find(bs, mi, aux_t_iprp)
  (items, iloc, iprp)
}

///|
fn aux_parse_iloc(
  d : Array[Byte],
  b : AuxBox,
  xs : Array[AuxItem],
) -> Unit raise AuxParseError {
  let p = b.payload
  let v = aux_u8(d, p, b.end)
  if v > 2 {
    raise AuxParseError::Unsupported
  }
  let sizes = aux_u8(d, p + 4, b.end)
  let os = sizes >> 4
  let ls = sizes & 15
  let z = aux_u8(d, p + 5, b.end)
  let bs = z >> 4
  let isz = if v >= 1 { z & 15 } else { 0 }
  if (os != 0 && os != 4 && os != 8) ||
    (ls != 0 && ls != 4 && ls != 8) ||
    (bs != 0 && bs != 4 && bs != 8) {
    raise AuxParseError::Unsupported
  }
  let mut q = p + 6
  let n = if v < 2 { aux_u16(d, q, b.end) } else { aux_u32(d, q, b.end) }
  q = q + (if v < 2 { 2 } else { 4 })
  for _ in 0..<n {
    let id = if v < 2 { aux_u16(d, q, b.end) } else { aux_u32(d, q, b.end) }
    q = q + (if v < 2 { 2 } else { 4 })
    let construction = if v >= 1 { aux_u16(d, q, b.end) & 15 } else { 0 }
    if construction != 0 && construction != 1 {
      raise AuxParseError::Unsupported
    }
    if v >= 1 {
      q = q + 2
    }
    if aux_u16(d, q, b.end) != 0 {
      raise AuxParseError::Unsupported
    }
    q = q + 2
    let base = if bs == 0 {
      0
    } else if bs == 4 {
      aux_u32(d, q, b.end)
    } else {
      aux_u64(d, q, b.end)
    }
    q = q + bs
    let ec = aux_u16(d, q, b.end)
    q = q + 2
    let xi = aux_item_index(xs, id)
    for _ in 0..<ec {
      if v >= 1 && isz != 0 {
        q = q + isz
      }
      let off = if os == 0 {
        0
      } else if os == 4 {
        aux_u32(d, q, b.end)
      } else {
        aux_u64(d, q, b.end)
      }
      q = q + os
      let len = if ls == 0 {
        0
      } else if ls == 4 {
        aux_u32(d, q, b.end)
      } else {
        aux_u64(d, q, b.end)
      }
      q = q + ls
      if xi >= 0 {
        xs[xi].method_id = construction
        xs[xi].base = base
        xs[xi].offsets.push(off)
        xs[xi].lengths.push(len)
      }
    }
  }
}

///|
fn aux_parse_ipma(
  d : Array[Byte],
  bs : Array[AuxBox],
  iprp : AuxBox?,
  xs : Array[AuxItem],
) -> Unit raise AuxParseError {
  let rp = match iprp {
    Some(x) => x
    None => return
  }
  let ri = aux_box_index(bs, rp.start)
  let b = match aux_find(bs, ri, aux_t_ipma) {
    Some(x) => x
    None => return
  }
  let p = b.payload
  let version = aux_u8(d, p, b.end)
  if version > 1 {
    raise AuxParseError::Unsupported
  }
  let flags = aux_u32(d, p, b.end) & 0xFFFFFF
  let mut q = p + 4
  let n = aux_u32(d, q, b.end)
  q = q + 4
  for _ in 0..<n {
    let id = if version >= 1 {
      aux_u32(d, q, b.end)
    } else {
      aux_u16(d, q, b.end)
    }
    q = q + (if version >= 1 { 4 } else { 2 })
    let c = aux_u8(d, q, b.end)
    q = q + 1
    let xi = aux_item_index(xs, id)
    for _ in 0..<c {
      let a = if (flags & 1) != 0 {
        aux_u16(d, q, b.end)
      } else {
        aux_u8(d, q, b.end)
      }
      q = q + (if (flags & 1) != 0 { 2 } else { 1 })
      let property = if (flags & 1) != 0 { a & 0x7FFF } else { a & 0x7F }
      if xi >= 0 && property != 0 {
        xs[xi].props.push(property)
      }
    }
  }
}

///|
fn aux_parse_props(
  d : Array[Byte],
  bs : Array[AuxBox],
  iprp : AuxBox?,
) -> Array[AuxProp] raise AuxParseError {
  let out : Array[AuxProp] = []
  let rp = match iprp {
    Some(x) => x
    None => return out
  }
  let ri = aux_box_index(bs, rp.start)
  let co = match aux_find(bs, ri, aux_t_ipco) {
    Some(x) => x
    None => return out
  }
  let ci = aux_box_index(bs, co.start)
  for b in bs {
    if b.parent != ci {
      continue
    }
    if b.typ == aux_t_ispe {
      out.push({
        kind: b.typ,
        width: aux_u32(d, b.payload + 4, b.end),
        height: aux_u32(d, b.payload + 8, b.end),
        bit_depth: 8,
        data: [],
      })
    } else if b.typ == aux_t_av1c {
      if b.end - b.payload < 3 {
        raise AuxParseError::Invalid
      }
      let f = aux_u8(d, b.payload + 2, b.end)
      let depth = if (f & 0x40) == 0 {
        8
      } else if (f & 0x20) != 0 {
        12
      } else {
        10
      }
      let data : Array[Byte] = []
      for i in b.payload..<b.end {
        data.push(d[i])
      }
      out.push({ kind: b.typ, width: 0, height: 0, bit_depth: depth, data, })
    } else {
      let data : Array[Byte] = []
      if b.typ == aux_t_auxc {
        for i in b.payload..<b.end {
          data.push(d[i])
        }
      }
      out.push({ kind: b.typ, width: 0, height: 0, bit_depth: 8, data, })
    }
  }
  out
}

///|
/// auxC is a FullBox followed by a NUL-terminated auxiliary type, not an
/// item type. Other auxiliary types (including depth) are not alpha.
fn aux_is_alpha_type(data : Array[Byte]) -> Bool raise AuxParseError {
  if data.length() < 5 {
    raise AuxParseError::Invalid
  }
  if data[0] != b'\x00' {
    raise AuxParseError::Unsupported
  }
  let mut end = 4
  while end < data.length() && data[end] != b'\x00' {
    end = end + 1
  }
  if end == data.length() {
    raise AuxParseError::Invalid
  }
  let name = "urn:mpeg:mpegB:cicp:systems:auxiliary:alpha".to_array()
  if end - 4 != name.length() {
    return false
  }
  for i in 0..<name.length() {
    if data[i + 4].to_int() != name[i].to_int() {
      return false
    }
  }
  true
}

///|
/// Read the mandatory image properties only for the selected color/alpha pair.
fn aux_image_info(
  item : AuxItem,
  props : Array[AuxProp],
) -> (Int, Int, Int, Bool) raise AuxParseError {
  if item.typ != aux_t_av01 {
    raise AuxParseError::Unsupported
  }
  let mut width = 0
  let mut height = 0
  let mut depth = 0
  let mut monochrome = false
  let mut seen_ispe = false
  let mut seen_av1c = false
  for ai in item.props {
    if ai == 0 {
      continue
    }
    if ai < 0 || ai > props.length() {
      raise AuxParseError::Invalid
    }
    let prop = props[ai - 1]
    if prop.kind == aux_t_ispe {
      if seen_ispe {
        raise AuxParseError::Invalid
      }
      seen_ispe = true
      width = prop.width
      height = prop.height
    } else if prop.kind == aux_t_av1c {
      if seen_av1c || prop.data.length() < 4 || prop.data[0] != b'\x81' {
        raise AuxParseError::Invalid
      }
      seen_av1c = true
      let flags = prop.data[2].to_int()
      let profile = prop.data[1].to_int() >> 5
      if profile > 2 ||
        ((flags & 0x20) != 0 && ((flags & 0x40) == 0 || profile != 2)) {
        raise AuxParseError::Invalid
      }
      depth = prop.bit_depth
      monochrome = (flags & 0x10) != 0
    }
  }
  if !seen_ispe || !seen_av1c || width <= 0 || height <= 0 {
    raise AuxParseError::Invalid
  }
  (width, height, depth, monochrome)
}

///|
/// A derived grid inherits coded configuration from its validated cells;
/// av1C belongs to those av01 items, not to the grid item itself.
fn aux_item_image_info(
  data : Array[Byte],
  item : AuxItem,
  items : Array[AuxItem],
  props : Array[AuxProp],
) -> (Int, Int, Int, Bool) raise AuxParseError {
  if item.typ == aux_t_av01 {
    return aux_image_info(item, props)
  }
  if item.typ != 0x67726964 {
    raise AuxParseError::Unsupported
  }
  let grid = match avif_grid_descriptor_for_item(data, Some(item.id)) {
    Some(value) => value
    None => raise AuxParseError::Invalid
  }
  if !avif_grid_properties_match(data, grid) {
    raise AuxParseError::Invalid
  }
  let first = aux_item_index(items, grid.tiles[0].item_id)
  if first < 0 {
    raise AuxParseError::Invalid
  }
  let info = aux_image_info(items[first], props)
  (grid.output_width, grid.output_height, info.2, info.3)
}

///|
/// Internal three-way query: None means no alpha associated with pitm;
/// a selected malformed/unsupported alpha raises instead of becoming opaque.
/// This parser is independent of avif_container_parse, so both public container
/// and alpha entry points can call it without recursive parsing.
fn avif_alpha_descriptor_checked(
  data : Array[Byte],
) -> AvifAlphaItemDescriptor? raise AuxParseError {
  let bs : Array[AuxBox] = []
  aux_walk(data, 0, data.length(), -1, bs)
  let meta = match aux_find(bs, -1, aux_t_meta) {
    Some(value) => value
    None => raise AuxParseError::Invalid
  }
  let mi = aux_box_index(bs, meta.start)
  let pitm = match aux_find(bs, mi, aux_t_pitm) {
    Some(value) => value
    None => raise AuxParseError::Invalid
  }
  let pv = aux_u8(data, pitm.payload, pitm.end)
  if pv > 1 {
    raise AuxParseError::Unsupported
  }
  let primary = if pv == 0 {
    aux_u16(data, pitm.payload + 4, pitm.end)
  } else {
    aux_u32(data, pitm.payload + 4, pitm.end)
  }
  let iref = match aux_find(bs, mi, aux_t_iref) {
    Some(value) => value
    None => return None
  }
  let version = aux_u8(data, iref.payload, iref.end)
  if version > 1 {
    raise AuxParseError::Unsupported
  }
  let ri = aux_box_index(bs, iref.start)
  let linked_ids : Array[Int] = []
  let premultiplied_by : Array[Int] = []
  for reference in bs {
    if reference.parent != ri ||
      (reference.typ != aux_t_auxl && reference.typ != aux_t_prem) {
      continue
    }
    let mut p = reference.payload
    let from_id = if version == 0 {
      aux_u16(data, p, reference.end)
    } else {
      aux_u32(data, p, reference.end)
    }
    p = p + (if version == 0 { 2 } else { 4 })
    let count = aux_u16(data, p, reference.end)
    p = p + 2
    for _ in 0..<count {
      let to_id = if version == 0 {
        aux_u16(data, p, reference.end)
      } else {
        aux_u32(data, p, reference.end)
      }
      p = p + (if version == 0 { 2 } else { 4 })
      if reference.typ == aux_t_auxl && to_id == primary && from_id != primary {
        linked_ids.push(from_id)
      }
      // prem points from the color item to the alpha item, opposite to auxl.
      if reference.typ == aux_t_prem && from_id == primary {
        premultiplied_by.push(to_id)
      }
    }
    if p != reference.end {
      raise AuxParseError::Invalid
    }
  }
  if linked_ids.length() == 0 {
    return None
  }
  let parsed = aux_parse_items(data, bs, meta)
  let items = parsed.0
  aux_parse_ipma(data, bs, parsed.2, items)
  let props = aux_parse_props(data, bs, parsed.2)
  // Match libavif's item ordering: the first alpha auxiliary of this primary
  // is selected. Unrelated auxiliaries and other aux_type values are ignored.
  for item in items {
    let mut linked = false
    for id in linked_ids {
      if id == item.id {
        linked = true
      }
    }
    if !linked {
      continue
    }
    let mut alpha = false
    for ai in item.props {
      if ai == 0 {
        continue
      }
      if ai < 0 || ai > props.length() {
        raise AuxParseError::Invalid
      }
      let prop = props[ai - 1]
      if prop.kind == aux_t_auxc && aux_is_alpha_type(prop.data) {
        alpha = true
      }
    }
    if !alpha {
      continue
    }
    let pi = aux_item_index(items, primary)
    if pi < 0 {
      raise AuxParseError::Invalid
    }
    let color = aux_item_image_info(data, items[pi], items, props)
    let auxiliary = aux_item_image_info(data, item, items, props)
    // AVIF 4.1 requires the same encoded bit depth as the master image.
    // Width and height must each match; equal pixel counts are insufficient.
    if auxiliary.0 != color.0 ||
      auxiliary.1 != color.1 ||
      auxiliary.2 != color.2 ||
      !auxiliary.3 {
      raise AuxParseError::Invalid
    }
    let iloc = match parsed.1 {
      Some(value) => value
      None => raise AuxParseError::Invalid
    }
    aux_parse_iloc(data, iloc, items)
    if item.offsets.length() == 0 {
      raise AuxParseError::Invalid
    }
    let (base, bound) = if item.method_id == 1 {
      match aux_find(bs, mi, aux_t_idat) {
        Some(value) => (value.payload, value.end)
        None => raise AuxParseError::Invalid
      }
    } else {
      (0, data.length())
    }
    let extents : Array[AvifAlphaExtent] = []
    for i in 0..<item.offsets.length() {
      let len = item.lengths[i]
      if len <= 0 ||
        item.base < 0 ||
        item.offsets[i] < 0 ||
        base > bound - len ||
        item.base > bound - len - base ||
        item.offsets[i] > bound - len - base - item.base {
        raise AuxParseError::Invalid
      }
      extents.push({
        offset: base + item.base + item.offsets[i],
        length: len,
        construction_method: item.method_id,
      })
    }
    return Some({
      item_id: item.id,
      width: auxiliary.0,
      height: auxiliary.1,
      bit_depth: auxiliary.2,
      auxiliary_property: true,
      premultiplied: premultiplied_by.contains(item.id),
      extents,
    })
  }
  None
}

///|
/// Extract the first alpha item associated with the primary image through
/// auxl and the alpha auxC URN. None also represents malformed input for this
/// public Option API; composition uses the checked internal query instead.
pub fn avif_alpha_item_descriptor(
  data : Array[Byte],
) -> AvifAlphaItemDescriptor? {
  avif_alpha_descriptor_checked(data) catch {
    _ => None
  }
}

///|
/// Return the validated raw auxiliary alpha item bytes in extent order.
/// The bytes are still AV1 payload data and are not interpreted as pixels.
pub fn avif_alpha_item_payload(data : Array[Byte]) -> Array[Byte]? {
  let descriptor = match avif_alpha_item_descriptor(data) {
    Some(value) => value
    None => return None
  }
  let out : Array[Byte] = []
  for extent in descriptor.extents {
    if extent.offset < 0 ||
      extent.length < 0 ||
      extent.offset > data.length() - extent.length {
      return None
    }
    for i in extent.offset..<(extent.offset + extent.length) {
      out.push(data[i])
    }
  }
  Some(out)
}
