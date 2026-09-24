///|
/// H.273 (07/2024), Tables 2--4 and equations 55--87. Values here are
/// normalized nonlinear luma and signed chroma, before integer rounding.
/// These conversions preserve the source primaries and transfer function;
/// display gamut conversion and tone mapping are separate operations.
fn av1_matrix_supported(matrix : Int) -> Bool {
  matrix >= 0 && matrix <= 14 && matrix != 3
}

///|
fn av1_color_transfer_supported(transfer : Int) -> Bool {
  transfer == 1 || (transfer >= 4 && transfer <= 18)
}

///|
/// Chromaticity-derived Y coefficients from H.273 Table 2. These constants
/// were evaluated in double precision by solving P*s = (xw,yw,zw)/yw,
/// where each column of P is (xp,yp,1-xp-yp), then taking (yr*sr,yb*sb).
/// Keeping the result avoids rebuilding/inverting a matrix for each pixel.
/// Unspecified and reserved primaries deliberately have no guessed values.
fn av1_color_derived_coefficients(primaries : Int) -> (Double, Double)? {
  match primaries {
    1 => Some((0.21263900587151033, 0.07219231536073371))
    4 => Some((0.29896661812478992, 0.11461217174222660))
    5 => Some((0.22200430999823087, 0.07134092407648639))
    6 | 7 => Some((0.21237636070506746, 0.08656378236920959))
    8 => Some((0.25358536343373467, 0.06807886086929262))
    9 => Some((0.26270021201126698, 0.05930171646986195))
    10 => Some((0.0, 0.0))
    11 => Some((0.20949167791273055, 0.06891306792622581))
    12 => Some((0.22897456406974875, 0.07928691409374498))
    22 => Some((0.23175054567210918, 0.09599868152322844))
    _ => None
  }
}

///|
fn av1_color_supported(matrix : Int, primaries : Int, transfer : Int) -> Bool {
  match matrix {
    10 => av1_color_transfer_supported(transfer)
    12 => av1_color_derived_coefficients(primaries) is Some(_)
    13 =>
      av1_color_derived_coefficients(primaries) is Some(_) &&
      av1_color_transfer_supported(transfer)
    14 => transfer == 16 || transfer == 18
    _ => av1_matrix_supported(matrix)
  }
}

///|
/// Inverse of H.273 Table 3, using its continuous-join constants.
/// PQ is normalized to its 10000-nit peak; HLG uses scene-linear light
/// without an OOTF. Log curves lose the darkest interval: encoded zero is
/// reconstructed as black. Curves without a negative domain clip at black.
/// PQ values beyond its finite inverse domain return None.
fn av1_color_linear(value : Double, transfer : Int) -> Double? {
  let positive = if value < 0.0 { 0.0 } else { value }
  Some(
    match transfer {
      1 | 6 | 14 | 15 =>
        if positive < 4.5 * 0.018053968510807 {
          positive / 4.5
        } else {
          @math.pow(
            (positive + 0.099296826809442) / 1.099296826809442,
            1.0 / 0.45,
          )
        }
      4 => @math.pow(positive, 2.2)
      5 => @math.pow(positive, 2.8)
      7 =>
        if positive < 4.0 * 0.022821585529445 {
          positive / 4.0
        } else {
          @math.pow(
            (positive + 0.111572195921731) / 1.111572195921731,
            1.0 / 0.45,
          )
        }
      8 => value
      9 => if value <= 0.0 { 0.0 } else { @math.pow(10.0, 2.0 * (value - 1.0)) }
      10 =>
        if value <= 0.0 {
          0.0
        } else {
          @math.pow(10.0, 2.5 * (value - 1.0))
        }
      11 =>
        if value < -4.5 * 0.018053968510807 {
          -@math.pow(
            (-value + 0.099296826809442) / 1.099296826809442,
            1.0 / 0.45,
          )
        } else if value < 4.5 * 0.018053968510807 {
          value / 4.5
        } else {
          @math.pow((value + 0.099296826809442) / 1.099296826809442, 1.0 / 0.45)
        }
      12 =>
        if value < -4.5 * 0.018053968510807 / 4.0 {
          -@math.pow(
            (-4.0 * value + 0.099296826809442) / 1.099296826809442,
            1.0 / 0.45,
          ) /
          4.0
        } else if value < 4.5 * 0.018053968510807 {
          value / 4.5
        } else {
          @math.pow((value + 0.099296826809442) / 1.099296826809442, 1.0 / 0.45)
        }
      13 => {
        let magnitude = if value < 0.0 { -value } else { value }
        let linear = if magnitude < 12.92 * 0.0030412825601275209 {
          magnitude / 12.92
        } else {
          @math.pow((magnitude + 0.0550107189475866) / 1.0550107189475866, 2.4)
        }
        if value < 0.0 {
          -linear
        } else {
          linear
        }
      }
      16 => {
        let power = @math.pow(positive, 1.0 / 78.84375)
        let numerator = if power > 0.8359375 { power - 0.8359375 } else { 0.0 }
        let denominator = 18.8515625 - 18.6875 * power
        // H.273's PQ curve can extend above the nominal white of 1, but
        // reaches an asymptote at (c2/c3)^m. At or beyond that point there
        // is no finite nonnegative light value: reject instead of allowing
        // a negative fractional-power base to become a NaN pixel.
        if !(denominator > 0.0) {
          return None
        }
        @math.pow(numerator / denominator, 1.0 / 0.1593017578125)
      }
      17 => @math.pow(positive, 2.6) * (52.37 / 48.0)
      18 =>
        if positive <= 0.5 {
          positive * positive / 3.0
        } else {
          (@math.exp((positive - 0.55991073) / 0.17883277) + 0.28466892) / 12.0
        }
      _ => return None
    },
  )
}

