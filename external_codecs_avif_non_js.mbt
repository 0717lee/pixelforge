/// AVIF is intentionally a JS-only adapter because it uses browser codecs.

/// AVIF encoding is unavailable on native and wasm-gc targets.
pub fn avif_encode(_image : Image) -> Array[Byte] {
  abort("avif_encode: AVIF encoding requires the JS target")
}
