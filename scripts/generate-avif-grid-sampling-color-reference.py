#!/usr/bin/env python3
"""Native 4:2:2/4:4:4 AVIF grid and primary-nclx references from libavif."""
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
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests/fixtures/avif-grid-sampling-color"
TEST = ROOT / "avif_grid_sampling_color_reference_wbtest.mbt"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


animation = load("grid_sampling_codec", "generate-avif-animation-alpha-reference.py")
grid = load("grid_sampling_container", "generate-avif-grid-reference.py")


class FullImage(C.Structure):
    _fields_ = animation.Image._fields_ + [
        ("owns_alpha", C.c_int), ("premultiplied", C.c_int), ("icc", animation.RWData),
        ("primaries", C.c_uint16), ("transfer", C.c_uint16), ("matrix", C.c_uint16),
    ]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode_cell(lib, depth, layout, index, color_fields=(2, 2, 2)):
    sx = int(layout == "422")
    planes = []
    for plane in range(3):
        width = 64 >> (sx if plane else 0)
        scale = 1 << (depth - 8)
        samples = [(32 + (x * 3 + y * 5 + plane * 37 + index * 23) % 192) * scale +
                   (x + y + plane + index) % scale for y in range(64) for x in range(width)]
        planes.append(samples)
    image = lib.avifImageCreate(64, 64, depth, 2 if sx else 1)
    encoder = lib.avifEncoderCreate()
    output = animation.RWData()
    try:
        if not image or not encoder:
            raise RuntimeError("reference allocation failed")
        info = FullImage.from_address(image)
        info.range = 1
        info.primaries, info.transfer, info.matrix = color_fields
        animation.checked(lib.avifImageAllocatePlanes(image, 1), "allocate native YUV")
        options = animation.Encoder.from_address(encoder)
        options.codec, options.threads, options.speed = 1, 1, 8
        options.min_q = options.max_q = 0
        for plane, samples in enumerate(planes):
            width = 64 >> (sx if plane else 0)
            for y in range(64):
                values = samples[y * width:(y + 1) * width]
                raw = bytes(values) if depth == 8 else struct.pack(f"<{width}H", *values)
                C.memmove(info.planes[plane] + y * info.strides[plane], raw, len(raw))
        animation.checked(lib.avifEncoderWrite(encoder, image, C.byref(output)), "encode grid cell")
        data = C.string_at(output.data, output.size)
        return data, planes
    finally:
        lib.avifRWDataFree(C.byref(output))
        lib.avifEncoderDestroy(encoder)
        lib.avifImageDestroy(image)


def decode_grid(lib, data):
    image, decoder = lib.avifImageCreateEmpty(), lib.avifDecoderCreate()
    rgb = animation.helpers.ScalarRGB0111()
    buffer = C.create_string_buffer(data)
    try:
        animation.checked(lib.avifDecoderReadMemory(decoder, image, buffer, len(data)), "decode complete grid")
        info = FullImage.from_address(image)
        sx = int(info.format == 2)
        if info.format not in (1, 2):
            raise RuntimeError("unexpected grid subsampling")
        planes = []
        for plane in range(3):
            width = (info.width + (sx if plane else 0)) >> (sx if plane else 0)
            raw = b"".join(C.string_at(info.planes[plane] + y * info.strides[plane], width * (1 if info.depth == 8 else 2)) for y in range(info.height))
            planes.append(list(raw) if info.depth == 8 else list(struct.unpack(f"<{len(raw)//2}H", raw)))
        lib.avifRGBImageSetDefaults(C.byref(rgb), image)
        rgb.depth, rgb.avoidLibYUV, rgb.chromaUpsampling = 8, 1, 3
        lib.avifRGBImageAllocatePixels(C.byref(rgb))
        animation.checked(lib.avifImageYUVToRGB(image, C.byref(rgb)), "scalar nearest RGBA")
        rgba = b"".join(C.string_at(rgb.pixels + y * rgb.rowBytes, rgb.width * 4) for y in range(rgb.height))
        return planes, rgba, [info.primaries, info.transfer, info.matrix, info.range]
    finally:
        lib.avifRGBImageFreePixels(C.byref(rgb))
        lib.avifImageDestroy(image)
        lib.avifDecoderDestroy(decoder)


