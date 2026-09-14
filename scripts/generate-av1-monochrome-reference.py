#!/usr/bin/env python3
"""Generate real full-range monochrome AV1 and assembled AVIF alpha references.

Libaom receives native-depth Y samples through Y4M. FFmpeg/libdav1d must report
the matching gray pixel format before raw extraction, and its result must equal
the dav1d CLI result. Alpha containers are explicitly BMFF assembly of existing
real AV1 image payloads; they are independently decoded by Pillow/libavif.
"""

from __future__ import annotations

import argparse
import ctypes
import importlib.util
import itertools
import json
import re
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image, features


sys.dont_write_bytecode = True
helper_path = Path(__file__).with_name("generate-av1-cdef-frame-reference.py")
helper_spec = importlib.util.spec_from_file_location("av1_cdef_reference_helpers", helper_path)
assert helper_spec is not None and helper_spec.loader is not None
helpers = importlib.util.module_from_spec(helper_spec)
helper_spec.loader.exec_module(helpers)
run = helpers.run
sha256 = helpers.sha256
trace_value = helpers.helpers.helpers.trace_value
rle = helpers.helpers.helpers.rle


class ScalarRGB0111(ctypes.Structure):
    """ABI from the installed, version-checked libavif 0.11.1 public header."""
    _fields_ = [
        ("width", ctypes.c_uint32), ("height", ctypes.c_uint32), ("depth", ctypes.c_uint32),
        ("format", ctypes.c_int), ("chromaUpsampling", ctypes.c_int), ("chromaDownsampling", ctypes.c_int),
        ("avoidLibYUV", ctypes.c_int), ("ignoreAlpha", ctypes.c_int), ("alphaPremultiplied", ctypes.c_int),
        ("isFloat", ctypes.c_int), ("pixels", ctypes.c_void_p), ("rowBytes", ctypes.c_uint32),
    ]


class ScalarImagePrefix0111(ctypes.Structure):
    _fields_ = [("width", ctypes.c_uint32), ("height", ctypes.c_uint32), ("depth", ctypes.c_uint32),
                ("yuvFormat", ctypes.c_int), ("yuvRange", ctypes.c_int)]


def scalar_library(path: str):
    library = ctypes.CDLL(path)
    library.avifVersion.restype = ctypes.c_char_p
    version = library.avifVersion().decode()
    if version != "0.11.1":
        raise RuntimeError(f"scalar reference binding requires the recorded libavif 0.11.1 ABI, found {version}")
    library.avifImageCreateEmpty.restype = ctypes.c_void_p
    library.avifDecoderCreate.restype = ctypes.c_void_p
    library.avifDecoderReadMemory.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    library.avifDecoderReadMemory.restype = ctypes.c_int
    library.avifRGBImageSetDefaults.argtypes = [ctypes.POINTER(ScalarRGB0111), ctypes.c_void_p]
    library.avifRGBImageAllocatePixels.argtypes = [ctypes.POINTER(ScalarRGB0111)]
    library.avifImageYUVToRGB.argtypes = [ctypes.c_void_p, ctypes.POINTER(ScalarRGB0111)]
    library.avifImageYUVToRGB.restype = ctypes.c_int
    library.avifRGBImageFreePixels.argtypes = [ctypes.POINTER(ScalarRGB0111)]
    library.avifImageDestroy.argtypes = [ctypes.c_void_p]
    library.avifDecoderDestroy.argtypes = [ctypes.c_void_p]
    return library, version


def scalar_rgba(data: bytes, library, *, range_override: int | None = None) -> bytes:
    image = library.avifImageCreateEmpty()
    decoder = library.avifDecoderCreate()
    rgb = ScalarRGB0111()
    try:
        if not image or not decoder:
            raise RuntimeError("libavif scalar reference allocation failed")
        buffer = ctypes.create_string_buffer(data)
        result = library.avifDecoderReadMemory(decoder, image, buffer, len(data))
        if result:
            raise RuntimeError(f"libavif scalar reference decode failed: {result}")
        if range_override is not None:
            if range_override not in (0, 1):
                raise RuntimeError("invalid scalar range override")
            ScalarImagePrefix0111.from_address(image).yuvRange = range_override
        library.avifRGBImageSetDefaults(ctypes.byref(rgb), image)
        rgb.depth = 8
        rgb.avoidLibYUV = 1
        library.avifRGBImageAllocatePixels(ctypes.byref(rgb))
        if not rgb.pixels:
            raise RuntimeError("libavif scalar RGBA allocation failed")
        result = library.avifImageYUVToRGB(image, ctypes.byref(rgb))
        if result:
            raise RuntimeError(f"libavif scalar conversion failed: {result}")
        return b"".join(ctypes.string_at(rgb.pixels + y * rgb.rowBytes, rgb.width * 4) for y in range(rgb.height))
    finally:
        if rgb.pixels:
            library.avifRGBImageFreePixels(ctypes.byref(rgb))
        if image:
            library.avifImageDestroy(image)
        if decoder:
            library.avifDecoderDestroy(decoder)


