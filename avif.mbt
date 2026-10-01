///|
/// Decodes the primary AVIF image to owned RGBA8 pixels using MoonAV1 0.2.0.
/// Supports the decoder's still-image, alpha and grid paths on js, wasm-gc
/// and native. Animation playback is not exposed by this adapter.
/// Returns None for invalid, unsupported or resource-limited input.
pub fn avif_decode(data : Array[Byte]) -> Image? {
  match @moonav1.avif_decode_rgba(data) {
    Some(image) =>
      Some(Image::from_bytes(image.width, image.height, image.data))
    None => None
  }
}
