///| Zero-copy tile and row traversal tests.

test "for_each_tile clips edges and writes through the source" {
  let image = @pixelforge.Image::new(5, 3)
  let mut count = 0
  let mut edge_width = 0
  let mut edge_height = 0
  image.for_each_tile(2, 2, fn(tile) {
    count = count + 1
    tile.set_pixel(0, 0, b'\x11', b'\x22', b'\x33', b'\xFF')
    if tile.x() == 4 {
      edge_width = tile.width()
    }
    if tile.y() == 2 {
      edge_height = tile.height()
    }
  })
  assert_eq(count, 6)
  assert_eq(edge_width, 1)
  assert_eq(edge_height, 1)
  let (r, g, b, a) = image.get_pixel(4, 2)
  assert_eq(r.to_int(), 17)
  assert_eq(g.to_int(), 34)
  assert_eq(b.to_int(), 51)
  assert_eq(a.to_int(), 255)
}

test "tile copy is independent while row traversal sees source" {
  let image = @pixelforge.Image::new(3, 2)
  image.set_pixel(1, 1, b'\xAA', b'\xBB', b'\xCC', b'\xDD')
  let mut copied = @pixelforge.Image::new(0, 0)
  image.for_each_tile(3, 2, fn(tile) { copied = tile.copy() })
  image.set_pixel(1, 1, b'\x01', b'\x02', b'\x03', b'\x04')
  let (r, g, b, a) = copied.get_pixel(1, 1)
  assert_eq(r.to_int(), 170)
  assert_eq(g.to_int(), 187)
  assert_eq(b.to_int(), 204)
  assert_eq(a.to_int(), 221)
  let mut rows = 0
  let mut row_width = 0
  image.for_each_row(fn(row) {
    rows = rows + 1
    row_width = row.width()
  })
  assert_eq(rows, 2)
  assert_eq(row_width, 3)
}

test "empty images produce no tiles or rows" {
  let image = @pixelforge.Image::new(0, 4)
  let mut tiles = 0
  let mut rows = 0
  image.for_each_tile(2, 2, fn(_) { tiles = tiles + 1 })
  image.for_each_row(fn(_) { rows = rows + 1 })
  assert_eq(tiles, 0)
  assert_eq(rows, 4)
}
