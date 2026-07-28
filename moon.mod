// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "0717lee/pixelforge"

version = "0.5.0"

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

description = "Pure MoonBit image processing library: 26 filters (Sobel/Scharr/Canny edges, morphology, HSV/YCbCr), affine transforms, drawing primitives with a bitmap font, layer compositing with blend modes, separable Gaussian blur, and PNG/QOI/BMP codecs with a self-implemented DEFLATE inflate. Backend-agnostic (js, wasm-gc, native) with a browser Playground."
