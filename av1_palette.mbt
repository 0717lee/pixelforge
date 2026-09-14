/// Tile-owned palette CDFs and direct-MI neighbor colors. Each recorded color
/// array is immutable after publication; a new block replaces the current
/// arrays. U is the shared chroma cache base; V has no neighbor cache.

///|
priv struct Av1PaletteState {
  cols : Int
  rows : Int
  y_mode : Array[Array[Array[Int]]]
  uv_mode : Array[Array[Int]]
  y_size : Array[Array[Int]]
  uv_size : Array[Array[Int]]
  y_index : Array[Array[Array[Int]]]
  uv_index : Array[Array[Array[Int]]]
  y_neighbors : Array[Array[Int]]
  u_neighbors : Array[Array[Int]]
  mut y_colors : Array[Int]
  mut u_colors : Array[Int]
  mut v_colors : Array[Int]
}

///|
/// cols/rows are the tile's already validated, padded MI dimensions. Index
/// CDFs use [palette size - 2][context 0..4], each with size+1 entries.
fn av1_palette_state(cols : Int, rows : Int) -> Av1PaletteState {
  {
    cols,
    rows,
    y_mode: av1_palette_y_mode_cdfs(),
    uv_mode: av1_palette_uv_mode_cdfs(),
    y_size: av1_palette_y_size_cdfs(),
    uv_size: av1_palette_uv_size_cdfs(),
    y_index: av1_palette_y_index_cdfs(),
    uv_index: av1_palette_uv_index_cdfs(),
    y_neighbors: Array::makei(cols * rows, _ => []),
    u_neighbors: Array::makei(cols * rows, _ => []),
    y_colors: [],
    u_colors: [],
    v_colors: [],
  }
}

///|
/// Entropy-coded literal, distinct from the MSAC raw-input refill helper.
/// Callers supply a syntax-defined count in 0..12.
fn av1_palette_literal(decoder : Av1SymbolDecoder, count : Int) -> Int {
  let mut value = 0
  for _ in 0..<count {
    value = (value << 1) | decoder.bool()
  }
  value
}

///|
/// AV1 ns(n) over equiprobable entropy bits. The palette's first index is
/// direct, does not use the color-order permutation, and adapts no CDF.
fn av1_palette_ns(decoder : Av1SymbolDecoder, n : Int) -> Int? {
  if n < 1 || n > 8 {
    return None
  }
  let bits = av1_msac_floor_log2(n) + 1
  let cutoff = (1 << bits) - n
  let value = av1_palette_literal(decoder, bits - 1)
  let result = if value < cutoff {
    value
  } else {
    2 * value - cutoff + decoder.bool()
  }
  if decoder.symbol_max_bits < -14 {
    None
  } else {
    Some(result)
  }
}

///|
fn av1_palette_mode_context(state : Av1PaletteState, block : Av1SbBlock) -> Int {
  let row = block.row / 4
  let col = block.col / 4
  let above = row > 0 &&
    state.y_neighbors[(row - 1) * state.cols + col].length() > 0
  let left = col > 0 &&
    state.y_neighbors[row * state.cols + col - 1].length() > 0
  (if above { 1 } else { 0 }) + (if left { 1 } else { 0 })
}

///|
/// Merge sorted lists without removing duplicates: equal U base colors may
/// correspond to different V values. Only the neighbor-cache union deduplicates.
fn av1_palette_merge_colors(
  first : Array[Int],
  second : Array[Int],
) -> Array[Int] {
  let result : Array[Int] = []
  let mut i = 0
  let mut j = 0
  while i < first.length() || j < second.length() {
    if i < first.length() && (j == second.length() || first[i] <= second[j]) {
      result.push(first[i])
      i = i + 1
    } else {
      result.push(second[j])
      j = j + 1
    }
  }
  result
}

///|
/// plane is 0 for Y or 1 for U. Direct above/left MI points are used for both.
/// Every 64-luma-pixel row suppresses the above COLOR CACHE, including halfway
/// through a 128 SB. It does not suppress av1_palette_mode_context's above flag.
/// Tile origins are SB-aligned, so the tile-local row preserves this boundary.
fn av1_palette_cache(
  state : Av1PaletteState,
  block : Av1SbBlock,
  plane : Int,
) -> Array[Int] {
  let row = block.row / 4
  let col = block.col / 4
  let neighbors = if plane == 0 { state.y_neighbors } else { state.u_neighbors }
  let above = if row > 0 && block.row % 64 != 0 {
    neighbors[(row - 1) * state.cols + col]
  } else {
    []
  }
  let left = if col > 0 { neighbors[row * state.cols + col - 1] } else { [] }
  let cache : Array[Int] = []
  for color in av1_palette_merge_colors(above, left) {
    if cache.length() == 0 || cache[cache.length() - 1] != color {
      cache.push(color)
    }
  }
  cache
}

