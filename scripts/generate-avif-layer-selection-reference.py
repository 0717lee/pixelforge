#!/usr/bin/env python3
"""AVIF layer selectors and frame extents, independently read by libavif.

Payloads reuse committed libaom pixels with controlled AV1 header changes.
The complete AVIF is decoded through libavif/dav1d; the selected native frame
is cross-checked against the stock dav1d CLI. --check only reads committed data.
"""
from __future__ import annotations

import argparse
import ctypes as C
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/avif-layer-selection"
TEST = ROOT / "avif_layer_selection_reference_wbtest.mbt"
SOURCE = ROOT / "tests/fixtures/av1-inter/inter_lossless_64x64.obu"


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


obu = module("avif_layer_obu", "generate-av1-obu-reference.py")
animation = module("avif_layer_lib", "generate-avif-animation-alpha-reference.py")
box = animation.helpers.box
full_box = animation.helpers.full_box


def sha(data):
    return hashlib.sha256(data).hexdigest()


def payloads(ffmpeg):
    packets = obu.packets(SOURCE.read_bytes())
    sequence = next(payload for kind, payload, _ in packets if kind == 1)
    frames = [(payload, header) for kind, payload, header in packets if kind == 6]
    original = obu.bits(sequence)
    assert original[:29] == "0" * 29
    # OP0 contains spatial layers 0/1; OP1 contains only spatial layer 0.
    layered = original[:7] + "00001"
    for idc in (769, 257):
        layered += f"{idc:012b}" + original[24:29]
    layered += original[29:]
    spatial = obu.obu(1, obu.packed(layered))
    spatial += obu.obu(6, frames[0][0], extension=0)
    spatial += obu.obu(6, frames[1][0], extension=8)

    # Increase sequence maxima to 128x128, preserving the actual 64x64 key
    # picture via frame_size_override. The entropy-coded tile is unchanged.
    assert original[29:49] == "01010101" + "1" * 12
    maximum_sequence = original[:29] + "01100110" + "1" * 14 + original[49:]
    fields = obu.trace_frames(ffmpeg, SOURCE)[0]
    frame, header_bytes = frames[0]
    offset = header_bytes * 8
    end = max(pos + width for pos, width, _ in fields.values()) - offset
    flag = fields["frame_size_override_flag"][0] - offset
    source_header = obu.bits(frame)[:end]
    assert source_header[flag] == "0"
    changed_header = source_header[:flag] + "1" + f"{63:07b}{63:07b}" + source_header[flag + 1:]
    maximum = obu.obu(1, obu.packed(maximum_sequence))
    maximum += obu.obu(6, obu.packed(changed_header) + frame[(end + 7) // 8:])
    return spatial, maximum


def container(payload, *, op=None, layer=None, size=64, grid=False):
    ftyp = box(b"ftyp", b"avif" + bytes(4) + b"avifmif1miaf")
    hdlr = full_box(b"hdlr", 0, 0, bytes(4) + b"pict" + bytes(12) + b"Layer reference\0")
    pitm = full_box(b"pitm", 0, 0, struct.pack(">H", 1))
    infe = full_box(b"infe", 2, 0, struct.pack(">HH", 1, 0) + (b"gridGrid\0" if grid else b"av01Color\0"))
    if grid:
        infe += full_box(b"infe", 2, 1, struct.pack(">HH", 2, 0) + b"av01Cell\0")
    iinf = full_box(b"iinf", 0, 0, struct.pack(">H", 2 if grid else 1) + infe)
    properties = [full_box(b"ispe", 0, 0, struct.pack(">II", size, size)),
                  full_box(b"pixi", 0, 0, bytes([3, 8, 8, 8])),
                  box(b"av1C", bytes([0x81, 0, 0x0c, 0])),
                  box(b"colr", b"nclx" + struct.pack(">HHHB", 1, 13, 1, 0))]
    associations = [1, 2, 0x83, 4]
    for kind, value in ((b"a1op", op), (b"lsel", layer)):
        if value is not None:
            raw = value if isinstance(value, bytes) else value.to_bytes(1 if kind == b"a1op" else 2, "big")
            properties.append(box(kind, raw))
            associations.append(0x80 | len(properties))
    if grid:
        associations.remove(4)
        association_bytes = struct.pack(">IHB", 2, 1, 3) + bytes([1, 2, 4])
        association_bytes += struct.pack(">HB", 2, len(associations)) + bytes(associations)
    else:
        association_bytes = struct.pack(">IHB", 1, 1, len(associations)) + bytes(associations)
    iprp = box(b"iprp", box(b"ipco", b"".join(properties)) + full_box(b"ipma", 0, 0, association_bytes))
    grid_data = bytes(4) + struct.pack(">HH", size, size) if grid else b""
    iref = full_box(b"iref", 0, 0, box(b"dimg", struct.pack(">HHH", 1, 1, 2))) if grid else b""

    def meta(start):
        locations = b"\x44\x00" + struct.pack(">H", 2 if grid else 1)
        if grid:
            locations += struct.pack(">HHHII", 1, 0, 1, start, len(grid_data))
        locations += struct.pack(">HHHII", 2 if grid else 1, 0, 1, start + len(grid_data), len(payload))
        return full_box(b"meta", 0, 0, hdlr + pitm + full_box(b"iloc", 0, 0, locations) + iinf + iprp + iref)

    return ftyp + meta(len(ftyp) + len(meta(0)) + 8) + box(b"mdat", grid_data + payload)


def decode(lib, data):
    image, decoder = lib.avifImageCreateEmpty(), lib.avifDecoderCreate()
    rgb = animation.helpers.ScalarRGB0111()
    try:
        buf = C.create_string_buffer(data)
        animation.checked(lib.avifDecoderReadMemory(decoder, image, buf, len(data)), "decode selected AVIF")
        info = animation.Image.from_address(image)
        assert (info.width, info.height, info.depth, info.format) == (64, 64, 8, 3)
        native = b""
        for plane in range(3):
            width = info.width >> int(plane != 0)
            height = info.height >> int(plane != 0)
            native += b"".join(C.string_at(info.planes[plane] + y * info.strides[plane], width) for y in range(height))
        lib.avifRGBImageSetDefaults(C.byref(rgb), image)
        rgb.depth, rgb.avoidLibYUV, rgb.chromaUpsampling = 8, 1, 3
        lib.avifRGBImageAllocatePixels(C.byref(rgb))
        animation.checked(lib.avifImageYUVToRGB(image, C.byref(rgb)), "selected scalar nearest RGBA")
        rgba = b"".join(C.string_at(rgb.pixels + y * rgb.rowBytes, rgb.width * 4) for y in range(rgb.height))
        return native, rgba
    finally:
        lib.avifRGBImageFreePixels(C.byref(rgb))
        lib.avifImageDestroy(image)
        lib.avifDecoderDestroy(decoder)


def cases():
    return [dict(name="sequence_max_128_frame_64", payload="maximum", op=None, layer=None, expected="key", maximum=128),
            dict(name="default_highest_layer", payload="spatial", op=None, layer=None, expected="inter", maximum=64),
            dict(name="explicit_operating_point_1", payload="spatial", op=1, layer=None, expected="key", maximum=64),
            dict(name="explicit_spatial_layer_0", payload="spatial", op=None, layer=0, expected="key", maximum=64),
            dict(name="explicit_spatial_layer_1", payload="spatial", op=0, layer=1, expected="inter", maximum=64),
            dict(name="unspecified_layer_ffff", payload="spatial", op=None, layer=65535, expected="inter", maximum=64),
            dict(name="grid_cell_sequence_max_128", payload="maximum", op=None, layer=None, expected="key", maximum=128, grid=True),
            dict(name="grid_cell_operating_point_1", payload="spatial", op=1, layer=None, expected="key", maximum=64, grid=True)]


def render(manifest):
    text = '''/// Complete AVIFs independently decoded by libavif/dav1d. Every native
/// sample and RGBA byte is compared with the embedded independent reference.

///|
fn avif_layer_selection_check(data : Array[Byte], max_size : Int,
  op : Int, layer : Int?, expected_native : Array[Byte], expected_rgba : Array[Byte], grid : Bool) -> Unit raise {
  let container = avif_container_parse(data).unwrap()
  assert_eq((container.width, container.height), (64, 64))
  let frame = if grid {
    let descriptor = avif_grid_descriptor(data).unwrap()
    assert_eq(avif_item_layer_selection(data, descriptor.tiles[0].item_id), Some((op, layer)))
    avif_decode_grid_frame(data, descriptor).unwrap()
  } else {
    let sequence = av1_sequence_info(container.payload).unwrap()
    assert_eq((sequence.width, sequence.height), (max_size, max_size))
    assert_eq((container.operating_point, container.spatial_layer), (op, layer))
    assert_eq(avif_item_layer_selection(data, 1), Some((op, layer)))
    av1_decode_frame_planes(container.payload, allow_monochrome=true,
      operating_point=op, spatial_layer=layer).unwrap()
  }
  let samples : Array[Byte] = []
  for plane in 0..<3 {
    for value in av1_frame_crop(frame, plane) { samples.push(value.to_byte()) }
  }
  assert_eq((frame.width, frame.height), (64, 64))
  assert_eq(samples.length(), expected_native.length())
  for i in 0..<samples.length() { assert_eq((i, samples[i]), (i, expected_native[i])) }
  for result in [avif_decode(data), avif_decode_rgba(data)] {
    let image = result.unwrap()
    assert_eq((image.width, image.height), (64, 64))
    assert_eq(image.data.length(), expected_rgba.length())
    for i in 0..<image.data.length() { assert_eq((i, image.data[i]), (i, expected_rgba[i])) }
  }
}
'''
    for expected in ("key", "inter"):
        sample = next(case for case in manifest["fixtures"] if case.get("expected") == expected)
        for plane, suffix in (("native", ".reference.yuv"), ("rgba", ".reference.rgba")):
            text += "\n" + obu.emit_array(f"avif_layer_expected_{expected}_{plane}", (OUT / (sample["name"] + suffix)).read_bytes())
    for case in manifest["fixtures"]:
        name = case["name"]
        text += "\n" + obu.emit_array("avif_layer_" + name, (OUT / (name + ".avif")).read_bytes())
        text += f'\n///|\ntest "AVIF layer selector {name}" {{\n'
        if case.get("reject"):
            text += f'  assert_true(avif_decode(avif_layer_{name}) is None)\n'
            text += f'  assert_true(avif_decode_rgba(avif_layer_{name}) is None)\n'
        else:
            layer = f'Some({case["layer"]})' if case["layer"] not in (None, 65535) else "None"
            text += f'  avif_layer_selection_check(avif_layer_{name}, {case["maximum"]}, {case["op"] or 0}, {layer}, '
            text += f'avif_layer_expected_{case["expected"]}_native, avif_layer_expected_{case["expected"]}_rgba, {str(case.get("grid", False)).lower()})\n'
        text += "}\n"
    return text


def normalized(text):
    return re.sub(r"\s+", "", re.sub(r",\s*([\]\)])", r"\1", text))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--libavif", default="avif.dll")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--dav1d", default="dav1d")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((OUT / "manifest.json").read_text())
        assert sha(SOURCE.read_bytes()) == manifest["source_sha256"]
        for case in manifest["fixtures"]:
            for suffix, digest in case["sha256"].items():
                assert sha((OUT / (case["name"] + suffix)).read_bytes()) == digest
        assert normalized(TEST.read_text(encoding="utf-8")) == normalized(render(manifest))
        print(f'checked {len(manifest["fixtures"])} AVIF selection cases; no files written')
        return
    lib, version = animation.library(args.libavif)
    spatial, maximum = payloads(args.ffmpeg)
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pixelforge-avif-layers-") as temporary:
        directory = Path(temporary)
        reference = obu.decode(args.dav1d, SOURCE, directory / "source.yuv")
        frame_size = 64 * 64 * 3 // 2
        assert len(reference) == frame_size * 2
        source_frames = dict(key=reference[:frame_size], inter=reference[frame_size:])
        records = []
        for case in cases():
            coded = spatial if case["payload"] == "spatial" else maximum
            data = container(coded, op=case["op"], layer=case["layer"], grid=case.get("grid", False))
            native, rgba = decode(lib, data)
            assert native == source_frames[case["expected"]], case["name"]
            record = dict(case, native_crc=zlib.crc32(native), rgba_crc=zlib.crc32(rgba), sha256={})
            artifacts = {".avif": data, ".obu": coded, ".reference.yuv": native, ".reference.rgba": rgba}
            for suffix, content in artifacts.items():
                (OUT / (case["name"] + suffix)).write_bytes(content)
                record["sha256"][suffix] = sha(content)
            records.append(record)
        for name, values in [("reject_op_outside_sequence", dict(op=2)),
                             ("reject_op_above_31", dict(op=32)),
                             ("reject_layer_outside_range", dict(layer=4)),
                             ("reject_absent_layer", dict(layer=2)),
                             ("reject_layer_excluded_by_op", dict(op=1, layer=1)),
                             ("reject_truncated_lsel", dict(layer=b"\x00")),
                             ("reject_actual_frame_size_mismatch", dict(size=63))]:
            data = container(spatial, **values)
            (OUT / (name + ".avif")).write_bytes(data)
            records.append(dict(name=name, reject=True, sha256={".avif": sha(data)}))
    manifest = dict(generator="python scripts/generate-avif-layer-selection-reference.py --libavif <libavif 0.11.1> --dav1d <dav1d> --ffmpeg <ffmpeg>",
                    libavif_version=version, source=SOURCE.relative_to(ROOT).as_posix(), source_sha256=sha(SOURCE.read_bytes()),
                    reference_method="complete AVIF decoded by libavif/dav1d, every native sample checked against stock dav1d source decode; libavif scalar nearest RGBA", fixtures=records)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    TEST.write_text(render(manifest), encoding="utf-8", newline="\n")
    (OUT / "README.md").write_text('''# AVIF dimensions and layer selectors

Eight valid complete AVIFs exercise sequence maxima 128x128 with an actual
64x64 frame, the default highest layer, essential a1op=1, essential lsel=0/1,
and lsel=0xffff. The two spatial layers have different real image pixels.
The lower layer supplies references for the higher layer within one sync TU.
Two grid cases exercise a coded cell with different sequence maxima and OP1.
Seven malformed or unsatisfiable selections test rejection.

The generator reuses committed libaom tile payloads, changing only AV1 frame
and sequence headers. Independent libavif 0.11.1/dav1d reads the entire AVIF;
each native sample must equal the stock dav1d decode of the source frame.
RGBA is libavif's scalar nearest-chroma output with container BT.709 nclx.
Full native and RGBA bytes are committed alongside checksums and file hashes.
Whitebox regressions embed both distinct native/RGBA references and compare
every sample through primary, RGBA, and grid entry points as applicable.

Regenerate with the manifest command. `--check` only reads existing files.
The required property semantics are AVIF sections 2.2.2 and 2.3.2:
https://aomediacodec.github.io/av1-avif/
The fixtures and generator are project-owned; no decoder source is vendored.
''', encoding="utf-8", newline="\n")
    print(f"generated {len(records)} independent AVIF selection cases")


if __name__ == "__main__":
    main()
