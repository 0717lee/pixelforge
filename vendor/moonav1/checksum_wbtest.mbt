// Extracted unchanged from PixelForge's png.mbt for AV1 reference tests.

///|
/// CRC-32 (ISO-HDLC) over `data[from..<to]`, bitwise implementation.
fn crc32(data : Array[Byte], from : Int, to : Int) -> UInt {
  let mut crc = 0xFFFFFFFFU
  for i in from..<to {
    crc = crc ^ data[i].to_uint()
    for _ in 0..<8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ 0xEDB88320U
      } else {
        crc = crc >> 1
      }
    }
  }
  crc ^ 0xFFFFFFFFU
}
