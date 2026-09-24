///|
test "image format detection covers modern containers" {
  assert_true(
    detect_image_format([b'\xFF', b'\xD8', b'\xFF', b'\xE0']) is Some(Jpeg),
  )
  assert_true(
    detect_image_format([
      b'R', b'I', b'F', b'F', b'\x00', b'\x00', b'\x00', b'\x00', b'W', b'E', b'B',
      b'P',
    ])
    is Some(Webp),
  )
  assert_true(
    detect_image_format(formats_test_ftyp(0x61766966, [])) is Some(Avif),
  )
  assert_true(detect_image_format([b'I', b'I', b'*', b'\x00']) is Some(Tiff))
}

///|
test "metadata reads png and gif dimensions" {
  let png : Array[Byte] = [
    b'\x89', b'P', b'N', b'G', b'\x0D', b'\x0A', b'\x1A', b'\x0A', b'\x00', b'\x00',
    b'\x00', b'\x0D', b'I', b'H', b'D', b'R', b'\x00', b'\x00', b'\x00', b'\x02',
    b'\x00', b'\x00', b'\x00', b'\x03',
  ]
  let p = image_metadata(png).unwrap()
  assert_eq(p.format.name(), "png")
  assert_eq(p.width, 2)
  assert_eq(p.height, 3)
  let gif : Array[Byte] = [
    b'G', b'I', b'F', b'8', b'9', b'a', b'\x04', b'\x00', b'\x05', b'\x00',
  ]
  let g = image_metadata(gif).unwrap()
  assert_eq(g.width, 4)
  assert_eq(g.height, 5)
  assert_false(g.animated)
}

///|
fn formats_test_join(parts : Array[Array[Byte]]) -> Array[Byte] {
  let result : Array[Byte] = []
  for part in parts {
    for byte in part {
      result.push(byte)
    }
  }
  result
}

///|
fn formats_test_uint(value : Int, width : Int) -> Array[Byte] {
  let result : Array[Byte] = []
  for i in 0..<width {
    result.push(((value >> ((width - i - 1) * 8)) & 255).to_byte())
  }
  result
}

///|
/// FourCC values are written as big-endian integers; these fixtures contain
/// container metadata only, with no compressed AV1 payload.
fn formats_test_box(kind : Int, payload : Array[Byte]) -> Array[Byte] {
  formats_test_join([
    formats_test_uint(payload.length() + 8, 4),
    formats_test_uint(kind, 4),
    payload,
  ])
}

///|
fn formats_test_ftyp(major : Int, compatible : Array[Int]) -> Array[Byte] {
  let payload = formats_test_join([
    formats_test_uint(major, 4),
    formats_test_uint(0, 4), // minor_version is not a compatible brand.
  ])
  for brand in compatible {
    for byte in formats_test_uint(brand, 4) {
      payload.push(byte)
    }
  }
  formats_test_box(0x66747970, payload) // ftyp
}

///|
fn formats_test_pitm(id : Int, version : Int) -> Array[Byte] {
  formats_test_box(
    0x7069746D,
    formats_test_join([
      formats_test_uint(version << 24, 4),
      formats_test_uint(id, if version == 0 { 2 } else { 4 }),
    ]),
  )
}

///|
fn formats_test_ispe(width : Int, height : Int) -> Array[Byte] {
  formats_test_box(
    0x69737065,
    formats_test_join([
      formats_test_uint(0, 4),
      formats_test_uint(width, 4),
      formats_test_uint(height, 4),
    ]),
  )
}

