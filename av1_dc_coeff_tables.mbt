// AV1 default probability and 8-bit DC quantizer tables for the DC-only path.
// Adapted from go-av1/cdf/tables_coeff_gen.go and decode/quant_gen.go,
// generated there from AV1 specification sections 10 and 7.12.3.
// Copyright (c) 2026, Oleksandr Zhabotynskyi. BSD-2-Clause.
// Keep this attribution with the table source when redistributing the project.
// Each CDF call returns a fresh array: its final slot is a mutable adaptation
// counter, so callers must retain the result for the life of the tile context.

///|
fn av1_dc_q_context(qidx : Int) -> Int {
  if qidx < 0 || qidx > 255 {
    abort("AV1 coefficient CDF qidx must be in 0..255")
  }
  if qidx <= 20 {
    0
  } else if qidx <= 60 {
    1
  } else if qidx <= 120 {
    2
  } else {
    3
  }
}

///|
/// DefaultEobPt1024Cdf[coeffQIdx(base_q_idx)][ptype].
/// A 32x32 or 64x64 DCT uses this 11-symbol EOB position CDF.
fn av1_dc_eob1024_cdf(qidx : Int, ptype : Int) -> Array[Int] {
  av1_coeff_eob1024_default(av1_dc_q_context(qidx), ptype)
}

/// Compact DC-only view of the complete coeff_base_eob table.
fn av1_dc_base_eob_cdf(qidx : Int, tx_ctx : Int, ptype : Int) -> Array[Int] {
  if tx_ctx != 3 && tx_ctx != 4 { abort("AV1 DC EOB requires tx context 3 or 4") }
  av1_coeff_base_eob_default(av1_dc_q_context(qidx), tx_ctx, ptype, 0)
}

///|
/// DefaultCoeffBaseEobCdf[coeffQIdx(base_q_idx)][txSzCtx][ptype][38].
///
/// In the AV1 syntax the DC coefficient (scan position c=0) has the EOB
/// context `sigCoefContexts - 4 = 38`.  The generated default table stores
/// only the four EOB contexts, after subtracting `sigCoefContexts -
/// sigCoefContextsEob`; therefore semantic context 38 is inner index 0.  This
/// wrapper makes that offset explicit while preserving the compact source
/// table.  `tx_ctx` is 3 (TX_32X32/chroma) or 4 (TX_64X64/luma).
fn av1_dc_base_eob_dc_cdf(qidx : Int, tx_ctx : Int, ptype : Int) -> Array[Int] {
  av1_dc_base_eob_cdf(qidx, tx_ctx, ptype)
}

///|
/// DefaultCoeffBrCdf[coeffQIdx(base_q_idx)][3][ptype][0].
/// The range context caps tx_ctx at TX_32X32 (3). With only DC nonzero,
/// all neighboring coefficient magnitudes are zero, hence br_ctx is 0.
fn av1_dc_br_cdf(qidx : Int, ptype : Int) -> Array[Int] {
  av1_coeff_br_default(av1_dc_q_context(qidx), 3, ptype, 0)
}

///|
/// DefaultDcSignCdf[coeffQIdx(base_q_idx)][ptype][0].
/// Context 0 requires a zero sum of neighboring DC signs, including absent
/// top/left neighbors. It is not the sign context for arbitrary later blocks.
fn av1_dc_sign_cdf(qidx : Int, ptype : Int) -> Array[Int] {
  av1_coeff_dc_sign_default(av1_dc_q_context(qidx), ptype, 0)
}

