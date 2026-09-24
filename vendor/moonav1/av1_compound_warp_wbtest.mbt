/// Compound warp references from unchanged dav1d 1.2.1 scalar C kernels.
/// warp_affine_8x8t_c, avg_c, w_avg_c, mask_c and w_mask_c supplied every
/// expected sample; init_chroma supplied signed subsampled wedge weights.
/// The input pattern, model matrices and plane geometry are explicit below.
/// Canonical text output SHA-256:
/// 7ae7e07f95d8801b1ab8718cf283424cfcd7640a4173ab513c56260e98b585a0.

///|
let av1_compound_warp_matrices : Array[Array[Int]] = [
  [73728, -32768, 65664, 256, -256, 65664],
  [-16384, 77824, 65344, -128, 128, 65344],
]

///|
fn av1_compound_warp_reference(
  depth : Int,
  layout : Int,
  list : Int,
) -> Av1RefFrame {
  let sub_x = if layout > 0 { 1 } else { 0 }
  let sub_y = if layout == 2 { 1 } else { 0 }
  let maximum = (1 << depth) - 1
  let planes : Array[Array[Int]] = []
  for plane in 0..<3 {
    let width = 32 >> (if plane == 0 { 0 } else { sub_x })
    let height = 32 >> (if plane == 0 { 0 } else { sub_y })
    planes.push(
      Array::makei(width * height, i => {
        let x = i % width
        let y = i / width
        let ramp = (x * 7 + y * 3 + list * 11 + plane * 17) & (maximum >> 3)
        if (x / 2 + y / 3 + list + plane) % 4 < 2 {
          ramp
        } else {
          maximum - ramp
        }
      }),
    )
  }
  av1_warp_regression_frame(planes, 32, 32, 32, 32, sub_x, sub_y, depth)
}

///|
fn av1_compound_warp_info(depth : Int, layout : Int) -> Av1InterInfo {
  let base = av1_inter_regression_info()
  base.refs[av1_last_frame] = Some(
    av1_compound_warp_reference(depth, layout, 0),
  )
  base.refs[av1_last2_frame] = Some(
    av1_compound_warp_reference(depth, layout, 1),
  )
  for list in 0..<2 {
    base.frame.gm_type[list + 1] = av1_gm_affine
    base.frame.gm_params[list + 1] = av1_compound_warp_matrices[list]
  }
  base.ref_distances[av1_last_frame] = 2
  base.ref_distances[av1_last2_frame] = 4
  base
}

///|
fn av1_compound_warp_block(info : Av1InterInfo, size : Int) -> Av1InterBlock {
  let index = av1_intra_block_index(size, size).unwrap()
  let block = av1_inter_block(4, 4, size / 4, size / 4, index, true, true)
  block.ref_frame = av1_last_frame
  block.ref_frame1 = av1_last2_frame
  block.y_mode = av1_mode_global_global_mv
  block.mv_row = 8
  block.mv_col = 16
  block.mv_row1 = -8
  block.mv_col1 = -16
  av1_motion_field_store(
    info.field,
    4,
    4,
    size / 4,
    size / 4,
    block.y_mode,
    [av1_last_frame, av1_last2_frame],
    [8, -8],
    [16, -16],
    interp=[0, 0],
  )
  block
}

///|
fn av1_compound_warp_crc(pixels : Array[Int]) -> UInt {
  let bytes : Array[Byte] = []
  for pixel in pixels {
    for shift in [0, 8, 16, 24] {
      bytes.push(((pixel >> shift) & 255).to_byte())
    }
  }
  crc32(bytes, 0, bytes.length())
}

