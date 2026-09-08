name = "0717lee/pixelforge"

version = "0.15.0"

readme = "README.md"

repository = "https://github.com/0717lee/pixelforge"

license = "Apache-2.0"

keywords = [
  "image",
  "image-processing",
  "filters",
  "convolution",
  "wasm",
  "canvas",
]

preferred_target = "wasm-gc"

description = "Pure MoonBit image processing library with filters, morphology, bilateral and color-space operations, affine transforms, drawing primitives with a bitmap font, layer compositing with blend modes, separable Gaussian blur, and PNG/GIF/QOI/BMP codecs with self-implemented DEFLATE inflate and LZW. Backend-agnostic (js, wasm-gc, native) with a browser Playground."

options(
  exclude: [
    "assets/",
    "_screenshots/",
    "cmd/",
    "项目申报书*.md",
    "申报*.md",
    "*.pdf",
  ],
)

import {
  "moonbitlang/x@0.5.1",
}
