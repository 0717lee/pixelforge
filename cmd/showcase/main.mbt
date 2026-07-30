///|
/// PixelForge showcase: builds one image that exercises a wide slice of the
/// public API — a gradient background, a translucent blended panel, drawing
/// primitives (rectangles, circles, lines), bitmap text, and a final
/// auto-contrast pass — then verifies it survives a PNG encode/decode round
/// trip before printing it as ASCII PPM.
///
///   moon run cmd/showcase > showcase.ppm
fn main {
  let w = 160
  let h = 100
  let img = @pixelforge.Image::new(w, h)

  // 1) Diagonal gradient background.
  for y in 0..<h {
    for x in 0..<w {
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(40 + x * 120 / w),
        @pixelforge.clamp_byte(30 + y * 150 / h),
        @pixelforge.clamp_byte(90 + (x + y) * 80 / (w + h)),
        @pixelforge.clamp_byte(255),
      )
    }
  }

  // 2) A translucent panel blended over the gradient (multiply).
  let panel = @pixelforge.Image::new(w, h)
  panel.fill_rect(20, 20, 120, 60, b'\xFF', b'\xE0', b'\x80', b'\x80')
  let composed = img.composite(panel, @pixelforge.BlendMode::Multiply)

  // 3) Drawing primitives on top of the composed image.
  composed.draw_rect(20, 20, 120, 60, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
  composed.fill_circle(48, 50, 16, b'\xF4', b'\x72', b'\xB6', b'\xFF')
  composed.draw_circle(96, 50, 20, b'\x34', b'\xD3', b'\x99', b'\xFF')
  composed.draw_line(20, 82, 140, 82, b'\xFF', b'\xFF', b'\xFF', b'\xFF')

  // 4) Bitmap title text.
  composed.draw_text(
    28, 26, "PIXELFORGE", 2, b'\x11', b'\x11', b'\x11', b'\xFF',
  )
  composed.draw_text(
    28, 66, "MOONBIT 1.0", 1, b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  )

  // 5) A final tonal pass.
  let final_img = composed.auto_contrast()

  // End-to-end codec smoke test: the produced image must survive a PNG
  // encode/decode round trip byte for byte.
  let png = @pixelforge.png_encode(final_img)
  let ok = match @pixelforge.png_decode(png) {
    Some(back) => images_equal(final_img, back)
    None => false
  }
  if !ok {
    println("# WARNING: PNG round trip failed")
  } else {
    println("# PNG round trip: OK (\{png.length()} bytes)")
  }
  print_ppm(final_img)
}

///|
/// Exact pixel-for-pixel equality over two same-size images.
fn images_equal(a : @pixelforge.Image, b : @pixelforge.Image) -> Bool {
  if a.width != b.width || a.height != b.height {
    return false
  }
  for i in 0..<(a.width * a.height * 4) {
    if a.data[i].to_int() != b.data[i].to_int() {
      return false
    }
  }
  true
}

///|
/// Writes an image as ASCII PPM (P3): header lines then one "r g b" triple
/// per pixel in row-major order. The leading '#' lines above are PPM
/// comments, so the output is still a valid PPM file.
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
