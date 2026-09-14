/// First executable AV1 tile milestone.
///
/// This module accepts a small, fully specified subset: a 32x32 or 64x64
/// reduced-still key frame, one tile, intra prediction, with square DCT_DCT
/// residuals for the legacy path and the full tx-mode leaf walk for frames
/// that select transform sizes. Entropy symbols are decoded from the tile
/// with the stateful MSAC reader. Other streams return None and remain
/// eligible for later milestones.

///|
/// Mutable CDF state for one transform context. UV blocks share one context
/// for the tile, as required by the AV1 symbol update process.
priv struct Av1DcContext {
  eob : Array[Int]
  base : Array[Int]
  br : Array[Int]
  sign : Array[Int]
}

///|
/// Decode an EOB=1 DC coefficient and run the exact integer inverse DCT.
fn av1_decode_single_dc(
  decoder : Av1SymbolDecoder,
  base_q_idx : Int,
  tx_ctx : Int,
  context : Av1DcContext,
  bit_depth? : Int = 8,
) -> Int? {
  if (tx_ctx != 3 && tx_ctx != 4) ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) {
    return None
  }
  if decoder.symbol(context.eob) != 0 {
    return None
  }
  let mut level = decoder.symbol(context.base) + 1
  if level > 2 {
    let mut complete = false
    for _ in 0..<4 {
      if complete {
        continue
      }
      let extra = decoder.symbol(context.br)
      level = level + extra
      if extra < 3 {
        complete = true
      }
    }
  }
  let sign = decoder.symbol(context.sign)
  if level > 14 {
    let mut length = 0
    let mut terminated = false
    while length < 32 && !terminated {
      length = length + 1
      terminated = decoder.bool() == 1
    }
    if !terminated {
      return None
    }
    let mut code = 1
    for _ in 0..<(length - 1) {
      code = (code << 1) | decoder.bool()
    }
    level = code + 14
  }
  if level > 65535 {
    return None
  }
  let denom = if tx_ctx == 4 { 4 } else { 2 }
  let dq = ((level * av1_dc_quant(bit_depth, base_q_idx)) & 0xFFFFFF) / denom
  let signed = if sign == 1 { -dq } else { dq }
  let side = if tx_ctx == 4 { 64 } else { 32 }
  let coeffs : Array[Int] = Array::make(side * side, 0)
  coeffs[0] = signed
  match av1_inverse_dct_2d(coeffs, side, side, bit_depth) {
    Some(residual) => Some(residual[0])
    None => None
  }
}

///|
/// Transform size context for the all_zero CDF (AV1 spec §5.11.39:
/// txSzCtx = (Tx_Size_Sqr + Tx_Size_Sqr_Up + 1) >> 1, which for square
/// transforms is 0..4 for 4x4..64x64).
fn av1_tx_size_ctx(side : Int) -> Int {
  if side <= 4 {
    0
  } else if side == 8 {
    1
  } else if side == 16 {
    2
  } else if side == 32 {
    3
  } else {
    4
  }
}

///|
/// Coefficient/all_zero context: rounded-up average of the square-down and
/// square-up transform size classes (AV1 coeffs syntax).
fn av1_tx_size_ctx_rect(width : Int, height : Int) -> Int {
  (av1_tx_size_ctx(width) + av1_tx_size_ctx(height) + 1) >> 1
}

///|
/// Luma all_zero context from the neighbour level model (AV1 spec §8.3,
/// readAllZero). `top`/`left` are the maximum neighbour cul levels over the
/// leaf's 4x4 units.
fn av1_txb_skip_ctx_luma(top : Int, left : Int, whole : Bool) -> Int {
  if whole {
    return 0
  }
  if top == 0 && left == 0 {
    return 1
  }
  if top == 0 || left == 0 {
    return if (if top > left { top } else { left }) > 3 { 3 } else { 2 }
  }
  if (if top > left { top } else { left }) <= 3 {
    return 4
  }
  if (if top < left { top } else { left }) <= 3 {
    return 5
  }
  6
}

