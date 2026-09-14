/// Metadata boundary tests use real libaom AVIF fixtures produced by
/// generate-av1-monochrome-reference.py and generate-av1-cdef-frame-reference.py.
/// Only av1C declaration bits are mutated; item payloads and box extents stay intact.

///|
fn av1_monochrome_metadata_fixture(kind : Int) -> Array[Byte] {
  let rows = match kind {
    // tests/fixtures/av1-monochrome/mono_64x64_1tile_8bit_q30.avif
    0 =>
      [
        "00000020667479706176696600000000617669666d6966316d6961664d413141000000f76d657461000000000000002f",
        "68646c720000000000000000706963740000000000000000000000005069637475726548616e646c6572000000000e70",
        "69746d0000000000010000001e696c6f6300000000440000010001000000010000011f000001660000002869696e6600",
        "00000000010000001a696e6665020000000001000061763031436f6c6f72000000006869707270000000496970636f00",
        "000014697370650000000000000040000000400000000e706978690000000001080000000c6176314381001c00000000",
        "13636f6c726e636c78000200020002800000001769706d610000000000000001000104010283040000016e6d6461740a",
        "0618157ffc254032db021780000120e0d894038ffc62ee326b0d85c9755e99a47519485947031629e3a2416b76cd9f12",
        "c30ea25f6cd57ceb4ca1df681fd274cb39324415d83e3e0142421a460b7a509abd70dcba647be92c245ed52d2891b343",
        "ef9cc24e35acb94d1bd789f18c4487bea082d3d1cc89fa27e5d46f9231650f8690353e6e1bf3f1123053214e8795f4ce",
        "1f2d83116ddcd9711caeafc24c189caa56a43e73a66d8ca63c628c6425d0a25aeae5c824591ac19824f948781d6244b9",
        "8e760f7908ecca6e06fd090cf86433c6432d261924f3744c00bbcd5e5370e4ef2c7094d85dffc3a24b883a0baaa6e24b",
        "727b288f3ea1a8e9220ef87e9a118fcf21f880c1cedcd3b87a1d4267cb68be4d302da2c9a9c431ae5d91bf31568bb25f",
        "9c68806e0b417e943e3d7f5864dffaa0bf4cc906650ea930480a8d22ae9a75f0e97c533f26dde67ef03e1c3705b864a5",
        "1cdb1d8f5c65e88fcc34e3dbd36b54b80338cd0dc0",
      ]
    // tests/fixtures/av1-monochrome/mono_64x64_1tile_10bit_q0.avif
    1 =>
      [
        "00000020667479706176696600000000617669666d6966316d6961664d413141000000f76d657461000000000000002f",
        "68646c720000000000000000706963740000000000000000000000005069637475726548616e646c6572000000000e70",
        "69746d0000000000010000001e696c6f6300000000440000010001000000010000011f000001b40000002869696e6600",
        "00000000010000001a696e6665020000000001000061763031436f6c6f72000000006869707270000000496970636f00",
        "000014697370650000000000000040000000400000000e7069786900000000010a0000000c6176314381005c00000000",
        "13636f6c726e636c78000200020002800000001769706d61000000000000000100010401028304000001bc6d6461740a",
        "0618157ffc0d4032a9031000daf67cfcc03e6cfd1c68c8b3c226158a0d65c26ddf9ffbdf03cdc3110faa14d8a04307c9",
        "b96b0867bf7749560f30c07ed20bfec246d16f9457b920b334ac23d6c7046546f91a513574040e231cc32fa221a6ff58",
        "6e322a30f06827c100f1a9fcc386f7fbea6189a94908414883749d64b7c42a9018b4954714538f18f9770edf289c917b",
        "1a16c5cc572ef9fa2b0675e659a1a1736608ca6eeed1064541495b0c22c2e3440a1ee0867901500198d42de430ed7efc",
        "98736180c24e39c127439e86df5fc71621185bceb7c3bb3ee81bad940b0db981175b5277b6cde0221e81778a555e0adc",
        "7d75a97a9e1a3e3922dff9bbf58d62416f081680e09be70ecdcef55cdb510cff26572ccceb3a113ea7d903513ad8bf8a",
        "0f7c736ccb45b4f31a9bf72c50a09f9b645f09663eeedbae629622c58f7176a905cdad14350ba81450bd095d17b409a7",
        "955b8c37b55ac6b8bdf1f9c692a8e41e83f5de8a5ab96942380611bfa5cbfb30687e1d30915c8358e9bdd55da7491339",
        "97d43a7096533d14340c76e9ca54ad88e450b4d96a84f598b5b3cc97b26590f5e58558b157290906591dd49691c32f68",
        "963cc0",
      ]
    // tests/fixtures/av1-monochrome/mono_64x64_1tile_12bit_q0.avif
    2 =>
      [
        "0000001c667479706176696600000000617669666d6966316d696166000000f76d657461000000000000002f68646c72",
        "0000000000000000706963740000000000000000000000005069637475726548616e646c6572000000000e7069746d00",
        "00000000010000001e696c6f6300000000440000010001000000010000011b000001bc0000002869696e660000000000",
        "010000001a696e6665020000000001000061763031436f6c6f72000000006869707270000000496970636f0000001469",
        "7370650000000000000040000000400000000e7069786900000000010c0000000c6176314381407c0000000013636f6c",
        "726e636c78000200020002800000001769706d61000000000000000100010401028304000001c46d6461740a0658157f",
        "fc0ea032b1031000daf67d0177de225c49b32fbe04c0595fbbeb533f45b31052d8aeb88070ab901ffdb85dad67003dbf",
        "cc2441474bb2e284b4776735e670baf97ddcb1723bcac887e7e95b2e6cd4c0d4c5d8d3e072bf0a403232b9a144de6542",
        "74735bf251e6984e25458b0ac09d617df75ce06db929e8fc81f39f8a53a2a21ceff0de841047b1307eb2ed13e7552df1",
        "1b7f53c5c018afa42b98b17d63dea1d3305be003205dd1cf631420fd28547f02f47cdfa9c023fe719d385b107f5aaa45",
        "21c6560b1ff2b7691e3f43172ee117947d3bea92106ebc96becc91df2cae57be5667bdd7e575dc529b6dcb21a2769a74",
        "ddc28d39036951803039bbfa760a6af7369bdaa494b50f13ad50a49fc7e6fa6e7672b0cf360f8a640abe1d6a7a646f1c",
        "9fc393e9f42f488e0723d9a37138424417e0b9c8b7a1a18d1009156e2fc13bd0becb4dcdccb9b61cb2829299287789b6",
        "c7761404c0bd7a215e259bcb5ec011e288650714b7dc48c40753837da616b9a8eb98e49cee7946d1b8f315637a0e2f0b",
        "a5cc6bfbf3ec4b1206695638ab46a6968847e171789810176385afdbe166d16225cbef6dc51b8d5bd96ce5b97eb1e0af",
        "8b449173406f40",
      ]
    // tests/fixtures/av1-cdef-frame/cdef_64x64_1tile_8bit.avif
    3 =>
      [
        "00000020667479706176696600000000617669666d6966316d6961664d413142000000f96d657461000000000000002f",
        "68646c720000000000000000706963740000000000000000000000005069637475726548616e646c6572000000000e70",
        "69746d0000000000010000001e696c6f63000000004400000100010000000100000121000001c00000002869696e6600",
        "00000000010000001a696e6665020000000001000061763031436f6c6f72000000006a697072700000004b6970636f00",
        "00001469737065000000000000004000000040000000107069786900000000030808080000000c6176314381000c0000",
        "000013636f6c726e636c78000200020002000000001769706d61000000000000000100010401028304000001c86d6461",
        "740a0618157ffc200832b50317800000483900d82d3bdbcab9de0eb1a929ab70fc38c9742e24d03268e6495cef4c3dd4",
        "ffba378f1572e11aa815510acfc517492ab3ad32877d96e8812a9f1d5dd56c546e91613b486d181acef50e437026d660",
        "1c2d771ddcd457c5186bfd67bf98d6fc2dae7d57cb57ea626b959df79282ca52f00a06874f45b5e73ffbbd3a218bdab0",
        "fbf35f77fc33e0ca5982f01e71a818ce0f5d4cbd46d73aa367f1496c68d05993bf8c1ccf12f3826f839552162690e612",
        "a7ad51f5689df70413e20889d4b48b758f0fbffb28ee65b831abf9065c58ea35051102ca1329055202f1c53871f5b8c3",
        "fcd56d42fc6502a96cbd90d41e784dad0be9247cecfe40a44150e4f11d432526aa379abca6e1c9de58e129b0bae0b1de",
        "4ce5d26074ca168a5b7b5257ca9953025758c0433abbe9486fd9f14fb93559afcb352192371699557174c24e81bdca01",
        "7523d33112a9f85d70d804c7dd8297510cd70d189a2e14526724def2a31565e7582e8a1553345d5bae4564c5ff2c6c2b",
        "c11a71a5c7e3c6ae4198317579d77cf63e31fe62798bbb4e558868c2034028ce86151880eeab9c608591893de359eebb",
        "eb60c075de50a745bffa77d54d723b98b7",
      ]
    _ => []
  }
  let data : Array[Byte] = []
  for row in rows {
    let chars = row.to_array()
    for i in 0..<(chars.length() / 2) {
      let hi = chars[i * 2].to_int()
      let lo = chars[i * 2 + 1].to_int()
      let high = if hi >= 97 { hi - 87 } else { hi - 48 }
      let low = if lo >= 97 { lo - 87 } else { lo - 48 }
      data.push(((high << 4) | low).to_byte())
    }
  }
  data
}

