/// The frame entropy context AV1 snapshots per reference slot (AV1 §6.10
/// `disable_cdf_update`, §8.3 `frame_end_update_cdf`, §7.20 `save_cdfs`,
/// §5.9 tile adaptation, §9.3 `init_coeff_cdfs` / `init_non_coeff_cdfs`).
///
/// A snapshot is an ordered list of CDF tables, each table the row-major list
/// of q15 rows a symbol decoder adapts. Every tile starts its tables from the
/// frame context (the spec's `TileXxx` arrays are working copies of the frame
/// arrays), adapts them while symbols are decoded and, when
/// `disable_frame_end_update_cdf` is 0, the context_update_tile_id tile writes
/// its final rows back into the frame context the next frame inherits through
/// `primary_ref_frame`.
///
/// Table order (capture, restore and defaults keep this order):
///   0..5    partition trees w8, w16, w32, w64, w128
///   5..44   intra tile state: skip, y_mode, uv_cfl, uv_no_cfl, angle_delta,
///           cfl_sign, cfl_alpha, palette_y_mode, palette_uv_mode,
///           palette_y_size, palette_uv_size, palette_y_index, palette_uv_index,
///           filter_intra, filter_intra_mode_cdf, txb_skip, tx_set1, tx_set2,
///           luma eob, eob512, eob_small, extra, base_eob, base, br, sign,
///           chroma eob, eob512, eob_small, extra, base_eob, base, br, sign,
///           vartx, tx_depth 8/16/32/64
///   44..65  inter mode rows: single_ref, new_mv, zero_mv, ref_mv, drl_mode,
///           is_inter, skip_mode, interp_filter, y_mode, tx_type_set1, set2,
///           set3, mv_joint, mv_sign, mv_class, mv_class0_bit, mv_class0_fr,
///           mv_class0_hp, mv_bit, mv_fr, mv_hp
///   65..68  loop restoration selectors: switchable, wiener, sgr
///
/// Each table keeps the shape its default constructor produces, so a restored
/// snapshot is shape-identical to the defaults a tile would otherwise start
/// from and every row can be copied in place. An intra frame has no inter rows
/// to adapt; its snapshots still carry the inter defaults so a later inter
/// frame restoring the snapshot sees every table.

///|
/// Whether a frame inherits the entropy context stored in its primary
/// reference slot (AV1 §6.10 `load_cdfs`). The snapshot save in
/// `av1_frame_map_update` and the capture in `av1_decode_intra_tile_state`
/// always run, so the machinery is exercised end to end.
let av1_cdf_load_enabled : Bool = true

///|
pub(all) struct Av1FrameCdfs {
  tables : Array[Array[Array[Int]]]
}

///|
let av1_cdf_partition_count : Int = 5

///|
let av1_cdf_intra_count : Int = 39

///|
let av1_cdf_inter_count : Int = 21

///|
let av1_cdf_lr_count : Int = 3

///|
let av1_cdf_inter_base : Int = av1_cdf_partition_count + av1_cdf_intra_count

///|
let av1_cdf_lr_base : Int = av1_cdf_inter_base + av1_cdf_inter_count

///|
fn av1_cdf_rows_copy(rows : Array[Array[Int]]) -> Array[Array[Int]] {
  rows.map(fn(row) { row.copy() })
}

///|
/// Flatten one group of a 3-level live structure into rows.
fn av1_cdf_rows_of3(rows : Array[Array[Array[Int]]]) -> Array[Array[Int]] {
  let flat : Array[Array[Int]] = []
  for group in rows {
    for row in group {
      flat.push(row.copy())
    }
  }
  flat
}

///|
/// Flatten two groups of a 4-level live structure into rows.
fn av1_cdf_rows_of4(
  rows : Array[Array[Array[Array[Int]]]],
) -> Array[Array[Int]] {
  let flat : Array[Array[Int]] = []
  for outer in rows {
    for group in outer {
      for row in group {
        flat.push(row.copy())
      }
    }
  }
  flat
}

///|
/// Treat a single row as a one-row table.
fn av1_cdf_row_of(row : Array[Int]) -> Array[Array[Int]] {
  [row.copy()]
}

///|
/// Copy one row's contents in place. A shape mismatch cannot happen because
/// every table shape is fixed by its default constructor.
fn av1_cdf_row_into(dst : Array[Int], src : Array[Int]) -> Unit {
  if dst.length() != src.length() {
    return
  }
  for i in 0..<dst.length() {
    dst[i] = src[i]
  }
}

///|
/// Copy a table's row contents into a 2-level live structure.
fn av1_cdf_rows_into2(
  dst : Array[Array[Int]],
  table : Array[Array[Int]],
) -> Unit {
  if dst.length() != table.length() {
    return
  }
  for i in 0..<dst.length() {
    av1_cdf_row_into(dst[i], table[i])
  }
}

