# Changelog

## Unreleased
- Closed the global-motion gate for translation models, and reached one at all.
  libaom writes `is_global` as zero for every reference of these two-frame
  groups whatever the encoder flags say - the neighbour-based motion predictor
  makes a uniform translation cheaper per block than the model's own ~30 bits -
  so `inject_global_motion` builds the stream instead of encoding it: it sets
  `is_global(LAST_FRAME)` on `inter_minimal_64x64`, codes a TRANSLATION model as
  two `decode_signed_subexp_with_ref` deltas (3 and -5, a 6/8-pel row and a
  -10/8-pel column displacement) against the inherited default model, and
  shifts the rest of the header by the inserted width. The tile payload is
  byte-aligned behind the header and is copied through untouched, which is what
  makes the insertion measurable: a wrong width desynchronises the header and
  the frame stops matching. `inter_globalmv_64x64` is then pinned against
  dav1d at [0, 0, 0] per plane, with the model itself asserted on the parsed
  header (`gm_type`, both shifted deltas, the byte the tile starts on). The
  frame gate in `av1_inter_frame_supported` now refuses only a rotate-zoom or
  affine model, which needs the warped prediction grid a LOCALWARP block needs
  too; `av1_setup_global_mv` already derives every model at the block centre.
  One consequence is worth recording: a translation model makes a
  GLOBAL(Global)MV block read a subpel filter symbol that the identity model
  skips, so the symbols after those blocks re-symbolise into a different legal
  decode - the reference planes are committed for that decode, not for the
  base's.
- - Closed the stage-D animation integration seam with two three-frame tests. The
  animated-AVIF seam (`avif_decode_animation_samples`) is now driven over the
  three temporal units of `inter_skipmode_64x64`, whose third sample names both
  earlier frames as references through skip mode: one stateful decoder walks
  `[0, 40, 80]` at a 1000 Hz timescale, and every returned RGBA frame is
  compared sample for sample against `av1_yuv_highbd_to_rgba` of that same
  frame's dav1d planes, so the reference-slot state the third frame needs is
  pinned through the only sequence that can reach it. Alongside it, a container
  test builds a real BMFF file around those units - `moov>trak>mdia` with
  `mdhd`/`stts`/`stsz`/`stco` and an `mdat` holding one unit per sample, one
  chunk per sample with per-sample sizes - and walks it through
  `avif_animation_descriptor`, `avif_animation_sample_payloads`,
  `avif_decode_animation` and `avif_decode_animation_frame`: three frames at
  timestamps 0/40/80, the key frame matching an independent single-sample
  `av1_decode` and all three matching the timing-table entrypoint fed the same
  units. Two layout traps are worth recording: this package's `stsz` reader
  treats the first four payload bytes as version/flags, so a per-sample size
  table must start with a second zero word; and the stream's temporal units
  split at 84/110/132, each inter unit carrying its own temporal delimiters.
- `segmentation_params` is now parsed in full (AV1 §6.10.9): the enable bit,
  the update-map/temporal/data flags, and all eight segments' eight feature
  levels with the `su`/`f` value reads and the clip. The parsed result is kept
  on the frame header. The frame is still refused when a map update or any
  feature is active, because the per-block `segment_id` symbol and the feature
  application are not implemented; a segmentation that updates nothing and
  enables nothing decodes unchanged. Closing the gate for real needs a stream
  whose encoder emits segmentation, and this aomenc build has no switch for it:
  patching the enable bit alone makes every non-skip block read a `segment_id`
  symbol, which shifts the tile entropy enough that even dav1d rejects the
  frame.
- `inter_diffwtd_64x64` pins the difference-weighted blend end to end against
  dav1d at [0, 0, 0]. It needs three bit rewrites, the third of which is a new
  capability in the generator: `tile_patches` flips one bit inside a frame's
  tile entropy, which changes how the symbols after it decode. That is the only
  way to reach a masked blend at all, because libaom never emits a compound
  block for a two-frame group - with the tile bit unchanged, `comp_mode` decodes
  zero everywhere and `comp_group_idx` is never read.
- Found and fixed five more long-standing bugs along the way, again all on a
  path only a compound block reaches: a compound block in GLOBAL_GLOBALMV takes
  each list's frame-level global motion rather than a stack candidate; the
  NEAREST_NEWMV and NEAR_NEWMV modes mark a neighbour as new-motion for the
  depth-reference index and the context, matching libdav1d's `0xbc` mode mask;
  the compound `comp_inter_mode` row is the reference-motion context halved, so
  2 and 3 share a row; the near-motion reference context scales the match count
  by three before saturating at four; and the compound extended candidate merge
  read its different-reference scratch slots from the wrong offset.
- `_refs/mvstack_sim.py` had the same two gaps (its `NEWMV_MODES` set and the
  reference-motion scaling). Both are corrected against libdav1d, and the six
  affected oracle vectors in `av1_mv_oracle_wbtest.mbt` are regenerated - five of
  them only in the raw new-motion count, which the entropy context itself does
  not consult beyond whether it is zero.
- Implemented the masked-compound grammar and blends, and closed the
  `enable_masked_compound` frame gate. `read_compound_type` now reads
  `comp_group_idx`, and when a block asks for a masked blend it reads
  `compound_type` (unless the block size has no wedge bits, in which case only
  the difference weighting exists) and then `wedge_index`/`wedge_sign` or
  `mask_type`. `av1_wedge_mask.mbt` gained the difference-weight mask of
  §7.11.3.12, whose chroma planes take the luma mask averaged down to their
  sample grid exactly as the wedge variant does. `general_inter_64x64`, which
  carries the switch, now reconstructs against dav1d instead of being refused.
- Fixed four long-standing bugs on the compound path, none of which any earlier
  fixture could reach because no stream carried a compound block:
  `comp_ref_type` zero means the unidirectional pair, not one; the compound
  mode numbering follows libdav1d's `CompInterPredMode`
  (NEAREST_NEWMV is 2 and NEW_NEWMV is 7, so the depth-reference tree, the
  per-list fresh vectors and the subpel-filter decision were all reading the
  wrong mode); a compound block reads no subpel filter when both of its lists
  are the frame's global motion; and the compound extended candidate set of
  §7.10.2.12 is now built instead of refusing the frame.
- Implemented the interintra blend and closed its gate. A block that selects
  `interintra` now rebuilds itself as an intra prediction of its reconstructed
  neighbourhood mixed into the motion-compensated one (AV1 §7.11.3.10,
  §7.11.3.14): the intra predictor runs on the plane's own grid, the weight is
  the `Ii_Weights_1d` ramp for the non-wedge variant or the `WedgeMasks`
  table for the wedge one, chroma takes the luma wedge mask averaged down to
  its sample grid with the spec's rounding, and `interPostRound` is zero for a
  single-reference block so the inter prediction blends unrounded.
  `av1_wedge_mask.mbt` builds the wedge tables: the three 1-D master columns,
  the six 64x64 directions, the `Wedge_Codebook` rows, and the per-block
  sign convention of §7.11.3.11 - a mask whose border row and column average
  below 32 is stored complemented.
- Found and fixed two bugs while wiring it. `wedge_interintra` and `wedge_index`
  are indexed by the **block size** (AV1 §9.3.8-9), not by a shape row; an
  earlier round read them through a tall/wide/square helper, which would have
  desynchronised the entropy decoder on any interintra block. And an
  interintra block reads **no** `motion_mode` symbol at all (AV1 §5.11.26) -
  its second list is the intra prediction, so the overlapped/warped choices do
  not apply to it.
- `inter_interintra_64x64` now reconstructs instead of refusing: its inter
  frame compares sample-exact against dav1d at [0, 0, 0] on all three planes.
  One 32x32 block selects the mode and selects the wedge variant, so both the
  ramp and the mask are pinned by real pixels. Its earlier refusal test was
  also wrong about the fixture split (byte 84 instead of byte 71), which made
  it vacuous; the new test walks the two temporal units as the reference
  decoder does.
- Implemented the interintra grammar and opened its gate. A frame whose
  sequence header carries `enable_interintra_compound` now reads
  `interintra` for every inter block from 8x8 to 32x32, with
  `interintra_mode`, `wedge_interintra` and `wedge_index` when a block
  selects it; the row is dav1d's `ymode_size_context` minus one, which is
  not the spec's `Size_Group - 1` for every block size (the handoff records
  the mapping, and the earlier note that the three references disagreed on
  the default table was wrong - dav1d's `CDF1(x)` is `32768 - x`, so the
  tables agree). When this landed, a block that actually selected the mode
  refused the frame whole, because the blend needs the intra predictor in the
  inter path; that fence is replaced by the blend itself further down.
  `inter_interintra_64x64` pins it: one equal-width bit in the sequence
  header, the grammar read, dav1d's planes committed.
