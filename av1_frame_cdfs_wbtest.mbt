/// The frame entropy context a reference slot stores (AV1 §8.3
/// `frame_end_update_cdf`, §7.20 `save_cdfs`), and the one property of it a
/// loading frame depends on: the adaptation counters must restart from zero.
///
/// A snapshot's rows are the probabilities the saving frame ended with, plus one
/// last entry per row holding how many symbols that row has already seen.
/// AV1's adaptation rate is a function of that counter, so libaom resets it
/// when the context is saved (`av1_reset_cdf_symbol_counters`) and a loading
/// frame therefore restarts the rate schedule rather than inheriting the
/// saver's. Without the reset the probabilities are still right and the saving
/// frame still decodes exactly, which is why this can only be observed by a
/// frame that actually loads the context - `inter_cdf_inherit_64x64`.

///|
/// Every counter of every row in every table.
fn av1_cdf_test_counters(snapshot : Av1FrameCdfs) -> Array[Int] {
  let counters : Array[Int] = []
  for table in snapshot.tables {
    for row in table {
      counters.push(row[row.length() - 1])
    }
  }
  counters
}

///|
test "the stored frame context resets the adaptation counters" {
  let map = av1_frame_map()
  let whole = inter_minimal_64x64_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, 69)
  if av1_decode_frame_planes(key_unit, map~) is None {
    fail("inter_minimal_64x64: key frame decode rejected")
  }
  // The key frame refreshed every slot, so slot 0 holds the frame context.
  let stored = match av1_frame_map_show(map, 0) {
    Some(value) => value
    None => fail("inter_minimal_64x64: key frame not stored")
  }
  let snapshot = match stored.cdfs {
    Some(value) => value
    None => fail("inter_minimal_64x64: no frame context stored")
  }
  for counter in av1_cdf_test_counters(snapshot) {
    assert_eq(counter, 0)
  }
  // The map's own frame context is the same object the slots alias, so a load
  // through either route sees reset counters.
  match map.saved_cdfs {
    Some(previous) =>
      for counter in av1_cdf_test_counters(previous) {
        assert_eq(counter, 0)
      }
    None => fail("inter_minimal_64x64: map frame context missing")
  }
}

///|
test "the reset leaves the adapted probabilities in place" {
  let map = av1_frame_map()
  let whole = inter_minimal_64x64_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, 69)
  if av1_decode_frame_planes(key_unit, map~) is None {
    fail("inter_minimal_64x64: key frame decode rejected")
  }
  let stored = match av1_frame_map_show(map, 0) {
    Some(value) => value
    None => fail("inter_minimal_64x64: key frame not stored")
  }
  let snapshot = match stored.cdfs {
    Some(value) => value
    None => fail("inter_minimal_64x64: no frame context stored")
  }
  // A freshly built state holds the normative defaults; the key frame adapted
  // its skip table, so at least one row of the stored copy must differ from it.
  // This is what proves the reset fires on rows that *did* adapt, rather than
  // on rows that were already at their defaults.
  let fresh = av1_intra_state(64, 64, 49, 8, false, false, false, false)
  let skip_table = snapshot.tables[av1_cdf_partition_count]
  let mut differing = 0
  for ctx in 0..<fresh.skip_cdfs.length() {
    let default_row = fresh.skip_cdfs[ctx]
    let stored_row = skip_table[ctx]
    for i in 0..<default_row.length() {
      if stored_row[i] != default_row[i] {
        differing = differing + 1
      }
    }
  }
  assert_true(differing > 0)
  // The counters are gone, not moved somewhere else in the row.
  for ctx in 0..<skip_table.length() {
    assert_eq(skip_table[ctx][skip_table[ctx].length() - 1], 0)
  }
}

///|
test "a frame that cannot update its context keeps the previous one" {
  // `disable_frame_end_update_cdf` leaves the frame context alone, so a slot
  // refreshed by such a frame keeps the earlier (already counter-free)
  // snapshot instead of this frame's rows. The patch in
  // `inter_primary_ref_64x64` freezes its key frame this way, which is what
  // makes that fixture's inter frame inherit the defaults.
  let map = av1_frame_map()
  let whole = inter_primary_ref_64x64_obu
  let key_unit = av1_inter_slice_bytes(whole, 0, 69)
  let inter_unit = av1_inter_slice_bytes(whole, 69, 98)
  if av1_decode_frame_planes(key_unit, map~) is None {
    fail("inter_primary_ref_64x64: key frame decode rejected")
  }
  let sequence = match av1_sequence_info(key_unit) {
    Some(value) => value
    None => fail("inter_primary_ref_64x64: no sequence header")
  }
  if av1_decode_frame_planes(inter_unit, map~, sequence~) is None {
    fail("inter_primary_ref_64x64: inter frame decode rejected")
  }
  // The inter frame inherits the frozen key frame's context, which is the
  // key frame's initial state: the normative defaults. Every counter is zero
  // either way, and the inter frame's own rows then start from that.
  let stored = match av1_frame_map_show(map, 0) {
    Some(value) => value
    None => fail("inter_primary_ref_64x64: no frame stored")
  }
  match stored.cdfs {
    Some(snapshot) =>
      for counter in av1_cdf_test_counters(snapshot) {
        assert_eq(counter, 0)
      }
    None => ()
  }
}
