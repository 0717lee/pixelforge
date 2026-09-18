/// Film grain tests.
///
/// The fixture is a reduced-still aomenc encode (--film-grain-test=1) of a
/// 64x64 8-bit 4:2:0 frame. Every expectation is dav1d 1.2.1 output: the
/// grain-free decode uses --filmgrain 0 and the grained decode is the default,
/// so the pair isolates the synthesis exactly. The reduced-still header is
/// required because AVIF stills always set reduced_still_picture_header, and
/// the go-av1 test streams are inter sequences that cannot exercise it.

///|
/// Position-sensitive 24-bit digest. A single differing sample changes it.
fn av1_fg_digest(samples : Array[Int]) -> Int {
  let mut h = 0
  for i in 0..<samples.length() {
    let v = samples[i] & 0xFF
    h = h ^ (v + (i & 0xFF))
    h = ((h << 5) & 0xFFFFFF) | ((h >> 19) & 0x1F)
  }
  h & 0xFFFFFF
}

///|
fn av1_fg_stream() -> Array[Byte] {
  [
    b'\x12', b'\x00', b'\x0A', b'\x06', b'\x18', b'\x15', b'\x7F', b'\xFF', b'\xB0',
    b'\x18', b'\x32', b'\xF8', b'\x1B', b'\x11', b'\xD0', b'\x00', b'\x00', b'\x40',
    b'\x05', b'\xA1', b'\x87', b'\x2C', b'\x67', b'\x84', b'\x00', b'\x06', b'\x62',
    b'\x08', b'\x64', b'\x0A', b'\x68', b'\x0C', b'\x2A', b'\x0E', b'\x22', b'\x10',
    b'\xE0', b'\x14', b'\xA4', b'\x18', b'\x66', b'\x1C', b'\x64', b'\x20', b'\x2C',
    b'\x23', b'\xEA', b'\x27', b'\xAC', b'\x2C', b'\xAE', b'\x10', b'\x20', b'\x00',
    b'\x28', b'\x80', b'\x38', b'\xB0', b'\x78', b'\xD0', b'\xB5', b'\x10', b'\xD3',
    b'\x41', b'\x0D', b'\x51', b'\x51', b'\xA1', b'\x22', b'\x00', b'\x03', b'\x8C',
    b'\x07', b'\x0A', b'\x08', b'\x4C', b'\x0A', b'\x0D', b'\x0D', b'\x8C', b'\x0F',
    b'\x4E', b'\x11', b'\x2E', b'\x15', b'\x36', b'\x1D', b'\x01', b'\x00', b'\x8D',
    b'\x01', b'\x01', b'\x00', b'\x69', b'\xC8', b'\xAB', b'\x00', b'\x9B', b'\xA5',
    b'\x01', b'\x00', b'\x9F', b'\x01', b'\x01', b'\x00', b'\xB9', b'\x2C', b'\xC5',
    b'\x00', b'\xB5', b'\x0F', b'\x4F', b'\x01', b'\x00', b'\xA3', b'\x01', b'\x01',
    b'\x00', b'\xC3', b'\x3E', b'\xCF', b'\x00', b'\xC1', b'\x1A', b'\x39', b'\x1E',
    b'\xF8', b'\x01', b'\x2E', b'\x5C', b'\x01', b'\xB2', b'\xC6', b'\x58', b'\x31',
    b'\x2A', b'\x7F', b'\x59', b'\xCF', b'\xFF', b'\xFF', b'\x25', b'\x48', b'\xE4',
    b'\xEC', b'\x92', b'\xE7', b'\x90', b'\x29', b'\x7C', b'\xDE', b'\x31', b'\x86',
    b'\x10', b'\x96', b'\x67', b'\x52', b'\x88', b'\xE1', b'\x8D', b'\xD1', b'\x79',
    b'\xE6', b'\xD5', b'\x41', b'\xB1', b'\x5E', b'\x3C', b'\x4D', b'\x3E', b'\x6F',
    b'\x09', b'\x36', b'\x33', b'\xE2', b'\xE6', b'\xD1', b'\x45', b'\x16', b'\x08',
    b'\x4B', b'\x7F', b'\xFB', b'\x96', b'\xC5', b'\x1F', b'\x45', b'\x92', b'\xD6',
    b'\x94', b'\xA0', b'\x68', b'\x72', b'\x76', b'\x6D', b'\x41', b'\xF9', b'\xEC',
    b'\x27', b'\x6A', b'\x15', b'\xEB', b'\xC4', b'\xC3', b'\x91', b'\x89', b'\x17',
    b'\x1E', b'\x45', b'\x16', b'\x8D', b'\x78', b'\xC7', b'\x1E', b'\x93', b'\xDC',
    b'\xD2', b'\x14', b'\x91', b'\xBE', b'\x72', b'\x92', b'\xFF', b'\xC3', b'\xF8',
    b'\x31', b'\x4D', b'\x48', b'\xA8', b'\x82', b'\xA4', b'\xD2', b'\xC2', b'\x21',
    b'\x78', b'\xD1', b'\xEB', b'\xF2', b'\x88', b'\xC5', b'\x40', b'\x54', b'\xD8',
    b'\x4C', b'\x2D', b'\x13', b'\x56', b'\x99', b'\x47', b'\x57', b'\xAF', b'\x9F',
    b'\xCD', b'\x43', b'\x0F', b'\x25', b'\xE3', b'\x92', b'\xFF', b'\xE9', b'\x3C',
    b'\xD9', b'\xAA', b'\x52', b'\xE1', b'\xAF', b'\x97', b'\xB0', b'\x16', b'\x52',
    b'\xE2', b'\x55', b'\x6B', b'\xB8', b'\x6C', b'\x3C', b'\x53', b'\xB2', b'\xDF',
    b'\xE5', b'\x2B', b'\x49', b'\xBF', b'\x87', b'\x5C', b'\x9D', b'\xFE', b'\x1B',
    b'\x2B', b'\x5A', b'\xEE', b'\xED', b'\x6C', b'\x30', b'\xE9', b'\x01', b'\x25',
    b'\xA3', b'\x0C', b'\xF6', b'\x21', b'\x3C', b'\xF8', b'\x1E', b'\x88', b'\x48',
    b'\xE7', b'\x5A', b'\x0B', b'\xB6', b'\x5D', b'\xC1', b'\x7E', b'\x1D', b'\xBF',
    b'\xBF', b'\x55', b'\x7A', b'\x38', b'\xD7', b'\xF8', b'\xC5', b'\x1A', b'\xE9',
    b'\xA4', b'\x80', b'\x0B', b'\x3E', b'\x5D', b'\x89', b'\x23', b'\x25', b'\xDB',
    b'\x2B', b'\x4D', b'\xF6', b'\xBF', b'\x74', b'\xF0', b'\x22', b'\xC8', b'\x18',
    b'\x25', b'\x83', b'\x45', b'\x94', b'\x2F', b'\xE5', b'\x7B', b'\x3F', b'\x66',
    b'\x73', b'\xEC', b'\xF6', b'\xAC', b'\x0D', b'\x6E', b'\x41', b'\x4C', b'\x2F',
    b'\x89', b'\xC7', b'\x34', b'\x27', b'\x52', b'\x08', b'\x3C', b'\xAB', b'\xAB',
    b'\x31', b'\x2B', b'\x46', b'\xB3', b'\x21', b'\x19', b'\xF7', b'\x04', b'\x62',
    b'\x44', b'\x8D', b'\x21', b'\xA2', b'\xA5', b'\xC0', b'\xC1', b'\xC0', b'\x11',
    b'\x6C', b'\xA0', b'\x89', b'\xD5', b'\x2A', b'\x56', b'\x87', b'\x58', b'\xA4',
    b'\x41', b'\xB1', b'\x92', b'\xAA', b'\x14', b'\x4C', b'\x59', b'\x47', b'\x3F',
    b'\x43', b'\x18', b'\xC5', b'\x16', b'\x14', b'\xA7', b'\x51', b'\x16', b'\x16',
    b'\xEE', b'\x42', b'\xDF', b'\xC3', b'\x1C', b'\xB7', b'\x29', b'\xB5', b'\xC9',
    b'\xCC', b'\x90', b'\x52', b'\x90', b'\x5B', b'\x42', b'\x1A', b'\x3B', b'\x8A',
    b'\x8A', b'\x46', b'\x9F', b'\x55', b'\xC6', b'\x94', b'\x19', b'\xBC', b'\xC3',
    b'\xCB', b'\x5E', b'\x90', b'\x80', b'\x66', b'\xE5', b'\xC7', b'\x76', b'\x47',
    b'\x3B', b'\x56', b'\xE4', b'\x7A', b'\x5C', b'\x26', b'\x2C', b'\x82', b'\x4B',
    b'\xF9', b'\x5A', b'\x4D', b'\x47', b'\xEC', b'\xCC', b'\xD0', b'\xCB', b'\x76',
    b'\xA2', b'\x1C', b'\xDF', b'\x2B', b'\xC8', b'\x66', b'\x34', b'\xC9', b'\x35',
    b'\x05', b'\xED', b'\xB5', b'\xD3', b'\xBC', b'\x3B', b'\x23', b'\xA4', b'\xEE',
    b'\x65', b'\xEC', b'\x9E', b'\x87', b'\xD3', b'\x35', b'\x11', b'\x92', b'\xBE',
    b'\x37', b'\xEF', b'\x42', b'\x29', b'\x64', b'\x78', b'\xCC', b'\x82', b'\x09',
    b'\x06', b'\x6A', b'\x69', b'\x84', b'\x58', b'\x2F', b'\x56', b'\x14', b'\x5A',
    b'\x64', b'\x0D', b'\x06', b'\x29', b'\x53', b'\xD2', b'\x5E', b'\x04', b'\x8B',
    b'\xC8', b'\xB8', b'\x00', b'\xB0', b'\x2C', b'\x3E', b'\x33', b'\x15', b'\x4C',
    b'\x58', b'\x91', b'\x03', b'\xDC', b'\x49', b'\xC9', b'\xD0', b'\x7E', b'\xAB',
    b'\xC9', b'\x58', b'\x25', b'\x91', b'\x7A', b'\x5A', b'\x5D', b'\x72', b'\xE6',
    b'\xEC', b'\x41', b'\x03', b'\xD1', b'\x25', b'\x75', b'\x90', b'\xAE', b'\x98',
    b'\xF7', b'\xD6', b'\x87', b'\x78', b'\x8F', b'\x40', b'\x49', b'\x65', b'\x52',
    b'\xAF', b'\x5C', b'\x48', b'\x95', b'\x57', b'\xA5', b'\x0C', b'\x54', b'\x16',
    b'\xBF', b'\x31', b'\x39', b'\x47', b'\xED', b'\xFC', b'\xB9', b'\xBE', b'\x2E',
    b'\xEE', b'\x78', b'\x2E', b'\xE0', b'\x22', b'\x3F', b'\x5C', b'\x1F', b'\x62',
    b'\x1F', b'\xB0', b'\x46', b'\x43', b'\xD1', b'\xA3', b'\x5F', b'\xF4', b'\xB3',
    b'\x00', b'\x60', b'\x12', b'\xB5', b'\x1D', b'\xC9', b'\x54', b'\xF2', b'\x56',
    b'\x42', b'\x28', b'\x8F', b'\x1B', b'\x8B', b'\xBF', b'\xB7', b'\xF3', b'\xDB',
    b'\x36', b'\x77', b'\x28', b'\x69', b'\x62', b'\x7F', b'\xA3', b'\xB2', b'\xAA',
    b'\xD9', b'\xFD', b'\x02', b'\x43', b'\x5A', b'\x2D', b'\xC7', b'\x8D', b'\xB8',
    b'\x9F', b'\x6A', b'\x53', b'\x3D', b'\x83', b'\xC5', b'\xA8', b'\x5E', b'\x7A',
    b'\x5F', b'\xB1', b'\xC4', b'\x06', b'\x19', b'\x4F', b'\x8C', b'\xDF', b'\x8A',
    b'\xA5', b'\x92', b'\xF5', b'\x78', b'\x25', b'\xC5', b'\xAC', b'\xB2', b'\xD7',
    b'\xD4', b'\xA3', b'\x99', b'\xFF', b'\x07', b'\xDA', b'\x84', b'\xA8', b'\x20',
    b'\xAD', b'\xA7', b'\xD1', b'\x90', b'\xA9', b'\xEA', b'\x0A', b'\x94', b'\x67',
    b'\xA9', b'\x25', b'\x1E', b'\xEE', b'\xBD', b'\x54', b'\x6C', b'\x68', b'\x68',
    b'\x7F', b'\x78', b'\xFA', b'\xBA', b'\x60', b'\x15', b'\x64', b'\xBF', b'\x27',
    b'\x09', b'\xA9', b'\xBF', b'\x24', b'\x2D', b'\x90', b'\x06', b'\xD7', b'\xE0',
    b'\x74', b'\x5C', b'\x88', b'\x58', b'\x47', b'\xDF', b'\x76', b'\xF1', b'\x3B',
    b'\xC1', b'\x3A', b'\x01', b'\x39', b'\x79', b'\x64', b'\x2C', b'\x86', b'\xE1',
    b'\xA2', b'\xF7', b'\x0F', b'\x52', b'\x1A', b'\x17', b'\xE8', b'\xD7', b'\x27',
    b'\xFC', b'\xC5', b'\x89', b'\xD8', b'\x9E', b'\x1D', b'\xE7', b'\x3F', b'\x3B',
    b'\x1A', b'\xF5', b'\x90', b'\x40', b'\xE6', b'\x9D', b'\x15', b'\x9E', b'\x56',
    b'\x8F', b'\xDD', b'\x0E', b'\xC9', b'\x18', b'\x43', b'\x98', b'\xBD', b'\x97',
    b'\x13', b'\x04', b'\x62', b'\x75', b'\x31', b'\x0F', b'\x47', b'\x1B', b'\x48',
    b'\x80', b'\x9A', b'\x12', b'\x47', b'\xC6', b'\xCA', b'\x53', b'\x45', b'\x5B',
    b'\x86', b'\xB8', b'\x1F', b'\x70', b'\xB3', b'\x48', b'\xB2', b'\xE6', b'\xBB',
    b'\xA0', b'\x57', b'\x32', b'\x4F', b'\x86', b'\xE0', b'\xF3', b'\xAE', b'\xF3',
    b'\x74', b'\x90', b'\xB9', b'\x27', b'\x71', b'\x32', b'\x36', b'\xA0', b'\x94',
    b'\xFC', b'\xDC', b'\xC1', b'\x54', b'\x0A', b'\x94', b'\x31', b'\x70', b'\x37',
    b'\xDA', b'\x6E', b'\x8D', b'\x02', b'\x5E', b'\x88', b'\x10', b'\x47', b'\x3E',
    b'\xDA', b'\x99', b'\x6E', b'\x63', b'\x04', b'\xCF', b'\x2B', b'\xD8', b'\x38',
    b'\xEA', b'\x19', b'\x1C', b'\x9C', b'\x72', b'\x31', b'\x2C', b'\x2C', b'\x26',
    b'\xCE', b'\x69', b'\x1A', b'\xB2', b'\x2C', b'\x75', b'\x25', b'\xB5', b'\x0E',
    b'\x92', b'\x83', b'\x84', b'\xD2', b'\xB8', b'\xF8', b'\x88', b'\x1C', b'\x7D',
    b'\x78', b'\x13', b'\x4F', b'\x31', b'\xCF', b'\xF1', b'\x37', b'\xD2', b'\x80',
    b'\x04', b'\x9D', b'\x47', b'\x25', b'\xCD', b'\xB8', b'\xF3', b'\x3C', b'\x81',
    b'\xD6', b'\x6F', b'\x23', b'\x8B', b'\x10', b'\xFD', b'\xAF', b'\x15', b'\xC0',
    b'\x4E', b'\x92', b'\x19', b'\x29', b'\x94', b'\x00', b'\xC3', b'\x33', b'\xA9',
    b'\x47', b'\x5F', b'\x20', b'\x22', b'\x72', b'\x1A', b'\xC4', b'\x21', b'\x41',
    b'\x65', b'\x3F', b'\x0A', b'\x63', b'\x09', b'\x83', b'\xFA', b'\xB6', b'\xFE',
    b'\xC2', b'\x8B', b'\x50', b'\x60', b'\xD9', b'\x13', b'\x24', b'\xA6', b'\x38',
    b'\xA2', b'\x69', b'\xB0', b'\x7B', b'\x7B', b'\xED', b'\x8B', b'\xA3', b'\x25',
    b'\x1D', b'\xB1', b'\xF1', b'\x15', b'\x27', b'\x1A', b'\xD8', b'\x57', b'\x31',
    b'\xA2', b'\x10', b'\x23', b'\x1D', b'\x2D', b'\x72', b'\x98', b'\xF1', b'\xAC',
    b'\x86', b'\xB4', b'\xE0', b'\x38', b'\x3B', b'\x8F', b'\xD1', b'\x28', b'\x9E',
    b'\x7B', b'\xE8', b'\x35', b'\xB7', b'\xA9', b'\xDE', b'\xFE', b'\x6F', b'\x92',
    b'\x0E', b'\xE9', b'\x29', b'\x12', b'\x44', b'\x66', b'\x91', b'\xFB', b'\x94',
    b'\xE7', b'\xF6', b'\x98', b'\x53', b'\xE3', b'\x42', b'\xEB', b'\xBE', b'\x02',
    b'\x61', b'\x2F', b'\x56', b'\xDD', b'\x34', b'\xFF', b'\xD0', b'\x0C', b'\xDE',
    b'\x19', b'\x8B', b'\xFF', b'\x47', b'\xF5', b'\xC2', b'\xD5', b'\x07', b'\x6C',
    b'\x49', b'\x83', b'\x85', b'\x8C', b'\xFE', b'\x6B', b'\xA1', b'\x09', b'\x26',
    b'\x3C', b'\x1C', b'\x03', b'\x89', b'\x36', b'\xA2', b'\xF0', b'\x42', b'\xFE',
    b'\x64', b'\x38', b'\xE2', b'\x4A', b'\xDD', b'\x33', b'\x05', b'\x0F', b'\x87',
    b'\xAA', b'\x3F', b'\x20', b'\x37', b'\xCF', b'\xE1', b'\xB5', b'\x5C', b'\x88',
    b'\x7E', b'\x64', b'\x93', b'\x28', b'\xFA', b'\x63', b'\x56', b'\x38', b'\xC2',
    b'\x22', b'\x21', b'\x00', b'\xCD', b'\xB2', b'\x0C', b'\xD7', b'\xB3', b'\x21',
    b'\xC3', b'\x63', b'\xA8', b'\x30', b'\x3A', b'\x4D', b'\xA1', b'\x0E', b'\x06',
    b'\xC8', b'\xCF', b'\x3F', b'\x3F', b'\x26', b'\x88', b'\x06', b'\x21', b'\xBD',
    b'\xA5', b'\x38', b'\xA2', b'\x0F', b'\x1E', b'\x4F', b'\xCA', b'\xC8', b'\x83',
    b'\x86', b'\x89', b'\x0D', b'\x5C', b'\x8B', b'\x77', b'\x52', b'\x33', b'\x7C',
    b'\xA2', b'\xDD', b'\x83', b'\x2F', b'\x8B', b'\x68', b'\xF9', b'\xB9', b'\xB5',
    b'\x6F', b'\x5B', b'\x61', b'\x24', b'\x94', b'\x6B', b'\x93', b'\x05', b'\x12',
    b'\x7F', b'\xE9', b'\x04', b'\xC0', b'\xD7', b'\xF9', b'\x42', b'\x22', b'\x48',
    b'\xA3', b'\x86', b'\x2B', b'\x61', b'\x3D', b'\x5A', b'\x70', b'\x4C', b'\x96',
    b'\x8F', b'\xCE', b'\xE2', b'\xD4', b'\x36', b'\x74', b'\x7F', b'\x96', b'\xCB',
    b'\x7B', b'\x83', b'\xDF', b'\x1D', b'\xDC', b'\x89', b'\xA8', b'\xE1', b'\x43',
    b'\x2D', b'\x47', b'\xF0', b'\x19', b'\x67', b'\x73', b'\x59', b'\x11', b'\x91',
    b'\xDC', b'\xF3', b'\x19', b'\x5E', b'\x84', b'\xE5', b'\x79', b'\x39', b'\xCF',
    b'\xC6', b'\xC6', b'\xB1', b'\x6D', b'\x35', b'\xA6', b'\x22', b'\x05', b'\x18',
    b'\x30', b'\x19', b'\x2A', b'\x89', b'\xAE', b'\xFA', b'\xC5', b'\x03', b'\x6A',
    b'\x15', b'\x93', b'\xE4', b'\xDF', b'\x89', b'\x74', b'\x18', b'\xA6', b'\xB9',
    b'\x8A', b'\x96', b'\x26', b'\x90', b'\xDD', b'\xDF', b'\x27', b'\x88', b'\x5A',
    b'\x5A', b'\x8F', b'\x72', b'\x65', b'\xBE', b'\x8D', b'\xE7', b'\xCB', b'\x51',
    b'\xD2', b'\x4E', b'\x7D', b'\xE9', b'\x33', b'\x45', b'\x59', b'\xF6', b'\x4A',
    b'\x60', b'\xCD', b'\x8D', b'\x14', b'\xA1', b'\x5F', b'\x94', b'\xC0', b'\x5A',
    b'\xDB', b'\xCC', b'\x8B', b'\x9C', b'\x2C', b'\x09', b'\xC9', b'\xD0', b'\x39',
    b'\x84', b'\x64', b'\x9D', b'\x0E', b'\xC8', b'\x07', b'\xA7', b'\x44', b'\x1B',
    b'\x71', b'\x9F', b'\xE4', b'\x13', b'\x35', b'\x32', b'\x4B', b'\xBA', b'\x17',
    b'\xBB', b'\x5B', b'\xE9', b'\x0E', b'\xD0', b'\xB0', b'\xAF', b'\x02', b'\x07',
    b'\x3F', b'\x9F', b'\x8B', b'\x1C', b'\x25', b'\x82', b'\x98', b'\x6B', b'\x30',
    b'\xED', b'\xBD', b'\x0D', b'\xDA', b'\xEC', b'\x8E', b'\xA5', b'\xD6', b'\x56',
    b'\x78', b'\x43', b'\x5D', b'\x8E', b'\x3B', b'\x86', b'\xF7', b'\x60', b'\x88',
    b'\xDB', b'\x0D', b'\xDB', b'\xF1', b'\x13', b'\xB2', b'\x94', b'\xE7', b'\xBF',
    b'\x32', b'\xFA', b'\x02', b'\x12', b'\x5D', b'\x67', b'\xC6', b'\x47', b'\x4F',
    b'\xF2', b'\x1D', b'\x30', b'\xCD', b'\x54', b'\x45', b'\x0B', b'\xD2', b'\xF7',
    b'\xD2', b'\xD8', b'\xF9', b'\xEB', b'\x47', b'\xB7', b'\xB6', b'\xD8', b'\x6D',
    b'\x5C', b'\xB5', b'\x5E', b'\xF1', b'\x30', b'\x11', b'\x50', b'\x41', b'\x59',
    b'\x87', b'\x4B', b'\x7A', b'\x94', b'\x99', b'\x20', b'\xEA', b'\x88', b'\x10',
    b'\x9E', b'\x99', b'\xBA', b'\xE8', b'\x2C', b'\x85', b'\x49', b'\x7F', b'\x90',
    b'\xCC', b'\xA3', b'\x2A', b'\x8E', b'\x3D', b'\x2B', b'\xE8', b'\xE7', b'\x63',
    b'\x4D', b'\xF3', b'\x84', b'\xA5', b'\xC4', b'\x03', b'\xA8', b'\xD9', b'\x27',
    b'\x81', b'\x8B', b'\x14', b'\x44', b'\xF4', b'\x2B', b'\x99', b'\x96', b'\x6A',
    b'\xDD', b'\xE9', b'\x9A', b'\x2E', b'\x78', b'\x52', b'\x29', b'\x29', b'\x2D',
    b'\x27', b'\x63', b'\x9F', b'\xE3', b'\x92', b'\xA9', b'\x10', b'\xCF', b'\x3B',
    b'\x73', b'\xC8', b'\x02', b'\x13', b'\xFB', b'\xEB', b'\x4C', b'\xA4', b'\x2C',
    b'\xA9', b'\x0D', b'\xB4', b'\xC8', b'\x9C', b'\x2B', b'\x92', b'\x1A', b'\x1F',
    b'\xFB', b'\x4F', b'\x85', b'\x69', b'\x43', b'\xBA', b'\xF3', b'\xB0', b'\xFC',
    b'\x76', b'\x15', b'\x78', b'\xE8', b'\xB3', b'\x0E', b'\xCC', b'\xB4', b'\x2F',
    b'\x0E', b'\x39', b'\x7C', b'\xB8', b'\x50', b'\x6B', b'\xF9', b'\x87', b'\x3F',
    b'\x0F', b'\x4F', b'\x5F', b'\x65', b'\xBC', b'\xED', b'\xAC', b'\x80', b'\xEE',
    b'\x9C', b'\x00', b'\x5D', b'\x6B', b'\x7A', b'\x87', b'\xBD', b'\xB1', b'\xA7',
    b'\xE9', b'\xAE', b'\x66', b'\x4E', b'\x03', b'\xD1', b'\xC8', b'\x2F', b'\x8B',
    b'\x06', b'\x24', b'\x14', b'\x0B', b'\xB0', b'\x02', b'\x88', b'\x20', b'\xBD',
    b'\x86', b'\xF7', b'\xE5', b'\xB2', b'\xF9', b'\x4F', b'\xF1', b'\xF1', b'\x31',
    b'\x88', b'\x5A', b'\xFE', b'\x16', b'\x9C', b'\xBB', b'\x90', b'\x6E', b'\xFF',
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\x66', b'\x5B', b'\x6B',
    b'\xF4', b'\xE6', b'\x54', b'\xB5', b'\x3A', b'\x13', b'\x7B', b'\xA5', b'\x57',
    b'\x8E', b'\xAC', b'\x50', b'\x85', b'\x7B', b'\x58', b'\xCE', b'\x70', b'\x9A',
    b'\x82', b'\xA2', b'\x54', b'\x92', b'\x9B', b'\x8E', b'\x7E', b'\xEA', b'\x66',
    b'\x30', b'\xAA', b'\x8A', b'\xA9', b'\xBA', b'\x32', b'\x6E', b'\x8E', b'\xE8',
    b'\x32', b'\xD6', b'\xC0', b'\x90', b'\x70', b'\xD0', b'\xE6', b'\xB1', b'\xD1',
    b'\x1A', b'\x8E', b'\x76', b'\x53', b'\x7F', b'\x32', b'\x88', b'\xC5', b'\xC4',
    b'\x15', b'\x05', b'\x4D', b'\x4E', b'\x1C', b'\x49', b'\xBD', b'\xBA', b'\x3B',
    b'\xA0', b'\xA8', b'\x1A', b'\xB3', b'\x77', b'\x35', b'\x9B', b'\x13', b'\x0F',
    b'\xDE', b'\x5A', b'\x2C', b'\x3F', b'\xAE', b'\x2B', b'\xCA', b'\xE1', b'\x39',
    b'\xB5', b'\xA2', b'\x1D', b'\xD2', b'\x0F', b'\x91', b'\x3A', b'\x54', b'\xC7',
    b'\x41', b'\x6D', b'\x02', b'\x26', b'\x30', b'\x24', b'\x1B', b'\xDA', b'\x36',
    b'\x0E', b'\x12', b'\x0E', b'\x8B', b'\xEF', b'\x19', b'\xCC', b'\x6E', b'\xE9',
    b'\xBF', b'\x96', b'\xEF', b'\x9A', b'\x5A', b'\x45', b'\xFA', b'\x8F', b'\x1E',
    b'\x39', b'\x6C', b'\x56', b'\x67', b'\x62', b'\x3A', b'\xEB', b'\x29', b'\x9B',
    b'\x21', b'\x7E', b'\x9A', b'\xE7', b'\xA8', b'\x32', b'\x45', b'\xB8', b'\x54',
    b'\x22', b'\x8B', b'\xD7', b'\x92', b'\x9A', b'\x6A', b'\x08', b'\x84', b'\x76',
    b'\x20', b'\x8D', b'\x87', b'\x1B', b'\xC9', b'\x7A', b'\xA5', b'\x05', b'\x02',
    b'\xCE', b'\xE5', b'\x32', b'\x4D', b'\x80', b'\x0B', b'\x8E', b'\xF5', b'\x8E',
    b'\x5C', b'\xC3', b'\x81', b'\x23', b'\x42', b'\x07', b'\x50', b'\xC6', b'\xDE',
    b'\xB8', b'\x19', b'\xD6', b'\x5A', b'\x6A', b'\x8A', b'\x21', b'\x66', b'\x23',
    b'\xA3', b'\x53', b'\x60', b'\x52', b'\x10', b'\x3B', b'\x7D', b'\xA1', b'\x5F',
    b'\x16', b'\x50', b'\x9E', b'\x55', b'\x48', b'\x72', b'\x76', b'\x31', b'\x3B',
    b'\x94', b'\x4F', b'\xA9', b'\x0E', b'\x2B', b'\x16', b'\x66', b'\xA5', b'\xA2',
    b'\xC2', b'\x91', b'\xBF', b'\xBA', b'\x42', b'\x39', b'\xD4', b'\x11', b'\x80',
    b'\x79', b'\xCF', b'\xB1', b'\xE0', b'\xAD', b'\x48', b'\x90', b'\x5B', b'\x84',
    b'\xD3', b'\x4D', b'\xF5', b'\xBE', b'\xAD', b'\xEF', b'\x7A', b'\x9A', b'\x9A',
    b'\x56', b'\x6E', b'\x73', b'\x00', b'\x1A', b'\xC9', b'\x86', b'\xF2', b'\xE3',
    b'\x28', b'\xEC', b'\x94', b'\x7D', b'\x5F', b'\xD9', b'\x93', b'\xC6', b'\x43',
    b'\x90', b'\xD2', b'\x6E', b'\x8D', b'\xA9', b'\xAE', b'\xEB', b'\xC5', b'\x5B',
    b'\xB7', b'\xA2', b'\x52', b'\x39', b'\xB7', b'\x94', b'\xF9', b'\x0E', b'\x31',
    b'\x47', b'\x8B', b'\xDE', b'\x77', b'\xFD', b'\xBF', b'\xB0', b'\x03', b'\xAA',
    b'\x47', b'\xBA', b'\x38', b'\xA3', b'\x72', b'\x62', b'\x41', b'\x57', b'\x2A',
    b'\xD9', b'\x20', b'\x7B', b'\x6E', b'\xC2', b'\x93', b'\x99', b'\x89', b'\x10',
    b'\x29', b'\x62', b'\x97', b'\xD9', b'\x51', b'\x59', b'\xEF', b'\x1F', b'\x2E',
    b'\xAC', b'\xF8', b'\xCF', b'\x94', b'\xF8', b'\x44', b'\x4E', b'\x92', b'\x58',
    b'\x91', b'\x77', b'\x7A', b'\x55', b'\x8A', b'\xA1', b'\x9B', b'\xEF', b'\x1C',
    b'\x27', b'\x89', b'\xFC', b'\x15', b'\x4C', b'\xE9', b'\x74', b'\x1C', b'\x44',
    b'\xD7', b'\x18', b'\x7E', b'\x67', b'\x6E', b'\xE5', b'\xC8', b'\x23', b'\x34',
    b'\x33', b'\xB7', b'\xBD', b'\x3C', b'\x92', b'\xBC', b'\x62', b'\x09', b'\xBF',
    b'\x1F', b'\x74', b'\x9B', b'\xA3', b'\xF6', b'\xD1', b'\x1D', b'\x0A', b'\x2D',
    b'\x80', b'\x29', b'\x8B', b'\x43', b'\xD3', b'\x2A', b'\x04', b'\x7E', b'\x30',
    b'\x83', b'\xA3', b'\xAE', b'\x91', b'\x9F', b'\xDC', b'\xBE', b'\x85', b'\xE4',
    b'\x9E', b'\x5D', b'\x4E', b'\xC9', b'\xF8', b'\x89', b'\x0D', b'\x25', b'\xE7',
    b'\x94', b'\x1C', b'\xC2', b'\x95', b'\x95', b'\x13', b'\x68', b'\x44', b'\xE0',
    b'\x1A', b'\x46', b'\x1A', b'\x69', b'\x56', b'\x21', b'\x4A', b'\x06', b'\x16',
    b'\xEE', b'\xCA', b'\x50', b'\x8B', b'\xD1', b'\x72', b'\x3F', b'\x3E', b'\xE6',
    b'\xFA', b'\x7F', b'\x19', b'\xD1', b'\x56', b'\xF9', b'\x32', b'\xA6', b'\x66',
    b'\xF8', b'\xE9', b'\xF2', b'\x65', b'\x15', b'\x95', b'\xBD', b'\xE6', b'\xE9',
    b'\x60', b'\x41', b'\x8B', b'\xA2', b'\x56', b'\x6F', b'\x72', b'\x04', b'\xAC',
    b'\x3C', b'\x1E', b'\x0D', b'\x65', b'\x7C', b'\xCC', b'\xEC', b'\xBC', b'\x7E',
    b'\xEB', b'\x89', b'\xDD', b'\x7D', b'\x29', b'\xCB', b'\x40', b'\x4A', b'\xEA',
    b'\x0D', b'\x21', b'\x92', b'\x9B', b'\xC3', b'\xD3', b'\xE0', b'\x22', b'\x0B',
    b'\x90', b'\xC2', b'\xF9', b'\x7F', b'\x4B', b'\xF1', b'\x0A', b'\x9A', b'\x78',
    b'\x21', b'\xF6', b'\xF3', b'\x39', b'\xC1', b'\xFF', b'\x0A', b'\x72', b'\x4E',
    b'\xD7', b'\x20', b'\x43', b'\x64', b'\x41', b'\x16', b'\x8B', b'\xC5', b'\x7F',
    b'\xEF', b'\xFE', b'\x29', b'\xE6', b'\x51', b'\x97', b'\xFB', b'\x70', b'\xB4',
    b'\xF8', b'\xD9', b'\x15', b'\xBB', b'\x0A', b'\xBC', b'\xC9', b'\xFD', b'\x1A',
    b'\xB1', b'\xC7', b'\x59', b'\xB2', b'\xBB', b'\x59', b'\x90', b'\xB1', b'\x50',
    b'\x76', b'\x38', b'\xFE', b'\xB6', b'\x66', b'\x9B', b'\x5F', b'\xF3', b'\x6A',
    b'\x16', b'\xF9', b'\x24', b'\x51', b'\xF7', b'\xC2', b'\xB4', b'\xC9', b'\x94',
    b'\x39', b'\x98', b'\x9D', b'\x3C', b'\x15', b'\x93', b'\xD7', b'\x70', b'\xD7',
    b'\xCA', b'\xFF', b'\xAD', b'\xC6', b'\x3F', b'\x38', b'\xE1', b'\x08', b'\x4E',
    b'\xB7', b'\xD8', b'\x5E', b'\x87', b'\x7F', b'\xF4', b'\x67', b'\x2E', b'\xBC',
    b'\x5B', b'\x5D', b'\xE7', b'\xFC', b'\xAA', b'\x94', b'\xD8', b'\xF5', b'\x4D',
    b'\xEF', b'\x39', b'\x69', b'\x2D', b'\x4E', b'\xE1', b'\x70', b'\x70', b'\xB7',
    b'\xEF', b'\xFD', b'\x9E', b'\xF9', b'\x29', b'\xFE', b'\xA0', b'\x41', b'\xBA',
    b'\x56', b'\x91', b'\x38', b'\x01', b'\x58', b'\xC8', b'\xC6', b'\x2B', b'\x5C',
    b'\x8E', b'\x73', b'\xD4', b'\x45', b'\x19', b'\x96', b'\x76', b'\x94', b'\xAB',
    b'\xB6', b'\xD2', b'\x21', b'\xFD', b'\x33', b'\xA9', b'\x43', b'\x8E', b'\x36',
    b'\xD2', b'\xC0', b'\x91', b'\xAA', b'\x3D', b'\x65', b'\x5D', b'\xEC', b'\x25',
    b'\x1E', b'\xC6', b'\x9C', b'\xF5', b'\x59', b'\xEE', b'\x68', b'\xC9', b'\x81',
    b'\xD9', b'\x71', b'\x14', b'\x61', b'\x1B', b'\x84', b'\xED', b'\x42', b'\x6A',
    b'\x3E', b'\xFF', b'\x6D', b'\x12', b'\x4A', b'\x90', b'\xBD', b'\x8E', b'\x6C',
    b'\x71', b'\x30', b'\x32', b'\xE8', b'\xB7', b'\x6A', b'\x60', b'\xF7', b'\x6A',
    b'\x41', b'\x04', b'\x14', b'\x59', b'\xC9', b'\x6E', b'\x97', b'\x1F', b'\x40',
    b'\x21', b'\x81', b'\x7E', b'\xDA', b'\xDD', b'\xB3', b'\xC5', b'\x33', b'\x81',
    b'\x21', b'\xB3', b'\xFE', b'\x08', b'\x11', b'\x61', b'\x2C', b'\xB2', b'\xC3',
    b'\x53', b'\xC9', b'\x22', b'\xD8', b'\xA8', b'\x0F', b'\xA9', b'\x9F', b'\xBA',
    b'\xD8', b'\x83', b'\xA9', b'\xED', b'\xD8', b'\xED', b'\x92', b'\x71', b'\xC3',
    b'\x77', b'\xE8', b'\xBC', b'\x9E', b'\xB5', b'\xEA', b'\x18', b'\xA2', b'\x45',
    b'\x75', b'\x3B', b'\x6E', b'\x56', b'\x52', b'\x62', b'\xD7', b'\x61', b'\xCE',
    b'\xA5', b'\x48', b'\xAF', b'\x6D', b'\x25', b'\x1F', b'\xB9', b'\x81', b'\xA3',
    b'\xA3', b'\x2B', b'\xF8', b'\x95', b'\x5A', b'\x86', b'\xB3', b'\xD6', b'\xA3',
    b'\x39', b'\xB3', b'\x25', b'\x34', b'\x79', b'\x9F', b'\x7E', b'\xB6', b'\x7B',
    b'\x09', b'\xAD', b'\x90', b'\xEF', b'\xCA', b'\xD0', b'\xCE', b'\x45', b'\x71',
    b'\xBB', b'\x9A', b'\xD0', b'\x47', b'\x48', b'\xE7', b'\xB6', b'\x76', b'\xAB',
    b'\xD2', b'\x3D', b'\xA3', b'\xC6', b'\x5C', b'\x00', b'\xF5', b'\x27', b'\x0D',
    b'\x6C', b'\x5D', b'\xD2', b'\x61', b'\x41', b'\x40', b'\x9E', b'\xF2', b'\xDD',
    b'\x32', b'\x2E', b'\xA8', b'\x89', b'\x7A', b'\xC9', b'\x1E', b'\xC3', b'\x46',
    b'\x41', b'\xB6', b'\x8D', b'\x86', b'\x88', b'\xBA', b'\xAA', b'\xD8', b'\x42',
    b'\x4E', b'\x50', b'\x9F', b'\xD2', b'\x0E', b'\xE5', b'\xFA', b'\x76', b'\x15',
    b'\x6C', b'\x2C', b'\xDF', b'\x96', b'\x82', b'\x76', b'\x7A', b'\x01', b'\xDD',
    b'\xF1', b'\xC5', b'\x2B', b'\x39', b'\x31', b'\xF7', b'\x1C', b'\xFB', b'\xDD',
    b'\xE5', b'\x0C', b'\xA0', b'\x1D', b'\x26', b'\xAF', b'\x9A', b'\xC1', b'\x1A',
    b'\x84', b'\x2D', b'\xF8', b'\xDB', b'\x40', b'\xB6', b'\x76', b'\x7C', b'\xCE',
    b'\x65', b'\xD6', b'\x7B', b'\xFF', b'\x46', b'\x01', b'\x22', b'\x85', b'\x8C',
    b'\xDE', b'\x03', b'\x61', b'\x5D', b'\x1A', b'\xEE', b'\x52', b'\xB6', b'\xF6',
    b'\xDE', b'\xF4', b'\x6E', b'\x2D', b'\x66', b'\xCE', b'\x67', b'\xCA', b'\xE7',
    b'\x03', b'\xE9', b'\xF6', b'\xF0', b'\xB3', b'\x9C', b'\xB9', b'\x6C', b'\xD8',
    b'\x05', b'\x90', b'\xA5', b'\x33', b'\xD3', b'\x03', b'\x55', b'\x7A', b'\x28',
    b'\x92', b'\x65', b'\xA2', b'\xCA', b'\x10', b'\x4C', b'\x44', b'\x42', b'\xC6',
    b'\xFE', b'\x04', b'\x4A', b'\x71', b'\x42', b'\xD6', b'\x45', b'\x2F', b'\xEC',
    b'\xE8', b'\xB5', b'\x57', b'\x66', b'\x98', b'\xDA', b'\xE0', b'\xB9', b'\xFA',
    b'\xC3', b'\x85', b'\x92', b'\x57', b'\x94', b'\xB4', b'\xE4', b'\x92', b'\x2A',
    b'\x4D', b'\x78', b'\x82', b'\x2B', b'\xDB', b'\x27', b'\xCA', b'\x2B', b'\xC0',
    b'\xB0', b'\x8A', b'\x21', b'\x42', b'\x95', b'\xE4', b'\xC6', b'\xE9', b'\x45',
    b'\xCD', b'\xF4', b'\x06', b'\xEE', b'\x3D', b'\xE4', b'\x78', b'\xC5', b'\x8D',
    b'\xF1', b'\xFD', b'\xA2', b'\x09', b'\x5A', b'\xE2', b'\xA2', b'\x4A', b'\xCD',
    b'\x12', b'\x23', b'\xD6', b'\xCF', b'\x5E', b'\xE4', b'\xF6', b'\x6C', b'\x5E',
    b'\x02', b'\x82', b'\xF3', b'\x77', b'\x6E', b'\x00', b'\xDA', b'\xCC', b'\x89',
    b'\x70', b'\x32', b'\xF0', b'\x91', b'\x16', b'\xAB', b'\x49', b'\x00', b'\x2B',
    b'\xE6', b'\xA2', b'\xD8', b'\x47', b'\x21', b'\x31', b'\x6B', b'\xC4', b'\x6D',
    b'\x37', b'\x8A', b'\x8A', b'\x05', b'\x39', b'\x99', b'\x16', b'\x06', b'\xFD',
    b'\x6C', b'\x14', b'\x5C', b'\xD8', b'\x4C', b'\xAA', b'\x4F', b'\x81', b'\x12',
    b'\x3B', b'\x6F', b'\x3C', b'\x11', b'\x66', b'\x04', b'\x12', b'\xD6', b'\x0E',
    b'\x4F', b'\x64', b'\x7A', b'\xCA', b'\x0C', b'\x8F', b'\x94', b'\xD9', b'\x02',
    b'\xEC', b'\x2E', b'\xD6', b'\x74', b'\x06', b'\x64', b'\xCE', b'\x8C', b'\x0B',
    b'\xB8', b'\x72', b'\xFD', b'\x55', b'\xFB', b'\x96', b'\x7F', b'\x2F', b'\xB3',
    b'\x13', b'\x77', b'\x8B', b'\xCF', b'\xC3', b'\x1E', b'\x77', b'\x90', b'\x6B',
    b'\x0C', b'\x96', b'\x2F', b'\x96', b'\x0F', b'\x3C', b'\xFE', b'\x3F', b'\x40',
    b'\xC1', b'\x99', b'\xAC', b'\x59', b'\x76', b'\x66', b'\xDB', b'\x01', b'\x1D',
    b'\xBD', b'\x8B', b'\x7F', b'\x77', b'\x62', b'\x8D', b'\x49', b'\x91', b'\xE8',
    b'\xC1', b'\xEC', b'\x8C', b'\xEE', b'\x8E', b'\xAA', b'\x1B', b'\xD1', b'\x5D',
    b'\xCA', b'\x47', b'\x15', b'\xF1', b'\x92', b'\xE2', b'\xE1', b'\x3F', b'\x15',
    b'\x1E', b'\xC4', b'\x0F', b'\x79', b'\xC4', b'\x50', b'\xA0', b'\xD9', b'\xEC',
    b'\x3A', b'\xF2', b'\x57', b'\x5E', b'\x6B', b'\x55', b'\x58', b'\xCC', b'\x7D',
    b'\xCD', b'\x0F', b'\xE2', b'\x83', b'\x67', b'\xCC', b'\xBE', b'\x64', b'\x73',
    b'\xDA', b'\x91', b'\xF6', b'\xEE', b'\xD0', b'\xF9', b'\xD4', b'\x9D', b'\x18',
    b'\xD3', b'\x75', b'\x05', b'\x9B', b'\x36', b'\xFD', b'\x4B', b'\x73', b'\xCA',
    b'\x4D', b'\xEB', b'\x78', b'\x39', b'\x47', b'\x26', b'\x1D', b'\x3B', b'\xD9',
    b'\x0D', b'\xAF', b'\x84', b'\x53', b'\x63', b'\xB9', b'\x93', b'\x91', b'\x25',
    b'\xDD', b'\xA0', b'\x36', b'\x71', b'\x16', b'\xFA', b'\x60', b'\x15', b'\x0C',
    b'\x00', b'\x8A', b'\x97', b'\xEA', b'\x58', b'\xF0', b'\x6D', b'\xA4', b'\xF7',
    b'\x63', b'\x25', b'\x18', b'\xD4', b'\x3C', b'\x36', b'\xE4', b'\xAF', b'\xCF',
    b'\xB3', b'\x52', b'\x2C', b'\x59', b'\xF8', b'\x2A', b'\x8E', b'\x44', b'\x8B',
    b'\x90', b'\x86', b'\x0D', b'\xFE', b'\xDC', b'\xF0', b'\x4F', b'\x73', b'\xCF',
    b'\xCB', b'\xAD', b'\x75', b'\x36', b'\xAC', b'\x5E', b'\x96', b'\x74', b'\x30',
    b'\x4C', b'\x74', b'\xA5', b'\xEC', b'\x8E', b'\xDB', b'\xA1', b'\x52', b'\xF0',
    b'\xBE', b'\x02', b'\xF7', b'\xE4', b'\xB1', b'\x18', b'\xDE', b'\xC9', b'\xB3',
    b'\x5C', b'\x2D', b'\x15', b'\xEB', b'\x12', b'\xE6', b'\x02', b'\x0C', b'\x15',
    b'\xCC', b'\x2C', b'\x88', b'\x85', b'\x5D', b'\xB6', b'\x6D', b'\xDD', b'\x63',
    b'\xF9', b'\xD3', b'\xF7', b'\x5C', b'\x2A', b'\xEA', b'\x18', b'\x1F', b'\xE6',
    b'\x0E', b'\xE5', b'\xB0', b'\xFE', b'\xF6', b'\x55', b'\x73', b'\x0B', b'\x35',
    b'\xAC', b'\xEB', b'\x89', b'\x66', b'\x9A', b'\x47', b'\x5E', b'\x5C', b'\x3E',
    b'\xC7', b'\x53', b'\xBA', b'\xE5', b'\xE6', b'\x35', b'\x1E', b'\xAA', b'\x06',
    b'\x42', b'\x69', b'\xC9', b'\xB8', b'\xE9', b'\x9C', b'\xD3', b'\xF1', b'\xB2',
    b'\xBA', b'\x17', b'\xF5', b'\x3D', b'\x3A', b'\x5C', b'\x70', b'\x89', b'\x27',
    b'\xFC', b'\xD3', b'\x80', b'\x2A', b'\x6A', b'\xB6', b'\x99', b'\x8E', b'\xE0',
    b'\x28', b'\x77', b'\x9E', b'\xF7', b'\x97', b'\x5F', b'\xC2', b'\x9B', b'\x53',
    b'\xD3', b'\xA7', b'\xE5', b'\xB7', b'\x1F', b'\x25', b'\x9C', b'\xAD', b'\x76',
    b'\x57', b'\xA4', b'\xEC', b'\x97', b'\x6A', b'\xA2', b'\x23', b'\xDE', b'\xBA',
    b'\x2C', b'\x60', b'\xDF', b'\xF1', b'\x9D', b'\xFC', b'\xCE', b'\x2D', b'\x4B',
    b'\x6A', b'\xD7', b'\x7C', b'\xB6', b'\x51', b'\x09', b'\xFC', b'\x94', b'\xBA',
    b'\xB8', b'\x24', b'\x99', b'\xEE', b'\x77', b'\x5F', b'\x9D', b'\x68', b'\x95',
    b'\x51', b'\x93', b'\xAF', b'\xF5', b'\x3C', b'\x3A', b'\x2F', b'\x79', b'\xF2',
    b'\xF7', b'\x46', b'\x6E', b'\xA8', b'\x44', b'\xC6', b'\x70', b'\x7D', b'\x3F',
    b'\x83', b'\xEC', b'\x90', b'\x00', b'\x9B', b'\xD1', b'\x97', b'\x56', b'\x6F',
    b'\x17', b'\xA1', b'\xE3', b'\x9B', b'\x32', b'\xE9', b'\x48', b'\x8F', b'\x47',
    b'\xB8', b'\x82', b'\xE8', b'\x59', b'\x7E', b'\xEE', b'\xDF', b'\x21', b'\x29',
    b'\x24', b'\xE9', b'\x61', b'\x8E', b'\x96', b'\x5D', b'\x1A', b'\xC0', b'\xCF',
    b'\xE8', b'\x9C', b'\x9A', b'\x7A', b'\xA7', b'\xF1', b'\x22', b'\x61', b'\xFC',
    b'\xCA', b'\x6A', b'\x43', b'\x59', b'\x3D', b'\x5A', b'\xAF', b'\x31', b'\x36',
    b'\xF4', b'\x92', b'\xF5', b'\xBB', b'\xA6', b'\xD5', b'\xE5', b'\xDC', b'\x82',
    b'\xDB', b'\x7E', b'\x00', b'\xD7', b'\xA0', b'\xBC', b'\xE0', b'\xA6', b'\x62',
    b'\x7C', b'\x74', b'\xD5', b'\x75', b'\x28', b'\xD5', b'\x54', b'\x72', b'\xB6',
    b'\x10', b'\x05', b'\x15', b'\x37', b'\x0E', b'\x0D', b'\x46', b'\x2D', b'\x21',
    b'\xC3', b'\x18', b'\xEA', b'\x25', b'\x4F', b'\x0F', b'\x7C', b'\xCE', b'\xF4',
    b'\xAF', b'\x64', b'\xC0', b'\x5C', b'\x28', b'\x5B', b'\x50', b'\x82', b'\x8C',
    b'\x14', b'\x4E', b'\x79', b'\x58', b'\x18', b'\x96', b'\x06', b'\x7F', b'\xD0',
    b'\x75', b'\x7D', b'\x6B', b'\xA6', b'\x67', b'\x80', b'\xD8', b'\xE5', b'\x04',
    b'\x9E', b'\x67', b'\x24', b'\xC3', b'\xCA', b'\x13', b'\x64', b'\xAA', b'\xE3',
    b'\x72', b'\x59', b'\x60', b'\xA9', b'\xCC', b'\x7E', b'\x45', b'\x79', b'\x4E',
    b'\x5E', b'\xF8', b'\xE6', b'\x4C', b'\xC1', b'\x95', b'\x7F', b'\x44', b'\x27',
    b'\xBF', b'\x08', b'\x97', b'\xE3', b'\x80', b'\x25', b'\x75', b'\xB0', b'\x9B',
    b'\x68', b'\x93', b'\x51', b'\x73', b'\xAF', b'\xD5', b'\x11', b'\xC3', b'\xEA',
    b'\xC7', b'\x4F', b'\xBA', b'\xCA', b'\x91', b'\x1E', b'\xFB', b'\x25', b'\x04',
    b'\x0C', b'\x54', b'\xE0', b'\x0B', b'\x05', b'\x90', b'\x1B', b'\x4B', b'\x01',
    b'\x1F', b'\x44', b'\xA9', b'\xEB', b'\x56', b'\x48', b'\x4A', b'\x4C', b'\x6E',
    b'\x34', b'\xB8', b'\x7A', b'\xCC', b'\xF0', b'\xAA', b'\x32', b'\x4B', b'\xFC',
    b'\x0F', b'\x57', b'\xEE', b'\xCC', b'\x8C', b'\x39', b'\x21', b'\xDF', b'\x08',
    b'\xB9', b'\x9E', b'\x21', b'\x8D', b'\x09', b'\x57', b'\xA3', b'\xD5', b'\xA5',
    b'\x68', b'\xF4', b'\xA3', b'\xBB', b'\x04', b'\x4E', b'\xEF', b'\x9A', b'\xCF',
    b'\x1E', b'\xFF', b'\xC2', b'\x2F', b'\xB6', b'\x5B', b'\x2C', b'\x8A', b'\x4B',
    b'\x07', b'\x7F', b'\xA8', b'\x85', b'\xA2', b'\x6A', b'\x2F', b'\x9F', b'\xE8',
    b'\xB8', b'\x52', b'\x3C', b'\x8D', b'\x12', b'\xBE', b'\xAA', b'\xE1', b'\xD4',
    b'\x44', b'\x06', b'\x97', b'\x1B', b'\xB9', b'\x29', b'\xEC', b'\x81', b'\x37',
    b'\x72', b'\x4D', b'\x3A', b'\x2D', b'\xA9', b'\x62', b'\x15', b'\x0D', b'\x2E',
    b'\x79', b'\x62', b'\x2E', b'\x7C', b'\x3C', b'\x73', b'\xC9', b'\x46', b'\x22',
    b'\x79', b'\xE7', b'\x5F', b'\x4B', b'\x04', b'\x1E', b'\x48', b'\x71', b'\xA6',
    b'\x07', b'\x45', b'\xD6', b'\xD0', b'\xCE', b'\x94', b'\xAC', b'\x42', b'\x2A',
    b'\x37', b'\x54', b'\xBD', b'\xAD', b'\x62', b'\xA4', b'\x9E', b'\x02', b'\xE7',
    b'\x69', b'\xB8', b'\x54', b'\xF1', b'\x06', b'\xAB', b'\x66', b'\x6C', b'\xF6',
    b'\x57', b'\xD6', b'\xD5', b'\x7E', b'\x07', b'\x8D', b'\x59', b'\xC4', b'\x9D',
    b'\x75', b'\x31', b'\x24', b'\x01', b'\x2F', b'\x9C', b'\x6E', b'\x90', b'\x99',
    b'\x42', b'\x66', b'\x7F', b'\x9E', b'\x9D', b'\xA6', b'\x2D', b'\x8F', b'\xE7',
    b'\x03', b'\x09', b'\x45', b'\xE5', b'\x6A', b'\x0E', b'\x0A', b'\x72', b'\x37',
    b'\x2A', b'\xFB', b'\xD2', b'\x7E', b'\x5B', b'\xEE', b'\xBF', b'\x98', b'\x93',
    b'\x99', b'\xEA', b'\x09', b'\xC7', b'\x76', b'\x21', b'\x8E', b'\x54', b'\x5F',
    b'\xC6', b'\x95', b'\x3C', b'\x27', b'\xB9', b'\xE6', b'\x2E', b'\x8B', b'\xFB',
    b'\xE3', b'\x8A', b'\x57', b'\x8C', b'\x12', b'\xFF', b'\x3F', b'\xB9', b'\xB1',
    b'\x15', b'\xDD', b'\x1B', b'\x5C', b'\x6A', b'\xB4', b'\x46', b'\x50', b'\xB8',
    b'\xA8', b'\xB6', b'\x75', b'\x00', b'\xE7', b'\xD1', b'\x00', b'\xDA', b'\xCE',
    b'\x93', b'\x76', b'\x23', b'\xAC', b'\x0F', b'\xB1', b'\x4A', b'\xF6', b'\x2F',
    b'\x32', b'\x9F', b'\xFE', b'\xDB', b'\xCE', b'\x77', b'\xE1', b'\xF0', b'\x88',
    b'\xA3', b'\x3C', b'\xDC', b'\x77', b'\xE4', b'\x7A', b'\x42', b'\x04', b'\x20',
    b'\x62', b'\xC4', b'\x6D', b'\x9F', b'\x1A', b'\xD9', b'\xDD', b'\x73', b'\x17',
    b'\x8D', b'\xE5', b'\x7F', b'\xFB', b'\x3E', b'\x1A', b'\x86', b'\x7B', b'\x6A',
    b'\x41', b'\x40', b'\x13', b'\x32', b'\xA1', b'\x40', b'\x32', b'\x20', b'\x2E',
    b'\x27', b'\x46', b'\x38', b'\x6C', b'\x1B', b'\xDE', b'\x2B', b'\x0A', b'\x50',
    b'\xC9', b'\xE3', b'\xB0', b'\x63', b'\x04', b'\x9F', b'\x31', b'\x35', b'\x18',
    b'\x1E', b'\x8E', b'\x57', b'\x40', b'\xB8', b'\x75', b'\x9A', b'\x91', b'\x62',
    b'\xE9', b'\x98', b'\xB1', b'\x71', b'\x5F', b'\xE4', b'\x82', b'\xC1', b'\x1E',
    b'\x8D', b'\x95', b'\x51', b'\xC1', b'\x95', b'\x31', b'\x94', b'\x84', b'\x71',
    b'\xBE', b'\x0F', b'\x80', b'\x86', b'\xDD', b'\x3E', b'\x40', b'\xBD', b'\xC8',
    b'\xD8', b'\x96', b'\x8B', b'\xE9', b'\x6F', b'\xBB', b'\x76', b'\xA1', b'\xCC',
    b'\xA1', b'\x68', b'\xBA', b'\xDC', b'\xC1', b'\x54', b'\x8B', b'\x13', b'\xAD',
    b'\xDA', b'\x70', b'\x6C', b'\xAB', b'\xC3', b'\x33', b'\x6C', b'\xF8', b'\x47',
    b'\x00', b'\xE9', b'\x73', b'\x8A', b'\x23', b'\xD2', b'\xCE', b'\xDB', b'\x6D',
    b'\x2A', b'\xCC', b'\xED', b'\xF1', b'\x58', b'\x53', b'\x8A', b'\x80', b'\x55',
    b'\x5E', b'\xCD', b'\x1B', b'\x3B', b'\x39', b'\xA6', b'\x53', b'\x98', b'\x75',
    b'\x49', b'\x89', b'\xDD', b'\x1E', b'\xAD', b'\xAE', b'\x5C', b'\xCC', b'\xD0',
    b'\xE3', b'\xE9', b'\x34', b'\xEB', b'\x4F', b'\xAB', b'\xEA', b'\xD6', b'\x9D',
    b'\x07', b'\xDC', b'\x38', b'\x4F', b'\xCA', b'\x1D', b'\x3C', b'\xBA', b'\x09',
    b'\xBC', b'\xE3', b'\x55', b'\xA7', b'\x6E', b'\x68', b'\x83', b'\x9C', b'\x6E',
    b'\x5E', b'\x82', b'\x65', b'\xEA', b'\x8E', b'\x02', b'\x8C', b'\xF2', b'\x9E',
    b'\x4E', b'\x14', b'\x4E', b'\x67', b'\x9A', b'\xE4', b'\x42', b'\xFB', b'\x7F',
    b'\xA6', b'\xBE', b'\x2D', b'\xE5', b'\x49', b'\xC3', b'\xAC', b'\x34', b'\x7B',
    b'\x64', b'\x7C', b'\x5B', b'\x58', b'\x07', b'\x94', b'\xF8', b'\x26', b'\xC5',
    b'\xF8', b'\x86', b'\x03', b'\x9D', b'\xB6', b'\xD1', b'\x6A', b'\x1C', b'\x4A',
    b'\xD1', b'\xCE', b'\x3F', b'\x72', b'\x78', b'\xE0', b'\x9A', b'\x24', b'\xF4',
    b'\x64', b'\xD9', b'\x27', b'\xE9', b'\x18', b'\x6F', b'\x40',
  ]
}

