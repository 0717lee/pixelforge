///|
/// Expected values are independent forward evaluations of ITU-T H.273
/// (07/2024), not round trips through the decoder. ICtCp vectors were
/// calculated with Python/NumPy: decode the specified RGB transfer,
/// multiply by the normative integer RGB-to-LMS matrix, encode LMS,
/// and multiply by the normative PQ/HLG LMS-to-ICtCp matrix.
fn av1_color_math_near(
  actual : Double,
  expected : Double,
  tolerance : Double,
) -> Unit raise {
  assert_true(
    actual >= expected - tolerance && actual <= expected + tolerance,
    msg="actual=\{actual}, expected=\{expected}, tolerance=\{tolerance}",
  )
}

///|
fn av1_color_math_rgb_near(
  actual : (Double, Double, Double)?,
  expected : (Double, Double, Double),
  tolerance : Double,
) -> Unit raise {
  let (r, g, b) = actual.unwrap()
  let (er, eg, eb) = expected
  av1_color_math_near(r, er, tolerance)
  av1_color_math_near(g, eg, tolerance)
  av1_color_math_near(b, eb, tolerance)
}

///|
test "H273 matrix support rejects reserved values and missing required metadata" {
  for matrix in [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] {
    assert_true(av1_matrix_supported(matrix))
  }
  for matrix in [-1, 3, 15, 255] {
    assert_false(av1_matrix_supported(matrix))
    assert_false(av1_color_supported(matrix, 1, 1))
    assert_true(av1_color_rgb(0.5, 0.0, 0.0, matrix, 1, 1) is None)
  }
  for primary in [0, 2, 3, 13, 21, 23, 255] {
    for matrix in [12, 13] {
      assert_false(av1_color_supported(matrix, primary, 13))
      assert_true(av1_color_rgb(0.5, 0.0, 0.0, matrix, primary, 13) is None)
    }
  }
  for transfer in [0, 2, 3, 19, 255] {
    assert_true(av1_color_linear(0.5, transfer) is None)
    assert_true(av1_color_nonlinear(0.5, transfer) is None)
    for matrix in [10, 13] {
      assert_false(av1_color_supported(matrix, 9, transfer))
      assert_true(av1_color_rgb(0.5, 0.0, 0.0, matrix, 9, transfer) is None)
    }
  }
  assert_true(av1_color_supported(12, 1, 2))
  for transfer in [1, 2, 13, 14, 17] {
    assert_false(av1_color_supported(14, 9, transfer))
    assert_true(av1_color_rgb(0.5, 0.0, 0.0, 14, 9, transfer) is None)
  }
  assert_true(av1_color_supported(14, 9, 16))
  assert_true(av1_color_supported(14, 9, 18))
}

///|
test "H273 NCL matrices restore normative red blue and neutral values" {
  // Matrix 2 is the explicit BT.601 application default.
  for
    item in [
      (1, 0.2126, 0.0722),
      (2, 0.299, 0.114),
      (4, 0.30, 0.11),
      (5, 0.299, 0.114),
      (6, 0.299, 0.114),
      (7, 0.212, 0.087),
      (9, 0.2627, 0.0593),
    ] {
    let (matrix, kr, kb) = item
    av1_color_math_rgb_near(
      av1_color_rgb(kr, -kr / (2.0 * (1.0 - kb)), 0.5, matrix, 2, 2),
      (1.0, 0.0, 0.0),
      1.0e-12,
    )
    av1_color_math_rgb_near(
      av1_color_rgb(kb, 0.5, -kb / (2.0 * (1.0 - kr)), matrix, 2, 2),
      (0.0, 0.0, 1.0),
      1.0e-12,
    )
    for gray in [0.0, 0.18, 0.5, 1.0] {
      av1_color_math_rgb_near(
        av1_color_rgb(gray, 0.0, 0.0, matrix, 2, 2),
        (gray, gray, gray),
        1.0e-12,
      )
    }
  }
}

///|
test "H273 YCgCo and ST2085 restore independently encoded source components" {
  av1_color_math_rgb_near(
    av1_color_rgb(0.425, -0.025, -0.25, 8, 1, 13),
    (0.2, 0.4, 0.7),
    1.0e-12,
  )
  av1_color_math_rgb_near(
    av1_color_rgb(0.4, 0.1452981, -0.0983804, 11, 10, 17),
    (0.2, 0.4, 0.7),
    1.0e-12,
  )
  // An out-of-gamut NCL sample remains unclipped until output quantization.
  av1_color_math_rgb_near(
    av1_color_rgb(0.0, 0.5, 0.0, 8, 1, 13),
    (-0.5, 0.5, -0.5),
    1.0e-12,
  )
}

