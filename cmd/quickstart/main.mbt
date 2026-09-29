///|
fn main {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  image.set_pixel(1, 0, b'\x00', b'\xFF', b'\x00', b'\xFF')
  let pipeline = @pixelforge.Pipeline::new()
    .append(@pixelforge.Filter::Grayscale)
    .append(@pixelforge.Filter::Brightness(10))
  let processed = image.apply_pipeline(pipeline)
  let png = @pixelforge.png_encode(processed)
  let decoded = match @pixelforge.png_decode(png) {
    Some(value) => value
    None => abort("PNG decoding failed")
  }
  if decoded.data != processed.data {
    abort("PNG round-trip changed pixels")
  }
  println("\{decoded.width}x\{decoded.height} PNG round-trip OK")
}
