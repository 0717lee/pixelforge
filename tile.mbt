///|
/// Zero-copy traversal helpers for bounded image processing.
///
/// `Image::for_each_tile` visits rectangular views over the source image. A
/// view only stores its origin and dimensions; it does not copy pixel bytes.
/// Call `ImageTile::copy` when an owned image is required. This makes the
/// traversal suitable for streaming decoders and bounded-memory processing.

/// A read/write view over one rectangular tile of an image.
pub(all) struct ImageTile {
  image : Image
  origin_x : Int
  origin_y : Int
  tile_width : Int
  tile_height : Int
}

/// Horizontal origin of this tile in the source image.
pub fn ImageTile::x(self : ImageTile) -> Int {
  self.origin_x
}

/// Vertical origin of this tile in the source image.
pub fn ImageTile::y(self : ImageTile) -> Int {
  self.origin_y
}

/// Width of this tile in pixels.
pub fn ImageTile::width(self : ImageTile) -> Int {
  self.tile_width
}

/// Height of this tile in pixels.
pub fn ImageTile::height(self : ImageTile) -> Int {
  self.tile_height
}

/// Reads a pixel relative to the tile origin.
pub fn ImageTile::get_pixel(
  self : ImageTile,
  x : Int,
  y : Int,
) -> (Byte, Byte, Byte, Byte) {
  if x < 0 || x >= self.tile_width || y < 0 || y >= self.tile_height {
    abort("ImageTile: pixel coordinates are out of bounds")
  }
  self.image.get_pixel(self.origin_x + x, self.origin_y + y)
}

/// Writes a pixel relative to the tile origin without copying the tile.
pub fn ImageTile::set_pixel(
  self : ImageTile,
  x : Int,
  y : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  if x < 0 || x >= self.tile_width || y < 0 || y >= self.tile_height {
    abort("ImageTile: pixel coordinates are out of bounds")
  }
  self.image.set_pixel(self.origin_x + x, self.origin_y + y, r, g, b, a)
}

/// Copies the tile into an independently-owned image.
pub fn ImageTile::copy(self : ImageTile) -> Image {
  let out = Image::new(self.tile_width, self.tile_height)
  for y in 0..<self.tile_height {
    for x in 0..<self.tile_width {
      let src = ( (self.origin_y + y) * self.image.width + self.origin_x + x) * 4
      let dst = (y * self.tile_width + x) * 4
      out.data[dst] = self.image.data[src]
      out.data[dst + 1] = self.image.data[src + 1]
      out.data[dst + 2] = self.image.data[src + 2]
      out.data[dst + 3] = self.image.data[src + 3]
    }
  }
  out
}

/// Visits all tiles in row-major order using a zero-copy view.
///
/// The final row or column is clipped when the image dimensions are not
/// multiples of the requested tile size. `tile_width` and `tile_height` must
/// both be positive. The callback may mutate pixels through the view; changes
/// are applied directly to the source image.
pub fn Image::for_each_tile(
  self : Image,
  tile_width : Int,
  tile_height : Int,
  visit : (ImageTile) -> Unit,
) -> Unit {
  if tile_width <= 0 || tile_height <= 0 {
    abort("Image::for_each_tile: tile dimensions must be positive")
  }
  for origin_y = 0; origin_y < self.height; origin_y = origin_y + tile_height {
    let h = if origin_y + tile_height > self.height {
      self.height - origin_y
    } else {
      tile_height
    }
    for origin_x = 0; origin_x < self.width; origin_x = origin_x + tile_width {
      let w = if origin_x + tile_width > self.width {
        self.width - origin_x
      } else {
        tile_width
      }
      visit({
        image: self,
        origin_x,
        origin_y,
        tile_width: w,
        tile_height: h,
      })
    }
  }
}

/// A zero-copy view of one image row for streaming scans.
pub(all) struct ImageRow {
  image : Image
  row_y : Int
}

/// Y coordinate of this row in the source image.
pub fn ImageRow::y(self : ImageRow) -> Int {
  self.row_y
}

/// Number of pixels in this row.
pub fn ImageRow::width(self : ImageRow) -> Int {
  self.image.width
}

/// Reads a pixel from this row.
pub fn ImageRow::get_pixel(self : ImageRow, x : Int) -> (Byte, Byte, Byte, Byte) {
  if x < 0 || x >= self.image.width {
    abort("ImageRow: pixel coordinate is out of bounds")
  }
  self.image.get_pixel(x, self.row_y)
}

/// Visits rows in order without allocating row buffers.
pub fn Image::for_each_row(
  self : Image,
  visit : (ImageRow) -> Unit,
) -> Unit {
  for row_y in 0..<self.height {
    visit({ image: self, row_y })
  }
}