///|
/// Forward H.273 transfer. Negative values are retained only by curves
/// defining a negative domain (linear, IEC 61966-2-4, BT.1361 and sYCC).
fn av1_color_nonlinear(value : Double, transfer : Int) -> Double? {
  let positive = if value < 0.0 { 0.0 } else { value }
  Some(
    match transfer {
      1 | 6 | 14 | 15 =>
        if positive < 0.018053968510807 {
          4.5 * positive
        } else {
          1.099296826809442 * @math.pow(positive, 0.45) - 0.099296826809442
        }
      4 => @math.pow(positive, 1.0 / 2.2)
      5 => @math.pow(positive, 1.0 / 2.8)
      7 =>
        if positive < 0.022821585529445 {
          4.0 * positive
        } else {
          1.111572195921731 * @math.pow(positive, 0.45) - 0.111572195921731
        }
      8 => value
      9 => if value <= 0.01 { 0.0 } else { 1.0 + @math.log10(value) / 2.0 }
      10 =>
        if value <= 0.003162277660168379 {
          0.0
        } else {
          1.0 + @math.log10(value) / 2.5
        }
      11 =>
        if value < -0.018053968510807 {
          -1.099296826809442 * @math.pow(-value, 0.45) + 0.099296826809442
        } else if value < 0.018053968510807 {
          4.5 * value
        } else {
          1.099296826809442 * @math.pow(value, 0.45) - 0.099296826809442
        }
      12 =>
        if value < -0.018053968510807 / 4.0 {
          -(1.099296826809442 * @math.pow(-4.0 * value, 0.45) -
          0.099296826809442) /
          4.0
        } else if value < 0.018053968510807 {
          4.5 * value
        } else {
          1.099296826809442 * @math.pow(value, 0.45) - 0.099296826809442
        }
      13 => {
        let magnitude = if value < 0.0 { -value } else { value }
        let nonlinear = if magnitude < 0.0030412825601275209 {
          12.92 * magnitude
        } else {
          1.0550107189475866 * @math.pow(magnitude, 1.0 / 2.4) -
          0.0550107189475866
        }
        if value < 0.0 {
          -nonlinear
        } else {
          nonlinear
        }
      }
      16 => {
        let power = @math.pow(positive, 0.1593017578125)
        @math.pow(
          (0.8359375 + 18.8515625 * power) / (1.0 + 18.6875 * power),
          78.84375,
        )
      }
      17 => @math.pow(positive * (48.0 / 52.37), 1.0 / 2.6)
      18 =>
        if positive <= 1.0 / 12.0 {
          (3.0 * positive).sqrt()
        } else {
          0.17883277 * @math.ln(12.0 * positive - 0.28466892) + 0.55991073
        }
      _ => return None
    },
  )
}

///|
fn av1_color_ncl(
  y : Double,
  u : Double,
  v : Double,
  kr : Double,
  kb : Double,
) -> (Double, Double, Double) {
  let r = y + 2.0 * (1.0 - kr) * v
  let b = y + 2.0 * (1.0 - kb) * u
  (r, (y - kr * r - kb * b) / (1.0 - kr - kb), b)
}

