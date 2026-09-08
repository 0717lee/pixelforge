///|
/// A filter operation that can be composed into a [`Pipeline`].
///
/// Each constructor corresponds to one of the stable `apply_filter_id`
/// operations. Keeping the operation as an enum means callers cannot create a
/// pipeline with an unknown filter id, while the existing numeric API remains
/// available for host bindings.
pub(all) enum Filter {
  Grayscale
  Invert
  Brightness(Int)
  Contrast(Double)
  Blur
  Sharpen
  Emboss
  Edges
  Sobel
  Sepia
  Threshold(Int)
  Pixelate(Int)
  Median
  HistogramEqualize
  FlipHorizontal
  FlipVertical
  Posterize(Int)
  Gamma(Double)
  Vignette(Double)
  Scharr
  Canny(Int)
  Otsu
  DitherMono
}

///|
/// Converts a typed operation to the shared host dispatch representation.
/// Parameter defaults intentionally stay in `Image::apply_filter_id`, so a
/// pipeline and a direct host call have exactly the same boundary semantics.
fn Filter::dispatch(self : Filter) -> (Int, Double) {
  match self {
    Grayscale => (0, 0.0)
    Invert => (1, 0.0)
    Brightness(delta) => (2, delta.to_double())
    Contrast(factor) => (3, factor)
    Blur => (4, 0.0)
    Sharpen => (5, 0.0)
    Emboss => (6, 0.0)
    Edges => (7, 0.0)
    Sobel => (8, 0.0)
    Sepia => (9, 0.0)
    Threshold(level) => (10, level.to_double())
    Pixelate(block) => (11, block.to_double())
    Median => (12, 0.0)
    HistogramEqualize => (13, 0.0)
    FlipHorizontal => (14, 0.0)
    FlipVertical => (15, 0.0)
    Posterize(levels) => (16, levels.to_double())
    Gamma(value) => (17, value)
    Vignette(strength) => (18, strength)
    Scharr => (19, 0.0)
    Canny(high) => (20, high.to_double())
    Otsu => (21, 0.0)
    DitherMono => (22, 0.0)
  }
}

///|
/// An ordered, reusable sequence of image filters.
///
/// `append` and `then` return a new pipeline and leave their receiver's
/// operation list untouched. `apply` also leaves the source image unchanged,
/// matching the copy-on-write behavior of individual filters.
pub struct Pipeline {
  operations : Array[Filter]
}

///|
/// Creates an empty pipeline. Applying it returns a deep copy of the input.
pub fn Pipeline::new() -> Pipeline {
  { operations: [], }
}

///|
/// Creates a pipeline containing one operation.
pub fn Pipeline::from_filter(filter : Filter) -> Pipeline {
  { operations: [filter], }
}

///|
/// Returns a new pipeline with `filter` appended at the end.
pub fn Pipeline::append(self : Pipeline, filter : Filter) -> Pipeline {
  let next = self.operations.copy()
  next.push(filter)
  { operations: next, }
}

///|
/// Returns a new pipeline that applies `self`, then `other`.
pub fn Pipeline::then(self : Pipeline, other : Pipeline) -> Pipeline {
  let next = self.operations.copy()
  for filter in other.operations {
    next.push(filter)
  }
  { operations: next, }
}

///|
/// Number of operations in this pipeline.
pub fn Pipeline::length(self : Pipeline) -> Int {
  self.operations.length()
}

///|
/// Whether this pipeline contains no operations.
pub fn Pipeline::is_empty(self : Pipeline) -> Bool {
  self.operations.length() == 0
}

///|
/// Applies each operation in insertion order.
pub fn Pipeline::apply(self : Pipeline, image : Image) -> Image {
  if self.operations.length() == 0 {
    return image.copy()
  }
  let mut out = image
  for filter in self.operations {
    let (filter_id, amount) = filter.dispatch()
    out = out.apply_filter_id(filter_id, amount)
  }
  out
}

///|
/// Applies a typed filter pipeline to an image.
pub fn Image::apply_pipeline(self : Image, pipeline : Pipeline) -> Image {
  pipeline.apply(self)
}