///|
fn av1_compound_warp_check_average(
  info : Av1InterInfo,
  depth : Int,
  layout : Int,
  size : Int,
  warp_lists : Array[Bool],
) -> Unit raise {
  let sub_x = if layout > 0 { 1 } else { 0 }
  let sub_y = if layout == 2 { 1 } else { 0 }
  let state = av1_intra_state(
    32,
    32,
    100,
    depth,
    false,
    false,
    false,
    false,
    sub_x~,
    sub_y~,
  )
  let block = av1_compound_warp_block(info, size)
  assert_true(
    av1_inter_predict(state, info, block, {
      row: 16,
      col: 16,
      width: size,
      height: size,
    }),
  )
  let post = if depth == 12 { 2 } else { 4 }
  for plane in 0..<3 {
    let sx = if plane == 0 { 0 } else { sub_x }
    let sy = if plane == 0 { 0 } else { sub_y }
    let width = size >> sx
    let height = size >> sy
    let predictions : Array[Array[Int]] = []
    for list in 0..<2 {
      let reference = info.refs[list + 1].unwrap()
      let prediction = if warp_lists[list] && width >= 8 && height >= 8 {
        av1_warp_predict(
          reference,
          av1_warp_from_global_motion(info.frame.gm_params[list + 1]).unwrap(),
          plane,
          4,
          4,
          16 >> sx,
          16 >> sy,
          width,
          height,
          compound=true,
        )
      } else {
        av1_motion_compensate({
          reference,
          frame_width: 32,
          frame_height: 32,
          plane,
          x: 16 >> sx,
          y: 16 >> sy,
          width,
          height,
          mv_row: if list == 0 {
            8
          } else {
            -8
          },
          mv_col: if list == 0 {
            16
          } else {
            -16
          },
          filter_vertical: 0,
          filter_horizontal: 0,
          compound: true,
        })
      }
      predictions.push(prediction)
    }
    let target = state.planes[plane]
    let maximum = (1 << depth) - 1
    for i in 0..<(width * height) {
      let value = (predictions[0][i] + predictions[1][i] + (1 << post)) >>
        (post + 1)
      let expected = if value < 0 {
        0
      } else if value > maximum {
        maximum
      } else {
        value
      }
      let actual = target.pixels[((16 >> sy) + i / width) * target.width +
        (16 >> sx) +
        i % width]
      assert_eq(
        (depth, layout, plane, i, actual),
        (depth, layout, plane, i, expected),
      )
    }
  }
}

///|
test "compound warp selects each global reference independently" {
  for depth in [8, 10, 12] {
    for layout in [0, 1, 2] {
      for warp_list in [0, 1] {
        let info = av1_compound_warp_info(depth, layout)
        info.frame.gm_type[2 - warp_list] = av1_gm_translation
        av1_compound_warp_check_average(info, depth, layout, 16, [
          warp_list == 0,
          warp_list == 1,
        ])
      }
    }
  }
}

///|
test "compound warp retains ordinary MC for small chroma and integer-only frames" {
  for depth in [8, 10, 12] {
    for layout in [0, 1, 2] {
      let info = av1_compound_warp_info(depth, layout)
      av1_compound_warp_check_average(info, depth, layout, 8, [true, true])
      let integer_info : Av1InterInfo = {
        ..info,
        frame: { ..info.frame, force_integer_mv: 1, },
      }
      av1_compound_warp_check_average(integer_info, depth, layout, 16, [
        false, false,
      ])
    }
  }
}

///|
test "compound warp falls back independently for invalid shear and scaled references" {
  for layout in [0, 1, 2] {
    let info = av1_compound_warp_info(10, layout)
    info.frame.gm_params[av1_last_frame] = [0, 0, 0x50000, 0, 0, 0x10000]
    av1_compound_warp_check_average(info, 10, layout, 16, [false, true])
    info.frame.gm_params[av1_last_frame] = av1_compound_warp_matrices[0]
    let reference = info.refs[av1_last_frame].unwrap()
    info.refs[av1_last_frame] = Some({
      ..reference,
      width: 24,
      frame_width: 24,
      upscaled_width: 24,
    })
    av1_compound_warp_check_average(info, 10, layout, 16, [false, true])
  }
}

