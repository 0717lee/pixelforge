///|
test "rectangular coefficient CDF rows use square down and square up" {
  for
    size in [
      (4, 16, 1),
      (8, 32, 2),
      (16, 64, 3),
      (4, 8, 1),
      (8, 16, 2),
      (16, 32, 3),
      (32, 64, 4),
    ] {
    let (width, height, row) = size
    assert_eq(av1_tx_size_ctx_rect(width, height), row)
    assert_eq(av1_tx_size_ctx_rect(height, width), row)
    let context = av1_coeff_context(0, 4, 0)
    ignore(
      av1_tx_decode_leaf_nodes(
        av1_msac_new(Array::make(64, b'\x00'), false),
        0,
        context,
        [{ node: { row: 0, col: 0, width, height, }, depth: 0, }],
        10,
      ),
    )
    assert_eq(context.tx_ctx, row)
  }
}

///|
test "rectangular AC positional contexts retain original transform orientation" {
  // Normative Coeff_Base_Ctx_Offset rows for tall and wide transforms.
  // Check also 32x64/64x32, whose adjusted coefficient domain is square.
  for size in [(4, 8), (4, 16), (8, 16), (8, 32), (16, 32), (16, 64), (32, 64)] {
    let (width, height) = size
    let dw = if width > 32 { 32 } else { width }
    let dh = if height > 32 { 32 } else { height }
    let quant = Array::make(dw * dh, 0)
    assert_eq(
      av1_coeff_base_ctx_rect(
        quant,
        1,
        0,
        false,
        dw,
        dh,
        width,
        height,
        AV1_SCAN_DEFAULT,
      ),
      11,
    )
    assert_eq(
      av1_coeff_base_ctx_rect(
        quant,
        dw,
        0,
        false,
        dw,
        dh,
        width,
        height,
        AV1_SCAN_DEFAULT,
      ),
      11,
    )
    assert_eq(
      av1_coeff_base_ctx_rect(
        quant,
        2 * dw,
        0,
        false,
        dw,
        dh,
        width,
        height,
        AV1_SCAN_DEFAULT,
      ),
      6,
    )
    assert_eq(
      av1_coeff_base_ctx_rect(
        quant,
        1,
        0,
        false,
        dh,
        dw,
        height,
        width,
        AV1_SCAN_DEFAULT,
      ),
      16,
    )
    assert_eq(
      av1_coeff_base_ctx_rect(
        quant,
        2,
        0,
        false,
        dh,
        dw,
        height,
        width,
        AV1_SCAN_DEFAULT,
      ),
      6,
    )
  }
}

///|
test "one dimensional coefficient contexts use axis specific neighbours" {
  let quant = Array::make(64, 0)
  quant[3 * 8] = 3
  quant[4 * 8] = 3
  assert_eq(
    av1_coeff_base_ctx_square(quant, 0, 0, false, 8, 1, AV1_SCAN_VERT),
    29,
  )
  assert_eq(
    av1_coeff_base_ctx_square(quant, 0, 0, false, 8, 1, AV1_SCAN_HORZ),
    26,
  )
  quant[2 * 8] = 12
  assert_eq(av1_coeff_br_ctx_square(quant, 0, 8, AV1_SCAN_VERT), 6)
  assert_eq(av1_coeff_br_ctx_square(quant, 0, 8, AV1_SCAN_HORZ), 0)
}

///|
test "rectangular residual traversal keeps independent horizontal and vertical extents" {
  for size in [(16, 64), (64, 16), (32, 64), (64, 32)] {
    let (width, height) = size
    // A skipped block reconstructs prediction without consuming coefficients.
    // Check both axes using the same plane state as the live tile decoder.
    let state = av1_intra_state(
      width, height, 64, 10, true, false, false, false,
    )
    let decoder = av1_msac_new([b'\x00'], false)
    let before = decoder.bit_pos
    for plane in 0..<3 {
      let divisor = if plane == 0 { 1 } else { 2 }
      let pw = width / divisor
      let ph = height / divisor
      assert_true(
        av1_intra_transform(
          decoder,
          state,
          plane,
          AV1_INTRA_DC,
          0,
          0,
          pw,
          ph,
          pw,
          ph,
          1,
        ),
      )
      assert_eq(state.planes[plane].pixels, Array::make(pw * ph, 512))
    }
    assert_eq(decoder.bit_pos, before)
  }
  assert_eq(
    av1_dc_sign_ctx_from([0, 0], [0, 0, 1, 1], 0, 0, 2, height_units=4),
    1,
  )
}
