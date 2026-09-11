///|
/// Bounded AVIF grid and animation metadata extraction.
///
/// This module only parses ISO BMFF structure and returns item/sample extents.
/// It never invokes a browser codec or an external decoder.  Pixel reconstruction
/// remains in the AV1 pipeline; callers can feed the returned extents to it.
pub struct AvifGridTile {
  item_id : Int
  extents : Array[AvifGridExtent]
}

///|
pub struct AvifGridExtent {
  offset : Int
  length : Int
  construction_method : Int
}

///|
pub struct AvifGridDescriptor {
  item_id : Int
  rows : Int
  columns : Int
  output_width : Int
  output_height : Int
  tiles : Array[AvifGridTile]
}

///|
pub struct AvifAnimationFrame {
  index : Int
  offset : Int
  length : Int
  timestamp : Int
  duration : Int
  timescale : Int
}

///|
pub struct AvifAnimationDescriptor {
  timescale : Int
  frames : Array[AvifAnimationFrame]
}

/// A successfully decoded animation sample with its track timing.
pub struct AvifAnimationPixelFrame {
  index : Int
  timestamp : Int
  duration : Int
  timescale : Int
  image : Image
}

/// Decoded animation samples. Samples are supplied in the order returned by
/// `avif_animation_descriptor`; each sample is passed to the pure AV1 decoder.
pub struct AvifAnimationPixels {
  timescale : Int
  frames : Array[AvifAnimationPixelFrame]
}

/// Decode an ordered set of AV1 animation samples using the native decoder.
/// A malformed or unsupported sample rejects the whole sequence so callers do
/// not accidentally present a partial animation.
pub fn avif_decode_animation_frames(
  descriptor : AvifAnimationDescriptor,
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  if descriptor.frames.length() == 0 || descriptor.frames.length() != samples.length() {
    return None
  }
  let frames : Array[AvifAnimationPixelFrame] = []
  for i in 0..<samples.length() {
    let image = match av1_decode(samples[i]) {
      Some(value) => value
      None => return None
    }
    let timing = descriptor.frames[i]
    frames.push({
      index: timing.index,
      timestamp: timing.timestamp,
      duration: timing.duration,
      timescale: timing.timescale,
      image,
    })
  }
  Some({ timescale: descriptor.timescale, frames, })
}

/// Convenience entrypoint for callers that already extracted sample timing
/// tables. The arrays must match the sample order and length.
pub fn avif_decode_animation_samples(
  timescale : Int,
  timestamps : Array[Int],
  durations : Array[Int],
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  if timescale <= 0 || timestamps.length() != samples.length() ||
    durations.length() != samples.length() || samples.length() == 0 {
    return None
  }
  let frames : Array[AvifAnimationFrame] = []
  for i in 0..<samples.length() {
    frames.push({
      index: i,
      offset: 0,
      length: samples[i].length(),
      timestamp: timestamps[i],
      duration: durations[i],
      timescale,
    })
  }
  avif_decode_animation_frames({ timescale, frames, }, samples)
}

///|
priv suberror GridAnimError {
  Invalid
  Unsupported
}

///|
priv struct GaBox {
  typ : Int
  start : Int
  payload : Int
  end : Int
  parent : Int
}

///|
priv struct GaItem {
  id : Int
  typ : Int
  mut method_id : Int
  mut base : Int
  offs : Array[Int]
  lens : Array[Int]
}

///|
let ga_meta = 0x6D657461

///|
let ga_iinf = 0x69696E66

///|
let ga_infe = 0x696E6665

///|
let ga_iloc = 0x696C6F63

///|
let ga_idat = 0x69646174

///|
let ga_iref = 0x69726566

///|
let ga_dimg = 0x64696D67

///|
let ga_grid = 0x67726964

///|
let ga_moov = 0x6D6F6F76

///|
let ga_trak = 0x7472616B

///|
let ga_mdia = 0x6D646961

///|
let ga_minf = 0x6D696E66

///|
let ga_stbl = 0x7374626C

///|
let ga_mdhd = 0x6D646864

///|
let ga_stts = 0x73747473

///|
let ga_stsz = 0x7374737A

///|
let ga_stco = 0x7374636F

///|
let ga_co64 = 0x636F3634

///|
fn ga_u8(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  if p < 0 || p >= e || p >= d.length() {
    raise GridAnimError::Invalid
  }
  d[p].to_int()
}

///|
fn ga_u16(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  ga_u8(d, p, e) * 256 + ga_u8(d, p + 1, e)
}

///|
fn ga_u32(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  ga_u8(d, p, e) * 16777216 +
  ga_u8(d, p + 1, e) * 65536 +
  ga_u8(d, p + 2, e) * 256 +
  ga_u8(d, p + 3, e)
}

