///|
test "motion store clips nominal blocks to the coded plane without row spill" {
  let plane = Array::make(12 * 8, -1)
  let prediction = Array::makei(8 * 8, i => i)
  // Only the left four columns and first four rows intersect this plane.
  av1_motion_store(plane, 12, prediction, 8, 8, 8, 4, 255)
  for y in 0..<8 {
    for x in 0..<12 {
      let expected = if y >= 4 && x >= 8 { (y - 4) * 8 + x - 8 } else { -1 }
      assert_eq(plane[y * 12 + x], expected)
    }
  }
}

///|
test "motion store preserves native clipping and prediction offsets" {
  let plane = Array::make(8 * 8, -1)
  let prediction = Array::makei(12 * 12, i => {
    if i % 3 == 0 {
      -5
    } else {
      1000 + i
    }
  })
  av1_motion_store(plane, 8, prediction, 12, 12, -2, -1, 1023)
  for y in 0..<8 {
    for x in 0..<8 {
      let source = prediction[(y + 1) * 12 + x + 2]
      assert_eq(
        plane[y * 8 + x],
        if source < 0 {
          0
        } else if source > 1023 {
          1023
        } else {
          source
        },
      )
    }
  }
}
