/// AV1 loop-restoration unit syntax reader.
///
/// Unit parameters are read on the shared tile entropy decoder exactly
/// once per root superblock, before that SB's first partition symbol
/// (AV1 spec §5.11.57; libaom decodeframe.c:1305-1346). The three mode
/// CDF rows, the per-plane coefficient references and the unit records
/// are per-tile state that resets at tile boundaries
/// (libaom decodeframe.c:2784-2786). Wiener coefficients are coded with
/// signed reference-recentered subexponential symbols; SGR carries an
/// equiprobable four-bit parameter version plus two projections. The
/// chroma five-tap case infers tap 0 on both axes and reads no bits.
///
/// Entropy ownership uses the unshifted global unit grid from
/// `Av1RestorationLayout`; the superres corner mapping preserves the
/// rational denominator-8 form until the final ceiling division.

///|
/// One decoded restoration unit. Wiener keeps the three coded taps per
/// axis in read order (vertical first, then horizontal); SGR keeps the
/// parameter version `ep` and the two coded projections.
pub(all) enum Av1RestorationUnit {
  Av1RestorationUnitNone
  Av1RestorationUnitWiener(Array[Int], Array[Int])
  Av1RestorationUnitSgrproj(Int, Array[Int])
}

///|
/// One unit's decoded parameters with its global grid identity. Records
/// are collected per tile and assembled into a frame unit map that must
/// distinguish decoded-None units from unread positions.
pub(all) struct Av1RestorationUnitRecord {
  plane : Int
  unit_row : Int
  unit_col : Int
  unit : Av1RestorationUnit
}

///|
/// Per-tile loop-restoration entropy state. The three CDF rows are
/// shared across planes (AV1 spec §5.11.57); coefficient references are
/// separate per plane and filter family and survive superblock rows.
pub(all) struct Av1RestorationTileState {
  cdf_switchable : Array[Int]
  cdf_wiener : Array[Int]
  cdf_sgr : Array[Int]
  // [plane][axis][tap], axis 0 vertical and 1 horizontal.
  ref_wiener : Array[Array[Array[Int]]]
  // [plane][projection].
  ref_sgr : Array[Array[Int]]
  units : Array[Av1RestorationUnitRecord]
}
///|
/// Wiener tap alphabet and reference table (libaom restoration.h:94-112).
/// Ranges are inclusive; k is the subexponential width.
fn av1_wiener_tap_min(tap : Int) -> Int {
  if tap == 0 {
    -5
  } else if tap == 1 {
    -23
  } else {
    -17
  }
}

///|
fn av1_wiener_tap_max(tap : Int) -> Int {
  if tap == 0 {
    10
  } else if tap == 1 {
    8
  } else {
    46
  }
}

///|
fn av1_wiener_tap_k(tap : Int) -> Int {
  if tap == 0 {
    1
  } else if tap == 1 {
    2
  } else {
    3
  }
}

///|
/// Initial Wiener reference taps (libaom restoration.h:124-132).
fn av1_wiener_tap_mid(tap : Int) -> Int {
  if tap == 0 {
    3
  } else if tap == 1 {
    -7
  } else {
    15
  }
}

///|
/// SGR projection ranges (libaom restoration.h:124-132): xqd0 spans
/// [-96,32), xqd1 spans [-32,96), references -32 and 31.
fn av1_sgr_xqd_low(index : Int) -> Int {
  if index == 0 {
    -96
  } else {
    -32
  }
}

///|
fn av1_sgr_xqd_high(index : Int) -> Int {
  if index == 0 {
    32
  } else {
    96
  }
}

///|
fn av1_sgr_xqd_mid(index : Int) -> Int {
  if index == 0 {
    -32
  } else {
    31
  }
}

