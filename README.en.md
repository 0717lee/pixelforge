# PixelForge

[![CI](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml/badge.svg)](https://github.com/0717lee/pixelforge/actions/workflows/ci.yml)

English | [简体中文](README.md)

> An image processing library written in pure [MoonBit](https://www.moonbitlang.com/), with a browser Playground that runs it live.
> The backend-agnostic core compiles to **JavaScript / WebAssembly (wasm-gc & linear-memory wasm) / native**.
>
> **v1.0 is out**: the public API is stable and follows semantic versioning (backward-compatible within the major version).

![PixelForge browser Playground](assets/playground-original.png)

*One UI, switchable filters and JS / WebAssembly engines — Sobel edge detection shown here:*

![Sobel edge detection](assets/playground-sobel.png)

---

## ✨ Features

- **26 filters & geometric transforms**: grayscale, invert, brightness, contrast, gaussian/box blur, sharpen, emboss, Laplacian/Sobel/Scharr/Canny edges, sepia, threshold, pixelate, median denoise, histogram equalization, posterize, gamma, vignette, saturate, hue rotate, horizontal/vertical flips — plus 90° rotation and nearest/bilinear/bicubic (Catmull-Rom) resize.
- **Morphology**: 3×3 erode / dilate / open / close.
- **Image codecs**: PNG (self-implemented full DEFLATE inflate with CRC-32/Adler-32 verification), GIF decoding (variable-width LZW, interlacing, transparency), QOI (complete spec, lossless round trip) and BMP (uncompressed 24/32-bit) — all in pure MoonBit.
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
- **Integer-first, deterministic**: filter math sticks to integers where possible (e.g. luma weights ×1000); results are reproducible and **all 172 unit tests are hand-verified** (including canonical CRC-32/Adler-32 check vectors and a hand-assembled DEFLATE bitstream).
- **Zero dependencies**: only `moonbitlang/core`, no third-party libraries.
- **Multi-backend, zero-copy interop**: on the js backend a `FixedArray[Byte]` *is* a `Uint8Array`, so canvas `Uint8ClampedArray` buffers cross over without copies; the linear-memory wasm backend exports `memory` for bulk pixel access.
- **Browser Playground**: drag & drop / paste / upload images, stackable filter pipeline, JS/WASM engine switch with benchmarks, an optional **Web Worker background thread** for large images, and PNG downloads produced by the library's **own `png_encode`**.

## 🆚 Relation to other MoonBit image libraries

The MoonBit ecosystem already hosts several image packages with overlapping directions (e.g. `megemini/millow`, `PingGuoMiaoMiao/MoonVision`, `shunge/image`). PixelForge unavoidably overlaps with them on basic filters (blur, edge detection, thresholding — the common foundation every image library shares, here all independently hand-written and test-driven), but its **positioning and core capabilities are clearly different**:

| Existing project | Positioning | Difference from PixelForge |
| --- | --- | --- |
| `megemini/millow` | Pillow-style computer vision library (corner detection, contours, HOG/LBP/moments, augmentation, SSIM, ...) | CV-focused; no codec breadth, browser interactivity or perceptual analysis |
| `PingGuoMiaoMiao/MoonVision` | Lightweight image processing + basic CV (grayscale-first, template matching) | Grayscale-focused; no full RGBA codecs, drawing/text, noise or hashing |
| `shunge/image` | Pure decoder (BMP/QOI/TGA/PNG/GIF/JPEG) | Decode only; no filters, encoding, drawing or analysis |

**Capabilities unique to PixelForge** (not offered by the projects above):

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
├── *_test.mbt             # 172 deterministic tests (blackbox + whitebox)
├── cmd/main/              # native CLI example (moon run cmd/main)
├── cmd/ppm/               # PPM output example (moon run cmd/ppm > edges.ppm)
├── cmd/showcase/          # capstone demo (drawing+text+filter+PNG round trip)
├── web/                   # browser bindings + Playground (HTML/CSS/JS)
│   ├── bindings.mbt       #   js-backend bindings (zero-copy) incl. encode_png
│   ├── worker.js          #   Web Worker running the same pipeline off-thread
│   ├── dist/web.js        #   prebuilt MoonBit→JS bundle
│   ├── dist/wasmcore.wasm #   prebuilt linear-memory wasm bundle
│   └── index.html / playground.js / style.css
├── wasmcore/              # linear-memory wasm bindings (alloc/process + memory)
└── serve.mjs              # dependency-free static server
```

## 🚀 Quick start

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) first.

```bash
moon test              # run the 172 unit tests
moon run cmd/main      # native example (builds an image, runs filters, prints checksums)
moon run cmd/ppm > edges.ppm   # emit a Sobel edge-detected PPM image
```

Start the browser Playground (prebuilt bundles ship in `web/dist/`):

```bash
node serve.mjs         # then open http://localhost:8123
```

To rebuild the web bundles from source:

```bash
moon build --release --target js     # produces _build/js/release/build/web/web.js
moon build --release --target wasm   # produces _build/wasm/release/build/wasmcore/wasmcore.wasm
# copy both artifacts into web/dist/ (web.js, wasmcore.wasm)
```

## 🧑‍💻 Library usage

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

// Compositing, text and codecs
let framed = img.composite(overlay_layer, @pixelforge.BlendMode::Multiply)
framed.draw_text(8, 8, "PIXELFORGE 0.5", 2, b'\xFF', b'\xFF', b'\xFF', b'\xFF')
let png_bytes = @pixelforge.png_encode(framed)
```

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

```bash
moon test                 # default backend (wasm-gc)
moon test --target js     # js backend
```

172 tests cover every filter, transform, drawing primitive, blend mode, the font, the analysis algorithms and all four codecs. Every expected value is derived by hand — impulse responses, flat-field invariance, known edges, histogram remapping, exact encoded byte lengths, lossless round trips, canonical CRC-32/Adler-32 check vectors and hand-assembled DEFLATE and GIF LZW bitstreams — and passes on both the wasm-gc and js backends, with GitHub Actions CI.

## 📮 Published on mooncakes.io

> The module is `0717lee/pixelforge`. Other MoonBit projects can depend on it with `moon add 0717lee/pixelforge`.

```bash
moon login             # log in to mooncakes.io
moon publish           # publish
```

## 📄 License

Apache-2.0
