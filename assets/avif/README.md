# AVIF adapter fixture

`grayscale.avif` is a 4x2 lossless AVIF encoded from our synthetic gray levels
`0, 32, 64, 96, 128, 160, 192, 255` in row-major order. `grayscale.rgba` is its
32-byte RGBA reference decoded independently with FFmpeg's libdav1d decoder.
The fixture is covered by this project's Apache-2.0 license.

Generated with FFmpeg 9.0.1, libaom-av1 and libdav1d:

```python
from pathlib import Path
levels = [0, 32, 64, 96, 128, 160, 192, 255]
Path("source.ppm").write_bytes(
    b"P6\n4 2\n255\n" + bytes(v for g in levels for v in (g, g, g))
)
```

```sh
ffmpeg -v error -y -i source.ppm -frames:v 1 -c:v libaom-av1 -crf 0 -cpu-used 8 -pix_fmt yuv444p -color_range pc -vf scale=in_range=pc:out_range=pc grayscale.avif
ffmpeg -v error -y -c:v libdav1d -i grayscale.avif -frames:v 1 -pix_fmt rgba -f rawvideo grayscale.rgba
```

`avif_test.mbt` embeds the same 328 AVIF bytes so library tests work without
filesystem access on all targets. `scripts/check-cli.mjs` uses these files
to check native AVIF -> invert -> PNG -> BMP conversion against the reference.