///|
test "H273 chromaticity-derived matrices use the declared primaries white point" {
  // NumPy solve of the Table 2 primary/white chromaticities. In particular,
  // BT.709/BT.2020 derived coefficients differ from the rounded NCL values.
  for
    item in [
      (1, 0.21263900587151033, 0.07219231536073371),
      (4, 0.29896661812478992, 0.11461217174222660),
      (5, 0.22200430999823087, 0.07134092407648639),
      (6, 0.21237636070506746, 0.08656378236920959),
      (7, 0.21237636070506746, 0.08656378236920959),
      (8, 0.25358536343373467, 0.06807886086929262),
      (9, 0.26270021201126698, 0.05930171646986195),
      (10, 0.0, 0.0),
      (11, 0.20949167791273055, 0.06891306792622581),
      (12, 0.22897456406974875, 0.07928691409374498),
      (22, 0.23175054567210918, 0.09599868152322844),
    ] {
    let (primary, kr, kb) = item
    assert_true(av1_color_supported(12, primary, 2))
    av1_color_math_rgb_near(
      av1_color_rgb(kr, -kr / (2.0 * (1.0 - kb)), 0.5, 12, primary, 2),
      (1.0, 0.0, 0.0),
      1.0e-12,
    )
  }
  // P3-D65 chromaticity-derived CL, independently encoded with TC 13.
  av1_color_math_rgb_near(
    av1_color_rgb(
      0.4030408949819425, 0.21579000390496214, -0.11385466200337964, 13, 12, 13,
    ),
    (0.2, 0.4, 0.7),
    1.0e-11,
  )
  av1_color_math_rgb_near(
    av1_color_rgb(
      0.47279237778684435, -0.19329590962789045, 0.3378934359749564, 13, 12, 13,
    ),
    (0.8, 0.3, 0.1),
    1.0e-11,
  )
}

///|
test "H273 constant luminance independently encoded mixed and primary colors" {
  for
    item in [
      (14, 0.38418384716191745, 0.19963462220434525, -0.10719319444887145),
      (16, 0.45687282258643447, 0.3985995487058502, -0.13269369238523165),
      (18, 0.39453412687598727, 0.264144179489123, -0.10304327485590375),
    ] {
    let (transfer, y, u, v) = item
    av1_color_math_rgb_near(
      av1_color_rgb(y, u, v, 10, 9, transfer),
      (0.2, 0.4, 0.7),
      1.0e-10,
    )
  }
  for
    item in [
      (14, 0.4800466134758218, -0.1958656555117308, 0.32193988591954154),
      (16, 0.6566250215106754, -0.28010689457778276, 0.5016087821451494),
      (18, 0.5673325929291556, -0.23631452406913203, 0.4622191537962814),
    ] {
    let (transfer, y, u, v) = item
    av1_color_math_rgb_near(
      av1_color_rgb(y, u, v, 10, 9, transfer),
      (0.8, 0.3, 0.1),
      1.0e-10,
    )
  }
  av1_color_math_rgb_near(
    av1_color_rgb(0.50308520236579257, -0.25927638727899499, 0.5, 10, 9, 14),
    (1.0, 0.0, 0.0),
    1.0e-11,
  )
  av1_color_math_rgb_near(
    av1_color_rgb(
      0.82363226695007374, -0.42447759865922902, -0.47934590956789791, 10, 9, 14,
    ),
    (0.0, 1.0, 0.0),
    1.0e-11,
  )
  av1_color_math_rgb_near(
    av1_color_rgb(0.20901457535052786, 0.5, -0.12164443496774752, 10, 9, 14),
    (0.0, 0.0, 1.0),
    1.0e-11,
  )
}

///|
test "H273 PQ and HLG ICtCp invert independent forward integer matrices" {
  for
    item in [
      (16, 0.47784643919222974, 0.24353866083225961, -0.2335684315537937),
      (18, 0.40590605193379325, 0.1737119841619193, -0.16532778697301106),
    ] {
    let (transfer, y, ct, cp) = item
    av1_color_math_rgb_near(
      av1_color_rgb(y, ct, cp, 14, 9, transfer),
      (0.2, 0.4, 0.7),
      1.0e-10,
    )
  }
  for
    item in [
      (
        16,
        0.85669469476341198,
        -0.19821794550159591,
        0.4574999435163033,
        (1.0, 0.0, 0.0),
      ),
      (
        16,
        0.94851026644351322,
        -0.4724671495736027,
        -0.11611136000565245,
        (0.0, 1.0, 0.0),
      ),
      (
        16,
        0.73409149651922734,
        0.2834338102143048,
        -0.29994905664242738,
        (0.0, 0.0, 1.0),
      ),
      (
        18,
        0.7458368002454068,
        -0.20492614274313065,
        0.4415769767247995,
        (1.0, 0.0, 0.0),
      ),
      (
        18,
        0.9100406994869747,
        -0.4873959729893254,
        -0.10483179286839611,
        (0.0, 1.0, 0.0),
      ),
      (
        18,
        0.5049375732750662,
        0.2649995892619407,
        -0.3389872261450156,
        (0.0, 0.0, 1.0),
      ),
    ] {
    let (transfer, y, ct, cp, expected) = item
    // PQ maps exact zero to c1^m (~7.31e-7); the inverse RGB matrix
    // also leaves tiny roundoff at zero, amplified by the PQ slope.
    av1_color_math_rgb_near(
      av1_color_rgb(y, ct, cp, 14, 9, transfer),
      expected,
      1.0e-5,
    )
  }
  for transfer in [16, 18] {
    for gray in [0.18, 0.5, 1.0] {
      av1_color_math_rgb_near(
        av1_color_rgb(gray, 0.0, 0.0, 14, 9, transfer),
        (gray, gray, gray),
        1.0e-10,
      )
    }
  }
}

