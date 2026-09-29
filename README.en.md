# PixelForge

[![CI](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml/badge.svg)](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml)

[简体中文](README.md) | English

PixelForge is a MoonBit RGBA8 library with filters, geometry, drawing, analysis and codecs, plus a native CLI and browser Playground. The core supports JavaScript, wasm-gc and native; the Playground also provides a linear-memory WebAssembly engine.

**The current version is `0.19.0`.** It removes the former AV1/AVIF parsing and pixel-decoding APIs. Read the [migration guide](docs/MIGRATION.md) before upgrading from `0.18.0`. The historical GitHub `v1.0.0` marker corresponds to the earlier `0.10.0` package, not the current version. See [CHANGELOG](CHANGELOG.md) for history.

## Quick start

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), create a project, and add the dependency:

```sh
moon new pixel-demo --user demo_user
cd pixel-demo
moon add 0717lee/pixelforge@0.19.0
```

Set `cmd/main/moon.pkg` to:

```moonbit
import {
  "0717lee/pixelforge",
}

pkgtype(kind: "executable")
```

Replace `cmd/main/main.mbt` with this complete example:

```moonbit
///|
fn main {
  let image = @pixelforge.Image::new(2, 1)
  image.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  image.set_pixel(1, 0, b'\x00', b'\xFF', b'\x00', b'\xFF')
  let pipeline = @pixelforge.Pipeline::new()
    .append(@pixelforge.Filter::Grayscale)
    .append(@pixelforge.Filter::Brightness(10))
  let processed = image.apply_pipeline(pipeline)
  let png = @pixelforge.png_encode(processed)
  let decoded = match @pixelforge.png_decode(png) {
    Some(value) => value
    None => abort("PNG decoding failed")
  }
  if decoded.data != processed.data {
    abort("PNG round-trip changed pixels")
  }
  println("\{decoded.width}x\{decoded.height} PNG round-trip OK")
}
```

