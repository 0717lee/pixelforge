///|
priv suberror AvifError {
  Invalid
  Unsupported
}

///|
pub struct AvifContainer {
  width : Int
  height : Int
  bit_depth : Int
  monochrome : Bool
  yuv420 : Bool
  has_alpha : Bool
  av1c : Array[Byte]
  payload : Array[Byte]
  nclx_primaries : Int?
  nclx_transfer : Int?
  nclx_matrix : Int?
}

///|
priv struct Box {
  typ : Int
  start : Int
  payload : Int
  end : Int
  parent : Int
}

///|
priv struct Item {
  id : Int
  typ : Int
  mut method_id : Int
  mut base : Int
  offs : Array[Int]
  lens : Array[Int]
  props : Array[Int]
}

///|
priv struct Prop {
  kind : Int
  width : Int
  height : Int
  data : Array[Byte]
  p : Int
  t : Int
  m : Int
}

///|
let t_meta = 0x6D657461

///|
let t_iprp = 0x69707270

///|
let t_ipco = 0x6970636F

///|
let t_pitm = 0x7069746D

///|
let t_iinf = 0x69696E66

///|
let t_infe = 0x696E6665

///|
let t_iloc = 0x696C6F63

///|
let t_idat = 0x69646174

///|
let t_ipma = 0x69706D61

///|
let t_ispe = 0x69737065

///|
let t_av1c = 0x61763143

///|
let t_colr = 0x636F6C72

///|
let t_nclx = 0x6E636C78

///|
let t_auxc = 0x61757843

///|
let t_av01 = 0x61763031

///|
fn u8(d : Array[Byte], p : Int, e : Int) -> Int raise AvifError {
  if p < 0 || p >= e || p >= d.length() {
    raise AvifError::Invalid
  }
  d[p].to_int()
}

///|
fn u16(d : Array[Byte], p : Int, e : Int) -> Int raise AvifError {
  u8(d, p, e) * 256 + u8(d, p + 1, e)
}

///|
fn u32(d : Array[Byte], p : Int, e : Int) -> Int raise AvifError {
  u8(d, p, e) * 16777216 +
  u8(d, p + 1, e) * 65536 +
  u8(d, p + 2, e) * 256 +
  u8(d, p + 3, e)
}

///|
fn u64(d : Array[Byte], p : Int, e : Int) -> Int raise AvifError {
  if u8(d, p, e) > 127 {
    raise AvifError::Unsupported
  }
  let mut x = 0
  for i in 0..<8 {
    x = x * 256 + u8(d, p + i, e)
  }
  x
}

///|
fn idx_box(bs : Array[Box], s : Int) -> Int {
  for i in 0..<bs.length() {
    if bs[i].start == s {
      return i
    }
  }
  -1
}

///|
fn find_box(bs : Array[Box], parent : Int, typ : Int) -> Box? {
  for b in bs {
    if b.parent == parent && b.typ == typ {
      return Some(b)
    }
  }
  None
}

///|
fn idx_item(xs : Array[Item], id : Int) -> Int {
  for i in 0..<xs.length() {
    if xs[i].id == id {
      return i
    }
  }
  -1
}

///|
fn slice(d : Array[Byte], a : Int, b : Int) -> Array[Byte] raise AvifError {
  if a < 0 || b < a || b > d.length() {
    raise AvifError::Invalid
  }
  let x : Array[Byte] = []
  for i in a..<b {
    x.push(d[i])
  }
  x
}

///|
fn walk(
  d : Array[Byte],
  from : Int,
  to : Int,
  parent : Int,
  out : Array[Box],
) -> Unit raise AvifError {
  let mut p = from
  while p < to {
    if to - p < 8 {
      raise AvifError::Invalid
    }
    let s32 = u32(d, p, to)
    let typ = u32(d, p + 4, to)
    let mut h = 8
    let mut size = s32
    if s32 == 1 {
      h = 16
      size = u64(d, p + 8, to)
    } else if s32 == 0 {
      size = to - p
    }
    if size < h || size > to - p {
      raise AvifError::Invalid
    }
    let end = p + size
    let payload = p + h
    let bi = out.length()
    out.push({ typ, start: p, payload, end, parent, })
    if typ == t_meta {
      if end - payload < 4 {
        raise AvifError::Invalid
      }
      walk(d, payload + 4, end, bi, out)
    } else if typ == t_iprp || typ == t_ipco {
      walk(d, payload, end, bi, out)
    } else if typ == t_iinf {
      let version = u8(d, payload, end)
      let child_start = if version == 0 { payload + 6 } else { payload + 8 }
      if child_start > end { raise AvifError::Invalid }
      walk(d, child_start, end, bi, out)
    }
    p = end
  }
}

