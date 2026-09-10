/// Bounded metadata for an AVIF auxiliary alpha item.
///
/// This API only identifies the auxiliary item and validates its BMFF extents.
/// It deliberately does not decode the alpha AV1 payload; alpha reconstruction
/// remains a later decoder stage.
pub struct AvifAlphaExtent {
  offset : Int
  length : Int
  construction_method : Int
}

/// A validated `auxl`/`auxC` item descriptor extracted from an AVIF container.
pub struct AvifAlphaItemDescriptor {
  item_id : Int
  width : Int
  height : Int
  bit_depth : Int
  auxiliary_property : Bool
  extents : Array[AvifAlphaExtent]
}

priv suberror AuxParseError {
  Invalid
  Unsupported
}

priv struct AuxBox {
  typ : Int
  start : Int
  payload : Int
  end : Int
  parent : Int
}

priv struct AuxItem {
  id : Int
  typ : Int
  props : Array[Int]
  mut method_id : Int
  mut base : Int
  offsets : Array[Int]
  lengths : Array[Int]
}

priv struct AuxProp {
  kind : Int
  width : Int
  height : Int
  bit_depth : Int
}

let aux_t_meta = 0x6D657461
let aux_t_iinf = 0x69696E66
let aux_t_infe = 0x696E6665
let aux_t_iloc = 0x696C6F63
let aux_t_iprp = 0x69707270
let aux_t_ipco = 0x6970636F
let aux_t_ipma = 0x69706D61
let aux_t_ispe = 0x69737065
let aux_t_av1c = 0x61763143
let aux_t_auxc = 0x61757843
let aux_t_auxl = 0x6175786C
let aux_t_idat = 0x69646174

fn aux_u8(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  if p < 0 || p >= e || p >= d.length() { raise AuxParseError::Invalid }
  d[p].to_int()
}

fn aux_u16(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  aux_u8(d, p, e) * 256 + aux_u8(d, p + 1, e)
}

fn aux_u32(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  aux_u8(d, p, e) * 16777216 + aux_u8(d, p + 1, e) * 65536 +
  aux_u8(d, p + 2, e) * 256 + aux_u8(d, p + 3, e)
}

fn aux_u64(d : Array[Byte], p : Int, e : Int) -> Int raise AuxParseError {
  if aux_u8(d, p, e) > 127 { raise AuxParseError::Unsupported }
  let mut x = 0
  for i in 0..<8 { x = x * 256 + aux_u8(d, p + i, e) }
  x
}

fn aux_box_index(bs : Array[AuxBox], start : Int) -> Int {
  for i in 0..<bs.length() { if bs[i].start == start { return i } }
  -1
}

fn aux_find(bs : Array[AuxBox], parent : Int, typ : Int) -> AuxBox? {
  for b in bs { if b.parent == parent && b.typ == typ { return Some(b) } }
  None
}

fn aux_item_index(xs : Array[AuxItem], id : Int) -> Int {
  for i in 0..<xs.length() { if xs[i].id == id { return i } }
  -1
}

fn aux_walk(
  d : Array[Byte],
  from : Int,
  to : Int,
  parent : Int,
  out : Array[AuxBox],
) -> Unit raise AuxParseError {
  let mut p = from
  while p < to {
    if to - p < 8 { raise AuxParseError::Invalid }
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
    if size < header || size > to - p { raise AuxParseError::Invalid }
    let end = p + size
    let payload = p + header
    let index = out.length()
    out.push({ typ, start: p, payload, end, parent })
    if typ == aux_t_meta {
      if end - payload < 4 { raise AuxParseError::Invalid }
      aux_walk(d, payload + 4, end, index, out)
    } else if typ == aux_t_iprp || typ == aux_t_ipco {
      aux_walk(d, payload, end, index, out)
    } else if typ == aux_t_iinf {
      let version = aux_u8(d, payload, end)
      let child = if version == 0 { payload + 6 } else { payload + 8 }
      if child > end { raise AuxParseError::Invalid }
      aux_walk(d, child, end, index, out)
    }
    p = end
  }
}

