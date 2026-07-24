///|
/// Genuine-WebAssembly binding, compiled with the linear-memory `wasm` backend.
///
/// `alloc` returns a pixel buffer whose i32 address points straight at the data
/// inside the module's exported linear `memory` (verified: zero header offset),
/// so the JS host creates a `Uint8Array` view and bulk-copies canvas pixels in
/// with no per-element FFI. `process` runs a filter and returns the address of
/// a fresh result buffer, which the host must read out before its next call.
pub fn alloc(len : Int) -> FixedArray[Byte] {
  FixedArray::make(len, b'\x00')
}

///|
/// Applies filter `filter_id` (see `@pixelforge.Image::apply_filter_id`) to the
/// `width` x `height` RGBA buffer at `buf` and returns the result buffer.
pub fn process(
  buf : FixedArray[Byte],
  width : Int,
  height : Int,
  filter_id : Int,
  amount : Double,
) -> FixedArray[Byte] {
  @pixelforge.Image::from_bytes(width, height, buf).apply_filter_id(
    filter_id, amount,
  ).data
}
