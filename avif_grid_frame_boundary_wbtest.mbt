///|
/// Native grid bounds are tested with independently valid original streams.
fn avif_grid_frame_single_descriptor(
  width : Int,
  height : Int,
  size : Int,
) -> AvifGridDescriptor {
  {
    item_id: 1,
    rows: 1,
    columns: 1,
    output_width: width,
    output_height: height,
    tiles: [
      {
        item_id: 2,
        extents: [{ offset: 0, length: size, construction_method: 0, }],
      },
    ],
  }
}

///|
/// Original stream SHA256: 710525a3683a69222e02350f6f9b2784dbb470d2af7886fd1d9155c4aeb579b7
test "native grid rejects cells below the MIAF minimum" {
  let sample : Array[Byte] = [
    b'\x12', b'\x00', b'\x0A', b'\x05', b'\x18', b'\x0C', b'\xFF', b'\xC0', b'\x54',
    b'\x32', b'\x21', b'\x17', b'\x80', b'\x00', b'\x01', b'\x00', b'\xCF', b'\xA0',
    b'\xED', b'\x67', b'\x02', b'\x70', b'\xB5', b'\xCD', b'\xA4', b'\xA3', b'\x42',
    b'\x9F', b'\x43', b'\xE5', b'\x9C', b'\x4C', b'\x67', b'\x6D', b'\x07', b'\x73',
    b'\x14', b'\x34', b'\x20', b'\x35', b'\x6B', b'\xCF', b'\xDF', b'\xEC',
  ]
  let frame = av1_decode_frame_planes(sample, allow_monochrome=true).unwrap()
  assert_eq((frame.width, frame.height), (16, 16))
  let descriptor = avif_grid_frame_single_descriptor(16, 16, sample.length())
  assert_true(avif_decode_grid_frame(sample, descriptor) is None)
}

