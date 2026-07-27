///|
/// A square (odd-sized) convolution kernel plus its normalization terms.
///
/// `weights` are stored row-major with `size * size` entries. Each output
/// channel is `(sum(weight_i * neighbor_i) / divisor) + bias`, clamped back
/// into `[0, 255]`. Keeping `divisor` and `bias` on the kernel lets a single
/// `convolve` implementation serve blur, sharpen, emboss and edge kernels.
pub(all) struct Kernel {
  size : Int
  weights : Array[Double]
  divisor : Double
  bias : Double
}

///|
/// Builds a kernel, aborting if the shape is invalid (even/negative size or a
/// weight count that does not match `size * size`).
pub fn Kernel::new(
  size : Int,
  weights : Array[Double],
  divisor : Double,
  bias : Double,
) -> Kernel {
  if size <= 0 || size % 2 == 0 {
    abort("Kernel::new: size must be a positive odd number")
  }
  if weights.length() != size * size {
    abort("Kernel::new: weights length must equal size * size")
  }
  { size, weights, divisor, bias }
}

///|
/// 3x3 box blur: unweighted average of the neighborhood.
pub fn Kernel::box_blur() -> Kernel {
  Kernel::new(3, [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0], 9.0, 0.0)
}

///|
/// 3x3 Gaussian blur approximation with weights summing to 16.
pub fn Kernel::gaussian_blur() -> Kernel {
  Kernel::new(3, [1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0], 16.0, 0.0)
}

///|
/// 3x3 sharpen: boosts the center and subtracts its 4-neighbors.
pub fn Kernel::sharpen() -> Kernel {
  Kernel::new(3, [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0], 1.0, 0.0)
}

///|
/// 3x3 Laplacian edge kernel; flat regions collapse to black.
pub fn Kernel::edges() -> Kernel {
  Kernel::new(
    3,
    [-1.0, -1.0, -1.0, -1.0, 8.0, -1.0, -1.0, -1.0, -1.0],
    1.0,
    0.0,
  )
}

///|
/// 3x3 emboss kernel with a +128 bias so flat areas render as mid-gray relief.
pub fn Kernel::emboss() -> Kernel {
  Kernel::new(3, [-2.0, -1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 2.0], 1.0, 128.0)
}

///|
/// Clamps a coordinate into `[0, limit)` so kernels sample a repeated edge
/// pixel instead of wrapping or reading out of bounds ("clamp-to-edge").
fn clamp_coord(v : Int, limit : Int) -> Int {
  if v < 0 {
    0
  } else if v >= limit {
    limit - 1
  } else {
    v
  }
}

///|
/// Convolves the image with `kernel`, processing R, G and B independently and
/// preserving alpha. Out-of-bounds neighbors are clamped to the edge. This is
/// the compute-heavy core the WebAssembly demo is built to show off.
pub fn Image::convolve(self : Image, kernel : Kernel) -> Image {
  let out = Image::new(self.width, self.height)
  let radius = kernel.size / 2
  for y in 0..<self.height {
    for x in 0..<self.width {
      let mut sum_r = 0.0
      let mut sum_g = 0.0
      let mut sum_b = 0.0
      for ky in 0..<kernel.size {
        for kx in 0..<kernel.size {
          let sx = clamp_coord(x + kx - radius, self.width)
          let sy = clamp_coord(y + ky - radius, self.height)
          let w = kernel.weights[ky * kernel.size + kx]
          let base = (sy * self.width + sx) * 4
          sum_r = sum_r + self.data[base].to_int().to_double() * w
          sum_g = sum_g + self.data[base + 1].to_int().to_double() * w
          sum_b = sum_b + self.data[base + 2].to_int().to_double() * w
        }
      }
      let base = (y * self.width + x) * 4
      out.data[base] = clamp_byte(
        (sum_r / kernel.divisor + kernel.bias).to_int(),
      )
      out.data[base + 1] = clamp_byte(
        (sum_g / kernel.divisor + kernel.bias).to_int(),
      )
      out.data[base + 2] = clamp_byte(
        (sum_b / kernel.divisor + kernel.bias).to_int(),
      )
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// Gaussian blur convenience wrapper.
pub fn Image::blur(self : Image) -> Image {
  self.convolve(Kernel::gaussian_blur())
}

///|
/// Sharpen convenience wrapper.
pub fn Image::sharpen(self : Image) -> Image {
  self.convolve(Kernel::sharpen())
}

///|
/// Emboss convenience wrapper.
pub fn Image::emboss(self : Image) -> Image {
  self.convolve(Kernel::emboss())
}

///|
/// Laplacian edge convenience wrapper.
pub fn Image::edges(self : Image) -> Image {
  self.convolve(Kernel::edges())
}

///|
/// Absolute value for `Int`, kept local so the Sobel gradient stays in pure
/// integer arithmetic without pulling in an extra dependency.
fn iabs(v : Int) -> Int {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
/// Shared gradient-edge engine: reduces the image to luma, measures the
/// horizontal (Gx) and vertical (Gy) gradients with the given 3x3 operators,
/// and writes the L1 magnitude `|Gx| + |Gy|`, which keeps the whole pass in
/// integer math (fast and reproducible). Output is grayscale; alpha preserved.
fn Image::gradient_edges(
  self : Image,
  gx : Array[Int],
  gy : Array[Int],
) -> Image {
  let gray = self.grayscale()
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let mut sx = 0
      let mut sy = 0
      for ky in 0..<3 {
        for kx in 0..<3 {
          let px = clamp_coord(x + kx - 1, self.width)
          let py = clamp_coord(y + ky - 1, self.height)
          let base = (py * self.width + px) * 4
          let lum = gray.data[base].to_int() // grayscale => R == G == B
          let k = ky * 3 + kx
          sx = sx + lum * gx[k]
          sy = sy + lum * gy[k]
        }
      }
      let v = clamp_byte(iabs(sx) + iabs(sy))
      let base = (y * self.width + x) * 4
      out.data[base] = v
      out.data[base + 1] = v
      out.data[base + 2] = v
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// Sobel edge detection with the classic 1/2/1 operators.
pub fn Image::sobel(self : Image) -> Image {
  self.gradient_edges([-1, 0, 1, -2, 0, 2, -1, 0, 1], [
    -1, -2, -1, 0, 0, 0, 1, 2, 1,
  ])
}

///|
/// Scharr edge detection: same structure as Sobel but with 3/10/3 weights,
/// which are closer to rotational symmetry and give stronger, more uniform
/// responses on diagonal edges.
pub fn Image::scharr(self : Image) -> Image {
  self.gradient_edges([-3, 0, 3, -10, 0, 10, -3, 0, 3], [
    -3, -10, -3, 0, 0, 0, 3, 10, 3,
  ])
}
