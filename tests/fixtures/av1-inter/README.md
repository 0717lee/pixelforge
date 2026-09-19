# AV1 general (inter-frame) header and motion-compensation fixtures

Phase D of the AVIF decoder is general frame syntax: everything a reduced
still-picture header hides. AVIF still images are always single intra key
frames coded under `reduced_still_picture_header`, so no earlier fixture in this
repository lexes a `frame_type`, an `order_hint`, a reference list,
`interpolation_filter`, `reference_select`, `allow_warped_motion` or
`global_motion` — the frame parser simply began at bit 0 with
`disable_cdf_update`. These streams are the first real temporal units the
project decodes.

Fixtures do not all share a frame size; `inter_edge_64x16` is 64x16 and the rest
are 64x64, and each fixture names its own input source and dimensions.

Each fixture ships the raw OBU (`.obu`), the FFmpeg `trace_headers` transcript
(`.trace.txt`) that acts as the syntax oracle, and dav1d's native planes
(`.reference.yuv`, both frames). Five also ship the deterministic input
(`.input.y4m`) they were encoded from; the spliced one is derived from another
fixture's bytes instead. The generated white-box test
`av1_inter_reference_wbtest.mbt` embeds the OBUs and both frames' planes, asserts
every frame-header field against the transcript, and compares reconstruction
against dav1d sample-for-sample.

## The six fixtures

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
makes aom answer with a dense tree of 4x16 strips inside an 11-byte tile. It is
also the only fixture here whose `interpolation_filter` is *switchable*, so every
block of it reads its own subpel filter choice. Its inter frame is sample-exact on
all three planes. Because the ramp repeats every 32 samples, the right-hand blocks
can be served either by the +3-pixel vector or by a −29-pixel one, and the
encoder picks the latter: this is the fixture that checks a NEARMV block resolving
to stacked candidate 1 rather than candidate 0.

`inter_still_64x64.obu` repeats one frame verbatim. The encoder answers with an
18-byte temporal unit whose fixed `interpolation_filter` is the 8-tap smooth
kernel, `loop_filter_level[0..1]` are both zero (so `loop_filter_level[2..3]` are
not even signalled), and the inter frame reconstructs **sample-exactly on all
three planes** against dav1d.

`inter_shift_64x64.obu` translates a small-amplitude band-limited wave by a true
2.5 luma pixels, which forces a fractional motion vector, a switchable
interpolation filter and a non-zero `loop_filter_level[1]` (4, on Y horizontal
edges only - `loop_filter_level[2..3]` are both zero, so chroma is not deblocked).
Its inter frame is also sample-exact on all three planes, so sub-pel
interpolation, reference masking and the frame filters agree with dav1d. The
strength itself buys nothing here: rewriting `loop_filter_level[1]` from 4 to 40
or 63 leaves dav1d's output byte-identical, because a band-limited wave is locally
linear and the deblocking kernels preserve a ramp. That is why the loop-filter
fixture is not based on this stream.

`inter_edge_64x16.obu` is the 64x16 case, deliberately smaller than the rest. Its
content is the same sawtooth shifted by 3 pixels, so the last columns wrap around
to the values at the left edge: no clamped motion compensation can produce them,
and aom instead codes a large negative vector for the final 4x16 strip to reach
back into the frame. That vector is magnitude class 4, which is what exposed the
`read_mv_component` row-index defect - the test therefore pins the whole picture,
every sample of all three planes, against dav1d.

`inter_lf_delta_64x64.obu` is the loop-filter-delta fixture, and the only one that
is not a verbatim encoder output: it is `inter_minimal_64x64.obu` with the inter
frame's loop-filter fields rewritten bit by bit
(`splice_loop_filter_deltas` in the generator). The rewrite is needed because this
`aomenc` will not produce the syntax at all - it writes
`loop_filter_delta_update = 0` whatever `--delta-lf-mode` says, and picks
`loop_filter_level[0..1] = 0` for every stream here, which leaves the frame
undeblocked (and `loop_filter_level[2..3]` unsignalled, AV1 §5.11 loop filter params). The splice touches only fixed-width fields at the start
of the uncompressed header - four `f(6)` levels, ten `f(1)` flags and their
`su(1+6)` values - and re-pads the header so that it still ends on a byte
boundary; the tile's entropy-coded bytes are copied unchanged. FFmpeg's transcript
then reads back exactly the configuration that was written, dav1d decodes the
result, and its planes are the fixture's ground truth like every other fixture's.

What it covers is AV1 §7.14.5 step 4.c: levels 30/33 on Y (so the two directions
get different `nShift`, 0 and 1) and 20/16 on U/V, with
`loop_filter_ref_deltas` +3, -6, +5, -2 on rows INTRA, LAST, BWDREF and BWDREF2
and `loop_filter_mode_deltas` +2 and -4. The rows an inter block reaches - LAST
and modeType 1 - are the negative ones, which is what makes the sign convention
observable. `su(1+6)` is a seven-bit two's complement value: parsing the same bits
as sign-and-magnitude turns -6 into -58 and -4 into -60, and that misread leaves
108 U and 50 V samples wrong against dav1d. Skipping step 4.c altogether, so that
every edge is filtered with the INTRA row and no mode delta, leaves 41 luma and 24
V samples wrong. Both numbers were measured by mutating the decoder, so the
assertions are evidence about the arithmetic and not a coincidence of a frame that
happens never to be deblocked.