///|
fn av1_compound_warp_oracle_case(
  depth : Int,
  layout : Int,
  prediction_crcs : Array[UInt],
  blend_crcs : Array[UInt],
) -> Unit raise {
  let sub_x = if layout > 0 { 1 } else { 0 }
  let sub_y = if layout == 2 { 1 } else { 0 }
  let post = if depth == 12 { 2 } else { 4 }
  let info = av1_compound_warp_info(depth, layout)
  for plane in 0..<3 {
    let sx = if plane == 0 { 0 } else { sub_x }
    let sy = if plane == 0 { 0 } else { sub_y }
    for list in 0..<2 {
      let reference = info.refs[list + 1].unwrap()
      let model = av1_warp_from_global_motion(av1_compound_warp_matrices[list]).unwrap()
      let actual = av1_warp_predict(
        reference,
        model,
        plane,
        4,
        4,
        16 >> sx,
        16 >> sy,
        16 >> sx,
        16 >> sy,
        compound=true,
      )
      assert_eq(
        (plane, list, av1_compound_warp_crc(actual)),
        (plane, list, prediction_crcs[plane * 2 + list]),
      )
      // Every reference vector exercises both retained fraction and overshoot.
      assert_true(actual.any(v => (v & ((1 << post) - 1)) != 0))
      assert_true(actual.any(v => v < 0 || v > ((1 << depth) - 1) << post))
    }
  }
  for mode in 0..<6 {
    let state = av1_intra_state(
      32,
      32,
      100,
      depth,
      false,
      false,
      false,
      false,
      sub_x~,
      sub_y~,
    )
    let block = av1_compound_warp_block(info, 16)
    block.compound_type = match mode {
      0 => av1_compound_average
      1 => av1_compound_distance
      2 | 3 => av1_compound_diffwtd
      _ => av1_compound_wedge
    }
    block.mask_type = if mode == 3 { 1 } else { 0 }
    block.wedge_index = 4
    block.wedge_sign = if mode == 5 { 1 } else { 0 }
    assert_true(
      av1_inter_predict(state, info, block, {
        row: 16,
        col: 16,
        width: 16,
        height: 16,
      }),
    )
    for plane in 0..<3 {
      let sx = if plane == 0 { 0 } else { sub_x }
      let sy = if plane == 0 { 0 } else { sub_y }
      let width = 16 >> sx
      let height = 16 >> sy
      let target = state.planes[plane]
      let actual = Array::makei(width * height, i => {
        target.pixels[((16 >> sy) + i / width) * target.width +
        (16 >> sx) +
        i % width]
      })
      assert_eq(
        (mode, plane, av1_compound_warp_crc(actual)),
        (mode, plane, blend_crcs[mode * 3 + plane]),
      )
    }
  }
}

///|
fn av1_compound_warp_full_pixels(
  depth : Int,
  layout : Int,
  mode : Int,
  plane : Int,
  expected : Array[Int],
) -> Unit raise {
  let sub_x = if layout > 0 { 1 } else { 0 }
  let sub_y = if layout == 2 { 1 } else { 0 }
  let info = av1_compound_warp_info(depth, layout)
  let state = av1_intra_state(
    32,
    32,
    100,
    depth,
    false,
    false,
    false,
    false,
    sub_x~,
    sub_y~,
  )
  let block = av1_compound_warp_block(info, 16)
  block.compound_type = match mode {
    0 => av1_compound_average
    1 => av1_compound_distance
    2 | 3 => av1_compound_diffwtd
    _ => av1_compound_wedge
  }
  block.mask_type = if mode == 3 { 1 } else { 0 }
  block.wedge_index = 4
  block.wedge_sign = if mode == 5 { 1 } else { 0 }
  assert_true(
    av1_inter_predict(state, info, block, {
      row: 16,
      col: 16,
      width: 16,
      height: 16,
    }),
  )
  let sx = if plane == 0 { 0 } else { sub_x }
  let sy = if plane == 0 { 0 } else { sub_y }
  let width = 16 >> sx
  let height = 16 >> sy
  let target = state.planes[plane]
  let actual = Array::makei(width * height, i => {
    target.pixels[((16 >> sy) + i / width) * target.width +
    (16 >> sx) +
    i % width]
  })
  assert_eq(actual, expected)
}

