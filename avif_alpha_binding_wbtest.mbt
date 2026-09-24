///|
/// Actual paired AVIF files from the monochrome reference corpus. Payloads are
/// original libaom output; the standards-compliant association is independently
/// decoded by libavif in generate-av1-monochrome-reference.py.
fn avif_alpha_binding_fixture(depth : Int) -> Array[Byte] {
  let rows = match depth {
    // tests/fixtures/av1-monochrome/color_alpha_8bit.avif
    8 =>
      [
        "0000001c667479706176696600000000617669666d6966316d6961660000019a6d657461000000000000003568646c72000000000000000070696374",
        "000000000000000000000000506978656c466f726765207265666572656e6365000000000e7069746d0000000000010000002c696c6f630000000044",
        "000002000100000001000001be000001c00002000000010000037e000001040000004269696e660000000000020000001a696e666502000000000100",
        "0061763031436f6c6f72000000001a696e6665020000010002000061763031416c70686100000000c3697072700000009d6970636f00000014697370",
        "65000000000000004000000040000000107069786900000000030808080000000c6176314381000c0000000013636f6c726e636c7800020002000200",
        "0000000e706978690000000001080000000c6176314381001c0000000038617578430000000075726e3a6d7065673a6d706567423a636963703a7379",
        "7374656d733a617578696c696172793a616c706861000000001e69706d61000000000000000200010401028304000204010586870000001a69726566",
        "000000000000000e6175786c000200010001000002cc6d6461740a0618157ffc200832b50317800000483900d82d3bdbcab9de0eb1a929ab70fc38c9",
        "742e24d03268e6495cef4c3dd4ffba378f1572e11aa815510acfc517492ab3ad32877d96e8812a9f1d5dd56c546e91613b486d181acef50e437026d6",
        "601c2d771ddcd457c5186bfd67bf98d6fc2dae7d57cb57ea626b959df79282ca52f00a06874f45b5e73ffbbd3a218bdab0fbf35f77fc33e0ca5982f0",
        "1e71a818ce0f5d4cbd46d73aa367f1496c68d05993bf8c1ccf12f3826f839552162690e612a7ad51f5689df70413e20889d4b48b758f0fbffb28ee65",
        "b831abf9065c58ea35051102ca1329055202f1c53871f5b8c3fcd56d42fc6502a96cbd90d41e784dad0be9247cecfe40a44150e4f11d432526aa379a",
        "bca6e1c9de58e129b0bae0b1de4ce5d26074ca168a5b7b5257ca9953025758c0433abbe9486fd9f14fb93559afcb352192371699557174c24e81bdca",
        "017523d33112a9f85d70d804c7dd8297510cd70d189a2e14526724def2a31565e7582e8a1553345d5bae4564c5ff2c6c2bc11a71a5c7e3c6ae419831",
        "7579d77cf63e31fe62798bbb4e558868c2034028ce86151880eeab9c608591893de359eebbeb60c075de50a745bffa77d54d723b98b70a0618157ffc",
        "054032f9011000daf67aca692b3592254de3f5950c8cae0db56deb8efb2e2032eb1b72310a150f083b1be57c8b0cc5767f552dd3d623d73e0813fa0e",
        "9a6d899acdeb0cda53fe3e95191e1514d7e7ab4e6fde83b89b4fa645a9838c86ace9d667719760c8a4426aeb0ec39161638ab105f2310f8ef2624666",
        "e9d52676be23487c3ee051677f5dd49c1c2e68fc957b5859afdf60969a004fc9ca6c77d447a5c1724319cf95bd472b4c155c3d48fe36590cbc1873e7",
        "db871a8254a8504706be09218318080be3ec9e33024f46088a001d4eb79dc1cf668cba00d2a186fcb63baebf69c9411530824717274c3a00dfdb9a64",
        "9de614925f8da07c12e229ba2f29",
      ]
    // tests/fixtures/av1-monochrome/color_alpha_10bit.avif
    10 =>
      [
        "0000001c667479706176696600000000617669666d6966316d6961660000019a6d657461000000000000003568646c72000000000000000070696374",
        "000000000000000000000000506978656c466f726765207265666572656e6365000000000e7069746d0000000000010000002c696c6f630000000044",
        "000002000100000001000001be0000019f0002000000010000035d000001b40000004269696e660000000000020000001a696e666502000000000100",
        "0061763031436f6c6f72000000001a696e6665020000010002000061763031416c70686100000000c3697072700000009d6970636f00000014697370",
        "65000000000000004000000040000000107069786900000000030a0a0a0000000c6176314381004c0000000013636f6c726e636c7800020002000200",
        "0000000e7069786900000000010a0000000c6176314381005c0000000038617578430000000075726e3a6d7065673a6d706567423a636963703a7379",
        "7374656d733a617578696c696172793a616c706861000000001e69706d61000000000000000200010401028304000204010586870000001a69726566",
        "000000000000000e6175786c0002000100010000035b6d6461740a0618157ffc280832940317800000487180d82d3bdbca6ce95bcca8f481c9623fc3",
        "274631ab4b7943739a03b62864e714b166144027ab63af6bfd923df8d4dd1657c0b7772623b825ab1401ac57cba564adab69da1e62f16108773cd1bf",
        "5f1f5af2086328b6607a15bd4b5da685307026cc1dfd527626a8276475772311fe612772811e74daaed91a7b4a492911174a26825d35b979282ae6ed",
        "048130d19cc10d1bd5b2c7861ce15c0eedf893f90c58fd296a243d0e843a4ce41e1015b3d9fc57c923dc8c92d35b3b8d59cd200618eddc3273d0aa8e",
        "ce2ff8f91542b4c3b2dce7ac77478d60ca4a2b377707e976e4cba65eafa9fd948e4d4a9ca8b6d36f453780e144b8fa562acb6c5fbba98c2de4ba14a1",
        "bb31ab077ceedcf0d27ad1b8a4583c558d14e2b94f6b40d032120c351fd998ea19ac1e563f820058d823e4cfe7d6988d2f677c1ddcc96da5f5badb79",
        "e2d0463258ec4daa9a05fde3ca12ce8cbd2718ce5e463fa80fbcf8a17bb1317fff7ea50a262405b8374e18090d482f455715b6c71920c7a35832854e",
        "58a9d9c6a6be8b3b277c33866abaa7e7f7a9eb6f800a0618157ffc0d4032a9031000daf67cfcc03e6cfd1c68c8b3c226158a0d65c26ddf9ffbdf03cd",
        "c3110faa14d8a04307c9b96b0867bf7749560f30c07ed20bfec246d16f9457b920b334ac23d6c7046546f91a513574040e231cc32fa221a6ff586e32",
        "2a30f06827c100f1a9fcc386f7fbea6189a94908414883749d64b7c42a9018b4954714538f18f9770edf289c917b1a16c5cc572ef9fa2b0675e659a1",
        "a1736608ca6eeed1064541495b0c22c2e3440a1ee0867901500198d42de430ed7efc98736180c24e39c127439e86df5fc71621185bceb7c3bb3ee81b",
        "ad940b0db981175b5277b6cde0221e81778a555e0adc7d75a97a9e1a3e3922dff9bbf58d62416f081680e09be70ecdcef55cdb510cff26572ccceb3a",
        "113ea7d903513ad8bf8a0f7c736ccb45b4f31a9bf72c50a09f9b645f09663eeedbae629622c58f7176a905cdad14350ba81450bd095d17b409a7955b",
        "8c37b55ac6b8bdf1f9c692a8e41e83f5de8a5ab96942380611bfa5cbfb30687e1d30915c8358e9bdd55da749133997d43a7096533d14340c76e9ca54",
        "ad88e450b4d96a84f598b5b3cc97b26590f5e58558b157290906591dd49691c32f68963cc0",
      ]
    // tests/fixtures/av1-monochrome/color_alpha_12bit.avif
    12 =>
      [
        "0000001c667479706176696600000000617669666d6966316d6961660000019a6d657461000000000000003568646c72000000000000000070696374",
        "000000000000000000000000506978656c466f726765207265666572656e6365000000000e7069746d0000000000010000002c696c6f630000000044",
        "000002000100000001000001be000000c500020000000100000283000001bc0000004269696e660000000000020000001a696e666502000000000100",
        "0061763031436f6c6f72000000001a696e6665020000010002000061763031416c70686100000000c3697072700000009d6970636f00000014697370",
        "65000000000000004000000040000000107069786900000000030c0c0c0000000c6176314381406c0000000013636f6c726e636c7800020002000200",
        "0000000e7069786900000000010c0000000c6176314381407c0000000038617578430000000075726e3a6d7065673a6d706567423a636963703a7379",
        "7374656d733a617578696c696172793a616c706861000000001e69706d61000000000000000200010401028304000204010586870000001a69726566",
        "000000000000000e6175786c000200010001000002896d6461740a0658157ffc2c6132ba0117800000482080d80e00b5ca1baf11ac3829df88050973",
        "8cb4683aa3129cf11bec6d5206c0bfddf25b2e90cf451f21f4b800aef4dac5eabf2ac9d2ea901b5b10179ccc83a4b48ea19e9b88ecf69a15bae1ef3a",
        "76fcc20ff78b5cac8319de97cf43bfc5612d87c6b5b2b053e79a6fbf4cd5d0758c0c302af94c2ea3f05506b5a635b13e3d1b52239429cdcf73508de3",
        "c721706abb0aa9ad3ba5da4733ae5bd95d1ea11b2f417f14ae25fd265b80ea3b6c61a4955f9b38379577160a0658157ffc0ea032b1031000daf67d01",
        "77de225c49b32fbe04c0595fbbeb533f45b31052d8aeb88070ab901ffdb85dad67003dbfcc2441474bb2e284b4776735e670baf97ddcb1723bcac887",
        "e7e95b2e6cd4c0d4c5d8d3e072bf0a403232b9a144de654274735bf251e6984e25458b0ac09d617df75ce06db929e8fc81f39f8a53a2a21ceff0de84",
        "1047b1307eb2ed13e7552df11b7f53c5c018afa42b98b17d63dea1d3305be003205dd1cf631420fd28547f02f47cdfa9c023fe719d385b107f5aaa45",
        "21c6560b1ff2b7691e3f43172ee117947d3bea92106ebc96becc91df2cae57be5667bdd7e575dc529b6dcb21a2769a74ddc28d39036951803039bbfa",
        "760a6af7369bdaa494b50f13ad50a49fc7e6fa6e7672b0cf360f8a640abe1d6a7a646f1c9fc393e9f42f488e0723d9a37138424417e0b9c8b7a1a18d",
        "1009156e2fc13bd0becb4dcdccb9b61cb2829299287789b6c7761404c0bd7a215e259bcb5ec011e288650714b7dc48c40753837da616b9a8eb98e49c",
        "ee7946d1b8f315637a0e2f0ba5cc6bfbf3ec4b1206695638ab46a6968847e171789810176385afdbe166d16225cbef6dc51b8d5bd96ce5b97eb1e0af",
        "8b449173406f40",
      ]
    _ => []
  }
  let data : Array[Byte] = []
  for row in rows {
    let chars = row.to_array()
    for i in 0..<(chars.length() / 2) {
      let hi = chars[i * 2].to_int()
      let lo = chars[i * 2 + 1].to_int()
      data.push(
        (((if hi >= 97 { hi - 87 } else { hi - 48 }) << 4) |
        (if lo >= 97 { lo - 87 } else { lo - 48 })).to_byte(),
      )
    }
  }
  data
}