///|
/// Read Y or U: cached selections precede an independently coded sorted new
/// list. Y deltas are positive; U deltas may be zero. Clamp before shrinking
/// the next delta's bit count, exactly as decodemv.c read_palette_colors_y/uv.
fn av1_palette_read_base_colors(
  decoder : Av1SymbolDecoder,
  cache : Array[Int],
  size : Int,
  bit_depth : Int,
  is_y : Bool,
) -> Array[Int] {
  let cached : Array[Int] = []
  for color in cache {
    if cached.length() == size {
      break
    }
    if decoder.bool() != 0 {
      cached.push(color)
    }
  }
  if cached.length() == size {
    return cached
  }
  let fresh = [av1_palette_literal(decoder, bit_depth)]
  let new_count = size - cached.length()
  if new_count > 1 {
    let mut bits = bit_depth - 3 + av1_palette_literal(decoder, 2)
    let maximum = (1 << bit_depth) - 1
    while fresh.length() < new_count {
      let delta = av1_palette_literal(decoder, bits) +
        (if is_y { 1 } else { 0 })
      let value = fresh[fresh.length() - 1] + delta
      let color = if value > maximum { maximum } else { value }
      fresh.push(color)
      let range = (1 << bit_depth) - color - (if is_y { 1 } else { 0 })
      let remaining_bits = if range <= 1 {
        0
      } else {
        av1_msac_floor_log2(range - 1) + 1
      }
      if remaining_bits < bits {
        bits = remaining_bits
      }
    }
  }
  av1_palette_merge_colors(cached, fresh)
}

///|
/// V follows the final U order. Its signed deltas wrap at native bit depth;
/// they do not clip, shrink their bit count, or reorder the U/V pairs.
fn av1_palette_read_v_colors(
  decoder : Av1SymbolDecoder,
  size : Int,
  bit_depth : Int,
) -> Array[Int] {
  let colors : Array[Int] = []
  if decoder.bool() == 0 {
    for _ in 0..<size {
      colors.push(av1_palette_literal(decoder, bit_depth))
    }
  } else {
    let bits = bit_depth - 4 + av1_palette_literal(decoder, 2)
    let modulus = 1 << bit_depth
    colors.push(av1_palette_literal(decoder, bit_depth))
    for _ in 1..<size {
      let magnitude = av1_palette_literal(decoder, bits)
      let delta = if magnitude != 0 && decoder.bool() != 0 {
        0 - magnitude
      } else {
        magnitude
      }
      let value = colors[colors.length() - 1] + delta
      colors.push(
        if value < 0 {
          value + modulus
        } else if value >= modulus {
          value - modulus
        } else {
          value
        },
      )
    }
  }
  colors
}

///|
/// Publish fresh immutable Y/U color arrays at every covered MI point, also
/// clearing the cache entries of non-palette and non-chroma-owning blocks.
fn av1_palette_record(state : Av1PaletteState, block : Av1SbBlock) -> Unit {
  let row_end = if block.row / 4 + block.height / 4 < state.rows {
    block.row / 4 + block.height / 4
  } else {
    state.rows
  }
  let col_end = if block.col / 4 + block.width / 4 < state.cols {
    block.col / 4 + block.width / 4
  } else {
    state.cols
  }
  for row in (block.row / 4)..<row_end {
    for col in (block.col / 4)..<col_end {
      state.y_neighbors[row * state.cols + col] = state.y_colors
      state.u_neighbors[row * state.cols + col] = state.u_colors
    }
  }
}

