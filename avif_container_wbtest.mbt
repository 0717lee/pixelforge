/// Container-level AVIF validation tests.

///|
test "avif container rejects truncated and non BMFF data" {
  assert_true(avif_container_parse([]) is None)
  let bad : Array[Byte] = [0, 0, 0, 8, b'f', b't', b'y', b'p']
  assert_true(avif_container_parse(bad) is None)
  let truncated : Array[Byte] = [
    0, 0, 0, 20, b'f', b't', b'y', b'p', 0, 0, 0, 0,
  ]
  assert_true(avif_container_parse(truncated) is None)
}

/// A declared 64-bit box size must still fit in the supplied input.

///|
test "avif container rejects oversized largesize" {
  let bad : Array[Byte] = [
    0, 0, 0, 1, b'm', b'e', b't', b'a', 0, 0, 0, 0, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF,
  ]
  assert_true(avif_container_parse(bad) is None)
}
