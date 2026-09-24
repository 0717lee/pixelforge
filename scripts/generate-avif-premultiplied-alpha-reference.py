#!/usr/bin/env python3
"""Encode real premultiplied AVIF items/tracks and verify libavif RGBA oracles."""
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
OUT = ROOT / "tests/fixtures/avif-premultiplied-alpha"
TEST = ROOT / "avif_premultiplied_alpha_reference_wbtest.mbt"
WIDTH = HEIGHT = 16
DURATIONS = (100, 200, 300)


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


color = load("premultiplied_reference_color", "generate-avif-grid-sampling-color-reference.py")
animation = color.animation
checked = animation.checked


def library(path):
    lib, version = animation.library(path)
    lib.avifImageRGBToYUV.argtypes = [C.c_void_p, C.POINTER(animation.helpers.ScalarRGB0111)]
    lib.avifImageRGBToYUV.restype = C.c_int
    lib.avifEncoderWrite.argtypes = [C.c_void_p, C.c_void_p, C.POINTER(animation.RWData)]
    lib.avifEncoderWrite.restype = C.c_int
    lib.avifLibYUVVersion.restype = C.c_uint
    if lib.avifLibYUVVersion() != 0:
        raise RuntimeError("this exact scalar oracle requires libavif built without libyuv")
    return lib, version


