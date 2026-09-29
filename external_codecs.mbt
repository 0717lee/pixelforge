///|
/// Adapters to the ecosystem image codecs in `mizchi/image`.
///
/// PixelForge keeps its own `Image` type and codec APIs stable; these helpers
/// bridge RGBA bytes to the external package for formats that are too large to
/// maintain safely in this repository. JPEG decoding/encoding works on all
/// supported targets. WebP encoding is lossless and available on all targets.
/// AVIF encoding requires a JS host with Canvas AVIF encoding or local ffmpeg
/// in Node.js, and accepts opaque pixels only. Unsupported targets or encoding
/// failures abort. PixelForge's own WebP Lossless decoder is separate.
fn image_to_bytes(image : Image) -> Bytes {
  let bytes : Array[Byte] = []
  for byte in image.data {
    bytes.push(byte)
  }
  Bytes::from_array(bytes)
}

///|
fn external_to_image(data : @image.ImageData) -> Image {
  Image::from_bytes(data.width, data.height, data.data.to_fixedarray())
}

///|
/// Decodes a baseline JPEG into RGBA8 pixels.
pub fn jpeg_decode(data : Array[Byte]) -> Image? {
  Some(external_to_image(@image.decode_jpeg(Bytes::from_array(data)))) catch {
    _ => None
  }
}

///|
/// Encodes an RGBA8 image as JPEG. `quality` is clamped by the external codec.
pub fn jpeg_encode(image : Image, quality : Int) -> Array[Byte] {
  let encoded = @image.encode_jpeg(
    { width: image.width, height: image.height, data: image_to_bytes(image), },
    quality~,
  ) catch {
    _ => abort("jpeg_encode: external codec rejected the image")
  }
  Bytes::to_array(encoded)
}

///|
/// Encodes an RGBA8 image as lossless WebP.
pub fn webp_encode(image : Image) -> Array[Byte] {
  let encoded = @image.encode_webp({
    width: image.width,
    height: image.height,
    data: image_to_bytes(image),
  }) catch {
    _ => abort("webp_encode: external codec rejected the image")
  }
  Bytes::to_array(encoded)
}