///|
fn formats_test_ipma(
  entries : Array[(Int, Array[Int])],
  version : Int,
  wide_properties : Bool,
) -> Array[Byte] {
  let parts = [
    formats_test_uint(
      (version << 24) | (if wide_properties { 1 } else { 0 }),
      4,
    ),
    formats_test_uint(entries.length(), 4),
  ]
  for entry in entries {
    let (id, associations) = entry
    parts.push(formats_test_uint(id, if version == 0 { 2 } else { 4 }))
    parts.push(formats_test_uint(associations.length(), 1))
    for association in associations {
      parts.push(
        formats_test_uint(association, if wide_properties { 2 } else { 1 }),
      )
    }
  }
  formats_test_box(0x69706D61, formats_test_join(parts)) // ipma
}

///|
fn formats_test_iprp(
  properties : Array[Array[Byte]],
  associations : Array[Byte],
) -> Array[Byte] {
  formats_test_box(
    0x69707270,
    formats_test_join([
      formats_test_box(0x6970636F, formats_test_join(properties)), // ipco
      associations,
    ]),
  )
}

///|
fn formats_test_avif(children : Array[Array[Byte]]) -> Array[Byte] {
  formats_test_join([
    formats_test_ftyp(0x61766966, []), // avif
    formats_test_box(
      0x6D657461,
      formats_test_join([
        formats_test_uint(0, 4), // meta FullBox version and flags.
        formats_test_join(children),
      ]),
    ),
  ])
}

///|
test "avif detection requires complete ftyp and explicit avif brands" {
  for brand in [0x61766966, 0x61766973] { // avif, avis
    assert_true(detect_image_format(formats_test_ftyp(brand, [])) is Some(Avif))
    assert_true(
      detect_image_format(formats_test_ftyp(0x6D696631, [brand])) is Some(Avif),
    )
  }
  for brand in [0x6D696631, 0x68656963, 0x68656978] { // mif1, heic, heix
    assert_true(detect_image_format(formats_test_ftyp(brand, [])) is None)
  }
  let minor_is_avif = formats_test_box(
    0x66747970,
    formats_test_join([
      formats_test_uint(0x6D696631, 4),
      formats_test_uint(0x61766966, 4),
    ]),
  )
  assert_true(detect_image_format(minor_is_avif) is None)
  let missing_minor = formats_test_box(
    0x66747970,
    formats_test_uint(0x61766966, 4),
  )
  assert_true(detect_image_format(missing_minor) is None)
  let truncated = formats_test_ftyp(0x61766966, [])
  truncated[3] = b'\x18'
  assert_true(detect_image_format(truncated) is None)
  let brand_outside_ftyp = formats_test_join([
    formats_test_ftyp(0x6D696631, []),
    formats_test_box(0x66726565, formats_test_uint(0x61766966, 4)),
  ])
  assert_true(detect_image_format(brand_outside_ftyp) is None)
}

///|
test "avif metadata selects the primary item rather than auxiliary dimensions" {
  let data = formats_test_avif([
    formats_test_pitm(7, 0),
    formats_test_iprp(
      [
        formats_test_ispe(16, 16), // A tile, thumbnail, or alpha item comes first.
        formats_test_box(0x61763143, [b'\x81', b'\x00', b'\x00', b'\x00']), // av1C
        formats_test_ispe(640, 360),
      ],
      formats_test_ipma([(2, [1]), (7, [0, 2, 0x83])], 0, false),
    ),
  ])
  let metadata = image_metadata(data).unwrap()
  assert_eq(metadata.format.name(), "avif")
  assert_eq(metadata.width, 640)
  assert_eq(metadata.height, 360)
  assert_false(metadata.animated)
}

///|
test "avif metadata supports reordered boxes and wide item and property references" {
  let properties : Array[Array[Byte]] = []
  for _ in 0..<128 {
    properties.push(formats_test_box(0x66726565, [])) // Unknown properties retain indices.
  }
  properties.push(formats_test_ispe(1920, 1080))
  let data = formats_test_avif([
    formats_test_box(
      0x69707270,
      formats_test_join([
        formats_test_ipma([(70000, [0x8081])], 1, true), // Essential property 129.
        formats_test_box(0x6970636F, formats_test_join(properties)),
      ]),
    ),
    formats_test_pitm(70000, 1),
  ])
  let metadata = image_metadata(data).unwrap()
  assert_eq(metadata.width, 1920)
  assert_eq(metadata.height, 1080)
}

