///|
/// Renders a gradient-and-disc test scene, runs Sobel edge detection, and
/// prints the result as a plain-text PPM (P3) image on stdout — a real
/// command-line use of the library with zero file-system dependencies:
///
///   moon run cmd/ppm > edges.ppm
fn main {
  let width = 96
  let height = 64
  let img = @pixelforge.Image::new(width, height)
  for y in 0..<height {
    for x in 0..<width {
      // Background gradient plus a bright disc, so the edge detector has both
      // smooth regions and a crisp round contour to find.
      let mut r = x * 255 / width
      let mut g = y * 255 / height
      let mut b = 160
      let dx = x - 48
      let dy = y - 32
      if dx * dx + dy * dy < 400 {
        r = 240
        g = 220
        b = 60
      }
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(r),
        @pixelforge.clamp_byte(g),
        @pixelforge.clamp_byte(b),
        @pixelforge.clamp_byte(255),
      )
    }
  }
  print_ppm(img.sobel())
}

///|
/// Writes an image as ASCII PPM (P3): the three header lines, then one
/// "r g b" triple per pixel in row-major order.
fn print_ppm(img : @pixelforge.Image) -> Unit {
  println("P3")
  println("\{img.width} \{img.height}")
  println("255")
  for y in 0..<img.height {
    for x in 0..<img.width {
      let (r, g, b, _) = img.get_pixel(x, y)
      println("\{r.to_int()} \{g.to_int()} \{b.to_int()}")
    }
  }
}
