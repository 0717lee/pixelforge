/// Palette color-index contexts and entropy map traversal. Palette colors,
/// geometry conversion and plane/count CDF selection are owned by the caller.

///|
let av1_palette_index_context_lookup : Array[Int] = [
  -1, -1, 0, -1, -1, 4, 3, 2, 1,
]

///|
/// Return the context and all eight ranks in the normative color order. The
/// first three scores are selected by stable insertion, retaining the order
/// of tied and unselected colors. Outside neighbors contribute no score.
fn av1_palette_index_context(
  indices : Array[Int],
  width : Int,
  row : Int,
  col : Int,
  palette_size : Int,
) -> (Int, Array[Int])? {
  if palette_size < 2 ||
    palette_size > 8 ||
    width <= 0 ||
    indices.length() % width != 0 ||
    row < 0 ||
    col < 0 ||
    col >= width ||
    row >= indices.length() / width ||
    (row == 0 && col == 0) {
    return None
  }
  let scores = Array::make(8, 0)
  if col > 0 {
    let value = indices[row * width + col - 1]
    if value < 0 || value >= palette_size {
      return None
    }
    scores[value] = scores[value] + 2
  }
  if row > 0 && col > 0 {
    let value = indices[(row - 1) * width + col - 1]
    if value < 0 || value >= palette_size {
      return None
    }
    scores[value] = scores[value] + 1
  }
  if row > 0 {
    let value = indices[(row - 1) * width + col]
    if value < 0 || value >= palette_size {
      return None
    }
    scores[value] = scores[value] + 2
  }
  let order = Array::make(8, 0)
  for i in 0..<8 {
    order[i] = i
  }
  for i in 0..<3 {
    let mut maximum = scores[i]
    let mut selected = i
    for j in (i + 1)..<palette_size {
      if scores[j] > maximum {
        maximum = scores[j]
        selected = j
      }
    }
    if selected != i {
      let color = order[selected]
      let mut j = selected
      while j > i {
        scores[j] = scores[j - 1]
        order[j] = order[j - 1]
        j = j - 1
      }
      scores[i] = maximum
      order[i] = color
    }
  }
  let hash = scores[0] + 2 * scores[1] + 2 * scores[2]
  if hash < 0 || hash >= av1_palette_index_context_lookup.length() {
    return None
  }
  let context = av1_palette_index_context_lookup[hash]
  if context < 0 {
    None
  } else {
    Some((context, order))
  }
}

///|
/// Decode a full palette index map. `rows` and `cols` are the decoded MI
/// rectangle, already converted to this plane; width/height retain the full
/// coding-block map. Only that prefix consumes entropy. The five CDF rows
/// belong to the selected plane and palette size and adapt in place, including
/// across calls when the caller keeps the same rows and symbol decoder.
fn av1_palette_decode_index_map(
  decoder : Av1SymbolDecoder,
  palette_size : Int,
  width : Int,
  height : Int,
  rows : Int,
  cols : Int,
  cdfs : Array[Array[Int]],
) -> Array[Int]? {
  if palette_size < 2 ||
    palette_size > 8 ||
    width <= 0 ||
    width > 64 ||
    height <= 0 ||
    height > 64 ||
    rows <= 0 ||
    rows > height ||
    cols <= 0 ||
    cols > width ||
    cdfs.length() != 5 {
    return None
  }
  for cdf in cdfs {
    if cdf.length() != palette_size + 1 ||
      cdf[palette_size - 1] != 32768 ||
      cdf[palette_size] < 0 ||
      cdf[palette_size] > 32 {
      return None
    }
    let mut previous = 0
    for i in 0..<palette_size {
      if cdf[i] < previous || cdf[i] > 32768 {
        return None
      }
      previous = cdf[i]
    }
  }
  let output = Array::make(width * height, 0)
  output[0] = match av1_palette_ns(decoder, palette_size) {
    Some(value) => value
    None => return None
  }
  if output[0] < 0 || output[0] >= palette_size {
    return None
  }
  let mut diagonal = 1
  while diagonal < rows + cols - 1 {
    let mut col = if diagonal < cols { diagonal } else { cols - 1 }
    let last_col = if diagonal - rows + 1 > 0 { diagonal - rows + 1 } else { 0 }
    while col >= last_col {
      let row = diagonal - col
      let (context, order) = match
        av1_palette_index_context(output, width, row, col, palette_size) {
        Some(value) => value
        None => return None
      }
      let rank = decoder.symbol(cdfs[context])
      if rank < 0 || rank >= palette_size {
        return None
      }
      output[row * width + col] = order[rank]
      col = col - 1
    }
    diagonal = diagonal + 1
  }
  // Extend each decoded row before copying that complete last row downward.
  for row in 0..<rows {
    for col in cols..<width {
      output[row * width + col] = output[row * width + cols - 1]
    }
  }
  for row in rows..<height {
    for col in 0..<width {
      output[row * width + col] = output[(rows - 1) * width + col]
    }
  }
  Some(output)
}
