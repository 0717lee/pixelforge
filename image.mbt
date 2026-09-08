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

// Keep this limit in sync with the codec decoders.  Besides bounding memory
// use, checking the product before multiplying prevents hostile dimensions
// from wrapping an `Int` and reaching `FixedArray::make`.

///|
const MAX_IMAGE_PIXELS : Int = 100000000

///|
/// Computes the RGBA buffer length after validating image dimensions.
///
/// Image dimensions are non-negative and may contain at most
/// `MAX_IMAGE_PIXELS` pixels.  Empty images (where either dimension is zero)
/// are valid and use an empty backing buffer.  The checks are deliberately
/// performed before either multiplication so this helper is safe for
/// untrusted decoder input.
fn checked_buffer_len(width : Int, height : Int) -> Int {
  if width < 0 || height < 0 {
    abort("Image: width and height must be non-negative")
  }
  if width == 0 || height == 0 {
    return 0
  }
  if width > MAX_IMAGE_PIXELS / height {
    abort("Image: dimensions exceed the maximum pixel count")
  }
  let pixels = width * height
  // MAX_IMAGE_PIXELS is chosen so that this multiplication is safe on all
  // supported MoonBit Int targets (including 32-bit targets).
  pixels * 4
}

///|
/// Creates a fully transparent black image of the given size.
pub fn Image::new(width : Int, height : Int) -> Image {
  let len = checked_buffer_len(width, height)
  { width, height, data: FixedArray::make(len, b'\x00'), }
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
  let len = checked_buffer_len(width, height)
  if data.length() != len {
    abort("Image::from_bytes: buffer length must equal width * height * 4")
  }
  { width, height, data, }
}

///|
/// The number of pixels (not bytes) in the image.
pub fn Image::pixel_count(self : Image) -> Int {
  // Validate dimensions even when this method is called on a struct assembled
  // by a low-level host.  This keeps malformed public records from silently
  // propagating an overflowing pixel count.
  checked_buffer_len(self.width, self.height) / 4
}

///|
/// Returns a deep copy that shares no mutable state with the original.
pub fn Image::copy(self : Image) -> Image {
  { width: self.width, height: self.height, data: self.data.copy(), }
}

///|
/// Reads the (R, G, B, A) channels of the pixel at (`x`, `y`).
///
/// Aborts when the coordinates are outside the image bounds or when a host
/// supplies an `Image` record whose backing buffer does not match its size.
pub fn Image::get_pixel(
  self : Image,
  x : Int,
  y : Int,
) -> (Byte, Byte, Byte, Byte) {
  let i = self.pixel_offset(x, y)
  (self.data[i], self.data[i + 1], self.data[i + 2], self.data[i + 3])
}

///|
/// Writes the (R, G, B, A) channels of the pixel at (`x`, `y`).
///
/// Aborts when the coordinates are outside the image bounds or when a host
/// supplies an `Image` record whose backing buffer does not match its size.
pub fn Image::set_pixel(
  self : Image,
  x : Int,
  y : Int,
  r : Byte,
  g : Byte,
  b : Byte,
  a : Byte,
) -> Unit {
  let i = self.pixel_offset(x, y)
  self.data[i] = r
  self.data[i + 1] = g
  self.data[i + 2] = b
  self.data[i + 3] = a
}

///|
/// Returns the byte offset for one pixel after checking the image invariant
/// and coordinate bounds.  Keeping this in one place makes all public pixel
/// accessors fail with a deterministic message instead of a raw array panic.
fn Image::pixel_offset(self : Image, x : Int, y : Int) -> Int {
  let len = checked_buffer_len(self.width, self.height)
  if self.data.length() != len {
    abort("Image: backing buffer length does not match dimensions")
  }
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    abort("Image: pixel coordinates are out of bounds")
  }
  (y * self.width + x) * 4
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
