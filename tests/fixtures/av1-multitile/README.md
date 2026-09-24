# External multi-tile AV1 references

These nine OBU files are unchanged `aomenc` outputs. They cover 128x64 (2x1
tiles), 64x128 (1x2 tiles), and 128x128 (2x2 tiles) at 8, 10, and 12 bits.
Every tile is one 64x64 superblock with a distinct constant luma and neutral
chroma. The encoder disables in-loop filtering, alternate intra predictors,
partition search, and transform-size search.

Regenerate from the repository root:

```text
python scripts/generate-av1-multitile-reference.py --aomenc <path-to-aomenc>
```

The generator independently decodes each stream with FFmpeg's `libdav1d`,
checks every Y/U/V sample in every tile, and writes the actual decoded tile
constants to `manifest.json`. The manifest includes executable versions and
hashes, encoder/decoder commands, source/OBU/decoded hashes, and traced frame
header constraints. Temporary command paths use `{work_dir}`.

`av1_multitile_reference_test.mbt` embeds the original OBU bytes and calls the
public `av1_decode` entry. It compares every output pixel with PixelForge's
YUV conversion applied to the recorded dav1d planes, so RGB converter rounding
does not obscure tile entropy/reconstruction differences. For 12-bit input the
decoded constants differ slightly from the source after quantization; the tests
use those decoded values, not the source values.