///|
fn avif_alpha_binding_put32(
  data : Array[Byte],
  offset : Int,
  value : Int,
) -> Unit {
  for i in 0..<4 {
    data[offset + i] = (value >> (24 - 8 * i)).to_byte()
  }
}

///|
/// Give alpha an independent ispe while preserving the original two AV1 payloads.
/// The source 8-bit fixture shares property 1 (64x64) between color and alpha.
fn avif_alpha_binding_shape(width : Int, height : Int) -> Array[Byte] {
  let original = avif_alpha_binding_fixture(8)
  let data : Array[Byte] = []
  for i in 0..<382 {
    data.push(original[i])
  }
  for i in 233..<253 {
    data.push(original[i])
  }
  for i in 382..<original.length() {
    data.push(original[i])
  }
  avif_alpha_binding_put32(data, 28, 430) // meta +20
  avif_alpha_binding_put32(data, 217, 215) // iprp +20
  avif_alpha_binding_put32(data, 225, 177) // ipco +20
  avif_alpha_binding_put32(data, 129, 466) // primary extent moved +20
  avif_alpha_binding_put32(data, 143, 914) // alpha extent moved +20
  avif_alpha_binding_put32(data, 394, width) // new ispe width
  avif_alpha_binding_put32(data, 398, height) // new ispe height
  data[428] = b'\x08' // alpha now associates independent property 8
  data
}

