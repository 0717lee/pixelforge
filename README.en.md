# PixelForge

[![CI](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml/badge.svg)](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml)

English | [简体中文](README.md)

[Developer handoff and final acceptance goal (Chinese)](HANDOFF.md)

**AVIF/AV1 status (2026-09-24)**: the complete pure MoonBit decoding mainline is implemented. All 1546 tests pass on native, JavaScript and wasm-gc; independent pixel comparisons, native CLI, Playground main/worker paths and generated artifacts pass local verification. See the [handoff](HANDOFF.md) for scope, color conventions, reproduction commands and the CI record for the corresponding revision.

> An image processing library written in pure [MoonBit](https://www.moonbitlang.com/), with a browser Playground that runs it live.
> The backend-agnostic core compiles to **JavaScript / WebAssembly (wasm-gc & linear-memory wasm) / native**.
>
> **Stable API milestone**: GitHub keeps `v1.0.0` as the stable-release marker; the source package version is `0.18.0`, as declared in `moon.mod`. Common decode calls retain their existing forms. `Av1SequenceInfo`, `Av1FrameHeaderInfo` and reference-state records have expanded; code that constructs public records directly must supply the fields in the current [generated interface](pkg.generated.mbti). See the [changelog](CHANGELOG.md) for compatibility changes.

![PixelForge browser Playground](assets/playground-original.png)

*One UI, switchable filters and JS / WebAssembly engines — Sobel edge detection shown here:*

![Sobel edge detection](assets/playground-sobel.png)

---

## ✨ Features

- **AVIF/AV1 pixel decoding**: pure MoonBit 8/10/12-bit monochrome, 4:2:0, 4:2:2 and 4:4:4 reconstruction, with multiple tiles, intra prediction, palettes, CfL, lossless transforms and intra-block copy (`intrabc`). Quantization matrices cover levels 0–15 and all AV1 transform sizes, with per-plane selection and lossless/transform bypass rules. All eight segmentation features, inherited maps/features, temporal segment prediction, delta-Q and per-superblock delta-LF feed reconstruction and filtering. Native-depth deblocking, CDEF, horizontal super-resolution, Wiener/SGR restoration and film grain share the frame pipeline.
- **Stateful AV1 sequences**: reference pixels and entropy contexts persist across frames. Motion prediction includes subpixel/reference scaling, temporal motion vectors, OBMC, local/global warps, inter-intra and compound blends, including wedge and dual-reference global warp. Standalone frame-header/tile-group assembly, hidden frames, show-existing, frame IDs, decoder timing and grain-parameter inheritance are integrated. Raw AV1 decoding defaults to operating point 0 and presents its highest spatial layer present in each temporal unit. [Encoder fixtures](tests/fixtures/av1-mainline/README.md), [segmentation references](tests/fixtures/av1-segmentation-tools/README.md) and [OBU fixtures](tests/fixtures/av1-obu-assembly/README.md) record the actual exercised paths.
- **AVIF containers and composition**: primary images, auxiliary alpha, and 4:2:0/4:2:2/4:4:4 grids retain native samples until final color/alpha conversion. Animated color and associated alpha tracks have independent reference state and exact timestamp/duration synchronization, including differing track timescales. Item and track `nclx` metadata supplies unspecified AV1 color fields. See the [grid](tests/fixtures/avif-grid-sampling-color/README.md) and [animation-alpha](tests/fixtures/avif-animation-alpha/README.md) references.
- **AVIF alpha and Playground integration**: static-item and animation-track `prem` relationships produce straight RGBA, retaining the precision needed for high-bit-depth unpremultiplication. Playground main and worker threads decode static and animated AVIF through the MoonBit core. Transparent animation playback and PNG export are verified with browser image decoders disabled. AVIF encoding remains browser-only.
- **A broad set of filters & geometric transforms**: grayscale, invert, brightness, contrast, gaussian/box blur, sharpen, emboss, Laplacian/Sobel/Scharr/Canny edges, sepia, threshold, pixelate, median denoise, histogram equalization, posterize, gamma, vignette, saturate, hue rotate, horizontal/vertical flips — plus 90° rotation and nearest/bilinear/bicubic (Catmull-Rom) resize.
- **Morphology**: 3×3 erode / dilate / open / close.
- **Image codecs**: PNG (8-bit grayscale, grayscale+alpha, palette, RGB/RGBA and `tRNS`; self-implemented full DEFLATE inflate, adaptive row filters and fixed-Huffman encoding with CRC-32/Adler-32 verification), GIF decoding (variable-width LZW, interlacing, transparency), QOI (complete spec, lossless round trip) and BMP (uncompressed 24/32-bit) — all in pure MoonBit.
- **GIF animation frames**: `gif_decode_all()` returns each frame with its offset, delay, transparency index, and disposal metadata; `gif_decode()` remains the first-frame convenience API.
- **Affine transforms**: an `Affine` matrix type (rotate/translate/scale/shear + composition + inversion) rendered by inverse mapping with bilinear sampling; arbitrary-angle `rotate(degrees)`.
- **Drawing primitives**: Bresenham lines, rectangles, midpoint circles and fills, all bounds-clipped.
- **Separable Gaussian blur**: `gaussian(radius)` with any radius, binomial weights split into row/column passes — O(r) per pixel instead of O(r²).
- **Unsharp mask**: `unsharp_mask(radius, amount)` reuses the Gaussian to extract and re-add high-frequency detail, sharpening edges.
- **Crop & pad**: `crop(x, y, w, h)` (clamped to bounds) and `pad(l, t, r, b, color)` (colored borders); `crop∘pad` round-trips losslessly.
- **Bilateral filter**: `bilateral(radius, σs, σr)` edge-preserving smoothing — denoises flat regions while keeping strong edges sharp.
- **Image analysis**: Otsu automatic thresholding (between-class variance), Floyd–Steinberg error-diffusion dithering, 4-connected component labeling and counting, chamfer (3,4) distance transform, perceptual hashes (aHash/dHash + Hamming distance).
- **Integral image & O(1) box blur**: `integral_image()` builds a summed-area table (Int64, overflow-safe) that drives `box_blur(radius)` at O(1) per pixel for any radius.
- **Flood fill**: `flood_fill(x, y, color, tolerance)` 4-connected seed fill with per-channel tolerance.
- **Layer compositing**: `composite(top, mode)` — Porter-Duff source-over with 8 blend modes (multiply, screen, overlay, darken, lighten, difference, add), in rounded integer math.
- **Bitmap text**: built-in 5×7 font (digits, uppercase letters, basic punctuation), `draw_text` with integer scaling and clipping.
- **Color spaces**: exact round-trip RGB ↔ HSV, RGB ↔ HSL (with `adjust_lightness`) and RGB ↔ YCbCr (BT.601) conversions.
- **Histograms**: `histogram_luma()` / `histogram_rgb()` 256-bin counts; the playground has a live luma histogram panel.
- **Generic convolution engine**: `Kernel` + `Image::convolve` for custom odd-sized kernels.
- **Image statistics & tone**: `stats()` per-channel min/max/mean (Int64 accumulation), `auto_contrast()` automatic contrast stretch, `levels(black, white, gamma)` tonal remap.
- **Deterministic noise**: `add_gaussian_noise(seed, σ)` / `add_salt_pepper(seed, density)` driven by a 64-bit LCG — the same seed is byte-identical on every backend.
- **Image-quality metrics**: `mse()` / `psnr()` compare all RGBA channels; `luma_mse()` / `ssim()` use Rec.601 luma and ignore alpha.
- **Local thresholding and region statistics**: `sauvola()` / `adaptive_mean()` use summed-area tables for local windows; `regionprops()` reports component area, bounding boxes, and centroids.
- **Integer-first, deterministic**: filter math sticks to integers where possible (e.g. luma weights ×1000); results are reproducible, with tests covering normal, boundary, and malformed inputs (including canonical CRC-32/Adler-32 check vectors and a hand-assembled DEFLATE bitstream).
- **Zero third-party dependencies in the core**: the image package uses only `moonbitlang/core`; native CLI file mode separately uses the official `moonbitlang/x/fs` package.
- **Multi-backend, zero-copy interop**: on the js backend a `FixedArray[Byte]` *is* a `Uint8Array`, so canvas `Uint8ClampedArray` buffers cross over without copies; the linear-memory wasm backend exports `memory` for bulk pixel access.
- **Browser Playground**: drag & drop / paste / upload images, stackable filter pipeline, JS/WASM engine switch with benchmarks, an optional **Web Worker background thread** for large images, and PNG downloads produced by the library's **own `png_encode`**.

## 🆚 Relation to other MoonBit image libraries

The MoonBit ecosystem already hosts several image packages with overlapping directions (e.g. `megemini/millow`, `PingGuoMiaoMiao/MoonVision`, `shunge/image`). PixelForge unavoidably overlaps with them on basic filters (blur, edge detection, thresholding — the common foundation every image library shares, here all independently hand-written and test-driven), but its **positioning and core capabilities are clearly different**:

| Existing project | Positioning | Difference from PixelForge |
| --- | --- | --- |
| `megemini/millow` | Broader computer-vision algorithms (augmentation, contours/region features, HOG/LBP, SSIM, ...) | CV-focused; PixelForge emphasizes zero dependencies, multi-backend codecs, and browser interaction |
| `PingGuoMiaoMiao/MoonVision` | Lightweight image processing + basic CV (grayscale-first, template matching) | Grayscale-focused; no full RGBA codecs, drawing/text, noise or hashing |
| `shunge/image` | Pure decoder (BMP/QOI/TGA/PNG/GIF/JPEG) | Decode only; no filters, encoding, drawing or analysis |

**Capabilities PixelForge focuses on**:

- **Codec breadth**: PNG (self-implemented full DEFLATE inflate with CRC-32/Adler-32 verification), QOI, BMP **encode + decode** and GIF decoding, all in pure MoonBit
- **Browser Playground**: live JS/WASM engine comparison, Web Worker background thread, real-time luma histogram panel, downloads via the library's own `png_encode`
- **Bitmap text**: built-in 5×7 font `draw_text` for typesetting directly on images
- **Perceptual hashing**: aHash / dHash + Hamming distance for deduplication and similarity search
- **Deterministic noise**: 64-bit LCG-driven gaussian / salt-and-pepper noise, byte-identical across backends for a given seed; pairs with median/bilateral filters into a denoise demo loop
- **Statistics & tone**: per-channel min/max/mean, auto_contrast, levels
- **Engineering transparency**: full evolution across 13 releases, bilingual docs, CI end-to-end smoke tests

If you found this library on `mooncakes.io`, you can use it directly with `moon add 0717lee/pixelforge`; we also hope the codec and Playground implementations serve as useful ecosystem references.

## 📦 Project layout

```
pixelforge/
├── image.mbt              # Image type, pixel access, clamp_byte
├── filters_basic.mbt      # map_rgb engine + grayscale/invert/brightness/contrast
├── convolution.mbt        # Kernel + convolve + blur/sharpen/emboss/edges/Sobel/Scharr
├── filters_advanced.mbt   # sepia/threshold/pixelate/median/histogram/posterize
├── filters_effects.mbt    # gamma/vignette
├── colorspace.mbt         # RGB↔HSV, RGB↔YCbCr, saturate/hue_rotate
├── morphology.mbt         # 3×3 erode/dilate/open/close
├── canny.mbt              # Canny edges (NMS + hysteresis)
├── affine.mbt             # affine transforms (inverse-mapped sampling)
├── drawing.mbt            # drawing primitives (Bresenham/rect/circle/fill)
├── gaussian.mbt           # separable Gaussian blur (any radius)
├── unsharp.mbt            # unsharp mask (reuses gaussian)
├── croppad.mbt            # crop / colored-border pad
├── integral.mbt           # integral image (SAT) + O(1) box blur
├── floodfill.mbt          # flood fill (4-connected seed fill)
├── distance.mbt           # chamfer (3,4) distance transform
├── stats.mbt              # statistics / auto-contrast / levels
├── bicubic.mbt            # bicubic resize (Catmull-Rom)
├── phash.mbt              # perceptual hashes (aHash/dHash + Hamming)
├── noise.mbt              # deterministic noise (gaussian / salt-pepper)
├── hsl.mbt                # HSL color space + lightness adjust
├── histogram.mbt          # histogram API (luma / RGB)
├── bilateral.mbt          # bilateral filter (edge-preserving)
├── otsu.mbt               # Otsu automatic threshold
├── dither.mbt             # Floyd–Steinberg error diffusion
├── components.mbt         # 4-connected component labeling
├── blend.mbt              # layer compositing (source-over + 8 blend modes)
├── text.mbt               # 5×7 bitmap font draw_char/draw_text
├── png.mbt                # PNG codec (full DEFLATE inflate + checksums)
├── gif.mbt                # GIF decoder (variable-width LZW, interlacing)
├── qoi.mbt                # QOI codec (complete spec)
├── bmp.mbt                # BMP codec (uncompressed 24/32-bit)
├── transform.mbt          # flips, 90° rotation
├── resize.mbt             # nearest/bilinear resize
├── dispatch.mbt           # Image::apply_filter_id shared dispatch table
├── pipeline.mbt           # typed, reusable Filter / Pipeline API
├── metrics.mbt            # MSE / PSNR / luma MSE / SSIM
├── adaptive_threshold.mbt # Sauvola / local-mean thresholding
├── regionprops.mbt        # component area, bounds, and centroids
├── *_test.mbt             # deterministic tests (blackbox + whitebox)
├── cmd/main/              # native CLI example (moon run cmd/main)
├── cmd/ppm/               # PPM output example (moon run cmd/ppm > edges.ppm)
├── cmd/showcase/          # capstone demo (drawing+text+filter+PNG round trip)
├── cmd/cli/               # native info/convert CLI plus hex mode
├── web/                   # browser bindings + Playground (HTML/CSS/JS)
│   ├── bindings.mbt       #   js-backend bindings (zero-copy) incl. encode_png
│   ├── worker.js          #   Web Worker running the same pipeline off-thread
│   ├── dist/web.js        #   prebuilt MoonBit→JS bundle
│   ├── dist/wasmcore.wasm #   prebuilt linear-memory wasm bundle
│   └── index.html / playground.js / style.css
├── wasmcore/              # linear-memory wasm bindings (alloc/process + memory)
├── scripts/build-web.mjs  # build and verify web/dist artifacts
└── serve.mjs              # dependency-free static server
```

## 🚀 Quick start

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) first.