// BEGIN DAV1D COMPOUND WARP REFERENCES

///|
test "compound warp original C 8bit 444 all signed blends" {
  av1_compound_warp_oracle_case(
    8,
    0,
    [
      0x30f54104U, 0xcbeb9dc1U, 0x5bcb0476U, 0x3a3c6988U, 0xbd5b6547U, 0xd2b5ac46U,
    ],
    [
      0xa8a886cbU, 0xc06685c7U, 0x28349710U, 0x6a8514e1U, 0x32c67417U, 0x20214414U,
      0x47264296U, 0x466826eaU, 0x4d6c6916U, 0x87ba2ecdU, 0x841c5a7eU, 0x99b7e67aU,
      0xddf2553fU, 0x0c84b59bU, 0x07d6e9c3U, 0x20118ef6U, 0xf77e794bU, 0xd5f55d7cU,
    ],
  )
}

///|
test "compound warp original C 8bit 422 all signed blends" {
  av1_compound_warp_oracle_case(
    8,
    1,
    [
      0x30f54104U, 0xcbeb9dc1U, 0xf76c7f31U, 0x51ef4a5cU, 0x5a25d16eU, 0x5a3ea488U,
    ],
    [
      0xa8a886cbU, 0x3670f198U, 0x1790160fU, 0x6a8514e1U, 0xf7524a4cU, 0x25107889U,
      0x47264296U, 0xa8781246U, 0x7b000f83U, 0x87ba2ecdU, 0xa65975bcU, 0x37ceda78U,
      0xddf2553fU, 0xddb43aa6U, 0xedfcb2f3U, 0x20118ef6U, 0x5d4d195eU, 0xc3b4e417U,
    ],
  )
}

///|
test "compound warp original C 8bit 420 all signed blends" {
  av1_compound_warp_oracle_case(
    8,
    2,
    [
      0x30f54104U, 0xcbeb9dc1U, 0xcaef0facU, 0x3da03139U, 0xde432338U, 0xfd737179U,
    ],
    [
      0xa8a886cbU, 0x3f84988fU, 0x3261e1cfU, 0x6a8514e1U, 0xc681af4cU, 0xbc182e72U,
      0x47264296U, 0x1323ba77U, 0x822e9200U, 0x87ba2ecdU, 0xd24b8ed6U, 0x972d48f9U,
      0xddf2553fU, 0xe49e95c1U, 0xc480f19eU, 0x20118ef6U, 0x0431923aU, 0x9673912cU,
    ],
  )
}

///|
test "compound warp original C 10bit 444 all signed blends" {
  av1_compound_warp_oracle_case(
    10,
    0,
    [
      0x411df3f2U, 0x1642068aU, 0x90534548U, 0xf0b74b66U, 0xfe314842U, 0x3195d560U,
    ],
    [
      0x641c579bU, 0x4213aa92U, 0x6c763c11U, 0xa761a0b9U, 0xe3a56362U, 0x51160011U,
      0xb9be326eU, 0xae12dfb3U, 0xf0344d82U, 0x81187a5eU, 0xfc83b858U, 0x1ef9cde5U,
      0xfd35ecb0U, 0x180a000cU, 0x1baaf478U, 0x26f421f5U, 0x5a583ba9U, 0x03d4f041U,
    ],
  )
}

