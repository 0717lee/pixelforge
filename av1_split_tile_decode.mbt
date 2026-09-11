///|
/// Bounded AV1 SPLIT tile decoder for a 64x64 reduced-still frame.
///
/// This path shares one MSAC reader and one mutable coefficient context across
/// the four 32x32 luma children. It is deliberately narrow (4:2:0, 8-bit,
/// DC intra prediction and all-zero chroma), but walks the real split syntax.
fn av1_split_luma_zero(q : Int) -> Array[Int] {
  if q <= 20 {
    [17920, 32768, 0]
  } else if q <= 60 {
    [26726, 32768, 0]
  } else if q <= 120 {
    [30669, 32768, 0]
  } else {
    [31671, 32768, 0]
  }
}

///|
fn av1_split_chroma_zero(q : Int) -> Array[Int] {
  if q <= 20 {
    [3778, 32768, 0]
  } else if q <= 60 {
    [4215, 32768, 0]
  } else if q <= 120 {
    [3648, 32768, 0]
  } else {
    [3440, 32768, 0]
  }
}

///|
fn av1_split_partition_cdf(use_128x128_superblock : Bool) -> Array[Int] {
  if use_128x128_superblock {
    [27899, 28219, 28529, 32484, 32539, 32619, 32639, 32768, 0]
  } else {
    [20137, 21547, 23078, 29566, 29837, 30261, 30524, 30892, 31724, 32768, 0]
  }
}

///|
fn av1_split_skip_cdf() -> Array[Int] {
  [31671, 32768, 0]
}

///|
fn av1_split_y_mode_cdf() -> Array[Int] {
  [
    15588, 17027, 19338, 20218, 20682, 21110, 21825, 23244, 24189, 28165, 29093,
    30466, 32768, 0,
  ]
}

///|
fn av1_split_uv_mode_cdf() -> Array[Int] {
  [
    22631, 24152, 25378, 25661, 25986, 26520, 27055, 27923, 28244, 30059, 30941,
    31961, 32768, 0,
  ]
}

///|
/// Decode a 64x64 root whose first partition symbol is SPLIT.
pub fn av1_decode_split_tile_64x64(
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  allow_screen_content_tools? : Bool = false,
) -> Image? {
  if tile_payload.length() == 0 ||
    tile_payload.length() > 255 ||
    base_q_idx < 0 ||
    base_q_idx > 255 {
    return None
  }
  let decoder = av1_msac_new(tile_payload, !disable_cdf_update)
  if decoder.symbol(av1_split_partition_cdf(use_128x128_superblock)) != 3 {
    return None
  }
  let y_context = av1_coeff_context(base_q_idx, 3, 0)
  let y_zero = av1_split_luma_zero(base_q_idx)
  let c_zero = av1_split_chroma_zero(base_q_idx)
  let y_coeffs : Array[Array[Int]] = []
  let y_modes : Array[Int] = []
  let u_coeffs : Array[Array[Int]] = []
  let v_coeffs : Array[Array[Int]] = []
  let u_modes : Array[Int] = []
  let v_modes : Array[Int] = []
  for _ in 0..<4 {
    if decoder.symbol(av1_split_skip_cdf()) != 0 {
      return None
    }
    let mode = decoder.symbol(av1_split_y_mode_cdf())
    if allow_screen_content_tools &&
      mode == 0 &&
      decoder.symbol([32309, 32768, 0]) != 0 {
      return None
    }
    if allow_screen_content_tools && decoder.symbol([32461, 32768, 0]) != 0 {
      return None
    }
    let all_zero = decoder.symbol(y_zero)
    if all_zero == 0 {
      let coeffs = match
        av1_decode_coeffs_square_with_decoder(decoder, base_q_idx, y_context) {
        Some(value) => value
        None => return None
      }
      y_coeffs.push(coeffs)
    } else if all_zero == 1 {
      y_coeffs.push(Array::make(32 * 32, 0))
    } else {
      return None
    }
    y_modes.push(mode)
    let uv_mode = decoder.symbol(av1_split_uv_mode_cdf())
    let u_zero = decoder.symbol(c_zero)
    if u_zero == 1 {
      u_coeffs.push(Array::make(16 * 16, 0))
    } else if u_zero == 0 {
      let coeffs = match av1_decode_coeffs_square_with_decoder(
        decoder, base_q_idx, av1_coeff_context(base_q_idx, 3, 1),
      ) {
        Some(value) => value
        None => return None
      }
      u_coeffs.push(coeffs)
    } else { return None }
    let v_zero = decoder.symbol(c_zero)
    if v_zero == 1 {
      v_coeffs.push(Array::make(16 * 16, 0))
    } else if v_zero == 0 {
      let coeffs = match av1_decode_coeffs_square_with_decoder(
        decoder, base_q_idx, av1_coeff_context(base_q_idx, 3, 2),
      ) {
        Some(value) => value
        None => return None
      }
      v_coeffs.push(coeffs)
    } else { return None }
    if uv_mode < 0 || uv_mode > AV1_INTRA_PAETH {
      return None
    }
    u_modes.push(uv_mode)
    v_modes.push(uv_mode)
  }
  av1_reconstruct_split_64x64(
    y_coeffs,
    u_coeffs,
    v_coeffs,
    y_modes,
    u_modes,
    v_modes,
    full_range~,
    matrix_coefficients~,
  )
}

///|
test "split tile probe rejects a non-split root" {
  assert_true(av1_decode_split_tile_64x64([b'\x2E'], 43) is None)
}
