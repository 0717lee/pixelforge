# Original-C filter-intra kernel references

This corpus contains **2,520 cases**: all five filter-intra modes × 14 legal
transform shapes with both axes at most 32 × 8/10/12-bit samples × six reference
availability states × two deterministic native-value input patterns.

Modes follow the original enum: **DC, V, H, D157, PAETH** (indices 0..4).
These names select filter-intra tap banks, not the corresponding ordinary intra
predictors. Shapes are 4×4, 8×8, 16×16, 32×32, 4×8, 8×4, 8×16, 16×8, 16×32,
32×16, 4×16, 16×4, 8×32 and 32×8. Each shape/mode/depth tests full references,
missing top, missing left, missing both, partial top and partial left. Partial
edges have `axis_length - 3` valid samples, exercising a single available sample
on four-pixel axes and last-sample repetition on all shapes.

`output.bin` holds 601,920 native samples (1,203,840 bytes), in concatenated
row-major **uint16 little-endian** planes. `manifest.json` records deterministic
input parameters, sample counts, byte offsets, SHA-256 and CRC-32 per case,
prepared-reference hashes, original-C call/clipping/rounding evidence and complete
source/compiler/generation provenance. It does not duplicate output pixel arrays.

## Independent implementation and provenance

The source is AOM revision `8e7b6a567df174d795479b92b4ac766d271add73`:

- [Tap table and scalar predictors](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/reconintra.c)
- [Enums and mode numbering](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/enums.h)

The generator verifies the revision, canonical Git blob hashes and working-copy
contents (accepting LF or CRLF), then extracts these original blocks verbatim:

- Complete `av1_filter_intra_taps` table, including padding taps.
- `av1_filter_intra_predictor_c` and `highbd_filter_intra_predictor`.
- Both complete `build_directional_and_filter_intra_predictors` functions.
- Original enums, size/edge tables, clipping functions, rounding macro, memory
  helper and highbd pointer conversion macros.

Both full builders run with `DC_PRED`, a filter mode in 0..4 and no top-right or
bottom-left references (`-1`, as in the real caller). Edge filtering is enabled
at the builder argument, but filter-intra returns before directional filtering,
corner filtering or upsampling. Fail-fast substitutions for these unreachable
functions make accidental routing to them an error.

The builders therefore perform actual missing-edge defaults, opposite-edge
substitution, last-sample extension and corner selection. Highbd missing edges
use `base - 1` and `base + 1` in native units; they are not scaled 8-bit defaults.
Every case enters the original highbd predictor exactly once. All **840 eight-bit
cases** additionally execute the original lowbd builder and predictor; every
prepared reference and output pixel, plus clipping counters, must match HBD8.
Source and destination strides differ from small transform widths, and unused
output rows/columns retain sentinels.

Instrumentation only records values and forwards calls to the original helper
or predictor. It does not calculate replacement output pixels. The original
`ROUND_POWER_OF_TWO` macro produces every rounded value, and the original clip
functions produce every clipped value. All 15 mode/depth groups demonstrate
actual low and high clipping and native-unit half-way rounding. Per-case residue
counts account for exactly one rounding call per predicted sample. Re-running
with rounding instrumentation preserved the complete output SHA-256.

The two input patterns are a native-unit polynomial and alternating 0/maximum
pairs with phase-shifted top/left references and near-extreme corners. Inputs are
defined in the generator and manifest; no Python or MoonBit filter contributes
to goldens.

## Reproduce and check

```powershell
python scripts/generate-av1-filter-intra-kernel-reference.py --source-dir C:/path/to/aom
python scripts/generate-av1-filter-intra-kernel-reference.py --check
```

The first command compiles the temporary extracted C translation unit using
`--cc` (default: MoonBit's bundled Windows x64 TinyCC), executes the oracle and
formats only the generated test through moonfmt stdin/stdout. Temporary source
and executable files are removed after execution. Full generation and compiler
commands, compiler binary hash/version and source fragment hashes are recorded
in the manifest. No AV1 encoder, Moon build or package-wide formatter runs.

`--check` needs only Python. It verifies deterministic input reconstruction, the
complete binary hash, per-case SHA-256/CRC-32, coverage evidence, canonical WB
reconstruction and its exact file hash. It does not compile, encode, access the
source checkout or use the network.

The generated draft is `_refs/av1_filter_intra_kernel_reference_wbtest.mbt`.
Its 15 mode/depth test groups CRC-check every output sample, and all **180 4×4
cases** also compare every pixel directly. Missing/partial cases pass only valid
reference prefixes, including empty arrays for absent edges. To verify an
unchanged published copy, use `--check --test <published-test-path>`.

Frame syntax, coding-block eligibility, transform context mapping and reference
availability derived from tile neighbors are outside this pure-kernel corpus.
