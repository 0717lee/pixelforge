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
(`.reference.yuv`, both frames). The six derived from the `--i420` Y4M path also
ship the deterministic input (`.input.y4m`) they were encoded from;
`inter_lossless_64x64`, `inter_obmc_64x64`, `inter_screen_content_64x64`,
`inter_palette_64x64`, `inter_warped_64x64` and `inter_temporalmv_64x64` ship
theirs as raw planar `.input.yuv`, because they were encoded through aomenc's
`-w`/`-h` raw input path rather than a Y4M muxer.
`inter_lf_delta_64x64`, `inter_primary_ref_64x64` and
`inter_cdf_inherit_64x64` are derived from another fixture's bytes instead. The generated white-box test
`av1_inter_reference_wbtest.mbt` embeds the OBUs and both frames' planes, asserts
every frame-header field against the transcript, and compares reconstruction
against dav1d sample-for-sample.

## The fixtures

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

`inter_primary_ref_64x64.obu` is the frame-context inheritance fixture, and unlike
the loop-filter one it moves no bits at all: `patch_header_fields` rewrites two
fixed-width header fields in place on `inter_minimal_64x64`, so the stream differs
from its base in exactly two bytes (16 and 74) and every tile byte is untouched.
AV1 5.11 reads a 3-bit `primary_ref_frame` on an inter frame that is not error
resilient, and `PRIMARY_REF_NONE` (7) means "start from scratch" while any smaller
value means "load the frame context of `ref_frame_idx[that]`" - the non-coefficient
and coefficient distributions via `load_cdfs`, and the block context via
`load_previous`. This encoder always answers 7, because inside a two-frame group
there is nothing worth inheriting.

The patch sets the inter frame's field to 0 (which names the key frame, since
`ref_frame_idx[0]` is 0 and the key frame refreshed all eight slots) and *also*
freezes the key frame's `disable_frame_end_update_cdf` to 1. The second half is not
decoration: those tile bits were coded against freshly initialised distributions, so
without freezing the key frame leaves its own adapted ones behind, and inheriting
them makes the whole frame diverge - measured, 5035 of 6144 samples move. With the
key frame's frame-end update frozen its stored distributions *are* the fresh ones,
and dav1d's output on the patched stream is then **bit-identical to the base
stream's** on both frames (verified for the `inter_minimal` and `inter_still`
shapes alike), which is what makes this stream usable as a first rung: a real
`primary_ref_frame != NONE` header that is decoded and compared sample-for-sample.

What it pins is the branch - the field is read, the frame is not mis-lexed and is not
refused. What it deliberately does **not** pin is the *contents* of a snapshot,
because the distributions it inherits were chosen to equal a fresh start. The
substance is the next fixture.

`inter_cdf_inherit_64x64.obu` is that next fixture: the same field rewritten on its
own, with the key frame left alone, so exactly **one byte** (74) separates it from
`inter_minimal_64x64`. Its tile bits were still coded against freshly initialised
distributions, but the header now loads the key frame's *adapted* ones, so a decoder
that starts from scratch disagrees with dav1d across most of the picture - measured
5762 of 6144 samples. That disagreement is not hidden: the generated test asserts the
per-plane counts (`3992, 842, 928`) explicitly, and they are the acceptance target for
the AV1 §7.21 entropy-state snapshot, which must drive them back to `0, 0, 0`. This
fixture is a stream the encoder would never emit but a stream that is legal and
semantically determined, and dav1d's planes are its truth like every other one's.

`inter_compound_64x64.obu` is `inter_shift_64x64` with `reference_select`
patched from 0 to 1 - again **one byte**, and again a stream libaom would not
emit (it never picks compound for this two-frame group). With the flag on, the
block layer reads `comp_mode` and the tile bytes that were coded for a
single-reference frame are decoded as compound ones, so this fixture pins the
whole compound path against dav1d: `comp_ref_type`'s unidirectional or
bidirectional pair, both reference names, both motion vectors (fresh
`read_mv` per list or the nearest candidate of each), the `compound_mode`
symbol, the interpolation-filter context's compound row group, and the
COMPOUND_AVERAGE blend itself. The frame's sequence header has both
masked-compound switches off, so `read_compound_type` resolves to
COMPOUND_AVERAGE without a symbol; a stream that asks for a wedge or a
distance weighting is still refused whole.

`inter_skipmode_64x64` is the only three-frame fixture here, and it has to be:
skip mode's derivation needs two references with order hints on either side of
the frame's own hint, which a two-frame encode cannot express. The generator
encodes the usual two-frame `shift` stream with `--enable-order-hint=1`,
appends a **byte-for-byte copy** of the last inter frame behind a fresh
temporal delimiter, and rewrites five header bits: the key frame's order hint
moves ahead of the copy's, the copy's `LAST2` is repointed at the middle
frame's slot, the copy's own hint is set between the two, and
`reference_select` plus `skip_mode_present` are set. All three tile payloads
are untouched, so the appended frame decodes compound-free blocks that name
their references and vectors from the SkipModeFrames pair. Its test compares
**all three frames**, which also pins the reference-slot state carried across
them. libaom cannot produce this stream itself - it never emits skip mode on
these tiny groups and this build crashes past two frames.

