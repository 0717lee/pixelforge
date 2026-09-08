///|
/// Genuine-WebAssembly binding, compiled with the linear-memory `wasm` backend.
///
/// `alloc` returns a pixel buffer whose i32 address points straight at the data
/// inside the module's exported linear `memory` (verified: zero header offset),
/// so the JS host creates a `Uint8Array` view and bulk-copies canvas pixels in
/// with no per-element FFI. `process` runs a filter and returns the address of
/// a fresh result buffer, while `process_in_place` copies each result back into
/// the caller-owned allocation for pointer-stable multi-operation pipelines.
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

///|
/// Applies one filter and copies the result back into `buf`.
///
/// The returned array is the exact input array, allowing a host to allocate
/// one linear-memory buffer for a whole pipeline. Filter implementations may
/// still allocate temporary MoonBit arrays internally; this API guarantees
/// pointer stability for the caller's buffer, not zero internal allocation.
pub fn process_in_place(
  buf : FixedArray[Byte],
  width : Int,
  height : Int,
  filter_id : Int,
  amount : Double,
) -> FixedArray[Byte] {
  // Validate dimensions and buffer ownership before taking the fast paths.
  let image = @pixelforge.Image::from_bytes(width, height, buf)
  // Unknown dispatch ids are specified as an identity operation. Returning
  // the validated input directly avoids a full-image allocation and copy.
  if filter_id < 0 || filter_id > 22 ||
    (filter_id == 2 && amount == 0.0) ||
    (filter_id == 3 && amount == 1.0) {
    return image.data
  }
  let result = image.apply_filter_id(filter_id, amount).data
  if result.length() != buf.length() {
    abort("process_in_place: filter changed the image buffer length")
  }
  for i in 0..<buf.length() {
    buf[i] = result[i]
  }
  buf
}
