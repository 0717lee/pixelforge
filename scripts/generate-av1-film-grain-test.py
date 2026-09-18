"""Generate the film-grain white-box test with the fixture stream embedded."""

import sys

STREAM = "tests/fixtures/av1-film-grain/rs_grain1.obu"
OUT = "av1_film_grain_wbtest.mbt"


def moon_bytes(data, per_line=12):
    lines = []
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        lines.append(
            "    " + ", ".join("b'\\x%02X'" % b for b in chunk) + ","
        )
    return "\n".join(lines)


HEADER = '''/// Film grain tests.
///
/// The fixture is a reduced-still aomenc encode (--film-grain-test=1) of a
/// 64x64 8-bit 4:2:0 frame. Every expectation is dav1d 1.2.1 output: the
/// grain-free decode uses --filmgrain 0 and the grained decode is the default,
/// so the pair isolates the synthesis exactly. The reduced-still header is
/// required because AVIF stills always set reduced_still_picture_header, and
/// the go-av1 test streams are inter sequences that cannot exercise it.

///|
/// Position-sensitive 24-bit digest. A single differing sample changes it.
fn av1_fg_digest(samples : Array[Int]) -> Int {
  let mut h = 0
  for i in 0..<samples.length() {
    let v = samples[i] & 0xFF
    h = h ^ (v + (i & 0xFF))
    h = ((h << 5) & 0xFFFFFF) | ((h >> 19) & 0x1F)
  }
  h & 0xFFFFFF
}

///|
fn av1_fg_stream() -> Array[Byte] {
  [
'''

FOOTER = '''  ]
}

///|
fn av1_fg_params() -> Av1FilmGrainParams? {
  let stream = av1_fg_stream()
  let seq = match av1_sequence_info(stream) {
    None => return None
    Some(value) => value
  }
  let frames = av1_obu_payloads(stream, 6)
  if frames.length() == 0 {
    return None
  }
  match av1_parse_stage1_frame(frames[0], seq) {
    None => None
    Some(frame) => frame.film_grain
  }
}

///|
fn av1_fg_same_ints(actual : Array[Int], expected : Array[Int]) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut ok = true
    for i in 0..<expected.length() {
      if actual[i] != expected[i] {
        ok = false
      }
    }
    ok
  }
}

///|
/// The parameter values come from _refs/film_grain_sim.py, which parses the
/// same stream bit by bit and byte-aligns at the tile group. A wrong AR
/// coefficient count would still land on a byte boundary but desynchronise
/// the tile data, so this test guards the go-av1 coefficient arithmetic.
test "film grain header parses aomenc test vector 1" {
  let fg = av1_fg_params().unwrap()
  assert_eq(fg.apply_grain, true)
  assert_eq(fg.grain_seed, 51993)
  assert_eq(fg.num_y_points, 14)
  assert_eq(
    av1_fg_same_ints(fg.point_y_value, [16, 25, 33, 41, 48, 56, 67, 82, 97, 113, 128, 143, 158, 178]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_y_scaling, [0, 136, 144, 160, 168, 136, 128, 144, 152, 144, 176, 168, 176, 184]),
    true,
  )
  assert_eq(fg.chroma_scaling_from_luma, false)
  assert_eq(fg.num_cb_points, 8)
  assert_eq(fg.num_cr_points, 9)
  assert_eq(
    av1_fg_same_ints(fg.point_cb_value, [16, 20, 28, 60, 90, 105, 134, 168]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cb_scaling, [0, 64, 88, 104, 136, 160, 168, 208]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cr_value, [16, 28, 56, 66, 80, 108, 122, 137, 169]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cr_scaling, [0, 96, 80, 96, 104, 96, 112, 112, 176]),
    true,
  )
  assert_eq(fg.grain_scaling_minus8, 3)
  assert_eq(fg.ar_coeff_lag, 2)
  // numPosLuma = 2 * lag * (lag + 1) = 12 for luma, plus the centre tap for
  // chroma because num_y_points > 0.
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_y, [128, 128, 70, 128, 128, 128, 52, 228, 85, 128, 77, 210]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_cb, [128, 128, 79, 128, 128, 128, 92, 150, 98, 128, 90, 135, 167]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_cr, [128, 128, 81, 128, 128, 128, 97, 159, 103, 128, 96, 141, 28]),
    true,
  )
  assert_eq(fg.ar_coeff_shift_minus6, 2)
  assert_eq(fg.grain_scale_shift, 0)
  assert_eq(fg.cb_mult, 247)
  assert_eq(fg.cb_luma_mult, 192)
  assert_eq(fg.cb_offset, 18)
  assert_eq(fg.cr_mult, 229)
  assert_eq(fg.cr_luma_mult, 192)
  assert_eq(fg.cr_offset, 54)
  assert_eq(fg.overlap_flag, false)
  assert_eq(fg.clip_to_restricted_range, true)
}

///|
/// End-to-end: the reduced-still frame decodes and the grain synthesis
/// reproduces dav1d 1.2.1 output for all 6144 samples. The grain-free decode
/// (dav1d --filmgrain 0) digests differently, so the pair cannot pass by
/// accident, and the first samples pin the plane order and offsets.
test "film grain synthesis matches dav1d pixel truth" {
  let frame = av1_decode_frame_planes(av1_fg_stream()).unwrap()
  let y = av1_frame_crop(frame, 0)
  let u = av1_frame_crop(frame, 1)
  let v = av1_frame_crop(frame, 2)
  assert_eq(y.length(), 4096)
  assert_eq(u.length(), 1024)
  assert_eq(v.length(), 1024)
  // dav1d with grain synthesis enabled.
  assert_eq(av1_fg_digest(y), 9177809)
  assert_eq(av1_fg_digest(u), 6447404)
  assert_eq(av1_fg_digest(v), 3641591)
  assert_eq(y[0], 19)
  assert_eq(y[1], 87)
  assert_eq(y[2], 168)
  assert_eq(y[3], 16)
  assert_eq(u[0], 129)
  assert_eq(u[1], 127)
  assert_eq(u[2], 127)
  assert_eq(u[3], 125)
  assert_eq(v[0], 164)
  assert_eq(v[1], 89)
  assert_eq(v[2], 240)
  assert_eq(v[3], 113)
}
'''


def main():
    data = open(STREAM, "rb").read()
    body = HEADER + moon_bytes(data) + "\n" + FOOTER
    open(OUT, "w", newline="\n").write(body)
    print("wrote", OUT, len(data), "stream bytes")


if __name__ == "__main__":
    sys.exit(main())
