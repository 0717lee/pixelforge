///|
/// CICP primaries 10 carries CIE XYZ components, so its recovered channels
/// cannot be labelled RGB. Decode the declared transfer, convert linear XYZ
/// to BT.709 D65 RGB, and encode sRGB. Values retain the source normalization;
/// there is no chromatic adaptation or HDR tone mapping. The caller performs
/// final gamut clipping to the Image type's 8-bit channels.
fn av1_color_xyz_to_srgb(
  x : Double,
  y : Double,
  z : Double,
  transfer : Int,
) -> (Double, Double, Double)? {
  let x = match av1_color_linear(x, transfer) {
    Some(value) => value
    None => return None
  }
  let y = match av1_color_linear(y, transfer) {
    Some(value) => value
    None => return None
  }
  let z = match av1_color_linear(z, transfer) {
    Some(value) => value
    None => return None
  }
  let linear_r = 3.2409699419045226 * x -
    1.537383177570094 * y -
    0.4986107602930034 * z
  let linear_g = -0.9692436362808796 * x +
    1.8759675015077202 * y +
    0.04155505740717559 * z
  let linear_b = 0.05563007969699366 * x -
    0.20397695888897652 * y +
    1.0569715142428786 * z
  let r = match av1_color_nonlinear(linear_r, 13) {
    Some(value) => value
    None => return None
  }
  let g = match av1_color_nonlinear(linear_g, 13) {
    Some(value) => value
    None => return None
  }
  let b = match av1_color_nonlinear(linear_b, 13) {
    Some(value) => value
    None => return None
  }
  Some((r, g, b))
}
