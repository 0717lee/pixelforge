///|
/// AV1 ISOBMFF section 2.3.4 permits nclx to supply each unspecified (2)
/// bitstream color-description field. Specified fields retain the sequence
/// value; conforming containers declare the same value in nclx. The nclx
/// range flag is retained and applied (it likewise matches the sequence in
/// conforming files). Pixel reconstruction itself does not depend on nclx.
fn avif_frame_apply_color(
  frame : Av1FramePlanes,
  container : AvifContainer,
) -> Av1FramePlanes {
  av1_frame_apply_nclx(
    frame,
    container.nclx_primaries,
    container.nclx_transfer,
    container.nclx_matrix,
    container.nclx_full_range,
  )
}

///|
/// Shared item/track nclx application; absent fields preserve bitstream data.
fn av1_frame_apply_nclx(
  frame : Av1FramePlanes,
  primaries : Int?,
  transfer : Int?,
  matrix : Int?,
  full_range : Bool?,
) -> Av1FramePlanes {
  {
    ..frame,
    color_primaries: if frame.color_primaries == 2 {
      primaries.unwrap_or(2)
    } else {
      frame.color_primaries
    },
    transfer_characteristics: if frame.transfer_characteristics == 2 {
      transfer.unwrap_or(2)
    } else {
      frame.transfer_characteristics
    },
    matrix_coefficients: if frame.matrix_coefficients == 2 {
      matrix.unwrap_or(2)
    } else {
      frame.matrix_coefficients
    },
    full_range: full_range.unwrap_or(frame.full_range),
  }
}
