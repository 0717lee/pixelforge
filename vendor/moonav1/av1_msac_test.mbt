///|
test "av1 msac decodes an equiprobable symbol" {
  let symbol = av1_msac_decode_first(
    [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'],
    [16384, 32768, 0],
  )
  assert_eq(symbol, Some(0))
}

///|
test "av1 msac rejects an empty alphabet" {
  assert_true(av1_msac_decode_first([b'\x00', b'\x00'], [0]) is None)
}
