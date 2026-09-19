# AV1 general (inter-frame) header and motion-compensation fixtures

Phase D of the AVIF decoder is general frame syntax: everything a reduced
still-picture header hides. AVIF still images are always single intra key
frames coded under `reduced_still_picture_header`, so no earlier fixture in this
repository lexes a `frame_type`, an `order_hint`, a reference list,
`interpolation_filter`, `reference_select`, `allow_warped_motion` or
`global_motion` — the frame parser simply began at bit 0 with
`disable_cdf_update`. These streams are the first real temporal units the
project decodes.

Each fixture ships the raw OBU (`.obu`), the deterministic input (`.input.y4m`),
the FFmpeg `trace_headers` transcript (`.trace.txt`) that acts as the syntax
oracle, and dav1d's native planes (`.reference.yuv`, both frames). The generated
white-box test `av1_inter_reference_wbtest.mbt` embeds the OBUs and both frames'
planes, asserts every frame-header field against the transcript, and compares
reconstruction against dav1d sample-for-sample.

## The four fixtures

`general_inter_64x64.obu` is one untouched libaom encode with the default tool
set, so frame 1 is an inter frame that reads the whole general grammar:
`frame_refs_short_signaling`, seven `ref_frame_idx`, `allow_high_precision_mv`,
a switchable `interpolation_filter`, `is_motion_mode_switchable`,
`use_ref_frame_mvs`, `reference_select`, `allow_warped_motion` and seven
`is_global` bits. Its sequence header also carries every inter tool flag.

`inter_minimal_64x64.obu` disables order hints, warped motion, reference-frame
MVs, dual filter and every compound and global-motion variant, so each of those
frame-header fields turns from a *read* into a *derivation* and the pair covers
both sides of every gate. Its input is a 3-pixel translating sawtooth ramp, which
makes aom answer with a dense tree of 4x16 strips inside an 11-byte tile; the
block stage reads a coherent skip sequence with the true motion but overruns the
tile's trailing-bit budget, so that frame is still refused. That overrun is the
open defect, not a design refusal.

`inter_still_64x64.obu` repeats one frame verbatim. The encoder answers with an
18-byte temporal unit whose fixed `interpolation_filter` is the 8-tap smooth
kernel, `loop_filter_level[0..1]` are both zero (so `loop_filter_level[2..3]` are
not even signalled), and the inter frame reconstructs **sample-exactly on all
three planes** against dav1d.

`inter_shift_64x64.obu` translates a small-amplitude band-limited wave by a true
2.5 luma pixels, which forces a fractional motion vector, a switchable
interpolation filter and non-zero `loop_filter_level[1]` (chroma deblocking is
live at strength 4). Its inter frame is also sample-exact on all three planes, so
sub-pel interpolation, reference masking and the frame filters agree with dav1d.

## Reproduce and check

```powershell
python scripts/generate-av1-inter-reference.py
python scripts/generate-av1-inter-reference.py --check
python scripts/emit-av1-inter-test.py
```

The input regenerates byte-identically, so `--check` re-derives it, re-encodes
with the manifest command and verifies the OBU, the per-field transcript
expectations and dav1d's output length. The emitter turns the verified evidence
into the committed MoonBit test.

## Encoder constraint

The libaom build in `D:\ProgramData\anaconda3\Library\bin` segfaults on the
third frame of any encode, so every fixture here is exactly one key frame plus
one inter frame. Deeper reference structures (alt-ref, B-frames, more than one
refresh generation) will need a different encoder build or hand-crafted
temporal units; the multi-frame stages of Phase D should plan for that.

The same build also segfaults at teardown on *some* two-frame encodes: the
`shift` source crashes at 44-count / period-48 contrast and survives at
8-count / period-64, which is why the amplitudes and periods in `encode_input`
are pinned rather than chosen for looks. Probe candidate content with a throwaway
encode before adding a fixture that leans on it.
