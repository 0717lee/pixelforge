# Original-C superres kernel references

This corpus contains **780 cases / 831,933 native samples**: the complete
horizontal super-resolution upscale across 8/10/12-bit depths, both plane
groups (luma and chroma), all 64 phases, strided padding, outer-edge
replication and truncated availability. Six test groups in
`av1_superres_kernel_reference_wbtest.mbt` assert the Q14 step and initial
phase against the original functions and CRC-32 every output sample.

Inputs are deterministic: a native-unit polynomial pattern and alternating
0/maximum pairs with phase-shifted references. Strided rows place sentinel
`65535` gap pixels between the legal sample bound and the stride; those values
are never sampled. The contract is:

```text
av1_superres_upscale_plane(
  src, src_stride, src_available_width,
  downscaled_width, upscaled_width, rows, bit_depth
) -> packed native Array[Int]?
```

`src_available_width` is the legal sample bound, independently of the physical
stride (for luma `align8(frame_width)`, for 4:2:0 chroma half that value).
Phase dimensions are the visible widths; only the outer frame edges replicate
their last sample. The pinned arithmetic is normative: signed division
truncates toward zero, including the half-error phase correction.

`output.bin` holds the native samples in concatenated row-major **uint16
little-endian** planes. `manifest.json` records per-case parameters, phases,
SHA-256 and CRC-32, original-C call/clipping/rounding observation counts and
complete source/compiler/generation provenance.

## Independent implementation and provenance

The source is AOM revision `8e7b6a567df174d795479b92b4ac766d271add73`:

- [Phase step and initialization](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/resize.c)
- [Fixed 8-tap filter bank](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/resize.c)
- [Scalar convolution](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/convolve.c)

The generator verifies the revision and canonical blob hashes, then extracts
the original blocks verbatim: the complete 64×8 filter table, the rect wrappers
that repeat borders, the step/x0 selection functions and the scalar
convolution, plus the original clip and rounding macros. Python constructs
input samples and serializes C output; it does not implement a resampler. All
154,299 low-clip, 154,470 high-clip, 154,329 negative-round and 51,726
halfway-round observations come from the original helpers. Every case enters
the original convolution exactly once.

## Reproduce and check

```powershell
python scripts/generate-av1-superres-kernel-reference.py --source-dir C:/path/to/aom
python scripts/generate-av1-superres-kernel-reference.py --check
```

The first command compiles the temporary extracted C translation unit using
`--cc` (default: MoonBit's bundled Windows x64 TinyCC), executes the oracle
and formats only the generated test through moonfmt stdin/stdout. Temporary
source and executable files are removed after execution. `--check` needs only
Python: it verifies deterministic input reconstruction, the complete binary
hash, per-case SHA-256/CRC-32, coverage evidence, canonical whitebox-test
reconstruction and its exact file hash.

The generated draft is `_refs/av1_superres_kernel_reference_wbtest.mbt`. Frame
syntax, denominator policy and plane layout are outside this pure-kernel
corpus; see `../av1-superres/` for complete frame references.