///|
test "avif metadata derives animation from major or compatible avis brands" {
  let meta = formats_test_box(
    0x6D657461,
    formats_test_join([
      formats_test_uint(0, 4),
      formats_test_pitm(1, 0),
      formats_test_iprp(
        [formats_test_ispe(8, 6)],
        formats_test_ipma([(1, [1])], 0, false),
      ),
    ]),
  )
  for
    ftyp in [
      formats_test_ftyp(0x61766973, []),
      formats_test_ftyp(0x61766966, [0x61766973]),
      formats_test_ftyp(0x6D696631, [0x61766973]),
    ] {
    let metadata = image_metadata(formats_test_join([ftyp, meta])).unwrap()
    assert_true(metadata.animated)
    assert_eq(metadata.width, 8)
    assert_eq(metadata.height, 6)
  }
}

///|
test "avif metadata accepts extended sizes and boxes extending to their parent end" {
  let ipco_to_end = formats_test_join([
    formats_test_uint(0, 4),
    formats_test_uint(0x6970636F, 4),
    formats_test_ispe(321, 123),
  ])
  let iprp_to_end = formats_test_join([
    formats_test_uint(0, 4),
    formats_test_uint(0x69707270, 4),
    formats_test_ipma([(1, [1])], 0, false),
    ipco_to_end,
  ])
  let payload = formats_test_join([
    formats_test_uint(0, 4),
    formats_test_pitm(1, 0),
    iprp_to_end,
  ])
  let meta64 = formats_test_join([
    formats_test_uint(1, 4),
    formats_test_uint(0x6D657461, 4),
    formats_test_uint(0, 4),
    formats_test_uint(payload.length() + 16, 4),
    payload,
  ])
  let ftyp64 = formats_test_join([
    formats_test_uint(1, 4),
    formats_test_uint(0x66747970, 4),
    formats_test_uint(0, 4),
    formats_test_uint(24, 4),
    formats_test_uint(0x61766966, 4),
    formats_test_uint(0, 4),
  ])
  let metadata = image_metadata(formats_test_join([ftyp64, meta64])).unwrap()
  assert_eq(metadata.width, 321)
  assert_eq(metadata.height, 123)
}

///|
test "avif metadata rejects missing or ambiguous primary property associations" {
  let properties = [formats_test_ispe(100, 50), formats_test_ispe(20, 10)]
  let valid_iprp = formats_test_iprp(
    properties,
    formats_test_ipma([(1, [1])], 0, false),
  )
  assert_true(image_metadata(formats_test_avif([valid_iprp])) is None)
  assert_true(
    image_metadata(formats_test_avif([formats_test_pitm(1, 0)])) is None,
  )
  for
    entries in [
      [(2, [1])], // Only another item is associated.
      [(1, [])],
      [(1, [0])], // Property index zero does not select a property.
      [(1, [3])], // Out-of-range property index.
      [(1, [1, 2])], // Two dimensions for the primary item are ambiguous.
    ] {
    let data = formats_test_avif([
      formats_test_pitm(1, 0),
      formats_test_iprp(properties, formats_test_ipma(entries, 0, false)),
    ])
    assert_true(image_metadata(data) is None)
  }
  let no_ispe = formats_test_avif([
    formats_test_pitm(1, 0),
    formats_test_iprp(
      [formats_test_box(0x66726565, [])],
      formats_test_ipma([(1, [1])], 0, false),
    ),
  ])
  assert_true(image_metadata(no_ispe) is None)
}

