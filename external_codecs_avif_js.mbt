/// JS-host AVIF encoder. The core does not provide AVIF pixel decoding.

///|
/// Encodes an opaque RGBA8 image through `mizchi/image`'s JS adapter.
/// Requires Canvas AVIF encoding in browsers or local ffmpeg in Node.js.
/// Unsupported alpha or encoding failures abort.
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
