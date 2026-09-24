# AVIF grid sampling and color references

Six positive fixtures combine four distinct 64x64 lossless libaom/libavif cells
into 2x2 grids. They cover 8/10/12-bit 4:4:4 (99x97 output) and 4:2:2 (98x97
output). The odd crops exercise both unrestricted axes in 4:4:4 and the
unrestricted vertical axis in 4:2:2.

Cell sequence headers leave CP/TC/matrix unspecified (2). The primary grid
declares full-range BT.709 through `nclx` (1/13/1). Expected native planes are
independently decoded from the complete container by libavif 0.11.1 and must
equal the exact lossless source-cell composition. Expected RGBA comes from
libavif scalar conversion with `avoidLibYUV=1` and nearest-neighbor chroma
upsampling, matching PixelForge's public conversion contract.

Each `.native.bin` stores all native planes as row-major uint16 little endian,
including the 8-bit fixtures; `.rgba` stores RGBA8. Tests compare all native and
RGBA bytes through CRC32, and retain the full artifacts for pixel diagnosis.
The same expected RGBA is checked through explicit-grid, AVIF and RGBA entry
points. Two controlled incompatible-cell cases test rejection of mixed sampling
and bitstream color. The manifest records libavif's observed acceptance/rejection
separately from PixelForge's strict consistency requirement.

```sh
python scripts/generate-avif-grid-sampling-color-reference.py --libavif /path/to/avif.dll
python scripts/generate-avif-grid-sampling-color-reference.py --check
```

Regeneration uses the version-checked libavif 0.11.1 ABI, its libaom encoder,
Python and `moonfmt`. The grid BMFF structure is explicitly assembled around
unmodified encoded AV1 cells. `--check` reads artifacts and tests only; no codec
library or encoder is loaded.
