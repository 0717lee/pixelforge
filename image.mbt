///|
/// An 8-bit RGBA raster image.
///
/// Pixels are stored row-major in `data`, four bytes per pixel in R, G, B, A
/// order, so `data.length() == width * height * 4`. This layout matches the
/// browser `ImageData.data` buffer, which lets a `<canvas>` hand its pixels to
/// the library without any conversion step.
pub(all) struct Image {
  width : Int
  height : Int
  data : FixedArray[Byte]
}

///|
/// Creates a fully transparent black image of the given size.
pub fn Image::new(width : Int, height : Int) -> Image {
  { width, height, data: FixedArray::make(width * height * 4, b'\x00') }
}

///|
/// Wraps an existing RGBA buffer. Aborts if `data` does not hold exactly
/// `width * height * 4` bytes, so a malformed buffer fails fast instead of
/// producing silently corrupt output.
pub fn Image::from_bytes(
  width : Int,
  height : Int,
  data : FixedArray[Byte],
) -> Image {
  if data.length() != width * height * 4 {
    abort("Image::from_bytes: buffer length must equal width * height * 4")
  }
  { width, height, data }
}

///|
/// The number of pixels (not bytes) in the image.
pub fn Image::pixel_count(self : Image) -> Int {
  self.width * self.height
}

///|
/// Returns a deep copy that shares no mutable state with the original.
pub fn Image::copy(self : Image) -> Image {
  { width: self.width, height: self.height, data: self.data.copy() }
}

///|
/// Reads the (R, G, B, A) channels of the pixel at (`x`, `y`).
pub fn Image::get_pixel(
  self : Image,
  x : Int,
  y : Int,
) -> (Byte, Byte, Byte, Byte) {
  let i = (y * self.width + x) * 4
  (self.data[i], self.data[i + 1], self.data[i + 2], self.data[i + 3])
}

///|
/// Writes the (R, G, B, A) channels of the pixel at (`x`, `y`).
pub fn Image::set_pixel(
  self : Image,
  x : Int,
  y : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  let i = (y * self.width + x) * 4
  self.data[i] = r
  self.data[i + 1] = g
  self.data[i + 2] = b
  self.data[i + 3] = a
}

///|
/// Clamps an integer into the `[0, 255]` range and narrows it to a `Byte`.
/// Channel math is done in `Int` to avoid wrap-around, then funnelled through
/// this helper before being stored back into a pixel buffer.
pub fn clamp_byte(value : Int) -> Byte {
  if value < 0 {
    b'\x00'
  } else if value > 255 {
    b'\xFF'
  } else {
    value.to_byte()
  }
}