def pack(values: list[int], depth: int) -> bytes:
    return bytes(values) if depth == 8 else struct.pack(f"<{len(values)}H", *values)


def unpack(data: bytes, count: int, depth: int) -> list[int]:
    if len(data) != count * (1 if depth == 8 else 2):
        raise RuntimeError(f"unexpected native gray reference length: {len(data)}")
    values = list(data) if depth == 8 else list(struct.unpack(f"<{count}H", data))
    if any(value >= 1 << depth for value in values):
        raise RuntimeError("gray sample exceeds coded bit depth")
    return values


def read_hashed(path: Path, expected_sha256: str) -> bytes:
    data = path.read_bytes()
    if sha256(data) != expected_sha256:
        raise RuntimeError(f"reference hash mismatch: {path}")
    return data


def verify_generated_test(manifest: dict[str, object], source: str, moonfmt: str) -> None:
    path = Path(manifest["generated_test"])
    existing = read_hashed(path, manifest["generated_test_sha256"])
    generated = run([moonfmt, "-"], input_text=source).stdout.encode("utf-8")
    if generated != existing:
        raise RuntimeError(f"canonical references did not reproduce the existing test: {path}")
    print(f"verified unchanged {path}: SHA256 {sha256(generated)}")


def box(typ: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload) + 8) + typ + payload


def full_box(typ: bytes, version: int, flags: int, payload: bytes) -> bytes:
    return box(typ, bytes([version]) + flags.to_bytes(3, "big") + payload)


def box_payloads(data: bytes, wanted: bytes) -> list[bytes]:
    out = []
    position = 0
    while position < len(data):
        size, typ = struct.unpack_from(">I4s", data, position)
        if size < 8 or position + size > len(data):
            raise RuntimeError("unsupported or truncated source AVIF box")
        payload = data[position + 8:position + size]
        if typ == wanted:
            out.append(payload)
        if typ == b"meta":
            out.extend(box_payloads(payload[4:], wanted))
        elif typ in (b"iprp", b"ipco"):
            out.extend(box_payloads(payload, wanted))
        position += size
    return out