///|
test "actual AVIF alpha association is reported for 8 10 and 12 bits" {
  for depth in [8, 10, 12] {
    let data = avif_alpha_binding_fixture(depth)
    let container = avif_container_parse(data).unwrap()
    assert_true(container.has_alpha)
    let alpha = avif_alpha_item_descriptor(data).unwrap()
    assert_eq(
      (alpha.item_id, alpha.width, alpha.height, alpha.bit_depth),
      (2, 64, 64, depth),
    )
    assert_eq(avif_stage1_input(data).unwrap().bit_depth, depth)
    assert_true(avif_decode_rgba(data) is Some(_))
  }
}

///|
test "AVIF alpha references must point from auxiliary to current primary" {
  for changed in [0, 1] {
    let data = avif_alpha_binding_fixture(8)
    if changed == 0 {
      data[433] = b'\x01'
      data[437] = b'\x02'
    } else {
      data[437] = b'\x02'
    }
    assert_true(avif_alpha_item_descriptor(data) is None)
    assert_false(avif_container_parse(data).unwrap().has_alpha)
    let image = avif_decode_rgba(data).unwrap()
    assert_eq(image.get_pixel(0, 0).3, b'\xFF')
  }
}

///|
test "a depth auxiliary is not an alpha association" {
  let data = avif_alpha_binding_fixture(8)
  for i in 0..<5 {
    data[376 + i] = [b'd', b'e', b'p', b't', b'h'][i]
  }
  assert_true(avif_alpha_item_descriptor(data) is None)
  assert_false(avif_container_parse(data).unwrap().has_alpha)
  assert_eq(avif_decode_rgba(data).unwrap().get_pixel(0, 0).3, b'\xFF')
}