///|
fn parse_av1c(_d : Array[Byte], p : Prop) -> (Int, Bool, Bool) raise AvifError {
  if p.data.length() < 3 {
    raise AvifError::Invalid
  }
  let b0 = p.data[0].to_int()
  if (b0 & 0x80) == 0 || (b0 & 0x7F) != 1 {
    raise AvifError::Unsupported
  }
  let f = p.data[2].to_int()
  let depth = if (f & 0x80) == 0 {
    8
  } else if (f & 0x40) != 0 {
    12
  } else {
    10
  }
  (depth, (f & 0x20) != 0, ((f >> 4) & 1) != 0 && ((f >> 3) & 1) != 0)
}

///|
pub fn avif_container_parse(data : Array[Byte]) -> AvifContainer? {
  try {
    let bs : Array[Box] = []
    walk(data, 0, data.length(), -1, bs)
    let meta = match find_box(bs, -1, t_meta) {
      Some(x) => x
      None => raise AvifError::Invalid
    }
    let mi = idx_box(bs, meta.start)
    let pitm = match find_box(bs, mi, t_pitm) {
      Some(x) => x
      None => raise AvifError::Invalid
    }
    let pv = u8(data, pitm.payload, pitm.end)
    let primary = if pv == 0 {
      u16(data, pitm.payload + 4, pitm.end)
    } else {
      u32(data, pitm.payload + 4, pitm.end)
    }
    let iinf = match find_box(bs, mi, t_iinf) {
      Some(x) => x
      None => raise AvifError::Invalid
    }
    let ii = idx_box(bs, iinf.start)
    let items : Array[Item] = []
    for b in bs {
      if b.parent == ii && b.typ == t_infe {
        let v = u8(data, b.payload, b.end)
        if v < 2 {
          raise AvifError::Unsupported
        }
        let id = if v >= 3 {
          u32(data, b.payload + 4, b.end)
        } else {
          u16(data, b.payload + 4, b.end)
        }
        items.push({
          id,
          typ: u32(data, b.payload + (if v >= 3 { 10 } else { 8 }), b.end),
          method_id: 0,
          base: 0,
          offs: [],
          lens: [],
          props: [],
        })
      }
    }
    let iloc = match find_box(bs, mi, t_iloc) {
      Some(x) => x
      None => raise AvifError::Invalid
    }
    parse_iloc(data, iloc, items)
    let iprp = find_box(bs, mi, t_iprp)
    parse_ipma(data, bs, iprp, items)
    let props = parse_props(data, bs, iprp)
    let pi = idx_item(items, primary)
    if pi < 0 || items[pi].typ != t_av01 {
      raise AvifError::Invalid
    }
    let it = items[pi]
    let mut w = 0
    let mut h = 0
    let mut depth = 8
    let mut mono = false
    let mut yuv = false
    let mut av1 : Array[Byte]? = None
    let mut np : Int? = None
    let mut nt : Int? = None
    let mut nm : Int? = None
    let mut alpha = false
    for ai in it.props {
      if ai <= 0 || ai > props.length() {
        raise AvifError::Invalid
      }
      let q = props[ai - 1]
      if q.kind == t_ispe {
        w = q.width
        h = q.height
      }
      if q.kind == t_av1c {
        av1 = Some(q.data)
        let parsed = parse_av1c(data, q)
        depth = parsed.0
        mono = parsed.1
        yuv = parsed.2
      }
      if q.kind == t_colr {
        np = Some(q.p)
        nt = Some(q.t)
        nm = Some(q.m)
      }
      if q.kind == t_auxc {
        alpha = true
      }
    }
    if w <= 0 || h <= 0 || av1 is None || it.offs.length() == 0 {
      raise AvifError::Invalid
    }
    let idat = find_box(bs, mi, t_idat)
    let payload : Array[Byte] = []
    for i in 0..<it.offs.length() {
      let base = if it.method_id == 1 {
        match idat {
          Some(x) => x.payload
          None => raise AvifError::Invalid
        }
      } else {
        0
      }
      let off = base + it.base + it.offs[i]
      let len = it.lens[i]
      if off < 0 || len < 0 || off > data.length() - len {
        raise AvifError::Invalid
      }
      for j in off..<(off + len) {
        payload.push(data[j])
      }
    }
    Some({
      width: w,
      height: h,
      bit_depth: depth,
      monochrome: mono,
      yuv420: yuv,
      has_alpha: alpha,
      av1c: av1.unwrap(),
      payload,
      nclx_primaries: np,
      nclx_transfer: nt,
      nclx_matrix: nm,
    })
  } catch {
    _ => None
  }
}