///|
fn av1_fg_params() -> Av1FilmGrainParams? {
  let stream = av1_fg_stream()
  let seq = match av1_sequence_info(stream) {
    None => return None
    Some(value) => value
  }
  let frames = av1_obu_payloads(stream, 6)
  if frames.length() == 0 {
    return None
  }
  match av1_parse_stage1_frame(frames[0], seq) {
    None => None
    Some(frame) => frame.film_grain
  }
}

///|
fn av1_fg_same_ints(actual : Array[Int], expected : Array[Int]) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut ok = true
    for i in 0..<expected.length() {
      if actual[i] != expected[i] {
        ok = false
      }
    }
    ok
  }
}

///|
/// The parameter values come from _refs/film_grain_sim.py, which parses the
/// same stream bit by bit and byte-aligns at the tile group. A wrong AR
/// coefficient count would still land on a byte boundary but desynchronise
/// the tile data, so this test guards the go-av1 coefficient arithmetic.
test "film grain header parses aomenc test vector 1" {
  let fg = av1_fg_params().unwrap()
  assert_eq(fg.apply_grain, true)
  assert_eq(fg.grain_seed, 51993)
  assert_eq(fg.num_y_points, 14)
  assert_eq(
    av1_fg_same_ints(fg.point_y_value, [
      16, 25, 33, 41, 48, 56, 67, 82, 97, 113, 128, 143, 158, 178,
    ]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_y_scaling, [
      0, 136, 144, 160, 168, 136, 128, 144, 152, 144, 176, 168, 176, 184,
    ]),
    true,
  )
  assert_eq(fg.chroma_scaling_from_luma, false)
  assert_eq(fg.num_cb_points, 8)
  assert_eq(fg.num_cr_points, 9)
  assert_eq(
    av1_fg_same_ints(fg.point_cb_value, [16, 20, 28, 60, 90, 105, 134, 168]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cb_scaling, [0, 64, 88, 104, 136, 160, 168, 208]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cr_value, [16, 28, 56, 66, 80, 108, 122, 137, 169]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.point_cr_scaling, [
      0, 96, 80, 96, 104, 96, 112, 112, 176,
    ]),
    true,
  )
  assert_eq(fg.grain_scaling_minus8, 3)
  assert_eq(fg.ar_coeff_lag, 2)
  // numPosLuma = 2 * lag * (lag + 1) = 12 for luma, plus the centre tap for
  // chroma because num_y_points > 0.
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_y, [
      128, 128, 70, 128, 128, 128, 52, 228, 85, 128, 77, 210,
    ]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_cb, [
      128, 128, 79, 128, 128, 128, 92, 150, 98, 128, 90, 135, 167,
    ]),
    true,
  )
  assert_eq(
    av1_fg_same_ints(fg.ar_coeffs_cr, [
      128, 128, 81, 128, 128, 128, 97, 159, 103, 128, 96, 141, 28,
    ]),
    true,
  )
  assert_eq(fg.ar_coeff_shift_minus6, 2)
  assert_eq(fg.grain_scale_shift, 0)
  assert_eq(fg.cb_mult, 247)
  assert_eq(fg.cb_luma_mult, 192)
  assert_eq(fg.cb_offset, 18)
  assert_eq(fg.cr_mult, 229)
  assert_eq(fg.cr_luma_mult, 192)
  assert_eq(fg.cr_offset, 54)
  assert_eq(fg.overlap_flag, false)
  assert_eq(fg.clip_to_restricted_range, true)
}

