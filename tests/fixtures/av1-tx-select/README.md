# Real AV1 transform-size selection references

These three real libaom streams encode the fixed16 64x64 partition corpus inputs
at 8, 10, and 12 bits with `--enable-tx-size-search=1`, `--cpu-used=0`, and q30.
Generation requires FFmpeg's header parser to report `tx_mode=2` (`SELECT`)
from each original OBU. No OBU header or entropy bytes are rewritten.

The streams retain DC-only intra prediction, DCT transforms, YUV420, 64x64
superblocks, and fixed square 16x16 coding blocks. Directional/smooth/Paeth
predictors, CFL, palette, filter intra, CDEF, restoration, loop filtering,
quantizer deltas, and quantizer matrices remain disabled. The corpus verifies
this actual transform-selection path, not general AV1 conformance.

From the repository root:

```sh
python scripts/generate-av1-tx-select-reference.py
moon test av1_tx_select_reference_wbtest.mbt --target js
```

The generator uses the existing partition manifest and its retained source YUV
files; `--source` selects that manifest. Other options are `--aomenc`, `--ffmpeg`,
`--moonfmt`, `--out`, and `--test`. It formats only its own generated test through
`moonfmt -` and writes no Python bytecode artifacts.

Each case retains the source input, untouched encoder OBU, and complete dav1d
reference Y/U/V planes. Ten- and twelve-bit samples use unsigned 16-bit
little-endian storage. The manifest records input formulas, exact commands,
encoder/decoder versions, actual header fields, plane offsets, and SHA-256
hashes. Generated white-box tests use `av1_reference_planes_wbtest.mbt` to compare
every coded-depth reference sample against the cropped internal YUV planes.
The shared helper validates the parsed sequence/frame and single-tile scope,
then requires public `av1_decode` to succeed and compares all 4096 RGBA pixels
using the existing color converter.