///|
/// Copy a table's row contents into a 3-level live structure.
fn av1_cdf_rows_into3(
  dst : Array[Array[Array[Int]]],
  table : Array[Array[Int]],
) -> Unit {
  let mut index = 0
  for group in dst {
    for row in group {
      if index >= table.length() {
        return
      }
      av1_cdf_row_into(row, table[index])
      index = index + 1
    }
  }
}

///|
/// Copy a table's row contents into a 4-level live structure.
fn av1_cdf_rows_into4(
  dst : Array[Array[Array[Array[Int]]]],
  table : Array[Array[Int]],
) -> Unit {
  let mut index = 0
  for outer in dst {
    for group in outer {
      for row in group {
        if index >= table.length() {
          return
        }
        av1_cdf_row_into(row, table[index])
        index = index + 1
      }
    }
  }
}

///|
/// Copy a one-row table into a single live row.
fn av1_cdf_row_into1(dst : Array[Int], table : Array[Array[Int]]) -> Unit {
  if table.length() != 1 {
    return
  }
  av1_cdf_row_into(dst, table[0])
}

///|
/// Deep copy a snapshot so a stored context is private to the reference slot.
fn av1_frame_cdfs_copy(snapshot : Av1FrameCdfs) -> Av1FrameCdfs {
  { tables: snapshot.tables.map(fn(table) { av1_cdf_rows_copy(table) }), }
}

///|
/// Zero the adaptation counter - the last entry of every row - in every table.
///
/// AV1's adaptation rate depends on how many symbols a row has already seen, so
/// a frame context that is saved for a later frame to load must restart that
/// schedule from zero: libaom's `av1_reset_cdf_symbol_counters` does exactly
/// this at `frame_end_update_cdf`, and the go-av1 port applies it in
/// `resetCounts` with the same reasoning. Without the reset, a loading frame
/// inherits the saving frame's counters, and from its very first adaptation the
/// two decoders move their rows at different rates.
fn av1_frame_cdfs_reset_counts(cdfs : Av1FrameCdfs) -> Unit {
  for table in cdfs.tables {
    for row in table {
      if row.length() > 0 {
        row[row.length() - 1] = 0
      }
    }
  }
}

///|
/// Append table groups into one ordered list.
fn av1_cdf_tables_concat(
  groups : Array[Array[Array[Array[Int]]]],
) -> Array[Array[Array[Int]]] {
  let tables : Array[Array[Array[Int]]] = []
  for group in groups {
    for table in group {
      tables.push(table)
    }
  }
  tables
}

///|
/// Partition trees: capture or restore the five superblock-size trees.
fn av1_partition_cdfs_capture(
  state : Av1PartitionCdfState,
) -> Array[Array[Array[Int]]] {
  [
    av1_cdf_rows_copy(state.w8),
    av1_cdf_rows_copy(state.w16),
    av1_cdf_rows_copy(state.w32),
    av1_cdf_rows_copy(state.w64),
    av1_cdf_rows_copy(state.w128),
  ]
}

///|
fn av1_partition_cdfs_restore(
  state : Av1PartitionCdfState,
  snapshot : Av1FrameCdfs,
) -> Unit {
  let tables = snapshot.tables
  if tables.length() < av1_cdf_partition_count {
    return
  }
  av1_cdf_rows_into2(state.w8, tables[0])
  av1_cdf_rows_into2(state.w16, tables[1])
  av1_cdf_rows_into2(state.w32, tables[2])
  av1_cdf_rows_into2(state.w64, tables[3])
  av1_cdf_rows_into2(state.w128, tables[4])
}

///|
/// A tile's partition trees: the snapshot's rows when one is inherited, the
/// normative defaults otherwise.
fn av1_partition_cdfs_of(snapshot : Av1FrameCdfs?) -> Av1PartitionCdfState {
  let state = av1_partition_cdf_state()
  match snapshot {
    Some(value) => av1_partition_cdfs_restore(state, value)
    None => ()
  }
  state
}