///|
/// Chroma all_zero context (AV1 spec §8.3): 7 plus one per non-empty
/// neighbour side, plus 3 when the residual block exceeds the transform.
fn av1_txb_skip_ctx_chroma(above_nonzero : Bool, left_nonzero : Bool, whole : Bool,
) -> Int {
  let ctx = 7 +
    (if above_nonzero { 1 } else { 0 }) +
    (if left_nonzero { 1 } else { 0 })
  if whole {
    ctx
  } else {
    ctx + 3
  }
}

///|
/// dc_sign context from the neighbour dc categories (AV1 spec §8.3).
fn av1_dc_sign_ctx_from(above_dc : Array[Int], left_dc : Array[Int], x4 : Int, y4 : Int, width_units : Int, height_units? : Int = 0,
) -> Int {
  let h_units = if height_units > 0 { height_units } else { width_units }
  let mut score = 0
  for k in 0..<width_units {
    let a = above_dc[x4 + k]
    if a == 1 {
      score = score - 1
    } else if a == 2 {
      score = score + 1
    }
  }
  for k in 0..<h_units {
    let l = left_dc[y4 + k]
    if l == 1 {
      score = score - 1
    } else if l == 2 {
      score = score + 1
    }
  }
  if score < 0 {
    1
  } else if score > 0 {
    2
  } else {
    0
  }
}

