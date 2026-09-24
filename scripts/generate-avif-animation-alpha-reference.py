#!/usr/bin/env python3
"""Generate and independently decode real libavif alpha image sequences."""
from __future__ import annotations

import argparse
import ctypes as C
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests/fixtures/avif-animation-alpha"
TEST = ROOT / "avif_animation_alpha_reference_wbtest.mbt"
MARKER = "// BEGIN LIBAVIF ANIMATION ALPHA REFERENCES\n"
spec = importlib.util.spec_from_file_location("animation_reference_helpers", Path(__file__).with_name("generate-av1-monochrome-reference.py"))
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


class Image(C.Structure):
    _fields_ = [("width", C.c_uint32), ("height", C.c_uint32), ("depth", C.c_uint32),
                ("format", C.c_int), ("range", C.c_int), ("chroma", C.c_int),
                ("planes", C.c_void_p * 3), ("strides", C.c_uint32 * 3),
                ("owns_yuv", C.c_int), ("alpha", C.c_void_p), ("alpha_stride", C.c_uint32)]


class Encoder(C.Structure):
    _fields_ = [("codec", C.c_int), ("threads", C.c_int), ("speed", C.c_int),
                ("keyframe_interval", C.c_int), ("timescale", C.c_uint64),
                ("min_q", C.c_int), ("max_q", C.c_int), ("min_aq", C.c_int), ("max_aq", C.c_int)]


class RWData(C.Structure):
    _fields_ = [("data", C.c_void_p), ("size", C.c_size_t)]


class Timing(C.Structure):
    _fields_ = [("timescale", C.c_uint64), ("pts", C.c_double),
                ("pts_units", C.c_uint64), ("duration", C.c_double), ("duration_units", C.c_uint64)]


class Decoder(C.Structure):
    _fields_ = [("inputs", C.c_uint32 * 11), ("image", C.c_void_p),
                ("index", C.c_int), ("count", C.c_int), ("progressive", C.c_int),
                ("timing", Timing), ("timescale", C.c_uint64), ("duration", C.c_double),
                ("duration_units", C.c_uint64), ("has_alpha", C.c_int)]


def library(path):
    lib, version = helpers.scalar_library(path)
    lib.avifImageCreate.argtypes = [C.c_uint32, C.c_uint32, C.c_uint32, C.c_int]
    lib.avifImageCreate.restype = C.c_void_p
    lib.avifImageAllocatePlanes.argtypes = [C.c_void_p, C.c_uint32]
    lib.avifImageAllocatePlanes.restype = C.c_int
    lib.avifEncoderCreate.restype = C.c_void_p
    lib.avifEncoderDestroy.argtypes = [C.c_void_p]
    lib.avifEncoderAddImage.argtypes = [C.c_void_p, C.c_void_p, C.c_uint64, C.c_uint32]
    lib.avifEncoderAddImage.restype = C.c_int
    lib.avifEncoderFinish.argtypes = [C.c_void_p, C.POINTER(RWData)]
    lib.avifEncoderFinish.restype = C.c_int
    lib.avifRWDataFree.argtypes = [C.POINTER(RWData)]
    lib.avifDecoderSetSource.argtypes = [C.c_void_p, C.c_int]
    lib.avifDecoderSetIOMemory.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
    lib.avifDecoderParse.argtypes = [C.c_void_p]
    lib.avifDecoderNextImage.argtypes = [C.c_void_p]
    return lib, version


def checked(result, stage):
    if result:
        raise RuntimeError(f"{stage}: libavif result {result}")


