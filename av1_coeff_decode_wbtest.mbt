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