///|
/// Read only palette mode/size/colors. The caller subsequently reads FI,
/// then index maps, then tx_depth and coefficients, even for skip_txfm blocks.
/// Raw Y/UV modes stay DC when their palettes are enabled.
fn av1_palette_read_colors(
  decoder : Av1SymbolDecoder,
  state : Av1PaletteState,
  block : Av1SbBlock,
  bit_depth : Int,
  y_mode : Int,
  uv_mode : Int,
  has_chroma : Bool,
  allow_screen_content_tools : Bool,
) -> Bool {
  if !av1_tx_block_geometry_valid(block.width, block.height) ||
    block.row < 0 ||
    block.col < 0 ||
    block.row % 4 != 0 ||
    block.col % 4 != 0 ||
    block.row / 4 >= state.rows ||
    block.col / 4 >= state.cols ||
    (bit_depth != 8 && bit_depth != 10 && bit_depth != 12) ||
    y_mode < 0 ||
    y_mode > 12 ||
    uv_mode < 0 ||
    uv_mode > 13 {
    return false
  }
  state.y_colors = []
  state.u_colors = []
  state.v_colors = []
  if allow_screen_content_tools &&
    block.width <= 64 &&
    block.height <= 64 &&
    block.width * block.height >= 64 {
    let context = av1_msac_floor_log2(block.width) +
      av1_msac_floor_log2(block.height) -
      6
    if y_mode == 0 &&
      decoder.symbol(
        state.y_mode[context][av1_palette_mode_context(state, block)],
      ) !=
      0 {
      let size = decoder.symbol(state.y_size[context]) + 2
      state.y_colors = av1_palette_read_base_colors(
        decoder,
        av1_palette_cache(state, block, 0),
        size,
        bit_depth,
        true,
      )
    }
    if has_chroma &&
      uv_mode == 0 &&
      decoder.symbol(
        state.uv_mode[if state.y_colors.length() > 0 { 1 } else { 0 }],
      ) !=
      0 {
      let size = decoder.symbol(state.uv_size[context]) + 2
      state.u_colors = av1_palette_read_base_colors(
        decoder,
        av1_palette_cache(state, block, 1),
        size,
        bit_depth,
        false,
      )
      state.v_colors = av1_palette_read_v_colors(decoder, size, bit_depth)
    }
  }
  if decoder.symbol_max_bits < -14 {
    return false
  }
  av1_palette_record(state, block)
  true
}

// BEGIN GENERATED PALETTE CDFS
// Generated by scripts/generate-av1-palette-tables.py.
// Original AOM 8e7b6a567df174d795479b92b4ac766d271add73, av1/common/entropymode.c:642-783.
// Forward cumulative thresholds include terminal 32768 and update count 0.

///|
fn av1_palette_y_mode_cdfs() -> Array[Array[Array[Int]]] {
  [
    [[31676, 32768, 0], [3419, 32768, 0], [1261, 32768, 0]],
    [[31912, 32768, 0], [2859, 32768, 0], [980, 32768, 0]],
    [[31823, 32768, 0], [3400, 32768, 0], [781, 32768, 0]],
    [[32030, 32768, 0], [3561, 32768, 0], [904, 32768, 0]],
    [[32309, 32768, 0], [7337, 32768, 0], [1462, 32768, 0]],
    [[32265, 32768, 0], [4015, 32768, 0], [1521, 32768, 0]],
    [[32450, 32768, 0], [7946, 32768, 0], [129, 32768, 0]],
  ]
}

///|
fn av1_palette_uv_mode_cdfs() -> Array[Array[Int]] {
  [[32461, 32768, 0], [21488, 32768, 0]]
}

///|
fn av1_palette_y_size_cdfs() -> Array[Array[Int]] {
  [
    [7952, 13000, 18149, 21478, 25527, 29241, 32768, 0],
    [7139, 11421, 16195, 19544, 23666, 28073, 32768, 0],
    [7788, 12741, 17325, 20500, 24315, 28530, 32768, 0],
    [8271, 14064, 18246, 21564, 25071, 28533, 32768, 0],
    [12725, 19180, 21863, 24839, 27535, 30120, 32768, 0],
    [9711, 14888, 16923, 21052, 25661, 27875, 32768, 0],
    [14940, 20797, 21678, 24186, 27033, 28999, 32768, 0],
  ]
}

///|
fn av1_palette_uv_size_cdfs() -> Array[Array[Int]] {
  [
    [8713, 19979, 27128, 29609, 31331, 32272, 32768, 0],
    [5839, 15573, 23581, 26947, 29848, 31700, 32768, 0],
    [4426, 11260, 17999, 21483, 25863, 29430, 32768, 0],
    [3228, 9464, 14993, 18089, 22523, 27420, 32768, 0],
    [3768, 8886, 13091, 17852, 22495, 27207, 32768, 0],
    [2464, 8451, 12861, 21632, 25525, 28555, 32768, 0],
    [1269, 5435, 10433, 18963, 21700, 25865, 32768, 0],
  ]
}