///|
test "native grid accepts even 420 cropping and rejects odd axes" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFC', b'\x20', b'\x08', b'\x32',
    b'\xB5', b'\x03', b'\x17', b'\x80', b'\x00', b'\x00', b'\x48', b'\x39', b'\x00',
    b'\xD8', b'\x2D', b'\x3B', b'\xDB', b'\xCA', b'\xB9', b'\xDE', b'\x0E', b'\xB1',
    b'\xA9', b'\x29', b'\xAB', b'\x70', b'\xFC', b'\x38', b'\xC9', b'\x74', b'\x2E',
    b'\x24', b'\xD0', b'\x32', b'\x68', b'\xE6', b'\x49', b'\x5C', b'\xEF', b'\x4C',
    b'\x3D', b'\xD4', b'\xFF', b'\xBA', b'\x37', b'\x8F', b'\x15', b'\x72', b'\xE1',
    b'\x1A', b'\xA8', b'\x15', b'\x51', b'\x0A', b'\xCF', b'\xC5', b'\x17', b'\x49',
    b'\x2A', b'\xB3', b'\xAD', b'\x32', b'\x87', b'\x7D', b'\x96', b'\xE8', b'\x81',
    b'\x2A', b'\x9F', b'\x1D', b'\x5D', b'\xD5', b'\x6C', b'\x54', b'\x6E', b'\x91',
    b'\x61', b'\x3B', b'\x48', b'\x6D', b'\x18', b'\x1A', b'\xCE', b'\xF5', b'\x0E',
    b'\x43', b'\x70', b'\x26', b'\xD6', b'\x60', b'\x1C', b'\x2D', b'\x77', b'\x1D',
    b'\xDC', b'\xD4', b'\x57', b'\xC5', b'\x18', b'\x6B', b'\xFD', b'\x67', b'\xBF',
    b'\x98', b'\xD6', b'\xFC', b'\x2D', b'\xAE', b'\x7D', b'\x57', b'\xCB', b'\x57',
    b'\xEA', b'\x62', b'\x6B', b'\x95', b'\x9D', b'\xF7', b'\x92', b'\x82', b'\xCA',
    b'\x52', b'\xF0', b'\x0A', b'\x06', b'\x87', b'\x4F', b'\x45', b'\xB5', b'\xE7',
    b'\x3F', b'\xFB', b'\xBD', b'\x3A', b'\x21', b'\x8B', b'\xDA', b'\xB0', b'\xFB',
    b'\xF3', b'\x5F', b'\x77', b'\xFC', b'\x33', b'\xE0', b'\xCA', b'\x59', b'\x82',
    b'\xF0', b'\x1E', b'\x71', b'\xA8', b'\x18', b'\xCE', b'\x0F', b'\x5D', b'\x4C',
    b'\xBD', b'\x46', b'\xD7', b'\x3A', b'\xA3', b'\x67', b'\xF1', b'\x49', b'\x6C',
    b'\x68', b'\xD0', b'\x59', b'\x93', b'\xBF', b'\x8C', b'\x1C', b'\xCF', b'\x12',
    b'\xF3', b'\x82', b'\x6F', b'\x83', b'\x95', b'\x52', b'\x16', b'\x26', b'\x90',
    b'\xE6', b'\x12', b'\xA7', b'\xAD', b'\x51', b'\xF5', b'\x68', b'\x9D', b'\xF7',
    b'\x04', b'\x13', b'\xE2', b'\x08', b'\x89', b'\xD4', b'\xB4', b'\x8B', b'\x75',
    b'\x8F', b'\x0F', b'\xBF', b'\xFB', b'\x28', b'\xEE', b'\x65', b'\xB8', b'\x31',
    b'\xAB', b'\xF9', b'\x06', b'\x5C', b'\x58', b'\xEA', b'\x35', b'\x05', b'\x11',
    b'\x02', b'\xCA', b'\x13', b'\x29', b'\x05', b'\x52', b'\x02', b'\xF1', b'\xC5',
    b'\x38', b'\x71', b'\xF5', b'\xB8', b'\xC3', b'\xFC', b'\xD5', b'\x6D', b'\x42',
    b'\xFC', b'\x65', b'\x02', b'\xA9', b'\x6C', b'\xBD', b'\x90', b'\xD4', b'\x1E',
    b'\x78', b'\x4D', b'\xAD', b'\x0B', b'\xE9', b'\x24', b'\x7C', b'\xEC', b'\xFE',
    b'\x40', b'\xA4', b'\x41', b'\x50', b'\xE4', b'\xF1', b'\x1D', b'\x43', b'\x25',
    b'\x26', b'\xAA', b'\x37', b'\x9A', b'\xBC', b'\xA6', b'\xE1', b'\xC9', b'\xDE',
    b'\x58', b'\xE1', b'\x29', b'\xB0', b'\xBA', b'\xE0', b'\xB1', b'\xDE', b'\x4C',
    b'\xE5', b'\xD2', b'\x60', b'\x74', b'\xCA', b'\x16', b'\x8A', b'\x5B', b'\x7B',
    b'\x52', b'\x57', b'\xCA', b'\x99', b'\x53', b'\x02', b'\x57', b'\x58', b'\xC0',
    b'\x43', b'\x3A', b'\xBB', b'\xE9', b'\x48', b'\x6F', b'\xD9', b'\xF1', b'\x4F',
    b'\xB9', b'\x35', b'\x59', b'\xAF', b'\xCB', b'\x35', b'\x21', b'\x92', b'\x37',
    b'\x16', b'\x99', b'\x55', b'\x71', b'\x74', b'\xC2', b'\x4E', b'\x81', b'\xBD',
    b'\xCA', b'\x01', b'\x75', b'\x23', b'\xD3', b'\x31', b'\x12', b'\xA9', b'\xF8',
    b'\x5D', b'\x70', b'\xD8', b'\x04', b'\xC7', b'\xDD', b'\x82', b'\x97', b'\x51',
    b'\x0C', b'\xD7', b'\x0D', b'\x18', b'\x9A', b'\x2E', b'\x14', b'\x52', b'\x67',
    b'\x24', b'\xDE', b'\xF2', b'\xA3', b'\x15', b'\x65', b'\xE7', b'\x58', b'\x2E',
    b'\x8A', b'\x15', b'\x53', b'\x34', b'\x5D', b'\x5B', b'\xAE', b'\x45', b'\x64',
    b'\xC5', b'\xFF', b'\x2C', b'\x6C', b'\x2B', b'\xC1', b'\x1A', b'\x71', b'\xA5',
    b'\xC7', b'\xE3', b'\xC6', b'\xAE', b'\x41', b'\x98', b'\x31', b'\x75', b'\x79',
    b'\xD7', b'\x7C', b'\xF6', b'\x3E', b'\x31', b'\xFE', b'\x62', b'\x79', b'\x8B',
    b'\xBB', b'\x4E', b'\x55', b'\x88', b'\x68', b'\xC2', b'\x03', b'\x40', b'\x28',
    b'\xCE', b'\x86', b'\x15', b'\x18', b'\x80', b'\xEE', b'\xAB', b'\x9C', b'\x60',
    b'\x85', b'\x91', b'\x89', b'\x3D', b'\xE3', b'\x59', b'\xEE', b'\xBB', b'\xEB',
    b'\x60', b'\xC0', b'\x75', b'\xDE', b'\x50', b'\xA7', b'\x45', b'\xBF', b'\xFA',
    b'\x77', b'\xD5', b'\x4D', b'\x72', b'\x3B', b'\x98', b'\xB7',
  ]
  let even = avif_grid_frame_single_descriptor(62, 64, sample.length())
  let frame = avif_decode_grid_frame(sample, even).unwrap()
  assert_eq((frame.width, frame.height), (62, 64))
  let odd_width = avif_grid_frame_single_descriptor(63, 64, sample.length())
  let odd_height = avif_grid_frame_single_descriptor(64, 63, sample.length())
  assert_true(avif_decode_grid_frame(sample, odd_width) is None)
  assert_true(avif_decode_grid_frame(sample, odd_height) is None)
}