def input_samples(depth, frame):
    maximum = (1 << depth) - 1
    gray = [(37 + frame * 29 + x * 3 + y * 5) * maximum // 255 for y in range(16) for x in range(16)]
    alpha = [((x * 13 + y * 19 + frame * 47) * 7 + frame + x % 3) & maximum for y in range(16) for x in range(16)]
    alpha[0], alpha[1], alpha[2], alpha[3] = 0, maximum, 1, maximum // 2 + frame
    return gray, alpha


def encode(lib, depth, *, color444=False):
    encoder = lib.avifEncoderCreate()
    if not encoder:
        raise RuntimeError("encoder allocation failed")
    options = Encoder.from_address(encoder)
    options.codec, options.threads, options.speed = 1, 1, 8
    options.keyframe_interval, options.timescale = 0, 1000
    options.min_q = options.max_q = options.min_aq = options.max_aq = 0
    output = RWData()
    try:
        for frame, duration in enumerate((100, 200, 300)):
            image = lib.avifImageCreate(16, 16, depth, 1 if color444 else 4)
            if not image:
                raise RuntimeError("image allocation failed")
            try:
                checked(lib.avifImageAllocatePlanes(image, 255), "allocate planes")
                info = Image.from_address(image)
                info.range = 1
                gray, alpha = input_samples(depth, frame)
                buffers = [(info.planes[0], info.strides[0], gray), (info.alpha, info.alpha_stride, alpha)]
                if color444:
                    maximum = (1 << depth) - 1
                    for plane in (1, 2):
                        chroma = [(65 + (x * 7 + y * 3 + plane * 43 + frame * 11) % 128) * maximum // 255 for y in range(16) for x in range(16)]
                        buffers.append((info.planes[plane], info.strides[plane], chroma))
                for plane, stride, values in buffers:
                    for y in range(16):
                        row = bytes(values[y * 16:(y + 1) * 16]) if depth == 8 else struct.pack("<16H", *values[y * 16:(y + 1) * 16])
                        C.memmove(plane + y * stride, row, len(row))
                checked(lib.avifEncoderAddImage(encoder, image, duration, 0), "encode frame")
            finally:
                lib.avifImageDestroy(image)
        checked(lib.avifEncoderFinish(encoder, C.byref(output)), "finish sequence")
        return C.string_at(output.data, output.size)
    finally:
        lib.avifRWDataFree(C.byref(output))
        lib.avifEncoderDestroy(encoder)


def decode(lib, data, *, expect_alpha=True):
    decoder = lib.avifDecoderCreate()
    if not decoder:
        raise RuntimeError("decoder allocation failed")
    buffer = C.create_string_buffer(data)
    try:
        checked(lib.avifDecoderSetSource(decoder, 2), "select tracks")
        checked(lib.avifDecoderSetIOMemory(decoder, buffer, len(data)), "set memory")
        checked(lib.avifDecoderParse(decoder), "parse sequence")
        state = Decoder.from_address(decoder)
        if state.count != 3 or bool(state.has_alpha) != expect_alpha:
            raise RuntimeError(f"unexpected sequence count/alpha: {state.count}/{state.has_alpha}")
        frames = []
        for index in range(state.count):
            checked(lib.avifDecoderNextImage(decoder), "decode frame")
            info = Image.from_address(state.image)
            size = 1 if info.depth == 8 else 2
            native_alpha = b"".join(C.string_at(info.alpha + y * info.alpha_stride, info.width * size) for y in range(info.height)) if expect_alpha else b""
            rgb = helpers.ScalarRGB0111()
            lib.avifRGBImageSetDefaults(C.byref(rgb), state.image)
            rgb.depth, rgb.avoidLibYUV = 8, 1
            lib.avifRGBImageAllocatePixels(C.byref(rgb))
            try:
                checked(lib.avifImageYUVToRGB(state.image, C.byref(rgb)), "scalar RGBA")
                rgba = b"".join(C.string_at(rgb.pixels + y * rgb.rowBytes, rgb.width * 4) for y in range(rgb.height))
            finally:
                lib.avifRGBImageFreePixels(C.byref(rgb))
            frames.append({"index": index, "timestamp": state.timing.pts_units,
                           "duration": state.timing.duration_units, "timescale": state.timing.timescale,
                           "rgba": rgba, "native_alpha": native_alpha})
        return frames
    finally:
        lib.avifDecoderDestroy(decoder)


def boxes(data, start=0, end=None, ancestors=()):
    end = len(data) if end is None else end
    result = []
    while start < end:
        size, kind = struct.unpack_from(">I4s", data, start)
        payload, finish = start + 8, start + size
        if size < 8 or finish > end:
            raise ValueError("unexpected reference box bounds")
        box = {"type": kind.decode(), "start": start, "payload": payload, "end": finish, "ancestors": ancestors}
        result.append(box)
        child = payload if kind in (b"moov", b"trak", b"mdia", b"minf", b"stbl", b"tref") else None
        if kind == b"stsd":
            child = payload + 8
        elif kind == b"av01":
            child = payload + 78
        if child is not None:
            result += boxes(data, child, finish, ancestors + (start,))
        start = finish
    return result


def swap_tracks(data):
    tracks = [box for box in boxes(data) if box["type"] == "trak"]
    if len(tracks) != 2 or tracks[0]["end"] != tracks[1]["start"]:
        raise ValueError("expected adjacent primary and auxiliary tracks")
    a, b = tracks
    return data[:a["start"]] + data[b["start"]:b["end"]] + data[a["start"]:a["end"]] + data[b["end"]:]


def alpha_boxes(data):
    tree = boxes(data)
    auxl = next(box for box in tree if box["type"] == "auxl")
    track = next(box for box in tree if box["type"] == "trak" and box["start"] in auxl["ancestors"])
    return {box["type"]: box for box in tree if track["start"] in box["ancestors"]}


def rescale_alpha(data):
    out = bytearray(data)
    alpha = alpha_boxes(data)
    mdhd = alpha["mdhd"]
    version = data[mdhd["payload"]]
    timescale = mdhd["payload"] + (12 if version == 0 else 20)
    duration = timescale + 4
    scale = int.from_bytes(data[timescale:timescale + 4], "big")
    out[timescale:timescale + 4] = (scale * 2).to_bytes(4, "big")
    size = 4 if version == 0 else 8
    duration_value = int.from_bytes(data[duration:duration + size], "big")
    out[duration:duration + size] = (duration_value * 2).to_bytes(size, "big")
    stts = alpha["stts"]
    count = int.from_bytes(data[stts["payload"] + 4:stts["payload"] + 8], "big")
    for index in range(count):
        at = stts["payload"] + 12 + index * 8
        out[at:at + 4] = (int.from_bytes(data[at:at + 4], "big") * 2).to_bytes(4, "big")
    return bytes(out)


def negative_cases(data):
    alpha = alpha_boxes(data)
    def changed(at, value):
        out = bytearray(data)
        out[at:at + len(value)] = value
        return bytes(out)
    yield "zero_master_id", changed(alpha["auxl"]["payload"], bytes(4))
    yield "misaligned_alpha_time", changed(alpha["stts"]["payload"] + 12, (101).to_bytes(4, "big"))
    yield "zero_alpha_duration", changed(alpha["stts"]["payload"] + 12, bytes(4))
    at = alpha["av1C"]["payload"] + 2
    yield "alpha_depth_mismatch", changed(at, bytes([data[at] | 0x40]))
    yield "alpha_geometry_mismatch", changed(alpha["av01"]["payload"] + 24, (15).to_bytes(2, "big"))
    yield "truncated_alpha_samples", changed(alpha["stsz"]["payload"] + 8, (2).to_bytes(4, "big"))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def array(name, data, indent=""):
    out = f"{indent}let {name} : Array[Byte] = [\n"
    for start in range(0, len(data), 20):
        out += indent + "  " + ", ".join(f"0x{value:02x}" for value in data[start:start + 20]) + ",\n"
    return out + indent + "]\n"


def render(manifest):
    text = MARKER
    prefixes = sorted({case.get("rgba_prefix", f'alpha_sequence_{case["depth"]}bit') for case in manifest["fixtures"] if case["result"] != "reject"})
    for prefix in prefixes:
        pixels = b"".join((FIXTURES / f"{prefix}_frame{index}.rgba").read_bytes() for index in range(3))
        text += "\n///|\n" + array(f"avif_animation_{prefix}_pixels", pixels)
    for record in manifest["fixtures"]:
        data = (FIXTURES / record["file"]).read_bytes()
        text += f'\n///|\ntest "libavif animation alpha {record["name"]}" {{\n'
        text += array("container", data, "  ")
        expected = "avif_animation_" + record.get("rgba_prefix", f'alpha_sequence_{record["depth"]}bit') + "_pixels"
        if record["result"] == "rgba":
            text += f'  avif_animation_alpha_reference_case(container, {expected})\n'
        elif record["result"] == "opaque":
            text += f'  let expected = {expected}.copy()\n'
            text += '  for i in 0..<768 { expected[i * 4 + 3] = 0xff }\n'
            text += '  avif_animation_alpha_reference_case(container, expected)\n'
        else:
            text += '  assert_true(avif_decode_animation(container) is None)\n'
        text += "}\n"
    return text


def canonical(text):
    import re
    return re.sub(r",(?=[\])}])", "", re.sub(r"\s+", "", text))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--libavif", default="avif.dll")
    parser.add_argument("--check", action="store_true", help="only read and verify recorded artifacts and tests")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((FIXTURES / "manifest.json").read_text())
        for name, expected in manifest["artifacts"].items():
            if sha((FIXTURES / name).read_bytes()) != expected:
                raise SystemExit(f"fixture hash mismatch: {name}")
        if canonical(MARKER + TEST.read_text().split(MARKER, 1)[1]) != canonical(render(manifest)):
            raise SystemExit("generated animation tests differ from independent references")
        print(f'Validated {len(manifest["fixtures"])} animation fixtures; no files changed.')
        return
    lib, version = library(args.libavif)
    FIXTURES.mkdir(parents=True, exist_ok=True)
    records, artifacts = [], {}
    def write(name, data):
        (FIXTURES / name).write_bytes(data)
        artifacts[name] = sha(data)
    for depth in (8, 10, 12):
        data = encode(lib, depth)
        sync = [box for box in boxes(data) if box["type"] == "stss"]
        if len(sync) != 2 or any(data[b["payload"]:b["end"]] != bytes.fromhex("000000000000000100000001") for b in sync):
            raise RuntimeError("expected independently stateful tracks with only the first sample marked sync")
        frames = decode(lib, data)
        print(depth, len(data), [(f["timestamp"], f["duration"], f["timescale"]) for f in frames])
        for frame in frames:
            gray, alpha = input_samples(depth, frame["index"])
            expected_alpha = bytes(alpha) if depth == 8 else struct.pack("<256H", *alpha)
            if expected_alpha != frame["native_alpha"]:
                raise RuntimeError("lossless alpha differs from native input")
            maximum = (1 << depth) - 1
            expected_rgba = bytes(channel for y, a in zip(gray, alpha) for channel in
                                  [(y * 255 + maximum // 2) // maximum] * 3 + [(a * 255 + maximum // 2) // maximum])
            if expected_rgba != frame["rgba"]:
                raise RuntimeError("actual scalar RGBA differs from native full-range UNORM")
            write(f"alpha_sequence_{depth}bit_frame{frame['index']}.rgba", frame["rgba"])
            write(f"alpha_sequence_{depth}bit_frame{frame['index']}.alpha.bin", frame["native_alpha"])
        for suffix, container in (("", data), ("_swapped_tracks", swap_tracks(data)), ("_alpha_timescale_2000", rescale_alpha(data))):
            reference = decode(lib, container)
            if reference != frames:
                raise RuntimeError(f"independent decoder changed sequence for {suffix}")
            name = f"alpha_sequence_{depth}bit{suffix}"
            write(name + ".avif", container)
            records.append({"name": name, "file": name + ".avif", "depth": depth, "result": "rgba",
                            "oracle": "actual libavif 0.11.1 track decoding and scalar RGBA; native alpha exactly equals lossless input"})
        if depth == 8:
            unlinked = bytearray(data)
            auxl = alpha_boxes(data)["auxl"]
            unlinked[auxl["start"] + 4:auxl["start"] + 8] = b"free"
            opaque = decode(lib, bytes(unlinked), expect_alpha=False)
            for original, actual in zip(frames, opaque):
                expected = bytearray(original["rgba"])
                expected[3::4] = bytes([255]) * 256
                if actual["rgba"] != bytes(expected):
                    raise RuntimeError("unassociated auxiliary changed independently decoded color")
            write("unassociated_alpha.avif", bytes(unlinked))
            records.append({"name": "unassociated_alpha", "file": "unassociated_alpha.avif", "depth": depth, "result": "opaque",
                            "oracle": "actual libavif selects primary color and reports no associated alpha"})
            for name, container in negative_cases(data):
                write(name + ".avif", container)
                records.append({"name": name, "file": name + ".avif", "depth": depth, "result": "reject",
                                "oracle": "controlled metadata corruption of independently verified sequence; expected rejection is a normative PixelForge contract, not a claim of libavif rejection parity"})
    for depth in (8, 10, 12):
        coded = encode(lib, depth, color444=True)
        original = decode(lib, coded)
        modified = bytearray(coded)
        colr = next(box for box in boxes(coded) if box["type"] == "colr")
        if coded[colr["payload"]:colr["end"]] != b"nclx" + struct.pack(">HHHB", 2, 2, 2, 128):
            raise RuntimeError("expected unspecified 444 color sample entry")
        modified[colr["payload"]:colr["end"]] = b"nclx" + struct.pack(">HHHB", 1, 13, 1, 128)
        data = bytes(modified)
        frames = decode(lib, data)
        if all(a["rgba"] == b["rgba"] for a, b in zip(original, frames)):
            raise RuntimeError("nclx709 did not change independently converted color pixels")
        name = f"nclx709_color444_alpha_{depth}bit"
        write(name + ".avif", data)
        for frame in frames:
            write(name + f"_frame{frame['index']}.rgba", frame["rgba"])
            write(name + f"_frame{frame['index']}.alpha.bin", frame["native_alpha"])
        records.append({"name": name, "file": name + ".avif", "depth": depth, "result": "rgba", "rgba_prefix": name,
                        "oracle": "actual libavif complete-track scalar RGBA; only sample-entry nclx changed from unspecified to BT709, original AV1 payloads remain untouched"})
        print(name, "actual libavif sample-entry nclx override verified")
    codec_versions = C.create_string_buffer(256)
    lib.avifCodecVersions.argtypes = [C.c_void_p]
    lib.avifCodecVersions(codec_versions)
    manifest = {"libavif_version": version, "codec_versions": codec_versions.value.decode(), "encoder": {"codec": "aom", "threads": 1, "speed": 8, "quantizers": [0, 0, 0, 0], "timescale": 1000, "durations": [100, 200, 300]},
                "references": ["https://aomediacodec.github.io/av1-avif/#auxiliary-images", "https://aomediacodec.github.io/av1-isobmff/"],
                "fixtures": records, "artifacts": artifacts}
    (FIXTURES / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    prefix = TEST.read_text(encoding="utf-8").split(MARKER, 1)[0]
    formatted = subprocess.run(["moonfmt", "-"], input=prefix + render(manifest), capture_output=True, text=True, check=True).stdout
    TEST.write_text(formatted, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