```bash
moon test              # run the complete unit-test suite
moon run cmd/main      # native example (builds an image, runs filters, prints checksums)
moon run cmd/ppm > edges.ppm   # emit a Sobel edge-detected PPM image
moon run --target native cmd/cli -- --help # show the file codec CLI help
```

Start the browser Playground (prebuilt bundles ship in `web/dist/`):

```bash
node serve.mjs         # then open http://localhost:8123
```

The Playground scales uploaded images to a 1024-pixel longest edge for preview so repeated renders do not exhaust browser memory. It shows the actual preview dimensions, and downloads use that preview size. Use the library API directly when you need to preserve the original resolution.

To rebuild the web bundles from source:

```bash
node scripts/build-web.mjs           # build and synchronize web/dist/
node scripts/build-web.mjs --check   # only verify committed artifacts are current
```

### Errors and boundaries

- `png_decode`, `gif_decode`, `qoi_decode`, and `bmp_decode` return `None` for malformed or unsupported input.
- `Image::new`, `Image::from_bytes`, and compositing operations that require matching dimensions reject invalid sizes or buffers; coordinate APIs require in-bounds coordinates.
- Codecs and constructors enforce image-size limits. Hosts handling untrusted images should still apply stricter file-size and pixel-count limits.
- The Playground demonstrates the common filters and backend switching; the complete codec, geometry, drawing, analysis, and compositing APIs are available through the MoonBit library.

