/// Masked-compound wedge masks (AV1 §7.11.3.11-14).
///
/// A wedge mask is a `64 x 64` blend-weight table cut down to the block's own
/// size along one of six directions, optionally mirrored. The table is built
/// from three one-dimensional master columns: the oblique-63 column is sampled
/// with a per-row shift, and the other directions are its transposes and
/// complements (go-av1 `decode/wedge.go`, `initWedgeMasks`).

///|
/// Direction indices in the wedge codebook.
const AV1_WEDGE_HORIZONTAL : Int = 0

///|
const AV1_WEDGE_VERTICAL : Int = 1

///|
const AV1_WEDGE_OBLIQUE27 : Int = 2

///|
const AV1_WEDGE_OBLIQUE63 : Int = 3

///|
const AV1_WEDGE_OBLIQUE117 : Int = 4

///|
const AV1_WEDGE_OBLIQUE153 : Int = 5

///|
/// `Wedge_Master_Oblique_Odd` (go-av1 `decode/wedge.go`).
let av1_wedge_master_oblique_odd : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 1, 2, 6, 18, 37, 53, 60, 63, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
]

///|
/// `Wedge_Master_Oblique_Even`.
let av1_wedge_master_oblique_even : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 1, 4, 11, 27, 46, 58, 62, 63, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
]

///|
/// `Wedge_Master_Vertical`.
let av1_wedge_master_vertical : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 2, 7, 21, 43, 57, 62, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
]

///|
/// `Wedge_Codebook[3][16][3]` = { direction, xoff, yoff } per block shape
/// (0 tall, 1 wide, 2 square) and wedge index.
let av1_wedge_codebook : Array[Array[Array[Int]]] = [
  [
    [AV1_WEDGE_OBLIQUE27, 4, 4],
    [AV1_WEDGE_OBLIQUE63, 4, 4],
    [AV1_WEDGE_OBLIQUE117, 4, 4],
    [AV1_WEDGE_OBLIQUE153, 4, 4],
    [AV1_WEDGE_HORIZONTAL, 4, 2],
    [AV1_WEDGE_HORIZONTAL, 4, 4],
    [AV1_WEDGE_HORIZONTAL, 4, 6],
    [AV1_WEDGE_VERTICAL, 4, 4],
    [AV1_WEDGE_OBLIQUE27, 4, 2],
    [AV1_WEDGE_OBLIQUE27, 4, 6],
    [AV1_WEDGE_OBLIQUE153, 4, 2],
    [AV1_WEDGE_OBLIQUE153, 4, 6],
    [AV1_WEDGE_OBLIQUE63, 2, 4],
    [AV1_WEDGE_OBLIQUE63, 6, 4],
    [AV1_WEDGE_OBLIQUE117, 2, 4],
    [AV1_WEDGE_OBLIQUE117, 6, 4],
  ],
  [
    [AV1_WEDGE_OBLIQUE27, 4, 4],
    [AV1_WEDGE_OBLIQUE63, 4, 4],
    [AV1_WEDGE_OBLIQUE117, 4, 4],
    [AV1_WEDGE_OBLIQUE153, 4, 4],
    [AV1_WEDGE_VERTICAL, 2, 4],
    [AV1_WEDGE_VERTICAL, 4, 4],
    [AV1_WEDGE_VERTICAL, 6, 4],
    [AV1_WEDGE_HORIZONTAL, 4, 4],
    [AV1_WEDGE_OBLIQUE27, 4, 2],
    [AV1_WEDGE_OBLIQUE27, 4, 6],
    [AV1_WEDGE_OBLIQUE153, 4, 2],
    [AV1_WEDGE_OBLIQUE153, 4, 6],
    [AV1_WEDGE_OBLIQUE63, 2, 4],
    [AV1_WEDGE_OBLIQUE63, 6, 4],
    [AV1_WEDGE_OBLIQUE117, 2, 4],
    [AV1_WEDGE_OBLIQUE117, 6, 4],
  ],
  [
    [AV1_WEDGE_OBLIQUE27, 4, 4],
    [AV1_WEDGE_OBLIQUE63, 4, 4],
    [AV1_WEDGE_OBLIQUE117, 4, 4],
    [AV1_WEDGE_OBLIQUE153, 4, 4],
    [AV1_WEDGE_HORIZONTAL, 4, 2],
    [AV1_WEDGE_HORIZONTAL, 4, 6],
    [AV1_WEDGE_VERTICAL, 2, 4],
    [AV1_WEDGE_VERTICAL, 6, 4],
    [AV1_WEDGE_OBLIQUE27, 4, 2],
    [AV1_WEDGE_OBLIQUE27, 4, 6],
    [AV1_WEDGE_OBLIQUE153, 4, 2],
    [AV1_WEDGE_OBLIQUE153, 4, 6],
    [AV1_WEDGE_OBLIQUE63, 2, 4],
    [AV1_WEDGE_OBLIQUE63, 6, 4],
    [AV1_WEDGE_OBLIQUE117, 2, 4],
    [AV1_WEDGE_OBLIQUE117, 6, 4],
  ],
]