///|
/// End-to-end: the reduced-still frame decodes and the grain synthesis
/// reproduces dav1d 1.2.1 output for all 6144 samples. The grain-free decode
/// (dav1d --filmgrain 0) digests differently, so the pair cannot pass by
/// accident, and the first samples pin the plane order and offsets.
test "film grain synthesis matches dav1d pixel truth" {
  let frame = av1_decode_frame_planes(av1_fg_stream()).unwrap()
  let y = av1_frame_crop(frame, 0)
  let u = av1_frame_crop(frame, 1)
  let v = av1_frame_crop(frame, 2)
  assert_eq(y.length(), 4096)
  assert_eq(u.length(), 1024)
  assert_eq(v.length(), 1024)
  // dav1d with grain synthesis enabled.
  assert_eq(av1_fg_digest(y), 9177809)
  assert_eq(av1_fg_digest(u), 6447404)
  assert_eq(av1_fg_digest(v), 3641591)
  assert_eq(y[0], 19)
  assert_eq(y[1], 87)
  assert_eq(y[2], 168)
  assert_eq(y[3], 16)
  assert_eq(u[0], 129)
  assert_eq(u[1], 127)
  assert_eq(u[2], 127)
  assert_eq(u[3], 125)
  assert_eq(v[0], 164)
  assert_eq(v[1], 89)
  assert_eq(v[2], 240)
  assert_eq(v[3], 113)
}