///|
test "native grid rejects covered output above the image pixel limit" {
  let sample : Array[Byte] = [
    b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFC', b'\x25', b'\x40', b'\x32',
    b'\xDB', b'\x02', b'\x17', b'\x80', b'\x00', b'\x01', b'\x20', b'\xE0', b'\xD8',
    b'\x94', b'\x03', b'\x8F', b'\xFC', b'\x62', b'\xEE', b'\x32', b'\x6B', b'\x0D',
    b'\x85', b'\xC9', b'\x75', b'\x5E', b'\x99', b'\xA4', b'\x75', b'\x19', b'\x48',
    b'\x59', b'\x47', b'\x03', b'\x16', b'\x29', b'\xE3', b'\xA2', b'\x41', b'\x6B',
    b'\x76', b'\xCD', b'\x9F', b'\x12', b'\xC3', b'\x0E', b'\xA2', b'\x5F', b'\x6C',
    b'\xD5', b'\x7C', b'\xEB', b'\x4C', b'\xA1', b'\xDF', b'\x68', b'\x1F', b'\xD2',
    b'\x74', b'\xCB', b'\x39', b'\x32', b'\x44', b'\x15', b'\xD8', b'\x3E', b'\x3E',
    b'\x01', b'\x42', b'\x42', b'\x1A', b'\x46', b'\x0B', b'\x7A', b'\x50', b'\x9A',
    b'\xBD', b'\x70', b'\xDC', b'\xBA', b'\x64', b'\x7B', b'\xE9', b'\x2C', b'\x24',
    b'\x5E', b'\xD5', b'\x2D', b'\x28', b'\x91', b'\xB3', b'\x43', b'\xEF', b'\x9C',
    b'\xC2', b'\x4E', b'\x35', b'\xAC', b'\xB9', b'\x4D', b'\x1B', b'\xD7', b'\x89',
    b'\xF1', b'\x8C', b'\x44', b'\x87', b'\xBE', b'\xA0', b'\x82', b'\xD3', b'\xD1',
    b'\xCC', b'\x89', b'\xFA', b'\x27', b'\xE5', b'\xD4', b'\x6F', b'\x92', b'\x31',
    b'\x65', b'\x0F', b'\x86', b'\x90', b'\x35', b'\x3E', b'\x6E', b'\x1B', b'\xF3',
    b'\xF1', b'\x12', b'\x30', b'\x53', b'\x21', b'\x4E', b'\x87', b'\x95', b'\xF4',
    b'\xCE', b'\x1F', b'\x2D', b'\x83', b'\x11', b'\x6D', b'\xDC', b'\xD9', b'\x71',
    b'\x1C', b'\xAE', b'\xAF', b'\xC2', b'\x4C', b'\x18', b'\x9C', b'\xAA', b'\x56',
    b'\xA4', b'\x3E', b'\x73', b'\xA6', b'\x6D', b'\x8C', b'\xA6', b'\x3C', b'\x62',
    b'\x8C', b'\x64', b'\x25', b'\xD0', b'\xA2', b'\x5A', b'\xEA', b'\xE5', b'\xC8',
    b'\x24', b'\x59', b'\x1A', b'\xC1', b'\x98', b'\x24', b'\xF9', b'\x48', b'\x78',
    b'\x1D', b'\x62', b'\x44', b'\xB9', b'\x8E', b'\x76', b'\x0F', b'\x79', b'\x08',
    b'\xEC', b'\xCA', b'\x6E', b'\x06', b'\xFD', b'\x09', b'\x0C', b'\xF8', b'\x64',
    b'\x33', b'\xC6', b'\x43', b'\x2D', b'\x26', b'\x19', b'\x24', b'\xF3', b'\x74',
    b'\x4C', b'\x00', b'\xBB', b'\xCD', b'\x5E', b'\x53', b'\x70', b'\xE4', b'\xEF',
    b'\x2C', b'\x70', b'\x94', b'\xD8', b'\x5D', b'\xFF', b'\xC3', b'\xA2', b'\x4B',
    b'\x88', b'\x3A', b'\x0B', b'\xAA', b'\xA6', b'\xE2', b'\x4B', b'\x72', b'\x7B',
    b'\x28', b'\x8F', b'\x3E', b'\xA1', b'\xA8', b'\xE9', b'\x22', b'\x0E', b'\xF8',
    b'\x7E', b'\x9A', b'\x11', b'\x8F', b'\xCF', b'\x21', b'\xF8', b'\x80', b'\xC1',
    b'\xCE', b'\xDC', b'\xD3', b'\xB8', b'\x7A', b'\x1D', b'\x42', b'\x67', b'\xCB',
    b'\x68', b'\xBE', b'\x4D', b'\x30', b'\x2D', b'\xA2', b'\xC9', b'\xA9', b'\xC4',
    b'\x31', b'\xAE', b'\x5D', b'\x91', b'\xBF', b'\x31', b'\x56', b'\x8B', b'\xB2',
    b'\x5F', b'\x9C', b'\x68', b'\x80', b'\x6E', b'\x0B', b'\x41', b'\x7E', b'\x94',
    b'\x3E', b'\x3D', b'\x7F', b'\x58', b'\x64', b'\xDF', b'\xFA', b'\xA0', b'\xBF',
    b'\x4C', b'\xC9', b'\x06', b'\x65', b'\x0E', b'\xA9', b'\x30', b'\x48', b'\x0A',
    b'\x8D', b'\x22', b'\xAE', b'\x9A', b'\x75', b'\xF0', b'\xE9', b'\x7C', b'\x53',
    b'\x3F', b'\x26', b'\xDD', b'\xE6', b'\x7E', b'\xF0', b'\x3E', b'\x1C', b'\x37',
    b'\x05', b'\xB8', b'\x64', b'\xA5', b'\x1C', b'\xDB', b'\x1D', b'\x8F', b'\x5C',
    b'\x65', b'\xE8', b'\x8F', b'\xCC', b'\x34', b'\xE3', b'\xDB', b'\xD3', b'\x6B',
    b'\x54', b'\xB8', b'\x03', b'\x38', b'\xCD', b'\x0D', b'\xC0',
  ]
  // Valid 64-pixel cells cover this canvas. The only invalid output
  // constraint is its pixel count, checked before decoding or allocation.
  assert_true(10001 > MAX_IMAGE_PIXELS / 10000)
  let tile : AvifGridTile = {
    item_id: 2,
    extents: [{ offset: 0, length: sample.length(), construction_method: 0, }],
  }
  let descriptor : AvifGridDescriptor = {
    item_id: 1,
    rows: 157,
    columns: 157,
    output_width: 10001,
    output_height: 10000,
    tiles: Array::make(157 * 157, tile),
  }
  assert_true(avif_decode_grid_frame(sample, descriptor) is None)
}