///|
test "an out of bounds selected alpha extent cannot become opaque" {
  let data = avif_alpha_binding_fixture(8)
  // Only alpha's extent changes: the original primary remains [446, 894).
  avif_alpha_binding_put32(data, 143, data.length())
  assert_true(avif_alpha_item_descriptor(data) is None)
  assert_true(avif_decode_rgba(data) is None)
}

///|
test "selected alpha requires an AV1 item and valid configuration" {
  for mutation in [0, 1, 2, 3] {
    let data = avif_alpha_binding_fixture(8)
    if mutation == 0 {
      // The alpha infe item_type is av01 at byte 207.
      for i in 0..<4 {
        data[207 + i] = [b'a', b'u', b'x', b'l'][i]
      }
    } else if mutation == 1 {
      for i in 0..<4 {
        data[318 + i] = [b'f', b'r', b'e', b'e'][i]
      }
    } else if mutation == 2 {
      data[334] = b'\x01' // auxC must be version zero.
    } else {
      data[381] = b'x' // aux_type must be NUL-terminated within auxC.
    }
    assert_true(avif_alpha_item_descriptor(data) is None)
    assert_true(avif_decode_rgba(data) is None)
  }
}

///|
test "alpha geometry must match width and height not just pixel count" {
  let valid = avif_alpha_binding_shape(64, 64)
  assert_true(avif_alpha_item_descriptor(valid) is Some(_))
  assert_true(avif_decode_rgba(valid) is Some(_))
  for shape in [(32, 128), (128, 32)] {
    let data = avif_alpha_binding_shape(shape.0, shape.1)
    assert_true(avif_alpha_item_descriptor(data) is None)
    assert_true(avif_decode_rgba(data) is None)
  }
}

