///|
/// Public histogram API. The luma histogram reuses the same 256-bin
/// BT.601 integer binning that Otsu and histogram equalization are built
/// on, so every consumer of the library sees one consistent definition.

///|
/// 256-bin luma histogram (BT.601 integer weights): `result[v]` counts the
/// pixels whose luma is exactly `v`.
pub fn Image::histogram_luma(self : Image) -> FixedArray[Int] {
  self.luma_histogram()
}

///|
/// Per-channel 256-bin histograms, returned as `(red, green, blue)`.
pub fn Image::histogram_rgb(
  self : Image,
) -> (FixedArray[Int], FixedArray[Int], FixedArray[Int]) {
  let hr = FixedArray::make(256, 0)
  let hg = FixedArray::make(256, 0)
  let hb = FixedArray::make(256, 0)
  let n = self.pixel_count()
  for p in 0..<n {
    let base = p * 4
    let r = self.data[base].to_int()
    let g = self.data[base + 1].to_int()
    let b = self.data[base + 2].to_int()
    hr[r] = hr[r] + 1
    hg[g] = hg[g] + 1
    hb[b] = hb[b] + 1
  }
  (hr, hg, hb)
}