## 🧑‍💻 Library usage

### AV1 and AVIF entry points

Use `av1_decode` for an AV1 image, `avif_decode` for the AVIF primary image, and `avif_decode_rgba` to include auxiliary alpha. `avif_decode_grid_auto` selects the primary grid and its ordered `dimg` cells. For sequences, create an `av1_video_decoder` and pass temporal units to `av1_video_decode_temporal_unit`; it returns one selected presentation per unit, including show-existing, or an empty array for hidden-only input. `av1_video_decode_frame` returns the first presentation while processing all reference updates. `avif_decode_animation` returns all composed frames with their timestamps, durations and timescale; `avif_decode_animation_frame` selects the image at a track timestamp.

AVIF honors essential `a1op`/`lsel` properties for operating-point and spatial-layer selection, and validates `ispe` against the selected presentation dimensions. Primary images, alpha items and grid cells share this selection path; sequence maximum dimensions may exceed the selected image dimensions.

The composition contract is straight RGBA: a static item or animation track marked by `prem` is unpremultiplied before exposing the final image. Independent libavif references cover the separate RGB8 and native-precision rounding paths. Playground uses these bindings with no host AVIF decode fallback; AVIF encoding remains a separate browser-only capability.

Color conversion supports AV1 CICP matrix values 0–14 except reserved value 3, with the required primaries/transfer metadata and field-wise `nclx` completion. RGBA8 preserves source primaries and the source transfer function, uses nearest-neighbor chroma replication, and clips/rounds at final conversion. XYZ primaries (CP 10) explicitly convert linear XYZ to BT.709 D65 RGB and then sRGB. No HDR tone mapping or display-gamut adaptation is applied. The [color reference contract](tests/fixtures/av1-color/README.md) documents exact output comparisons.