///|
fn av1_monochrome_metadata_flags_offset(data : Array[Byte]) -> Int? {
  for i in 0..<(data.length() - 6) {
    if data[i] == b'a' &&
      data[i + 1] == b'v' &&
      data[i + 2] == b'1' &&
      data[i + 3] == b'C' {
      return Some(i + 6)
    }
  }
  None
}

///|
test "AVIF stage propagates actual monochrome metadata at all sample depths" {
  for fixture in [(0, 8), (1, 10), (2, 12)] {
    let (index, depth) = fixture
    let data = av1_monochrome_metadata_fixture(index)
    let container = avif_container_parse(data).unwrap()
    let sequence = av1_sequence_info(container.payload).unwrap()
    let stage = avif_stage1_input(data).unwrap()
    assert_true(container.monochrome)
    assert_true(sequence.monochrome)
    assert_true(stage.monochrome)
    assert_eq((stage.width, stage.height, stage.bit_depth), (64, 64, depth))
    assert_eq(stage.bit_depth, sequence.bit_depth)
    assert_true(stage.full_range)
    assert_true(stage.tile_payload.length() > 0)
    if index == 0 {
      assert_true(stage.cdef is Some(_))
    }
  }
  let color = avif_stage1_input(av1_monochrome_metadata_fixture(3)).unwrap()
  assert_false(color.monochrome)
  assert_eq((color.width, color.height, color.bit_depth), (64, 64, 8))
}

