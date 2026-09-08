///|
fn pipeline_fixture() -> Image {
  let image = Image::new(1, 1)
  image.set_pixel(0, 0, b'\x14', b'\x32', b'\x64', b'\xFF')
  image
}

///|
test "pipeline applies operations in insertion order" {
  let pipeline = Pipeline::new().append(Invert).append(Brightness(10))
  let result = pipeline.apply(pipeline_fixture())
  let (r, g, b, a) = result.get_pixel(0, 0)
  // (20, 50, 100) -> invert -> (235, 205, 155) -> +10.
  assert_eq(r.to_int(), 245)
  assert_eq(g.to_int(), 215)
  assert_eq(b.to_int(), 165)
  assert_eq(a.to_int(), 255)
  assert_eq(pipeline.length(), 2)
}

///|
test "pipeline parameters match numeric dispatch" {
  let source = pipeline_fixture()
  let pipeline = Pipeline::new()
    .append(Threshold(90))
    .append(Pixelate(3))
    .append(Gamma(1.5))
  let via_pipeline = source.apply_pipeline(pipeline)
  let via_ids = source
    .apply_filter_id(10, 90.0)
    .apply_filter_id(11, 3.0)
    .apply_filter_id(17, 1.5)
  let (pr, pg, pb, pa) = via_pipeline.get_pixel(0, 0)
  let (ir, ig, ib, ia) = via_ids.get_pixel(0, 0)
  assert_eq(pr.to_int(), ir.to_int())
  assert_eq(pg.to_int(), ig.to_int())
  assert_eq(pb.to_int(), ib.to_int())
  assert_eq(pa.to_int(), ia.to_int())
}

///|
test "empty pipeline is a copy and does not mutate source" {
  let source = pipeline_fixture()
  let result = source.apply_pipeline(Pipeline::new())
  let (r, g, b, a) = result.get_pixel(0, 0)
  assert_eq(r.to_int(), 20)
  assert_eq(g.to_int(), 50)
  assert_eq(b.to_int(), 100)
  assert_eq(a.to_int(), 255)
  assert_eq(Pipeline::new().length(), 0)
  assert_true(Pipeline::new().is_empty())
  result.set_pixel(0, 0, b'\xFF', b'\x00', b'\x00', b'\xFF')
  assert_eq(source.get_pixel(0, 0).0.to_int(), 20)
}

///|
test "pipeline composition leaves both inputs reusable" {
  let left = Pipeline::from_filter(Invert)
  let right = Pipeline::from_filter(Brightness(5)).append(FlipHorizontal)
  let combined = left.then(right)
  assert_eq(left.length(), 1)
  assert_eq(right.length(), 2)
  assert_eq(combined.length(), 3)
  let source = pipeline_fixture()
  let expected = source
    .apply_filter_id(1, 0.0)
    .apply_filter_id(2, 5.0)
    .apply_filter_id(14, 0.0)
  let actual = combined.apply(source)
  let (ar, ag, ab, _) = actual.get_pixel(0, 0)
  let (er, eg, eb, _) = expected.get_pixel(0, 0)
  assert_eq(ar.to_int(), er.to_int())
  assert_eq(ag.to_int(), eg.to_int())
  assert_eq(ab.to_int(), eb.to_int())
}

///|
test "typed boundary values preserve dispatch defaults" {
  let source = pipeline_fixture()
  // Threshold, pixelate, posterize, gamma, vignette and canny all define
  // fallback behavior for non-positive amounts in the numeric dispatcher.
  let via_pipeline = Pipeline::new()
    .append(Threshold(0))
    .append(Pixelate(0))
    .append(Posterize(1))
    .append(Gamma(0.0))
    .append(Vignette(0.0))
    .append(Canny(0))
    .apply(source)
  let via_ids = source
    .apply_filter_id(10, 0.0)
    .apply_filter_id(11, 0.0)
    .apply_filter_id(16, 1.0)
    .apply_filter_id(17, 0.0)
    .apply_filter_id(18, 0.0)
    .apply_filter_id(20, 0.0)
  for i in 0..<4 {
    assert_eq(via_pipeline.data[i].to_int(), via_ids.data[i].to_int())
  }
}

///|
test "unknown numeric ids still pass through independently of pipelines" {
  let source = pipeline_fixture()
  let result = source.apply_filter_id(-1, 123.0)
  let (r, g, b, a) = result.get_pixel(0, 0)
  assert_eq(r.to_int(), 20)
  assert_eq(g.to_int(), 50)
  assert_eq(b.to_int(), 100)
  assert_eq(a.to_int(), 255)
}
