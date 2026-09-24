# AV1 palette references

The stock corpus contains exactly 12 unmodified libaom streams: color and
monochrome at 8/10/12 bits, with three-color and six-color screen textures.
Actual palette colors retain high-depth low bits. CDEF, deblocking,
restoration, intrabc and the other optional intra predictors are disabled.

An independent Python MSAC reader records palette mode/size contexts, cache
selections, colors, V coding and diagonal color-index maps. It fully reads all
16 blocks in each monochrome stock image. Color cases contain real palette
plus nonzero chroma residuals; their traces explicitly stop at the first such
coefficient block. These partial traces are not described as full-frame
entropy traces. Every traced palette plane with zero residual is checked
against the independent native pixel oracle.

Seven separately labeled complete syntax constructions add:

- Y and UV palette sizes 2/4/5/7/8, complementing stock sizes 3/6.
- A 128×128 superblock whose above-color cache resets at luma row 64 while the
  above-palette mode context remains available.
- A 53×51 image with six maps padded from MI bounds to complete coding blocks.
- Fifteen partial-cache blocks and 112 signed V-color wrap events.
- 4×16 and 16×4 luma blocks, each with two actual chroma owners.
- Palette maps on `skip=1` blocks; the maps still consume entropy.

The constructions are deterministic legal bitstreams, not encoder output.
Their full independently read colors/maps match the unmodified dav1d result
at every visible sample. Every stock and constructed native reference also
matches a second dav1d build and an AVIF remux without re-encoding.

Expected native planes are stored as canonical binary files. Generated tests
compare native samples before the existing nearest-420 RGBA conversion;
monochrome RGBA uses actual scalar libavif UNORM output. Vendor color-RGBA
parity is not claimed.

```powershell
python scripts/generate-av1-palette-reference.py
python scripts/generate-av1-palette-reference.py --check
python scripts/generate-av1-palette-reference.py --constructed
python scripts/generate-av1-palette-reference.py --check-constructed
```

The default test paths are prospective files under `_refs`. Check commands
verify hashes and reproduce the tests without encoding or writing files;
`--check-constructed` also reconstructs every conformance OBU byte-for-byte.
