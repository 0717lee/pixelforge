/// Browser-native AVIF encoder. Decoding runs in the shared MoonBit core.

///|
/// Encodes an RGBA8 image as AVIF using the browser's native encoder.
pub fn avif_encode(image : Image) -> Array[Byte] {
  let encoded = @image.encode_avif({
    width: image.width,
    height: image.height,
    data: image_to_bytes(image),
  }) catch {
    _ => abort("avif_encode: browser AVIF encoding failed")
  }
  Bytes::to_array(encoded)
}
