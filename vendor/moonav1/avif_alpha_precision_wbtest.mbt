///|
fn avif_alpha_precision_frame(
  depth : Int,
  full_range : Bool,
  matrix : Int,
  planes : Array[Array[Int]],
  primaries? : Int = 1,
  transfer? : Int = 13,
) -> Av1FramePlanes {
  {
    width: planes[0].length(),
    height: 1,
    coded_width: planes[0].length(),
    bit_depth: depth,
    full_range,
    matrix_coefficients: matrix,
    color_primaries: primaries,
    transfer_characteristics: transfer,
    sub_x: 0,
    sub_y: 0,
    planes,
  }
}

///|
test "XYZ source alpha is undone before existing XYZ to sRGB conversion" {
  // Independent Fraction solve of BT.709 xy/D65, as in the existing
  // generate-av1-color-reference.py H.273 oracle; no decoder matrix reused.
  // CP10 derived matrix has Kr=Kb=0: X=Y+2Cr, Z=Y+2Cb. Dividing XYZ by
  // native alpha before the rational solve yields linear RGB for pixel 1:
  // (0.818925973651806, 0.2000699943318237, 0.340444498145664).
  // H.273 sRGB encoding then rounds to (234,124,158); dividing encoded
  // sRGB8 afterwards gives a different result.
  let color = avif_alpha_precision_frame(
    12,
    true,
    12,
    [[0, 700, 1200], [2048, 2070, 2110], [2048, 2180, 2010]],
    primaries=10,
    transfer=8,
  )
  let alpha = avif_alpha_precision_frame(12, true, 2, [[0, 2048, 4095]])
  let actual = av1_frame_with_alpha(color, alpha, true).unwrap()
  assert_eq(actual.get_pixel(0, 0), (0x00, 0x00, 0x00, 0x00))
  assert_eq(actual.get_pixel(1, 0), (0xea, 0x7c, 0x9e, 0x80))
  assert_eq(actual.get_pixel(2, 0), (0x90, 0x94, 0x94, 0xff))
}

///|
test "limited alpha expands and rounds at native depth before RGBA8" {
  // libavif avifLimitedToFullY: 263 -> 8 -> alpha8=0, 264 -> 9 -> 1.
  // Direct limited12-to-alpha8 conversion incorrectly maps 263 to one.
  let alpha = avif_alpha_precision_frame(12, false, 2, [
    [0, 256, 263, 264, 3760, 4095],
  ])
  let native = av1_alpha_full_samples(alpha)
  assert_eq(native, [0, 0, 8, 9, 4095, 4095])
  assert_eq(av1_alpha_samples_to_bytes(native, 12), [
    0x00, 0x00, 0x00, 0x01, 0xff, 0xff,
  ])
}

///|
test "straight alpha composition preserves color while prem clears zero coverage" {
  let color = avif_alpha_precision_frame(8, true, 0, [
    [40, 60],
    [80, 100],
    [20, 30],
  ])
  let alpha = avif_alpha_precision_frame(8, true, 2, [[0, 255]])
  let straight = av1_frame_with_alpha(color, alpha, false).unwrap()
  let prem = av1_frame_with_alpha(color, alpha, true).unwrap()
  assert_eq(straight.get_pixel(0, 0), (0x14, 0x28, 0x50, 0x00))
  assert_eq(prem.get_pixel(0, 0), (0x00, 0x00, 0x00, 0x00))
  assert_eq(prem.get_pixel(1, 0), straight.get_pixel(1, 0))
  assert_eq(color.planes, [[40, 60], [80, 100], [20, 30]])
}
