# PixelForge CLI

`cmd/cli` is a native codec utility. It supports `info` and `convert` for PNG,
QOI, BMP, and GIF input; PNG, QOI, and BMP output are supported.

The native executable reads and writes files directly:

```text
moon run --target native cmd/cli -- info --input input.png
moon run --target native cmd/cli -- convert --from png --to qoi --input input.png --output output.qoi
```

For deterministic portable smoke tests, `--input-hex` remains available and
prints converted bytes as hexadecimal. The filesystem implementation is
native-only; the core library and other targets remain backend agnostic.

```text
moon run cmd/cli -- info --input-hex 89504e470d0a1a0a...
moon run cmd/cli -- convert --from png --to qoi --input-hex 89504e470d0a1a0a...
```

Malformed options, signatures, and codec data abort with a non-zero exit.
