# AV1 mainline encoder references

These 22 fixtures are **untouched encoder output**. There are no bit flips,
header splices, patched tile symbols, or PixelForge-produced reference pixels.
The generator owns this directory's generated evidence and
`av1_mainline_reference_wbtest.mbt`; it does not refresh any older fixture set.

| Group | Cases | Actual decoded evidence |
| --- | --- | --- |
| Quantization matrices | 8/10/12-bit, 32×32 | `using_qmatrix=1`, level 5, four nonempty luma DCT coefficient blocks each |
| Intra-block copy | 8/10/12-bit 4:2:0, 256×128 | Three copied blocks each |
| Intra-block copy, residual | 8-bit 4:2:0, 256×128, q24 | Nine copied blocks; one copied luma transform has nonzero residual |
| Intra-block copy, 4:4:4 | 10-bit, 256×128 | Three copied blocks |
| Delta-LF | 8/10/12-bit, 128×128 | Decoded deltas `[-10,4,0,0]`, `[-10,10,0,0]`, `[0,4,0,0]` respectively |
| Delta-LF with active deblocking | 8-bit, 128×128, q48 ramp | Base luma levels `[0,1]`, deltas `[-12,2,0,-2]`; disabling deblock changes 105 native samples |
| Segmentation inheritance | 8-bit, four 128×128 frames | Segment IDs 0/1/5/6; frame 3 reuses both map and feature data |
| Temporal segmentation | 8-bit, four 128×128 frames | Frame 3 has temporal update and one non-skipped block that reads the prediction symbol; that symbol is 0 |
| Wedge compound | 8-bit, four 128×128 frames | Eight actual wedge-compound blocks |
| Compound global warp | 8-bit, four 128×128 frames | Seven GLOBALMV_GLOBALMV blocks; six use two nonidentity rotzoom models |
| Default tool combinations | 8/10/12-bit 4:2:0 and 10-bit 4:2:2/4:4:4, four 64×64 frames; 10-bit 256×128 two-tile stream | AC, partitions, adaptive CDFs, inter references, CDEF, Wiener/SGR and motion modes selected by the unmodified encoder |

The temporal fixture covers a coded false prediction symbol. It does not claim
that a block selected `seg_pred=1`. Segmentation feature coverage here is ALT_Q;
the test does not claim additional encoder-selected segment feature types.

The six `combined_*` cases retain libaom's default coding-tool switches. The
encoder command fixes quality, one thread, and zero lookahead for four directly
displayed frames. Only the two-tile case supplies tile layout parameters; none
uses `INTER_FLAGS`. Input planes contain nonneutral texture translated by
fractional pixels, and 10/12-bit inputs also contain nonzero low sample bits.
Every case has four entropy-adaptive frames and two frames inheriting a primary
reference context. Actual decoded tool counts are:

| Combined case | Luma AC transforms | Inter / compound blocks | Motion modes | CDEF symbols | Wiener / SGR units |
| --- | ---: | ---: | --- | ---: | ---: |
| 8-bit 4:2:0 64×64 | 17 | 6 / 1 | 0, 1, 2 | 4 | 9 / 2 |
| 10-bit 4:2:0 64×64 | 14 | 7 / 3 | 0 | 4 | 9 / 0 |
| 12-bit 4:2:0 64×64 | 12 | 8 / 0 | 0, 2 | 4 | 6 / 2 |
| 10-bit 4:2:2 64×64 | 21 | 3 / 2 | 0 | 4 | 9 / 1 |
| 10-bit 4:4:4 64×64 | 24 | 52 / 14 | 0, 1, 2 | 4 | 7 / 3 |
| 10-bit 4:2:0 256×128, two tiles | 90 | 105 / 20 | 0, 1, 2 | 29 | 10 / 3 |

Motion modes 0/1/2 are translation/OBMC/local warp in the dav1d symbol trace.
The manifest contains the complete sequence and frame headers, including the
actual filter strengths, reference indices, transform controls, and tile layout.
For combined traces, uncoded inter-intra mode/wedge fields and the unused wedge
index of a difference-weighted compound block are omitted. Upstream debug
printing reads these unused union members even when their tool is not selected;
their memory-dependent values are not bitstream evidence. Actual selections,
coded parameters, and entropy ranges remain in the transcript.

## Evidence and pixel layout

Each case has:

- `.obu`: the unmodified low-overhead AV1 stream.
- `.reference.yuv`: release dav1d 1.2.1 output, frame-major then Y/U/V,
  with tightly packed rows. Eight-bit samples are bytes; 10/12-bit samples are
  little-endian unsigned 16-bit integers. Chroma is 4:2:0 except the named
  `intrabc_444`, `combined_*_422`, and `combined_*_444` cases.