///|
test "H273 transfer functions match independent 18 percent reference values" {
  for
    item in [
      (1, 0.40884810889122397),
      (4, 0.45865644686438112),
      (5, 0.5420332080075112),
      (6, 0.40884810889122397),
      (7, 0.40224697306710883),
      (8, 0.18),
      (9, 0.62763625255165301),
      (10, 0.70210900204132243),
      (11, 0.40884810889122397),
      (12, 0.40884810889122397),
      (13, 0.46135065680336518),
      (14, 0.40884810889122397),
      (15, 0.40884810889122397),
      (16, 0.81594345511375599),
      (17, 0.50004833771723545),
      (18, 0.67235813259809252),
    ] {
    let (transfer, encoded) = item
    av1_color_math_near(
      av1_color_nonlinear(0.18, transfer).unwrap(),
      encoded,
      1.0e-12,
    )
    av1_color_math_near(
      av1_color_linear(encoded, transfer).unwrap(),
      0.18,
      1.0e-12,
    )
  }
}

///|
test "H273 transfer dark segments and signed extended gamut domains" {
  for transfer in [1, 6, 11, 12, 14, 15] {
    av1_color_math_near(
      av1_color_nonlinear(0.01, transfer).unwrap(),
      0.045,
      1.0e-14,
    )
    av1_color_math_near(
      av1_color_linear(0.045, transfer).unwrap(),
      0.01,
      1.0e-14,
    )
  }
  av1_color_math_near(av1_color_nonlinear(0.01, 7).unwrap(), 0.04, 1.0e-14)
  av1_color_math_near(av1_color_linear(0.04, 7).unwrap(), 0.01, 1.0e-14)
  av1_color_math_near(
    av1_color_nonlinear(-0.001, 12).unwrap(),
    -0.0045,
    1.0e-14,
  )
  av1_color_math_near(av1_color_linear(-0.0045, 12).unwrap(), -0.001, 1.0e-14)
  av1_color_math_near(
    av1_color_nonlinear(-0.045, 12).unwrap(),
    -0.102212027222806,
    1.0e-12,
  )
  av1_color_math_near(
    av1_color_linear(-0.102212027222806, 12).unwrap(),
    -0.045,
    1.0e-12,
  )
  av1_color_math_near(
    av1_color_nonlinear(-0.18, 11).unwrap(),
    -0.40884810889122397,
    1.0e-12,
  )
  av1_color_math_near(
    av1_color_nonlinear(-0.18, 13).unwrap(),
    -0.46135065680336518,
    1.0e-12,
  )
  av1_color_math_near(
    av1_color_linear(-0.46135065680336518, 13).unwrap(),
    -0.18,
    1.0e-12,
  )
  av1_color_math_near(
    av1_color_nonlinear(-0.001, 13).unwrap(),
    -0.01292,
    1.0e-14,
  )
  av1_color_math_near(av1_color_linear(-0.01292, 13).unwrap(), -0.001, 1.0e-14)
  av1_color_math_near(av1_color_linear(0.5, 18).unwrap(), 1.0 / 12.0, 1.0e-14)
  av1_color_math_near(
    av1_color_nonlinear(1.0 / 12.0, 18).unwrap(),
    0.5,
    1.0e-14,
  )
  for transfer in [9, 10] {
    av1_color_math_near(
      av1_color_nonlinear(0.001, transfer).unwrap(),
      0.0,
      1.0e-14,
    )
    av1_color_math_near(av1_color_linear(0.0, transfer).unwrap(), 0.0, 1.0e-14)
  }
}

///|
test "H273 PQ inverse rejects its asymptote without clipping finite highlights" {
  av1_color_math_near(av1_color_linear(1.0, 16).unwrap(), 1.0, 1.0e-14)
  av1_color_math_near(
    av1_color_linear(1.1, 16).unwrap(),
    2.6556252635527993,
    1.0e-12,
  )
  for encoded in [1.1, 1.9, 1.99] {
    let linear = av1_color_linear(encoded, 16).unwrap()
    assert_true(linear > 1.0 && linear < @double.max_value)
  }
  // The positive-light forward curve approaches (c2/c3)^m ~= 1.99206.
  // Larger encoded values have no finite real inverse, even though matrix
  // reconstruction can produce them from individually valid sample codes.
  for encoded in [1.9920600818564766, 2.0, 10.0] {
    assert_true(av1_color_linear(encoded, 16) is None)
  }
  // Derived CL with XYZ primaries has Kr=Kb=0. Maximal luma/chroma can
  // reconstruct nearly 2.0 in R/B, which previously contaminated G with NaN.
  assert_true(av1_color_rgb(1.0, 0.5, 0.5, 13, 10, 16) is None)
  // ICtCp must propagate the same failure, not unwrap the inverse transfer.
  assert_true(av1_color_rgb(2.0, 0.0, 0.0, 14, 9, 16) is None)
}
