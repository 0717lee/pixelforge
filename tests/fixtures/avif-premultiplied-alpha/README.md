# Premultiplied AVIF alpha references

These 17 containers verify that static AVIF items and animated AVIF tracks produce
**straight RGBA**, honoring the color-to-alpha `prem` reference. Expected pixels
come from unmodified **libavif 0.11.1**, using libaom 3.6.0 for encoding and dav1d
1.2.1 for decoding. PixelForge never generates the expected values. Exact codec
versions, settings, per-frame differences and artifact hashes are recorded in
[manifest.json](manifest.json).

All images are 16×16. The source uses native-depth premultiplied nonlinear RGB,
with each channel between zero and alpha. Coverage includes zero, full coverage,
partial coverage and native values 1, 2, 3, 8, 9, 24 and 25. Color and alpha are
encoded losslessly with one thread, speed 6 and quantizers zero. Regeneration
checks decoded native YUV and alpha against the planes supplied to the encoder.

| Cases | Count | Coverage |
| --- | ---: | --- |
| Static and three-frame animation, matrix 6 | 6 | Nonneutral 4:4:4 at 8, 10 and 12 bits |
| Static and three-frame animation, identity matrix 0 | 4 | Nonneutral 4:4:4 at 10 and 12 bits |
| Static and three-frame animation, YCgCo matrix 8 | 2 | Nonneutral 4:4:4 at 10 bits |
| Static monochrome YCgCo | 1 | Native 10-bit alpha fusion |
| Swapped physical track order | 2 | Matrix 6/8-bit and identity/12-bit retain pixels and timing |
| Reference direction/target controls | 2 | Reversed static `prem`, and animation `prem` targeting color instead of alpha |

Animations use timestamps 0, 100 and 300, durations 100, 200 and 300, and
timescale 1000. The controls change only reference metadata; AV1 samples remain
unchanged. Libavif reports `alphaPremultiplied=false` for both controls, and their
saved straight outputs differ from the corresponding premultiplied cases.

The oracle requests RGBA8, nearest chroma (`chromaUpsampling=3`),
`avoidLibYUV=1` and `alphaPremultiplied=0`. This fixture set additionally requires
a libavif build **without libyuv**. For matrix 6, libavif first quantizes RGB and
alpha to eight bits, then unpremultiplies. Its high-depth identity and YCgCo
paths instead fuse native alpha into Float32 conversion before final rounding.
The manifest records 371–432 differing bytes per such frame versus the incorrect
RGB8-first alternative. These cases also distinguish Float32 rounding boundaries
from unrestricted Double arithmetic; the tests require exact bytes. See the
upstream [conversion dispatch](https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/reformat.c#L1261)
and [alpha conversion](https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/alpha.c#L231).

Each `.avif` is a complete container. A `_frameN.rgba` file contains 1024 row-major
RGBA8 bytes. `_frameN.alpha.bin` contains 256 native alpha samples;
`_frameN.yuv.bin` contains consecutive full-resolution Y, U and V planes, or only
Y for monochrome. Native samples are unsigned bytes at 8 bits and little-endian
unsigned 16-bit words at 10/12 bits, without row padding. Swapped-track cases
reuse the original reference files through the manifest's `reference` field.
The generated [whitebox tests](../../../avif_premultiplied_alpha_reference_wbtest.mbt)
compare every output RGBA byte and every native alpha sample.

From the repository root, use Python 3 and a compatible libavif 0.11.1 shared
library with its dependent libraries available to the operating-system loader:

```sh
python scripts/generate-avif-premultiplied-alpha-reference.py --libavif /path/to/libavif.so --check
python scripts/generate-avif-premultiplied-alpha-reference.py --libavif /path/to/libavif.so
```

On Windows, pass a quoted path to `avif.dll`; on macOS, use `libavif.dylib`.
The default is `avif.dll`. The version-checked ctypes bindings reject other
libavif ABIs. Regeneration also requires the `moonfmt` executable and rewrites
the fixtures, manifest and generated whitebox file.

`--check` requires the actual decoding library: it verifies hashes, independently
redecodes all 17 existing containers, compares native YUV/alpha and RGBA files,
checks alpha input values, timing and recorded rounding differences, and checks
the generated whitebox source. It does not re-encode, run Moon tests or write
repository files. The recorded fixture set passed this independent re-decode
check in full.