- `.trace.txt`: FFmpeg's independent `trace_headers` syntax transcript.
- `.symbols.txt`: decoded block positions and symbols from the trace-only
  dav1d build described below. In dav1d, `Post-intrabcflag[0]` means a copied
  block (`b->intra == 0`), and compound mode 6 is GLOBALMV_GLOBALMV.

`deltalf_filter_8bit_128x128.nodeblock.yuv` additionally records the same
stream decoded with `--inloopfilters nodeblock`. Its command, SHA-256 and
nonzero sample-difference count are in the manifest. CDEF and restoration are
disabled in this case, isolating the deblocking stage.

The generator compares every byte from the release and trace dav1d decoders.
The generated MoonBit tests preserve a frame map across the stream and compare
every native sample in every plane. They do not use RGBA conversion or image
hashes as a substitute for plane equality.

The generated test stores reference constants as RLE packets in hexadecimal
strings. Literal packets retain up to 128 samples; repeated packets retain
3–130 identical samples. The local helper expands the original 8-bit or
little-endian 16-bit values before performing the same per-sample assertions.
The reference `.yuv` files remain uncompressed and unchanged.

`manifest.json` stores exact argument arrays, dimensions, depth, input SHA-256,
artifact SHA-256/lengths, frame syntax, selected-symbol counts, tool versions,
executable/library SHA-256, and the trace patch SHA-256. The first fourteen
cases use standalone libaom 3.6.0. The two compound cases and six default-tool
cases use FFmpeg's libaom 3.14.1-147-gec0dedc1a2; this version is also captured
from the encoder log.

## Regeneration and read-only checks

Generated MoonBit source is formatted by `moonfmt` (or `MOONFMT`) before token
comparison, including the formatter's optional trailing commas.
Tools are resolved through `--aomenc`, `--dav1d`, `--ffmpeg`, and
`--trace-dav1d`, their corresponding uppercase environment variables, then
PATH. For example:

```text
python scripts/generate-av1-mainline-reference.py --trace-dav1d <debug-dav1d>
python scripts/generate-av1-mainline-reference.py --check --trace-dav1d <debug-dav1d>
python scripts/generate-av1-mainline-reference.py --check --select qmatrix --trace-dav1d <debug-dav1d>
python scripts/generate-av1-mainline-reference.py --check --select combined --trace-dav1d <debug-dav1d>
python scripts/generate-av1-mainline-reference.py --check --case wedge_8bit_128x128 --case compound_globalwarp_8bit_128x128 --trace-dav1d <debug-dav1d>
python scripts/generate-av1-mainline-reference.py --list
```

`--select` and repeatable `--case` limit re-encoding to the selected cases.
Other recorded cases are preserved when regenerating the shared test source.
`--check` puts encoder inputs, statistics, streams, and decoder outputs inside
a system temporary directory. It compares committed files without writing
them. MoonBit source comparison ignores comments and formatting whitespace,
so `moon fmt` does not require regenerating pixel evidence.

## Rebuilding the independent symbol tracer

Use the upstream [dav1d 1.2.1 source](https://code.videolan.org/videolan/dav1d/-/tree/1.2.1)
and apply `dav1d-debug.patch`. The patch enables upstream block logging and
adds one segmentation-state print. It changes no decoding decisions or sample
values. Build with Meson and Ninja:

```text
git apply <absolute-path-to>/dav1d-debug.patch
meson setup build --buildtype=debugoptimized -Denable_asm=false -Denable_tests=false -Denable_examples=false
ninja -C build
```

On Windows, run these commands in the compiler's developer command prompt and
place the built `src/dav1d.dll` beside `tools/dav1d.exe` before using the tool.
The source archive used for the recorded build had SHA-256
`2dd85860d213479672b1c708e31593446e8c2b53ff41e2ca25a2eafb718424e2`.
The manifest records the exact built executable and DLL, not just a version
label. Rebuilding a binary can change those provenance hashes even when the
encoded streams and decoded pixels remain identical.

## Encoder controls

The standalone encoder's `--help` and libaom's
[encodeframe.c](https://aomedia.googlesource.com/aom/+/refs/tags/v3.6.0/av1/encoder/encodeframe.c)
define the delta-Q/loop-filter relationship: `--deltaq-mode=2` enables varying
superblock quantizers, `--delta-lf-mode=1` derives the filter deltas, and
`--loopfilter-control=1` keeps filtering active. A header flag alone is not
accepted; the generator requires a decoded nonzero delta.

For intrabc, [encoder.c](https://aomedia.googlesource.com/aom/+/refs/tags/v3.6.0/av1/encoder/encoder.c)
enables screen tools for `--tune-content=screen`. The 256-pixel width gives the
decoder sufficient previously reconstructed superblocks for legal copies.
Actual copy/residual selection is verified from block symbols. Compound
coverage is similarly accepted only when the decoder selects wedge or two
nonidentity global models for an actual compound block.