`inter_distcomp_64x64` reaches the `comp_mode` / `compound_idx` grammar on a
sequence that carries the switches. Its base is encoded with order hints and
both jnt-comp switches on - tools the group never uses - and one header bit is
rewritten, `reference_select` 0 to 1, so the block layer reads `comp_mode`
where the base read the single-reference tree. The sequence's
`enable_masked_compound` stays off, which is what keeps `read_compound_type`
from reading `comp_group_idx` and pointing at a wedge or a difference-weighted
block: those need the mask generation and are refused.

It is worth recording plainly what this fixture does **not** cover: no block in
it selects compound, so `compound_idx` is never read and the distance-weighted
blend is never entered. The encoder never picks compound on a two-frame group
(both references alias the one key frame, so a compound prediction is an
average of a picture with itself), and the patched bits happen to decode
`comp_mode` as zero everywhere. The blend itself is a port of libdav1d's and
remains unexercised; the HANDOFF records how to build the stream that would
exercise it.

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
The per-buffer CDF snapshot and restore is still unimplemented, so
`inter_cdf_inherit_64x64` currently decodes with the fresh state and its pinned
`3992, 842, 928` is a *known-wrong* reconstruction held as a fence rather than as
acceptance; `load_previous_segment_ids` is likewise unproven (every fixture here runs
with `segmentation_enabled = 0`).

`load_previous`'s **block context** is a different case, and is recorded here as a
conclusion rather than a gap. On a conforming single-tile stream it cannot be made
visible by any fixture: AV1's decode order means the left and above neighbours of
every block are already written by the current frame, and positions outside the frame
take the "unavailable" inference, so nothing ever reads the inherited `MiSizes`,
`Skips`, `SkipModes`, `TxTypes`, `RefFrames` or `Mvs`; the state that does reach back
into a previous frame is the temporal motion-vector data, and that is the §11
`ref_frame_mvs` mechanism, not `load_previous`. The measurement agrees: freezing only
the distributions, so that the sole difference is the inherited block context, moved 0
of 6144 samples on both the `inter_minimal` and `inter_still` shapes. If a path
appears that genuinely reads previous-frame block state the current frame has not
written - multi-tile or tile-group resynchronisation, error-resilient recovery after a
dropped tile, or temporal MV projection - that is when this conclusion needs testing.

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

`inter_lossless_64x64.obu` is the lossless rung: the same `MINIMAL_FLAGS` set plus
`--lossless=1`, so both frames carry `base_q_idx == 0` and the coefficient path runs
without quantisation error. dav1d 1.2.1's planes for the inter frame are the truth and
the generated test asserts `[0, 0, 0]` per plane: motion compensation, the residual and
the frame filters must all agree exactly, because a lossless reconstruction has no
quantisation slack to hide a wrong prediction or a mis-scaled coefficient. This fixture
pins that `coded_lossless` inter frames are reconstructed rather than refused; the
`av1_inter_frame_supported` gate no longer lists `coded_lossless` because the block
stage handles it sample-exactly.

`inter_obmc_64x64.obu` is the overlapped-block-motion-compensation rung: the same
`MINIMAL_FLAGS` set with only `--enable-obmc=1` added, which is the single flag
that turns the frame header's `is_motion_mode_switchable` from a derivation into
a read. Its input is the decoded pair of `general_inter_64x64` re-fed as a
source, so frame 0 is a key frame the encoder already knows it can predict from
exactly. The inter frame partitions into four 32x32 blocks; the top-right one at
MI row 0, column 8 carries `use_obmc = 1`, so `read_motion_mode` selects OBMC for
it and the overlap blending process runs on all three planes: the left pass
blends the eight columns it shares with the top-left block, and the above pass
contributes nothing because that block sits on the frame's top row
(`AvailU` is 0). dav1d 1.2.1's planes are the truth and the generated test
asserts `[0, 0, 0]` per plane.

This fixture is the one that caught a silent-wrong-picture bug rather than a
rejection: `read_motion_mode` used to read the `use_obmc` symbol, set
`motion_mode = 1`, and then report success, so the block was predicted as if the
mode were SIMPLE. Luma still matched dav1d (the neighbour's prediction happened
to round to the same samples where the two overlap strips met), which is exactly
the kind of near-miss that makes an unimplemented tool dangerous: the frame
decoded, most of it was right, and only the blend columns were wrong - 16 luma
and 48 chroma samples. `av1_obmc_blend` now implements the two passes of
AV1 §7.11.3.9, and `av1_inter_frame_supported` no longer lists
`is_motion_mode_switchable`.

## Above-pass coverage

