# Directional tile decoding references

This corpus contains 12 untouched libaom stock streams and 8 complete syntax
constructions. All 20 streams have matching native planar output from unmodified
dav1d CLI 1.2.1 and FFmpeg/libdav1d 1.5.4, and matching output after AVIF remux.
The `.reference.yuv` files are the canonical expected samples. White-box tests
generate RLE from those files; the manifest contains no duplicate pixel arrays.

The stock matrix is 8/10/12-bit × four directional textures at 32×32. The
encoder requested min/max partition size 16; two streams actually split a 16×16
node into four 8×8 blocks. The independent Python entropy reader decodes every
partition, mode, angle delta, coefficient and final tile termination bit. It
confirms 54 coding blocks, including nonzero-angle Z1/Z2/Z3 modes in both Y and
UV. Per-stream `.syntax.json` files record the actual syntax; control flags are
not used as coverage evidence.

The eight constructed streams cover:

- SPLIT versus VERT_A top-right availability at the bottom-left 8×8 block.
- SPLIT versus VERT_B bottom-left availability at the top-right 8×8 block.
- Separate Y and UV SMOOTH neighbors, with 8×8 transforms where filter type
  changes upsampling. An unchanged pinned libaom C predictor, supplied with the
  actual native neighboring edges, confirms that the wrong type changes every
  tested plane. `smooth_context_probes.u16` stores these small counterfactual
  prediction probes; full-image expected samples still come from dav1d.
- A 4×4 UV owner at luma (20,12), UV (8,4), with a 29×29 visible crop and 32×32
  coded MI extent.
- Two independent 128×128 coding-block tiles in a 256×128 frame, SELECT 32×32
  Y transforms, 32×32 UV transforms and the normative 64-pixel chunk order.

Constructed `.syntax.json` files record every block and transform. They are
generated afresh with the existing range-encoder primitives, never by patching
an encoder's entropy bytes. The final matrix has eight constructions; the two
SMOOTH plans use 32×32 frames because a preliminary 4×4 UV target did not
distinguish filter types at 81 degrees.

Color API checks use the established nearest-420 converter from the exact
native planes, full range and matrix 2. Actual scalar libavif RGBA and FFmpeg
RGBA files are retained, with their conversion differences recorded; vendor
RGB parity is not asserted.

Reproduce in an empty output directory with the recorded native tools:

```text
python scripts/generate-av1-directional-tile-reference.py
python scripts/generate-av1-directional-tile-reference.py --conformance
python scripts/generate-av1-directional-tile-reference.py --evidence --aom-source <pinned-checkout>
python scripts/generate-av1-directional-tile-reference.py --check
```

`--evidence` requires TinyCC and the pinned libaom checkout used by
`generate-av1-directional-reference.py`. `--check` uses no encoder, decoder or C
compiler: it verifies stored hashes, all stock syntax, deterministic constructed
bytes and standalone-moonfmt output. No command runs a MoonBit build or writes
a root white-box test; tests remain under `_refs` until explicitly published.