///|
/// Dc_Qlookup[0][qindex], the 8-bit quantizer table.
/// qindex includes the plane's DC delta and must already be clamped to 0..255.
fn av1_dc_quant_8(qindex : Int) -> Int {
  let table : Array[Int] = [
    4, 8, 8, 9, 10, 11, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 23, 24,
    25, 26, 26, 27, 28, 29, 30, 31, 32, 32, 33, 34, 35, 36, 37, 38, 38, 39, 40, 41,
    42, 43, 43, 44, 45, 46, 47, 48, 48, 49, 50, 51, 52, 53, 53, 54, 55, 56, 57, 57,
    58, 59, 60, 61, 62, 62, 63, 64, 65, 66, 66, 67, 68, 69, 70, 70, 71, 72, 73, 74,
    74, 75, 76, 77, 78, 78, 79, 80, 81, 81, 82, 83, 84, 85, 85, 87, 88, 90, 92, 93,
    95, 96, 98, 99, 101, 102, 104, 105, 107, 108, 110, 111, 113, 114, 116, 117, 118,
    120, 121, 123, 125, 127, 129, 131, 134, 136, 138, 140, 142, 144, 146, 148, 150,
    152, 154, 156, 158, 161, 164, 166, 169, 172, 174, 177, 180, 182, 185, 187, 190,
    192, 195, 199, 202, 205, 208, 211, 214, 217, 220, 223, 226, 230, 233, 237, 240,
    243, 247, 250, 253, 257, 261, 265, 269, 272, 276, 280, 284, 288, 292, 296, 300,
    304, 309, 313, 317, 322, 326, 330, 335, 340, 344, 349, 354, 359, 364, 369, 374,
    379, 384, 389, 395, 400, 406, 411, 417, 423, 429, 435, 441, 447, 454, 461, 467,
    475, 482, 489, 497, 505, 513, 522, 530, 539, 549, 559, 569, 579, 590, 602, 614,
    626, 640, 654, 668, 684, 700, 717, 736, 755, 775, 796, 819, 843, 869, 896, 925,
    955, 988, 1022, 1058, 1098, 1139, 1184, 1232, 1282, 1336,
  ]
  table[qindex]
}

///|
test "AV1 DC CDF quantizer boundaries and independent adaptive state" {
  let qindices = [0, 20, 21, 60, 61, 120, 121, 255]
  let expected_contexts = [0, 0, 1, 1, 2, 2, 3, 3]
  for i in 0..<qindices.length() {
    let qidx = qindices[i]
    let expected = expected_contexts[i]
    assert_eq(av1_dc_q_context(qidx), expected)
    for ptype in 0..<2 {
      let cdfs = [
        av1_dc_eob1024_cdf(qidx, ptype),
        av1_dc_base_eob_cdf(qidx, 3, ptype),
        av1_dc_base_eob_cdf(qidx, 4, ptype),
        av1_dc_br_cdf(qidx, ptype),
        av1_dc_sign_cdf(qidx, ptype),
      ]
      let copies = [
        av1_dc_eob1024_cdf(qidx, ptype),
        av1_dc_base_eob_cdf(qidx, 3, ptype),
        av1_dc_base_eob_cdf(qidx, 4, ptype),
        av1_dc_br_cdf(qidx, ptype),
        av1_dc_sign_cdf(qidx, ptype),
      ]
      for i in 0..<cdfs.length() {
        let cdf = cdfs[i]
        assert_eq(cdf[cdf.length() - 2], 32768)
        assert_eq(cdf[cdf.length() - 1], 0)
        for j in 1..<(cdf.length() - 1) {
          assert_true(cdf[j] > cdf[j - 1])
        }
        cdf[cdf.length() - 1] = 32
        assert_eq(copies[i][cdf.length() - 1], 0)
      }
      assert_eq(
        av1_dc_base_eob_dc_cdf(qidx, 3, ptype),
        av1_dc_base_eob_cdf(qidx, 3, ptype),
      )
    }
  }
}

///|
test "AV1 8-bit DC quantizer extrema and monotonicity" {
  assert_eq(av1_dc_quant_8(0), 4)
  assert_eq(av1_dc_quant_8(128), 140)
  assert_eq(av1_dc_quant_8(255), 1336)
  for q in 1..<256 {
    assert_true(av1_dc_quant_8(q) >= av1_dc_quant_8(q - 1))
  }
}
