///|
/// Shared 3x3 morphology kernel: per-channel neighborhood minimum (erode) or
/// maximum (dilate) with clamp-to-edge sampling. Alpha is preserved.
fn Image::morph3(self : Image, take_max : Bool) -> Image {
  let out = Image::new(self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let base = (y * self.width + x) * 4
      for c in 0..<3 {
        let mut best = if take_max { 0 } else { 255 }
        for dy in -1..<2 {
          for dx in -1..<2 {
            let sx = clamp_coord(x + dx, self.width)
            let sy = clamp_coord(y + dy, self.height)
            let v = self.data[(sy * self.width + sx) * 4 + c].to_int()
            if take_max {
              if v > best {
                best = v
              }
            } else if v < best {
              best = v
            }
          }
        }
        out.data[base + c] = clamp_byte(best)
      }
      out.data[base + 3] = self.data[base + 3]
    }
  }
  out
}

///|
/// Dilation: each channel takes the 3x3 neighborhood maximum, growing bright
/// regions by one pixel per application.
pub fn Image::dilate(self : Image) -> Image {
  self.morph3(true)
}

///|
/// Erosion: each channel takes the 3x3 neighborhood minimum, shrinking bright
/// regions by one pixel per application.
pub fn Image::erode(self : Image) -> Image {
  self.morph3(false)
}

///|
/// Morphological opening (erode then dilate): removes bright specks smaller
/// than the 3x3 element while roughly preserving larger shapes.
pub fn Image::morph_open(self : Image) -> Image {
  self.erode().dilate()
}

///|
/// Morphological closing (dilate then erode): fills dark pinholes smaller
/// than the 3x3 element while roughly preserving larger shapes.
pub fn Image::morph_close(self : Image) -> Image {
  self.dilate().erode()
}
