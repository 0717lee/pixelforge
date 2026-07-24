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
