/// `Div_Mult`, the reciprocal lookup table the temporal motion-vector projection
/// divides by (AV1 §7.9.3, `av1spec08.md:872-877`).
///
/// The 32 values are transcribed verbatim from the specification. They equal
/// `16384 / i` in integer division for every index, which the white-box test
/// below pins; that identity is a check on the transcription, not a substitute
/// for it, so the table stays literal.

///|
let av1_mv_div_mult : Array[Int] = [
  0, 16384, 8192, 5461, 4096, 3276, 2730, 2340, 2048, 1820, 1638, 1489, 1365, 1260,
  1170, 1092, 1024, 963, 910, 862, 819, 780, 744, 712, 682, 655, 630, 606, 585, 564,
  546, 528,
]

///|
/// `Div_Mult` has exactly 32 entries, and the temporal projection indexes it
/// with `Min(MAX_FRAME_DISTANCE, denominator)`. That is what bounds
/// `MAX_FRAME_DISTANCE` to at most 31 — see HANDOFF.md addendum 25.
pub let av1_mv_div_mult_size : Int = 32