///|
test "AVIF stage rejects container monochrome declarations inconsistent with AV1" {
  for index in [0, 3] {
    let data = av1_monochrome_metadata_fixture(index)
    let flags = av1_monochrome_metadata_flags_offset(data).unwrap()
    data[flags] = (data[flags].to_int() ^ 0x10).to_byte()
    let container = avif_container_parse(data).unwrap()
    let sequence = av1_sequence_info(container.payload).unwrap()
    assert_false(container.monochrome == sequence.monochrome)
    assert_true(avif_stage1_input(data) is None)
  }
}

///|
test "AVIF stage rejects av1C sample depths inconsistent with sequence samples" {
  for
    case in [
      (0, 0x40, 10),
      (0, 0x60, 12),
      (1, 0, 8),
      (2, 0x40, 10),
      (3, 0x40, 10),
    ] {
    let (index, depth_flags, declared_depth) = case
    let data = av1_monochrome_metadata_fixture(index)
    let flags = av1_monochrome_metadata_flags_offset(data).unwrap()
    data[flags] = ((data[flags].to_int() & 0x9f) | depth_flags).to_byte()
    let container = avif_container_parse(data).unwrap()
    let sequence = av1_sequence_info(container.payload).unwrap()
    assert_eq(container.bit_depth, declared_depth)
    assert_false(container.bit_depth == sequence.bit_depth)
    assert_eq(container.monochrome, sequence.monochrome)
    assert_true(avif_stage1_input(data) is None)
  }
}

///|
test "AVIF stage applies chroma sampling restrictions only to color inputs" {
  for index in [0, 3] {
    let data = av1_monochrome_metadata_fixture(index)
    let flags = av1_monochrome_metadata_flags_offset(data).unwrap()
    data[flags] = (data[flags].to_int() & 0xf3).to_byte()
    let container = avif_container_parse(data).unwrap()
    let sequence = av1_sequence_info(container.payload).unwrap()
    assert_false(container.yuv420)
    assert_eq(container.monochrome, sequence.monochrome)
    if sequence.monochrome {
      assert_true(avif_stage1_input(data).unwrap().monochrome)
    } else {
      assert_true(avif_stage1_input(data) is None)
    }
  }
}