def input_rgba(depth, frame):
    maximum = (1 << depth) - 1
    values = []
    boundary_alpha = (0, maximum, 1, 2, 3, 8, 9, 24, 25, maximum // 2)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            i = y * WIDTH + x
            a = boundary_alpha[i] if i < len(boundary_alpha) else (x * 113 + y * 197 + frame * 71) % (maximum + 1)
            # Native-depth, nonlinear premultiplied RGB; no channel exceeds A.
            r = a * (43 + (x * 17 + y * 11 + frame * 31) % 180) // 255
            g = a * (19 + (x * 7 + y * 23 + frame * 47) % 200) // 255
            b = a * (71 + (x * 29 + y * 3 + frame * 13) % 170) // 255
            if i == 2:
                r, g, b = 1, 0, 1
            if i == 7:
                r, g, b = 9, 8, 3
            values.extend((r, g, b, a))
    if any(c > values[i + 3] for i in range(0, len(values), 4) for c in values[i:i + 3]):
        raise RuntimeError("source RGB is not premultiplied")
    return values


def pack_samples(values, depth):
    return bytes(values) if depth == 8 else struct.pack(f"<{len(values)}H", *values)


def native_planes(image):
    size = 1 if image.depth == 8 else 2
    color_planes = [b"".join(C.string_at(image.planes[p] + y * image.strides[p], image.width * size)
                              for y in range(image.height)) for p in range(1 if image.format == 4 else 3)]
    alpha = b"".join(C.string_at(image.alpha + y * image.alpha_stride, image.width * size)
                     for y in range(image.height))
    return b"".join(color_planes), alpha


def encode(lib, depth, matrix, animated, monochrome=False):
    encoder = lib.avifEncoderCreate()
    if not encoder:
        raise RuntimeError("encoder allocation failed")
    options = animation.Encoder.from_address(encoder)
    options.codec, options.threads, options.speed = 1, 1, 6
    options.keyframe_interval, options.timescale = 0, 1000
    options.min_q = options.max_q = options.min_aq = options.max_aq = 0
    output = animation.RWData()
    native = []
    try:
        for index in range(3 if animated else 1):
            image = lib.avifImageCreate(WIDTH, HEIGHT, depth, 4 if monochrome else 1)
            if not image:
                raise RuntimeError("image allocation failed")
            try:
                info = color.FullImage.from_address(image)
                info.range = 1
                info.primaries, info.transfer, info.matrix = 1, 13, matrix
                info.premultiplied = 1
                rgb = animation.helpers.ScalarRGB0111()
                lib.avifRGBImageSetDefaults(C.byref(rgb), image)
                rgb.avoidLibYUV, rgb.alphaPremultiplied = 1, 1
                rgba = pack_samples(input_rgba(depth, index), depth)
                buffer = C.create_string_buffer(rgba)
                rgb.pixels, rgb.rowBytes = C.addressof(buffer), WIDTH * 4 * (1 if depth == 8 else 2)
                checked(lib.avifImageRGBToYUV(image, C.byref(rgb)), "native premultiplied RGB to YUV")
                native.append(native_planes(info))
                if animated:
                    checked(lib.avifEncoderAddImage(encoder, image, DURATIONS[index], 0), "encode premultiplied track frame")
                else:
                    checked(lib.avifEncoderWrite(encoder, image, C.byref(output)), "encode premultiplied item")
            finally:
                lib.avifImageDestroy(image)
        if animated:
            checked(lib.avifEncoderFinish(encoder, C.byref(output)), "finish premultiplied tracks")
        return C.string_at(output.data, output.size), native
    finally:
        lib.avifRWDataFree(C.byref(output))
        lib.avifEncoderDestroy(encoder)


def rgba8(lib, image, *, keep_premultiplied=False):
    rgb = animation.helpers.ScalarRGB0111()
    lib.avifRGBImageSetDefaults(C.byref(rgb), image)
    rgb.depth, rgb.avoidLibYUV, rgb.chromaUpsampling = 8, 1, 3
    rgb.alphaPremultiplied = int(keep_premultiplied)
    lib.avifRGBImageAllocatePixels(C.byref(rgb))
    try:
        checked(lib.avifImageYUVToRGB(image, C.byref(rgb)), "scalar nearest RGBA8")
        return b"".join(C.string_at(rgb.pixels + y * rgb.rowBytes, rgb.width * 4) for y in range(rgb.height))
    finally:
        lib.avifRGBImageFreePixels(C.byref(rgb))


def unpremultiply_bytes(data):
    out = bytearray(data)
    for offset in range(0, len(out), 4):
        a = out[offset + 3]
        for channel in range(3):
            c = out[offset + channel]
            out[offset + channel] = 0 if a == 0 else min(255, (c * 255 + a // 2) // a)
    return bytes(out)


def decode(lib, data, animated, depth, matrix, monochrome=False, premultiplied=True):
    decoder = lib.avifDecoderCreate()
    if not decoder:
        raise RuntimeError("decoder allocation failed")
    buffer = C.create_string_buffer(data)
    try:
        checked(lib.avifDecoderSetSource(decoder, 2 if animated else 1), "select tracks/items")
        checked(lib.avifDecoderSetIOMemory(decoder, buffer, len(data)), "set memory")
        checked(lib.avifDecoderParse(decoder), "parse real premultiplied container")
        state = animation.Decoder.from_address(decoder)
        if state.count != (3 if animated else 1) or not state.has_alpha:
            raise RuntimeError("wrong independent frame count or missing alpha")
        frames = []
        for index in range(state.count):
            checked(lib.avifDecoderNextImage(decoder), "decode real premultiplied frame")
            info = color.FullImage.from_address(state.image)
            if (info.width, info.height, info.depth, info.format, info.range, info.matrix, info.premultiplied) != (WIDTH, HEIGHT, depth, 4 if monochrome else 1, 1, matrix, int(premultiplied)):
                raise RuntimeError("libavif did not preserve prem reference or native color metadata")
            yuv, alpha = native_planes(info)
            straight = rgba8(lib, state.image)
            post8 = unpremultiply_bytes(rgba8(lib, state.image, keep_premultiplied=True)) if premultiplied else straight
            mismatch = [i for i, (a, b) in enumerate(zip(straight, post8)) if a != b]
            frames.append({"index": index, "timestamp": state.timing.pts_units,
                           "duration": state.timing.duration_units, "timescale": state.timing.timescale,
                           "rgba": straight, "alpha": alpha, "yuv": yuv,
                           "post8_mismatches": len(mismatch),
                           "first_post8_difference": None if not mismatch else {
                               "byte": mismatch[0], "native_fused": straight[mismatch[0]], "post8": post8[mismatch[0]]}})
        return frames
    finally:
        lib.avifDecoderDestroy(decoder)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def test_source(manifest):
    text = '''/// Real libavif 0.11.1 premultiplied AVIF items and stateful tracks.
/// Expected RGBA uses scalar nearest conversion; native alpha is also checked.

///|
fn avif_premultiplied_check_alpha(frame : Av1FramePlanes, expected : Array[Byte],
  offset : Int, depth : Int) -> Unit raise {
  assert_eq((frame.width, frame.height, frame.bit_depth), (16, 16, depth))
  let samples = av1_frame_crop(frame, 0)
  for i in 0..<256 {
    let value = if depth == 8 { expected[offset + i].to_int() } else {
      expected[offset + i * 2].to_int() | (expected[offset + i * 2 + 1].to_int() << 8)
    }
    assert_eq((i, samples[i]), (i, value))
  }
}

///|
fn avif_premultiplied_reference_case(data : Array[Byte], expected : Array[Byte],
  native_alpha : Array[Byte], depth : Int, animated : Bool, premultiplied : Bool) -> Unit raise {
  if animated {
    let (color, alpha) = ga_animation_tracks(data).unwrap()
    let alpha = alpha.unwrap()
    assert_eq(color.premultiplied_by.contains(alpha.id), premultiplied)
    let descriptor = avif_animation_descriptor(data).unwrap()
    assert_eq(descriptor.timescale, 1000)
    assert_eq(descriptor.frames.length(), 3)
    let decoded_alpha = ga_animation_decode_track(data, alpha).unwrap()
    let actual = avif_decode_animation(data).unwrap()
    assert_eq(actual.timescale, 1000)
    assert_eq(actual.frames.length(), 3)
    for i in 0..<3 {
      let frame = actual.frames[i]
      assert_eq((frame.index, frame.timestamp, frame.duration),
        (i, [0, 100, 300][i], [100, 200, 300][i]))
      assert_eq((frame.image.width, frame.image.height), (16, 16))
      for byte in 0..<1024 {
        assert_eq((i, byte, frame.image.data[byte]), (i, byte, expected[i * 1024 + byte]))
      }
      avif_premultiplied_check_alpha(decoded_alpha[i], native_alpha,
        i * 256 * (if depth == 8 { 1 } else { 2 }), depth)
    }
  } else {
    let descriptor = avif_alpha_item_descriptor(data).unwrap()
    assert_eq(descriptor.premultiplied, premultiplied)
    assert_eq(descriptor.bit_depth, depth)
    let actual = avif_decode_rgba(data).unwrap()
    assert_eq((actual.width, actual.height), (16, 16))
    for byte in 0..<1024 {
      assert_eq((byte, actual.data[byte]), (byte, expected[byte]))
    }
    let alpha = av1_decode_frame_planes(avif_alpha_item_payload(data).unwrap(),
      allow_monochrome=true).unwrap()
    avif_premultiplied_check_alpha(alpha, native_alpha, 0, depth)
  }
}
'''
    for prefix in sorted({case["reference"] for case in manifest["cases"]}):
        count = 3 if prefix.startswith("animation") else 1
        for suffix, variable in (("rgba", "pixels"), ("alpha.bin", "alpha")):
            blob = b"".join((OUT / f"{prefix}_frame{i}.{suffix}").read_bytes() for i in range(count))
            text += "\n///|\n" + animation.array(f"prem_{prefix}_{variable}", blob)
    for case in manifest["cases"]:
        text += f'\n///|\ntest "actual libavif premultiplied {case["name"]}" {{\n'
        text += animation.array("container", (OUT / case["file"]).read_bytes(), "  ")
        prefix = case["reference"]
        text += f'  avif_premultiplied_reference_case(container, prem_{prefix}_pixels, prem_{prefix}_alpha, {case["depth"]}, {str(case["animated"]).lower()}, {str(case["premultiplied"]).lower()})\n}}\n'
    return text


def verify_case(lib, case, native=None):
    data = (OUT / case["file"]).read_bytes()
    frames = decode(lib, data, case["animated"], case["depth"], case["matrix"], case["monochrome"], case["premultiplied"])
    for index, frame in enumerate(frames):
        prefix = f'{case["reference"]}_frame{index}'
        for key, suffix in (("rgba", "rgba"), ("alpha", "alpha.bin"), ("yuv", "yuv.bin")):
            if frame[key] != (OUT / f"{prefix}.{suffix}").read_bytes():
                raise RuntimeError(f'{case["name"]} frame {index}: independent {key} differs')
        expected_alpha = pack_samples(input_rgba(case["depth"], index)[3::4], case["depth"])
        if frame["alpha"] != expected_alpha:
            raise RuntimeError("lossless native alpha differs from original input")
        if native is not None and (frame["yuv"], frame["alpha"]) != native[index]:
            raise RuntimeError("lossless native planes differ from encoder input")
        recorded = case["frames"][index]
        for key in ("timestamp", "duration", "timescale", "post8_mismatches", "first_post8_difference"):
            if frame[key] != recorded[key]:
                raise RuntimeError(f'{case["name"]}: independent {key} changed')
    if case["premultiplied"] and case["matrix"] in (0, 8) and not any(frame["post8_mismatches"] for frame in frames):
        raise RuntimeError("fixture does not distinguish native alpha fusion from RGBA8 postprocessing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--libavif", default="avif.dll")
    parser.add_argument("--check", action="store_true", help="redecode and verify existing artifacts without writing files")
    args = parser.parse_args()
    lib, version = library(args.libavif)
    if args.check:
        manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
        for name, digest in manifest["artifacts"].items():
            if sha((OUT / name).read_bytes()) != digest:
                raise RuntimeError(f"artifact hash mismatch: {name}")
        for case in manifest["cases"]:
            verify_case(lib, case)
        if animation.canonical(TEST.read_text(encoding="utf-8")) != animation.canonical(test_source(manifest)):
            raise RuntimeError("whitebox fixtures differ from independently decoded references")
        print(f'Independently redecoded {len(manifest["cases"])} premultiplied fixtures; no files changed.')
        return
    OUT.mkdir(parents=True, exist_ok=True)
    artifacts, cases = {}, []
    def write(name, blob):
        (OUT / name).write_bytes(blob)
        artifacts[name] = sha(blob)
    for matrix, depth, monochrome in ((6, 8, False), (6, 10, False), (6, 12, False), (0, 10, False), (0, 12, False), (8, 10, False), (8, 10, True)):
        for animated in ((False,) if monochrome else (False, True)):
            prefix = f'{"animation" if animated else "static"}_{"mono_" if monochrome else ""}matrix{matrix}_{depth}bit'
            data, native = encode(lib, depth, matrix, animated, monochrome)
            frames = decode(lib, data, animated, depth, matrix, monochrome)
            write(prefix + ".avif", data)
            for frame in frames:
                for key, suffix in (("rgba", "rgba"), ("alpha", "alpha.bin"), ("yuv", "yuv.bin")):
                    write(f'{prefix}_frame{frame["index"]}.{suffix}', frame[key])
            case = {"name": prefix, "file": prefix + ".avif", "reference": prefix,
                    "animated": animated, "depth": depth, "matrix": matrix, "monochrome": monochrome,
                    "premultiplied": True, "frames": [{k: v for k, v in frame.items() if k not in ("rgba", "alpha", "yuv")} for frame in frames]}
            verify_case(lib, case, native)
            cases.append(case)
            print(prefix, "bytes", len(data), "post8 differences", [f["post8_mismatches"] for f in frames], flush=True)
            if animated and (matrix, depth) in ((6, 8), (0, 12)):
                name = prefix + "_swapped_tracks"
                write(name + ".avif", animation.swap_tracks(data))
                swapped = {**case, "name": name, "file": name + ".avif"}
                verify_case(lib, swapped, native)
                cases.append(swapped)
            if (matrix, depth, monochrome) == (6, 8, False):
                changed = bytearray(data)
                if animated:
                    prem = next(box for box in animation.boxes(data) if box["type"] == "prem")
                    # Track 1 is the selected color, whereas alpha is track 2.
                    changed[prem["payload"]:prem["end"]] = (1).to_bytes(4, "big")
                    name = prefix + "_prem_targets_color"
                else:
                    # Item reference is from:16, count:16, to:16 (iref v0).
                    at = data.index(b"prem") + 4
                    if data[at:at + 6] != bytes.fromhex("000100010002"):
                        raise RuntimeError("unexpected libavif prem item IDs")
                    changed[at:at + 6] = bytes.fromhex("000200010001")
                    name = prefix + "_reversed_prem"
                changed = bytes(changed)
                controls = decode(lib, changed, animated, depth, matrix, premultiplied=False)
                if all(control["rgba"] == original["rgba"] for control, original in zip(controls, frames)):
                    raise RuntimeError("prem reference control does not change output")
                write(name + ".avif", changed)
                for frame in controls:
                    for key, suffix in (("rgba", "rgba"), ("alpha", "alpha.bin"), ("yuv", "yuv.bin")):
                        write(f'{name}_frame{frame["index"]}.{suffix}', frame[key])
                control = {**case, "name": name, "file": name + ".avif", "reference": name,
                           "premultiplied": False, "mutation": "only prem reference source/target changed; AV1 samples untouched",
                           "frames": [{k: v for k, v in frame.items() if k not in ("rgba", "alpha", "yuv")} for frame in controls]}
                verify_case(lib, control, native)
                cases.append(control)
    codec_versions = C.create_string_buffer(256)
    lib.avifCodecVersions.argtypes = [C.c_void_p]
    lib.avifCodecVersions(codec_versions)
    manifest = {"libavif_version": version, "libyuv_version": lib.avifLibYUVVersion(),
                "codec_versions": codec_versions.value.decode(), "width": WIDTH, "height": HEIGHT,
                "encoder": {"codec": "aom", "speed": 6, "threads": 1, "color_quantizer": 0, "alpha_quantizer": 0},
                "oracle": {"source": "actual libavif decoding; PixelForge is never used for expected values",
                           "rgb_depth": 8, "avoidLibYUV": 1, "chromaUpsampling": 3, "alphaPremultiplied": 0,
                           "native_lossless_checked": True,
                           "source_premultiplication": "native nonlinear RGB channels are each between zero and native alpha",
                           "prem_references": "written by libavif encoder and confirmed by libavif decoder alphaPremultiplied",
                           "rounding_discriminator": "compare actual straight RGBA against separately quantized premultiplied RGBA8 then integer unpremultiply"},
                "references": ["https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/reformat.c#L1261",
                               "https://github.com/AOMediaCodec/libavif/blob/v0.11.1/src/alpha.c#L231"],
                "cases": cases, "artifacts": artifacts}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    formatted = subprocess.run(["moonfmt", "-"], input=test_source(manifest), capture_output=True, text=True, check=True).stdout
    TEST.write_text(formatted, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
