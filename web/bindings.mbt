///|
/// Browser-facing binding for the MoonBit **js** backend. A `FixedArray[Byte]`
/// compiles to a JS `Uint8Array`, so a canvas `ImageData.data` buffer crosses
/// into MoonBit with zero copies. Filters are selected by integer id — see
/// `@pixelforge.Image::apply_filter_id` for the id table.
pub fn apply_filter(
  data : FixedArray[Byte],
  width : Int,
  height : Int,
  filter_id : Int,
  amount : Double,
) -> FixedArray[Byte] {
  @pixelforge.Image::from_bytes(width, height, data).apply_filter_id(
    filter_id, amount,
  ).data
}

///|
/// Encodes an RGBA buffer as a PNG file using the library's own pure-MoonBit
/// encoder (`@pixelforge.png_encode`), so the playground's download button
/// exercises the codec instead of `canvas.toBlob`. Returns the file bytes as
/// a `Uint8Array`.
pub fn encode_png(
  data : FixedArray[Byte],
  width : Int,
  height : Int,
) -> FixedArray[Byte] {
  let bytes = @pixelforge.png_encode(
    @pixelforge.Image::from_bytes(width, height, data),
  )
  let out = FixedArray::make(bytes.length(), b'\x00')
  for i in 0..<bytes.length() {
    out[i] = bytes[i]
  }
  out
}
