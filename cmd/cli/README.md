# PixelForge CLI

`cmd/cli` is the native codec utility for PixelForge **0.19.0**.
Use a repository checkout: `cmd/` is excluded from the mooncakes library package.
`convert` can apply an ordered filter pipeline before encoding.

AVIF input and `--fit` below are unreleased additions to the 0.19.0 baseline.

| Format | Input | Output |
| --- | --- | --- |
| PNG | Non-interlaced 8-bit | RGBA8 |
| QOI | Yes | Yes |
| BMP | Uncompressed 24/32-bit | 32-bit RGBA |
| GIF | First frame | Single frame, at most 256 palette entries |
| JPEG | Baseline | Quality 90, alpha discarded |
| WebP | Lossless VP8L | Lossless VP8L |
| TIFF / BigTIFF | Supported subset in either byte order | No |
| AVIF | Primary image through MoonAV1 0.2.0 | No |

See the [root format matrix](../../README.en.md) for TIFF compression/sample
restrictions, GIF alpha behavior and other codec boundaries.

For AVIF input, `info` reads container metadata without decoding pixels and
prints `metadata_only=true` alongside the format, dimensions and input size.
The probe reads the primary item's associated `ispe` dimensions; track-only
sequences without primary-item dimensions remain unsupported.
`convert` decodes AVIF input to RGBA8 through MoonAV1, including supported
alpha and grid images. Invalid or unsupported data fails before output is opened.
AVIF output remains unsupported on native.

Native builds require a C compiler. The executable reads and writes files
directly; `--output` replaces an existing file. Preserve the source or choose a
different output path when you need to keep the original.

```text
moon run --target native cmd/cli -- info --input input.png
moon run --target native cmd/cli -- info --input input.avif
moon run --target native cmd/cli -- convert --from avif --to png --pipeline grayscale --input input.avif --output output.png
moon run --target native cmd/cli -- convert --from avif --to png --fit 320x240 --input input.avif --output thumbnail.png
moon run --target native cmd/cli -- convert --from png --to qoi --input input.png --output output.qoi
moon run --target native cmd/cli -- convert --from png --to png --pipeline grayscale,contrast:1.2 --input input.png --output filtered.png
```

Pipeline operations are comma-separated. Parameterized operations use `:`:
`brightness:N`, `contrast:N`, `threshold:N`, `pixelate:N`, `posterize:N`,
`gamma:N`, `vignette:N`, and `canny:N`. The remaining operations take no
parameter; an unknown operation or malformed value fails with a non-zero exit.

`--from` and `--to` use the lowercase format names above (`tiff` also covers
BigTIFF); `--from` must match the detected input. Parameter defaults match the
typed pipeline in the [root guide](../../README.en.md).

`--input-hex` accepts non-empty hexadecimal bytes and prints converted data as
`hex=...`. This is an alternative input mode on the native executable, not a
promise that the CLI package compiles for JS or wasm-gc. Choose exactly one of
`--input` and `--input-hex`.

```text
moon run --target native cmd/cli -- info --input-hex 89504e470d0a1a0a...
moon run --target native cmd/cli -- convert --from png --to qoi --input-hex 89504e470d0a1a0a...
```

Success exits with code 0. Missing required values, invalid pipeline values,
unknown signatures and rejected codec data abort with a non-zero exit; the
exact panic exit code is platform-specific. Processing/encoding failures occur
before the output is opened. Filesystem write failures can leave a partial file.

Options must be known, unique name/value pairs. Missing values and nonfinite
pipeline numbers are rejected. `info` accepts only input options. `--output`
requires `--input`; hexadecimal input always returns hexadecimal output on stdout.

`--fit WIDTHxHEIGHT` fits within positive integer bounds before applying filters.
It uses alpha-weighted bilinear sampling to prevent transparent color fringes,
preserves aspect ratio to integer-pixel precision,
does not crop or enlarge, and rounds the shorter dimension down to at least one
pixel. It works with file and hexadecimal input. Reported dimensions describe
the converted output. Invalid bounds fail without creating an output file.

Run `node scripts/check-cli.mjs` from the repository root for BigTIFF byte-order
checks, PNG → pipeline → QOI → BMP pixel checks, AVIF → invert → PNG conversion
against a libdav1d reference, AVIF metadata and rejection tests.