///|
fn av1_clip_int(low : Int, value : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// SGR parameter-version radii: ep 0..9 use (2,1), 10..13 use (0,1)
/// and 14..15 use (2,0) (libaom restoration.c:584-595).
fn av1_sgr_radii(ep : Int) -> (Int, Int) {
  if ep < 10 {
    (2, 1)
  } else if ep < 14 {
    (0, 1)
  } else {
    (2, 0)
  }
}

///|
/// Fresh per-tile state: default forward-cumulative CDF rows and
/// coefficient references (AV1 spec §5.11.57; libaom entropymode.c).
fn av1_restoration_tile_state_new(num_planes : Int) -> Av1RestorationTileState {
  let ref_wiener : Array[Array[Array[Int]]] = []
  let ref_sgr : Array[Array[Int]] = []
  for _ in 0..<num_planes {
    let axes : Array[Array[Int]] = []
    for _ in 0..<2 {
      let taps : Array[Int] = []
      for tap in 0..<3 {
        taps.push(av1_wiener_tap_mid(tap))
      }
      axes.push(taps)
    }
    ref_wiener.push(axes)
    let sgr : Array[Int] = [av1_sgr_xqd_mid(0), av1_sgr_xqd_mid(1)]
    ref_sgr.push(sgr)
  }
  {
    cdf_switchable: [9413, 22581, 32768, 0],
    cdf_wiener: [11570, 32768, 0],
    cdf_sgr: [16855, 32768, 0],
    ref_wiener,
    ref_sgr,
    units: [],
  }
}

///|
/// Read one Wiener unit: vertical axis first, then horizontal, each in
/// tap 0..2 order. Chroma planes infer tap 0 on both axes as zero and
/// read no bits for it (libaom decodeframe.c:1605-1662). Every decoded
/// tap immediately replaces that plane's running reference.
fn av1_restoration_read_wiener(
  decoder : Av1SymbolDecoder,
  tile_state : Av1RestorationTileState,
  plane : Int,
) -> Av1RestorationUnit {
  let vertical : Array[Int] = []
  let horizontal : Array[Int] = []
  for axis in 0..<2 {
    for tap in 0..<3 {
      let value = if plane != 0 && tap == 0 {
        0
      } else {
        decoder.entropy_signed_refsubexp(
          av1_wiener_tap_min(tap),
          av1_wiener_tap_max(tap) + 1,
          av1_wiener_tap_k(tap),
          tile_state.ref_wiener[plane][axis][tap],
        )
      }
      tile_state.ref_wiener[plane][axis][tap] = value
      if axis == 0 {
        vertical.push(value)
      } else {
        horizontal.push(value)
      }
    }
  }
  Av1RestorationUnitWiener(vertical, horizontal)
}

///|
/// Read one SGR unit: an equiprobable four-bit parameter version, then
/// the two projections. A zero radius on either side removes that
/// projection from the bitstream and fixes its coded value; the other
/// side is derived without entropy (libaom decodeframe.c:1664-1700).
fn av1_restoration_read_sgr(
  decoder : Av1SymbolDecoder,
  tile_state : Av1RestorationTileState,
  plane : Int,
) -> Av1RestorationUnit {
  let ep = decoder.entropy_literal(4)
  let (r0, r1) = av1_sgr_radii(ep)
  let xqd : Array[Int] = [0, 0]
  if r0 == 0 {
    xqd[1] = decoder.entropy_signed_refsubexp(
      av1_sgr_xqd_low(1),
      av1_sgr_xqd_high(1),
      4,
      tile_state.ref_sgr[plane][1],
    )
  } else if r1 == 0 {
    xqd[0] = decoder.entropy_signed_refsubexp(
      av1_sgr_xqd_low(0),
      av1_sgr_xqd_high(0),
      4,
      tile_state.ref_sgr[plane][0],
    )
    xqd[1] = av1_clip_int(av1_sgr_xqd_low(1), 128 - xqd[0], av1_sgr_xqd_high(1) - 1)
  } else {
    xqd[0] = decoder.entropy_signed_refsubexp(
      av1_sgr_xqd_low(0),
      av1_sgr_xqd_high(0),
      4,
      tile_state.ref_sgr[plane][0],
    )
    xqd[1] = decoder.entropy_signed_refsubexp(
      av1_sgr_xqd_low(1),
      av1_sgr_xqd_high(1),
      4,
      tile_state.ref_sgr[plane][1],
    )
  }
  tile_state.ref_sgr[plane][0] = xqd[0]
  tile_state.ref_sgr[plane][1] = xqd[1]
  Av1RestorationUnitSgrproj(ep, xqd)
}

///|
/// Read one unit's mode symbol from the frame-mode CDF row and its
/// filter coefficients. Mode None reads no coefficients and changes no
/// reference. Returns the decoded unit; the caller appends the record.
fn av1_restoration_read_unit(
  decoder : Av1SymbolDecoder,
  tile_state : Av1RestorationTileState,
  plane : Int,
  frame_mode : Av1RestorationType,
) -> Av1RestorationUnit {
  match frame_mode {
    Av1RestorationWiener => {
      let selected = decoder.symbol(tile_state.cdf_wiener)
      if selected == 0 {
        Av1RestorationUnitNone
      } else {
        av1_restoration_read_wiener(decoder, tile_state, plane)
      }
    }
    Av1RestorationSgrproj => {
      let selected = decoder.symbol(tile_state.cdf_sgr)
      if selected == 0 {
        Av1RestorationUnitNone
      } else {
        av1_restoration_read_sgr(decoder, tile_state, plane)
      }
    }
    Av1RestorationSwitchable => {
      match decoder.symbol(tile_state.cdf_switchable) {
        0 => Av1RestorationUnitNone
        1 => av1_restoration_read_wiener(decoder, tile_state, plane)
        _ => av1_restoration_read_sgr(decoder, tile_state, plane)
      }
    }
    Av1RestorationNone => Av1RestorationUnitNone
  }
}

///|
/// Global unit-grid rectangle overlapped by one root superblock, per
/// plane. The root MI rectangle is `[mc0,mc1) x [mr0,mr1)` including its
/// full nominal superblock size at the frame edge; superres preserves
/// the rational `D/8` ratio as `num/den` until the final ceiling
/// division (libaom decodeframe.c:1702-1744). Only the end bounds are
/// clamped to the unit counts; an empty interval consumes nothing.
fn av1_restoration_sb_unit_range(
  layout : Av1RestorationLayout,
  plane : Int,
  mc0 : Int,
  mc1 : Int,
  mr0 : Int,
  mr1 : Int,
  subsampling_x : Bool,
  subsampling_y : Bool,
) -> (Int, Int, Int, Int) {
  let shift_x = if plane != 0 && subsampling_x { 1 } else { 0 }
  let shift_y = if plane != 0 && subsampling_y { 1 } else { 0 }
  let mx = 4 >> shift_x
  let my = 4 >> shift_y
  let unit = layout.config.unit_sizes[plane]
  let (num_x, den_x) = if layout.superres_denom != 8 {
    (mx * layout.superres_denom, unit * 8)
  } else {
    (mx, unit)
  }
  let c0 = (mc0 * num_x + den_x - 1) / den_x
  let c1 = {
    let raw = (mc1 * num_x + den_x - 1) / den_x
    if raw < layout.unit_cols[plane] { raw } else { layout.unit_cols[plane] }
  }
  let r0 = (mr0 * my + unit - 1) / unit
  let r1 = {
    let raw = (mr1 * my + unit - 1) / unit
    if raw < layout.unit_rows[plane] { raw } else { layout.unit_rows[plane] }
  }
  (c0, c1, r0, r1)
}

///|
/// Read the loop-restoration units whose nominal top-left corners fall
/// inside one root superblock, in plane then unit-row then unit-column
/// order. `mc0`/`mr0` are the SB's global coded MI coordinates. An SB
/// may contain zero, one or several unit origins per plane. Returns
/// false on entropy overrun at the unit boundary; the MSAC budget rule
/// mirrors the tile leaf check (`symbol_max_bits >= -14`).
fn av1_restoration_read_sb(
  decoder : Av1SymbolDecoder,
  tile_state : Av1RestorationTileState,
  layout : Av1RestorationLayout,
  mc0 : Int,
  mr0 : Int,
  sb_size : Int,
  subsampling_x? : Bool = false,
  subsampling_y? : Bool = false,
) -> Bool {
  let mc1 = mc0 + sb_size / 4
  let mr1 = mr0 + sb_size / 4
  for plane in 0..<layout.config.modes.length() {
    let frame_mode = layout.config.modes[plane]
    if frame_mode is Av1RestorationNone {
      continue
    }
    let (c0, c1, r0, r1) = av1_restoration_sb_unit_range(
      layout,
      plane,
      mc0,
      mc1,
      mr0,
      mr1,
      subsampling_x,
      subsampling_y,
    )
    for unit_row in r0..<r1 {
      for unit_col in c0..<c1 {
        let unit = av1_restoration_read_unit(decoder, tile_state, plane, frame_mode)
        tile_state.units.push({
          plane,
          unit_row,
          unit_col,
          unit,
        })
        if decoder.symbol_max_bits < -14 {
          return false
        }
      }
    }
  }
  true
}
