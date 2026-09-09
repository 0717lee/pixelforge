# PixelForge CLI

`cmd/cli` is a native codec utility. It supports `info` and `convert` for PNG,
QOI, BMP, GIF, JPEG, WebP, AVIF, and baseline TIFF signatures. JPEG/WebP
outputs and baseline TIFF input are available on native; WebP/AVIF decoding
and TIFF encoding remain unsupported by the native CLI. `convert` can apply an
ordered filter pipeline before encoding.

The native executable reads and writes files directly:

```text
moon run --target native cmd/cli -- info --input input.png
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
moon run cmd/cli -- info --input-hex 89504e470d0a1a0a...
moon run cmd/cli -- convert --from png --to qoi --input-hex 89504e470d0a1a0a...
```

Malformed options, signatures, and codec data abort with a non-zero exit.
