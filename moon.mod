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

name = "username/pixelforge"

version = "0.1.0"

readme = "README.md"

repository = ""

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

description = "Pure MoonBit image processing library: grayscale, invert, brightness/contrast, gaussian/box blur, sharpen, emboss, and Sobel/Laplacian edge detection. Backend-agnostic (js, wasm-gc, native) with a browser Playground."
