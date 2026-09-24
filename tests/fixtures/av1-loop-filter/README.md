# AV1 deblocking frame references

This bounded corpus contains 16 cases: color and monochrome at 8/10/12 bits,
with deblocking alone or with CDEF, followed by four seam/crop/transform cases.
Restoration, super-resolution, segmentation, delta quantization and delta-LF
are disabled and checked in actual frame headers.

Eleven complete streams are untouched libaom 3.6.0 output. Five 10-bit TX16
cases selected all-zero filter levels. Those cases retain the original
`.stock.obu` and reconstruct only the loop-filter fields, byte alignment and
enclosing OBU size. Every original tile entropy byte is unchanged. The
constructed stream with deblocking disabled must also equal the original
zero-level stream decoded with all filters. `header_construction` identifies
these cases explicitly.

Each reference must match unmodified dav1d 1.2.1 and FFmpeg's dav1d 1.5.4,
including after AVIF remux without re-encoding. The `.nodeblock.yuv` reference
comes from the **identical stream**, using `--inloopfilters nodeblock`.
Its per-plane differences are stored in the manifest. With CDEF enabled,
these differences include the effect of deblocking on subsequent CDEF;
changed chroma samples alone do not prove that plane's deblock level was
nonzero.

Actual first partitions are read with an independent MSAC prefix decoder.
The actual `tx_mode=LARGEST` header then establishes the first transform size.
This proves first TX4, TX8 and TX16 cases, without claiming all later block
geometry from encoder options. All actual `loop_filter_sharpness` values are
zero: the encoder's `--sharpness=3` option on one case biases coefficients and
does not establish nonzero loop-filter sharpness coverage.

The two-tile cases change samples on both sides of horizontal or vertical
seams. The 95×63 case retains odd visible dimensions and native 4:2:0 chroma
rounding. The generated tests compare every native sample before checking the
existing nearest-420 RGBA contract. Monochrome RGBA uses actual scalar libavif
UNORM output. No vendor color-RGBA parity is claimed.

```powershell
python scripts/generate-av1-loop-filter-reference.py
python scripts/generate-av1-loop-filter-reference.py --check
```

Generation writes the prospective test under `_refs` by default. `--check`
validates artifact hashes and rebuilds that test in memory without encoding or
writing files. This corpus covers intra-frame deblocking; it does not claim
inter-frame, segmentation or delta-LF coverage.