///|
test "AVIF alpha and primary must have the same encoded bit depth" {
  let data = avif_alpha_binding_fixture(8)
  data[324] = (data[324].to_int() | 0x40).to_byte()
  assert_true(avif_alpha_item_descriptor(data) is None)
  assert_true(avif_decode_rgba(data) is None)
}

///|
fn avif_alpha_binding_number(
  out : Array[Byte],
  value : Int,
  width : Int,
) -> Unit {
  for i in 0..<width {
    out.push((value >> (8 * (width - i - 1))).to_byte())
  }
}

///|
fn avif_alpha_binding_join(parts : Array[Array[Byte]]) -> Array[Byte] {
  let out : Array[Byte] = []
  for part in parts {
    for value in part {
      out.push(value)
    }
  }
  out
}

///|
fn avif_alpha_binding_slice(
  data : Array[Byte],
  from : Int,
  to : Int,
) -> Array[Byte] {
  let out : Array[Byte] = []
  for i in from..<to {
    out.push(data[i])
  }
  out
}

///|
fn avif_alpha_binding_box(name : String, data : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = []
  avif_alpha_binding_number(out, data.length() + 8, 4)
  for char in name.to_array() {
    out.push(char.to_int().to_byte())
  }
  avif_alpha_binding_join([out, data])
}

///|
fn avif_alpha_binding_fullbox(
  name : String,
  version : Int,
  flags : Int,
  data : Array[Byte],
) -> Array[Byte] {
  let header : Array[Byte] = [version.to_byte()]
  avif_alpha_binding_number(header, flags, 3)
  avif_alpha_binding_box(name, avif_alpha_binding_join([header, data]))
}