///|
/// `Wedge_Bits[BLOCK_SIZES]`: the number of wedge index bits per block size
/// (zero means this size cannot code a wedge at all). The nine sizes that can
/// are the ones dav1d fills: 8x8..32x32 in the pyramid, plus 8x32 and 32x8.
let av1_wedge_bits : Array[Int] = [
  0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 0, 0,
]

///|
/// Whether a block size can code a wedge.
pub fn av1_wedge_shape_ok(width : Int, height : Int) -> Bool {
  match av1_intra_block_index(width, height) {
    Some(index) => index < av1_wedge_bits.length() && av1_wedge_bits[index] != 0
    None => false
  }
}

///|
/// The six `64 x 64` master tables, built per call (the construction is a few
/// tens of thousands of writes, and a frame has only a handful of wedge
/// blocks).
fn av1_wedge_master() -> Array[Array[Array[Int]]] {
  let master : Array[Array[Array[Int]]] = Array::make(6, [])
  for d in 0..<6 {
    master[d] = Array::makei(64, _ => Array::make(64, 0))
  }
  for j in 0..<64 {
    let mut shift = 16
    let mut i = 0
    while i < 64 {
      let even_index = if j - shift < 0 {
        0
      } else if j - shift > 63 {
        63
      } else {
        j - shift
      }
      master[AV1_WEDGE_OBLIQUE63][i][j] = av1_wedge_master_oblique_even[even_index]
      shift = shift - 1
      let odd_index = if j - shift < 0 {
        0
      } else if j - shift > 63 {
        63
      } else {
        j - shift
      }
      master[AV1_WEDGE_OBLIQUE63][i + 1][j] = av1_wedge_master_oblique_odd[odd_index]
      master[AV1_WEDGE_VERTICAL][i][j] = av1_wedge_master_vertical[j]
      master[AV1_WEDGE_VERTICAL][i + 1][j] = av1_wedge_master_vertical[j]
      i = i + 2
    }
  }
  for i in 0..<64 {
    for j in 0..<64 {
      let mask = master[AV1_WEDGE_OBLIQUE63][i][j]
      master[AV1_WEDGE_OBLIQUE27][j][i] = mask
      master[AV1_WEDGE_OBLIQUE117][i][63 - j] = 64 - mask
      master[AV1_WEDGE_OBLIQUE153][63 - j][i] = 64 - mask
      master[AV1_WEDGE_HORIZONTAL][j][i] = master[AV1_WEDGE_VERTICAL][i][j]
    }
  }
  master
}

///|
/// The `width x height` wedge mask for one block, indexed `[y][x]`, or None
/// when the block size cannot code a wedge. The sign chooses each of the two
/// mirrored variants: the mask whose average is at least 32, or its
/// complement (AV1 §7.11.3.11).
pub fn av1_wedge_mask(
  width : Int,
  height : Int,
  index : Int,
  sign : Int,
) -> Array[Int]? {
  let master = av1_wedge_master()
  let shape = if height > width { 0 } else if height < width { 1 } else { 2 }
  let entry = av1_wedge_codebook[shape][index]
  let direction = entry[0]
  let xoff = 32 - ((entry[1] * width) >> 3)
  let yoff = 32 - ((entry[2] * height) >> 3)
  if xoff < 0 || yoff < 0 || xoff + width > 64 || yoff + height > 64 {
    return None
  }
  let mut sum = 0
  for i in 0..<width {
    sum = sum + master[direction][yoff][xoff + i]
  }
  for i in 1..<height {
    sum = sum + master[direction][yoff + i][xoff]
  }
  let average = (sum + (width + height - 1) / 2) / (width + height - 1)
  let flip = if average < 32 { 1 } else { 0 }
  let out : Array[Int] = Array::make(width * height, 0)
  for i in 0..<height {
    for j in 0..<width {
      let value = master[direction][yoff + i][xoff + j]
      out[i * width + j] = if flip == sign { value } else { 64 - value }
    }
  }
  Some(out)
}