### Image processing

```moonbit
// Build an image from an RGBA byte buffer (w*h*4)
let img = @pixelforge.Image::from_bytes(width, height, rgba_bytes)

// Chain filters (each returns a new image; the source is never mutated)
let stylized = img.grayscale().sobel()
let soft = img.gaussian(4).brightness(20)

// Custom convolution kernel
let kernel = @pixelforge.Kernel::new(3, [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0], 1.0, 0.0)
let sharp = img.convolve(kernel)

// Dispatch by numeric id (shared by all host bindings / CLI)
let out = img.apply_filter_id(8, 0.0) // 8 = Sobel

// Build a typed, reusable pipeline (operations run in append order)
let pipeline = @pixelforge.Pipeline::new()
  .append(@pixelforge.Filter::Grayscale)
  .append(@pixelforge.Filter::Contrast(1.25))
  .append(@pixelforge.Filter::Sobel)
let out2 = img.apply_pipeline(pipeline)

// Quality metrics: RGBA error and Rec.601 luma similarity.
let error = img.mse(out2)
let score = img.psnr(out2)
let similarity = img.ssim(out2)

// Compositing, text and codecs
let framed = img.composite(overlay_layer, @pixelforge.BlendMode::Multiply)
framed.draw_text(8, 8, "PIXELFORGE 0.5", 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
let png_bytes = @pixelforge.png_encode(framed)
```

