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
/// Two 1x1 frames sharing a global black/white palette.  The first frame is
/// transparent black with a 5cs delay; the second is opaque white with a
/// disposal method of 2 and a 7cs delay.
fn two_frame_gif() -> Array[Byte] {
  let src = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
    0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
    // GCE: transparency index 0, delay 5.
     0x21, 0xF9, 0x04, 0x01, 0x05, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00,
    // GCE: disposal 2, delay 7, opaque.
     0x21, 0xF9, 0x04, 0x08, 0x07, 0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x4C, 0x01, 0x00, 0x3B,
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
test "gif_decode_all returns independent frames and GCE metadata" {
  let frames = gif_decode_all(two_frame_gif()).unwrap()
  assert_eq(frames.length(), 2)
  assert_eq(frames[0].image.width, 1)
  assert_eq(frames[0].delay_cs, 5)
  assert_eq(frames[0].disposal, 0)
  assert_eq(frames[0].transparent_index, 0)
  assert_eq(frames[0].image.get_pixel(0, 0).3.to_int(), 0)
  assert_eq(frames[1].delay_cs, 7)
  assert_eq(frames[1].disposal, 2)
  assert_eq(frames[1].transparent_index, -1)
  assert_eq(frames[1].image.get_pixel(0, 0).3.to_int(), 255)
  assert_eq(frames[1].image.get_pixel(0, 0).0.to_int(), 255)
}

///|
test "gif_decode_all rejects malformed trailing and GCE blocks" {
  let truncated = two_frame_gif()
  // Remove the trailer: the decoder must not silently accept an incomplete file.
  ignore(truncated.pop())
  assert_true(gif_decode_all(truncated) is None)
  let bad_gce = two_frame_gif()
  bad_gce[21] = b'\x03' // GCE block size must be exactly four bytes.
  assert_true(gif_decode_all(bad_gce) is None)
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

///|
/// GIF logical-screen and image-descriptor parameters are validated before
/// color-table and LZW reads.
test "gif_decode rejects invalid dimensions, tables and LZW parameters" {
  let zero_width = four_color_gif()
  // Image descriptor starts at byte 25; width is little-endian at 30..31.
  zero_width[30] = b'\x00'
  zero_width[31] = b'\x00'
  assert_true(gif_decode(zero_width) is None)

  let zero_height = four_color_gif()
  zero_height[32] = b'\x00'
  zero_height[33] = b'\x00'
  assert_true(gif_decode(zero_height) is None)

  let no_table = four_color_gif()
  no_table[10] = b'\x00' // clear the global color-table flag
  assert_true(gif_decode(no_table) is None)

  let bad_min_code = four_color_gif()
  bad_min_code[35] = b'\x01' // GIF LZW minimum code size must be 2..8.
  assert_true(gif_decode(bad_min_code) is None)

  let truncated_block = four_color_gif()
  truncated_block[35] = b'\xFF' // sub-block claims bytes past the file end
  assert_true(gif_decode(truncated_block) is None)
}
