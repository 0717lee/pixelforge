"""Emitter for the Phase D general-header reference test.

Reads the fixtures under tests/fixtures/av1-inter (each an untouched libaom
encode plus dav1d's native planes) and writes
av1_inter_reference_wbtest.mbt.

The template uses @TOKEN@ substitution rather than Python % formatting because
the MoonBit assertions contain their own %@ / %d format specifiers.
"""

import os
import subprocess

MOONFMT = os.path.join(os.path.expanduser("~"), ".moon", "bin", "moonfmt")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "fixtures", "av1-inter")
OUT = os.path.join(ROOT, "av1_inter_reference_wbtest.mbt")

WIDTH = HEIGHT = 64
PLANE = WIDTH * HEIGHT + 2 * (WIDTH // 2) * (HEIGHT // 2)


def frame_plane_of(spec):
    """Bytes of one I420 frame of the fixture this spec belongs to."""
    width = int(spec["width"])
    height = int(spec["height"])
    return width * height + 2 * (width // 2) * (height // 2)
NAMES = (
    "general_inter_64x64",
    "inter_minimal_64x64",
    "inter_still_64x64",
    "inter_shift_64x64",
    "inter_edge_64x16",
)
# Listing a fixture here replaces its assertions with the diagnostic print
# below, which is how a new fixture's header sizes and per-plane agreement are
# discovered before they are pinned in SPECS. Keep this empty in committed work:
# the generated test must not print.
PROBE = ()

SPECS = {
    "general_inter_64x64": {
        "order_hint": "true",
        "warped": "true",
        "dual": "true",
        "ref_mvs": "true",
        "hint_bits": "7",
        "inter_order_hint": "1",
        "switchable_motion": "true",
        "key_bytes": "9",
        "inter_bytes": "15",
        "interp": "4",
        "key_q": "49",
        "inter_q": "128",
        "width": "64",
        "height": "64",
        "bad_counts": "0, 0, 0",
        # Compound-capable signalling, overlapped and warped motion and temporal
        # motion vectors are all on, so the block stage refuses the frame whole.
        "inter_decodable": "false",
        "inter_note": "tools the block stage refuses: compound signalling, overlapped and warped motion, temporal motion vectors",
    },
    # --enable-order-hint=0 and --enable-warped-motion=0 turn each of those
    # frame-header fields into a derivation rather than a read, so the same
    # assertions prove the gates as well as the grammar.
    "inter_minimal_64x64": {
        "order_hint": "false",
        "warped": "false",
        "dual": "false",
        "ref_mvs": "false",
        "hint_bits": "0",
        "inter_order_hint": "0",
        "switchable_motion": "false",
        "key_bytes": "9",
        "inter_bytes": "14",
        "interp": "4",
        "key_q": "49",
        "inter_q": "128",
        "width": "64",
        "height": "64",
        # The dense partition tree no longer blows the tile budget: the frame
        # decodes, and the pinned counts are its remaining disagreement with
        # dav1d. Luma is wrong only in the last three columns of the 48 rows
        # below the first 16, chroma only in that same quadrant and by 1-2
        # samples, which is the signature of the later 4x16 strips not reaching
        # the far motion vector their top-row twins use. This frame is switchable
        # interpolation, the one tool the exact fixtures do not exercise.
        "bad_counts": "144, 248, 296",
        "inter_decodable": "true",
        "inter_note": "dense tree with switchable interpolation: still short of sample-exact, counts pinned",
        "animation_changed": "true",
        "animation_note": "The second sample is a translated picture, so the presented pixels must differ.",
    },
    # A repeated frame: the encoder answers with whole-frame skips, so the tree
    # stays coarse and the frame carries no deblocking at all. This is the
    # cleanest end-to-end inter reconstruction the encoder will produce.
    "inter_still_64x64": {
        "order_hint": "false",
        "warped": "false",
        "dual": "false",
        "ref_mvs": "false",
        "hint_bits": "0",
        "inter_order_hint": "0",
        "switchable_motion": "false",
        "key_bytes": "9",
        "inter_bytes": "14",
        "interp": "0",
        "key_q": "12",
        "inter_q": "128",
        "width": "64",
        "height": "64",
        "bad_counts": "0, 0, 0",
        "inter_decodable": "true",
        "inter_note": "whole-frame repeat: no loop filter, one reference, integer motion",
        "animation_changed": "false",
        "animation_note": "The second sample repeats the first, so the presented pixels must be identical.",
    },
    # A true half-pixel translation of a band-limited wave: fractional motion
    # vectors and the per-block interpolation filter, but chroma deblocking is
    # live (loop_filter_level[1] is 4) so the chroma plane also needs the inter
    # loop-filter deltas.
    "inter_shift_64x64": {
        "order_hint": "false",
        "warped": "false",
        "dual": "false",
        "ref_mvs": "false",
        "hint_bits": "0",
        "inter_order_hint": "0",
        "switchable_motion": "false",
        "key_bytes": "10",
        "inter_bytes": "16",
        "interp": "4",
        "key_q": "49",
        "inter_q": "128",
        "width": "64",
        "height": "64",
        "bad_counts": "0, 0, 0",
        "inter_decodable": "true",
        "inter_note": "fractional translation: subpel motion compensation plus chroma deblocking",
        "animation_changed": "true",
        "animation_note": "The second sample is a translated picture, so the presented pixels must differ.",
    },
    # The periodic content forces the last strip to reach back into the frame
    # instead of coding a residual, which is what pins the magnitude-class bits
    # of read_mv_component to the right CDF rows.
    "inter_edge_64x16": {
        "order_hint": "false",
        "warped": "false",
        "dual": "false",
        "ref_mvs": "false",
        "hint_bits": "0",
        "inter_order_hint": "0",
        "switchable_motion": "false",
        "key_bytes": "9",
        "inter_bytes": "15",
        "interp": "0",
        "key_q": "49",
        "inter_q": "128",
        "width": "64",
        "height": "16",
        "bad_counts": "0, 0, 0",
        "inter_decodable": "true",
        "inter_note": "periodic translation: the last strip reaches back with a large motion vector",
        "animation_changed": "true",
        "animation_note": "The second sample is a translated picture, so the presented pixels must differ.",
    },
}

HEADER = (
    "/// Generated by scripts/emit-av1-inter-test.py from\n"
    "/// scripts/generate-av1-inter-reference.py fixtures.\n"
    "///\n"
    "/// General (non reduced-still) AV1 headers carrying real inter frames, checked\n"
    "/// field-by-field against the FFmpeg `trace_headers` transcripts in\n"
    "/// tests/fixtures/av1-inter, plus dav1d's native planes for both frames.\n"
    "/// `inter_still_64x64` and `inter_shift_64x64` reconstruct their inter frames\n"
    "/// sample-exactly on all three planes, the first end-to-end motion-compensated\n"
    "/// evidence in the package: one whole-frame skip with integer motion, one true\n"
    "/// half-pixel translation with a switchable interpolation filter and live\n"
    "/// chroma deblocking. The other two fixtures parse completely and are then\n"
    "/// refused whole, because they need tools the block stage does not have yet\n"
    "/// (compound, warped and global motion, temporal motion vectors) or the tile\n"
    "/// budget fix; a partial reconstruction would be worse than no picture.\n"
)

HELPERS = r"""
///|
fn av1_inter_expand(runs : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < runs.length() {
    let value = runs[i]
    let count = runs[i + 1]
    for _ in 0..<count {
      out.push(value)
    }
    i = i + 2
  }
  out
}

///|
/// dav1d's fixture planes are concatenated row-packed; copy one plane out.
fn av1_inter_slice(source : Array[Int], start : Int, end : Int) -> Array[Int] {
  Array::makei(end - start, i => source[start + i])
}

///|
/// Parse both frame headers of a fixture against one shared reference buffer,
/// the way a video decoder walks a temporal unit.
fn av1_inter_parse(
  obu : Array[Byte],
  label : String,
) -> (Av1SequenceInfo, Array[Av1FrameHeaderInfo], Av1FrameMap) raise {
  let seq = match av1_sequence_info(obu) {
    Some(value) => value
    None => fail(label + ": no sequence header")
  }
  let map = av1_frame_map()
  let payloads = av1_obu_payloads(obu, 6)
  assert_eq(payloads.length(), 2)
  let headers : Array[Av1FrameHeaderInfo] = []
  for payload in payloads {
    headers.push(match av1_parse_stage1_frame(payload, seq, allow_highbd=true, map=map) {
      Some(value) => value
      None => fail(label + ": frame header rejected")
    })
  }
  (seq, headers, map)
}
"""

TEST_TEMPLATE = r"""
///|
test "@NAME@: general frame headers parse and the key frame matches dav1d" {
  let (seq, headers, map) = av1_inter_parse(@NAME@_obu, "@NAME@")
  assert_eq(seq.reduced_still_picture_header, false)
  assert_eq(seq.enable_order_hint, @ORDER_HINT@)
  assert_eq(seq.enable_warped_motion, @WARPED@)
  assert_eq(seq.enable_dual_filter, @DUAL@)
  assert_eq(seq.enable_ref_frame_mvs, @REF_MVS@)
  assert_eq(seq.seq_force_screen_content_tools, av1_select_screen_content_tools)
  assert_eq(seq.seq_force_integer_mv, av1_select_integer_mv)
  assert_eq(seq.frame_id_numbers_present, false)
  assert_eq(seq.order_hint_bits, @HINT_BITS@)
  assert_eq(seq.use_128x128_superblock, true)
  assert_eq(seq.enable_superres, false)

  let key = headers[0]
  assert_eq(key.frame_type, av1_key_frame)
  assert_eq(key.frame_is_intra, true)
  assert_eq(key.show_frame, true)
  // A showing key frame is error resilient by bitstream requirement (AV1 6.4.2).
  assert_eq(key.error_resilient, true)
  assert_eq(key.primary_ref_frame, av1_primary_ref_none)
  assert_eq(key.refresh_frame_flags, 255)
  assert_eq(key.force_integer_mv, 1)
  assert_eq(key.order_hint, 0)
  assert_eq(key.frame_width, @WIDTH@)
  assert_eq(key.upscaled_width, @WIDTH@)
  assert_eq(key.frame_height, @HEIGHT@)
  assert_eq(key.superres_denom, 8)
  assert_eq(key.render_width, @WIDTH@)
  assert_eq(key.base_q_idx, @KEY_Q@)
  assert_eq(key.header_bytes, @KEY_BYTES@)

  let inter = headers[1]
  assert_eq(inter.frame_type, av1_inter_frame)
  assert_eq(inter.frame_is_intra, false)
  assert_eq(inter.show_frame, true)
  assert_eq(inter.error_resilient, false)
  assert_eq(inter.order_hint, @INTER_ORDER_HINT@)
  assert_eq(inter.primary_ref_frame, av1_primary_ref_none)
  assert_eq(inter.refresh_frame_flags, 2)
  assert_eq(inter.base_q_idx, @INTER_Q@)
  assert_eq(inter.header_bytes, @INTER_BYTES@)
  assert_eq(inter.ref_frame_idx.length(), av1_refs_per_frame)
  for slot in inter.ref_frame_idx {
    // frame_refs_short_signaling is 0 here and every name points at slot 0.
    assert_eq(slot, 0)
  }
  assert_eq(inter.allow_high_precision_mv, false)
  // A switchable frame defers the interpolation filter to each block.
  assert_eq(inter.interpolation_filter, @INTERP@)
  assert_eq(inter.allow_warped_motion, @WARPED@)
  assert_eq(inter.use_ref_frame_mvs, @REF_MVS@)
  assert_eq(inter.is_motion_mode_switchable, @SWITCHABLE@)
  assert_eq(inter.reference_select, false)
  assert_eq(inter.skip_mode_present, false)
  assert_eq(inter.allow_intrabc, false)
  for typ in inter.gm_type {
    assert_eq(typ, av1_gm_identity)
  }
  for bias in inter.ref_frame_sign_bias {
    assert_eq(bias, 0)
  }

  // Parsing alone must not touch the buffer: only reconstruction stores.
  assert_eq(av1_frame_map_show(map, 0) is None, true)
  let decoded = match av1_decode_frame_planes(@NAME@_obu, map=map) {
    Some(value) => value
    None => fail("@NAME@: key frame decode rejected")
  }
  // dav1d's native planes are stored row-packed per plane, the same view
  // `av1_frame_crop` produces from the MI-padded coding layout.
  let reference = av1_inter_expand(@NAME@_frame0_reference)
  let chroma = @PLANE@ / 6
  assert_eq(av1_frame_crop(decoded, 0), av1_inter_slice(reference, 0, @PLANE@ - chroma * 2))
  assert_eq(av1_frame_crop(decoded, 1), av1_inter_slice(reference, @PLANE@ - chroma * 2, @PLANE@ - chroma))
  assert_eq(av1_frame_crop(decoded, 2), av1_inter_slice(reference, @PLANE@ - chroma, @PLANE@))
  // Every slot a key frame claims now shares the same decoded picture.
  let stored = match av1_frame_map_show(map, 0) {
    Some(value) => value
    None => fail("@NAME@: key frame not stored")
  }
  assert_eq(stored.upscaled_width, @WIDTH@)
  assert_eq(stored.frame_height, @HEIGHT@)
  assert_eq(stored.bit_depth, 8)
  assert_eq(stored.frame_type, av1_key_frame)
  for slot in 0..<av1_num_ref_frames {
    assert_eq(av1_frame_map_show(map, slot) is None, false)
  }
}
"""


INTER_TEMPLATE = r"""
test "@NAME@: inter frame reconstruction" {
  let map = av1_frame_map()
  let whole = @NAME@_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, @INTER_UNIT@)
  let inter_unit = av1_inter_slice_bytes(whole, @INTER_UNIT@, @UNIT_END@)
  let sequence = match av1_sequence_info(key_unit) {
    Some(value) => value
    None => fail("@NAME@: no sequence header")
  }
  if av1_decode_frame_planes(key_unit, map=map) is None {
    fail("@NAME@: key frame decode rejected")
  }
  // @INTER_NOTE@. A frame that needs a missing tool must be refused whole:
  // a partial reconstruction would be worse than no picture at all.
  let inter = av1_decode_frame_planes(inter_unit, map=map, sequence=sequence)
  assert_eq(inter is Some(_), @INTER_DECODABLE@)
  if @INTER_DECODABLE@ {
    let frame = match inter {
      Some(value) => value
      None => fail("@NAME@: supported inter frame rejected")
    }
    // dav1d's native planes for the inter frame: sample-exact evidence that
    // motion compensation, the residual and the frame filters agree with an
    // external decoder. Every sample of every plane is counted, so a fixture
    // that is not exact yet carries its disagreement as an explicit number
    // rather than as an excluded region.
    let reference = av1_inter_expand(@NAME@_frame1_reference)
    let chroma = @PLANE@ / 6
    let luma_size = @PLANE@ - chroma * 2
    let bad = [0, 0, 0]
    for p in 0..<3 {
      let got = av1_frame_crop(frame, p)
      let start =
        if p == 0 { 0 } else if p == 1 { luma_size } else { luma_size + chroma }
      for i in 0..<got.length() {
        if got[i] != reference[start + i] {
          bad[p] = bad[p] + 1
        }
      }
    }
    assert_eq(bad, [@BAD_COUNTS@])
  }
}
"""


PROBE_TEMPLATE = r"""
///|
/// Diagnostic only: prints what the decoder actually reports for this fixture.
test "@NAME@: probe" {
  let map = av1_frame_map()
  let whole = @NAME@_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, @INTER_UNIT@)
  let inter_unit = av1_inter_slice_bytes(whole, @INTER_UNIT@, @UNIT_END@)
  let sequence = match av1_sequence_info(key_unit) {
    Some(value) => value
    None => fail("@NAME@: no sequence header")
  }
  let payloads = av1_obu_payloads(key_unit, 6)
  let kh = match av1_parse_stage1_frame(
    payloads[0],
    sequence,
    allow_highbd=true,
    map=map,
  ) {
    Some(value) => value
    None => fail("@NAME@: key header")
  }
  println("PROBE @NAME@ key_bytes=\{kh.header_bytes} key_q=\{kh.base_q_idx}")
  if av1_decode_frame_planes(key_unit, map=map) is None {
    fail("@NAME@: key frame decode rejected")
  }
  let units = av1_obu_payloads(inter_unit, 6)
  let ih = match av1_parse_stage1_frame(
    units[0],
    sequence,
    allow_highbd=true,
    map=map,
  ) {
    Some(value) => value
    None => fail("@NAME@: inter header")
  }
  println("PROBE @NAME@ inter_bytes=\{ih.header_bytes} inter_q=\{ih.base_q_idx}")
  println("PROBE @NAME@ interp=\{ih.interpolation_filter}")
  let inter = av1_decode_frame_planes(inter_unit, map=map, sequence=sequence)
  if inter is None {
    println("PROBE @NAME@ refused")
  } else {
    let frame = match inter {
      Some(value) => value
      None => fail("unreachable")
    }
    let reference = av1_inter_expand(@NAME@_frame1_reference)
    let chroma = @PLANE@ / 6
    let bad = [0, 0, 0]
    for p in 0..<3 {
      let got = av1_frame_crop(frame, p)
      let start = if p == 0 { 0 } else if p == 1 { @PLANE@ - chroma * 2 } else { @PLANE@ - chroma }
      for i in 0..<got.length() {
        if got[i] != reference[start + i] {
          bad[p] = bad[p] + 1
        }
      }
    }
    println(
      "PROBE @NAME@ decoded mismatches y=\{bad[0]} u=\{bad[1]} v=\{bad[2]}",
    )
  }
}
"""


ANIMATION_TEMPLATE = r"""
///|
/// The animated-AVIF seam: one stateful decoder walks the temporal units of a
/// sequence, and a later unit may carry neither the sequence header nor a
/// key frame. @ANIMATION_NOTE@
test "@NAME@: animation entry presents both temporal units" {
  let whole = @NAME@_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, @INTER_UNIT@)
  let inter_unit = av1_inter_slice_bytes(whole, @INTER_UNIT@, @UNIT_END@)
  let samples = avif_decode_animation_samples(
    1000,
    [0, 40],
    [40, 40],
    [key_unit, inter_unit],
  )
  let sequence = match samples {
    Some(value) => value
    None => fail("@NAME@: animation sequence rejected")
  }
  assert_eq(sequence.timescale, 1000)
  assert_eq(sequence.frames.length(), 2)
  assert_eq(sequence.frames[0].index, 0)
  assert_eq(sequence.frames[0].timestamp, 0)
  assert_eq(sequence.frames[1].index, 1)
  assert_eq(sequence.frames[1].timestamp, 40)
  assert_eq(sequence.frames[1].duration, 40)
  assert_eq(sequence.frames[1].timescale, 1000)
  let first = sequence.frames[0].image
  let second = sequence.frames[1].image
  assert_eq(second.width, @WIDTH@)
  assert_eq(second.height, @HEIGHT@)
  let mut changed = 0
  for fy in 0..<5 {
    for fx in 0..<5 {
      let x = fx * (second.width - 1) / 4
      let y = fy * (second.height - 1) / 4
      if first.get_pixel(x, y) != second.get_pixel(x, y) {
        changed = changed + 1
      }
    }
  }
  assert_eq(changed > 0, @CHANGED@)
  // The inter unit is not self-contained: it names no sequence header of its
  // own and predicts from a buffer only the first unit filled. A cold decoder
  // must refuse it rather than present a picture built from nothing.
  assert_eq(av1_video_decode_frame(av1_video_decoder(), inter_unit) is None, true)
}
"""


def obu_chain(data):
    """Return (type, header_start, payload_end) for each OBU in a temporal unit."""
    out = []
    i = 0
    while i < len(data):
        header = data[i]
        kind = (header >> 3) & 0x0F
        has_size = (header >> 1) & 1
        j = i + 1
        if (header >> 2) & 1:
            j += 1
        size = 0
        if has_size:
            shift = 0
            while True:
                byte = data[j]
                size |= (byte & 0x7F) << shift
                j += 1
                if not byte & 0x80:
                    break
                shift += 7
        out.append((kind, i, j + size))
        i = j + size
    return out


def byte_literal(data):
    rows = []
    for start in range(0, len(data), 12):
        rows.append(
            "  " + " ".join("b'\\x%02X'," % b for b in data[start : start + 12])
        )
    return "\n".join(rows)


def rle(samples):
    out = []
    i = 0
    while i < len(samples):
        value = samples[i]
        run = 1
        while (
            i + run < len(samples)
            and samples[i + run] == value
            and run < 9999
        ):
            run += 1
        out.append("%d, %d," % (value, run))
        i += run
    return "\n  ".join(out)


def sequence_tokens(data):
    """Byte offsets that split the first fixture into per-temporal-unit chunks."""
    chain = obu_chain(data)
    types = [entry[0] for entry in chain]
    frames = [i for i, kind in enumerate(chain) if kind[0] == 6]
    seqs = [i for i, kind in enumerate(chain) if kind[0] == 1]
    assert types[0] == 2 and len(frames) == 2 and len(seqs) == 1, chain
    first = chain[frames[0]]
    return {
        "@UNIT1_END@": str(chain[frames[0] + 1][2] if len(chain) > frames[0] + 1 else len(data)),
        "@SEQ_START@": str(chain[seqs[0]][1]),
        "@FRAME_START@": str(first[1]),
        "@FRAME_END@": str(first[2]),
        "@TD_START@": str(chain[1][1]) if types[1] == 2 else "0",
        "@TD_END@": str(chain[1][2]) if types[1] == 2 else "0",
        "@LEN@": str(len(data)),
    }


SEQUENCE_TEST = r"""
///|
/// AVIF image sequences only have to carry the sequence header in the first
/// item, so a later temporal unit that omits it must still decode. These two
/// units are the same key frame, once with the header and once without.
test "video decoder latches the sequence header across temporal units" {
  let whole = general_inter_64x64_obu
  let with_header = av1_inter_slice_bytes(whole, 0, @UNIT1_END@)
  let bare = av1_inter_concat(
    av1_inter_slice_bytes(whole, @TD_START@, @TD_END@),
    av1_inter_concat(
      av1_inter_slice_bytes(whole, @FRAME_START@, @FRAME_END@),
      [],
    ),
  )
  let decoder = av1_video_decoder()
  let first = match av1_video_decode_frame(decoder, with_header) {
    Some(value) => value
    None => fail("first temporal unit did not decode")
  }
  assert_eq(decoder.sequence is Some(_), true)
  // Cold decoder, header-less unit: nothing can be decoded without a sequence.
  assert_eq(av1_video_decode_frame(av1_video_decoder(), bare) is None, true)
  let second = match av1_video_decode_frame(decoder, bare) {
    Some(value) => value
    None => fail("header-less temporal unit did not reuse the cached sequence")
  }
  assert_eq(second.get_pixel(0, 0), first.get_pixel(0, 0))
  assert_eq(second.get_pixel(31, 17), first.get_pixel(31, 17))
  assert_eq(second.width, first.width)
}

///|
fn av1_inter_slice_bytes(
  source : Array[Byte],
  start : Int,
  end : Int,
) -> Array[Byte] {
  Array::makei(end - start, i => source[start + i])
}

///|
fn av1_inter_concat(left : Array[Byte], right : Array[Byte]) -> Array[Byte] {
  let out = Array::copy(left)
  for byte in right {
    out.push(byte)
  }
  out
}
"""


def main():
    parts = [HEADER]
    units = {}
    for name in NAMES:
        spec = SPECS[name]
        frame_plane = frame_plane_of(spec)
        obu = open(os.path.join(FIX, name + ".obu"), "rb").read()
        ref = open(os.path.join(FIX, name + ".reference.yuv"), "rb").read()
        assert len(ref) == 2 * frame_plane, len(ref)
        parts.append(
            "\n///|\nlet %s_obu : Array[Byte] = [\n%s\n]\n"
            % (name, byte_literal(obu))
        )
        # Both frames' planes are ground truth: frame 0 through the intra
        # pipeline, frame 1 through motion compensation.
        # OBU_TEMPORAL_DELIMITER opens every temporal unit, so the second one
        # is where the inter frame's unit begins.
        delimiters = [
            start for kind, start, _ in obu_chain(obu) if kind == 2
        ]
        units[name] = (delimiters[1], len(obu))
        for index in range(2):
            plane = ref[index * frame_plane : (index + 1) * frame_plane]
            parts.append(
                "\n///|\n/// dav1d native planes for %s frame %d.\n"
                "let %s_frame%d_reference : Array[Int] = [\n  %s\n]\n"
                % (name, index, name, index, rle(plane))
            )
    parts.append(HELPERS)
    for name in NAMES:
        spec = SPECS[name]
        if name in PROBE:
            probe = PROBE_TEMPLATE.replace("@NAME@", name)
            for token, value in [
                ("@PLANE@", str(frame_plane_of(spec))),
                ("@INTER_UNIT@", str(units[name][0])),
                ("@UNIT_END@", str(units[name][1])),
            ]:
                probe = probe.replace(token, value)
            assert "@" not in probe, probe
            parts.append(probe)
            continue
        body = TEST_TEMPLATE.replace("@NAME@", name)
        inter = INTER_TEMPLATE.replace("@NAME@", name)
        for token, value in [
            ("@ORDER_HINT@", spec["order_hint"]),
            ("@WARPED@", spec["warped"]),
            ("@DUAL@", spec["dual"]),
            ("@REF_MVS@", spec["ref_mvs"]),
            ("@HINT_BITS@", spec["hint_bits"]),
            ("@INTER_ORDER_HINT@", spec["inter_order_hint"]),
            ("@SWITCHABLE@", spec["switchable_motion"]),
            ("@KEY_BYTES@", spec["key_bytes"]),
            ("@INTER_BYTES@", spec["inter_bytes"]),
            ("@INTERP@", spec["interp"]),
            ("@KEY_Q@", spec["key_q"]),
            ("@INTER_Q@", spec["inter_q"]),
            ("@WIDTH@", spec["width"]),
            ("@HEIGHT@", spec["height"]),
            ("@BAD_COUNTS@", spec["bad_counts"]),
            ("@PLANE@", str(frame_plane_of(spec))),
            ("@INTER_UNIT@", str(units[name][0])),
            ("@UNIT_END@", str(units[name][1])),
            ("@INTER_DECODABLE@", spec["inter_decodable"]),
            ("@INTER_NOTE@", spec["inter_note"]),
        ]:
            body = body.replace(token, value)
            inter = inter.replace(token, value)
        leftover = [
            line.strip() for line in body.splitlines() if "@NAME" in line or "@KEY" in line
        ]
        assert not leftover, leftover
        assert "@" not in inter, inter
        parts.append(body)
        parts.append(inter)
        if spec["inter_decodable"] == "true":
            anim = ANIMATION_TEMPLATE.replace("@NAME@", name)
            for token, value in [
                ("@PLANE@", str(frame_plane_of(spec))),
                ("@INTER_UNIT@", str(units[name][0])),
                ("@UNIT_END@", str(units[name][1])),
                ("@WIDTH@", spec["width"]),
                ("@HEIGHT@", spec["height"]),
                ("@CHANGED@", spec["animation_changed"]),
                ("@ANIMATION_NOTE@", spec["animation_note"]),
            ]:
                anim = anim.replace(token, value)
            assert "@" not in anim, anim
            parts.append(anim)
    body = SEQUENCE_TEST
    for token, value in sequence_tokens(
        open(os.path.join(FIX, NAMES[0] + ".obu"), "rb").read()
    ).items():
        body = body.replace(token, value)
    assert "@" not in body, body
    parts.append(body)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("".join(parts))
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