///|
pub fn av1_decode_dc_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
) -> Image? {
  if loop_filter is Some(_) {
    let frame = match
      av1_decode_tile_planes(
        width,
        height,
        [0, width],
        [0, height],
        tile_payload,
        0,
        base_q_idx,
        disable_cdf_update,
        allow_screen_content_tools,
        full_range,
        matrix_coefficients,
        use_128x128_superblock,
        bit_depth,
        reduced_tx_set,
        enable_filter_intra,
        tx_mode_select,
        cdef,
        enable_intra_edge_filter~,
        loop_filter~,
      ) {
      Some(value) => value
      None => return None
    }
    return av1_frame_to_rgba(frame)
  }
  av1_decode_intra_tile(
    width,
    height,
    tile_payload,
    base_q_idx,
    disable_cdf_update,
    allow_screen_content_tools,
    full_range,
    matrix_coefficients,
    use_128x128_superblock,
    bit_depth,
    reduced_tx_set,
    enable_filter_intra,
    tx_mode_select,
    cdef~,
    enable_intra_edge_filter~,
  )
}
///|
/// Decode a complete tile group into a raster image when every tile is a
/// bounded intra tile supported by the current pixel path. Tile-local MSAC
/// state is reset for each payload. When CDEF is present, complete native-depth
/// planes are assembled before filtering across tile boundaries.
pub fn av1_decode_tile_group(
  width : Int,
  height : Int,
  tile_cols : Int,
  tile_rows : Int,
  tile_payload : Array[Byte],
  tile_size_bytes : Int,
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
) -> Image? {
  if width <= 0 ||
    height <= 0 ||
    width > MAX_IMAGE_PIXELS / height ||
    tile_cols <= 0 ||
    tile_cols > 1024 ||
    tile_rows <= 0 ||
    tile_rows > 1024 ||
    width % tile_cols != 0 ||
    height % tile_rows != 0 {
    return None
  }
  let tile_width = width / tile_cols
  let tile_height = height / tile_rows
  if tile_width < 16 || tile_width > 64 || tile_height < 16 || tile_height > 64 {
    return None
  }
  if cdef is Some(_) || loop_filter is Some(_) {
    let cols = Array::makei(tile_cols + 1, fn(i) { i * tile_width })
    let rows = Array::makei(tile_rows + 1, fn(i) { i * tile_height })
    let frame = match
      av1_decode_tile_planes(
        width,
        height,
        cols,
        rows,
        tile_payload,
        tile_size_bytes,
        base_q_idx,
        disable_cdf_update,
        allow_screen_content_tools,
        full_range,
        matrix_coefficients,
        use_128x128_superblock,
        bit_depth,
        reduced_tx_set,
        enable_filter_intra,
        tx_mode_select,
        cdef,
        enable_intra_edge_filter~,
        loop_filter~,
      ) {
      Some(value) => value
      None => return None
    }
    return av1_frame_to_rgba(frame)
  }
  let tiles = match
    av1_extract_tile_payloads(
      tile_payload, tile_cols, tile_rows, tile_size_bytes,
    ) {
    Some(value) => value
    None => return None
  }
  let output = Image::new(width, height)
  for tile in tiles {
    let image = match
      av1_decode_dc_tile(
        tile_width,
        tile_height,
        tile.bytes,
        base_q_idx,
        disable_cdf_update~,
        full_range~,
        matrix_coefficients~,
        use_128x128_superblock~,
        bit_depth~,
        allow_screen_content_tools~,
        tx_mode_select~,
        reduced_tx_set~,
        enable_filter_intra~,
        enable_intra_edge_filter~,
        loop_filter~,
      ) {
      Some(value) => value
      None => return None
    }
    for y in 0..<tile_height {
      for x in 0..<tile_width {
        let p = image.get_pixel(x, y)
        output.set_pixel(
          tile.col * tile_width + x,
          tile.row * tile_height + y,
          p.0,
          p.1,
          p.2,
          p.3,
        )
      }
    }
  }
  Some(output)
}
///|
/// Decode tiles whose superblock boundaries are explicitly known, including
/// non-uniform tile_info() layouts. Each tile keeps one entropy state across
/// its superblocks; frame filters run on the assembled native-depth planes.
pub fn av1_decode_tile_group_with_boundaries(
  width : Int,
  height : Int,
  tile_col_starts_sb : Array[Int],
  tile_row_starts_sb : Array[Int],
  superblock_pixels : Int,
  tile_payload : Array[Byte],
  tile_size_bytes : Int,
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
  monochrome? : Bool = false,
) -> Image? {
  if width <= 0 || height <= 0 || width > MAX_IMAGE_PIXELS / height {
    return None
  }
  let cols = match
    av1_frame_tile_starts(tile_col_starts_sb, superblock_pixels, width) {
    Some(value) => value
    None => return None
  }
  let rows = match
    av1_frame_tile_starts(tile_row_starts_sb, superblock_pixels, height) {
    Some(value) => value
    None => return None
  }
  let frame = match
    av1_decode_tile_planes(
      width,
      height,
      cols,
      rows,
      tile_payload,
      tile_size_bytes,
      base_q_idx,
      disable_cdf_update,
      allow_screen_content_tools,
      full_range,
      matrix_coefficients,
      use_128x128_superblock,
      bit_depth,
      reduced_tx_set,
      enable_filter_intra,
      tx_mode_select,
      cdef,
      monochrome~,
      enable_intra_edge_filter~,
      loop_filter~,
    ) {
    Some(value) => value
    None => return None
  }
  av1_frame_to_rgba(frame)
}
///|
/// Decode a reduced-still AV1 OBU stream through the supported intra syntax,
/// native-depth frame filters and final color conversion.
pub fn av1_decode(data : Array[Byte]) -> Image? {
  match av1_decode_frame_planes(data, allow_monochrome=true) {
    Some(frame) => av1_frame_to_rgba(frame)
    None => None
  }
}
///|
/// Decode an AVIF container through the same pure MoonBit intra frame
/// path. Unsupported syntax returns None; a validated
/// auxiliary alpha item is composed by `avif_decode_rgba` after this primary
/// image decode succeeds.
pub fn avif_decode(data : Array[Byte]) -> Image? {
  let input = avif_stage1_input(data)
  match input {
    None => avif_decode_grid_auto(data)
    Some(value) =>
      av1_decode_tile_group_with_boundaries(
        value.width,
        value.height,
        value.tile_col_starts_sb,
        value.tile_row_starts_sb,
        if value.use_128x128_superblock {
          128
        } else {
          64
        },
        value.tile_payload,
        value.tile_size_bytes,
        value.base_q_idx,
        disable_cdf_update=value.disable_cdf_update,
        allow_screen_content_tools=value.allow_screen_content_tools,
        full_range=value.full_range,
        matrix_coefficients=value.matrix_coefficients,
        use_128x128_superblock=value.use_128x128_superblock,
        bit_depth=value.bit_depth,
        tx_mode_select=value.tx_mode_select,
        reduced_tx_set=value.reduced_tx_set,
        enable_filter_intra=value.enable_filter_intra,
        enable_intra_edge_filter=value.enable_intra_edge_filter,
        cdef=value.cdef,
        loop_filter=value.loop_filter,
        monochrome=value.monochrome,
      )
  }
}
///|
test "single DC helper decodes a chroma coefficient" {
  let decoder = av1_msac_new([b'\x00', b'\x00'], false)
  let context = Av1DcContext::{
    eob: av1_dc_eob1024_cdf(33, 1),
    base: av1_dc_base_eob_dc_cdf(33, 3, 1),
    br: av1_dc_br_cdf(33, 1),
    sign: av1_dc_sign_cdf(33, 1),
  }
  let residual = av1_decode_single_dc(decoder, 33, 3, context).unwrap()
  assert_eq(residual, 0)
}