///|
test "compound warp original C 10bit 422 all signed blends" {
  av1_compound_warp_oracle_case(
    10,
    1,
    [
      0x411df3f2U, 0x1642068aU, 0xd2181a27U, 0xcc700960U, 0xc09519a7U, 0x9784d00aU,
    ],
    [
      0x641c579bU, 0xe6a56b38U, 0x95d29eb8U, 0xa761a0b9U, 0x909b55bdU, 0xc87a327fU,
      0xb9be326eU, 0xf7c28c99U, 0x7df0348bU, 0x81187a5eU, 0xc90b1277U, 0x223e7929U,
      0xfd35ecb0U, 0xeadc210eU, 0x3bc04430U, 0x26f421f5U, 0x34c44b59U, 0x716598afU,
    ],
  )
}

///|
test "compound warp original C 10bit 420 all signed blends" {
  av1_compound_warp_oracle_case(
    10,
    2,
    [
      0x411df3f2U, 0x1642068aU, 0x7757e43aU, 0x0682465dU, 0x8426d531U, 0x70706e47U,
    ],
    [
      0x641c579bU, 0xf052cc9eU, 0xf4a96af0U, 0xa761a0b9U, 0xb6d5fa8aU, 0xd45dfff3U,
      0xb9be326eU, 0x1830c016U, 0xba64109cU, 0x81187a5eU, 0x1ac2618fU, 0x5db51519U,
      0xfd35ecb0U, 0x520f03d6U, 0x863c461aU, 0x26f421f5U, 0x43f10443U, 0x2d92d240U,
    ],
  )
}

///|
test "compound warp original C 12bit 444 all signed blends" {
  av1_compound_warp_oracle_case(
    12,
    0,
    [
      0x013f4f87U, 0x39c71c18U, 0x355cfbb3U, 0x2e16af9cU, 0x90b147f1U, 0x7fdd47edU,
    ],
    [
      0x7795c1a2U, 0x5858af25U, 0x963375dbU, 0xa0998126U, 0xc24e71d7U, 0x13527db8U,
      0xe8b34ef0U, 0xfd2f822aU, 0x761013a8U, 0xdf00c56eU, 0x2825ebd3U, 0x050fd464U,
      0xcf049699U, 0x5946ca2bU, 0x8b9c74f6U, 0xb7efb29cU, 0x1b87e599U, 0x8e4389a9U,
    ],
  )
}

///|
test "compound warp original C 12bit 422 all signed blends" {
  av1_compound_warp_oracle_case(
    12,
    1,
    [
      0x013f4f87U, 0x39c71c18U, 0x5428c09aU, 0x91a9aeb9U, 0x3227459eU, 0xece1047fU,
    ],
    [
      0x7795c1a2U, 0xdb72a96cU, 0xe1b7d94aU, 0xa0998126U, 0xb9116ac7U, 0xf42c91f9U,
      0xe8b34ef0U, 0x44ce7364U, 0xdaabe93fU, 0xdf00c56eU, 0x23a22bc0U, 0xa54d4915U,
      0xcf049699U, 0x3ef056a4U, 0x6740f808U, 0xb7efb29cU, 0xbe94b50dU, 0x9242d956U,
    ],
  )
}

///|
test "compound warp original C 12bit 420 all signed blends" {
  av1_compound_warp_oracle_case(
    12,
    2,
    [
      0x013f4f87U, 0x39c71c18U, 0x399d5548U, 0xb8483721U, 0xdf0083f7U, 0xe46be4f3U,
    ],
    [
      0x7795c1a2U, 0xf3ddbbb7U, 0xbea15270U, 0xa0998126U, 0x6251f5b2U, 0xfbc9002bU,
      0xe8b34ef0U, 0x71a0c8c1U, 0xdb29869fU, 0xdf00c56eU, 0x9f939428U, 0x44d5f734U,
      0xcf049699U, 0xf46d7583U, 0xb90fa978U, 0xb7efb29cU, 0x17790308U, 0x8b258323U,
    ],
  )
}

