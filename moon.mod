name = "0717lee/pixelforge"

version = "0.18.0"

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

description = "Pure MoonBit image processing library with filters, morphology, color-space operations, affine transforms, drawing, compositing, PNG/GIF/QOI/BMP codecs, TIFF and lossless WebP decoding, and JPEG/WebP encoding adapters. Backend-agnostic (js, wasm-gc, native) with a browser Playground."

import {
  "moonbitlang/x@0.5.1",
  "mizchi/image@0.4.3",
}

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
