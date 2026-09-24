/// Qmatrix selection and coefficient-path regressions. Full matrix and
/// arithmetic truth is generated independently in av1_qmatrix_reference_wbtest.

///|
test "qmatrix selects independent Y U V levels and disables lossless" {
  let matrix = Some({ y: 0, u: 7, v: 14, })
  for plane in 0..<3 {
    assert_eq(
      av1_qmatrix_level(matrix, plane, Av1TxDctDct, false),
      [0, 7, 14][plane],
    )
    assert_eq(av1_qmatrix_level(matrix, plane, Av1TxDctDct, true), 15)
    assert_eq(av1_qmatrix_level(None, plane, Av1TxDctDct, false), 15)
  }
  assert_true(av1_quant_matrix_valid(matrix))
  assert_true(av1_quant_matrix_valid(Some({ y: 15, u: 15, v: 15, })))
  assert_false(av1_quant_matrix_valid(Some({ y: -1, u: 0, v: 0, })))
  assert_false(av1_quant_matrix_valid(Some({ y: 0, u: 16, v: 0, })))
  assert_false(av1_quant_matrix_valid(Some({ y: 0, u: 0, v: 16, })))
}

///|
test "qmatrix applies only to the nine two dimensional AV1 transforms" {
  let matrix = Some({ y: 3, u: 4, v: 5, })
  for code in 0..<16 {
    let tx_type = av1_tx_type_of_code(code)
    for plane in 0..<3 {
      assert_eq(
        av1_qmatrix_level(matrix, plane, tx_type, false),
        if code < 9 {
          3 + plane
        } else {
          15
        },
      )
    }
  }
}

///|
test "qmatrix level fifteen is the identity for every plane and transform size" {
  for width in [4, 8, 16, 32, 64] {
    for height in [4, 8, 16, 32, 64] {
      if width <= height * 4 && height <= width * 4 {
        let dw = if width > 32 { 32 } else { width }
        let dh = if height > 32 { 32 } else { height }
        for plane in 0..<3 {
          for pos in 0..<(dw * dh) {
            assert_eq(av1_qmatrix_weight(15, plane, width, height, pos), 32)
          }
        }
      }
    }
  }
  for q in [4, 35, 1828, 7312, 29247] {
    assert_eq(av1_qmatrix_quant(q, 32), q)
  }
}

///|
test "dequant denominator uses full transform area including quarter rectangles" {
  for
    size in [
      (4, 4),
      (8, 8),
      (16, 16),
      (4, 8),
      (8, 4),
      (4, 16),
      (16, 4),
      (8, 16),
      (16, 8),
      (8, 32),
      (32, 8),
    ] {
    assert_eq(av1_dequant_denom(size.0, size.1), 1L)
  }
  for size in [(32, 32), (16, 32), (32, 16), (16, 64), (64, 16)] {
    assert_eq(av1_dequant_denom(size.0, size.1), 2L)
  }
  for size in [(64, 64), (32, 64), (64, 32)] {
    assert_eq(av1_dequant_denom(size.0, size.1), 4L)
  }
}

///|
test "coefficient decoder applies chroma DC qmatrix at every bit depth" {
  // This coefficient transcript has EOB=1, magnitude=1 and positive DC.
  // dav1d's 4x4 level-0 chroma DC weight is 35; level-15 is uniform 32.
  let depths = [8, 10, 12]
  // dav1d 1.2.1 src/dequant_tables.c: dav1d_dq_tbl[depth][33][0].
  let scalar_dc = [35, 113, 421]
  let weighted_dc = [38, 124, 460]
  for index in 0..<3 {
    for plane in [1, 2] {
      let leaf = av1_decode_coeffs_leaf_with_decoder(
        av1_msac_new([b'\x00', b'\x00', b'\x00', b'\x00'], false),
        33,
        av1_coeff_context(33, 0, 1),
        4,
        bit_depth=depths[index],
        quant_matrix=Some({ y: 14, u: 0, v: 15, }),
        plane~,
      ).unwrap()
      assert_eq(
        leaf.coeffs[0],
        if plane == 1 {
          weighted_dc[index]
        } else {
          scalar_dc[index]
        },
      )
      assert_eq(leaf.cul_level, 1)
      assert_eq(leaf.dc_category, 2)
      for pos in 1..<16 {
        assert_eq(leaf.coeffs[pos], 0)
      }
    }
  }
}

///|
test "coefficient decoder bypasses qmatrix for identity and lossless" {
  for tx_type in [Av1TxIdentityIdentity, Av1TxDctDct] {
    let leaf = av1_decode_coeffs_leaf_with_decoder(
      av1_msac_new([b'\x00', b'\x00', b'\x00', b'\x00'], false),
      0,
      av1_coeff_context(0, 0, 1),
      4,
      quant_matrix=Some({ y: 0, u: 0, v: 0, }),
      plane=1,
      tx_type~,
      lossless=tx_type is Av1TxDctDct,
    ).unwrap()
    assert_eq(leaf.coeffs[0], 4)
  }
}

///|
test "coefficient decoder rejects out of range qmatrix before reading symbols" {
  let decoder = av1_msac_new([b'\x00', b'\x00'], false)
  assert_true(
    av1_decode_coeffs_leaf_with_decoder(
      decoder,
      33,
      av1_coeff_context(33, 0, 0),
      4,
      quant_matrix=Some({ y: 16, u: 0, v: 0, }),
    )
    is None,
  )
}
