/// Raw frame-level loop-restoration configuration from the uncompressed
/// header. Modes use the internal AV1 filter enum, not the two-bit header
/// codes: `00` selects None, `01` Switchable, `10` Wiener and `11` Sgrproj.
/// Monochrome configurations carry a single plane and no UV syntax. A missing
/// configuration means the frame omitted LR or declared all planes None; it
/// never downgrades a declared active filter.
///
/// Unit sizes are per-plane pixel sizes in the restored upscaled frame, not
/// MI counts. Luma derives from the superblock size with the header bits;
/// chroma planes may halve it once for 4:2:0. When every plane is None no
/// size bits occur and libaom implicitly assigns U256 to all planes.

///|
pub(all) enum Av1RestorationType {
  Av1RestorationNone
  Av1RestorationWiener
  Av1RestorationSgrproj
  Av1RestorationSwitchable
} derive(Eq, Debug)

///|
pub(all) struct Av1RestorationConfig {
  /// One entry per actual plane, in Y, U, V order.
  modes : Array[Av1RestorationType]
  /// Matching per-plane restoration unit size in pixels.
  unit_sizes : Array[Int]
}

///|
/// The unit-count rule from `av1_lr_count_units`: a trailing remainder smaller
/// than half a unit is absorbed by the last unit; the equality case creates
/// another one. Width 95 with U64 counts one unit, width 96 counts two. The
/// maximum with one handles planes smaller than half a unit.
fn av1_lr_count_units(unit_size : Int, plane_size : Int) -> Int {
  let count = (plane_size + (unit_size >> 1)) / unit_size
  if count > 1 {
    count
  } else {
    1
  }
}

///|
fn av1_restoration_config_valid(
  config : Av1RestorationConfig,
  monochrome? : Bool = false,
) -> Bool {
  let planes = if monochrome { 1 } else { 3 }
  if config.modes.length() != planes || config.unit_sizes.length() != planes {
    return false
  }
  for size in config.unit_sizes {
    if size != 32 && size != 64 && size != 128 && size != 256 {
      return false
    }
  }
  if monochrome {
    return true
  }
  // Both chroma planes share one unit size, either the luma size or its
  // single 4:2:0 halving; 4:4:4 would compare equality instead.
  if config.unit_sizes[1] != config.unit_sizes[2] {
    return false
  }
  config.unit_sizes[1] == config.unit_sizes[0] ||
  config.unit_sizes[1] * 2 == config.unit_sizes[0]
}

///|
/// True when any actual plane requests a filter. Unit sizes remain valid for
/// an all-None configuration; they are simply never applied.
pub fn av1_restoration_active(config : Av1RestorationConfig) -> Bool {
  for mode in config.modes {
    if mode is Av1RestorationNone {
      continue
    }
    return true
  }
  false
}

///|
/// Exact restoration grid for one frame, mirroring `av1_alloc_restoration_
/// struct`. Plane dimensions exclude coded MI padding: luma is the full
/// upscaled width and frame height, chroma rounds each up to its subsampled
/// size. `superres_denom` is retained for the tile pre-SB corner mapping.
pub(all) struct Av1RestorationLayout {
  config : Av1RestorationConfig
  frame_width : Int
  upscaled_width : Int
  frame_height : Int
  superres_denom : Int
  unit_cols : Array[Int]
  unit_rows : Array[Int]
}

///|
fn av1_restoration_layout(
  config : Av1RestorationConfig,
  frame_width : Int,
  upscaled_width : Int,
  frame_height : Int,
  monochrome : Bool,
  subsampling_x : Bool,
  subsampling_y : Bool,
  superres_denom : Int,
) -> Av1RestorationLayout? {
  if !av1_restoration_config_valid(config, monochrome~) ||
    frame_width <= 0 ||
    frame_width > 65536 ||
    upscaled_width < frame_width ||
    upscaled_width > 65536 ||
    frame_height <= 0 ||
    frame_height > 65536 ||
    (superres_denom != 8 && (superres_denom < 9 || superres_denom > 16)) {
    return None
  }
  let unit_cols : Array[Int] = []
  let unit_rows : Array[Int] = []
  for plane in 0..<config.modes.length() {
    let shift_x = if plane != 0 && subsampling_x { 1 } else { 0 }
    let shift_y = if plane != 0 && subsampling_y { 1 } else { 0 }
    let plane_width = (upscaled_width + (1 << shift_x) - 1) >> shift_x
    let plane_height = (frame_height + (1 << shift_y) - 1) >> shift_y
    let unit = config.unit_sizes[plane]
    unit_cols.push(av1_lr_count_units(unit, plane_width))
    unit_rows.push(av1_lr_count_units(unit, plane_height))
  }
  Some({
    config,
    frame_width,
    upscaled_width,
    frame_height,
    superres_denom,
    unit_cols,
    unit_rows,
  })
}