///|
fn parse_iloc(
  d : Array[Byte],
  b : Box,
  xs : Array[Item],
) -> Unit raise AvifError {
  let p = b.payload
  let v = u8(d, p, b.end)
  let a = u8(d, p + 4, b.end)
  let os = a >> 4
  let ls = a & 15
  let z = u8(d, p + 5, b.end)
  let bs = z >> 4
  let isz = if v >= 1 { z & 15 } else { 0 }
  if (os != 0 && os != 4 && os != 8) ||
    (ls != 0 && ls != 4 && ls != 8) ||
    (bs != 0 && bs != 4 && bs != 8) {
    raise AvifError::Unsupported
  }
  let mut q = p + 6
  let n = if v == 0 { u16(d, q, b.end) } else { u32(d, q, b.end) }
  q = q + (if v == 0 { 2 } else { 4 })
  for _ in 0..<n {
    let id = if v < 2 { u16(d, q, b.end) } else { u32(d, q, b.end) }
    q = q + (if v < 2 { 2 } else { 4 })
    let method_code = if v >= 1 { (u16(d, q, b.end) >> 12) & 15 } else { 0 }
    if method_code != 0 && method_code != 1 {
      raise AvifError::Unsupported
    }
    if v >= 1 {
      q = q + 2
    }
    let data_reference = u16(d, q, b.end)
    if data_reference != 0 {
      raise AvifError::Unsupported
    }
    q = q + 2
    let base = if bs == 0 {
      0
    } else if bs == 4 {
      u32(d, q, b.end)
    } else {
      u64(d, q, b.end)
    }
    q = q + bs
    let ec = u16(d, q, b.end)
    q = q + 2
    let xi = idx_item(xs, id)
    for _ in 0..<ec {
      if v >= 1 && isz != 0 {
        q = q + isz
      }
      let off = if os == 0 {
        0
      } else if os == 4 {
        u32(d, q, b.end)
      } else {
        u64(d, q, b.end)
      }
      q = q + os
      let len = if ls == 0 {
        0
      } else if ls == 4 {
        u32(d, q, b.end)
      } else {
        u64(d, q, b.end)
      }
      q = q + ls
      if xi >= 0 {
        xs[xi].method_id = method_code
        xs[xi].base = base
        xs[xi].offs.push(off)
        xs[xi].lens.push(len)
      }
    }
  }
}

///|
fn parse_ipma(
  d : Array[Byte],
  bs : Array[Box],
  iprp : Box?,
  xs : Array[Item],
) -> Unit raise AvifError {
  let rp = match iprp {
    Some(x) => x
    None => return
  }
  let ri = idx_box(bs, rp.start)
  let b = match find_box(bs, ri, t_ipma) {
    Some(x) => x
    None => return
  }
  let p = b.payload
  let flags = u32(d, p, b.end) & 0xFFFFFF
  let mut q = p + 4
  let n = u32(d, q, b.end)
  q = q + 4
  for _ in 0..<n {
    let id = if (flags & 1) != 0 { u32(d, q, b.end) } else { u16(d, q, b.end) }
    q = q + (if (flags & 1) != 0 { 4 } else { 2 })
    let c = u8(d, q, b.end)
    q = q + 1
    let xi = idx_item(xs, id)
    for _ in 0..<c {
      let a = if (flags & 2) != 0 { u16(d, q, b.end) } else { u8(d, q, b.end) }
      q = q + (if (flags & 2) != 0 { 2 } else { 1 })
      if xi >= 0 {
        let property = if (flags & 2) != 0 { a & 0x7FFF } else { a & 0x7F }
        xs[xi].props.push(property)
      }
    }
  }
}

///|
fn parse_props(
  d : Array[Byte],
  bs : Array[Box],
  iprp : Box?,
) -> Array[Prop] raise AvifError {
  let out : Array[Prop] = []
  let rp = match iprp {
    Some(x) => x
    None => return out
  }
  let ri = idx_box(bs, rp.start)
  let co = match find_box(bs, ri, t_ipco) {
    Some(x) => x
    None => return out
  }
  let ci = idx_box(bs, co.start)
  for b in bs {
    if b.parent != ci {
      continue
    }
    if b.typ == t_ispe {
      out.push({
        kind: b.typ,
        width: u32(d, b.payload + 4, b.end),
        height: u32(d, b.payload + 8, b.end),
        data: [],
        p: 0,
        t: 0,
        m: 0,
      })
    } else if b.typ == t_av1c {
      out.push({
        kind: b.typ,
        width: 0,
        height: 0,
        data: slice(d, b.payload, b.end),
        p: 0,
        t: 0,
        m: 0,
      })
    } else if b.typ == t_colr &&
      b.end - b.payload >= 11 &&
      u32(d, b.payload, b.end) == t_nclx {
      out.push({
        kind: b.typ,
        width: 0,
        height: 0,
        data: [],
        p: u16(d, b.payload + 4, b.end),
        t: u16(d, b.payload + 6, b.end),
        m: u16(d, b.payload + 8, b.end),
      })
    } else if b.typ == t_auxc {
      out.push({ kind: b.typ, width: 0, height: 0, data: [], p: 0, t: 0, m: 0, })
    } else {
      out.push({ kind: b.typ, width: 0, height: 0, data: [], p: 0, t: 0, m: 0, })
    }
  }
  out
}
