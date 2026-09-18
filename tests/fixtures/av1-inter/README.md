# AV1 general (inter-frame) header and motion-compensation fixtures

Phase D of the AVIF decoder is general frame syntax: everything a reduced
still-picture header hides. AVIF still images are always single intra key
frames coded under `reduced_still_picture_header`, so no earlier fixture in this
repository lexes a `frame_type`, an `order_hint`, a reference list,
`interpolation_filter`, `reference_select`, `allow_warped_motion` or
`global_motion` — the frame parser simply began at bit 0 with
`disable_cdf_update`. These two streams are the first real temporal units the
project decodes.

Each fixture ships the raw OBU (`.obu`), the deterministic input (`.input.y4m`),
the FFmpeg `trace_headers` transcript (`.trace.txt`) that acts as the syntax
oracle, and dav1d's native planes (`.reference.yuv`, both frames). The generated
white-box test `av1_inter_reference_wbtest.mbt` embeds the OBUs and the key
frame's planes, and asserts every frame-header field against the transcript.

## The two fixtures

`general_inter_64x64.obu` is one untouched libaom encode with the default tool
set, so frame 1 is an inter frame that reads the whole general grammar:
`frame_refs_short_signaling`, seven `ref_frame_idx`, `allow_high_precision_mv`,
a switchable `interpolation_filter`, `is_motion_mode_switchable`,
`use_ref_frame_mvs`, `reference_select`, `allow_warped_motion` and seven
`is_global` bits. Its sequence header also carries every inter tool flag.

`inter_minimal_64x64.obu` disables order hints, warped motion, reference-frame
MVs, dual filter and every compound and global-motion variant, and turns on
`--error-resilient=1`. That flips those same fields from *read* to *derived*, so
the pair covers both sides of each gate. It also enables frame-id numbering,
which adds `current_frame_id` and the per-reference `delta_frame_id_minus1`
fields that the general path must skip to stay aligned.

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
