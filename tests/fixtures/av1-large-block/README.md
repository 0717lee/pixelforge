# Actual 128-axis coding-block references

The initial eighteen bounded encoder configurations produced seven large-block
fixtures: color and monochrome 128x128 at each of 8, 10, and 12 bits, plus a color
127x125/10-bit cropped image coded as 128x128. Six additional source-guided
configurations produce actual SELECT depth 1 at all three depths for color and
monochrome. A third bounded batch adds two actual monochrome rectangles with
SELECT depth 2 and two lossless 128x128 fixtures. Two final controlled encodes
add color rectangles with SELECT depth 2 and neutral chroma. The corpus contains
nineteen accepted fixtures from thirty-two candidates. Every accepted stream is
original libaom output with DC prediction and screen-content tools allowed.
Seventeen use q30 with CDEF enabled; the two q0 streams have inferred ONLY_4X4/WHT
and no frame CDEF or loop-filter syntax.

`--sb-size=128` does not prove the coding-block size. Square encodes also receive
`--min-partition-size=128 --max-partition-size=128`; the primary libaom header
documents these as constraints on both axes, with a picture-boundary exception
for the minimum. An independent MSAC prefix reader checks the actual root
partition, skip flag, DC luma/chroma modes, CDEF index, and optional transform
depth. Square fixtures have `PARTITION_NONE` at the 128 root; the four accepted
monochrome and color rectangles have actual `PARTITION_HORZ` and
`PARTITION_VERT`. All have `skip=0`.
The manifest records this evidence and the SDK header's versioned source/hash.

The original six transform-search candidates retained `tx_mode=1`/depth 0.
Inspection of the matching libaom v3.6.0 source shows that all-intra CPU0 square
search considers 64 and 32, rather than 16. Enabling transform search and
disabling 64-point transforms leaves the 32-point candidate; the additional six
encodes all emit actual `tx_mode=2`, with independently decoded `tx_depth=1`.
The original four 128x64/64x128 rectangle candidates and odd monochrome crop chose SPLIT
at the root and were rejected as large-block fixtures. Their bounded commands,
actual prefix results, and hashes remain in the candidate ledger. No synthetic
OBU rewriting or unbounded parameter search is used.

The third batch follows the matching source rather than varying parameters at
random: `partition_strategy.c:1733-1761` disables rectangles when the root128 is
no larger than the minimum partition size. Lowering the minimum to 64 (maximum 128)
allows H/S for a 128x64 picture or V/S for 64x128. At CPU0, rectangular transform
search starts one level earlier than square search, so disabling 64 leaves 32/16.
Four 10-bit candidates use a physical 16x16 checkerboard at 64/192 with a small
local cosine. The two monochrome streams produce genuine 128x64 and 64x128 coding
blocks with independently decoded `tx_mode=2`, `tx_depth=2`, and 16-point luma
transforms. Both color candidates still choose SPLIT and remain ledger-only.
The other two configurations use color/mono 10-bit full-range ramps at q0 and
min=max128. Both emit NONE128; every independently decoded native sample equals
the input, exercising 4x4 WHT ordering across all four luma chunks and, for color,
the corresponding chroma chunks.

The final two candidates hold the 10-bit luma source and encoder controls fixed
while replacing the original color checkerboard U/V planes with constant 512.
The generator checks Y source bytes against the accepted monochrome source.
Both color cases now produce the requested H/V root partition and actual SELECT
depth 2. Thus the chroma input change controls the observed partition decision
in these two comparisons. Every U/V sample in both filtered and unfiltered
independent references remains 512; these two fixtures exercise luma AC with
neutral chroma rather than claiming nonzero chroma residual.

Every accepted 64x64 luma chunk and, except for the two neutral-chroma controls,
every corresponding 32x32 chroma chunk contains an internally varying transform
in the **same-OBU unfiltered** dav1d output.
Because DC prediction is constant within each transform, that proves nonzero AC
residual content in each of those plane/chunks. The resulting goldens exercise
the normative residual order: chunk Y, chunk X, plane, transform row, transform
column. A palette symbol is absent for 128-axis coding blocks even when the
frame permits screen-content tools.

```sh
python scripts/generate-av1-large-block-reference.py --include-source-guided-tx32 --include-rectangles-lossless --include-neutral-chroma-rectangles --test av1_large_block_reference_wbtest.mbt
moon test av1_large_block_reference_wbtest.mbt --target js
```

Without any include option, generation repeats the original eighteen-candidate
baseline. `--reuse-existing` verifies recorded artifact hashes and keeps the
existing candidate ledger while encoding only newly requested names. The actual
latest batch command and prior generation command are recorded in the manifest.
The default test destination is the ignored `_refs`
directory for staged development. Options also include `--source`, `--out`, encoder/decoder tool
paths, `--moonfmt`, and the version-checked scalar `--libavif-scalar` library.
Only the generated test is formatted through `moonfmt -`.

Files retain native source planes, original OBU, filtered and same-OBU `nocdef`
dav1d references, and a real AVIF remux. FFmpeg and dav1d CLI outputs must agree;
AVIF remux references must equal the original OBU references. The generated tests
compare every native YUV/Y sample and all public AV1/AVIF RGBA pixels. Monochrome
RGBA expected values come from actual scalar libavif conversion with libyuv
disabled. Full commands, versions, hashes, CDEF parameters, and per-chunk evidence
are recorded in `manifest.json`.
