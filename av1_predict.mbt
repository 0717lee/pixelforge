/// Pixel reconstruction primitives shared by the bounded AV1 stage.

///|
/// Converts an 8-bit planar YUV420 frame to PixelForge RGBA using the limited
/// range BT.601 matrix. The AV1 tile decoder can call this after reconstruction;
/// it performs no codec fallback and rejects malformed plane lengths.
pub fn av1_yuv420_to_rgba(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
) -> Image? {
  av1_yuv420_to_rgba_color(
    width,
    height,
    y,
    u,
    v,
    full_range=false,
    matrix_coefficients=6,
  )
}

///|
/// Converts 8-bit planar YUV420 using the AV1 color range flag.
pub fn av1_yuv420_to_rgba_range(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
) -> Image? {
  av1_yuv420_to_rgba_color(
    width,
    height,
    y,
    u,
    v,
    full_range~,
    matrix_coefficients=6,
  )
}

///|
/// Converts 8-bit planar YUV420 using color range and AV1 matrix coefficients.
/// This byte-plane adapter shares the native-depth CICP conversion and its
/// source-RGB convention; see `av1_yuv_highbd_to_rgba` for matrix metadata.
pub fn av1_yuv420_to_rgba_color(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
) -> Image? {
  av1_yuv_highbd_to_rgba(
    width,
    height,
    y.map(fn(value) { value.to_int() }),
    u.map(fn(value) { value.to_int() }),
    v.map(fn(value) { value.to_int() }),
    8,
    full_range~,
    matrix_coefficients~,
    color_primaries~,
    transfer_characteristics~,
  )
}