///|
/// Normative remuxes of the original 8-bit pair, with both AV1 payloads intact.
/// Cases 0..3 were independently decoded using scalar libavif 0.11.1 and had
/// exactly the original RGBA. Cases 4..6 were rejected with BMFF parse error 9.
/// 0: iloc v1/idat; 1: wide associations; 2: 32-bit IDs; 3: both widths;
/// 4: 64-bit offset overflow; 5: 64-bit base overflow; 6: primary addition wrap.
fn avif_alpha_binding_extended(kind : Int) -> Array[Byte] {
  let source = avif_alpha_binding_fixture(8)
  let wide_ids = kind == 2 || kind == 3
  let wide_props = kind == 1 || kind == 3
  let id_width = if wide_ids { 4 } else { 2 }
  let version = if wide_ids { 1 } else { 0 }
  let ids = if wide_ids { [65537, 65538] } else { [1, 2] }
  let primary : Array[Byte] = []
  avif_alpha_binding_number(primary, ids[0], id_width)
  let pitm = avif_alpha_binding_fullbox("pitm", version, 0, primary)
  let info : Array[Byte] = [b'\x00', b'\x02']
  for index in 0..<2 {
    let entry : Array[Byte] = []
    avif_alpha_binding_number(entry, ids[index], id_width)
    avif_alpha_binding_number(entry, 0, 2)
    for char in (if index == 0 { "av01Color" } else { "av01Alpha" }).to_array() {
      entry.push(char.to_int().to_byte())
    }
    entry.push(b'\x00')
    let infe = avif_alpha_binding_fullbox(
      "infe",
      if wide_ids {
        3
      } else {
        2
      },
      index,
      entry,
    )
    for value in infe {
      info.push(value)
    }
  }
  let iinf = avif_alpha_binding_fullbox("iinf", 0, 0, info)
  let offset_width = if kind == 4 { 8 } else { 4 }
  let base_width = if kind == 5 { 8 } else if kind == 6 { 4 } else { 0 }
  let locations : Array[Byte] = [
    ((offset_width << 4) | 4).to_byte(),
    (base_width << 4).to_byte(),
  ]
  avif_alpha_binding_number(locations, 2, if wide_ids { 4 } else { 2 })
  for index in 0..<2 {
    avif_alpha_binding_number(locations, ids[index], id_width)
    avif_alpha_binding_number(locations, 1, 2) // construction_method low nibble
    avif_alpha_binding_number(locations, 0, 2) // data_reference_index
    if base_width == 8 {
      avif_alpha_binding_number(locations, if index == 1 { 1 } else { 0 }, 4)
      avif_alpha_binding_number(locations, 0, 4)
    } else if base_width == 4 {
      avif_alpha_binding_number(
        locations,
        if index == 0 {
          2147483647
        } else {
          0
        },
        4,
      )
    }
    avif_alpha_binding_number(locations, 1, 2) // extent_count
    if offset_width == 8 {
      avif_alpha_binding_number(locations, if index == 1 { 1 } else { 0 }, 4)
    }
    let offset = if kind == 6 && index == 0 {
      -2147483647
    } else if index == 0 {
      0
    } else {
      448
    }
    avif_alpha_binding_number(locations, offset, 4)
    avif_alpha_binding_number(locations, if index == 0 { 448 } else { 260 }, 4)
  }
  let iloc = avif_alpha_binding_fullbox(
    "iloc",
    if wide_ids {
      2
    } else {
      1
    },
    0,
    locations,
  )
  let associations : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x02']
  for index in 0..<2 {
    avif_alpha_binding_number(associations, ids[index], id_width)
    associations.push(b'\x04')
    for
      property in (if index == 0 {
        [1, 2, 0x83, 4]
      } else {
        [1, 5, 0x86, 0x87]
      }) {
      if wide_props {
        avif_alpha_binding_number(
          associations,
          (property & 0x7F) | (if (property & 0x80) != 0 { 0x8000 } else { 0 }),
          2,
        )
      } else {
        associations.push(property.to_byte())
      }
    }
  }
  let ipma = avif_alpha_binding_fullbox(
    "ipma",
    version,
    if wide_props {
      1
    } else {
      0
    },
    associations,
  )
  let iprp = avif_alpha_binding_box(
    "iprp",
    avif_alpha_binding_join([avif_alpha_binding_slice(source, 225, 382), ipma]),
  )
  let reference : Array[Byte] = []
  avif_alpha_binding_number(reference, ids[1], id_width)
  avif_alpha_binding_number(reference, 1, 2)
  avif_alpha_binding_number(reference, ids[0], id_width)
  let iref = avif_alpha_binding_fullbox(
    "iref",
    version,
    0,
    avif_alpha_binding_box("auxl", reference),
  )
  let idat = avif_alpha_binding_box(
    "idat",
    avif_alpha_binding_slice(source, 446, source.length()),
  )
  avif_alpha_binding_join([
    avif_alpha_binding_slice(source, 0, 28),
    avif_alpha_binding_fullbox(
      "meta",
      0,
      0,
      avif_alpha_binding_join([
        avif_alpha_binding_slice(source, 40, 93),
        pitm,
        iloc,
        iinf,
        iprp,
        iref,
        idat,
      ]),
    ),
  ])
}

///|
test "alpha association supports normative idat iloc and ipma field widths" {
  let original = avif_alpha_binding_fixture(8)
  let color_payload = avif_container_parse(original).unwrap().payload
  let alpha_payload = avif_alpha_item_payload(original).unwrap()
  let reference = avif_decode_rgba(original).unwrap()
  for kind in 0..<4 {
    let data = avif_alpha_binding_extended(kind)
    let container = avif_container_parse(data).unwrap()
    let descriptor = avif_alpha_item_descriptor(data).unwrap()
    assert_true(container.has_alpha)
    assert_eq(container.payload, color_payload)
    assert_eq(avif_alpha_item_payload(data).unwrap(), alpha_payload)
    assert_eq(descriptor.item_id, if kind < 2 { 2 } else { 65538 })
    assert_eq(descriptor.extents[0].construction_method, 1)
    let image = avif_decode_rgba(data).unwrap()
    for y in 0..<64 {
      for x in 0..<64 {
        assert_eq(image.get_pixel(x, y), reference.get_pixel(x, y))
      }
    }
  }
}

///|
test "AVIF item offsets cannot wrap into valid primary or alpha data" {
  for kind in 4..<7 {
    let data = avif_alpha_binding_extended(kind)
    assert_true(avif_container_parse(data) is None)
    assert_true(avif_decode_rgba(data) is None)
  }
}
