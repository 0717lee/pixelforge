///|
/// Deterministic tests for the convolution engine. Small hand-built fixtures
/// let every expected value be derived on paper: impulse responses, flat-field
/// invariance, and a known vertical edge for Sobel.

///|
/// A `w` x `h` image painted a single RGBA color.
fn solid(
  w : Int,
  h : Int,
  r : Int,
  g : Int,
  b : Int,
  a : Int,
) -> @pixelforge.Image {
  let img = @pixelforge.Image::new(w, h)
  let rb = @pixelforge.clamp_byte(r)
  let gb = @pixelforge.clamp_byte(g)
  let bb = @pixelforge.clamp_byte(b)
  let ab = @pixelforge.clamp_byte(a)
  for y in 0..<h {
    for x in 0..<w {
      img.set_pixel(x, y, rb, gb, bb, ab)
    }
  }
  img
}

///|
/// A `w` x `h` opaque grayscale image whose luma values are given row-major.
fn gray_image(w : Int, h : Int, values : Array[Int]) -> @pixelforge.Image {
  let img = @pixelforge.Image::new(w, h)
  let full_alpha = @pixelforge.clamp_byte(255)
  for y in 0..<h {
    for x in 0..<w {
      let v = @pixelforge.clamp_byte(values[y * w + x])
      img.set_pixel(x, y, v, v, v, full_alpha)
    }
  }
  img
}

///|
test "gaussian blur preserves a flat field" {
  let (r, _, _, a) = solid(3, 3, 100, 100, 100, 255).blur().get_pixel(1, 1)
  assert_eq(r.to_int(), 100)
  assert_eq(a.to_int(), 255)
}

///|
test "box blur averages an impulse over its 3x3 neighborhood" {
  // Only the center carries value 90; box blur spreads it: 90 / 9 = 10.
  let img = gray_image(3, 3, [0, 0, 0, 0, 90, 0, 0, 0, 0])
  let (r, _, _, _) = img
    .convolve(@pixelforge.Kernel::box_blur())
    .get_pixel(1, 1)
  assert_eq(r.to_int(), 10)
}

///|
test "sharpen preserves a flat field" {
  let (r, _, _, _) = solid(3, 3, 120, 120, 120, 255).sharpen().get_pixel(1, 1)
  assert_eq(r.to_int(), 120)
}

///|
test "emboss maps a flat field to its level plus the mid-gray bias" {
  // Weights sum to 1, bias 128: 1 * 100 + 128 = 228.
  let (r, _, _, _) = solid(3, 3, 100, 100, 100, 255).emboss().get_pixel(1, 1)
  assert_eq(r.to_int(), 228)
}

///|
test "laplacian edges vanish on a flat field" {
  let (r, _, _, _) = solid(3, 3, 200, 200, 200, 255).edges().get_pixel(1, 1)
  assert_eq(r.to_int(), 0)
}

///|
test "sobel finds no edge in a flat field" {
  let (r, _, _, _) = solid(3, 3, 200, 200, 200, 255).sobel().get_pixel(1, 1)
  assert_eq(r.to_int(), 0)
}

///|
test "sobel lights up a vertical edge" {
  // Dark left, bright right column: Gx = 1020, Gy = 0 -> clamps to 255.
  let img = gray_image(3, 3, [0, 0, 255, 0, 0, 255, 0, 0, 255])
  let (r, _, _, _) = img.sobel().get_pixel(1, 1)
  assert_eq(r.to_int(), 255)
}

///|
test "convolution preserves dimensions and alpha" {
  let out = solid(4, 2, 50, 60, 70, 128).blur()
  assert_eq(out.width, 4)
  assert_eq(out.height, 2)
  let (_, _, _, a) = out.get_pixel(0, 0)
  assert_eq(a.to_int(), 128)
}