`mse`/`psnr` compare all RGBA channels; `luma_mse`/`ssim` use Rec.601 luma and ignore alpha. `ssim` uses one population-statistics window over the complete image (no sliding-window padding); equal-sized empty images return 1, while mismatched dimensions are rejected.

## 🎛️ Filter table

| id | filter | method | `amount` |
| --- | --- | --- | --- |
| 0 | grayscale | `grayscale()` | — |
| 1 | invert | `invert()` | — |
| 2 | brightness | `brightness(delta)` | −255..255 |
| 3 | contrast | `contrast(factor)` | 0.0..3.0 |
| 4 | gaussian blur | `blur()` | — |
| 5 | sharpen | `sharpen()` | — |
| 6 | emboss | `emboss()` | — |
| 7 | Laplacian edges | `edges()` | — |
| 8 | Sobel edges | `sobel()` | — |
| 9 | sepia | `sepia()` | — |
| 10 | threshold | `threshold(level)` | level (default 128) |
| 11 | pixelate | `pixelate(block)` | block size (default 8) |
| 12 | median denoise | `median()` | — |
| 13 | histogram equalize | `histogram_equalize()` | — |
| 14 | flip horizontal | `flip_horizontal()` | — |
| 15 | flip vertical | `flip_vertical()` | — |
| 16 | posterize | `posterize(levels)` | levels (default 4) |
| 17 | gamma | `gamma(value)` | gamma (default 2.2) |
| 18 | vignette | `vignette(strength)` | strength 0..1 (default 0.5) |
| 19 | Scharr edges | `scharr()` | — |
| 20 | Canny edges | `canny(low, high)` | high threshold (default 100, low = high/2) |
| 21 | Otsu auto threshold | `otsu()` | — |
| 22 | Floyd–Steinberg dither (mono) | `dither_mono()` | — |

