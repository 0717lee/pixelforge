///|
/// PixelForge showcase: builds one image that exercises a wide slice of the
/// public API — a box-blurred gradient background, a translucent blended
/// panel, drawing primitives (rectangles, circles, lines), bitmap text, and a
/// final auto-contrast pass — then verifies it survives a PNG encode/decode
/// round trip (aborting on mismatch) before printing it as ASCII PPM.
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

  // 2) Soften the background with a classic filter pass, then blend a
  //    translucent panel over it (multiply).
  let background = img.box_blur(1)
  let panel = @pixelforge.Image::new(w, h)
  panel.fill_rect(20, 20, 120, 60, b'\xFF', b'\xE0', b'\x80', b'\x80')
  let composed = background.composite(panel, @pixelforge.BlendMode::Multiply)

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
    abort("showcase: PNG round trip failed")
  }
  // Analysis self-check on a controlled flat tile: salt-and-pepper noise
  // then a median filter, which on a uniform field provably restores almost
  // every pixel. Confirms the noise + median + phash APIs compose; the
  // perceptual-hash distances (clean vs noisy vs denoised) are reported as a
  // diagnostic. (The median is deliberately not run on the detailed showcase
  // image itself, where it would also reshape genuine edges.)
  let tile = @pixelforge.Image::new(32, 32)
  tile.fill_rect(0, 0, 32, 32, b'\x80', b'\x80', b'\x80', b'\xFF')
  let clean_hash = tile.average_hash()
  let noisy = tile.add_salt_pepper(2026UL, 0.08)
  let denoised = noisy.median()
  let noisy_diff = pixel_diff(tile, noisy)
  let denoised_diff = pixel_diff(tile, denoised)
  if denoised_diff >= noisy_diff {
    abort("showcase: median denoise did not reduce the pixel difference")
  }
  let noisy_dist = @pixelforge.hamming_distance(
    clean_hash,
    noisy.average_hash(),
  )
  let denoised_dist = @pixelforge.hamming_distance(
    clean_hash,
    denoised.average_hash(),
  )
  // Emit the status as PPM comments *after* the magic number, so stdout
  // stays a strictly valid PPM stream.
  print_ppm(
    final_img,
    "# PNG round trip: OK (\{png.length()} bytes); denoise diff \{noisy_diff}->\{denoised_diff}; phash noisy=\{noisy_dist} denoised=\{denoised_dist}",
  )
}

///|
/// Counts channels that differ between two same-size images (a coarse
/// distance used only for the showcase self-check).
fn pixel_diff(a : @pixelforge.Image, b : @pixelforge.Image) -> Int {
  let mut diff = 0
  for i in 0..<(a.width * a.height * 4) {
    if a.data[i].to_int() != b.data[i].to_int() {
      diff = diff + 1
    }
  }
  diff
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
/// Writes an image as ASCII PPM (P3): the magic number, an optional comment
/// line (valid only *after* the magic), the dimensions and maxval, then one
/// "r g b" triple per pixel in row-major order.
fn print_ppm(img : @pixelforge.Image, comment : String) -> Unit {
  println("P3")
  println(comment)
  println("\{img.width} \{img.height}")
  println("255")
  for y in 0..<img.height {
    for x in 0..<img.width {
      let (r, g, b, _) = img.get_pixel(x, y)
      println("\{r.to_int()} \{g.to_int()} \{b.to_int()}")
    }
  }
}