///|
fn av1_color_cl(
  y : Double,
  u : Double,
  v : Double,
  kr : Double,
  kb : Double,
  transfer : Int,
) -> (Double, Double, Double)? {
  if !av1_color_transfer_supported(transfer) {
    return None
  }
  let blue_scale = if u <= 0.0 {
    av1_color_nonlinear(1.0 - kb, transfer).unwrap()
  } else {
    1.0 - av1_color_nonlinear(kb, transfer).unwrap()
  }
  let red_scale = if v <= 0.0 {
    av1_color_nonlinear(1.0 - kr, transfer).unwrap()
  } else {
    1.0 - av1_color_nonlinear(kr, transfer).unwrap()
  }
  let r = y + 2.0 * red_scale * v
  let b = y + 2.0 * blue_scale * u
  let linear_y = match av1_color_linear(y, transfer) {
    Some(value) => value
    None => return None
  }
  let linear_r = match av1_color_linear(r, transfer) {
    Some(value) => value
    None => return None
  }
  let linear_b = match av1_color_linear(b, transfer) {
    Some(value) => value
    None => return None
  }
  let green_linear = (linear_y - kr * linear_r - kb * linear_b) /
    (1.0 - kr - kb)
  Some((r, av1_color_nonlinear(green_linear, transfer).unwrap(), b))
}

///|
fn av1_color_ictcp(
  intensity : Double,
  ct : Double,
  cp : Double,
  transfer : Int,
) -> (Double, Double, Double)? {
  // Inverses of H.273 equations 81/82 and 86/87 (PQ and HLG).
  let (lp, mp, sp) = match transfer {
    16 =>
      (
        intensity + 0.008609037037932761 * ct + 0.11102962500302598 * cp,
        intensity - 0.008609037037932761 * ct - 0.11102962500302598 * cp,
        intensity + 0.56003133571067909 * ct - 0.32062717498731880 * cp,
      )
    18 =>
      (
        intensity + 0.015718580108730413 * ct + 0.20958106811640551 * cp,
        intensity - 0.015718580108730413 * ct - 0.20958106811640551 * cp,
        intensity + 1.0212710798422344 * ct - 0.60527449099243158 * cp,
      )
    _ => return None
  }
  let l = match av1_color_linear(lp, transfer) {
    Some(value) => value
    None => return None
  }
  let m = match av1_color_linear(mp, transfer) {
    Some(value) => value
    None => return None
  }
  let s = match av1_color_linear(sp, transfer) {
    Some(value) => value
    None => return None
  }
  // Inverse of the integer LMS matrix in H.273 equations 79 and 84.
  // Every row sums to one. Expressing it with channel differences preserves
  // the neutral axis exactly, including at the HLG piecewise-function join.
  let r = l - 2.5064521186562705 * (m - l) + 0.069845424323191518 * (s - l)
  let g = m - 0.79132955559892892 * (l - m) - 0.19227089619336202 * (s - m)
  let b = s - 0.025949899690592672 * (l - s) - 0.098913714711726455 * (m - s)
  Some(
    (
      av1_color_nonlinear(r, transfer).unwrap(),
      av1_color_nonlinear(g, transfer).unwrap(),
      av1_color_nonlinear(b, transfer).unwrap(),
    ),
  )
}

///|
/// Identity (matrix 0) has uncentered G/B/R planes and is handled by the
/// caller. Matrix 2 explicitly uses the decoder's BT.601 default.
/// Matrix 11 recovers the source R/G/B or X/Y/Z components; the caller
/// applies any required XYZ-to-display conversion for primaries 10.
fn av1_color_rgb(
  y : Double,
  u : Double,
  v : Double,
  matrix : Int,
  primaries : Int,
  transfer : Int,
) -> (Double, Double, Double)? {
  match matrix {
    1 => Some(av1_color_ncl(y, u, v, 0.2126, 0.0722))
    2 | 5 | 6 => Some(av1_color_ncl(y, u, v, 0.299, 0.114))
    4 => Some(av1_color_ncl(y, u, v, 0.30, 0.11))
    7 => Some(av1_color_ncl(y, u, v, 0.212, 0.087))
    8 => Some((y - u + v, y + u, y - u - v))
    9 => Some(av1_color_ncl(y, u, v, 0.2627, 0.0593))
    10 => av1_color_cl(y, u, v, 0.2627, 0.0593, transfer)
    11 => Some((2.0 * v + 0.991902 * y, y, (2.0 * u + y) / 0.986566))
    12 | 13 => {
      let (kr, kb) = match av1_color_derived_coefficients(primaries) {
        Some(coefficients) => coefficients
        None => return None
      }
      if matrix == 12 {
        Some(av1_color_ncl(y, u, v, kr, kb))
      } else {
        av1_color_cl(y, u, v, kr, kb, transfer)
      }
    }
    14 => av1_color_ictcp(y, u, v, transfer)
    _ => None
  }
}