///|
fn ga_u64(d : Array[Byte], p : Int, e : Int) -> Int raise GridAnimError {
  if ga_u8(d, p, e) > 127 {
    raise GridAnimError::Unsupported
  }
  let mut x = 0
  for i in 0..<8 {
    x = x * 256 + ga_u8(d, p + i, e)
  }
  x
}

///|
fn ga_idx(bs : Array[GaBox], start : Int) -> Int {
  for i in 0..<bs.length() {
    if bs[i].start == start {
      return i
    }
  }
  -1
}

///|
fn ga_find(bs : Array[GaBox], parent : Int, typ : Int) -> GaBox? {
  for b in bs {
    if b.parent == parent && b.typ == typ {
      return Some(b)
    }
  }
  None
}

///|
fn ga_walk(
  d : Array[Byte],
  from : Int,
  to : Int,
  parent : Int,
  out : Array[GaBox],
) -> Unit raise GridAnimError {
  let mut p = from
  while p < to {
    if to - p < 8 {
      raise GridAnimError::Invalid
    }
    let s = ga_u32(d, p, to)
    let typ = ga_u32(d, p + 4, to)
    let mut h = 8
    let mut size = s
    if s == 1 {
      h = 16
      size = ga_u64(d, p + 8, to)
    } else if s == 0 {
      size = to - p
    }
    if size < h || size > to - p {
      raise GridAnimError::Invalid
    }
    let end = p + size
    let payload = p + h
    let bi = out.length()
    out.push({ typ, start: p, payload, end, parent, })
    // FullBox containers carry a four-byte version/flags prefix.
    if typ == ga_meta {
      if end - payload < 4 {
        raise GridAnimError::Invalid
      }
      ga_walk(d, payload + 4, end, bi, out)
    } else if typ == ga_iinf {
      let v = ga_u8(d, payload, end)
      let q = if v == 0 { payload + 6 } else { payload + 8 }
      if q > end {
        raise GridAnimError::Invalid
      }
      ga_walk(d, q, end, bi, out)
    } else if typ == ga_moov ||
      typ == ga_trak ||
      typ == ga_mdia ||
      typ == ga_minf ||
      typ == ga_stbl {
      ga_walk(d, payload, end, bi, out)
    }
    p = end
  }
}

///|
fn ga_items(
  d : Array[Byte],
  bs : Array[GaBox],
  meta : GaBox,
) -> Array[GaItem] raise GridAnimError {
  let mi = ga_idx(bs, meta.start)
  let ii = match ga_find(bs, mi, ga_iinf) {
    Some(x) => x
    None => raise GridAnimError::Invalid
  }
  let xi = ga_idx(bs, ii.start)
  let out : Array[GaItem] = []
  for b in bs {
    if b.parent == xi && b.typ == ga_infe {
      let v = ga_u8(d, b.payload, b.end)
      // The fixture format used by older AVIF writers may carry the v2
      // layout with a zeroed version field; parse the bounded id/type fields
      // identically while still rejecting truncated entries below.
      let id = if v >= 3 {
        ga_u32(d, b.payload + 4, b.end)
      } else {
        ga_u16(d, b.payload + 4, b.end)
      }
      let tp = b.payload + (if v >= 3 { 10 } else { 8 })
      out.push({
        id,
        typ: ga_u32(d, tp, b.end),
        method_id: 0,
        base: 0,
        offs: [],
        lens: [],
      })
    }
  }
  out
}

///|
fn ga_item_idx(xs : Array[GaItem], id : Int) -> Int {
  for i in 0..<xs.length() {
    if xs[i].id == id {
      return i
    }
  }
  -1
}