- Implemented the distance-weighted compound blend and its syntax, and fixed a
  real bug found on the way: `compound_idx` and `compound_type` are different
  symbols with different tables (AV1 §5.11.25 / §8.3). The distance-versus-
  average choice reads `TileCompoundIdxCdf[ctx]` with the distance-balanced
  context - three when the two references sit at equal distance, plus each
  neighbour's own `compound_idx`, or one for a single-reference neighbour naming
  ALTREF - and an earlier round mistakenly read that choice from
  `TileCompoundTypeCdf[MiSize]` instead. The wedge-versus-difference choice is
  the one that uses `compound_type`. `comp_group_idx` likewise has its own
  table and context, and both compound-symbol grids are now stored in the
  motion field so the next compound block's contexts can read its neighbours'.
  The blend scales each list's interpolation by its distance weight through the
  quantized tables of §7.11.3.15 (`quantDistWeight`, `quantDistLookup`), one
  rounding step later than the average, matching libdav1d's blend.
- `inter_distcomp_64x64` carries the grammar it moved: an order-hint plus
  jnt-comp encode with `reference_select` patched on, whose inter frame matches
  dav1d at [0, 0, 0]. It does not exercise the distance blend - no block in it
  selects compound, so `compound_idx` is never read - because the encoder never
  picks compound on a two-frame group, where both references alias the one key
  frame. The blend itself therefore stays unexercised until a stream reaches
  it; the handoff records the recipe (a three-frame splice, whose two
  references carry different order hints) and the search already done.

- Implemented skip mode and closed its gate. A skip-mode block now names both
  of its references from the frame's SkipModeFrames pair (AV1 §5.11.25), which
  the compound machinery then predicts from - NEAREST_NEARESTMV takes the
  nearest candidate of each list - and the frame-level derivation
  (`skip_mode_params`, §6.8.14) picks that pair from the order hints.
  `inter_skipmode_64x64` pins it: the generator encodes the two-frame `shift`
  stream with order hints on, appends a copy of its last inter frame, and
  rewrites five header bits so the derivation finds one reference on either
  side of the copy's own hint and `skip_mode_present` is read. All three
  frames compare against dav1d at [0, 0, 0], which also pins the
  reference-slot state carried across three frames.
- Implemented compound inter prediction and closed the `reference_select` gate.
  A block with `reference_select` set now reads `comp_mode` (AV1 §5.11.24,
  `TileCompModeCdf` with the §8.3 context), and a compound block then reads its
  two reference names through `comp_ref_type`'s unidirectional or bidirectional
  tree (`uni_comp_ref`, `comp_ref`, `comp_bwd_ref`), both against the
  neighbour-count contexts the single-reference tree already used. The motion
  side follows: `find_mv_stack` is called with the compound flag (its machinery
  was already built), `inter_block_mode_info` reads the `compound_mode` symbol
  (`NEAREST_NEARESTMV` or `NEW_NEWMV`, with `RefMvContext`/`NewMvContext`
  mapped through `Compound_Mode_Ctx_Map`), `assign_mv` reads one `read_mv` per
  reference list against that list's candidate, and the interpolation-filter
  context gains the compound row group. The prediction averages both lists'
  interpolations with the compound intermediate rounding (`round1 = 7`) and the
  spec's `interPostRound` blend - 16ths of a sample on 8-bit, quarters on
  12-bit - exactly as libdav1d blends them.
- `inter_compound_64x64` pins the path: `inter_shift_64x64` with one header
  byte rewritten, `reference_select` 0 to 1, so a tile coded for a
  single-reference frame decodes as compound blocks. The generated test asserts
  every frame-header field against the FFmpeg transcript and compares
  reconstruction against dav1d sample for sample at `[0, 0, 0]`; the fixture
  joins the generator's `patch_header_fields` family, so
  `generate-av1-inter-reference.py --check` re-derives and re-verifies it.
- `skip_mode` stays refused: it is a compound block whose references and both
  motion vectors are copied from the frame's `SkipModeFrames` pair, and that
  derivation is the next slice. Masked compound (wedge and distance weighted)
  and inter-intra compound stay refused at the frame gate as before.
- Closed the stage-B inter fixture: `inter_cdf_inherit_64x64`'s inter frame now
  matches dav1d sample for sample (`[0, 0, 0]`, was `[3992, 842, 928]`), the
  production loader (`av1_cdf_load_enabled`) is on, and the OBU and its dav1d
  truth are untouched. Two conformance bugs were in the way, neither of them in
  the inheritance machinery itself.
- Fixed the 1-D coefficient scans being swapped between the two directional
  transform classes. `av1_coeff_scan_square` and `av1_coeff_scan_rect` emitted
  the transpose for `AV1_SCAN_VERT` and the identity for `AV1_SCAN_HORZ`, but the
  spec's `get_scan` maps the `V_*` types to `Mrow_Scan_*` (row-major) and the
  `H_*` types to `Mcol_Scan_*` (column-major) - `Mrow_Scan_16x16` is the
  identity and `Mcol_Scan_16x16` the transpose, likewise the rectangular
  `Mrow_Scan_16x8` / `Mcol_Scan_16x8` (AV1 spec get_scan; go-av1
  `getScan`/`scans_all_gen.go`). No existing sample could expose it: every leaf
  in the pixel-exact corpus is `scan_class == DEFAULT`, and this fixture holds
  the first `H_*` leaf. The wrong scan order moved the 2-D position a
  `coeff_base` context is derived from, so one late coefficient of one 16x16
  block read a neighbouring CDF row - identical symbol values, identical pixels
  for that read, but a differently adapted row that desynchronised every later
  read in the frame.
- Removed the `symbol_max_bits >= -14` over-read guards. The spec only requires
  that bound at `exit_symbol`: AV1 §8.2 explicitly allows `SymbolMaxBits` to go
  negative inside `read_symbol` and names the values read past the payload end
  as padding zero bits, which `read_bits` supplies (verified equivalent to
  libdav1d's "shift in ones, stop XORing" over 646 consecutive past-the-end
  reads). libdav1d does not enforce the check: on this fixture instrumented
  dav1d reads past its 11-byte tile payload from symbol 41 of 646 and ends at
  `SymbolMaxBits = -563`, so refusing on the budget also refused the reference
  decoder's own picture. The counter itself stays, because `renorm`'s
  `Min(shift, Max(0, SymbolMaxBits))` is the spec's padding mechanism.
- Verified the past-the-end path against libdav1d on three independent streams.
  The `av1_cdef_alpha_gate_wbtest` payloads whose CDEF index entropy runs past a
  one-byte tile are accepted by libdav1d (measured: it decodes all three, 4096
  samples each), and this decoder now reproduces its bytes exactly (plane sums
  522880, 523883, 525119; leading samples identical). The old comment stating
  libdav1d rejects them was wrong and is corrected.
- Rewrote the five tests that pinned the removed guard, keeping each test's
  subject but pinning the reference-matching behaviour: the transform-tree
  coefficient walk completes from padding bits (1 leaf), `vartx` reads the same
  16-leaf tree from a one-byte payload, `read_sb` completes its unit reads, the
  truncated palette read completes with its decoded colors, and the CDEF-alpha
  tile decodes to dav1d's plane. The 1-D scan assertions moved with the swap
  (`vertical[1] == 1`, `horizontal[16] == 256`).