def assemble_alpha_avif(color: bytes, alpha: bytes, depth: int) -> tuple[bytes, dict[str, object]]:
    # Both source files are real one-item AVIFs remuxed from untouched encoder
    # outputs. Reuse their validated item data and AV1 configuration records.
    color_data = box_payloads(color, b"mdat")
    alpha_data = box_payloads(alpha, b"mdat")
    color_config = box_payloads(color, b"av1C")
    alpha_config = box_payloads(alpha, b"av1C")
    color_info = box_payloads(color, b"colr")
    if any(len(values) != 1 for values in (color_data, alpha_data, color_config, alpha_config, color_info)):
        raise RuntimeError("alpha assembly needs one coded item and one configuration per source AVIF")
    ftyp = box(b"ftyp", b"avif" + bytes(4) + b"avifmif1miaf")
    hdlr = full_box(b"hdlr", 0, 0, bytes(4) + b"pict" + bytes(12) + b"PixelForge reference\0")
    pitm = full_box(b"pitm", 0, 0, struct.pack(">H", 1))
    color_infe = full_box(b"infe", 2, 0, struct.pack(">HH", 1, 0) + b"av01Color\0")
    alpha_infe = full_box(b"infe", 2, 1, struct.pack(">HH", 2, 0) + b"av01Alpha\0")
    iinf = full_box(b"iinf", 0, 0, struct.pack(">H", 2) + color_infe + alpha_infe)
    properties = [
        full_box(b"ispe", 0, 0, struct.pack(">II", 64, 64)),
        full_box(b"pixi", 0, 0, bytes([3, depth, depth, depth])),
        box(b"av1C", color_config[0]), box(b"colr", color_info[0]),
        full_box(b"pixi", 0, 0, bytes([1, depth])), box(b"av1C", alpha_config[0]),
        full_box(b"auxC", 0, 0, b"urn:mpeg:mpegB:cicp:systems:auxiliary:alpha\0"),
    ]
    ipco = box(b"ipco", b"".join(properties))
    ipma = full_box(b"ipma", 0, 0, struct.pack(">IHB", 2, 1, 4) + bytes([1, 2, 0x83, 4]) + struct.pack(">HB", 2, 4) + bytes([1, 5, 0x86, 0x87]))
    iprp = box(b"iprp", ipco + ipma)
    # 'auxl' points from the auxiliary alpha image (2) to primary color (1).
    iref = full_box(b"iref", 0, 0, box(b"auxl", struct.pack(">HHH", 2, 1, 1)))

    def meta(data_start: int) -> bytes:
        lengths = (len(color_data[0]), len(alpha_data[0]))
        offsets = (data_start, data_start + lengths[0])
        locations = b"\x44\x00" + struct.pack(">H", 2)
        for item_id, offset, length in zip((1, 2), offsets, lengths):
            locations += struct.pack(">HHHII", item_id, 0, 1, offset, length)
        iloc = full_box(b"iloc", 0, 0, locations)
        return full_box(b"meta", 0, 0, hdlr + pitm + iloc + iinf + iprp + iref)

    placeholder = meta(0)
    actual_meta = meta(len(ftyp) + len(placeholder) + 8)
    result = ftyp + actual_meta + box(b"mdat", color_data[0] + alpha_data[0])
    return result, {
        "construction": "standards BMFF container assembly, not encoder output; real AV1 item data/configuration copied from existing source AVIFs",
        "primary_item": 1, "alpha_item": 2, "auxl_from": 2, "auxl_to": 1,
        "aux_type": "urn:mpeg:mpegB:cicp:systems:auxiliary:alpha",
        "color_item_sha256": sha256(color_data[0]), "alpha_item_sha256": sha256(alpha_data[0]),
        "color_av1c_hex": color_config[0].hex(), "alpha_av1c_hex": alpha_config[0].hex(),
    }


