# PixelForge CLI

`cmd/cli` is a native codec utility. It supports pixel decoding for PNG, QOI,
BMP, GIF, JPEG, WebP, and TIFF. JPEG/WebP outputs and lossless WebP/TIFF input
are available on native. TIFF output is unavailable. `convert` can apply an
ordered filter pipeline before encoding.

For AVIF input, `info` reads container metadata without decoding pixels and
prints `metadata_only=true` alongside the format, dimensions and input size.
The probe reads the primary item's associated `ispe` dimensions; track-only
sequences without primary-item dimensions remain unsupported.
`convert` rejects AVIF input and output. Browser-only AVIF encoding does not
make it a supported native output format.

The native executable reads and writes files directly:

```text
moon run --target native cmd/cli -- info --input input.png
moon run --target native cmd/cli -- info --input input.avif
moon run --target native cmd/cli -- convert --from png --to qoi --input input.png --output output.qoi
moon run --target native cmd/cli -- convert --from png --to png --pipeline grayscale,contrast:1.2 --input input.png --output filtered.png
```

Pipeline operations are comma-separated. Parameterized operations use `:`:
`brightness:N`, `contrast:N`, `threshold:N`, `pixelate:N`, `posterize:N`,
`gamma:N`, `vignette:N`, and `canny:N`. The remaining operations take no
parameter; an unknown operation or malformed value fails with a non-zero exit.

For deterministic portable smoke tests, `--input-hex` remains available and
prints converted bytes as hexadecimal. The filesystem implementation is
native-only; the core library and other targets remain backend agnostic.

```text
moon run --target native cmd/cli -- info --input-hex 89504e470d0a1a0a...
moon run --target native cmd/cli -- convert --from png --to qoi --input-hex 89504e470d0a1a0a...
```

Malformed options, signatures, and codec data abort with a non-zero exit.
