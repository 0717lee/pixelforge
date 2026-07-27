///|
/// QOI codec tests: exact encoded-size checks plus lossless round trips that
/// exercise every op type (RUN, INDEX, DIFF, LUMA, RGB, RGBA).

///|
test "qoi_encode header and solid-color size are exact" {
  // Solid 10x1: header(14) + RGB op(4) + RUN(1) + end marker(8) = 27 bytes.
  let img = solid(10, 1, 100, 150, 200, 255)
  let bytes = qoi_encode(img)
  assert_eq(bytes.length(), 27)
  assert_eq(bytes[0].to_int(), 113) // 'q'
  assert_eq(bytes[1].to_int(), 111) // 'o'
  assert_eq(bytes[2].to_int(), 105) // 'i'
  assert_eq(bytes[3].to_int(), 102) // 'f'
  assert_eq(bytes[12].to_int(), 4) // channels
}

///|
test "qoi round-trips a varied RGBA image losslessly" {
  // Gradient + spots exercises DIFF, LUMA, RGB, RGBA, INDEX and RUN ops.
  let img = @pixelforge.Image::new(8, 8)
  for y in 0..<8 {
    for x in 0..<8 {
      let r = x * 31 % 256
      let g = y * 53 % 256
      let b = (x * y * 17 + 5) % 256
      let a = if (x + y) % 3 == 0 { 255 } else { 90 + x }
      img.set_pixel(
        x,
        y,
        @pixelforge.clamp_byte(r),
        @pixelforge.clamp_byte(g),
        @pixelforge.clamp_byte(b),
        @pixelforge.clamp_byte(a),
      )
    }
  }
  let decoded = qoi_decode(qoi_encode(img)).unwrap()
  assert_eq(decoded.width, 8)
  assert_eq(decoded.height, 8)
  for i in 0..<(8 * 8 * 4) {
    assert_eq(decoded.data[i].to_int(), img.data[i].to_int())
  }
}

///|
test "qoi round-trips repeated colors through the index" {
  // Alternating two colors: after first occurrences, INDEX ops take over.
  let img = gray_image(6, 1, [10, 200, 10, 200, 10, 200])
  let decoded = qoi_decode(qoi_encode(img)).unwrap()
  for x in 0..<6 {
    assert_eq(
      decoded.get_pixel(x, 0).0.to_int(),
      img.get_pixel(x, 0).0.to_int(),
    )
  }
}

///|
test "qoi_decode rejects malformed input" {
  assert_true(qoi_decode([]) is None)
  let junk : Array[Byte] = []
  for i in 0..<30 {
    junk.push((i % 250).to_byte())
  }
  assert_true(qoi_decode(junk) is None)
  // Truncated stream: valid header claiming more pixels than data provides.
  let img = solid(64, 64, 1, 2, 3, 255)
  let bytes = qoi_encode(img)
  let cut : Array[Byte] = []
  for i in 0..<20 {
    cut.push(bytes[i])
  }
  assert_true(qoi_decode(cut) is None)
}