> Size-changing transforms are library APIs rather than dispatch ids: `rotate90()`, `resize_nearest(w, h)`, `resize_bilinear(w, h)`, `resize_bicubic(w, h)`. Likewise for multi-parameter APIs: `average_hash()`/`difference_hash()`/`hamming_distance`, `add_gaussian_noise`/`add_salt_pepper`, `histogram_luma()`/`histogram_rgb()`, `rgb_to_hsl`/`hsl_to_rgb`/`adjust_lightness`, `box_blur(radius)`, `flood_fill(x, y, color, tol)`, `distance_transform(t)`, `gaussian(radius)`, `unsharp_mask(radius, amount)`, `crop(x, y, w, h)`, `pad(l, t, r, b, color)`, `bilateral(radius, σs, σr)`, `dither_grayscale(levels)`/`dither_mono()`, `otsu_threshold()`, `label_components(t)`/`count_components(t)`, `composite(top, mode)`, `draw_text(...)`, `rotate(deg)`, `translate(dx, dy)`, `affine(t)`, the drawing primitives, `saturate(factor)`, `hue_rotate(deg)`, the morphology operators, `png_encode`/`png_decode`, `gif_decode`, `qoi_encode`/`qoi_decode`, `bmp_encode`/`bmp_decode` and the color-space functions.

## 🏗️ Architecture & backends

The core library is fully backend-agnostic. Two host binding packages demonstrate both ways in and out of MoonBit:

- **`web/` (js backend)**: MoonBit's `FixedArray[Byte]` compiles to a JS `Uint8Array`, so a canvas `ImageData.data` buffer (`Uint8ClampedArray`) passes into `apply_filter` with **zero copies**.
- **`wasmcore/` (linear-memory wasm)**: the link step exports linear `memory`; the pointer returned by `alloc(len)` points **directly at the data** (measured zero header offset), so the host writes pixels through a `Uint8Array` view and calls `process`.

> **An honest performance note**: benchmarking the same filter pipeline in the browser, MoonBit's **js backend is about 4–5× faster than the linear-memory wasm path**. V8 JITs the JS output aggressively, while the wasm path pays for copying pixels in and out of linear memory. "WASM is always faster" is a myth — the Playground keeps the engine toggle and comparison button so you can reproduce this yourself.

## ✅ Tests

Run from the repository root with the MoonBit toolchain and Node.js installed; native tests also require a platform C compiler:

```sh
moon check
moon test --target native
moon test --target js
moon test --target wasm-gc
node scripts/build-web.mjs --check
node scripts/check-browser-codecs.mjs
node verify-wasm.mjs
moon run --target native cmd/cli -- --help
```

Tests cover filters, geometry, drawing, analysis and codecs, including malformed inputs and dimension boundaries. AV1/AVIF fixtures retain independent dav1d/libavif native pixels; native YUV and alpha comparisons require exact equality. The 14 color fixtures also strictly check RGBA against their declared conversion convention. Four PQ channels cross an 8-bit rounding boundary in the float32 zimg reference: those channels must equal the independent 80-digit H.273 result recorded in the [manifest](tests/fixtures/av1-color/manifest.json), and every other channel must match its reference exactly.

Ordinary MoonBit tests use committed fixture data and need no external codec tools. Reference generators provide separate portable checks, for example:

```sh
python scripts/generate-avif-grid-sampling-color-reference.py --check
python scripts/generate-avif-animation-alpha-reference.py --check
python scripts/generate-av1-mainline-reference.py --check --trace-dav1d /path/to/debug/dav1d
python scripts/generate-av1-color-reference.py --check --libavif /path/to/avif.dll
```

The first two commands verify recorded artifacts without a codec library. The latter two regenerate references in temporary storage; their fixture READMEs list the pinned tools, tracer build and path overrides. None of these `--check` commands writes generated repository files. Full acceptance also requires the combined-tool pixel checks, CLI/Web integration and CI evidence described in the [handoff](HANDOFF.md); the commands above are the verification procedure, not a claim that this implementation round has passed them.

## 📮 Published on mooncakes.io

> The module is `0717lee/pixelforge`. Other MoonBit projects can depend on it with `moon add 0717lee/pixelforge`.

```bash
moon login             # log in to mooncakes.io
moon publish           # publish
```

## 📄 License

Apache-2.0
