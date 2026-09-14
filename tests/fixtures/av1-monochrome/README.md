# Native monochrome and alpha references

Nine original libaom streams cover full-range monochrome at 8, 10, and 12 bits.
Each bit depth includes q30 textured 64x64/single-tile and 128x64/two-tile frames
with nonzero CDEF, plus a lossless q0 64x64 ramp spanning zero to the maximum
coded value. The encoder uses fixed16 coding blocks, seven DC/axis/smooth/Paeth
prediction searches, largest transforms for q30 and 4x4 WHT for q0. Other
unsupported tools, loop filtering, and restoration are disabled.

The native `*.reference.yuv` contains only Y samples. FFprobe must identify
`gray`, `gray10le`, or `gray12le` before raw extraction; the dav1d CLI must
reproduce the exact bytes. No RGB conversion or grayscale range rescaling is
used as the entropy-decoder oracle. Lossless references must equal the original
`*.source.yuv` samples byte for byte. Same-OBU `nocdef` references demonstrate
actual CDEF changes in every q30 sample.

The Y4M input requests `XCOLORRANGE=FULL`, producing an original sequence header
with `mono_chrome=1` and `color_range=1`. Aomenc 3.6 supports `Cmono` at 8 bits,
but not `Cmono10/12`; high-depth inputs therefore use `C420p10/12` with neutral
UV carrier samples ignored by `--monochrome`. Native Y samples remain unchanged.

```sh
python scripts/generate-av1-monochrome-reference.py --test av1_monochrome_reference_wbtest.mbt
moon test av1_monochrome_reference_wbtest.mbt --target js
```

Use `--test <path> --moonfmt <executable>` to additionally generate white-box
tests. Other options select `--source`, `--out`, `--aomenc`, `--ffmpeg`,
`--ffprobe`, `--dav1d`, and `--libavif-scalar`. The scalar conversion binding
checks the recorded libavif 0.11.1 ABI before calling it. Commands, versions,
source formulas, byte hashes, strengths, and sample summaries are recorded in
`manifest.json`. Native Y, gray8, and alpha8 samples are read from their canonical
binary reference files after checking the recorded hashes and dimensions. RLE
is generated only for the white-box test.

`python scripts/generate-av1-monochrome-reference.py --verify-existing-test`
rebuilds the recorded test in memory and requires identical bytes. This check
uses `moonfmt -` and performs no encoding or file writes.

Limited-range conversion vectors are also recorded for black, middle, white,
and out-of-range samples at each depth. They come from the same actual scalar
API after changing only the decoded image's in-memory `yuvRange` to limited;
the original full-range OBU and native samples are preserved.

Three `color_alpha_*bit.avif` files assemble existing real color and monochrome
AV1 items into standards BMFF containers. They are explicitly container assembly,
not encoder outputs: `auxl` points from alpha item 2 to primary item 1, and
`auxC` declares the standard alpha auxiliary type. Both item payloads and AV1
configuration records come from genuine, separately remuxed AVIF sources.

Eight-bit alpha/grayscale references come from an actual libavif decode and
`avifImageYUVToRGB` with `avoidLibYUV=1`. This implements normalized nearest UNORM:
`(value*255 + max/2)/max`, with integer division and `max=(1<<bit_depth)-1`.
The 10/12-bit ramps include endpoints and low values, exposing 680/952 samples
where a simple right shift differs from that reference.

Default Pillow/libavif output is retained separately. On this machine its
10-bit fast conversion matches a right shift and differs from the scalar oracle
at 680 samples; its 12-bit output matches the scalar oracle. The corpus does not
claim these distinct conversion paths produce the same result. Native-depth Y
remains the primary decoding oracle; alpha normalization is a separate API
contract. Generated alpha-container tests compare alpha to the scalar oracle and
require RGB to preserve the independently decoded primary image, without claiming
RGB parity with a different vendor's color converter.

Primary references: [libavif alpha conversion](https://raw.githubusercontent.com/AOMediaCodec/libavif/v1.4.2/src/alpha.c),
[AVIF auxiliary image requirements](https://aomediacodec.github.io/av1-avif/v1.1.0.html#auxiliary-image-items-and-sequences).