## What these fixtures do not cover

`read_mv_component` is only exercised at magnitude **class 1 and class 4** (the
24-eighth-pel translation and the 232-eighth-pel reach-back). The classes nobody
codes fall into two different kinds of hole, and only the first one is the
encoder's fault.

**Classes 5 to 10 are out of reach of this build.** The cause is measured rather
than suspected: **this `aomenc` searches about +/-32 pixels of motion**, and class
5 is where the magnitudes pass 32 pixels, so a coded vector beyond class 4 does
not exist however the source is shaped. Two observations pin that ceiling: a
source translated by 33 pixels is coded as magnitude 256 (the top of class 4,
i.e. the search stopped at its range limit), and sources translated by 40 pixels
or more are coded as `NEARESTMV` with `mv = (0, 0)` on every block - the encoder
prefers to hand back a verbatim copy of the key frame over spending bits on a
vector it cannot find. Class 10 is the extreme case of the same unreachable band:
it is the largest class, and it codes ten magnitude bits. Measured attempts, all
with the minimal flag set, `-p1`, `--cpu-used=0`, `--cq-level=32`:

- sawtooth sources cannot reach class 5 structurally: their 32-sample period
  makes a short vector predict exactly as well as a long one;
- smooth non-periodic waves translated by 33-48 pixels on 64x16/64x64/128x16
  frames encode, but the answer is a class-4 vector, `NEARESTMV`, or intra blocks,
  and the ones that do move leave 15-53 luma samples wrong;
- band-limited translated texture (sums of mutually incommensurate sinusoids),
  which is the content that makes residual far more expensive than one long
  vector, aborts the encoder at 64x16 and at every width from 160 to 512 whenever
  the total swing reaches roughly 44 codes; at amplitudes low enough to survive it
  collapses to the `mv = (0, 0)` copy described above;
- `--static-thresh=0`, the only exposed knob that could push the motion search
  further, leaves the output byte-identical.

Closing that band needs either an encoder build whose search range is configurable,
or a synthetic tile whose bits are written by hand - `scripts/craft_av1_fixture.py`
already carries an `MsacEncoder`, so most of the tooling for the second route
exists. But a hand-written tile only proves the reader agrees with whatever writer
produced the bits, so it is a regression fence, not external evidence.

**Classes 0, 2 and 3 are reachable and merely unused.** They sit *inside* the
measured search ceiling, so nothing about the toolchain keeps them out of the
suite: class 0 is the smallest band (1..16 eighth-pel per AV1 §5.11.25, so up to
two pixels, and with `allow_high_precision_mv = 0` only on quarter-pel steps -
which means a non-integer sub-2-pixel displacement), class 2 is a 4-8 pixel shift
and class 3 an 8-16 one - less than `inter_edge_64x16` already asks its encoder
for, not more. A fixture translating a non-periodic source by about 6 or 12 pixels
is the obvious way to code them; that has not been tried, and it is a choice about
content rather than a limit. Worth saying precisely, because it is easy to
overclaim: class 4 already reads `mv_bit` rows 0 through 3, so these three classes
would exercise **no** row index the fixtures do not already touch. What they would
add is the class symbol itself - the eleven-symbol `mv_class` tree, class 0's
separate `mv_class0_bit` / `mv_class0_fr` sub-syntax, and the magnitude arithmetic
at the class boundaries.

So the class-bound handling in `read_mv_component` rests today on the normative
text (AV1 §5.11.25) plus classes 1 and 4 of real traffic.

`inter_lf_delta_64x64` covers step 4.c, not step 4.b: the inter frame codes no
intra blocks, so `loop_filter_ref_deltas[INTRA_FRAME]` and
`loop_filter_mode_deltas[0]` - and reference rows 4 to 7, which no block names -
are parsed and stored but never select a strength. Measured, not assumed: adding
20 to the intra branch leaves every sample of the fixture unchanged. Equally, the
§7.14.2 widening that sends a chroma edge to the `row | subY`, `col | subX` luma
unit is not pinned either - removing the `| subX` / `| subY` leaves the fixture
exact, because this frame's motion field is uniform across each chroma 8x8. Both
need a fixture that mixes intra and inter blocks inside one chroma block.

## Reproduce and check

```powershell
python scripts/generate-av1-inter-reference.py
python scripts/generate-av1-inter-reference.py --check
python scripts/emit-av1-inter-test.py
```

The input regenerates byte-identically, so `--check` re-derives it, re-encodes
with the manifest command and verifies the OBU, the per-field transcript
expectations and dav1d's output length. `inter_lf_delta_64x64` is re-spliced from
the committed `inter_minimal_64x64.obu` instead of re-encoded, which makes the
splice itself part of what `--check` proves. The emitter turns the verified
evidence into the committed MoonBit test.

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