fn aux_parse_items(
  d : Array[Byte], bs : Array[AuxBox], meta : AuxBox,
) -> (Array[AuxItem], AuxBox?, AuxBox?) raise AuxParseError {
  let mi = aux_box_index(bs, meta.start)
  let iinf = match aux_find(bs, mi, aux_t_iinf) {
    Some(x) => x
    None => raise AuxParseError::Invalid
  }
  let ii = aux_box_index(bs, iinf.start)
  let items : Array[AuxItem] = []
  for b in bs {
    if b.parent != ii || b.typ != aux_t_infe { continue }
    let v = aux_u8(d, b.payload, b.end)
    if v < 2 { raise AuxParseError::Unsupported }
    let id = if v >= 3 { aux_u32(d, b.payload + 4, b.end) } else { aux_u16(d, b.payload + 4, b.end) }
    let typ = aux_u32(d, b.payload + (if v >= 3 { 10 } else { 8 }), b.end)
    items.push({ id, typ, props: [], method_id: 0, base: 0, offsets: [], lengths: [] })
  }
  let iloc = aux_find(bs, mi, aux_t_iloc)
  let iprp = aux_find(bs, mi, aux_t_iprp)
  (items, iloc, iprp)
}

fn aux_parse_iloc(d : Array[Byte], b : AuxBox, xs : Array[AuxItem]) -> Unit raise AuxParseError {
  let p = b.payload
  let v = aux_u8(d, p, b.end)
  let sizes = aux_u8(d, p + 4, b.end)
  let os = sizes >> 4
  let ls = sizes & 15
  let z = aux_u8(d, p + 5, b.end)
  let bs = z >> 4
  let isz = if v >= 1 { z & 15 } else { 0 }
  if (os != 0 && os != 4 && os != 8) || (ls != 0 && ls != 4 && ls != 8) ||
    (bs != 0 && bs != 4 && bs != 8) { raise AuxParseError::Unsupported }
  let mut q = p + 6
  let n = if v == 0 { aux_u16(d, q, b.end) } else { aux_u32(d, q, b.end) }
  q = q + (if v == 0 { 2 } else { 4 })
  for _ in 0..<n {
    let id = if v < 2 { aux_u16(d, q, b.end) } else { aux_u32(d, q, b.end) }
    q = q + (if v < 2 { 2 } else { 4 })
    let construction = if v >= 1 { (aux_u16(d, q, b.end) >> 12) & 15 } else { 0 }
    if construction != 0 && construction != 1 { raise AuxParseError::Unsupported }
    if v >= 1 { q = q + 2 }
    if aux_u16(d, q, b.end) != 0 { raise AuxParseError::Unsupported }
    q = q + 2
    let base = if bs == 0 { 0 } else if bs == 4 { aux_u32(d, q, b.end) } else { aux_u64(d, q, b.end) }
    q = q + bs
    let ec = aux_u16(d, q, b.end)
    q = q + 2
    let xi = aux_item_index(xs, id)
    for _ in 0..<ec {
      if v >= 1 && isz != 0 { q = q + isz }
      let off = if os == 0 { 0 } else if os == 4 { aux_u32(d, q, b.end) } else { aux_u64(d, q, b.end) }
      q = q + os
      let len = if ls == 0 { 0 } else if ls == 4 { aux_u32(d, q, b.end) } else { aux_u64(d, q, b.end) }
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

fn aux_parse_ipma(d : Array[Byte], bs : Array[AuxBox], iprp : AuxBox?, xs : Array[AuxItem]) -> Unit raise AuxParseError {
  let rp = match iprp { Some(x) => x; None => return }
  let ri = aux_box_index(bs, rp.start)
  let b = match aux_find(bs, ri, aux_t_ipma) { Some(x) => x; None => return }
  let p = b.payload
  let flags = aux_u32(d, p, b.end) & 0xFFFFFF
  let mut q = p + 4
  let n = aux_u32(d, q, b.end)
  q = q + 4
  for _ in 0..<n {
    let id = if (flags & 1) != 0 { aux_u32(d, q, b.end) } else { aux_u16(d, q, b.end) }
    q = q + (if (flags & 1) != 0 { 4 } else { 2 })
    let c = aux_u8(d, q, b.end)
    q = q + 1
    let xi = aux_item_index(xs, id)
    for _ in 0..<c {
      let a = if (flags & 2) != 0 { aux_u16(d, q, b.end) } else { aux_u8(d, q, b.end) }
      q = q + (if (flags & 2) != 0 { 2 } else { 1 })
      if xi >= 0 { xs[xi].props.push(if (flags & 2) != 0 { a & 0x7FFF } else { a & 0x7F }) }
    }
  }
}

fn aux_parse_props(d : Array[Byte], bs : Array[AuxBox], iprp : AuxBox?) -> Array[AuxProp] raise AuxParseError {
  let out : Array[AuxProp] = []
  let rp = match iprp { Some(x) => x; None => return out }
  let ri = aux_box_index(bs, rp.start)
  let co = match aux_find(bs, ri, aux_t_ipco) { Some(x) => x; None => return out }
  let ci = aux_box_index(bs, co.start)
  for b in bs {
    if b.parent != ci { continue }
    if b.typ == aux_t_ispe {
      out.push({ kind: b.typ, width: aux_u32(d, b.payload + 4, b.end), height: aux_u32(d, b.payload + 8, b.end), bit_depth: 8 })
    } else if b.typ == aux_t_av1c {
      if b.end - b.payload < 3 { raise AuxParseError::Invalid }
      let f = aux_u8(d, b.payload + 2, b.end)
      let depth = if (f & 0x40) == 0 { 8 } else if (f & 0x20) != 0 { 12 } else { 10 }
      out.push({ kind: b.typ, width: 0, height: 0, bit_depth: depth })
    } else {
      out.push({ kind: b.typ, width: 0, height: 0, bit_depth: 8 })
    }
  }
  out
}

/// Extract and validate the first auxiliary alpha item in an AVIF file.
/// Returns `None` for malformed BMFF references or when no alpha item exists.
pub fn avif_alpha_item_descriptor(data : Array[Byte]) -> AvifAlphaItemDescriptor? {
  try {
    let bs : Array[AuxBox] = []
    aux_walk(data, 0, data.length(), -1, bs)
    let meta = match aux_find(bs, -1, aux_t_meta) { Some(x) => x; None => raise AuxParseError::Invalid }
    let parsed = aux_parse_items(data, bs, meta)
    let items = parsed.0
    let iloc = match parsed.1 { Some(x) => x; None => raise AuxParseError::Invalid }
    aux_parse_iloc(data, iloc, items)
    aux_parse_ipma(data, bs, parsed.2, items)
    let props = aux_parse_props(data, bs, parsed.2)
    let idat = aux_find(bs, aux_box_index(bs, meta.start), aux_t_idat)
    for it in items {
      let mut aux = it.typ == aux_t_auxl
      let mut width = 0
      let mut height = 0
      let mut depth = 8
      for ai in it.props {
        if ai <= 0 || ai > props.length() { raise AuxParseError::Invalid }
        let p = props[ai - 1]
        if p.kind == aux_t_auxc { aux = true }
        if p.kind == aux_t_ispe { width = p.width; height = p.height }
        if p.kind == aux_t_av1c { depth = p.bit_depth }
      }
      if !aux || it.offsets.length() == 0 { continue }
      let extents : Array[AvifAlphaExtent] = []
      for i in 0..<it.offsets.length() {
        let base = if it.method_id == 1 {
          match idat { Some(x) => x.payload; None => raise AuxParseError::Invalid }
        } else { 0 }
        let off = base + it.base + it.offsets[i]
        let len = it.lengths[i]
        if off < 0 || len < 0 || off > data.length() - len { raise AuxParseError::Invalid }
        extents.push({ offset: off, length: len, construction_method: it.method_id })
      }
      if width <= 0 || height <= 0 { raise AuxParseError::Invalid }
      return Some({ item_id: it.id, width, height, bit_depth: depth, auxiliary_property: true, extents })
    }
    None
  } catch {
    _ => None
  }
}

/// Return the validated raw auxiliary alpha item bytes in extent order.
/// The bytes are still AV1 payload data and are not interpreted as pixels.
pub fn avif_alpha_item_payload(data : Array[Byte]) -> Array[Byte]? {
  let descriptor = match avif_alpha_item_descriptor(data) {
    Some(value) => value
    None => return None
  }
  let out : Array[Byte] = []
  for extent in descriptor.extents {
    if extent.offset < 0 || extent.length < 0 ||
      extent.offset > data.length() - extent.length {
      return None
    }
    for i in extent.offset..<(extent.offset + extent.length) {
      out.push(data[i])
    }
  }
  Some(out)
}