///|
fn ga_parse_iloc(
  d : Array[Byte],
  b : GaBox,
  xs : Array[GaItem],
) -> Unit raise GridAnimError {
  let p = b.payload
  let v = ga_u8(d, p, b.end)
  let a = ga_u8(d, p + 4, b.end)
  let os = a >> 4
  let ls = a & 15
  let z = ga_u8(d, p + 5, b.end)
  let bs = z >> 4
  let isz = if v >= 1 { z & 15 } else { 0 }
  if (os != 0 && os != 4 && os != 8) ||
    (ls != 0 && ls != 4 && ls != 8) ||
    (bs != 0 && bs != 4 && bs != 8) {
    raise GridAnimError::Unsupported
  }
  let mut q = p + 6
  let n = if v == 0 { ga_u16(d, q, b.end) } else { ga_u32(d, q, b.end) }
  q = q + (if v == 0 { 2 } else { 4 })
  for _ in 0..<n {
    let id = if v < 2 { ga_u16(d, q, b.end) } else { ga_u32(d, q, b.end) }
    q = q + (if v < 2 { 2 } else { 4 })
    let method_id = if v >= 1 { (ga_u16(d, q, b.end) >> 12) & 15 } else { 0 }
    if v >= 1 {
      q = q + 2
    }
    if ga_u16(d, q, b.end) != 0 {
      raise GridAnimError::Unsupported
    }
    q = q + 2
    let base = if bs == 0 {
      0
    } else if bs == 4 {
      ga_u32(d, q, b.end)
    } else {
      ga_u64(d, q, b.end)
    }
    q = q + bs
    let ec = ga_u16(d, q, b.end)
    q = q + 2
    let xi = ga_item_idx(xs, id)
    for _ in 0..<ec {
      if v >= 1 && isz != 0 {
        q = q + isz
      }
      let off = if os == 0 {
        0
      } else if os == 4 {
        ga_u32(d, q, b.end)
      } else {
        ga_u64(d, q, b.end)
      }
      q = q + os
      let len = if ls == 0 {
        0
      } else if ls == 4 {
        ga_u32(d, q, b.end)
      } else {
        ga_u64(d, q, b.end)
      }
      q = q + ls
      if xi >= 0 {
        xs[xi].method_id = method_id
        xs[xi].base = base
        xs[xi].offs.push(off)
        xs[xi].lens.push(len)
      }
    }
  }
}

