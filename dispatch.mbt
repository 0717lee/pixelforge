///|
/// Applies a filter selected by a numeric id. This single dispatch table is
/// shared by every host binding — the js browser binding, the linear-memory
/// wasm binding, and the native CLI — so they can never drift apart.
///
/// | id | filter | `amount` |
/// |----|--------|----------|
/// | 0 | grayscale | — |
/// | 1 | invert | — |
/// | 2 | brightness | delta (−255..255) |
/// | 3 | contrast | factor (0.0..3.0) |
/// | 4 | gaussian blur | — |
/// | 5 | sharpen | — |
/// | 6 | emboss | — |
/// | 7 | laplacian edges | — |
/// | 8 | sobel edges | — |
/// | 9 | sepia | — |
/// | 10 | threshold | level (default 128) |
/// | 11 | pixelate | block size (default 8) |
/// | 12 | median denoise | — |
/// | 13 | histogram equalize | — |
/// | 14 | flip horizontal | — |
/// | 15 | flip vertical | — |
/// | 16 | posterize | levels (default 4) |
/// | 17 | gamma | gamma value (default 2.2) |
/// | 18 | vignette | strength 0..1 (default 0.5) |
/// | 19 | scharr edges | — |
/// | 20 | canny edges | high threshold (default 100, low = high/2) |
pub fn Image::apply_filter_id(
  self : Image,
  filter_id : Int,
  amount : Double,
) -> Image {
  match filter_id {
    0 => self.grayscale()
    1 => self.invert()
    2 => self.brightness(amount.to_int())
    3 => self.contrast(amount)
    4 => self.blur()
    5 => self.sharpen()
    6 => self.emboss()
    7 => self.edges()
    8 => self.sobel()
    9 => self.sepia()
    10 =>
      self.threshold(if amount.to_int() <= 0 { 128 } else { amount.to_int() })
    11 => self.pixelate(if amount.to_int() < 2 { 8 } else { amount.to_int() })
    12 => self.median()
    13 => self.histogram_equalize()
    14 => self.flip_horizontal()
    15 => self.flip_vertical()
    16 => self.posterize(if amount.to_int() < 2 { 4 } else { amount.to_int() })
    17 => self.gamma(if amount <= 0.0 { 2.2 } else { amount })
    18 => self.vignette(if amount <= 0.0 { 0.5 } else { amount })
    19 => self.scharr()
    20 => {
      let high = if amount.to_int() <= 0 { 100 } else { amount.to_int() }
      self.canny(high / 2, high)
    }
    _ => self.copy()
  }
}
