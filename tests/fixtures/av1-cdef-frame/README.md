# AV1 frame-level CDEF references

Eight real libaom streams cover textured YUV420 at 8, 10, and 12 bits. Each bit
depth has a 64x64 single tile and a 128x64 frame with two adjacent 64x64 tiles.
Additional cases cover a 64x128/10-bit frame split into two tile rows and an odd
95x63/12-bit frame split into two tile columns. The latter has visible tile
widths 64 and 31, with 48x32 chroma planes and padded decoding before cropping.
The texture uses global coordinates and does not restart at the tile seam.
Every selected stream has nonzero CDEF strengths and observable filtered sample
changes. Both sides of the two-tile seam contain changed samples.

The accepted encodes use q30, texture amplitude 1, 64x64 superblocks, fixed
16x16 coding blocks, and `ONLY_LARGEST` transforms. DC, V/H, smooth, and Paeth
prediction searches are enabled, with intra-default DCT/ADST transforms.
Diagonal prediction, angle delta, CFL, palette, filter intra, intra-edge
filtering, loop filtering, restoration, quantizer deltas, quantizer matrices,
and lossless mode are disabled. CDEF damping is 4; the manifest retains the
actual `cdef_bits` and every luma/chroma primary/secondary strength.

From the repository root:

```sh
python scripts/generate-av1-cdef-frame-reference.py
moon test av1_cdef_frame_reference_wbtest.mbt --target js
```

The generator requires aomenc, FFmpeg with libdav1d, dav1d CLI with
`--inloopfilters`, Python, and moonfmt. Options are `--source`, `--aomenc`,
`--ffmpeg`, `--dav1d`, `--moonfmt`, `--out`, and `--test`. It formats only its
generated test through `moonfmt -`.

`*.obu` retains the original CDEF-on encoder output; `*.reference.yuv` is its
complete filtered FFmpeg/libdav1d output. The dav1d CLI must reproduce those
bytes exactly. `*.unfiltered.yuv` comes from decoding that identical OBU with
only CDEF disabled (`--inloopfilters nocdef`), so its differences demonstrate
the actual filter's effect. The CLI writes binary files because its older
Windows stdout performs newline conversion; its temporary filtered duplicate
is removed after the byte comparison succeeds.

The separately encoded `*.cdef_off.obu` and its reference use the matched
configuration with CDEF disabled. They are ancillary evidence: neither entropy
bytes nor prefilter reconstruction are assumed equal to the CDEF-on encode.

Each `*.avif` is a real AVIF container remuxed from its original OBU without
reencoding. Its independent dav1d YUV output must match the OBU reference exactly.
The temporary duplicate reference is removed after this comparison succeeds.

Raw files contain full Y, U, then V planes; 10/12-bit samples use unsigned
16-bit little-endian storage. `manifest.json` records source formulas, exact
commands, versions, hashes, plane offsets, header strengths, sample changes,
and changes within two luma/one chroma samples of either side of a horizontal or
vertical seam. Odd frame dimensions use rounded-up chroma widths and heights.

White-box tests call `av1_decode_frame_planes` and `av1_frame_crop`, comparing
every filtered YUV sample. They also compare every public `av1_decode` RGBA
pixel and every automatic `avif_decode_rgba` container-entry pixel after applying
the existing color converter to the reference planes.