///|
test "tx size context maps square transforms to rows" {
  assert_eq(av1_tx_size_ctx(4), 0)
  assert_eq(av1_tx_size_ctx(8), 1)
  assert_eq(av1_tx_size_ctx(16), 2)
  assert_eq(av1_tx_size_ctx(32), 3)
  assert_eq(av1_tx_size_ctx(64), 4)
}

///|
test "txb skip context ladder follows the neighbour model" {
  // A single transform covering the whole residual block uses context 0.
  assert_eq(av1_txb_skip_ctx_luma(0, 0, true), 0)
  // Nothing decoded above or left uses context 1.
  assert_eq(av1_txb_skip_ctx_luma(0, 0, false), 1)
  // One empty side uses context 2 (or 3 when the other level exceeds 3).
  assert_eq(av1_txb_skip_ctx_luma(0, 2, false), 2)
  assert_eq(av1_txb_skip_ctx_luma(0, 9, false), 3)
  // Both sides populated.
  assert_eq(av1_txb_skip_ctx_luma(2, 2, false), 4)
  assert_eq(av1_txb_skip_ctx_luma(9, 2, false), 5)
  assert_eq(av1_txb_skip_ctx_luma(9, 9, false), 6)
  // Chroma context offsets from 7 and grows with neighbour occupancy.
  assert_eq(av1_txb_skip_ctx_chroma(false, false, true), 7)
  assert_eq(av1_txb_skip_ctx_chroma(true, false, true), 8)
  assert_eq(av1_txb_skip_ctx_chroma(true, true, true), 9)
  assert_eq(av1_txb_skip_ctx_chroma(true, true, false), 12)
}

///|
test "dc sign context scores neighbour categories" {
  let above : Array[Int] = [0, 0, 2, 0]
  let left : Array[Int] = [1, 0, 0, 0]
  // +1 from the positive DC above, -1 from the negative DC left: neutral.
  assert_eq(av1_dc_sign_ctx_from(above, left, 0, 0, 4), 0)
  assert_eq(av1_dc_sign_ctx_from([2, 2, 2, 2], [0, 0, 0, 0], 0, 0, 4), 2)
  assert_eq(av1_dc_sign_ctx_from([1, 1, 1, 1], [0, 0, 0, 0], 0, 0, 4), 1)
}