///|
test "compound warp full pixels depth8 layout0 blend0 plane0" {
  av1_compound_warp_full_pixels(8, 0, 0, 0, [
    123, 255, 213, 238, 136, 0, 35, 30, 141, 255, 224, 230, 118, 0, 13, 16, 131,
    253, 146, 123, 123, 0, 104, 135, 140, 255, 151, 130, 112, 0, 102, 146, 181, 255,
    141, 55, 74, 0, 101, 185, 184, 255, 160, 65, 58, 0, 79, 125, 222, 227, 114, 0,
    28, 22, 137, 255, 232, 231, 134, 0, 16, 27, 94, 148, 150, 122, 114, 0, 105, 123,
    143, 255, 152, 130, 112, 0, 94, 134, 108, 116, 155, 67, 67, 0, 97, 193, 198,
    255, 157, 77, 69, 0, 93, 182, 164, 185, 119, 0, 22, 19, 120, 255, 236, 238, 128,
    0, 39, 8, 126, 255, 231, 238, 110, 0, 102, 125, 129, 255, 159, 128, 127, 0, 100,
    127, 133, 250, 137, 90, 68, 0, 101, 183, 187, 255, 158, 68, 83, 0, 89, 187, 174,
    255, 176, 118, 24, 9, 127, 255, 217, 252, 128, 0, 35, 7, 125, 255, 212, 225,
    169, 115, 94, 125, 128, 255, 154, 130, 121, 4, 112, 118, 136, 253, 146, 116,
    145, 149, 99, 193, 175, 255, 163, 62, 81, 0, 96, 191, 179, 255, 150, 66, 84,
    76, 127, 255, 221, 251, 130, 0, 44, 12, 119, 255, 219, 231, 110, 0, 18, 16, 135,
    253, 143, 138, 118, 0, 102, 126, 140, 255, 155, 124, 107, 0, 99, 146, 179, 255,
    137, 62, 74, 0, 118, 200, 183, 255, 156, 71, 68, 0, 82, 137, 224, 255, 126, 0,
    25, 0, 134, 255, 235, 255, 138, 0, 7, 4, 84, 145,
  ])
}

///|
test "compound warp full pixels depth10 layout1 blend3 plane1" {
  av1_compound_warp_full_pixels(10, 1, 3, 1, [
    962, 916, 485, 86, 40, 95, 585, 701, 392, 70, 474, 63, 607, 877, 603, 743, 529,
    201, 244, 0, 462, 785, 803, 901, 500, 66, 13, 106, 511, 927, 974, 864, 306, 111,
    724, 786, 670, 892, 289, 86, 195, 18, 537, 760, 790, 982, 462, 304, 18, 104,
    543, 935, 963, 916, 442, 339, 600, 917, 550, 946, 438, 105, 423, 289, 463, 819,
    774, 1002, 557, 216, 229, 152, 509, 940, 993, 912, 533, 105, 63, 164, 697, 900,
    313, 254, 289, 139, 706, 905, 814, 988, 501, 255, 227, 54, 547, 711, 996, 925,
    493, 114, 80, 115, 570, 672, 431, 128, 489, 70, 605, 894, 604, 724, 549, 216,
    283, 65, 475, 795, 754, 820, 563, 97, 0, 29, 460, 903, 1003, 948,
  ])
}

///|
test "compound warp full pixels depth12 layout2 blend5 plane2" {
  av1_compound_warp_full_pixels(12, 2, 5, 2, [
    2129, 2434, 3648, 4095, 1956, 1689, 422, 21, 2812, 4095, 3579, 3961, 1289, 54,
    451, 562, 518, 3050, 4095, 3885, 3564, 1039, 0, 0, 0, 2434, 4095, 3796, 4095,
    1616, 0, 482, 3321, 3444, 4095, 1990, 905, 513, 0, 99, 4095, 3624, 4095, 1221,
    0, 315, 306, 305, 4095, 3833, 4095, 1600, 0, 93, 0, 0, 4095, 1931, 854, 683,
    0, 2098, 3234, 2866,
  ])
}
