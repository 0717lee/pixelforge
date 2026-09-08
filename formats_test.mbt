///|
test "image format detection covers modern containers" {
  assert_true(detect_image_format([b'\xFF', b'\xD8', b'\xFF', b'\xE0']) is Some(Jpeg))
  assert_true(detect_image_format([b'R', b'I', b'F', b'F', b'\x00', b'\x00', b'\x00', b'\x00', b'W', b'E', b'B', b'P']) is Some(Webp))
  assert_true(detect_image_format([b'\x00', b'\x00', b'\x00', b'\x18', b'f', b't', b'y', b'p', b'a', b'v', b'i', b'f']) is Some(Avif))
  assert_true(detect_image_format([b'I', b'I', b'*', b'\x00']) is Some(Tiff))
}

///|
test "metadata reads png and gif dimensions" {
  let png : Array[Byte] = [
    b'\x89', b'P', b'N', b'G', b'\x0D', b'\x0A', b'\x1A', b'\x0A',
    b'\x00', b'\x00', b'\x00', b'\x0D', b'I', b'H', b'D', b'R',
    b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x03',
  ]
  let p = image_metadata(png).unwrap()
  assert_eq(p.format.name(), "png")
  assert_eq(p.width, 2)
  assert_eq(p.height, 3)
  let gif : Array[Byte] = [b'G', b'I', b'F', b'8', b'9', b'a', b'\x04', b'\x00', b'\x05', b'\x00']
  let g = image_metadata(gif).unwrap()
  assert_eq(g.width, 4)
  assert_eq(g.height, 5)
  assert_false(g.animated)
}