///|
test "avif metadata rejects invalid dimensions and unsupported fullbox versions" {
  for dimensions in [(0, 8), (8, 0), (-1, 8), (8, -1)] {
    let (width, height) = dimensions
    assert_true(
      image_metadata(
        formats_test_avif([
          formats_test_pitm(1, 0),
          formats_test_iprp(
            [formats_test_ispe(width, height)],
            formats_test_ipma([(1, [1])], 0, false),
          ),
        ]),
      )
      is None,
    )
  }
  let max_dimensions = image_metadata(
    formats_test_avif([
      formats_test_pitm(1, 0),
      formats_test_iprp(
        [formats_test_ispe(2147483647, 1)],
        formats_test_ipma([(1, [1])], 0, false),
      ),
    ]),
  ).unwrap()
  assert_eq(max_dimensions.width, 2147483647)
  let bad_ispe = formats_test_ispe(8, 6)
  bad_ispe[8] = b'\x01'
  for
    children in [
      [
        formats_test_pitm(1, 2),
        formats_test_iprp(
          [formats_test_ispe(8, 6)],
          formats_test_ipma([(1, [1])], 0, false),
        ),
      ],
      [
        formats_test_pitm(1, 0),
        formats_test_iprp(
          [formats_test_ispe(8, 6)],
          formats_test_ipma([(1, [1])], 2, false),
        ),
      ],
      [
        formats_test_pitm(1, 0),
        formats_test_iprp([bad_ispe], formats_test_ipma([(1, [1])], 0, false)),
      ],
    ] {
    assert_true(image_metadata(formats_test_avif(children)) is None)
  }
  for version_flags in [0x01000000, 1] {
    let data = formats_test_join([
      formats_test_ftyp(0x61766966, []),
      formats_test_box(
        0x6D657461,
        formats_test_join([
          formats_test_uint(version_flags, 4),
          formats_test_pitm(1, 0),
          formats_test_iprp(
            [formats_test_ispe(8, 6)],
            formats_test_ipma([(1, [1])], 0, false),
          ),
        ]),
      ),
    ])
    assert_true(image_metadata(data) is None)
  }
}

///|
test "avif metadata rejects truncated boxes and properties outside parent boundaries" {
  let valid = formats_test_avif([
    formats_test_pitm(1, 0),
    formats_test_iprp(
      [formats_test_ispe(8, 6)],
      formats_test_ipma([(1, [1])], 0, false),
    ),
  ])
  for length in 0..<valid.length() {
    let truncated : Array[Byte] = []
    for i in 0..<length {
      truncated.push(valid[i])
    }
    assert_true(image_metadata(truncated) is None)
  }
  let escaped_property = formats_test_ispe(8, 6)
  escaped_property[3] = b'\x18' // ispe exceeds ipco even though later file bytes exist.
  assert_true(
    image_metadata(
      formats_test_avif([
        formats_test_pitm(1, 0),
        formats_test_iprp(
          [escaped_property],
          formats_test_ipma([(1, [1])], 0, false),
        ),
      ]),
    )
    is None,
  )
  for
    malformed in [
      formats_test_join([
        formats_test_uint(7, 4),
        formats_test_uint(0x66726565, 4),
      ]),
      formats_test_join([
        formats_test_uint(-1, 4),
        formats_test_uint(0x66726565, 4),
      ]),
      formats_test_join([
        formats_test_uint(1, 4),
        formats_test_uint(0x66726565, 4),
        formats_test_uint(1, 4),
        formats_test_uint(16, 4),
      ]),
    ] {
    assert_true(
      image_metadata(
        formats_test_avif([
          formats_test_pitm(1, 0),
          malformed,
          formats_test_iprp(
            [formats_test_ispe(8, 6)],
            formats_test_ipma([(1, [1])], 0, false),
          ),
        ]),
      )
      is None,
    )
  }
  let unassociated_payload = formats_test_avif([
    formats_test_pitm(1, 0),
    formats_test_box(0x66726565, formats_test_ispe(8, 6)),
  ])
  assert_true(image_metadata(unassociated_payload) is None)
}
