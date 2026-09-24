///|
/// Raw frame-level CDEF parameters. Primary strengths remain in 8-bit units;
/// secondary syntax value 3 has already been remapped to strength 4.
/// Monochrome configurations have empty UV arrays. A missing configuration
/// in a frame header means CDEF is disabled by the frame/sequence gates.
pub(all) struct Av1CdefConfig {
  bits : Int
  damping : Int
  y_primary : Array[Int]
  y_secondary : Array[Int]
  uv_primary : Array[Int]
  uv_secondary : Array[Int]
}

///|
fn av1_cdef_config_valid(
  config : Av1CdefConfig,
  monochrome? : Bool = false,
) -> Bool {
  if config.bits < 0 ||
    config.bits > 3 ||
    config.damping < 3 ||
    config.damping > 6 {
    return false
  }
  let count = 1 << config.bits
  let uv_count = if monochrome { 0 } else { count }
  if config.y_primary.length() != count ||
    config.y_secondary.length() != count ||
    config.uv_primary.length() != uv_count ||
    config.uv_secondary.length() != uv_count {
    return false
  }
  for strengths in [config.y_primary, config.uv_primary] {
    for strength in strengths {
      if strength < 0 || strength > 15 {
        return false
      }
    }
  }
  for strengths in [config.y_secondary, config.uv_secondary] {
    for strength in strengths {
      if strength != 0 && strength != 1 && strength != 2 && strength != 4 {
        return false
      }
    }
  }
  true
}