Run `moon run cmd/main`; expected output is `2x1 PNG round-trip OK`. Select another backend with `--target js` or `--target native`; native requires a platform C compiler. The same example lives in [cmd/quickstart](https://github.com/0717lee/pixelforge/blob/main/cmd/quickstart/main.mbt); run `moon run cmd/quickstart` in this repository to exercise the current source.

## Features and API

| Category | Main capabilities |
| --- | --- |
| Filters and tone | Grayscale, invert, brightness, contrast, threshold, sepia, pixelate, median, histogram equalization, posterize, gamma, vignette, saturation, hue, HSL lightness, levels, auto contrast |
| Convolution and edges | Custom `Kernel` / `convolve`, Gaussian/box blur, sharpen, emboss, Laplacian, Sobel, Scharr, Canny, bilateral filtering, unsharp mask |
| Geometry and drawing | Crop, pad, flips, rotation, affine matrices, nearest/bilinear/bicubic resize, lines/rectangles/circles, 5×7 bitmap text, source-over and eight blend modes |
| Analysis and features | RGB/luma histograms and statistics, Otsu/Sauvola/local-mean thresholds, morphology, skeletons, components/region statistics/contours, Harris, HOG, LBP, integral images, distance transform, flood fill |
| Comparison and noise | aHash/dHash/Hamming distance, MSE/PSNR/SSIM, deterministic Gaussian and salt-and-pepper noise, Floyd–Steinberg dithering |
| Composition and traversal | Typed `Filter` / `Pipeline`, numeric dispatch, pixel-buffer-sharing `for_each_tile` / `for_each_row` |

Current public signatures are in [pkg.generated.mbti](pkg.generated.mbti); source documentation comments describe parameters. The [mooncakes API documentation](https://mooncakes.io/docs/0717lee/pixelforge) describes the published package.

`Image` stores row-major RGBA bytes and requires `width * height * 4` bytes. `from_bytes` wraps the original buffer, so modifying it also changes the image; use `copy()` for independent ownership. Filters, geometry and pipelines return new images; `set_pixel`, drawing and text methods mutate images. Tiles and rows share their source pixels.

`mse` / `psnr` compare RGBA channels; `luma_mse` / `ssim` use Rec.601 luma and ignore alpha. `ssim` uses one population-statistics window over the whole image; equal-sized empty images return 1. Bilinear/bicubic resize interpolates RGBA channels independently without converting to premultiplied alpha.

## Formats and backends

“Core” means JavaScript, wasm-gc and native. Playground loading uses browser decoders, whose support is separate from the core codecs.

| Format | Core decode | Core encode | Main boundaries |
| --- | --- | --- | --- |
| PNG | Yes | Yes | Non-interlaced, 8-bit grayscale/grayscale-alpha/palette/RGB/RGBA; tRNS; CRC-32/Adler-32 checks; RGBA8 output |
| GIF | Yes | Yes | LZW, interlacing, transparency; single-frame encoding, at most 256 palette entries, alpha < 128 becomes transparent; exceeding limits aborts |
| QOI | Yes | Yes | Lossless RGBA round trips |
| BMP | Yes | Yes | Uncompressed 24/32-bit; 24-bit output drops alpha |
| JPEG | Yes | Yes | Baseline JPEG through `mizchi/image`; lossy, drops alpha; `jpeg_encode(image, quality)` |
| WebP | Lossless VP8L | Lossless VP8L | Predictor, cross-color, subtract-green and color-indexing transforms; no lossy VP8 decoding |
| TIFF | Subset | No | Classic: chunky 8-bit grayscale/RGB/RGBA, strips or tiles, uncompressed/PackBits/LZW/Deflate, Predictor=2; BigTIFF: one strip, uncompressed/PackBits/LZW, offsets and values within supported Int bounds |
| AVIF | Detection and metadata only | JS host adapter | No AV1 pixel decoder; encoding accepts opaque images only and requires Canvas AVIF encoding in browsers; the dependency uses local `ffmpeg` in Node.js; native/wasm-gc encoding aborts |

`detect_image_format()` recognizes signatures; `image_metadata()` reads supported dimensions. Neither proves that complete pixel data is decodable. TIFF/BigTIFF detection supports both byte orders. AVIF metadata follows the primary item's associated `ispe`; track-only sequences without primary-item dimensions are unsupported.

`gif_decode_all()` returns frame images, offsets, delays, transparency indices and disposal metadata; callers handle playback and compositing. `gif_decode()` returns the first frame. The core does not decode AVIF grids or animations.

Operators use `moonbitlang/core`; JPEG decode/encode, WebP encoding and AVIF adapters use `mizchi/image`; the native CLI uses `moonbitlang/x/fs`. Dependency versions and attribution are in [moon.mod](moon.mod) and [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).

## Errors, sizes and parameters

- Pixel decoders return `Image?` (multi-frame GIF returns an optional frame array). Malformed input or unsupported variants return `None`, which callers must handle.
- `Image::new` / `from_bytes` abort for negative dimensions, more than 100,000,000 pixels, or a mismatched buffer length. `abort` is a panic that terminates the current execution, not a recoverable decoding error handled by `catch`. Out-of-bounds pixel access and mismatched comparison/compositing sizes also abort.
- Either dimension may be zero. All three resizers clamp target dimensions to at least 1; an empty source produces a transparent image at that size. Follow each operator's own contract for other operations.
- Encoders may abort on format restrictions. Check format support, sizes, GIF palettes and AVIF alpha first. Hosts should limit upload bytes and pixels according to their memory budget.
- `Pipeline` and numeric dispatch share defaults: threshold ≤ 0 means 128; pixel block < 2 means 8; posterize levels < 2 means 4; gamma ≤ 0 means 2.2; vignette ≤ 0 means 0.5; Canny high threshold ≤ 0 means 100. Use direct `threshold(0)` / `vignette(0.0)` for explicit zero values. The numeric id table is in [dispatch.mbt](dispatch.mbt).

## Browser Playground and performance

From the repository root, with Node.js 22 or newer:

```sh
node serve.mjs
```

Open [localhost:8123](http://localhost:8123). Upload, drag/drop or paste images; edit parameterized pipelines; undo/redo; switch JS/WASM or Worker mode; download PNG. GIF preview retains animation while processing edits the loaded frame. WebP/AVIF loading depends on browser support.

Uploads are limited to 20 MiB, 16,000,000 pixels and an 8192-pixel side. Previews scale to a 1024-pixel longest edge; downloads use that resolution. Use the library or CLI for original-resolution processing.

Main-thread and Worker processing share [WasmPipeline](web/wasm-pipeline.js): equal buffer lengths reuse one allocation; length changes replace the instance so old memory can be collected. Hosts using low-level `alloc` must also manage instance lifetimes instead of allocating indefinitely on every render.

Relative speed depends on input, filters, host and copying costs. The page comparison uses the current preview and pipeline, warms each engine once, then averages ten runs. It includes pixel copies and computation, but excludes decoding, painting and Worker messaging. Run the reproducible Node.js benchmark with:

```sh
node scripts/benchmark.mjs
```

It reports Node/OS/CPU, fixed input and operations, warmup/sample counts, median/p95 and WASM memory, and checks pixel equality before timing. Results do not describe browser performance or imply a universal speed ratio.

## CLI

```sh
moon run --target native cmd/cli -- --help
moon run --target native cmd/cli -- info --input input.tiff
moon run --target native cmd/cli -- convert --from png --to qoi --pipeline grayscale,contrast:1.2 --input input.png --output output.qoi
```

`info` reads only metadata for AVIF; `convert` accepts neither AVIF input nor output. See the [CLI guide](https://github.com/0717lee/pixelforge/blob/main/cmd/cli/README.md) for formats, pipelines, exit behavior and file replacement. CLI examples are excluded from the mooncakes library package; use a repository checkout.

## Development and contributions

See [CONTRIBUTING](CONTRIBUTING.md) for the toolchain, checks, conventions and generated Web artifacts. [HANDOFF](HANDOFF.md) records scope and validation evidence; the [release guide](docs/RELEASING.md) covers version, package documentation and GitHub Release synchronization.

Directory entry points: core code and tests at the root; examples in `cmd/`; Playground in `web/`; linear-memory bindings in `wasmcore/`; build, documentation, CLI and benchmark scripts in `scripts/`.

Include the version, backend and minimal reproduction in issues. Follow [SECURITY](SECURITY.md) for private reports and [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md) for participation.

## License

[Apache-2.0](LICENSE); attribution is in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