///|
/// The intra tile state tables, in the order the file header documents.
fn av1_intra_cdfs_capture(state : Av1IntraState) -> Array[Array[Array[Int]]] {
  let tables : Array[Array[Array[Int]]] = []
  tables.push(av1_cdf_rows_copy(state.skip_cdfs))
  tables.push(av1_cdf_rows_of3(state.y_mode))
  tables.push(av1_cdf_rows_copy(state.uv_cfl))
  tables.push(av1_cdf_rows_copy(state.uv_no_cfl))
  tables.push(av1_cdf_rows_copy(state.angle_delta))
  tables.push(av1_cdf_row_of(state.cfl.sign))
  tables.push(av1_cdf_rows_copy(state.cfl.alpha))
  tables.push(av1_cdf_rows_of3(state.palette.y_mode))
  tables.push(av1_cdf_rows_copy(state.palette.uv_mode))
  tables.push(av1_cdf_rows_copy(state.palette.y_size))
  tables.push(av1_cdf_rows_copy(state.palette.uv_size))
  tables.push(av1_cdf_rows_of3(state.palette.y_index))
  tables.push(av1_cdf_rows_of3(state.palette.uv_index))
  tables.push(av1_cdf_rows_copy(state.filter_intra))
  tables.push(av1_cdf_row_of(state.filter_intra_mode_cdf))
  tables.push(av1_cdf_rows_of3(state.tables.txb_skip))
  tables.push(av1_cdf_rows_of3(state.tables.tx_set1))
  tables.push(av1_cdf_rows_of3(state.tables.tx_set2))
  tables.push(av1_cdf_row_of(state.y_coeff.eob))
  tables.push(av1_cdf_row_of(state.y_coeff.eob512))
  tables.push(av1_cdf_rows_copy(state.y_coeff.eob_small))
  tables.push(av1_cdf_rows_of3(state.y_coeff.extra))
  tables.push(av1_cdf_rows_of3(state.y_coeff.base_eob))
  tables.push(av1_cdf_rows_of3(state.y_coeff.base))
  tables.push(av1_cdf_rows_of3(state.y_coeff.br))
  tables.push(av1_cdf_rows_copy(state.y_coeff.sign))
  tables.push(av1_cdf_row_of(state.uv_coeff.eob))
  tables.push(av1_cdf_row_of(state.uv_coeff.eob512))
  tables.push(av1_cdf_rows_copy(state.uv_coeff.eob_small))
  tables.push(av1_cdf_rows_of3(state.uv_coeff.extra))
  tables.push(av1_cdf_rows_of3(state.uv_coeff.base_eob))
  tables.push(av1_cdf_rows_of3(state.uv_coeff.base))
  tables.push(av1_cdf_rows_of3(state.uv_coeff.br))
  tables.push(av1_cdf_rows_copy(state.uv_coeff.sign))
  tables.push(av1_cdf_rows_copy(state.vartx.rows))
  tables.push(av1_cdf_rows_copy(state.tx_depth.cdf8))
  tables.push(av1_cdf_rows_copy(state.tx_depth.cdf16))
  tables.push(av1_cdf_rows_copy(state.tx_depth.cdf32))
  tables.push(av1_cdf_rows_copy(state.tx_depth.cdf64))
  tables
}

///|
fn av1_intra_cdfs_restore(
  state : Av1IntraState,
  snapshot : Av1FrameCdfs,
) -> Unit {
  let tables = snapshot.tables
  if tables.length() < av1_cdf_inter_base {
    return
  }
  let mut index = av1_cdf_partition_count
  av1_cdf_rows_into2(state.skip_cdfs, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.y_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.uv_cfl, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.uv_no_cfl, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.angle_delta, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.cfl.sign, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.cfl.alpha, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.palette.y_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.palette.uv_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.palette.y_size, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.palette.uv_size, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.palette.y_index, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.palette.uv_index, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.filter_intra, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.filter_intra_mode_cdf, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.tables.txb_skip, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.tables.tx_set1, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.tables.tx_set2, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.y_coeff.eob, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.y_coeff.eob512, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.y_coeff.eob_small, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.y_coeff.extra, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.y_coeff.base_eob, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.y_coeff.base, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.y_coeff.br, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.y_coeff.sign, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.uv_coeff.eob, tables[index])
  index = index + 1
  av1_cdf_row_into1(state.uv_coeff.eob512, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.uv_coeff.eob_small, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.uv_coeff.extra, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.uv_coeff.base_eob, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.uv_coeff.base, tables[index])
  index = index + 1
  av1_cdf_rows_into3(state.uv_coeff.br, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.uv_coeff.sign, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.vartx.rows, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.tx_depth.cdf8, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.tx_depth.cdf16, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.tx_depth.cdf32, tables[index])
  index = index + 1
  av1_cdf_rows_into2(state.tx_depth.cdf64, tables[index])
}

///|
/// Seed a freshly built intra tile state from the inherited frame context.
fn av1_intra_cdfs_of(state : Av1IntraState, snapshot : Av1FrameCdfs?) -> Unit {
  match snapshot {
    Some(value) => av1_intra_cdfs_restore(state, value)
    None => ()
  }
}

