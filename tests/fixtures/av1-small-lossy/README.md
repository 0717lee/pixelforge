# Lossy small-rectangle conformance references

Exactly eight complete AV1 syntax constructions cover color and monochrome
10-bit images with 4x8, 8x4, 4x16 and 16x4 coding blocks. These are not encoder
outputs, encoder searches, or edits to another stream's entropy payload.

Every frame uses `base_q_idx=32`, `TX_MODE_LARGEST`, DC prediction and DCT_DCT.
Each luma transform has the requested rectangular coding-block dimensions.
Chroma owners use their normative full residual sizes: 4x4, 4x8 or 8x4.
All 36 transforms (24 Y, 12 UV) contain positive quantized level 2 at the first
three default-scan positions: DC and two off-DC positions. EOB=3 and levels<=2
make coefficient-base coding sufficient; no BR or Golomb syntax is implied.
These cases exercise lossy integer DCT reconstruction, unlike the earlier q0
small rectangles, which use 4x4 Walsh-Hadamard transforms.

The generator checks every used default coefficient CDF family plus skip,
intra/UV mode, intra transform type and partition CDFs against pinned libaom
source at `8e7b6a567df174d795479b92b4ac766d271add73`. It also compares the complete
4x4/4x8/8x4/4x16/16x4 scans after converting libaom's column-major coefficient
storage, and checks geometric coefficient-context offsets. Source paths and
hashes are recorded. The independent first-leaf reader verifies the requested
partition, skip0/DC mode, DCT_DCT and nonzero-AC EOB prefix. Every arithmetic
symbol is additionally replayed through the MSAC decoder dual; this arithmetic
check is distinct from the external AV1 decoder validation.

Both unmodified dav1d CLI and FFmpeg/libdav1d must produce identical complete
native planes. FFmpeg's AVIF remux must decode to the same native samples. Every
transform has observable within-transform variation in those external samples;
a step between constant blocks is insufficient. Filters are disabled, and each
transform's DC predictor is constant, so this variation demonstrates AC content.

Canonical artifacts are the original constructed OBU, actual AVIF remux, native
YUV/Y binary, scalar-libavif RGBA binary, and separately recorded FFmpeg RGBA.
The manifest stores hashes, metadata, commands and source evidence, without
duplicating full pixel RLE. Prospective MoonBit RLE is generated from the hashed
binaries. Color RGBA assertions use the project's existing nearest-420
conversion contract from the exact native samples; only monochrome RGBA claims
scalar-libavif parity. Vendor color-conversion differences remain recorded.

```sh
python scripts/generate-av1-small-lossy-reference.py --aom-source PATH_TO_PINNED_AOM
python scripts/generate-av1-small-lossy-reference.py --check
```

The initial default AOM path is the session's temporary checkout; pass an
explicit path when reproducing elsewhere. Generation requires the existing
reference helpers and go-av1 tables, FFmpeg/libdav1d, dav1d CLI, the installed
version-checked scalar libavif 0.11.1 library, and standalone `moonfmt`.
`--check` rebuilds all eight OBU/syntax descriptions, verifies artifact/support
hashes and compares canonical prospective test text. It does not invoke an
encoder, decoder or MoonBit compiler. Tests remain at
`_refs/av1_small_lossy_reference_wbtest.mbt` until the main task publishes them.

This corpus establishes these eight lossy rectangular-transform paths. It does
not claim all transform types, arbitrary coefficient levels, or general AV1
feature coverage.