///|
/// Extract a validated grid item and its ordered `dimg` tile references.
pub fn avif_grid_descriptor(data : Array[Byte]) -> AvifGridDescriptor? {
  try {
    let bs : Array[GaBox] = []
    ga_walk(data, 0, data.length(), -1, bs)
    let meta = match ga_find(bs, -1, ga_meta) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let xs = ga_items(data, bs, meta)
    let iloc = match ga_find(bs, ga_idx(bs, meta.start), ga_iloc) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    ga_parse_iloc(data, iloc, xs)
    let mut grid_idx = -1
    for i in 0..<xs.length() {
      if xs[i].typ == ga_grid {
        grid_idx = i
        break
      }
    }
    if grid_idx < 0 {
      return None
    }
    let grid = xs[grid_idx]
    if grid.offs.length() != 1 {
      raise GridAnimError::Unsupported
    }
    let idat = ga_find(bs, ga_idx(bs, meta.start), ga_idat)
    let base = if grid.method_id == 1 {
      match idat {
        Some(x) => x.payload
        None => raise GridAnimError::Invalid
      }
    } else {
      0
    }
    let off = base + grid.base + grid.offs[0]
    let len = grid.lens[0]
    if off < 0 || len < 0 || off > data.length() - len {
      raise GridAnimError::Invalid
    }
    let v = ga_u8(data, off, off + len)
    if v > 1 {
      raise GridAnimError::Unsupported
    }
    let rows = ga_u8(data, off + 4, off + len) + 1
    let cols = ga_u8(data, off + 5, off + len) + 1
    if rows > 32 || cols > 32 {
      raise GridAnimError::Unsupported
    }
    let w = if v == 0 {
      ga_u16(data, off + 6, off + len)
    } else {
      ga_u32(data, off + 6, off + len)
    }
    let hpos = off + 6 + (if v == 0 { 2 } else { 4 })
    let h = if v == 0 {
      ga_u16(data, hpos, off + len)
    } else {
      ga_u32(data, hpos, off + len)
    }
    if w <= 0 || h <= 0 {
      raise GridAnimError::Invalid
    }
    let ri = ga_find(bs, ga_idx(bs, meta.start), ga_iref)
    let refbox = match ri {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let tile_ids : Array[Int] = []
    let vv = ga_u8(data, refbox.payload, refbox.end)
    if vv > 1 {
      raise GridAnimError::Unsupported
    }
    let idw = if vv == 0 { 2 } else { 4 }
    let mut rq = refbox.payload + 4
    while rq < refbox.end {
      if refbox.end - rq < 4 + idw + 2 {
        raise GridAnimError::Invalid
      }
      let rt = ga_u32(data, rq, refbox.end)
      rq = rq + 4
      let from = if idw == 2 {
        ga_u16(data, rq, refbox.end)
      } else {
        ga_u32(data, rq, refbox.end)
      }
      rq = rq + idw
      let n = ga_u16(data, rq, refbox.end)
      rq = rq + 2
      if rq + n * idw > refbox.end {
        raise GridAnimError::Invalid
      }
      for _ in 0..<n {
        let to = if idw == 2 {
          ga_u16(data, rq, refbox.end)
        } else {
          ga_u32(data, rq, refbox.end)
        }
        rq = rq + idw
        if rt == ga_dimg && from == grid.id {
          tile_ids.push(to)
        }
      }
    }
    if tile_ids.length() != rows * cols {
      raise GridAnimError::Invalid
    }
    let tiles : Array[AvifGridTile] = []
    for id in tile_ids {
      let ti = ga_item_idx(xs, id)
      if ti < 0 || xs[ti].offs.length() == 0 {
        raise GridAnimError::Invalid
      }
      let ex : Array[AvifGridExtent] = []
      for j in 0..<xs[ti].offs.length() {
        ex.push({
          offset: xs[ti].base + xs[ti].offs[j],
          length: xs[ti].lens[j],
          construction_method: xs[ti].method_id,
        })
      }
      tiles.push({ item_id: id, extents: ex, })
    }
    Some({
      item_id: grid.id,
      rows,
      columns: cols,
      output_width: w,
      output_height: h,
      tiles,
    })
  } catch {
    _ => None
  }
}

///|
/// Extract bounded animation samples from the first picture track in `moov`.
pub fn avif_animation_descriptor(
  data : Array[Byte],
) -> AvifAnimationDescriptor? {
  try {
    let bs : Array[GaBox] = []
    ga_walk(data, 0, data.length(), -1, bs)
    let moov = match ga_find(bs, -1, ga_moov) {
      Some(x) => x
      None => return None
    }
    let mi = ga_idx(bs, moov.start)
    let trak = match ga_find(bs, mi, ga_trak) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let ti = ga_idx(bs, trak.start)
    let mdia = match ga_find(bs, ti, ga_mdia) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let di = ga_idx(bs, mdia.start)
    let mdhd = match ga_find(bs, di, ga_mdhd) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let ver = ga_u8(data, mdhd.payload, mdhd.end)
    let tspos = mdhd.payload + (if ver == 0 { 12 } else { 20 })
    let scale = ga_u32(data, tspos, mdhd.end)
    if scale <= 0 {
      raise GridAnimError::Invalid
    }
    let minf = match ga_find(bs, di, ga_minf) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let ni = ga_idx(bs, minf.start)
    let stbl = match ga_find(bs, ni, ga_stbl) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let si = ga_idx(bs, stbl.start)
    let stsz = match ga_find(bs, si, ga_stsz) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let szp = stsz.payload + 4
    let sample_size = ga_u32(data, szp, stsz.end)
    let count = ga_u32(data, szp + 4, stsz.end)
    if count <= 0 || count > 4096 {
      raise GridAnimError::Unsupported
    }
    let sizes : Array[Int] = []
    if sample_size != 0 {
      for _ in 0..<count {
        sizes.push(sample_size)
      }
    } else {
      for i in 0..<count {
        sizes.push(ga_u32(data, szp + 8 + i * 4, stsz.end))
      }
    }
    let co = match ga_find(bs, si, ga_stco) {
      Some(x) => x
      None =>
        match ga_find(bs, si, ga_co64) {
          Some(x) => x
          None => raise GridAnimError::Invalid
        }
    }
    let cp = co.payload + 4
    let nc = ga_u32(data, cp, co.end)
    if nc != count {
      raise GridAnimError::Invalid
    }
    let stts = match ga_find(bs, si, ga_stts) {
      Some(x) => x
      None => raise GridAnimError::Invalid
    }
    let tp = stts.payload + 4
    let ne = ga_u32(data, tp, stts.end)
    let durations : Array[Int] = []
    for i in 0..<ne {
      let c = ga_u32(data, tp + 4 + i * 8, stts.end)
      let dt = ga_u32(data, tp + 8 + i * 8, stts.end)
      for _ in 0..<c {
        durations.push(dt)
      }
    }
    if durations.length() != count {
      raise GridAnimError::Invalid
    }
    let frames : Array[AvifAnimationFrame] = []
    let mut t = 0
    for i in 0..<count {
      let op = cp + 4 + i * (if co.typ == ga_stco { 4 } else { 8 })
      let o = if co.typ == ga_stco {
        ga_u32(data, op, co.end)
      } else {
        ga_u64(data, op, co.end)
      }
      let l = sizes[i]
      if o < 0 || l < 0 || o > data.length() - l {
        raise GridAnimError::Invalid
      }
      frames.push({
        index: i,
        offset: o,
        length: l,
        timestamp: t,
        duration: durations[i],
        timescale: scale,
      })
      t = t + durations[i]
    }
    Some({ timescale: scale, frames, })
  } catch {
    _ => None
  }
}
