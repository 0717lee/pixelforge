# AV1 axis, smooth, and Paeth intra references

Nine real libaom streams cover 8, 10, and 12 bits across fixed 16x16 blocks,
fixed 32x32 blocks, and an adaptive 128x64 layout. They retain the nonconstant
mixed YUV source patterns from the partition corpus and enable DC, V, H,
SMOOTH, SMOOTH_V, SMOOTH_H, and PAETH searches.

The encoder uses directional intra=1, diagonal intra=0, smooth intra=1,
Paeth intra=1, angle delta=0, CFL=0, palette=0, filter intra=0,
intra-edge filtering=0, CDEF=0, restoration=0, and loop filtering=0.
Transform-size search remains disabled (`ONLY_LARGEST`), with
`use-intra-default-tx-only=1`; the default intra transform may use ADST.
The corpus does not infer individual chosen prediction symbols from header
traces or claim exhaustive mode coverage.

From the repository root:

```sh
python scripts/generate-av1-intra-mode-reference.py
moon test av1_intra_mode_reference_wbtest.mbt --target js
```

The existing partition manifest and raw source YUV files supply reproducible
inputs and encoder command templates. Options include `--source`, `--aomenc`,
`--ffmpeg`, `--moonfmt`, `--out`, and `--test`. The generator formats only its
own test through `moonfmt -` and writes no Python bytecode artifacts.

Each case retains source YUV, untouched OBU, and complete independent dav1d
reference planes in Y/U/V order. Ten- and twelve-bit samples are unsigned
16-bit little-endian. The manifest records input formulas, exact commands,
encoder/decoder versions, header fields, plane offsets, and SHA-256 hashes.
Generated white-box tests use `av1_reference_planes_wbtest.mbt` to validate the
parsed sequence/frame and single-tile scope, then compare every reference sample
with the cropped internal YUV planes at the coded bit depth. They also retain a
complete public `av1_decode` RGBA comparison through the existing color converter.