///|
/// The wedge mask on one plane's sample grid (AV1 §7.11.3.14): the luma mask
/// itself for plane zero, otherwise the luma mask averaged down two-by-two
/// (4:2:2) or two-by-two-by-two (4:2:0) with the spec's rounding.
fn av1_wedge_plane_mask(
  width : Int,
  height : Int,
  index : Int,
  sign : Int,
  sub_x : Int,
  sub_y : Int,
) -> Array[Int]? {
  let luma = match av1_wedge_mask(width, height, index, sign) {
    Some(value) => value
    None => return None
  }
  if sub_x != 1 {
    return Some(luma)
  }
  let out_w = width >> sub_x
  let out_h = height >> sub_y
  let out : Array[Int] = Array::make(out_w * out_h, 0)
  for i in 0..<out_h {
    for j in 0..<out_w {
      let base = i * (1 + sub_y) * width + 2 * j
      let mut sum = luma[base] + luma[base + 1]
      if sub_y == 1 {
        sum = sum + luma[base + width] + luma[base + width + 1]
      }
      out[i * out_w + j] = if sub_y == 1 {
        (sum + 2) >> 2
      } else {
        (sum + 1) >> 1
      }
    }
  }
  Some(out)
}

///|
/// The difference-weight mask of AV1 §7.11.3.12: one weight per luma sample
/// derived from how far apart the two predictions are there, `38 + diff/16`
/// clipped to 64, complemented when `mask_type` selects the mirrored variant.
/// The chroma planes take the luma mask averaged down to their sample grid by
/// §7.11.3.14, so this is always built at luma size and reduced here - the two
/// predictions handed in are this plane's, but only luma's reach the weight.
fn av1_diffwtd_mask(
  first : Array[Int],
  second : Array[Int],
  width : Int,
  height : Int,
  sub_x : Int,
  sub_y : Int,
  mask_type : Int,
  bit_depth : Int,
) -> Array[Int] {
  // The two predictions arrive as filter intermediates: for an 8-bit stream
  // that is the sample scaled by 16 (`interPostRound` is 4), for a 12-bit one
  // by 4. The mask's own rounding is the reference decoder's
  // `38 + ((|diff| + rnd) >> sh)` over those intermediates, which on the
  // sample scale is `38 + diff / 16` at 8 bits.
  let shift = bit_depth + (if bit_depth == 12 { 2 } else { 4 }) - 4
  let rnd = 1 << (shift - 5)
  let luma = Array::make(width * height, 0)
  for k in 0..<luma.length() {
    let diff = if first[k] > second[k] {
      first[k] - second[k]
    } else {
      second[k] - first[k]
    }
    let m = 38 + ((diff + rnd) >> shift)
    let clipped = if m > 64 { 64 } else { m }
    luma[k] = if mask_type == 0 { clipped } else { 64 - clipped }
  }
  if sub_x != 1 {
    return luma
  }
  av1_reduce_plane_mask(luma, width, height, sub_x, sub_y)
}

///|
///|
/// Average a luma-sized mask down to one plane's sample grid, the reduction
/// §7.11.3.14 applies to every mask the luma plane built: two columns for 4:2:2,
/// a 2x2 group for 4:2:0, each rounded the way the mask blend process rounds.
fn av1_reduce_plane_mask(
  luma : Array[Int],
  width : Int,
  height : Int,
  sub_x : Int,
  sub_y : Int,
) -> Array[Int] {
  if sub_x != 1 {
    return luma
  }
  let out_w = width >> sub_x
  let out_h = height >> sub_y
  let out = Array::make(out_w * out_h, 0)
  for i in 0..<out_h {
    for j in 0..<out_w {
      let base = i * (1 + sub_y) * width + 2 * j
      let mut sum = luma[base] + luma[base + 1]
      if sub_y == 1 {
        sum = sum + luma[base + width] + luma[base + width + 1]
      }
      out[i * out_w + j] = if sub_y == 1 {
        (sum + 2) >> 2
      } else {
        (sum + 1) >> 1
      }
    }
  }
  out
}
