/// White-box checks for the stateful square coefficient path.

///|
test "square coefficient context retains mutable CDF leaves" {
  let context = av1_coeff_context(33, 3, 1)
  assert_eq(context.tx_ctx, 3)
  assert_eq(context.eob.length(), 12)
  // Rows are kept per transform-size context (txSzCtx 0..4, br capped at 3).
  assert_eq(context.extra.length(), 5)
  assert_eq(context.extra[3].length(), 9)
  assert_eq(context.base_eob.length(), 5)
  assert_eq(context.base_eob[3].length(), 4)
  assert_eq(context.base.length(), 5)
  assert_eq(context.base[3].length(), 42)
  assert_eq(context.br.length(), 4)
  assert_eq(context.br[3].length(), 21)
  assert_eq(context.sign.length(), 3)
  let first = context.eob[0]
  context.eob[0] = first - 1
  assert_eq(context.eob[0], first - 1)
}

///|
test "square coefficient decoder returns full 64x64 transform storage" {
  let context = av1_coeff_context(33, 4, 0)
  let coefficients = av1_decode_coeffs_square_with_decoder(
    av1_msac_new([b'\x00', b'\x00'], false),
    33,
    context,
  ).unwrap()
  assert_eq(coefficients.length(), 4096)
  assert_eq(coefficients[0], 8)
}

///|
test "rectangular coefficient scans cover both adjusted domains and 1D classes" {
  let diagonal = av1_coeff_scan_rect(32, 16, AV1_SCAN_DEFAULT)
  let vertical = av1_coeff_scan_rect(32, 16, AV1_SCAN_VERT)
  let horizontal = av1_coeff_scan_rect(16, 32, AV1_SCAN_HORZ)
  assert_eq(diagonal.length(), 512)
  assert_eq(vertical.length(), 512)
  assert_eq(horizontal.length(), 512)
  assert_eq(diagonal[0], 0)
  assert_eq(diagonal[1], 32)
  assert_eq(diagonal[2], 1)
  assert_eq(vertical[1], 32)
  assert_eq(horizontal[16], 16)
  let transposed = av1_coeff_scan_rect(16, 32, AV1_SCAN_DEFAULT)
  assert_eq(transposed[0], 0)
  assert_eq(transposed[1], 1)
  assert_eq(transposed[2], 16)
}

/// Large rectangular transforms code the adjusted 32x32 domain and expand
/// into a full 64x32/32x64 coefficient plane for inverse reconstruction.
test "large rectangular coefficient decoder expands adjusted domain" {
  let context = av1_coeff_context(33, 4, 0)
  let horizontal = av1_decode_coeffs_leaf_with_decoder(
    av1_msac_new([b'\x00', b'\x00', b'\x00', b'\x00'], false),
    33,
    context,
    64,
    height=32,
  ).unwrap()
  assert_eq(horizontal.coeffs.length(), 64 * 32)
  for row in 0..<32 {
    for col in 32..<64 { assert_eq(horizontal.coeffs[row * 64 + col], 0) }
  }
  let vertical_context = av1_coeff_context(33, 4, 0)
  let vertical = av1_decode_coeffs_leaf_with_decoder(
    av1_msac_new([b'\x00', b'\x00', b'\x00', b'\x00'], false),
    33,
    vertical_context,
    32,
    height=64,
  ).unwrap()
  assert_eq(vertical.coeffs.length(), 32 * 64)
  for row in 32..<64 {
    for col in 0..<32 { assert_eq(vertical.coeffs[row * 32 + col], 0) }
  }
}

test "small rectangular coefficient decoder uses area-class EOB tables" {
  let a = av1_decode_coeffs_leaf_with_decoder(
    av1_msac_new([b'\x00', b'\x00', b'\x00'], false),
    33,
    av1_coeff_context(33, 1, 0),
    4,
    height=8,
  ).unwrap()
  assert_eq(a.coeffs.length(), 32)
  let b = av1_decode_coeffs_leaf_with_decoder(
    av1_msac_new([b'\x00', b'\x00', b'\x00', b'\x00'], false),
    33,
    av1_coeff_context(33, 4, 0),
    16,
    height=64,
  ).unwrap()
  assert_eq(b.coeffs.length(), 16 * 64)
}