///|
/// The inter mode rows, in the order the file header documents. An intra
/// frame contributes the defaults so an inter frame restoring the snapshot
/// still sees every table.
fn av1_inter_cdfs_capture(cdfs : Av1InterCdfs) -> Array[Array[Array[Int]]] {
  [
    av1_cdf_rows_of3(cdfs.single_ref),
    av1_cdf_rows_copy(cdfs.new_mv),
    av1_cdf_rows_copy(cdfs.zero_mv),
    av1_cdf_rows_copy(cdfs.ref_mv),
    av1_cdf_rows_copy(cdfs.drl_mode),
    av1_cdf_rows_copy(cdfs.is_inter),
    av1_cdf_rows_copy(cdfs.skip_mode),
    av1_cdf_rows_copy(cdfs.interp_filter),
    av1_cdf_rows_copy(cdfs.y_mode),
    av1_cdf_rows_copy(cdfs.inter_tx_type_set1),
    av1_cdf_row_of(cdfs.inter_tx_type_set2),
    av1_cdf_rows_copy(cdfs.inter_tx_type_set3),
    av1_cdf_rows_copy(cdfs.mv_joint),
    av1_cdf_rows_of3(cdfs.mv_sign),
    av1_cdf_rows_of3(cdfs.mv_class),
    av1_cdf_rows_of3(cdfs.mv_class0_bit),
    av1_cdf_rows_of4(cdfs.mv_class0_fr),
    av1_cdf_rows_of3(cdfs.mv_class0_hp),
    av1_cdf_rows_of4(cdfs.mv_bit),
    av1_cdf_rows_of3(cdfs.mv_fr),
    av1_cdf_rows_of3(cdfs.mv_hp),
  ]
}

///|
fn av1_inter_cdfs_restore(
  cdfs : Av1InterCdfs,
  snapshot : Av1FrameCdfs,
) -> Av1InterCdfs {
  let tables = snapshot.tables
  if tables.length() < av1_cdf_lr_base {
    return cdfs
  }
  let mut index = av1_cdf_inter_base
  av1_cdf_rows_into3(cdfs.single_ref, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.new_mv, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.zero_mv, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.ref_mv, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.drl_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.is_inter, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.skip_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.interp_filter, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.y_mode, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.inter_tx_type_set1, tables[index])
  index = index + 1
  av1_cdf_row_into1(cdfs.inter_tx_type_set2, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.inter_tx_type_set3, tables[index])
  index = index + 1
  av1_cdf_rows_into2(cdfs.mv_joint, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_sign, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_class, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_class0_bit, tables[index])
  index = index + 1
  av1_cdf_rows_into4(cdfs.mv_class0_fr, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_class0_hp, tables[index])
  index = index + 1
  av1_cdf_rows_into4(cdfs.mv_bit, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_fr, tables[index])
  index = index + 1
  av1_cdf_rows_into3(cdfs.mv_hp, tables[index])
  cdfs
}

///|
/// A tile's inter rows: the snapshot's rows when one is inherited, the
/// normative defaults otherwise.
fn av1_inter_cdfs_of(snapshot : Av1FrameCdfs?) -> Av1InterCdfs {
  let cdfs = av1_inter_cdfs()
  match snapshot {
    Some(value) => av1_inter_cdfs_restore(cdfs, value)
    None => cdfs
  }
}

///|
/// The loop-restoration selector rows. Their normative defaults come from the
/// same tables a tile state would start from.
fn av1_lr_cdfs_capture(
  state : Av1RestorationTileState?,
) -> Array[Array[Array[Int]]] {
  match state {
    Some(value) =>
      [
        av1_cdf_row_of(value.cdf_switchable),
        av1_cdf_row_of(value.cdf_wiener),
        av1_cdf_row_of(value.cdf_sgr),
      ]
    None => av1_lr_cdfs_capture(Some(av1_restoration_tile_state_new(1)))
  }
}

///|
fn av1_lr_cdfs_restore(
  state : Av1RestorationTileState,
  snapshot : Av1FrameCdfs,
) -> Unit {
  let tables = snapshot.tables
  if tables.length() < av1_cdf_lr_base + av1_cdf_lr_count {
    return
  }
  av1_cdf_row_into1(state.cdf_switchable, tables[av1_cdf_lr_base])
  av1_cdf_row_into1(state.cdf_wiener, tables[av1_cdf_lr_base + 1])
  av1_cdf_row_into1(state.cdf_sgr, tables[av1_cdf_lr_base + 2])
}

///|
/// Capture the whole frame context from one decoded tile's live state. The
/// tile is the `context_update_tile_id` one, tile 0 by default: its final rows
/// become the frame context the next frame may inherit.
fn av1_frame_cdfs_capture(
  state : Av1IntraState,
  partition : Av1PartitionCdfState,
  lr : Av1RestorationTileState?,
) -> Av1FrameCdfs {
  let inter = match state.inter {
    Some(info) => info.cdfs
    None => av1_inter_cdfs()
  }
  {
    tables: av1_cdf_tables_concat([
      av1_partition_cdfs_capture(partition),
      av1_intra_cdfs_capture(state),
      av1_inter_cdfs_capture(inter),
      av1_lr_cdfs_capture(lr),
    ]),
  }
}
