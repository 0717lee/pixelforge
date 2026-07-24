///|
/// A tiny end-to-end example of the PixelForge library running as a standalone
/// program (works on the native, wasm-gc and js backends). It builds a small
/// gradient image, runs a grayscale + Sobel edge pass, and prints a checksum so
/// the run is verifiable. Run with `moon run cmd/main`.
fn main {
  let width = 64
  let height = 64
  let img = @pixelforge.Image::new(width, height)
  for y in 0..<height {
    for x in 0..<width {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(x * 4),
        @pixelforge.clamp_byte(y * 4),
        @pixelforge.clamp_byte((x + y) * 2),
        @pixelforge.clamp_byte(255),
      )
    }
  }
  let edges = img.grayscale().sobel()
  let blurred = img.blur()
  println("PixelForge \{width}x\{height} demo")
  println("  sobel edge checksum : \{checksum(edges)}")
  println("  gaussian blur checksum : \{checksum(blurred)}")
}

///|
/// Sums all bytes modulo a large prime — a cheap, stable fingerprint of an
/// image, handy for smoke-testing that a filter produced a definite result.
fn checksum(img : @pixelforge.Image) -> Int {
  let mut sum = 0
  for i in 0..<img.data.length() {
    sum = (sum + img.data[i].to_int()) % 1000000007
  }
  sum
}
