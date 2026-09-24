# AV1 partition and superblock references

These fifteen real libaom streams cover 8, 10, and 12-bit YUV420 with DC intra
prediction and 64x64 superblocks. Each bit depth includes these q30 layouts:

- 64x64 image with fixed 32x32 coding blocks.
- 64x64 image with fixed 16x16 coding blocks.
- 128x128 image with fixed 32x32 coding blocks across four superblocks.
- 128x64 image with adaptive 16..64 partitions across two superblocks.

Each bit depth also includes a lossless q0 64x64 image with fixed 32x32 coding
blocks. Its complete dav1d reference must match the input byte for byte.
Lossy samples use `ONLY_LARGEST`/DCT; lossless samples use `ONLY_4X4`/WHT.

Fixed layouts disable rectangular, AB, and 1-to-4 partitions and set the encoder
minimum and maximum partition size equally. Adaptive layouts allow those modes;
the corpus does not claim particular adaptive symbols without an entropy trace.
All samples disable directional/smooth/Paeth predictors, CFL, palette, filter
intra, intra-edge filtering, CDEF, restoration, loop filtering, quantizer deltas,
and quantizer matrices. These are scoped decoder references, not general AV1
conformance evidence.

From the repository root:

```sh
python scripts/generate-av1-partition-reference.py
moon test av1_partition_reference_wbtest.mbt --target js
```

The generator requires `aomenc`, FFmpeg with `libdav1d`, Python, and `moonfmt`.
It accepts executable paths through `--aomenc`, `--ffmpeg`, and `--moonfmt`, plus
`--out` and `--test` output paths. It reuses serialization helpers from the
high-bit-depth reference generator and formats only its own test via `moonfmt -`.

Each case retains `*.input.yuv`, untouched `*.obu`, and complete
`*.reference.yuv`. Planes are Y, U, then V; 10/12-bit samples use unsigned
little-endian 16-bit storage. `manifest.json` records dimensions, plane offsets,
patterns, exact commands, executable versions, header checks, and SHA-256 hashes.

The generated white-box tests use `av1_reference_planes_wbtest.mbt` to expand
every reference sample and compare it with the cropped internal YUV planes at
the coded bit depth. The shared helper verifies the sequence/frame dimensions
and single-tile scope, then retains a complete public `av1_decode` RGBA comparison
using the existing color converter. This catches sub-byte high-bit-depth errors
and avoids treating FFmpeg RGB conversion differences as decoder mismatches.
