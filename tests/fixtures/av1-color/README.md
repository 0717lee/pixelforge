# AV1 CICP and AVIF nclx references

These 14 real, losslessly encoded 16×16 4:4:4 samples exercise identity,
BT.709 nclx overrides, FCC, SMPTE 240M, YCgCo full/limited range, BT.2020
non-constant/constant luminance, chromaticity-derived NCL/CL, PQ/HLG ICtCp,
and SMPTE 2085 YDzDx with XYZ primaries. They use 8-, 10-, and 12-bit native
samples, including nonzero low bits. `manifest.json` records each stream's
actual primaries, transfer, matrix, range, command arguments, and file hashes.

The `.obu` payloads are untouched libaom output. FFmpeg remuxes them into
`.avif`; the two `nclx709_*` containers supply their colour description through
nclx while the original AV1 sequence declares values 2 (unspecified). The
range flag remains consistent between each sequence and its container.

Every `.yuv` is independently decoded by dav1d and must equal the lossless
encoder input. It contains full-size Y, U, V planes, with 10/12-bit samples in
little-endian uint16. Every `.rgba` is row-major RGBA8. The generated white-box
tests compare native YUV sample-for-sample and exercise the public AVIF API.

## Conversion convention and references

Output is source-primary, source-transfer nonlinear RGB, clipped and rounded
once to 8 bits. There is no HDR display mapping or chromatic adaptation.
XYZ primaries are explicitly converted from linear XYZ to BT.709 D65 RGB and
then sRGB; they are never presented as if X/Y/Z were R/G/B. All fixtures are
4:4:4, so these references do not make a chroma interpolation claim; the
decoder's subsampled adapter uses nearest-neighbour replication.

The first eight fixtures use libavif 0.11.1's scalar conversion with
`avoidLibYUV=1`. CL and ICtCp use FFmpeg 9.0.1's zscale/zimg conversion to
linear floating-point RGB. `.linear-gbr.f32` preserves that independent
reference output. zscale applies display-oriented conversions by default:
requesting linear output avoids its final BT.1886 curve, and the generator
explicitly removes its HLG OOTF before applying the source H.273 curve. This
keeps the comparison in the decoder's stated source-RGB convention.

The PQ reference has four single-channel differences caused by float32 zimg
arithmetic crossing an RGBA8 rounding boundary. An independent 80-digit
Decimal calculation of the normative integer ICtCp/LMS matrices and PQ
functions records the exact coordinates and both values under
`rounding_edges` in the manifest. Tests require those four channels to equal
the high-precision result, every other channel to equal zimg, and the maximum
difference from zimg to remain 1. Native YUV remains exact. These PQ RGBA
results are not described as byte-identical to zimg.

libavif and zscale do not implement the required source-convention YDzDx/XYZ
and limited YCgCo paths. Their two references use independent H.273 integer
YCgCo inversion or an exact rational solve from the BT.709 primary and D65
white-point coordinates. The decoder's inverse-matrix constants and functions
are not used to generate these expectations.

Primary specifications and reference implementation details:

- [AV1 ISOBMFF §2.3.4](https://aomediacodec.github.io/av1-isobmff/#semantics)
  defines field-wise nclx replacement of unspecified sequence metadata.
- [ITU-T H.273 (07/2024)](https://www.itu.int/rec/T-REC-H.273-202407-I/en),
  Tables 2–4 and matrix/range equations, defines the numeric transforms.
- [libavif scalar conversion](https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/reformat.c)
  and [colour coefficients](https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/colr.c).
- [zimg transfer selection](https://github.com/sekrit-twc/zimg/blob/master/src/zimg/colorspace/gamma.cpp)
  and [CL/HLG operations](https://github.com/sekrit-twc/zimg/blob/master/src/zimg/colorspace/operation_impl.cpp)
  explain the display-versus-scene distinction handled by the generator.

## Reproduction

Generation used libaom 3.6.0, dav1d 1.2.1, FFmpeg 9.0.1 and libavif 0.11.1.
The scalar ctypes binding checks the libavif version before using its ABI.
Tools can be supplied explicitly; no local developer path is required.

```sh
python scripts/generate-av1-color-reference.py --libavif /path/to/avif.dll
python scripts/generate-av1-color-reference.py --check --libavif /path/to/avif.dll
```

`--aomenc`, `--dav1d`, `--ffmpeg`, and `--moonfmt` override tools discovered on
PATH. The generator uses only Python's standard library, the named reference
tools, and the repository's existing scalar libavif binding. `--check` performs
all regeneration in temporary storage and does not write repository files.
Ordinary MoonBit tests embed the references and need none of these tools.
