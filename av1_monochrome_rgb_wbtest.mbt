///|
test "monochrome limited range matches actual libavif scalar gray vectors" {
  // Recorded by generate-av1-monochrome-reference.py using decoded ramp
  // images with yuvRange=LIMITED and avifRGBImage.avoidLibYUV=1. The native
  // samples and these outputs are retained in the fixture manifest.
  let vectors = [
    [0, 15, 16, 128, 235, 236, 255],
    [0, 60, 64, 512, 940, 944, 1023],
    [0, 240, 256, 2048, 3760, 3776, 4095],
  ]
  let expected : Array[Byte] = [
    b'\x00', b'\x00', b'\x00', b'\x82', b'\xFF', b'\xFF', b'\xFF',
  ]
  for d in 0..<3 {
    let plane = Array::make(64, 0)
    for i in 0..<7 {
      plane[i] = vectors[d][i]
    }
    let frame : Av1FramePlanes = {
      width: 7,
      height: 1,
      coded_width: 8,
      bit_depth: [8, 10, 12][d],
      full_range: false,
      matrix_coefficients: 2,
      sub_x: 1,
      sub_y: 1,
      planes: [plane],
    }
    let image = av1_frame_to_rgba(frame).unwrap()
    for i in 0..<7 {
      let gray = expected[i]
      assert_eq(image.get_pixel(i, 0), (gray, gray, gray, b'\xFF'))
    }
  }
}
