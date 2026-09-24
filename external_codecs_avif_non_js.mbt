/// AVIF encoding requires browser codecs; the core does not decode AVIF pixels.

///|
/// AVIF encoding is unavailable on native and wasm-gc targets.
pub fn avif_encode(_image : Image) -> Array[Byte] {
  abort("avif_encode: AVIF encoding requires the JS target")
}