- Documentation: `HANDOFF.md` records the instrumented dav1d build (dav1d 1.2.1
  from source with MSVC + meson, `src/msac.c` patched to log every symbol with
  its pre-adaptation CDF row), the complementary-CDF convention between the two
  decoders (ours and dav1d's rows sum to 32768), and the read-by-read
  localisation that led to the scan swap.
- Formatting: the tree was re-formatted by the installed MoonBit toolchain
  (0.1.20260827), whose formatter re-wraps long literals and statements
  differently than the 0.10.11+6ff76a5f9 version CI pins; no `fmt` check runs in
  CI and no code changed beyond the entries above.
- Fixed the saved frame entropy context keeping its adaptation counters, which
  made an inheriting frame adapt at the wrong rate from its very first symbol
  (AV1 §6.10 `load_cdfs`, libaom's `av1_reset_cdf_symbol_counters`; go-av1
  applies it in `resetCounts` before saving). The counters are the last entry of
  every CDF row and select the adaptation rate together with the symbol count,
  so the saving frame's own decode and every row value were still exact - only a
  frame that loaded the context saw the difference, which is why it had stayed
  hidden while `inter_cdf_inherit_64x64` disagreed with dav1d over most of the
  picture. Measured on that fixture with the loader enabled and the §8.2
  over-read guard relaxed: the inter frame's disagreement drops from
  [4029, 464, 708] to [2138, 210, 493], and one parameterized probe stream now
  matches dav1d at [0, 0, 0]. The production loader stays off until the fixture
  itself is exact; the [3992, 842, 928] fence is unchanged, as is the OBU and its
  dav1d truth.
- Archived the fence for the entropy-state snapshot. `inter_cdf_inherit_64x64` is
  `inter_minimal_64x64` with one byte rewritten - `primary_ref_frame` 7 to 0, the key
  frame left free to keep its *adapted* distributions - which makes it a legal,
  semantically determined stream whose dav1d truth differs from ours by 5762 samples
  (3992 luma, 842 U, 928 V). Those counts are asserted explicitly instead of hidden,
  and driving them to `0, 0, 0` is what storing and loading the frame context
  (AV1 §7.20, §7.21 with §5.11's `load_cdfs`) now has to do.
  Recorded beside it as a conclusion rather than a gap: `load_previous`'s *block*
  context cannot be pinned by any fixture on a conforming single-tile stream, because
  decode order guarantees every in-frame left/above neighbour is already written and
  out-of-frame positions take the unavailable inference, while reaching into a
  previous frame's samples is the §11 `ref_frame_mvs` mechanism instead. Evidence in
  the fixture README: freezing only the distributions, so the inherited block state
  is the sole difference, moved 0 of 6144 samples on both the `inter_minimal` and
  `inter_still` shapes.
- Reached the `primary_ref_frame != PRIMARY_REF_NONE` branch of AV1 §5.11 with a
  fixture instead of an implementation guess. `inter_primary_ref_64x64` rewrites two
  same-width header fields in place on `inter_minimal_64x64` - the inter frame's
  `primary_ref_frame` 7 → 0, which names the key frame through `ref_frame_idx[0]`,
  and the key frame's `disable_frame_end_update_cdf` 0 → 1 - so the stream differs
  from its base in exactly two bytes, every tile byte is untouched, and dav1d's
  planes are *bit-identical* to the base's. Both halves are needed: inheriting
  without freezing leaves the key frame's adapted distributions behind, and then the
  whole frame diverges (5035 of 6144 samples). What that pins is the branch - the
  field is read, the header is not mis-lexed, and the frame is decoded and compared
  sample-for-sample instead of being refused - and the README says just as plainly
  what it does not pin, namely the *contents* of a snapshot: the inherited
  distributions were chosen to equal a fresh start, and a measured decomposition
  (freeze the distributions, inherit only the block context, nothing moves) shows
  `load_previous` is invisible on frames this small, where the first superblock
  spans the picture and overwrites the state before anything reads it. The next rung
  is the per-buffer CDF snapshot with the unfrozen variant as its fence. New
  `patch_header_fields` helper in the generator; the emitter's
  `inter.primary_ref_frame` assertion is now a per-spec value.
- Inter edges are now deblocked with the strength AV1 §7.14.5 step 4.c specifies:
  `base + (loop_filter_ref_deltas[ref] << nShift) + (loop_filter_mode_deltas[modeType]
  << nShift)`, where `modeType` is 1 for any mode from `NEARESTMV` up except
  `GLOBALMV` and `GLOBAL_GLOBALMV`, and `nShift` is the *pre-delta* base level
  shifted by five. Frame deblocking therefore takes the frame's motion field, so it
  can ask which reference and which mode owns the block beside each edge;
  `av1_loop_filter_edge_level` replaces the intra-only strength helper, and the
  gates around it (§7.14.1 skips a chroma plane whose own level is zero; a frame
  with two zero Y levels is not deblocked at all, which is what dav1d does) stay
  *outside* that arithmetic because they are per-plane, not per-edge.
  `inter_lf_delta_64x64` covers it: the encoder will not emit a delta-LF update at
  this size, and picks zero levels for every stream here, so the fixture is
  `inter_minimal_64x64` with its inter header's loop-filter fields rewritten by
  hand and dav1d's planes regenerated. `su(1+6)` is a seven-bit two's complement
  value, adjudicated by mutating the reader rather than by assertion: reading the
  same bits as sign-and-magnitude costs 108 U and 50 V samples, and skipping step
  4.c altogether costs 41 luma and 24 V. What the fixture provably does *not* pin
  is recorded in its README - step 4.b is never reached, because the frame codes no
  intra blocks, and the §7.14.2 `row | subY` / `col | subX` chroma widening makes
  no sample move on a frame this uniform.
- Measured, and then documented as two different kinds of gap, the regression
  coverage of `read_mv_component`: the committed fixtures code magnitude classes 1
  and 4 only (24 and 232 eighth-pel). Classes 5 to 10 are uncloseable with this
  build, and the reason is the encoder's motion search range - about +/-32 pixels,
  which is exactly where class 5 begins: a
  33-pixel displacement comes back as magnitude 256, and anything from 40 pixels
  up comes back as `NEARESTMV` with a zero vector, i.e. the inter frame is handed
  back as a copy of the key frame. Band-limited translated texture (the content
  that makes residual much dearer than one long vector) aborts the encoder at every
  contrast that still carries detail, sawtooth sources cannot reach class 5 at all
  because their period makes a short vector equally good, and `--static-thresh=0`
  changes nothing. Classes 0, 2 and 3 are the other case: they sit *inside* that
  ceiling (sub-2-pixel, 4-8 and 8-16 respectively), so they are reachable and just
  not used - and the README says plainly that closing them would add the class
  symbol and the class-boundary arithmetic but *no* new `mv_bit` row, because class
  4 already reads rows 0 through 3. `tests/fixtures/av1-inter/README.md` records the
  attempts and the two ways actually to close it, so the untested classes are not mistaken for
  covered.

- A NEARMV block resolves to stacked candidate **1**, not candidate 0. §5.11.24
  assigns `RefMvIdx = 1` before the depth-reference-list loop of the nearmv tree,
  so that value has to stand even when the stack is too thin for a single
  `drl_mode` symbol to be read - the old code initialised it to 0 and only wrote
  it inside the loop, which quietly turned every NEARMV block into a NEARESTMV
  one. The two trees are now entered only by the modes that actually have one, so
  no mode reads `drl_mode` syntax it should not.
  `inter_minimal_64x64` is exact on all three planes with this: its sawtooth
  repeats every 32 samples, so its right-hand blocks can be served by a +3 or a
  -29 pixel vector and the encoder picks the second, which only candidate 1
  carries. Every general-syntax inter frame in the package is now sample-exact
  against dav1d.

- Fixed `read_mv_component` indexing its magnitude bits against the wrong axis:
  the row is selected by bit position `i`, but the guard compared `i` against the
  length of the *component* axis, so every motion vector of magnitude class 3 or
  higher abandoned the read after two bits and returned a zero difference - the
  remaining class bits were never consumed, so the tile desynchronised from there
  on. The class bound now comes from the table (11 classes, the largest of which
  codes 10 magnitude bits) instead of a constant that cut the range short. This
  is the inter right-edge defect: `inter_edge_64x16` is now sample-exact on all
  three planes and its test compares every sample rather than excluding the last
  columns, because the last 4x16 strip reaches back into the frame with a large
  negative vector instead of coding the wrap-around as residual.
  `inter_minimal_64x64` decodes for the first time too - the dense 4x16 tree was
  never a budget problem, just the same truncated read - and what it still gets
  wrong is pinned as per-plane sample counts (144 luma, 248 U, 296 V) instead of
  a frame refusal.

- The inter right-edge defect now has committed evidence. `inter_edge_64x16` is a
  64x16 stream that decodes with a tile budget to spare, whose key frame is exact
  and whose inter frame is exact in every column except the last three luma
  columns and the last V column - so the generated test asserts everything known
  to be right and tightens by itself once the cause is fixed. The fixture
  generator and the emitter no longer assume 64x64: a fixture carries its own
  width and height.

- Dropped a duplicated probability table and an unused parameter that the inter
  work left behind: `av1_y_mode_cdfs()` copies the shared `av1_y_mode` rows
  instead of carrying a second literal, which the table generator can now do per
  table (`DERIVE_FACTORIES`), and `av1_inter_residual` no longer takes the frame
  state it never read.
- Inter frames now reconstruct. Two new general-syntax fixtures carry the first
  sample-exact motion-compensated evidence in the package, on all three planes,
  against dav1d: `inter_still_64x64` repeats one frame verbatim (fixed smooth
  8-tap filter, `loop_filter_level[0..1]` both zero, so `loop_filter_level[2..3]`
  are not signalled at all - AV1 §6.8.2), and `inter_shift_64x64` translates a
  band-limited wave by a true 2.5 luma pixels, which forces a fractional motion
  vector, a switchable interpolation filter and live chroma deblocking
  (`loop_filter_level[1]` is 4). Sub-pel interpolation, reference masking at the
  frame edge and the in-loop filters therefore agree with an external decoder.
- `scripts/generate-av1-inter-reference.py` selects its input source per fixture,
  because aom's partition search on the translating ramp descends into 4x16
  strips and the low-complexity sources keep a tree coarse enough to debug
  entropy against. The same build segfaults at teardown on some two-frame
  encodes, so the wave's amplitude and periods are pinned rather than chosen for
  looks; candidate content gets probed with a throwaway encode first.
- FFmpeg's muxing summary is cut from the committed transcripts. It carries a heap
  address and a speed figure, so every generator run rewrote two evidence files
  for no reason.
- Narrowed the remaining `inter_minimal_64x64` defect. The partition symbol
  indices and 4-way geometry were re-checked against the normative text (§6.4.1
  `decode_partition` and the §9.3 `split_or_horz`/`split_or_vert` gather sets,
  which pin `VERT_4` to index 9 and `HORZ_4` to 8), and that frame's loop filter
  is provably inert, so what is left is the tile's trailing-bit budget on dense
  trees and nothing else.
- `av1_video_decode_frame` now documents what it actually does: an inter unit
  reads the reference buffer the earlier units filled, so a sequence decodes only
  in order. Two generated tests drive the animated-AVIF seam
  (`avif_decode_animation_samples`) over a fixture's real temporal units and
  assert the second sample presents the motion-compensated picture, that a
  repeat sample presents identical pixels, and that a cold decoder refuses an
  inter unit rather than inventing one from nothing.
- Wired inter-frame block decoding end to end. `av1_inter_mode.mbt` reads the
  syntax (AV1 §5.11.20-§5.11.30): `is_inter` over the four intra-neighbour
  contexts, the six-node single-reference tree where every node carries its own
  forward/backward `ref_count_ctx`, the newmv/zeromv/refmv mode chain, the depth
  reference list walk that starts one candidate deeper for NEARMV than for
  NEWMV on purpose, `assign_mv`, the joint-and-class motion vector components
  with the fractional bits a frame is allowed to signal, and the switchable
  interpolation filter with `needs_interp_filter` and its same-reference
  neighbour context. `av1_inter_tile.mbt` turns it into samples: transform
  sizing (var-tx tree, tx_depth, or `Max_Tx_Size_Rect` for a skipped inter
  block), the inter transform-type sets with chroma inheriting the luma type
  through the `TxTypes` grid, `compute_prediction` per plane and per 8x8 subband
  so a merged four-pixel block takes its chroma vector from the even MI unit,
  and the residual in chunk/leaf order. `av1_intra_block` is now a three-line
  dispatcher: with no inter state it runs the previous intra leaf untouched.
  Tools the block stage cannot act on yet - compound, overlapped and warped
  motion, inter-intra blending, skip mode, intra block copy, segmentation and
  screen content - are refused per frame rather than decoded as a prefix.
- Recorded four corrections from the normative text over the reference
  implementation: the coefficient probability arrays exist once per tile, so an
  inter block shares them with an intra block; `ZeroMvContext` is only touched
  by the temporal sample process, so it is legitimately zero whenever
  `use_ref_frame_mvs` is off; there is no `enable_tx64` bit in the bitstream at
  all, so `Max_Tx_Size_Rect` needs no clamping; and `ReadDeltas` starts from
  `delta_q_present`, which the parser already requires to be zero, so block
  level quantizer and loop-filter deltas read no symbols at this stage.
- Verified the inter path against `inter_minimal_64x64` block by block: its
  second frame decodes as a single-reference, all-skip, MV (0, 24) sequence -
  the true three-pixel shift of its own key frame - and is then refused on the
  tile's trailing-bit budget about eleven blocks in, so the frame still ends up
  undecodable. Both fixtures now assert that whole-frame refusal explicitly, and
  dav1d's second-frame planes are embedded as the target the moment the budget
  is exact. Full suite: 1167/1167.

- Added the normative inter-frame probability defaults
  (`av1_inter_tables.mbt`, generated by
  `scripts/generate-av1-inter-tables.py` with each source hash pinned): the MV
  joint/sign/class/class0/fr/hp family, single-ref, new/zero/ref-mv and DRL
  mode, `is_inter` and skip mode, the switchable interpolation filter, OBMC and
  motion mode, the compound reference and compound-index family, compound type
  and wedge index, inter-intra modes, and the three inter transform-type sets.
  Thirty-five tables each get a fresh-allocating factory, because a CDF row's
  last slot is a mutable adaptation counter that tiles must not share.
- Added the inter motion-vector candidate derivation (`av1_mv.mbt`, AV1
  §7.10.2). `av1_find_mv_stack` walks the row, column and corner neighbours in
  the normative order, merges candidates that repeat a vector instead of
  appending them, weights the immediate-neighbourhood candidates by
  `REF_CAT_LEVEL`, sorts each range by descending weight while keeping equal
  weights in discovery order, falls back to the extra search when fewer than two
  candidates exist, clamps every candidate to the reach of a block of this
  size, and emits the newmv/refmv/zeromv and DRL contexts the mode tree reads.
  `Av1MotionField` holds the per-4x4 motion state a frame shares across tiles,
  and `av1_lower_mv_precision` reproduces the deliberate asymmetry where
  forced-integer motion rounds away from zero while dropping the
  high-precision bit rounds toward it. Derivation reads candidates already
  lowered, never the decoded MV, which is what lets an unclamped NEWMV reach
  past the clamp window without breaking the reference read's clamping.
- Cross-checked the derivation against `_refs/mvstack_sim.py`, an independent
  Python transcription of §7.10.2, on 42 vectors over seeded mixed motion
  fields: ten block geometries at four positions each, a tile-bounded case
  where neighbours outside the tile must be ignored, and an all-intra field
  that exercises the global-motion fallback. 43 new tests, 1165/1165.

- AVIF image sequences no longer require every item to carry its own sequence
  header. `av1_video_decode.mbt` adds a stateful decoder that latches the parsed
  sequence and owns one `Av1FrameMap` across items, which is also where an inter
  frame will find the references it predicts from; `avif_decode_animation_frames`
  now drives that object instead of decoding each sample independently. AVIF
  allows the header in the first item only, so a conforming sequence whose later
  items omitted it previously decoded to nothing. A new test re-wraps the key
  frame of the general fixture as a header-less temporal unit and asserts it
  decodes to the same picture only because the sequence was latched.
  1123/1123.

- Started Phase D (general frame syntax) with the inter-frame foundation. The
  sequence parser now reads the whole general `sequence_header_obu` instead of
  rejecting anything that is not a reduced still picture: operating points with
  their timing and decoder-model lengths, frame-id numbering, and the inter tool
  flags (`enable_order_hint`, `enable_ref_frame_mvs`, `enable_warped_motion`,
  `enable_dual_filter`, `enable_jnt_comp`, `enable_masked_compound`,
  `enable_interintra_compound`, `order_hint_bits`, the two `seq_force_*`
  selectors). The frame parser gained the entire non-reduced prefix —
  `show_existing_frame`, `frame_type`, `show_frame`, `showable_frame`,
  `error_resilient_mode`, `frame_id`, `frame_size_override`, `order_hint`,
  `primary_ref_frame`, `refresh_frame_flags`, `ref_order_hint`, `inter_refs`
  (reference list, short signaling, `frame_size_with_refs`,
  `allow_high_precision_mv`, `interpolation_filter`, `motion_field_mode`,
  `use_ref_frame_mvs`, sign bias), `disable_frame_end_update_cdf`,
  `reference_select`, `skip_mode_params`, `allow_warped_motion` and
  `global_motion_params` with its raw-bit sub-exp coders — as one unified
  grammar whose reduced-still path consumes exactly the bits it used to, so all
  1063 earlier tests still pass. A `load_previous`/`setup_past_independence`
  split now inherits the per-reference warp models and loop-filter deltas that
  `segmentation`-free frames read back, and the loop filter takes its reference
  and mode deltas as seeds instead of hard-coding the defaults.
- Replaced the placeholder RGBA reference store with the real one.
  `av1_frame_map.mbt` keeps eight slots of native bit-depth planes plus the
  per-slot order hints, frame types, ids, dimensions and saved parameters,
  implements `update_reference_map` over `refresh_frame_flags`, key-frame
  buffer invalidation, the relative-distance sign-bias rule,
  `frame_refs_short_signaling` derivation and show-existing lookup. The frame
  driver stores the grain-free reconstruction, so a later frame never predicts
  from film-grain samples.
- Added the eight-tap subpel motion-compensation kernel.
  `av1_interp_tables.mbt` carries the normative `Subpel_Filters` table
  (six filter sets by sixteen 1/16-pel phases by eight taps) generated with the
  source hash pinned, and `av1_mc.mbt` implements the two-pass
  horizontal-then-vertical interpolation with the 1/1024-pel scaled walk,
  reference-scaling ratios, the narrow-block four-tap substitution, per-direction
  dual-filter selection, the 8/10/12-bit and single/compound intermediate
  rounding exponents, and edge-replication by read-side clamping (the same
  convention the superres scaler already uses, and equivalent to the spec's
  border extension because the extension itself replicates).
- Verified against two new general-header fixtures
  (`tests/fixtures/av1-inter/`): a full-tool 64x64 encode whose second frame is
  a real inter frame, and a stripped one with every inter tool disabled so the
  derivation paths are exercised instead of the read paths. Every asserted
  frame-header field is checked against the FFmpeg `trace_headers` transcript by
  `scripts/generate-av1-inter-reference.py`, and the key frame of each is
  compared sample-by-sample against dav1d at native depth through the new
  general path — proving the reordered grammar lands on the right bits.
  `av1_mc.mbt` is cross-checked by `_refs/mc_sim.py`, an independent Python
  transcription of §7.11.3.4, on 58 vectors covering all six filter sets,
  reachable subpel phases, mixed direction filters, compound rounding,
  8/10/12-bit depths, 4x4 narrow blocks, out-of-frame motion and scaled
  references. Inter frames still stop at the reconstruction boundary until the
  mode tree and MV syntax land. 58 new tests, full suite: 1123/1123.

- Fixed two silent-wrong-value traps found while verifying the above.
  `force_integer_mv` was initialised to the sequence-level `SELECT` value (2)
  rather than the frame-level 0, which made `allow_high_precision_mv` look
  forced and drop a bit; the general header then desynced and reported
  `base_q_idx` as 0. And `1 << (SCALE_SUBPEL_BITS - SUBPEL_BITS) / 2` parses as
  `1 << 3` rather than `(1 << 6) / 2`, moving every walk origin by 24 units of
  1/1024-pel.
- Settled one spec-versus-reference question empirically. The loop filter's
  `loop_filter_delta_update` is read unconditionally, even when
  `error_resilient_mode` is set: flipping the bit that would otherwise be
  `cdef_damping_minus_3` in an error-resilient stream makes dav1d abort with an
  OBU buffer overrun, while the unmodified stream decodes. go-av1 and FFmpeg
  agree with that reading.

- Added 4:4:4 and 4:2:2 chroma support. The container now exposes both `av1C`
  subsampling flags instead of collapsing them into a 4:2:0 test, and the
  frame parser accepts profiles 1 and 2 (validating the profile/bit-depth
  pairing) rather than rejecting any non-4:2:0 stream. Every plane geometry is
  parameterised by the two subsampling shifts: plane allocation and assembly,
  cropping, the superres driver, grid-cell copies, the film-grain scatter and
  the loop-restoration stripe store. Inside the intra decoder the chroma
  reference rule (`is_chroma_reference`) now applies per axis, chroma blocks
  and palette maps take `max(4, luma >> sub)` sizes, the directional edge
  counts derive above/left/top-right/bottom-left availability per axis, CfL
  downsamples and stores its luma buffer with axis-specific windows (the Q3
  precision factor becomes `8 / 2^(sub_x+sub_y)`), and the coefficient leaf
  receives the plane's own transform size. CDEF selects chroma blocks that are
  eight luma pixels wide and tall, the loop-filter driver scales each axis
  independently, and the restoration layout, per-superblock unit reads and
  source-view strides all follow the real subsampling. Colour conversion grew
  a general planar YUV path (`av1_yuv_highbd_to_rgba`) with the 4:2:0 entry
  kept as a wrapper.
- Verified against dav1d pixel ground truth with three reduced-still fixtures:
  a 64x64 4:4:4 encode (profile 1), the same frame at 4:2:2 (profile 2, chroma
  32x64), and a 4:4:4 encode whose `cdef_uv_pri_strength` is 10 so the chroma
  CDEF path runs for real. The first two also carry active loop restoration on
  a single chroma plane (SGRPROJ on V for 4:4:4, Wiener on U for 4:2:2), which
  is what exposed the per-axis stripe and stride requirements. All three match
  dav1d for every sample of every plane. Four new tests cover the colour
  config, the two chroma formats and the active-CDEF case; full suite:
  1063/1063.

- Added per-plane quantizer deltas, so `separate_uv_delta_q` streams decode
  instead of being rejected. `quantization_params` now keeps the decoded
  deltas rather than refusing non-zero ones, reads the `diff_uv_delta` flag
  and the independent V pair when the sequence enables the tool, and V
  mirrors U when it does not. `CodedLossless` also requires every delta to
  be zero, as the spec states, which decides whether the loop-filter, CDEF,
  restoration and tx-mode syntax follows. The dequantiser reads the plane's
  own index (`base_q_idx` plus the plane's DC and AC deltas, clamped to
  [0, 255]); luma AC keeps the base index. Tile decoding threads the deltas
  from the frame header through the intra state to each coefficient leaf, and
  the alpha and stage-one inputs expose the same parameter.
- Verified against dav1d pixel ground truth with two 64x64 8-bit 4:2:0
  reduced-still streams that share their tile data and differ only in
  `quantization_params`: an aomenc encode with
  `--deltaq-mode=3 --enable-chroma-deltaq=1` (non-zero U deltas, which the
  decoder previously rejected) and the same stream rewritten to signal
  `separate_uv_delta_q` with an independent V pair, where Y and U stay
  identical to the dav1d decode while V follows the new index (928 of 1024
  samples differ). Both match dav1d for all 6,144 samples. Five new tests
  cover the two parses, the index arithmetic and both pixel-truth decodes;
  full suite: 1059/1059.

- Added AV1 film-grain synthesis, the last missing still-picture tool. The
  uncompressed header parses `film_grain_params` (AV1 5.9.30) after
  `reduced_tx_set` and no longer rejects reduced-still streams that enable
  the tool: `apply_grain`, the 16-bit seed, the luma and chroma scaling
  point sets, the AR lag and coefficients, and the chroma multipliers and
  offsets. Synthesis follows 7.18.3: a 16-bit LFSR drives the 73x82 luma and
  44x38 chroma grain blocks from the 2048-entry Gaussian table, the
  autoregressive pass walks the lag window up to the centre tap, the
  per-plane scaling LUTs interpolate the point sets, and the noise image is
  assembled from pseudo-random grain blocks with the optional horizontal and
  vertical overlap blend before it is added to the reconstructed planes.
  Synthesis streams its 32-row luma stripes (16 chroma rows) and keeps only
  the previous stripe for the vertical overlap, so the working set stays
  proportional to one stripe instead of the whole picture.
- Verified the synthesis against dav1d pixel ground truth: a 64x64 8-bit
  4:2:0 reduced-still aomenc encode (`--film-grain-test=1`) decodes
  byte-identically to the dav1d CLI with grain synthesis enabled, matching
  all 6,144 samples, while the `--filmgrain 0` control digests differently.
  The AR coefficient counts follow the go-av1 reference rather than the
  spec text: luma always carries `2 * lag * (lag + 1)` coefficients and
  chroma adds the single centre tap when `num_y_points > 0`. Only the
  go-av1 reading byte-aligns at the tile group, which
  `_refs/film_grain_sim.py` demonstrates by parsing both candidates. Two new
  tests lock the parameter parse and the pixel truth; full suite: 1054/1054.

- Added the AV1 loop-restoration decode pipeline. The entropy layer grows
  `read_literal`, the finite-alphabet `ns(n)` decoder and the `subexp(n,k)`
  reader with the inverse recentering, all on the arithmetic decoder;
  per-superblock unit reads fill a per-tile LR entropy state before each
  root superblock and feed the frame-level unit grid. Deblocked rows are
  snapshotted at every internal stripe boundary (64 luma, 8 chroma, halved
  for 4:2:0) into a stripe store that the source view reads with
  top/bottom pairing and frame-edge replication, and the scalar Wiener and
  SGR-projection filters apply on the upscaled post-CDEF frame at native
  8/10/12-bit depth. Wiener uses the per-depth round0/inter-round pair, the
  symmetric seven-tap layout and an intermediate clamp that never touches
  legal samples; SGR runs both box passes with the cdef-domain intermediate,
  the r0=0 self-replacement branch, the xqd offset clamps and the a2/b2
  index rounding. All-None planes and None units bypass filtering entirely.
- Verified the filters against dav1d pixel ground truth: one 97x65 10-bit
  4:2:0 restoration frame decoded with and without the filters is
  byte-identical to the dav1d CLI, cross-checked against FFmpeg's libdav1d,
  matching all 9,539 decoded samples (9,429 of which the restoration changes
  relative to the no-restoration control). Forty-six new tests cover the
  entropy readers, the pre-superblock unit syntax, the stripe store and
  source view, and the Wiener/SGR kernels against hand-computed values and a
  standalone Python reference simulator over four 120x16 planes. Full suite:
  1052/1052.

- Added AV1 loop-restoration header parsing, configuration validation and
  unit-grid layout. The uncompressed header reads per-plane lr_type codes in
  Y/U/V order (`00` None, `01` Switchable, `10` Wiener, `11` Sgrproj), the
  luma unit-size bits under SB64/SB128 and the 4:2:0 lr_uv_shift halving;
  all-None configurations take the implicit U256 without size bits, and the
  CodedLossless versus AllLossless gates stay distinct. The optional
  `Av1RestorationConfig` propagates through every decode entry point, and the
  grid layout mirrors `av1_alloc_restoration_struct` on the upscaled plane
  dimensions with the `av1_lr_count_units` tail rule.
- Verified against one untouched libaom encode with active Wiener on every
  plane (97x65 10-bit 4:2:0, superres denominator 12): the deterministic
  noise fixture regenerates byte-identically and its FFmpeg trace_headers
  transcript locks the parsed sequence, frame, CDEF, tx-mode and restoration
  fields. The trace's tx_mode ordinal uses FFmpeg's ONLY_4X4/LARGEST/SELECT
  numbering, where ordinal 1 is TX_MODE_LARGEST and the expected
  tx_mode_select is false; CDEF secondary strengths keep the parse-time remap
  of coded 3 to 4. Full suite: 1006/1006.

- Added normative AV1 horizontal super-resolution decoding at 8/10/12 bits.
  The header parses use_superres plus the coded denominator (nine through
  sixteen), derives the entropy-coded frame_width against the display width
  and keeps both dimensions distinct through tile geometry. The fixed 8-tap
  phase interpolation upscales complete native-depth planes after deblocking
  and CDEF, with Q14 stepping, half-error phase correction and outer-edge
  replication per the pinned libaom scalar path. CodedLossless and AllLossless
  stay distinct when scaling occurs, active restoration syntax is still
  consumed, and allow_intrabc only appears without scaling.
- Verified the kernel against 780 original-C normatives cases covering all
  bit depths, both plane groups, phases, strides and padding. Eighteen
  complete dual-dav1d references cover denominators 9–16, color/mono,
  8/10/12 bits, odd crops and two-tile seams; two constructed q0 headers
  exercise the screen-content and restoration syntax gates.

- Added native 8/10/12-bit AV1 palette decoding, including all 2–8-color
  probabilities, direct-MI neighbor caches, signed V deltas, diagonal index
  traversal and coded-edge padding. Palette predictions retain ordinary
  transform residuals, CfL and filter-intra syntax gates.
- Verified palette colors with 21 entropy transcripts and indices with 1,365
  original-C contexts and 112 complete maps. Twenty-one independently decoded
  full streams cover cache resets inside 128-pixel superblocks, chroma owners,
  palette/FI/CfL combinations and transform selection with nonzero AC.

- Added all five filter-intra modes at native 8/10/12-bit precision, with shared
  mode probabilities, per-transform prediction and ordinary residual/CfL
  reconstruction. Skipped and lossless blocks retain their filter syntax;
  transform-type probabilities use the selected filter's normative direction.
- Verified 2,520 original-C predictor cases (601,920 native samples), plus
  seventeen complete dual-dav1d streams covering every mode, nonzero AC,
  transform-size selection, sub-eight-pixel ownership and cropped edges.

- Added native-depth frame deblocking before CDEF, including cross-tile edges,
  per-plane transform-size maps, full four-sample lanes at cropped edges and
  the 4/6/8/14-tap scalar kernels. Transform maps are allocated only when an
  effective loop-filter level is nonzero.
- Parsed all four loop-filter levels, sharpness and signed reference/mode delta
  updates, with intra-specific strength and plane gates. Raw AV1, AVIF, alpha
  and isolated/grouped tile entry points propagate the parsed configuration.
- Verified 1,776 scalar edges and 512 threshold combinations against original
  libaom C. Eighteen dual-dav1d frame cases cover all depths, color/mono,
  CDEF composition, seams, crops and signed updates; varying mode deltas alone
  leaves intra output unchanged. Eleven cases preserve complete original
  libaom streams, while seven explicitly reconstruct only filter headers.

- Added all eight directional intra predictors, independent Y/UV angle deltas,
  integer interpolation, edge filtering and edge upsampling at 8/10/12 bits.
  The sequence's edge-filter flag now reaches every raw AV1/AVIF/tile entry.
- Preserved terminal partition context for top-right/bottom-left availability,
  including VERT_A/B, sub-eight-pixel chroma owners, tile boundaries and the
  64-pixel processing units inside 128-pixel blocks. Smooth-neighbor context
  uses each plane's coding modes rather than the current transform's mode.
- Checked the directional kernel against 672 original libaom C cases and
  complete tile decoding against 20 dual-dav1d references. Constructed cases
  prove visible effects of mixed partitions and independent Y/UV smooth context.

- Added CfL chroma prediction with shared adaptive sign/alpha probabilities,
  full reconstructed luma TX storage in Q3, sub-eight-pixel ownership, padded
  chroma footprints, signed rounding and prediction clipping before residuals.
  Seventeen original libaom cases and seven constructed cases compare
  complete native YUV and OBU/AVIF RGBA output at 8/10/12 bits.
- Corrected HEIF grid payload syntax, primary-item selection, sized dimg
  references and iloc/idat bounds. Automatic AVIF decoding now handles grids
  with validated tile properties, chroma alignment, equal cells and crop bounds.
  Fifteen actual libavif-decoded grids cover color/mono, all three depths,
  ordered distinct tiles, wide fields and idat storage; malformed graph and
  geometry regressions also exercise the public decode entry points.
- Assembled grids in native Y/UV precision and enabled grid alpha auxiliaries,
  including mixed av01/grid pairs. Grid metadata inherits validated cell
  configuration, and alpha is normalized once after native plane composition.
  Five actual libavif references cover three depths and both mixed layouts.
- Added eight deterministic lossy small-rectangle streams with independently
  decoded AC pixels in all four 4-axis rectangular transform geometries.

- Added 4x4, 4x8, 8x4, 4x16 and 16x4 coding blocks, including normative
  sub-eight-pixel chroma ownership, mode syntax and transform traversal.
- Added eight original libaom small-block cases and eight constructed lossless
  rectangle conformance streams, verified by dav1d CLI and FFmpeg before
  comparing native planes and public AV1/AVIF output on all three targets.
- Bound alpha selection to the primary item's auxl relationship and standard
  auxC alpha type. Selected malformed alpha now fails composition; shape and
  bit depth must match. Actual 8/10/12-bit paired AVIF files cover the binding.
- Corrected iloc version-one counts and construction methods, ipma item-ID and
  association widths, zero property indices and representable extent bounds.
  Valid idat/wide-ID variants match libavif; overflowing extents are rejected.

- Added 64x128, 128x64 and 128x128 coding blocks. Residuals follow the
  normative 64x64-chunk then plane order while retaining complete coding-plane
  skip contexts, native samples and shared coefficient state.
- Capped large-block transforms at Y64/UV32 and preserved real SELECT depths
  and lossless 4x4 traversal. Palette syntax is omitted on 128-axis blocks.
- Added 19 original libaom/dav1d large-block cases: color/mono at 8/10/12 bits,
  actual SELECT depths one and two, horizontal/vertical rectangles, cropped
  frame edges and source-exact lossless planes. All native samples and public
  AV1/AVIF pixels are compared, with scalar libavif references for mono RGB.

- Shared the native-depth intra traversal and CDEF path with monochrome images
  and auxiliary alpha, including AC, lossless WHT, multiple tiles and supported
  predictors. Removed the old size-limited single-DC alpha probes.
- Added nine original monochrome libaom/dav1d cases and three real-item alpha
  containers. Native Y is compared before conversion; grayscale and alpha use
  actual scalar libavif references, including full-depth lossless ramps.
- Converted high-bit-depth alpha with rounded UNORM scaling, preserving small
  coverage values and both endpoints. Monochrome RGB also respects full and
  limited sample ranges.
- Required AVIF configuration bit depth and monochrome flags to agree with the
  AV1 sequence header before accepting the stage input.
- Routed CLI AVIF conversion through alpha composition. Native AVIF-to-PNG
  checks at 8/10/12 bits preserve every alpha sample and the primary RGB pixels.

- Replaced speculative single-block tile probes with a shared MSAC traversal
  that decodes modes and residuals in partition order across superblocks.
  Supported coding blocks span 8..128 pixels per axis, including rectangles.
- Integrated intra transform-depth selection, including 8x8 signalling,
  16x16 depth-two transforms, rectangular splitting and neighbour updates.
- Added tile decoding for V/H with zero angle delta, SMOOTH, SMOOTH_V/H and
  PAETH, with complete adaptive Y/UV mode rows and mode-derived transforms.
- Added 45 libaom/dav1d reference cases with exact coded-depth YUV comparisons
  and public RGBA comparisons, including real tx_mode_select bitstreams.
- Corrected ADST/FLIPADST axis dispatch, identity axes, rectangular transform
  normalization and wide multiplication for high-bit-depth ADST4/identity.
- Removed the obsolete eight-byte high-bit-depth residual limit. Real
  8/10/12-bit luma cosine, two-dimensional gradient and mixed-YUV AC fixtures
  now exercise the shared coefficient decoder against full dav1d references.
- Routed zero-quantizer intra blocks through per-4x4 coefficient decoding,
  lossless inverse WHT and sequential prediction. Corrected historical
  lossless pixel expectations using independently decoded planar samples.
- Corrected partition geometry and syntax order. Geometry APIs now return
  rectangular Av1SbBlock leaves with width/height instead of square size;
  only SPLIT recurses, and the internal tile walker invokes each block's
  decoder before reading later partition symbols. Standalone partition
  probes remain separate from the complete tile syntax.
- Corrected the standalone CDEF kernel's direction offsets, damping, signed
  rounding, clipping and 4:2:0 chroma grid. Its 8/10/12-bit output is checked
  against 58,632 libaom reference samples.
- Integrated frame CDEF parameters, per-64x64 entropy indices, direction and
  variance search, and native-depth strength adjustment. Complete padded YUV
  planes are assembled before filtering across tile edges and converting to RGB.
- Added eight original CDEF-on libaom/dav1d cases at 8/10/12 bits, with exact
  YUV, raw OBU RGBA and remuxed AVIF RGBA comparisons. Same-stream CDEF-disabled
  references confirm actual filter changes, including both tile seam directions
  and an odd-sized frame.
- Corrected monochrome quantizer and restoration field counts, preserving
  frame-header alignment and independently verified zero-CDEF alpha streams.
- Corrected frame-OBU alignment and little-endian multi-byte tile lengths.
  Added nine unmodified libaom/dav1d fixtures covering 2x1, 1x2 and 2x2 tile
  grids at 8/10/12-bit, with every decoded pixel compared.
- Corrected variable-transform CDF selection, retained adaptation across
  trees, recorded sibling transform dimensions and rejected excessive entropy
  padding. The isolated tree API is not a complete inter-frame tile decoder.
- Corrected rectangular coefficient size/position contexts, 1D coefficient
  neighbours, U/V probability sharing and rectangular residual state extents.
- Added uniform multi-tile reduced-still frame-header parsing, checked tile
  size-prefix extraction, and bounded raster stitching for supported intra
  tiles. Multi-tile inputs now avoid feeding group prefixes into tile entropy.
- Preserved non-uniform tile superblock boundaries through the public stage-one
  metadata and routed supported bounded tile images by their explicit origins.
- Added AV1 partition CDF/MSAC decoding for NONE, HORZ, VERT, SPLIT and
  extended geometry symbols, with recursive raster leaf output and W8–W128
  neighbour contexts.
- Added bounded `show_existing_frame` envelope parsing with timing/frame-ID
  fields and explicit eight-slot reference-state validation; reference pixel
  storage and inter prediction remain separate stages.
- Added an eight-slot copy-on-store reference image state and a safe
  show-existing resolver for decoded RGBA frames.
- Extended the bounded tx-mode coefficient path to AV1 64x32/32x64
  rectangular leaves, including adjusted 32x32 coefficient storage, correct
  transform-size contexts, scan ordering, and 4:2:0 typed reconstruction.
- Primary AVIF stage input now remains decodable when the container carries a
  validated auxiliary alpha item; `avif_decode_rgba()` can reach its automatic
  alpha composition path without weakening auxiliary-item validation.
- Added a pure MoonBit single-tile AV1 path for 64x64 reduced-still, 8-bit
  4:2:0 frames with DC intra prediction, square DCT_DCT coefficient decoding,
  and luma/chroma residual reconstruction. The path is validated against
  external libaom/dav1d flat and non-constant fixtures and emits RGBA.
- Added bounded SPLIT four-child tile decoding, 8–12-bit quantization-aware
  reconstruction, monochrome alpha SPLIT decoding, and safe rejection of
  unsupported complex high-bit-depth residual streams.
- Added pure MoonBit grid tile extraction/composition and animation sample
  extraction, decoding, and timestamp-based frame selection APIs.
- Wired the normative integer inverse-DCT path into the bounded single-DC
  reconstruction and accepted 128x128-superblock 64x64 frames.
- Added `avif_stage1_input()` for validated AVIF-to-tile handoff; general block
  partitioning and inter-frame syntax remain staged work while bounded alpha
  and high-bit-depth reconstruction are available.
- Added an explicit 8-bit full-range YUV420→RGBA conversion path and threaded
  the sequence `color_range` flag through the bounded decoder.
- Added 32x32 single-tile neutral DC reconstruction with the W32 and chroma
  transform contexts.
- Enabled native CLI AVIF input through the bounded pure MoonBit decoder.
- Added a normative integer AV1 inverse-transform module for DCT and lossless
  4x4 WHT paths, plus reproducible libaom/dav1d AV1 and AVIF reference fixtures.
- Added single-DC chroma residual decoding for the bounded AV1 tile path.
- Added bounded pure MoonBit validation and reconstruction for AVIF auxiliary
  alpha items (`auxl`/`auxC`) and their `iloc` extents.
- Added pure MoonBit monochrome 8-bit alpha tile decoding and four-block plane
  reconstruction helpers for the next AV1 partition stage.
- Added validated 10-bit reduced-still frame-envelope parsing; high-bit-depth
  coefficient entropy and pixel reconstruction remain the next stage.

## 0.18.0 (2026-09-09)

- Added a bounded AVIF ISO BMFF primary-item parser with `ftyp`/`meta`,
  `pitm`, `iinf`/`infe`, `iloc`, `iprp`/`ipco`/`ipma`, `ispe`, `av1C`, `nclx`,
  and `mdat`/`idat` validation.
- Added pure MoonBit AV1 OBU framing, reduced-still sequence-header parsing,
  frame-envelope checks, and a bounded MSAC boolean foundation.
- The 0.18.0 release stopped before AV1 tile entropy decoding; the unreleased
  follow-up now covers only the bounded single-tile DC path.

## 0.17.7 (2026-09-09)

- Added complete pure MoonBit VP8L transform decoding for Predictor,
  cross-color, Subtract Green, and Color Indexing streams, including transform
  subimages, spatially varying Huffman groups, and the full close-distance map.
- Added native and JS regression fixtures for predictor/cross-color and color
  indexing WebP files.

## 0.17.6 (2026-09-09)

- Added the portable `cmd/cli` codec utility with `info` and `convert` commands.
- Added deterministic hexadecimal input/output so the utility works on native,
  JS, and wasm-gc without a target-specific filesystem dependency.
- Added adaptive PNG row filters and fixed-Huffman DEFLATE output with lossless
  round-trip coverage.
- Added multi-frame GIF metadata decoding and deterministic MSE/PSNR/SSIM
  image-quality metrics.
- Added Sauvola/local-mean thresholding, connected-component region statistics,
  and common 8-bit grayscale/palette PNG decode paths with `tRNS` support.
- Added deterministic format sniffing and lightweight dimension metadata for
  JPEG, WebP, AVIF and TIFF containers, plus an 8-neighbour LBP texture
  descriptor and histogram.
- Added zero-copy tile/row traversal, Harris corner detection, and WASM
  identity fast paths that avoid allocating for no-op or unknown dispatches.
- Added HOG descriptors, deterministic thresholded contours, and bounded
  Zhang--Suen skeletonization for advanced computer-vision workflows.
- Added JPEG decode/encode and lossless WebP encode adapters through
  `mizchi/image`, browser-target AVIF encoding, and a restricted baseline TIFF
  decoder for uncompressed chunky 8-bit grayscale/RGB/RGBA strips.
- Fixed target-specific AVIF adapter selection so wasm-gc and native web builds
  compile without importing the browser-only encoder.
- Added browser-native WebP/AVIF decode adapters with `createImageBitmap` and
  HTML image fallback, wired into the Playground upload path.
- Extended TIFF decoding to multiple strips, tiled images, PackBits/LZW
  compression, and a bounded BigTIFF subset with overflow-safe malformed-input
  checks.
- Added TIFF zlib/Deflate decompression and Predictor=2 horizontal differencing
  for classic strips and tiles, with cross-target regression fixtures.
- Added pure MoonBit VP8L WebP Lossless decoding for the encoder's subtract-
  green and color-cache streams, with native CLI input support.

## 0.17.5

### 修复与工程化
- Playground 的 Worker 渲染加入代际校验，避免切换图片或线程模式时旧结果覆盖新结果。
- Playground 增加上传失败、尺寸限制、缩放提示和下载错误反馈。
- WASM 验证、Web 构建产物和 CI 检查链路改为可复现并在失败时正确退出。
- 核心图像构造增加尺寸与溢出保护；补充编解码器畸形输入测试。
- 补充安全策略、贡献指南、行为准则和 Issue/PR 模板。
- 新增类型安全的 `Filter` / `Pipeline` API，支持可复用的顺序处理管线。
- Playground 支持带参数的操作栈、上移/下移、删除、撤销、重做和清空。

## 0.13.1 (2026-08-19)

### 文档
- README（中英）新增“与 MoonBit 生态中其他图像库的关系”章节，说明与 millow / MoonVision / shunge/image 的定位差异与 PixelForge 独有能力

## 0.13.0 (2026-07-31)

### 新增
- 直方图 API：`histogram_luma()`（复用 Otsu 的 256 桶 BT.601 分桶）与 `histogram_rgb()`（逐通道）
- HSL 色彩空间：`rgb_to_hsl` / `hsl_to_rgb`（与 HSV 风格一致、精确 8 位往返）与 `adjust_lightness(delta)`（保色相明暗调整）
- Playground：新增实时亮度直方图面板（经 `luma_histogram` js 绑定，每次渲染后更新）
- `cmd/showcase`：扩展“噪声 → 中值降噪 → 感知哈希”分析自检（受控平坦色块，median 必然降噪）

### 变更
- 单元测试从 163 个增加到 172 个

## 0.12.0 (2026-07-31)

### 新增
- 双三次缩放：`resize_bicubic(w, h)`，Catmull-Rom 4×4 核、中心对齐采样，同尺寸缩放为恒等
- 感知哈希：`average_hash()` / `difference_hash()` 返回 64 位指纹，`hamming_distance(a, b)` 度量相似度；区域均值缩略图保证跨后端确定性
- 确定性噪声：`add_gaussian_noise(seed, sigma)`（CLT 12 均匀和）与 `add_salt_pepper(seed, density)`，64 位 LCG 驱动，同 seed 逐字节可重现

### 变更
- 单元测试从 147 个增加到 163 个（含反相恰好翻转全部 64 位、中值滤波清除 ≥75% 椒盐噪声等强断言）

## 0.11.0 (2026-07-30)

代码审查驱动的加固（三视角审查后全量修复）：

### 变更
- `Stats` 结构由 `pub(all)` 收窄为 `pub`（只读），避免将字段集冻结进发布包的 semver 契约（便于日后扩展字段）
- `auto_contrast` 改为四舍五入除法，与 `stats`/`levels` 的舍入口径一致
- `Image::stats` 对空图（0×0）早返回全零结果，不再留下 min=255>max=0 的不自洽值
- `moon.mod` 的 exclude 新增 `cmd/`，不再将 demo 可执行包打进发布包

### 修复
- `cmd/showcase`：PNG 往返失败时改为 `abort`（使 CI 端到端冒烟测试能真正失败，而非静默通过）；诊断行移到 `P3` 魔数之后，保证输出为合规 PPM；背景新增一次 `box_blur` 滤镜，使展示覆盖更多招牌 API

## 0.10.0 / v1.0.0 (2026-07-30)

首个稳定版里程碑：公开 API 进入稳定期，后续遵循语义化版本（主版号内保持向后兼容）。

> 说明：mooncakes.io 目前要求主版号为 0，故该里程碑在 mooncakes 上以 **0.10.0** 发布；GitHub 保留 **v1.0.0** tag/release 作为稳定版标记。

### 新增
- 图像统计：`stats()` 返回逐通道 min/max/mean 与 luma 统计（Int64 累加，防溢出）
- 自动对比度：`auto_contrast()` 将 luma 线性拉伸至全量程，保持色相
- 色阶：`levels(black, white, gamma)` 窗口重映射与中间调 gamma
- 综合展示 CLI：`cmd/showcase` 组合绘图、位图文字、混合、滤镜与 PNG 编解码往返自检；CI 新增端到端冒烟测试

### 变更
- 单元测试从 141 个增加到 147 个；累计 27 个功能模块、约 6200 行有效 MoonBit 代码

## 0.9.0 (2026-07-30)

### 新增
- 积分图与 O(1) 盒式模糊：`integral_image()` 构建 Int64 求和面积表（防溢出），`Integral::rect_sum()` 四次查询得任意矩形和，`box_blur(radius)` 任意半径每像素 O(1)
- 泛洪填充：`flood_fill(x, y, r, g, b, a, tolerance)`，四连通显式栈种子填充，逐通道容差
- 距离变换：`distance_transform(threshold)`，两遍 chamfer (3,4) 距离，归一化为灰度

### 变更
- 单元测试从 126 个增加到 141 个

## 0.8.0 (2026-07-30)

### 新增
- 锐化蒙版：`unsharp_mask(radius, amount)`，复用可分离高斯提取高频细节并回叠
- 裁剪与填充：`crop(x, y, w, h)`（自动限幅，空选区降为 1x1）、`pad(l, t, r, b, color)`（颜色边框）；`crop∘pad` 无损往返
- Playground：dither_mono 接入派发表 id 22，新增 Otsu（21）与抖动（22）滤镜按钮，重建 web 产物

### 变更
- 单元测试从 117 个增加到 126 个

## 0.7.0 (2026-07-30)

### 新增
- Otsu 自动阈值：`otsu_threshold()` 类间方差最大化（Double 累加避免大图整数溢出），`otsu()` 一键二值化，接入派发表 id 21
- Floyd–Steinberg 抖动：`dither_grayscale(levels)` / `dither_mono()`，经典 7/16、3/16、5/16、1/16 误差扩散
- 连通域标记：`label_components(threshold)` 返回标签图与数量，`count_components` 便捷计数（四连通、显式栈泛洪填充）

### 变更
- 模块清单由 moon fmt 归一化回 moon.mod（exclude 保留在 options() 块内，发布包仍排除 assets 与个人文档）
- 单元测试从 102 个增加到 117 个

## 0.6.2 (2026-07-30)

### 变更
- 将 `moon.mod` 迁移为 `moon.mod.json`，并通过 `exclude` 字段将 `assets/`、`_screenshots/` 及个人文档排除出发布包（发布包从 83 项减至 72 项，图片仍保留在 GitHub 供 README 显示）

## 0.6.1 (2026-07-30)

### 安全
- 从发布包中移除非项目文档（项目申报书）并加固 `.gitignore`，防止个人信息随 `moon publish` 打包（感谢 @Nanaloveyuki 在 #30 中的友善提醒）；旧版本包已联系平台处理

## 0.6.0 (2026-07-30)

### 新增
- GIF 解码：`gif_decode`，支持 GIF87a/89a、全局/局部色表、图形控制扩展透明索引、变长 LSB-first LZW（含 KwKwK 与 4096 项字典上限）、四遍交错；畸形输入返回 `None`
- 双边滤波：`bilateral(radius, sigma_space, sigma_range)`，空间高斯 × luma 引导的值域高斯，保边平滑

### 变更
- 单元测试从 95 个增加到 102 个（含著名 1×1 透明 GIF 常量、手工汇编的 2×2 四色 GIF LZW 位流、双边 vs 高斯的保边对比等），达成申报目标 100+

## 0.5.0 (2026-07-28)

### 新增
- 可分离高斯模糊：`gaussian(radius)` 任意半径（二项式权重，行列两次 1D 扫描，每像素 O(r)；半径 1 与 3×3 高斯核一致）
- 图层合成：`composite(top, mode)` Porter-Duff source-over，`BlendMode` 含 Normal/Multiply/Screen/Overlay/Darken/Lighten/Difference/Add，纯整数舍入运算
- 位图文字：内置 5×7 字体（数字/A–Z/基本标点），`draw_char`/`draw_text` 整数倍缩放、小写折叠、自动裁剪
- 英文版 README（README.en.md），中英互链

### 变更
- 单元测试从 81 个增加到 95 个（全部手算验证，含逐模式合成期望值、字形精确像素数、高斯脉冲对称性等）

## 0.4.0 (2026-07-27)

### 新增
- 仿射变换：`Affine` 2×3 矩阵类型（旋转/平移/缩放/错切构造器、`then` 复合、`invert` 求逆）与 `Image::affine`（逆映射 + 双线性采样，未覆盖区域透明）；便捷方法 `rotate(degrees)`（绕中心任意角度）与 `translate(dx, dy)`
- 绘图原语：`draw_line`（Bresenham）、`draw_rect`/`fill_rect`、`draw_circle`（中点圆）/`fill_circle`，全部自动边界裁剪
- PNG 编解码：`png_encode`（8 位 RGBA，stored DEFLATE 块）与 `png_decode`（完整 inflate：stored/固定/动态 Huffman，逐块 CRC-32 与 zlib Adler-32 校验，全部 5 种行滤波，支持 RGB/RGBA）
- Playground：Web Worker 后台线程开关（双引擎均可在 Worker 中运行，像素缓冲区 transferable 传输）；下载按钮改用自家 `png_encode`（新增 `encode_png` js 绑定）

### 变更
- 单元测试从 62 个增加到 81 个（含 CRC-32/Adler-32 公开参考向量、手工汇编的固定 Huffman/LZ77 位流、rotate(90) 与 rotate90 逐字节一致性等）

## 0.3.0 (2026-07-27)

### 新增
- 形态学运算：`erode` / `dilate` / `morph_open` / `morph_close`（3×3 结构元）
- 色彩空间：`rgb_to_hsv` / `hsv_to_rgb` / `rgb_to_ycbcr` / `ycbcr_to_rgb`，及 `saturate`（饱和度）与 `hue_rotate`（色相旋转）滤镜
- QOI 编解码：`qoi_encode` / `qoi_decode`，完整实现 QOI 规范全部 6 种 op，无损往返，畸形输入返回 `None`
- BMP 编解码：`bmp_encode` / `bmp_decode`，无压缩 24/32 位，支持自上而下（负高度）位图
- Canny 边缘检测：`canny(low, high)`，含非极大值抑制与 8 连通滞后阈值追踪；接入派发表 id 20 与 Playground

### 变更
- 统一派发表 `Image::apply_filter_id` 扩展至 id 0–20
- 单元测试从 39 个增加到 62 个（含编码字节精确长度、无损往返、阶跃边缘几何等手算用例）

## 0.2.0 (2026-07-27)

### 新增
- 几何变换：`flip_horizontal` / `flip_vertical` / `rotate90`
- 缩放：`resize_nearest` / `resize_bilinear`（中心对齐采样，同尺寸缩放为恒等）
- 新滤镜：`posterize`（色调分离）、`gamma`（伽马校正）、`vignette`（暗角）、`scharr`（Scharr 边缘）
- CLI：`cmd/ppm` 示例，向 stdout 输出 PPM (P3) 图像（`moon run cmd/ppm > edges.ppm`）
- Playground：滤镜可叠加成管线、处理结果一键下载 PNG、新增伽马/暗角/Scharr/翻转/色调分离按钮
- GitHub Actions CI：`moon check` + wasm-gc/js 双后端测试 + Web 产物构建

### 变更
- Sobel 与 Scharr 共享同一梯度边缘引擎（内部重构，行为不变）
- 统一派发表 `Image::apply_filter_id` 扩展至 id 0–19
- 单元测试从 25 个增加到 39 个

## 0.1.0 (2026-07-24)

- 首个发布：`Image`/`Kernel` 核心类型，13 种滤镜与通用卷积引擎
- js 后端零拷贝浏览器绑定 + 线性内存 wasm 绑定（导出 memory）
- 浏览器 Playground（拖拽/粘贴/上传、JS/WASM 引擎切换与性能对比）
- 原生 CLI 示例、25 个确定性单元测试、发布至 mooncakes.io