def compose(sources, width, height, sx):
    out = []
    for plane in range(3):
        sub = sx if plane else 0
        pw, tile_width = width >> sub, 64 >> sub
        pixels = []
        for y in range(height):
            for x in range(pw):
                cell = (y // 64) * 2 + x // tile_width
                pixels.append(sources[cell][plane][(y % 64) * tile_width + x % tile_width])
        out.append(pixels)
    return out


def tests(manifest):
    text = '''/// Actual libavif complete-grid native planes and nearest scalar RGBA.
/// PixelForge is never used to generate expected values.

///|
fn avif_grid_sampling_color_check(data : Array[Byte], width : Int, height : Int,
  sx : Int, depth : Int, expected_native : UInt, expected_rgba : UInt) -> Unit raise {
  let descriptor = avif_grid_descriptor(data).unwrap()
  assert_true(avif_grid_properties_match(data, descriptor))
  let frame = avif_decode_grid_frame(data, descriptor).unwrap()
  assert_eq((frame.width, frame.height, frame.sub_x, frame.sub_y, frame.bit_depth),
    (width, height, sx, 0, depth))
  let bytes : Array[Byte] = []
  for plane in 0..<3 {
    let cropped = av1_frame_crop(frame, plane)
    assert_eq(cropped.length(), (width >> (if plane == 0 { 0 } else { sx })) * height)
    for pixel in cropped {
      bytes.push((pixel & 255).to_byte())
      bytes.push((pixel >> 8).to_byte())
    }
  }
  assert_eq(crc32(bytes, 0, bytes.length()), expected_native)
  for decoded in [avif_decode_grid_auto(data), avif_decode(data), avif_decode_rgba(data)] {
    let image = decoded.unwrap()
    assert_eq((image.width, image.height), (width, height))
    let rgba = Array::makei(image.data.length(), i => image.data[i])
    assert_eq(crc32(rgba, 0, rgba.length()), expected_rgba)
  }
}
'''
    for case in manifest["cases"]:
        data = (OUT / case["file"]).read_bytes()
        text += f'\n///|\ntest "actual libavif grid {case["name"]}" {{\n'
        text += animation.array("container", data, "  ")
        if case.get("result") == "reject":
            text += '  let descriptor = avif_grid_descriptor(container).unwrap()\n'
            text += '  assert_true(avif_decode_grid_frame(container, descriptor) is None)\n'
            text += '  assert_true(avif_decode_grid_auto(container) is None)\n}\n'
        else:
            text += f'  avif_grid_sampling_color_check(container, {case["width"]}, {case["height"]}, {case["sx"]}, {case["depth"]}, 0x{case["native_crc"]:08x}U, 0x{case["rgba_crc"]:08x}U)\n}}\n'
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--libavif", default="avif.dll")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((OUT / "manifest.json").read_text())
        for name, digest in manifest["artifacts"].items():
            if sha((OUT / name).read_bytes()) != digest:
                raise SystemExit(f"fixture hash mismatch: {name}")
        if animation.canonical(TEST.read_text()) != animation.canonical(tests(manifest)):
            raise SystemExit("grid sampling/color tests differ from independent references")
        print(f'Validated {len(manifest["cases"])} grid fixtures; no files changed.')
        return
    lib, version = animation.library(args.libavif)
    lib.avifEncoderWrite.argtypes = [C.c_void_p, C.c_void_p, C.POINTER(animation.RWData)]
    lib.avifEncoderWrite.restype = C.c_int
    OUT.mkdir(parents=True, exist_ok=True)
    cases, artifacts, source_sets = [], {}, {}
    def write(name, data):
        (OUT / name).write_bytes(data)
        artifacts[name] = sha(data)
    for depth in (8, 10, 12):
        for layout in ("444", "422"):
            sx = int(layout == "422")
            width, height = (98 if sx else 99), 97
            coded, inputs = [], []
            for cell in range(4):
                data, source_planes = encode_cell(lib, depth, layout, cell)
                inputs.append(source_planes)
                coded.append({"depth": depth, "monochrome": False,
                              "payload": grid.helpers.box_payloads(data, b"mdat")[0],
                              "av1c": grid.helpers.box_payloads(data, b"av1C")[0],
                              "colr": b"nclx" + struct.pack(">HHHB", 1, 13, 1, 128)})
            data, graph = grid.assemble(coded, 2, 2, width, height)
            source_sets[depth, layout] = coded
            native, rgba, color = decode_grid(lib, data)
            if native != compose(inputs, width, height, sx):
                raise RuntimeError("actual libavif grid differs from lossless native cell composition")
            if color != [1, 13, 1, 1]:
                raise RuntimeError(f"primary nclx was not applied: {color}")
            raw = b"".join(struct.pack(f"<{len(plane)}H", *plane) for plane in native)
            name = f"nclx709_{layout}_{depth}bit_2x2_odd_crop"
            write(name + ".avif", data)
            write(name + ".native.bin", raw)
            write(name + ".rgba", rgba)
            cases.append({"name": name, "file": name + ".avif", "depth": depth, "width": width, "height": height,
                          "sx": sx, "sy": 0, "native_crc": zlib.crc32(raw), "rgba_crc": zlib.crc32(rgba), "graph": graph})
            print(name, "native and scalar nearest RGBA verified")
    base = source_sets[8, "444"]
    color_data, _ = encode_cell(lib, 8, "444", 1, (9, 14, 9))
    foreign = [("mixed_sampling", source_sets[8, "422"][1]["payload"]),
               ("mixed_bitstream_color", grid.helpers.box_payloads(color_data, b"mdat")[0])]
    for name, payload in foreign:
        cells = [dict(cell) for cell in base]
        cells[1]["payload"] = payload
        data, _ = grid.assemble(cells, 2, 2, 99, 97)
        write(name + ".avif", data)
        try:
            decode_grid(lib, data)
            vendor_result = "accepted"
        except RuntimeError as error:
            vendor_result = str(error)
        cases.append({"name": name, "file": name + ".avif", "depth": 8, "result": "reject",
                      "oracle": "controlled incompatible second cell; strict consistency contract, not a claim of vendor rejection parity",
                      "libavif_observation": vendor_result})
    manifest = {"libavif": version, "cell_encoding": "libaom via libavif, lossless, speed8, threads1; 64x64 full-range cells with unspecified CP/TC/MC",
                "oracle": "actual complete-grid libavif native planes equal source-cell composition; RGBA8 scalar avoidLibYUV=1, nearest chroma; primary nclx709",
                "native_serialization": "all planes row-major uint16 little endian even for 8-bit samples",
                "cases": cases, "artifacts": artifacts}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    formatted = subprocess.run(["moonfmt", "-"], input=tests(manifest), text=True, capture_output=True, check=True).stdout
    TEST.write_text(formatted, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
