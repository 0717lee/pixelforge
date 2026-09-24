# Filter-intra tile references

The corpus contains 12 untouched libaom streams (color/monochrome × 8/10/12-bit
× two textures) and five complete syntax constructions. Every canonical native
YUV/Y binary matches unmodified dav1d CLI 1.2.1, FFmpeg/libdav1d 1.5.4 and the
decoded AVIF remux. The scalar filter-intra kernel oracle is a separate corpus.

All stock streams are independently parsed through complete partition, mode,
filter-mode, transform/coefficient syntax and valid tile termination. The 90
stock coding blocks include 82 active filter-intra blocks, each with nonzero
AC. Mode counts are `[16, 22, 22, 8, 14]`. Every color/depth group actually
selects all five modes across its two textures. Encoder flags alone are not
used as coverage evidence.

The five q32 constructions cover:

| Filter mode | Additional tile behavior |
| --- | --- |
| 0, DC | 13×13 visible crop and a skipped block that still reads filter syntax |
| 1, V | 4×16 coding blocks and chroma ownership |
| 2, H | 16×4 coding blocks and chroma ownership |
| 3, D157 | 32×32 coding block with SELECT 16×16 Y transforms |
| 4, PAETH | 4×4 coding blocks, sub-8 chroma owners and 13×13 crop |

All non-skipped construction transforms have off-DC coefficients. The filter
flag CDF uses the full coding-block enum. Its mode maps only the Y transform
CDF direction to `[DC,V,H,D157,DC]` (`[0,1,2,6,0]`); raw Y mode remains DC and
UV has no filter-intra syntax. Each construction records every block and
transform in `.syntax.json`. No encoder entropy is patched.

`.reference.yuv` files are the canonical expected pixels. Test RLE is derived
from those files and is not duplicated in the manifest. Color API checks use
the established nearest-420 conversion contract; vendor RGB is retained without
claiming parity. Monochrome RGBA is actual scalar libavif full-range UNORM.
These streams do not claim to exercise output saturation.

Generate the bounded stages in an empty output directory, using the recorded
native tools, then check without encoding or decoding:

```text
python scripts/generate-av1-filter-intra-reference.py
python scripts/generate-av1-filter-intra-reference.py --conformance
python scripts/generate-av1-filter-intra-reference.py --evidence
python scripts/generate-av1-filter-intra-reference.py --check
```

`--check` verifies artifact/source hashes, complete stock entropy traces,
deterministic constructed bytes and standalone-moonfmt output. Tests remain
under `_refs`; no command runs MoonBit builds or publishes a root test file.