///|
fn av1_palette_y_index_cdfs() -> Array[Array[Array[Int]]] {
  [
    [
      [28710, 32768, 0],
      [16384, 32768, 0],
      [10553, 32768, 0],
      [27036, 32768, 0],
      [31603, 32768, 0],
    ],
    [
      [27877, 30490, 32768, 0],
      [11532, 25697, 32768, 0],
      [6544, 30234, 32768, 0],
      [23018, 28072, 32768, 0],
      [31915, 32385, 32768, 0],
    ],
    [
      [25572, 28046, 30045, 32768, 0],
      [9478, 21590, 27256, 32768, 0],
      [7248, 26837, 29824, 32768, 0],
      [19167, 24486, 28349, 32768, 0],
      [31400, 31825, 32250, 32768, 0],
    ],
    [
      [24779, 26955, 28576, 30282, 32768, 0],
      [8669, 20364, 24073, 28093, 32768, 0],
      [4255, 27565, 29377, 31067, 32768, 0],
      [19864, 23674, 26716, 29530, 32768, 0],
      [31646, 31893, 32147, 32426, 32768, 0],
    ],
    [
      [23132, 25407, 26970, 28435, 30073, 32768, 0],
      [7443, 17242, 20717, 24762, 27982, 32768, 0],
      [6300, 24862, 26944, 28784, 30671, 32768, 0],
      [18916, 22895, 25267, 27435, 29652, 32768, 0],
      [31270, 31550, 31808, 32059, 32353, 32768, 0],
    ],
    [
      [23105, 25199, 26464, 27684, 28931, 30318, 32768, 0],
      [6950, 15447, 18952, 22681, 25567, 28563, 32768, 0],
      [7560, 23474, 25490, 27203, 28921, 30708, 32768, 0],
      [18544, 22373, 24457, 26195, 28119, 30045, 32768, 0],
      [31198, 31451, 31670, 31882, 32123, 32391, 32768, 0],
    ],
    [
      [21689, 23883, 25163, 26352, 27506, 28827, 30195, 32768, 0],
      [6892, 15385, 17840, 21606, 24287, 26753, 29204, 32768, 0],
      [5651, 23182, 25042, 26518, 27982, 29392, 30900, 32768, 0],
      [19349, 22578, 24418, 25994, 27524, 29031, 30448, 32768, 0],
      [31028, 31270, 31504, 31705, 31927, 32153, 32392, 32768, 0],
    ],
  ]
}

///|
fn av1_palette_uv_index_cdfs() -> Array[Array[Array[Int]]] {
  [
    [
      [29089, 32768, 0],
      [16384, 32768, 0],
      [8713, 32768, 0],
      [29257, 32768, 0],
      [31610, 32768, 0],
    ],
    [
      [25257, 29145, 32768, 0],
      [12287, 27293, 32768, 0],
      [7033, 27960, 32768, 0],
      [20145, 25405, 32768, 0],
      [30608, 31639, 32768, 0],
    ],
    [
      [24210, 27175, 29903, 32768, 0],
      [9888, 22386, 27214, 32768, 0],
      [5901, 26053, 29293, 32768, 0],
      [18318, 22152, 28333, 32768, 0],
      [30459, 31136, 31926, 32768, 0],
    ],
    [
      [22980, 25479, 27781, 29986, 32768, 0],
      [8413, 21408, 24859, 28874, 32768, 0],
      [2257, 29449, 30594, 31598, 32768, 0],
      [19189, 21202, 25915, 28620, 32768, 0],
      [31844, 32044, 32281, 32518, 32768, 0],
    ],
    [
      [22217, 24567, 26637, 28683, 30548, 32768, 0],
      [7307, 16406, 19636, 24632, 28424, 32768, 0],
      [4441, 25064, 26879, 28942, 30919, 32768, 0],
      [17210, 20528, 23319, 26750, 29582, 32768, 0],
      [30674, 30953, 31396, 31735, 32207, 32768, 0],
    ],
    [
      [21239, 23168, 25044, 26962, 28705, 30506, 32768, 0],
      [6545, 15012, 18004, 21817, 25503, 28701, 32768, 0],
      [3448, 26295, 27437, 28704, 30126, 31442, 32768, 0],
      [15889, 18323, 21704, 24698, 26976, 29690, 32768, 0],
      [30988, 31204, 31479, 31734, 31983, 32325, 32768, 0],
    ],
    [
      [21442, 23288, 24758, 26246, 27649, 28980, 30563, 32768, 0],
      [5863, 14933, 17552, 20668, 23683, 26411, 29273, 32768, 0],
      [3415, 25810, 26877, 27990, 29223, 30394, 31618, 32768, 0],
      [17965, 20084, 22232, 23974, 26274, 28402, 30390, 32768, 0],
      [31190, 31329, 31516, 31679, 31825, 32026, 32322, 32768, 0],
    ],
  ]
}
// END GENERATED PALETTE CDFS
