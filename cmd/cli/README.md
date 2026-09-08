# PixelForge CLI

`cmd/cli` provides a portable codec smoke utility for native, JS, and wasm-gc
targets. It supports `info` and `convert` for PNG, QOI, BMP, and GIF input;
PNG, QOI, and BMP output are supported.

The current MoonBit core has no filesystem API shared by all three targets, so
the CLI accepts hexadecimal bytes with `--input-hex` and prints converted bytes
as hexadecimal. This keeps the command deterministic and avoids a native-only
file I/O implementation. A future host wrapper can translate files to/from hex.

```text
moon run cmd/cli -- info --input-hex 89504e470d0a1a0a...
moon run cmd/cli -- convert --from png --to qoi --input-hex 89504e470d0a1a0a...
```

Malformed options, signatures, and codec data abort with a non-zero exit.
