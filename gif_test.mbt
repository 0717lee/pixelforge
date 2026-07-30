///|
/// GIF decoder tests: the famous 1x1 transparent-pixel GIF constant, a
/// hand-assembled 2x2 four-color file (LZW bitstream derived by hand) and
/// malformed-input rejection.

///|
/// The widely-published smallest transparent GIF (43 bytes).
fn tiny_transparent_gif() -> Array[Byte] {
  let src = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
     0x01, 0x00, 0x01, 0x00, // 1 x 1
     0x80, 0x00, 0x00, // GCT: 2 colors, bg 0
     0x00, 0x00, 0x00, // color 0: black
     0xFF, 0xFF, 0xFF, // color 1: white
     0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, // GCE: transparent idx 0
     0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // descriptor
     0x02, 0x02, 0x44, 0x01, 0x00, // LZW min 2, data
     0x3B, // trailer
  ]
  let out : Array[Byte] = []
  for v in src {
    out.push(v.to_byte())
  }
  out
}

///|
/// Hand-assembled 2x2 GIF with a 4-color table (red/green/blue/white) and
/// pixel indices 0,1,2,3. LZW min code size 2; codes 4(clear),0,1,2,3,5(end)
/// pack LSB-first into bytes 44 34 05.
fn four_color_gif() -> Array[Byte] {
  let src = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
     0x02, 0x00, 0x02, 0x00, // 2 x 2
     0x91, 0x00, 0x00, // GCT: 4 colors
     0xFF, 0x00, 0x00, // 0: red
     0x00, 0xFF, 0x00, // 1: green
     0x00, 0x00, 0xFF, // 2: blue
     0xFF, 0xFF, 0xFF, // 3: white
     0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, // descriptor
     0x02, 0x03, 0x44, 0x34, 0x05, 0x00, // LZW min 2, 3-byte block
     0x3B,
  ]
  let out : Array[Byte] = []
  for v in src {
    out.push(v.to_byte())
  }
  out
}

///|
test "gif_decode reads the canonical 1x1 transparent GIF" {
  let img = gif_decode(tiny_transparent_gif()).unwrap()
  assert_eq(img.width, 1)
  assert_eq(img.height, 1)
  let (r, g, b, a) = img.get_pixel(0, 0)
  assert_eq(r.to_int(), 0)
  assert_eq(g.to_int(), 0)
  assert_eq(b.to_int(), 0)
  assert_eq(a.to_int(), 0) // index 0 is the transparent index
}

///|
test "gif_decode reads a hand-assembled 2x2 four-color image" {
  let img = gif_decode(four_color_gif()).unwrap()
  assert_eq(img.width, 2)
  assert_eq(img.height, 2)
  let (r0, g0, b0, a0) = img.get_pixel(0, 0)
  assert_eq(r0.to_int(), 255) // red
  assert_eq(g0.to_int(), 0)
  assert_eq(b0.to_int(), 0)
  assert_eq(a0.to_int(), 255) // no transparency in this file
  assert_eq(img.get_pixel(1, 0).1.to_int(), 255) // green
  assert_eq(img.get_pixel(0, 1).2.to_int(), 255) // blue
  let (r3, g3, b3, _) = img.get_pixel(1, 1)
  assert_eq(r3.to_int(), 255) // white
  assert_eq(g3.to_int(), 255)
  assert_eq(b3.to_int(), 255)
}

///|
test "gif_decode rejects malformed input" {
  assert_true(gif_decode([]) is None)
  // Wrong signature.
  let junk : Array[Byte] = []
  for i in 0..<50 {
    junk.push((i % 250).to_byte())
  }
  assert_true(gif_decode(junk) is None)
  // Truncated: valid header, cut inside the LZW data.
  let good = tiny_transparent_gif()
  let cut : Array[Byte] = []
  for i in 0..<30 {
    cut.push(good[i])
  }
  assert_true(gif_decode(cut) is None)
  // Corrupted LZW: an out-of-range code must be refused.
  let bad = four_color_gif()
  bad[35] = b'\xFF' // clobber the packed code bytes
  bad[36] = b'\xFF'
  bad[37] = b'\xFF'
  assert_true(gif_decode(bad) is None)
}
