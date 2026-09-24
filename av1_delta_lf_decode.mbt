///|
/// The delta LF accumulator is tile-local and updates at the same SB origin
/// as delta-Q. Mono multi-delta streams code only Y vertical and horizontal.
fn av1_read_superblock_delta_lf(
  decoder : Av1SymbolDecoder,
  state : Av1IntraState,
) -> Unit {
  if !state.delta_lf_present {
    return
  }
  let count = if state.delta_lf_multi {
    if state.monochrome {
      2
    } else {
      4
    }
  } else {
    1
  }
  for k in 0..<count {
    let row = state.delta_lf_cdfs[if state.delta_lf_multi { k + 1 } else { 0 }]
    let mut delta = decoder.symbol(row)
    if delta == 3 {
      let bits = 1 + av1_msac_bools(decoder, 3)
      delta = av1_msac_bools(decoder, bits) + 1 + (1 << bits)
    }
    if delta != 0 && decoder.bool() == 1 {
      delta = -delta
    }
    let value = state.sb_lf_deltas[k] + (delta << state.delta_lf_res)
    state.sb_lf_deltas[k] = if value < -63 {
      -63
    } else if value > 63 {
      63
    } else {
      value
    }
  }
  if !state.delta_lf_multi {
    for k in 1..<4 {
      state.sb_lf_deltas[k] = state.sb_lf_deltas[0]
    }
  }
}