`inter_obmc_64x64` only exercises the **left** pass: its OBMC block sits on the
frame's top row, so `AvailU` is 0 and the above pass never runs. The libaom build
in `D:\ProgramData\anaconda3\Library\bin` segfaults before flushing on most other
two-frame encodes (five of seven candidate sources produced a zero-length OBU),
so a second fixture with a lower-row OBMC block could not be produced from it.
`av1_obmc_wbtest.mbt` drives `av1_obmc_blend` directly instead and pins the above
pass on both luma and chroma: the strip geometry (`predW` from `step4`, `predH`
capped at `h >> 1` and `32 >> subY`), the mask being indexed by **row** rather
than by column, the `Round2(m * own + (64 - m) * neighbour, 6)` rounding, and the
fact that an intra neighbour contributes nothing. Disabling the above pass makes
the two positive cases fail with the exact expected values, so they are not
passing by accident.

`inter_screen_content_64x64.obu` is the screen-content rung:
`--tune-content=screen` sets `seq_force_screen_content_tools` to SELECT, so the
inter frame reads `allow_screen_content_tools = 1` from the bitstream instead of
deriving it. On an inter frame that flag does two things: it derives
`force_integer_mv`, which the MV reader already handles, and it lets
`intra_block_mode_info` read `palette_mode_info` for intra blocks inside the
frame. Both are implemented, so the frame reconstructs sample-exactly.

`inter_palette_64x64.obu` is the same tool set over a source whose inter frame
carries a three-stripe flat patch in the bottom-right quadrant, so one intra
block inside the inter frame actually selects palette (two luma colours, no
chroma palette) and the index-map prediction runs. This is the fixture that
pins the palette path of an inter frame; `--cpu-used=4` is required because this
libaom build segfaults before flushing at `--cpu-used=0..3` for this source.

Both fixtures also pin `allow_intrabc = false`: AV1 §6.8.2 reads that bit only
under `if ( FrameIsIntra )`, so it can never be set on an inter frame, and the
gate entry in `av1_inter_frame_supported` that used to list it was dead code.

\`inter_warped_64x64.obu\` is the warped-motion rung: the same minimal tool set
with only \`--enable-warped-motion=1\` added. That flag makes the frame header
derive \`allow_warped_motion\`, so \`read_motion_mode\` takes the **three-symbol**
\`motion_mode\` branch whenever \`find_warp_samples\` reports a candidate, instead
of the binary \`use_obmc\` one. Both symbol shapes are in the stream, and the
frame reconstructs sample-exactly because no block selects LOCALWARP.

\`find_warp_samples\` itself is pinned by \`av1_warp_samples_wbtest.mbt\`, because
it reads no entropy symbols and a wrong candidate count would desynchronise the
symbol stream rather than merely pick a worse predictor. Its scan limit is
derived, not measured: a 64x64-superblock profile caps a block at 16 four-by-four
units per axis and the scan steps by at least the smallest block's two units, so
18 samples can never be truncated and the result is independent of the
unspecified \`LEAST_SQUARES_SAMPLES_MAX\`.

A block that does select LOCALWARP is refused whole: the warp estimation and the
warped prediction grid are not implemented, and this repository's rule is that a
legal but unimplemented tool must not be silently decoded into a wrong picture.

## The fourteenth fixture

`inter_temporalmv_64x64.obu` is the temporal-motion-vector rung: the same minimal
tool set with `--enable-order-hint=1 --enable-ref-frame-mvs=1` added, which is the
flag pair that turns `use_ref_frame_mvs` from a derivation into a read. Order
hints have to travel with it - AV1 §6.8.13 reads the bit only on an inter frame
whose sequence enables them - so this is the first fixture in the repository whose
inter frame carries a non-zero `order_hint` (1) at all. The frame sets
`reference_select = 0` and `skip_mode_present = 0`, so no compound block reaches
the candidate stack and the temporal scan is a single-reference lookup.

What it pins is the whole chain: `motion_field_estimation` (§7.9.1) projects the
key frame's buffer while the uncompressed header is read, and `av1_temporal_scan`
(§7.10.2.5) pushes the projected vectors between the near weighting and the
corner scan of `av1_find_mv_stack`. The key frame's saved field is intra
everywhere, so its projection writes no usable cell; what the scan contributes
here is `ZeroMvContext = 1` from the block's own cell, which is a *read* quantity
- the wrong context mis-lexes the inter mode tree instead of merely picking a
worse predictor. Both halves were measured: deleting the whole scan makes the
frame fail to decode at all, and deleting only that assignment fails the fixture
too. dav1d 1.2.1's planes are the truth and the generated test asserts
`[0, 0, 0]` per plane, so `av1_inter_frame_supported` no longer lists
`use_ref_frame_mvs`.

The scan's remaining behaviour - the candidate push, the weight-2 merge, the
precision lowering, the stride, the same-superblock extension and the two refusal
paths - is pinned by `av1_mv_temporal_wbtest.mbt`, because this stream's grid
never holds a usable vector and cannot reach them. What no fixture reaches yet is
a projection that *does* land: the only reference here is a key frame, and the
libaom build in `D:\ProgramData\anaconda3\Library\bin` cannot produce the
two-inter-frame sequence a live projection would need. `motion_field_estimation`
and `av1_mv_projection` therefore rest on the normative text plus their own unit
tests until an encoder build can emit that stream.
