# Fixed-transform AV1 AC references

These eighteen real libaom streams cover 64x64, one tile, and `PARTITION_NONE`
at 8, 10, and 12 bits. The q30 samples use `ONLY_LARGEST` and `DCT_DCT`;
lossless q0 samples use `ONLY_4X4` and the integer Walsh-Hadamard transform.
Each bit depth and quantizer has a horizontal luma cosine, a two-dimensional
luma gradient, and a mixed YUV pattern with nonconstant chroma.
CDEF, restoration, loop filtering, directional
intra prediction, filter intra, and quantizer deltas/matrices are disabled.
This corpus verifies that fixed subset; it does not establish general AV1
partition, tile, or inter-frame support.

From the repository root, with `aomenc`, `ffmpeg` (including `libdav1d`), Python,
and `moonfmt` available:

```sh
python scripts/generate-av1-highbd-ac-reference.py
moon test av1_highbd_ac_reference_wbtest.mbt --target js
```

The generator also accepts `--aomenc`, `--ffmpeg`, `--moonfmt`, `--out`, and
`--test` paths. It formats only the generated test via `moonfmt -`.

`*.input.yuv` retains the source samples; `*.obu` is the encoder output without
rewriting; `*.reference.yuv` contains every Y, U, and V sample decoded with
libdav1d. Planes are stored consecutively with 4096, 1024, and 1024 samples.
Samples occupy one byte at 8 bits and two little-endian bytes at 10/12 bits.
Every lossless reference must match its original input byte for byte; generation
fails if any sample differs. The q0 header infers `ONLY_4X4`, and its absent
loop-filter syntax is valid.

`manifest.json` records the input formulas, executable versions, exact commands,
header checks, byte offsets, and SHA-256 hashes. This generation used libaom
3.6.0 and libdav1d 1.5.4-0-g54706fc6 through FFmpeg 9.0.1.

The generated white-box tests call the shared `av1_reference_planes_wbtest.mbt`
helper. It expands the complete reference planes, parses the original sequence
and frame, requires one tile, and compares every coded-depth YUV sample with the
cropped internal decoder planes. It also requires public `av1_decode` to succeed
and compares every RGBA pixel after applying the existing color converter to the
reference. The sample comparison retains 10/12-bit precision that RGBA could
otherwise hide; using the same converter avoids unrelated FFmpeg RGB rounding.
