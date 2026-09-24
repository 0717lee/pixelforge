/// Regression coverage for the frame context carried between reference slots.
/// These tests adapt live motion/compound rows through the arithmetic decoder,
/// then verify that the next tile receives their probabilities and counters.

///|
/// Flatten live rows without copying them, so tests exercise each real context.
fn av1_cdf_roundtrip_live_rows3(
  groups : Array[Array[Array[Int]]],
) -> Array[Array[Int]] {
  let rows : Array[Array[Int]] = []
  for group in groups {
    for row in group {
      rows.push(row)
    }
  }
  rows
}

///|
/// The fifteen tool families previously omitted from frame snapshots.
fn av1_cdf_roundtrip_tool_rows(cdfs : Av1InterCdfs) -> Array[Array[Array[Int]]] {
  [
    cdfs.use_obmc,
    cdfs.motion_mode,
    cdfs.comp_mode,
    cdfs.comp_ref_type,
    cdfs.compound_mode,
    cdfs.compound_idx,
    cdfs.comp_group_idx,
    av1_cdf_roundtrip_live_rows3(cdfs.uni_comp_ref),
    av1_cdf_roundtrip_live_rows3(cdfs.comp_ref),
    av1_cdf_roundtrip_live_rows3(cdfs.comp_bwd_ref),
    cdfs.compound_type,
    cdfs.inter_intra,
    cdfs.inter_intra_mode,
    cdfs.wedge_inter_intra,
    cdfs.wedge_index,
  ]
}

///|
test "frame CDF roundtrip preserves every adapted inter tool context" {
  let live = av1_inter_cdfs()
  let rows = av1_cdf_roundtrip_tool_rows(live)
  let defaults = av1_cdf_roundtrip_tool_rows(av1_inter_cdfs())
  assert_eq(rows.length(), 15)
  for table in rows {
    for row in table {
      // An all-ones code selects the last symbol. A fresh decoder for each
      // row avoids depending on symbol padding after arbitrary-length reads.
      let decoder = av1_msac_new(Array::make(8, b'\xFF'), true)
      assert_eq(decoder.symbol(row), row.length() - 2)
      assert_eq(row[row.length() - 1], 1)
    }
  }
  assert_eq(live.use_obmc[0], [15360, 32768, 1])
  let snapshot = av1_frame_cdfs_default(49)
  let captured = av1_inter_cdfs_capture(live)
  assert_eq(captured.length(), 36)
  for i in 0..<captured.length() {
    snapshot.tables[av1_cdf_inter_base + i] = captured[i]
  }
  let restored = av1_inter_cdfs_of(Some(snapshot))
  let restored_rows = av1_cdf_roundtrip_tool_rows(restored)
  for table in 0..<rows.length() {
    assert_eq(restored_rows[table].length(), rows[table].length())
    for row in 0..<rows[table].length() {
      assert_eq(restored_rows[table][row], rows[table][row])
      assert_true(restored_rows[table][row] != defaults[table][row])
    }
  }
  // Saving a frame resets counts without resetting its adapted probabilities.
  av1_frame_cdfs_reset_counts(snapshot)
  let reset_rows = av1_cdf_roundtrip_tool_rows(
    av1_inter_cdfs_of(Some(snapshot)),
  )
  for table in 0..<rows.length() {
    for row in 0..<rows[table].length() {
      let expected = rows[table][row].copy()
      expected[expected.length() - 1] = 0
      assert_eq(reset_rows[table][row], expected)
    }
  }
  // A later tile must not mutate its reference's snapshot or another tile.
  restored.use_obmc[0][0] = 123
  live.use_obmc[0][0] = 456
  assert_eq(snapshot.tables[av1_cdf_inter_base + 21][0], [15360, 32768, 0])
  assert_eq(reset_rows[0][0], [15360, 32768, 0])
}

///|
test "inactive restoration retains the inherited frame CDFs" {
  let lr = av1_restoration_tile_state_new(3)
  let lr_rows = [lr.cdf_switchable, lr.cdf_wiener, lr.cdf_sgr]
  for row in lr_rows {
    let decoder = av1_msac_new(Array::make(8, b'\x00'), true)
    assert_eq(decoder.symbol(row), 0)
  }
  let intra = av1_intra_state(8, 8, 49, 8, false, false, false, false)
  let partition = av1_partition_cdf_state()
  let inherited = av1_frame_cdfs_capture(intra, partition, Some(lr))
  av1_frame_cdfs_reset_counts(inherited)
  let snapshot = av1_frame_cdfs_capture(
    intra,
    partition,
    None,
    inherited=Some(inherited),
  )
  let restored = av1_restoration_tile_state_new(3)
  av1_lr_cdfs_restore(restored, snapshot)
  // Adaptation after first symbol 0: probability + ((32768 - probability)
  // >> 4), then a frame boundary resets only the row's counter.
  assert_eq(restored.cdf_switchable, [10872, 23217, 32768, 0])
  assert_eq(restored.cdf_wiener, [12894, 32768, 0])
  assert_eq(restored.cdf_sgr, [17849, 32768, 0])
  inherited.tables[av1_cdf_lr_base][0][0] = 1
  restored.cdf_switchable[0] = 2
  assert_eq(snapshot.tables[av1_cdf_lr_base][0][0], 10872)
}

///|
test "active restoration replaces inherited selectors and absent inheritance uses defaults" {
  let inherited = av1_frame_cdfs_default(49)
  let lr = av1_restoration_tile_state_new(3)
  let decoder = av1_msac_new(Array::make(8, b'\xFF'), true)
  assert_eq(decoder.symbol(lr.cdf_wiener), 1)
  inherited.tables[av1_cdf_lr_base + 1][0][0] = 20000
  let active = av1_lr_cdfs_capture(Some(lr), inherited=Some(inherited))
  assert_eq(active[1][0], [10847, 32768, 1])
  let defaults = av1_lr_cdfs_capture(None)
  assert_eq(defaults[0][0], [9413, 22581, 32768, 0])
  assert_eq(defaults[1][0], [11570, 32768, 0])
  assert_eq(defaults[2][0], [16855, 32768, 0])
  lr.cdf_wiener[0] = 1
  assert_eq(active[1][0][0], 10847)
}

///|
test "default frame context includes all tools and this frame coefficient category" {
  let low = av1_frame_cdfs_default(0)
  let high = av1_frame_cdfs_default(200)
  assert_eq(low.tables.length(), 88)
  assert_eq(high.tables.length(), 88)
  assert_eq(low.tables[av1_cdf_inter_base + 21][0], [16384, 32768, 0])
  assert_eq(low.tables[av1_cdf_lr_base + 1][0], [11570, 32768, 0])
  // The txb_skip defaults depend on base_q_idx; frozen defaults must not be
  // reconstructed from the quantizer of some later loading frame.
  assert_true(
    low.tables[av1_cdf_partition_count + 15] !=
    high.tables[av1_cdf_partition_count + 15],
  )
}
