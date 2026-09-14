# AV1 scalar loop-filter reference corpus

These are **1,776 independent original-C edge results**: 148 cases for each of
four kernel widths (4, 6, 8, 14) at each of 8, 10 and 12 bits. Another 512 records
cover every level 0..63 and sharpness 0..7 threshold combination.

The oracle is AOM commit `8e7b6a567df174d795479b92b4ac766d271add73`:

- [Complete scalar kernel source](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/aom_dsp/loopfilter.c)
- [Original threshold initialization](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/av1_loopfilter.c)

The generator verifies the checkout revision and hashes of the original Git
blobs, then includes the **complete, byte-identical `loopfilter.c` blob** in its
temporary C translation unit. It supplies minimal headers, the verbatim upstream
clamp/rounding utilities, the verbatim `update_sharpness` function and HEV
initialization loop, storage and dispatch. No Python or MoonBit filter produces
the expected pixels. Windows CRLF checkouts and LF checkouts are both accepted
after comparison with the same pinned Git blobs.

Every case runs both original horizontal and vertical public entry points. All
four lanes must agree, as must the two orientations. All 592 eight-bit cases also
require exact lowbd-versus-highbd8 output parity. Branch labels are obtained by
calling the original C static mask, HEV, flat and flat2 functions on the original
input. Level zero is bypassed by the harness to match the scalar API's edge
selection contract; the raw C pixel kernels do not accept a level argument.

Cases cover threshold equality and rejection, HEV on/off, flat and nonflat
regions, the 6→4, 8→4, 14→8 and 14→4 branches, native-unit signed rounding,
intermediate and output clipping, low/high sample bounds and 48 fixed-LCG inputs
per width/depth. Every applicable active branch must visibly change at least one
case. HEV-on flat cases verify that strong filters are still selected. Extreme
perturbations outside the selected kernel's read footprint must not change its
used outputs. Separate outer-tap cases prove that a wide kernel preserves its
original mask when falling back to filter4: direct width4 ignores p2/p3, while
width8 and width14 can reject the same inner-edge input because of those taps.

## Canonical files

- `samples.bin`: 60-byte little-endian records. Four u8 fields give width, level,
  sharpness and bit depth, followed by 14 input u16 and 14 output u16 samples.
  Both arrays use `[p6,p5,p4,p3,p2,p1,p0,q0,q1,q2,q3,q4,q5,q6]` order.
- `thresholds.bin`: five u8 values per record: level, sharpness, limit, blimit,
  HEV. Records are sharpness-major and level-minor.
- `manifest.json`: pinned source hashes, compiler command template, corpus/test
  hashes, branch counts and each case's name, byte offset and original-C branch
  proof. `-1` means a flat/flat2 predicate does not apply to that kernel width.
  The manifest does not duplicate pixel arrays or RLE them.
- `_refs/av1_loop_filter_wbtest.mbt`: generated test draft with all canonical
  binary bytes embedded as hex. It compares all 14 outputs, preserves the input
  array, checks all thresholds and exercises invalid API inputs.

## Reproduce and verify

```powershell
python scripts/generate-av1-loop-filter-kernel-reference.py --aom-source C:/path/to/aom
python scripts/generate-av1-loop-filter-kernel-reference.py --check
```

Generation accepts `--cc`, `--moonfmt` and `--test`. Its command is:

```text
<cc> [-B <moon-root>] -I <temporary> <temporary>/reference.c -o <temporary>/reference.exe
```

On this Windows run, the compiler is MoonBit's bundled `tcc.exe`; temporary
headers, source copies and executable are removed when generation finishes.
Only the single generated test is passed through moonfmt's stdin/stdout; no Moon
build or package-wide formatter is run.

`--check` requires Python only. It verifies deterministic inputs, exact binary
and test hashes, canonical test reconstruction and coverage invariants without
compiling C, invoking Moon tools, accessing the source checkout or networking.
To verify a published test copy, pass `--check --test av1_loop_filter_wbtest.mbt`.
Frame-edge selection, tile traversal and deblock/CDEF ordering require separate
frame-level integration tests.