def generate_test(records: list[dict[str, object]], alpha_records: list[dict[str, object]], base: Path) -> str:
    source = """/// Generated by scripts/generate-av1-monochrome-reference.py.
/// Native Y is independently decoded with dav1d. Eight-bit UNORM samples come
/// from actual scalar libavif conversion with avoidLibYUV=1.
fn av1_mono_reference_compare(
  stream : Array[Byte], avif : Array[Byte], width : Int, height : Int,
  bit_depth : Int, y_runs : Array[Int], gray8_runs : Array[Int],
) -> Unit raise {
  let reference = av1_reference_planes_expand(y_runs)
  let gray8 = av1_reference_planes_expand(gray8_runs)
  assert_eq(reference.length(), width * height)
  assert_eq(gray8.length(), width * height)
  let frame = av1_decode_frame_planes(stream, allow_monochrome=true).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, bit_depth))
  assert_eq(frame.planes.length(), 1)
  let native = av1_frame_crop(frame, 0)
  assert_eq(native.length(), reference.length())
  for index in 0..<reference.length() {
    assert_eq((index, native[index]), (index, reference[index]))
  }
  let alpha = av1_decode_alpha(stream).unwrap()
  assert_eq(alpha.length(), reference.length())
  let image = av1_decode(stream).unwrap()
  let container_image = avif_decode_rgba(avif).unwrap()
  assert_eq((image.width, image.height), (width, height))
  assert_eq((container_image.width, container_image.height), (width, height))
  for index in 0..<gray8.length() {
    let expected = gray8[index].to_byte()
    let x = index % width
    let y = index / width
    assert_eq((index, alpha[index]), (index, expected))
    assert_eq(image.get_pixel(x, y), (expected, expected, expected, b'\\xFF'))
    assert_eq(container_image.get_pixel(x, y), (expected, expected, expected, b'\\xFF'))
  }
}

///|
fn av1_mono_alpha_pair_compare(
  primary : Array[Byte], container : Array[Byte], alpha_runs : Array[Int],
) -> Unit raise {
  let expected_alpha = av1_reference_planes_expand(alpha_runs)
  let color = avif_decode(primary).unwrap()
  let image = avif_decode_rgba(container).unwrap()
  let alpha = avif_decode_alpha(container).unwrap()
  assert_eq((image.width, image.height), (color.width, color.height))
  assert_eq(expected_alpha.length(), color.width * color.height)
  assert_eq(alpha.length(), expected_alpha.length())
  for index in 0..<expected_alpha.length() {
    let x = index % color.width
    let y = index / color.width
    let expected = color.get_pixel(x, y)
    let actual = image.get_pixel(x, y)
    assert_eq((index, actual.0, actual.1, actual.2), (index, expected.0, expected.1, expected.2))
    assert_eq((index, actual.3.to_int()), (index, expected_alpha[index]))
    assert_eq((index, alpha[index].to_int()), (index, expected_alpha[index]))
  }
}
"""

    def byte_array(label: str, data: bytes) -> str:
        rows = ["    " + ", ".join(f"b'\\x{value:02X}'" for value in data[i:i + 12]) + "," for i in range(0, len(data), 12)]
        return f"  let {label} : Array[Byte] = [\n" + "\n".join(rows) + "\n  ]\n"

    for case in records:
        width, height = case["dimensions"]
        native = unpack(read_hashed(base / case["reference_file"], case["reference_sha256"]), width * height, case["bit_depth"])
        gray8 = unpack(read_hashed(base / case["gray8_reference_file"], case["gray8_reference_sha256"]), width * height, 8)
        source += f'\n///|\ntest "external mono native and UNORM {case["name"]}" {{\n'
        source += byte_array("stream", read_hashed(base / case["obu_file"], case["obu_sha256"]))
        source += byte_array("avif", read_hashed(base / case["avif_file"], case["avif_sha256"]))
        source += "  let y_runs : Array[Int] = " + helpers.helpers.helpers.array(rle(native)) + "\n"
        source += "  let gray8_runs : Array[Int] = " + helpers.helpers.helpers.array(rle(gray8)) + "\n"
        source += f'  av1_mono_reference_compare(stream, avif, {width}, {height}, {case["bit_depth"]}, y_runs, gray8_runs)\n}}\n'
    for case in alpha_records:
        source += f'\n///|\ntest "external AVIF scalar alpha {case["bit_depth"]}bit full range" {{\n'
        source += byte_array("primary", read_hashed(Path(case["color_source_avif"]), case["color_source_sha256"]))
        source += byte_array("container", read_hashed(base / case["file"], case["sha256"]))
        alpha_case = next(record for record in records if record["name"] == case["alpha_case"])
        width, height = alpha_case["dimensions"]
        alpha8 = unpack(read_hashed(base / case["alpha8_reference_file"], case["alpha8_reference_sha256"]), width * height, 8)
        source += "  let alpha_runs : Array[Int] = " + helpers.helpers.helpers.array(rle(alpha8)) + "\n"
        source += "  av1_mono_alpha_pair_compare(primary, container, alpha_runs)\n}\n"
    return source


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("tests/fixtures/av1-cdef-frame/manifest.json"))
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-monochrome"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe") or "ffprobe")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--test", type=Path, help="optional generated white-box test path")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--verify-existing-test", action="store_true", help="regenerate the recorded test in memory from hashed references; require unchanged bytes without encoding or writing files")
    args = parser.parse_args()
    if args.verify_existing_test:
        manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        verify_generated_test(manifest, generate_test(manifest["fixtures"], manifest["alpha_containers"], args.out), args.moonfmt)
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    scalar, scalar_version = scalar_library(args.libavif_scalar)
    source_manifest = json.loads(args.source.read_text(encoding="utf-8"))
    source_cases = {case["name"]: case for case in source_manifest["fixtures"]}
    help_result = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", help_result.stdout + help_result.stderr)
    if encoder_version is None:
        raise RuntimeError("could not identify aomenc version")
    cli_version_result = run([args.dav1d, "--version"])
    cli_version = (cli_version_result.stdout + cli_version_result.stderr).strip()
    if not cli_version:
        raise RuntimeError("empty dav1d CLI version")
    ffmpeg_version = run([args.ffmpeg, "-version"]).stdout.splitlines()
    ffmpeg_decoder_version = None
    records = []
    for depth, (width, quantizer) in itertools.product((8, 10, 12), ((64, 30), (128, 30), (64, 0))):
        lossless = quantizer == 0
        height = 64
        columns = 1 if width == 64 else 2
        name = f"mono_{width}x64_{columns}tile_{depth}bit_q{quantizer}"
        source_path = args.out / f"{name}.source.yuv"
        input_path = args.out / f"{name}.input.y4m"
        obu_path = args.out / f"{name}.obu"
        reference_path = args.out / f"{name}.reference.yuv"
        unfiltered_path = args.out / f"{name}.unfiltered.yuv"
        if lossless:
            maximum = (1 << depth) - 1
            samples = [(index * maximum + 2047) // 4095 for index in range(4096)]
            pattern = {"y": "(index*((1<<bit_depth)-1)+2047)//4095, index=0..4095", "purpose": "full-range alpha ramp including endpoints and low values"}
        else:
            samples = helpers.input_planes(width, height, depth, 1)[0]
            pattern = {**helpers.INPUT_PATTERN, "selected_plane": "y", "amplitude": 1}
        source_data = pack(samples, depth)
        source_path.write_bytes(source_data)
        if depth == 8:
            chroma_type, encoded_input = "mono", source_data
        else:
            # aomenc 3.6 accepts C420p10/12 but not Cmono10/12. The dummy UV
            # carrier is ignored by --monochrome; Y remains native and exact.
            chroma_type = f"420p{depth}"
            encoded_input = source_data + pack([1 << (depth - 1)] * (width * height // 2), depth)
        y4m_header = f"YUV4MPEG2 W{width} H64 F1:1 Ip A1:1 C{chroma_type} XCOLORRANGE=FULL\nFRAME\n".encode()
        input_path.write_bytes(y4m_header + encoded_input)
        template = source_cases[f"cdef_{width}x64_{columns}tile_{depth}bit"]
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        encode.insert(1, "--monochrome")
        for flag, value in {"--cq-level": quantizer, "--lossless": int(lossless), "--enable-cdef": int(not lossless)}.items():
            index = next(index for index, argument in enumerate(encode) if argument.startswith(flag + "="))
            encode[index] = f"{flag}={value}"
        output_index = encode.index("-o")
        encode[output_index + 1] = str(obu_path)
        encode[output_index + 2] = str(input_path)
        run(encode)
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        fields = {field: trace_value(trace, field) for field in (
            "seq_profile", "reduced_still_picture_header", "high_bitdepth", "mono_chrome", "color_range",
            "use_128x128_superblock", "enable_cdef", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter",
            "base_q_idx", "delta_q_y_dc.delta_coded", "using_qmatrix", "segmentation_enabled",
            "max_frame_width_minus_1", "max_frame_height_minus_1", "tile_cols_log2", "tile_rows_log2",
        )}
        if fields["mono_chrome"] != 1 or fields["color_range"] != 1 or fields["reduced_still_picture_header"] != 1:
            raise RuntimeError(f"{name}: expected full-range monochrome reduced still header")
        if fields["seq_profile"] != (2 if depth == 12 else 0) or fields["high_bitdepth"] != (depth > 8):
            raise RuntimeError(f"{name}: unexpected coded profile/bit depth")
        if fields["max_frame_width_minus_1"] != width - 1 or fields["max_frame_height_minus_1"] != 63 or fields["tile_cols_log2"] != columns - 1 or fields["tile_rows_log2"] != 0:
            raise RuntimeError(f"{name}: unexpected dimensions or tile grid")
        if depth == 12:
            fields["twelve_bit"] = trace_value(trace, "twelve_bit")
            if fields["twelve_bit"] != 1:
                raise RuntimeError(f"{name}: expected twelve_bit")
        if any(fields[key] for key in ("use_128x128_superblock", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "delta_q_y_dc.delta_coded", "using_qmatrix", "segmentation_enabled")):
            raise RuntimeError(f"{name}: unexpected unsupported frame tool")
        if re.search(r"\bdelta_q_[uv]", trace):
            raise RuntimeError(f"{name}: monochrome header unexpectedly contains chroma quantization syntax")
        loop_levels = [int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]
        if any(loop_levels) or (not lossless and not loop_levels):
            raise RuntimeError(f"{name}: unexpected loop filter")
        cdef = None
        if lossless:
            if fields["base_q_idx"] != 0 or fields["enable_cdef"] != 0:
                raise RuntimeError(f"{name}: expected lossless q0 without CDEF")
        else:
            fields["tx_mode"] = trace_value(trace, "tx_mode")
            fields["delta_q_present"] = trace_value(trace, "delta_q_present")
            if fields["tx_mode"] != 1 or fields["delta_q_present"] != 0 or fields["enable_cdef"] != 1:
                raise RuntimeError(f"{name}: expected largest transforms and CDEF")
            bits = trace_value(trace, "cdef_bits")
            cdef = {"bits": bits, "damping_minus_3": trace_value(trace, "cdef_damping_minus_3"),
                    "y_primary": helpers.trace_array(trace, "cdef_y_pri_strength", 1 << bits),
                    "y_secondary_raw": helpers.trace_array(trace, "cdef_y_sec_strength", 1 << bits)}
            if not any(cdef["y_primary"] + cdef["y_secondary_raw"]):
                raise RuntimeError(f"{name}: encoder chose all-zero CDEF")
        gray_format = "gray" if depth == 8 else f"gray{depth}le"
        probe_command = [args.ffprobe, "-v", "error", "-show_entries", "stream=width,height,pix_fmt,color_range", "-of", "json", str(obu_path)]
        stream_info = json.loads(run(probe_command).stdout)["streams"]
        if len(stream_info) != 1 or stream_info[0]["pix_fmt"] != gray_format or stream_info[0]["width"] != width or stream_info[0]["height"] != height:
            raise RuntimeError(f"{name}: native decoder format is not the requested grayscale: {stream_info}")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(obu_path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", gray_format, str(reference_path)]
        result = run(decode)
        versions = re.findall(r"libdav1d\s+([0-9][^\s]*)", result.stderr)
        if not versions or (ffmpeg_decoder_version is not None and versions[0] != ffmpeg_decoder_version):
            raise RuntimeError("missing or inconsistent FFmpeg dav1d version")
        ffmpeg_decoder_version = versions[0]
        reference = reference_path.read_bytes()
        values = unpack(reference, width * height, depth)
        if lossless and reference != source_data:
            raise RuntimeError(f"{name}: lossless native samples differ from the source")
        cli_temp = args.out / f"{name}.cli.tmp.yuv"
        cli_all = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_temp), "--limit", "1", "--inloopfilters", "all"]
        helpers.run_binary(cli_all)
        if cli_temp.read_bytes() != reference:
            raise RuntimeError(f"{name}: CLI native Y differs from FFmpeg, possibly a conversion")
        cli_temp.unlink()
        cli_nocdef = cli_all.copy()
        cli_nocdef[cli_nocdef.index("--output") + 1] = str(unfiltered_path)
        cli_nocdef[-1] = "nocdef"
        helpers.run_binary(cli_nocdef)
        unfiltered = unpack(unfiltered_path.read_bytes(), width * height, depth)
        changed = [i for i, (a, b) in enumerate(zip(values, unfiltered)) if a != b]
        if not lossless and not changed:
            raise RuntimeError(f"{name}: CDEF had no actual sample effect")
        avif_path = args.out / f"{name}.avif"
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
        run(wrap)
        mono_rgba = scalar_rgba(avif_path.read_bytes(), scalar)
        gray8 = mono_rgba[0::4]
        maximum = (1 << depth) - 1
        normalized_gray = bytes((value * 255 + maximum // 2) // maximum for value in values)
        if gray8 != normalized_gray or mono_rgba[1::4] != gray8 or mono_rgba[2::4] != gray8 or any(value != 255 for value in mono_rgba[3::4]):
            raise RuntimeError(f"{name}: scalar libavif monochrome conversion differs from full-range UNORM")
        gray8_path = args.out / f"{name}.gray8.scalar.reference"
        gray8_path.write_bytes(gray8)
        records.append({
            "name": name, "dimensions": [width, height], "bit_depth": depth, "monochrome": True, "full_range": True,
            "quantizer": quantizer, "lossless": lossless, "tile_grid": [columns, 1], "partition_size": 16,
            "input_pattern": pattern, "source_file": source_path.name, "source_sha256": sha256(source_data),
            "encoder_input_file": input_path.name, "encoder_input_sha256": sha256(input_path.read_bytes()),
            "y4m_note": "Cmono at 8 bits; C420p10/12 with ignored neutral UV carrier and --monochrome at high depth; XCOLORRANGE=FULL",
            "obu_file": obu_path.name, "obu_bytes": obu_path.stat().st_size, "obu_sha256": sha256(obu_path.read_bytes()),
            "avif_file": avif_path.name, "avif_sha256": sha256(avif_path.read_bytes()),
            "reference_file": reference_path.name, "reference_sha256": sha256(reference), "reference_samples": len(values),
            "reference_minimum": min(values), "reference_maximum": max(values), "reference_unique_count": len(set(values)),
            "gray8_reference_file": gray8_path.name, "gray8_reference_sha256": sha256(gray8),
            "native_reference_format": gray_format, "probe_stream": stream_info[0], "cli_matches_ffmpeg": True,
            "lossless_reference_matches_source": True if lossless else None,
            "unfiltered_file": unfiltered_path.name, "unfiltered_sha256": sha256(unfiltered_path.read_bytes()),
            "cdef_changed_samples": len(changed), "cdef_changed_left_of_seam": sum(62 <= i % width < 64 for i in changed) if columns == 2 else 0,
            "cdef_changed_right_of_seam": sum(64 <= i % width < 66 for i in changed) if columns == 2 else 0,
            "header_trace": fields, "cdef": cdef, "loop_filter_levels": loop_levels,
            "commands": {"encode": encode, "trace_headers": trace_command, "probe_native_format": probe_command, "decode_reference": decode, "dav1d_cli_all": cli_all, "dav1d_cli_nocdef_same_obu": cli_nocdef, "wrap_avif": wrap},
        })
        print(f"generated {name}: OBU={obu_path.stat().st_size}, native={gray_format}, CDEF changes={len(changed)}, Y=[{min(values)},{max(values)}], lossless exact={lossless}", flush=True)
    limited_vectors = []
    for depth in (8, 10, 12):
        case = next(case for case in records if case["name"] == f"mono_64x64_1tile_{depth}bit_q0")
        native = unpack((args.out / case["reference_file"]).read_bytes(), 4096, depth)
        limited_rgba = scalar_rgba((args.out / case["avif_file"]).read_bytes(), scalar, range_override=0)
        scale = 1 << (depth - 8)
        inputs = [0, 15 * scale, 16 * scale, 128 * scale, 235 * scale, 236 * scale, (1 << depth) - 1]
        output = [limited_rgba[native.index(value) * 4] for value in inputs]
        limited_vectors.append({"bit_depth": depth, "native_y": inputs, "gray8": output,
                                "source_avif": case["avif_file"],
                                "method": "decode source without sample changes, override avifImage.yuvRange=AVIF_RANGE_LIMITED in memory, convert with avoidLibYUV=1; no OBU modification"})
    alpha_records = []
    for depth in (8, 10, 12):
        alpha_case = next(case for case in records if case["name"] == f"mono_64x64_1tile_{depth}bit_q0")
        color_case = source_cases[f"cdef_64x64_1tile_{depth}bit"]
        color_path = args.source.parent / color_case["avif_file"]
        alpha_path = args.out / alpha_case["avif_file"]
        container, assembly = assemble_alpha_avif(color_path.read_bytes(), alpha_path.read_bytes(), depth)
        pair_path = args.out / f"color_alpha_{depth}bit.avif"
        pair_path.write_bytes(container)
        with Image.open(pair_path) as image:
            if image.size != (64, 64):
                raise RuntimeError("libavif decoded unexpected alpha-pair dimensions")
            pillow_rgba = image.convert("RGBA").tobytes()
        pillow_alpha = pillow_rgba[3::4]
        rgba = scalar_rgba(container, scalar)
        alpha8 = rgba[3::4]
        native = unpack((args.out / alpha_case["reference_file"]).read_bytes(), 4096, depth)
        maximum = (1 << depth) - 1
        normalized = bytes((value * 255 + maximum // 2) // maximum for value in native)
        if alpha8 != normalized:
            raise RuntimeError(f"{depth}-bit: scalar libavif alpha differs from normalized round-to-nearest")
        rgba_path = args.out / f"color_alpha_{depth}bit.scalar_libavif.rgba"
        alpha8_path = args.out / f"color_alpha_{depth}bit.alpha8.reference"
        pillow_path = args.out / f"color_alpha_{depth}bit.pillow.rgba"
        rgba_path.write_bytes(rgba)
        alpha8_path.write_bytes(alpha8)
        pillow_path.write_bytes(pillow_rgba)
        shifted = bytes(value >> (depth - 8) for value in native)
        mismatches = [(index, value, shifted[index], alpha8[index]) for index, value in enumerate(native) if shifted[index] != alpha8[index]]
        alpha_records.append({
            "bit_depth": depth, "file": pair_path.name, "sha256": sha256(container), **assembly,
            "color_source_avif": str(color_path), "color_source_sha256": sha256(color_path.read_bytes()),
            "alpha_source_avif": alpha_path.name, "alpha_source_sha256": sha256(alpha_path.read_bytes()), "alpha_case": alpha_case["name"],
            "rgba_reference_file": rgba_path.name, "rgba_reference_sha256": sha256(rgba),
            "alpha8_reference_file": alpha8_path.name, "alpha8_reference_sha256": sha256(alpha8),
            "reference_decoder": "libavif 0.11.1 avifDecoderReadMemory + avifImageYUVToRGB, depth=8, avoidLibYUV=1",
            "pillow_rgba_file": pillow_path.name, "pillow_rgba_sha256": sha256(pillow_rgba),
            "default_pillow_matches_right_shift": pillow_alpha == shifted,
            "pillow_vs_scalar_alpha_mismatches": sum(a != b for a, b in zip(pillow_alpha, alpha8)),
            "alpha8_conversion": "(native*255 + ((1<<bit_depth)-1)//2)//((1<<bit_depth)-1)",
            "normalized_conversion_matches_scalar_libavif": True, "right_shift_mismatch_count": len(mismatches), "first_shift_mismatches": mismatches[:12],
        })
        print(f"verified {pair_path.name}: scalar libavif alpha exact, right-shift mismatches={len(mismatches)}, default Pillow differences={sum(a != b for a, b in zip(pillow_alpha, alpha8))}", flush=True)
    manifest = {
        "scope": "original monochrome libaom AV1 at 8/10/12 bits, full range, q30 nonzero CDEF single/multiple tiles, q0 full-range ramps; three standards-assembled alpha AVIF pairs",
        "generation_command": [sys.executable, *sys.argv], "source_manifest": str(args.source), "source_manifest_sha256": sha256(args.source.read_bytes()),
        "encoder_version": encoder_version.group(0), "ffmpeg_version": ffmpeg_version, "ffmpeg_decoder_version": ffmpeg_decoder_version,
        "dav1d_cli_version": cli_version, "pillow_version": Image.__version__, "pillow_libavif_version": features.version("avif"),
        "scalar_libavif_path": args.libavif_scalar, "scalar_libavif_version": scalar_version, "scalar_conversion_avoid_libyuv": True,
        "alpha_conversion_source": "https://raw.githubusercontent.com/AOMediaCodec/libavif/v1.4.2/src/alpha.c (avifReformatAlpha)",
        "auxiliary_binding_source": "https://aomediacodec.github.io/av1-avif/v1.1.0.html#auxiliary-image-items-and-sequences",
        "reference_notes": "native gray/gray10le/gray12le is verified by ffprobe and byte-identical dav1d CLI output; alpha8 UNORM oracle is actual scalar libavif with avoidLibYUV=1; default Pillow/libyuv conversion differences are retained separately",
        "fixtures": records, "alpha_containers": alpha_records, "limited_range_scalar_vectors": limited_vectors,
    }
    if args.test is not None:
        formatted = run([args.moonfmt, "-"], input_text=generate_test(records, alpha_records, args.out)).stdout
        args.test.parent.mkdir(parents=True, exist_ok=True)
        args.test.write_text(formatted, encoding="utf-8", newline="\n")
        manifest["generated_test"] = str(args.test)
        manifest["generated_test_sha256"] = sha256(args.test.read_bytes())
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(records)} monochrome fixtures and {len(alpha_records)} alpha containers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
