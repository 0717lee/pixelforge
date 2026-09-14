#!/usr/bin/env python3
"""Generate bounded AV1 deblocking references with two dav1d decoders.

The same coded stream is decoded with all filters and with only deblocking
disabled. This isolates observed deblock effects without re-encoding a control
image. AVIF remuxes preserve coded payloads and must decode identically.
Stock zero-level outputs may receive a clearly recorded reconstructed filter
header; their original stream and identical tile entropy are retained.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import re
import shutil
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


mono = module("loop_mono_helpers", "generate-av1-monochrome-reference.py")
cdef = mono.helpers
large = module("loop_frame_helpers", "generate-av1-large-block-reference.py")
run, sha256, read_hashed, rle = mono.run, mono.sha256, mono.read_hashed, mono.rle

LAYOUTS = [
    {"depth": depth, "monochrome": monochrome, "cdef": filtered, "width": 64,
     "height": 64, "columns": 1, "rows": 1, "partition": 16, "sharpness": 0}
    for depth, monochrome, filtered in itertools.product((8, 10, 12), (False, True), (False, True))
] + [
    {"depth": 10, "monochrome": False, "cdef": False, "width": 128, "height": 64,
     "columns": 2, "rows": 1, "partition": 16, "sharpness": 0},
    {"depth": 12, "monochrome": True, "cdef": True, "width": 64, "height": 128,
     "columns": 1, "rows": 2, "partition": 16, "sharpness": 0},
    {"depth": 12, "monochrome": False, "cdef": True, "width": 95, "height": 63,
     "columns": 2, "rows": 1, "partition": 8, "sharpness": 0},
    {"depth": 10, "monochrome": True, "cdef": False, "width": 64, "height": 64,
     "columns": 1, "rows": 1, "partition": 4, "sharpness": 3},
]


def trace_values(trace: str, name: str) -> dict[int, int]:
    values = {}
    for index, value in re.findall(rf"\b{re.escape(name)}\[(\d+)\]\s+[^=\n]+=\s*(-?\d+)", trace):
        index, value = int(index), int(value)
        if index in values and values[index] != value:
            raise RuntimeError(f"inconsistent {name}[{index}]")
        values[index] = value
    return values


def field(trace: str, name: str, default=None):
    values = re.findall(rf"\b{re.escape(name)}\s+[^=\n]+=\s*(-?\d+)", trace)
    if not values:
        if default is not None:
            return default
        raise RuntimeError(f"missing header field {name}")
    if len(set(values)) != 1:
        raise RuntimeError(f"inconsistent header field {name}")
    return int(values[0])


def native_planes(data: bytes, width: int, height: int, depth: int, monochrome: bool) -> list[list[int]]:
    return [mono.unpack(data, width * height, depth)] if monochrome else cdef.unpack_planes(data, width, height, depth)


def nonzero_header(data: bytes, trace: str, monochrome: bool) -> tuple[bytes, dict]:
    """Replace only zero LF levels, retaining every original tile entropy byte."""
    original_tile, header_bytes = large.frame_tile(data, trace)
    entries = re.findall(r"\]\s+(\d+)\s+(\S+)\s+([01]*)\s*=\s*(-?\d+)",
                         trace.split("Frame Header")[-1].split("Tile Group")[0])
    starts = {name: int(offset) for offset, name, _, _ in entries}
    syntax_end = max(int(offset) + len(bits) for offset, name, bits, _ in entries if name != "zero_bit")
    levels = [24, 36] if monochrome else [24, 36, 20, 28]
    position, output, count = 0, bytearray(), 0
    while position < len(data):
        start = position
        obu_header = data[position]
        position += 1
        if obu_header & 4 or not obu_header & 2:
            raise RuntimeError("unsupported stock OBU extension/size layout")
        length, shift = 0, 0
        while True:
            value = data[position]
            position += 1
            length |= (value & 127) << shift
            if value < 128:
                break
            shift += 7
            if shift > 49:
                raise RuntimeError("unbounded OBU length")
        payload_start = position
        position += length
        if (obu_header >> 3) & 15 != 6:
            output.extend(data[start:position])
            continue
        count += 1
        obu_bytes = payload_start - start
        bits = "".join(f"{value:08b}" for value in data[payload_start:payload_start + header_bytes])
        lf_start = starts["loop_filter_level[0]"] - obu_bytes * 8
        lf_end = starts["loop_filter_sharpness"] - obu_bytes * 8
        semantic_end = syntax_end - obu_bytes * 8
        if lf_end - lf_start != 12 or any(bit != "0" for bit in bits[lf_start:lf_end]):
            raise RuntimeError("header construction only accepts original zero filter levels")
        changed = bits[:lf_start] + "".join(f"{level:06b}" for level in levels) + bits[lf_end:semantic_end]
        changed += "0" * (-len(changed) % 8)
        header = bytes(int(changed[i:i + 8], 2) for i in range(0, len(changed), 8))
        payload = header + data[payload_start + header_bytes:position]
        output.extend(large.arithmetic.obu(6, payload))
    if count != 1:
        raise RuntimeError("expected one stock FRAME OBU")
    return bytes(output), {"kind": "standards-conformant reconstructed loop-filter header on unchanged original stock tile entropy",
                           "original_levels": [0, 0], "new_levels": levels,
                           "tile_entropy_sha256": sha256(original_tile),
                           "fields_changed": "loop_filter_level values, required color U/V level fields, byte alignment and enclosing OBU length only"}


def updated_filter_header(data: bytes, trace: str, modes: list[int]) -> tuple[bytes, dict]:
    """Signal signed reference/mode updates and sharpness on unchanged entropy."""
    levels = [trace_values(trace, "loop_filter_level")[index] for index in range(4)]
    references = [-1, 2, -3, 4, -5, 6, -7, 8]
    if len(modes) != 2 or any(value < -64 or value > 63 for value in modes):
        raise RuntimeError("invalid signed 7-bit mode delta")
    if field(trace, "loop_filter_delta_enabled") != 1 or field(trace, "loop_filter_delta_update") != 0:
        raise RuntimeError("parameter construction requires an original no-update filter header")
    tile, header_bytes = large.frame_tile(data, trace)
    entries = re.findall(r"\]\s+(\d+)\s+(\S+)\s+([01]*)\s*=\s*(-?\d+)",
                         trace.split("Frame Header")[-1].split("Tile Group")[0])
    starts = {name: int(offset) for offset, name, _, _ in entries}
    syntax_end = max(int(offset) + len(bits) for offset, name, bits, _ in entries if name != "zero_bit")
    syntax = "".join(f"{value:06b}" for value in levels) + "01111"
    syntax += "".join("1" + f"{value & 127:07b}" for value in references + modes)
    position, output, frames, frame_start = 0, bytearray(), 0, -1
    while position < len(data):
        start = position
        header = data[position]
        position += 1
        if header & 4 or not header & 2:
            raise RuntimeError("unsupported source OBU extension/size layout")
        length, shift = 0, 0
        while True:
            value = data[position]
            position += 1
            length |= (value & 127) << shift
            if value < 128:
                break
            shift += 7
            if shift > 49:
                raise RuntimeError("unbounded OBU length")
        payload_start = position
        position += length
        if (header >> 3) & 15 != 6:
            output.extend(data[start:position])
            continue
        frames += 1
        frame_start = start
        obu_bits = (payload_start - start) * 8
        bits = "".join(f"{value:08b}" for value in data[payload_start:payload_start + header_bytes])
        begin = starts["loop_filter_level[0]"] - obu_bits
        end = starts["loop_filter_delta_update"] + 1 - obu_bits
        changed = bits[:begin] + syntax + bits[end:syntax_end - obu_bits]
        changed += "0" * (-len(changed) % 8)
        payload = bytes(int(changed[i:i + 8], 2) for i in range(0, len(changed), 8))
        payload += data[payload_start + header_bytes:position]
        output.extend(large.arithmetic.obu(6, payload))
    if frames != 1:
        raise RuntimeError("expected one source FRAME OBU")
    return bytes(output), {"levels": levels, "sharpness": 3, "delta_enabled": 1,
                           "delta_update": 1, "ref_deltas": references, "mode_deltas": modes,
                           "tile_entropy_sha256": sha256(tile), "frame_obu_start": frame_start}


def first_geometry(data: bytes, trace: str, fields: dict, columns: int, rows: int) -> dict:
    tile, header_bytes = large.frame_tile(data, trace)
    group_bytes = 0
    if columns * rows > 1:
        # Stock FRAME OBUs use one tile group spanning every tile. Its one-bit
        # range-present flag and alignment precede little-endian tile lengths.
        if tile[0] != 0:
            raise RuntimeError("unsupported stock tile group range/alignment")
        size_bytes = fields["tile_size_bytes_minus1"] + 1
        size = int.from_bytes(tile[1:1 + size_bytes], "little") + 1
        group_bytes = 1 + size_bytes
        tile = tile[group_bytes:group_bytes + size]
        if len(tile) != size:
            raise RuntimeError("truncated first tile")
    tables = large.arithmetic.Tables()
    reader = large.arithmetic.MsacDecoder(tile, allow_update=not fields["disable_cdf_update"])
    rows_by_size = {64: tables.partition_w64[0], 32: tables.partition_w32[0],
                    16: [15597, 20929, 24571, 26706, 27664, 28821, 29601, 30571, 31902, 32768, 0],
                    8: [19132, 25510, 30392, 32768, 0]}
    size, path = 64, []
    while size > 4:
        symbol = reader.symbol(rows_by_size[size].copy())
        path.append({"square_side": size, "symbol": symbol})
        if symbol == 0:
            break
        if symbol != 3:
            raise RuntimeError(f"unexpected first rectangular partition {path}")
        size //= 2
    skip = reader.symbol(tables.skip[0])
    return {"frame_header_bytes": header_bytes, "tile_group_prefix_bytes": group_bytes,
            "first_tile_bytes": len(tile), "partition_prefix": path,
            "first_coding_dimensions": [size, size], "first_skip": skip,
            "first_luma_transform": [size, size] if fields["tx_mode"] == 1 else None,
            "transform_evidence": "decoded first coding partition plus actual tx_mode=LARGEST; later block geometry is not inferred from encoder flags"}


def generate_test(manifest: dict, base: Path) -> str:
    text = """/// Stock and explicitly reconstructed-filter-header libaom deblock streams.
/// Native reference pixels are independently
/// decoded by two unmodified dav1d builds and verified after AVIF remux.
fn av1_loop_filter_reference_compare(
  stream : Array[Byte], avif : Array[Byte], width : Int, height : Int,
  depth : Int, references : Array[Array[Int]], gray8 : Array[Int],
) -> Unit raise {
  let frame = av1_decode_frame_planes(stream, allow_monochrome=true).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, depth))
  assert_eq(frame.planes.length(), references.length())
  for plane in 0..<references.length() {
    let actual = av1_frame_crop(frame, plane)
    let expected = references[plane]
    assert_eq(actual.length(), expected.length())
    for index in 0..<expected.length() {
      assert_eq((plane, index, actual[index]), (plane, index, expected[index]))
    }
  }
  let expected = if references.length() == 1 {
    let image = Image::new(width, height)
    for i in 0..<gray8.length() {
      let value = gray8[i].to_byte()
      image.set_pixel(i % width, i / width, value, value, value, b'\\xFF')
    }
    image
  } else {
    av1_yuv420_highbd_to_rgba(width, height, references[0], references[1], references[2], depth,
      full_range=frame.full_range, matrix_coefficients=frame.matrix_coefficients).unwrap()
  }
  for image in [av1_decode(stream).unwrap(), avif_decode_rgba(avif).unwrap()] {
    assert_eq((image.width, image.height), (width, height))
    for y in 0..<height {
      for x in 0..<width {
        assert_eq((x, y, image.get_pixel(x, y)), (x, y, expected.get_pixel(x, y)))
      }
    }
  }
}
"""
    for record in manifest["fixtures"]:
        width, height = record["dimensions"]
        depth = record["bit_depth"]
        text += f'\n///|\ntest "external deblocking {record["name"]}" {{\n'
        for label in ("stream", "avif"):
            key = "obu" if label == "stream" else label
            data = read_hashed(base / record[key + "_file"], record[key + "_sha256"])
            lines = ["    " + ", ".join(f"b'\\x{byte:02X}'" for byte in data[i:i + 12]) + "," for i in range(0, len(data), 12)]
            text += f"  let {label} : Array[Byte] = [\n" + "\n".join(lines) + "\n  ]\n"
        data = read_hashed(base / record["reference_file"], record["reference_sha256"])
        planes = native_planes(data, width, height, depth, record["monochrome"])
        names = []
        for plane, values in enumerate(planes):
            text += f"  let plane{plane} = av1_reference_planes_expand(" + json.dumps(rle(values)) + ")\n"
            names.append(f"plane{plane}")
        gray8 = read_hashed(base / record["gray8_file"], record["gray8_sha256"]) if record["monochrome"] else b""
        text += "  let gray8 = av1_reference_planes_expand(" + json.dumps(rle(list(gray8))) + ")\n"
        text += f"  av1_loop_filter_reference_compare(stream, avif, {width}, {height}, {depth}, [" + ", ".join(names) + "], gray8)\n}\n"
    return text


def params_main(args) -> int:
    path = args.out / "params-manifest.json"
    if args.check_params:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        for key in ("source", "source_native", "source_nodeblock"):
            read_hashed(args.out / manifest[key + "_file"], manifest[key + "_sha256"])
        for record in manifest["fixtures"]:
            for key, value in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    read_hashed(args.out / value, record[key[:-5] + "_sha256"])
        source = generate_test(manifest, args.out).replace("av1_loop_filter_reference_compare", "av1_loop_filter_params_reference_compare")
        mono.verify_generated_test(manifest, source, args.moonfmt)
        return 0
    base = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    original = next(case for case in base["fixtures"] if case["name"] == "color_64x64_10bit_1x1tile_tx16_deblock")
    original_data = read_hashed(args.out / original["obu_file"], original["obu_sha256"])
    original_trace = read_hashed(args.out / original["trace_file"], original["trace_sha256"]).decode("utf-8")
    original_pixels = read_hashed(args.out / original["reference_file"], original["reference_sha256"])
    original_nodeblock = read_hashed(args.out / original["nodeblock_file"], original["nodeblock_sha256"])
    cli_version_result = run([args.dav1d, "--version"])
    cli_version = (cli_version_result.stdout + cli_version_result.stderr).strip()
    decoder_versions = set()
    records, filtered_pair, nodeblock_pair, stream_pair = [], [], [], []
    mode_field_positions = []
    for suffix, modes in (("negative_positive", [-64, 63]), ("positive_negative", [63, -64])):
        name = "params_10bit_sharpness3_modes_" + suffix
        files = {key: args.out / f"{name}.{ext}" for key, ext in (("obu", "obu"), ("trace", "trace.txt"),
                  ("reference", "reference.yuv"), ("nodeblock", "nodeblock.yuv"), ("avif", "avif"))}
        data, construction = updated_filter_header(original_data, original_trace, modes)
        files["obu"].write_bytes(data)
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(files["obu"]), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        files["trace"].write_text(trace, encoding="utf-8")
        actual = {"levels": [trace_values(trace, "loop_filter_level")[index] for index in range(4)],
                  "sharpness": field(trace, "loop_filter_sharpness"), "delta_enabled": field(trace, "loop_filter_delta_enabled"),
                  "delta_update": field(trace, "loop_filter_delta_update"),
                  "ref_deltas": [trace_values(trace, "loop_filter_ref_deltas")[index] for index in range(8)],
                  "mode_deltas": [trace_values(trace, "loop_filter_mode_deltas")[index] for index in range(2)]}
        if any(actual[key] != construction[key] for key in actual):
            raise RuntimeError(f"actual signed parameter syntax differs: {actual}")
        positions = [(int(offset) + construction["frame_obu_start"] * 8, len(bits))
                     for offset, bits in re.findall(r"\]\s+(\d+)\s+loop_filter_mode_deltas\[\d+\]\s+([01]+)\s*=", trace)]
        if len(positions) != 2 or any(length != 7 for _, length in positions):
            raise RuntimeError("actual mode-delta signed bit positions unavailable")
        mode_field_positions.append(positions)
        tile, _ = large.frame_tile(data, trace)
        if sha256(tile) != construction["tile_entropy_sha256"]:
            raise RuntimeError("parameter construction changed tile entropy")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(files["obu"]),
                  "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p10le", str(files["reference"])]
        decoded = run(decode)
        decoder_versions.update(re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr))
        temporary = args.out / f"{name}.cli.tmp.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(files["obu"]), "--demuxer", "section5", "--muxer", "yuv",
               "--output", str(temporary), "--limit", "1", "--inloopfilters", "all"]
        cdef.run_binary(cli)
        pixels = files["reference"].read_bytes()
        if temporary.read_bytes() != pixels:
            raise RuntimeError("dual dav1d parameter pixels differ")
        temporary.unlink()
        without = cli.copy()
        without[without.index("--output") + 1] = str(files["nodeblock"])
        without[-1] = "nodeblock"
        cdef.run_binary(without)
        raw = files["nodeblock"].read_bytes()
        if raw != original_nodeblock:
            raise RuntimeError("parameter variant changed no-deblock pixels")
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(files["obu"]), "-c", "copy", "-frames:v", "1", "-f", "avif", str(files["avif"])]
        run(wrap)
        remux_decode = decode.copy()
        remux_decode[remux_decode.index("-i") + 1] = str(files["avif"])
        remux_decode[-1] = str(temporary)
        run(remux_decode)
        if temporary.read_bytes() != pixels:
            raise RuntimeError("parameter AVIF remux changed pixels")
        temporary.unlink()
        planes = native_planes(pixels, 64, 64, 10, False)
        differences = cdef.differences(planes, native_planes(original_pixels, 64, 64, 10, False), 64, 1, 1)
        if not any(plane["changed_samples"] for plane in differences.values()):
            raise RuntimeError("new sharpness/reference deltas had no observable filtered effect")
        record = {"name": name, "dimensions": [64, 64], "bit_depth": 10, "monochrome": False,
                  "provenance": "complete standards-conformant filter-header reconstruction on unchanged original supported tile entropy; not untouched full encoder output",
                  "actual_filter_header": actual, "tile_entropy_sha256": sha256(tile),
                  "same_tile_entropy_as_original": True, "nodeblock_matches_original": True,
                  "dual_dav1d_exact": True, "avif_remux_native_exact": True,
                  "changes_vs_original_filter_header": differences,
                  "commands": {"trace": trace_command, "decode": decode, "dav1d_all": cli,
                               "dav1d_nodeblock": without, "remux": wrap, "decode_avif": remux_decode}}
        for key, filename in files.items():
            record[key + "_file"] = filename.name
            record[key + "_sha256"] = sha256(filename.read_bytes())
        records.append(record)
        filtered_pair.append(pixels)
        nodeblock_pair.append(raw)
        stream_pair.append(data)
        print(f"verified {name}: actual={actual}, differences=" + str({key: value["changed_samples"] for key, value in differences.items()}), flush=True)
    if filtered_pair[0] != filtered_pair[1] or nodeblock_pair[0] != nodeblock_pair[1]:
        raise RuntimeError("intra pixels depended on mode delta values")
    if len(stream_pair[0]) != len(stream_pair[1]) or mode_field_positions[0] != mode_field_positions[1]:
        raise RuntimeError("mode-delta pair changed container or field layout")
    changed_bits = {byte * 8 + bit for byte, (left, right) in enumerate(zip(*stream_pair))
                    for bit in range(8) if (left ^ right) & (1 << (7 - bit))}
    expected_bits = {position + bit for position, length in mode_field_positions[0] for bit in range(length)}
    if changed_bits != expected_bits:
        raise RuntimeError("mode-delta pair changed bits outside its two signed fields")
    if len(decoder_versions) != 1:
        raise RuntimeError(f"missing/inconsistent FFmpeg dav1d version: {decoder_versions}")
    manifest = {"scope": "exactly two same-entropy 10-bit intra header variants with sharpness3 and signed delta updates",
                "dav1d_cli_version": cli_version, "ffmpeg_dav1d_version": next(iter(decoder_versions)),
                "source_file": original["obu_file"], "source_sha256": original["obu_sha256"],
                "source_native_file": original["reference_file"], "source_native_sha256": original["reference_sha256"],
                "source_nodeblock_file": original["nodeblock_file"], "source_nodeblock_sha256": original["nodeblock_sha256"],
                "same_tile_entropy": True, "same_nodeblock_pixels": True, "same_filtered_pixels_despite_mode_deltas": True,
                "changed_bit_count": len(changed_bits), "changed_bit_positions": sorted(changed_bits),
                "pair_difference": "only loop_filter_mode_deltas signed values; all other header bits, alignment, OBU sizes and tile payloads are identical",
                "interpretation": "intra reference delta -1 and sharpness3 observably change filtered output; swapping mode deltas -64/63 must not change intra output",
                "fixtures": records, "generated_test": str(args.params_test)}
    source = generate_test(manifest, args.out).replace("av1_loop_filter_reference_compare", "av1_loop_filter_params_reference_compare")
    generated = run([args.moonfmt, "-"], input_text=source).stdout.encode("utf-8")
    args.params_test.parent.mkdir(parents=True, exist_ok=True)
    args.params_test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-loop-filter"))
    parser.add_argument("--test", type=Path, default=Path("_refs/av1_loop_filter_reference_wbtest.mbt"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--ffprobe", default=shutil.which("ffprobe") or "ffprobe")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--params", action="store_true", help="generate two separate sharpness/signed-delta header variants, preserving the base16 corpus")
    parser.add_argument("--check-params", action="store_true")
    parser.add_argument("--params-test", type=Path, default=Path("_refs/av1_loop_filter_params_reference_wbtest.mbt"))
    args = parser.parse_args()
    if args.params or args.check_params:
        return params_main(args)
    manifest_path = args.out / "manifest.json"
    if args.check:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for record in manifest["fixtures"]:
            for key, value in record.items():
                if key.endswith("_file") and key[:-5] + "_sha256" in record:
                    read_hashed(args.out / value, record[key[:-5] + "_sha256"])
        mono.verify_generated_test(manifest, generate_test(manifest, args.out), args.moonfmt)
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    templates = json.loads(Path("tests/fixtures/av1-cdef-frame/manifest.json").read_text(encoding="utf-8"))["fixtures"]
    scalar, scalar_version = mono.scalar_library(args.libavif_scalar)
    encoder_help = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", encoder_help.stdout + encoder_help.stderr).group(0)
    cli_version = run([args.dav1d, "--version"])
    cli_version = (cli_version.stdout + cli_version.stderr).strip()
    records = []
    decoder_versions = set()
    for layout in LAYOUTS:
        depth, monochrome = layout["depth"], layout["monochrome"]
        width, height, rows, columns = layout["width"], layout["height"], layout["rows"], layout["columns"]
        name = f"{'mono' if monochrome else 'color'}_{width}x{height}_{depth}bit_{columns}x{rows}tile_tx{layout['partition']}_{'cdef' if layout['cdef'] else 'deblock'}"
        paths = {key: args.out / f"{name}.{suffix}" for key, suffix in (
            ("source", "source.yuv"), ("input", "input.y4m" if monochrome else "input.yuv"),
            ("obu", "obu"), ("avif", "avif"), ("reference", "reference.yuv"),
            ("nodeblock", "nodeblock.yuv"), ("trace", "trace.txt"))}
        planes = cdef.input_planes(width, height, depth, 1)
        source = b"".join(mono.pack(plane, depth) for plane in (planes[:1] if monochrome else planes))
        paths["source"].write_bytes(source)
        if monochrome:
            # High-depth mono Y4M is carried in C420p10/12; --monochrome ignores
            # its neutral chroma. Luma values and full-range metadata are exact.
            carrier = source if depth == 8 else source + mono.pack([1 << (depth - 1)] * (2 * ((width + 1) // 2) * ((height + 1) // 2)), depth)
            chroma = "mono" if depth == 8 else f"420p{depth}"
            encoded_input = f"YUV4MPEG2 W{width} H{height} F1:1 Ip A1:1 C{chroma} XCOLORRANGE=FULL\nFRAME\n".encode() + carrier
        else:
            encoded_input = source
        paths["input"].write_bytes(encoded_input)
        template = next(case for case in templates if case["name"] == f"cdef_64x64_1tile_{depth}bit")
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        if monochrome:
            encode.insert(1, "--monochrome")
        replacements = {"--width": width, "--height": height, "--tile-columns": columns.bit_length() - 1,
                        "--tile-rows": rows.bit_length() - 1, "--enable-cdef": int(layout["cdef"]),
                        "--loopfilter-control": 1, "--min-partition-size": layout["partition"],
                        "--max-partition-size": layout["partition"], "--delta-lf-mode": 0,
                        "--sharpness": layout["sharpness"]}
        for flag, value in replacements.items():
            index = next((i for i, argument in enumerate(encode) if argument.startswith(flag + "=")), None)
            if index is None:
                encode.insert(1, f"{flag}={value}")
            else:
                encode[index] = f"{flag}={value}"
        encode[encode.index("-o") + 1] = str(paths["obu"])
        encode[encode.index("-o") + 2] = str(paths["input"])
        run(encode)
        trace_command = [args.ffmpeg, "-hide_banner", "-i", str(paths["obu"]), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
        trace = run(trace_command).stderr
        construction = None
        if not any(trace_values(trace, "loop_filter_level").values()):
            original_data = paths["obu"].read_bytes()
            paths["stock_obu"] = args.out / f"{name}.stock.obu"
            paths["stock_trace"] = args.out / f"{name}.stock.trace.txt"
            paths["stock_obu"].write_bytes(original_data)
            paths["stock_trace"].write_text(trace, encoding="utf-8")
            changed, construction = nonzero_header(original_data, trace, monochrome)
            paths["obu"].write_bytes(changed)
            trace = run(trace_command).stderr
            changed_tile, _ = large.frame_tile(changed, trace)
            if sha256(changed_tile) != construction["tile_entropy_sha256"]:
                raise RuntimeError("filter header construction changed original tile entropy")
        paths["trace"].write_text(trace, encoding="utf-8")
        fields = {key: field(trace, key) for key in (
            "reduced_still_picture_header", "use_128x128_superblock", "enable_superres", "enable_restoration",
            "enable_cdef", "enable_filter_intra", "enable_intra_edge_filter", "base_q_idx", "using_qmatrix",
            "segmentation_enabled", "delta_q_present", "disable_cdf_update", "tx_mode", "mono_chrome",
            "color_range", "tile_cols_log2", "tile_rows_log2", "loop_filter_sharpness", "loop_filter_delta_enabled")}
        fields["loop_filter_delta_update"] = field(trace, "loop_filter_delta_update", 0)
        fields["tile_size_bytes_minus1"] = field(trace, "tile_size_bytes_minus1", 0)
        quantizer_deltas = {name: int(value) for name, value in re.findall(r"\b(delta_q_[a-z_]+\.delta_coded)\s+[^=\n]+=\s*(\d+)", trace)}
        if not quantizer_deltas or any(quantizer_deltas.values()):
            raise RuntimeError(f"unexpected quantizer delta syntax for {name}: {quantizer_deltas}")
        for key in ("use_128x128_superblock", "enable_superres", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter", "using_qmatrix", "segmentation_enabled", "delta_q_present"):
            if fields[key]:
                raise RuntimeError(f"unexpected unsupported field {key} for {name}")
        if fields["reduced_still_picture_header"] != 1 or fields["tx_mode"] != 1 or fields["mono_chrome"] != int(monochrome):
            raise RuntimeError(f"unexpected coding configuration for {name}")
        levels = trace_values(trace, "loop_filter_level")
        if any(i not in levels for i in range(2)) or not any(levels.values()):
            raise RuntimeError(f"stock candidate has no nonzero deblocking levels: {name}: {levels}")
        ref_deltas = [1, 0, 0, 0, -1, 0, -1, -1]
        mode_deltas = [0, 0]
        for index, value in trace_values(trace, "loop_filter_ref_deltas").items():
            ref_deltas[index] = value
        for index, value in trace_values(trace, "loop_filter_mode_deltas").items():
            mode_deltas[index] = value
        geometry = first_geometry(paths["obu"].read_bytes(), trace, fields, columns, rows)
        if geometry["first_coding_dimensions"] != [layout["partition"]] * 2:
            raise RuntimeError(f"stock partition control did not match actual first leaf: {name}: {geometry}")
        pixel_format = ("gray" if depth == 8 else f"gray{depth}le") if monochrome else ("yuv420p" if depth == 8 else f"yuv420p{depth}le")
        probe_command = [args.ffprobe, "-v", "error", "-show_entries", "stream=width,height,pix_fmt", "-of", "json", str(paths["obu"])]
        stream_info = json.loads(run(probe_command).stdout)["streams"]
        if stream_info != [{"width": width, "height": height, "pix_fmt": pixel_format}]:
            raise RuntimeError(f"native pixel format differs: {stream_info}")
        decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(paths["obu"]), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(paths["reference"])]
        decoded = run(decode)
        decoder_versions.update(re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr))
        filtered = paths["reference"].read_bytes()
        actual = native_planes(filtered, width, height, depth, monochrome)
        cli_temp = args.out / f"{name}.cli.tmp.yuv"
        cli = [args.dav1d, "--quiet", "--input", str(paths["obu"]), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_temp), "--limit", "1", "--inloopfilters", "all"]
        cdef.run_binary(cli)
        if cli_temp.read_bytes() != filtered:
            raise RuntimeError(f"two dav1d decoders differ for {name}")
        cli_temp.unlink()
        nodeblock = cli.copy()
        nodeblock[nodeblock.index("--output") + 1] = str(paths["nodeblock"])
        nodeblock[-1] = "nodeblock"
        cdef.run_binary(nodeblock)
        if construction is not None:
            original_decode = cli.copy()
            original_decode[original_decode.index("--input") + 1] = str(paths["stock_obu"])
            cdef.run_binary(original_decode)
            if cli_temp.read_bytes() != paths["nodeblock"].read_bytes():
                raise RuntimeError("constructed stream without deblocking differs from original zero-level stream")
            cli_temp.unlink()
            construction["original_decode_exact_nodeblock"] = True
        without = native_planes(paths["nodeblock"].read_bytes(), width, height, depth, monochrome)
        changes = cdef.differences(actual, without, width, columns, rows)
        if not any(plane["changed_samples"] for plane in changes.values()):
            raise RuntimeError(f"deblocking changed no samples in {name}")
        wrap = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(paths["obu"]), "-c", "copy", "-frames:v", "1", "-f", "avif", str(paths["avif"])]
        run(wrap)
        avif_temp = args.out / f"{name}.avif.tmp.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1] = str(paths["avif"])
        decode_avif[-1] = str(avif_temp)
        run(decode_avif)
        if avif_temp.read_bytes() != filtered:
            raise RuntimeError(f"AVIF remux native pixels differ for {name}")
        avif_temp.unlink()
        record = {"name": name, "dimensions": [width, height], "bit_depth": depth, "monochrome": monochrome,
                  "provenance": "untouched original stock libaom full stream" if construction is None else construction["kind"],
                  "header_construction": construction, "tile_grid": [columns, rows],
                  "header": fields, "loop_filter_levels": [levels.get(i, 0) for i in range(2 if monochrome else 4)],
                  "quantizer_delta_fields": quantizer_deltas,
                  "encoder_coefficient_sharpness_option": layout["sharpness"],
                  "loop_filter_ref_deltas": ref_deltas, "loop_filter_mode_deltas": mode_deltas,
                  "delta_lf_present": False, "delta_lf_evidence": "delta_q_present=0 makes delta-LF syntax absent",
                  "actual_first_leaf": geometry, "same_stream_nodeblock_changes": changes,
                  "dual_dav1d_exact": True, "avif_remux_native_exact": True,
                  "input_pattern": {**cdef.INPUT_PATTERN, "amplitude": 1},
                  "commands": {"encode": encode, "trace": trace_command, "probe": probe_command,
                               "decode": decode, "dav1d_all": cli, "dav1d_nodeblock": nodeblock,
                               "remux": wrap, "decode_avif": decode_avif}}
        if layout["cdef"]:
            bits = field(trace, "cdef_bits")
            record["cdef"] = {"bits": bits, "damping_minus3": field(trace, "cdef_damping_minus_3"),
                              **{key: list(trace_values(trace, key).values()) for key in
                                 ("cdef_y_pri_strength", "cdef_y_sec_strength") + (() if monochrome else ("cdef_uv_pri_strength", "cdef_uv_sec_strength"))}}
        if monochrome:
            rgba = mono.scalar_rgba(paths["avif"].read_bytes(), scalar)
            gray = rgba[::4]
            maximum = (1 << depth) - 1
            expected_gray = bytes((sample * 255 + maximum // 2) // maximum for sample in actual[0])
            if gray != expected_gray or rgba[1::4] != gray or rgba[2::4] != gray:
                raise RuntimeError("actual scalar libavif mono normalization differs")
            paths["gray8"] = args.out / f"{name}.gray8.raw"
            paths["gray8"].write_bytes(gray)
        for key, path in paths.items():
            record[key + "_file"] = path.name
            record[key + "_sha256"] = sha256(path.read_bytes())
        records.append(record)
        print(f"verified {name}: levels={record['loop_filter_levels']}, changed=" + str({plane: evidence['changed_samples'] for plane, evidence in changes.items()}), flush=True)
    if len(decoder_versions) != 1:
        raise RuntimeError(f"missing/inconsistent FFmpeg dav1d build: {decoder_versions}")
    manifest = {"scope": "16 deblock fixtures from stock original entropy: color/mono at 8/10/12, deblock-only and combined CDEF, multi-tile seams, odd crop and first TX4/8 geometry; zero-level cases have explicitly reconstructed filter headers",
                "encoder_version": encoder_version, "dav1d_cli_version": cli_version,
                "ffmpeg_dav1d_version": next(iter(decoder_versions)), "scalar_libavif_version": scalar_version,
                "candidate_limit": len(LAYOUTS), "candidate_count": len(records), "fixtures": records,
                "untouched_full_stream_count": sum(record["header_construction"] is None for record in records),
                "reconstructed_filter_header_count": sum(record["header_construction"] is not None for record in records),
                "sharpness_evidence": "all actual loop_filter_sharpness fields are recorded; encoder --sharpness biases coefficients and does not prove nonzero loop-filter sharpness",
                "same_stream_filter_oracle": "dav1d --inloopfilters nodeblock disables only deblocking on the identical input OBU; CDEF remains enabled if signaled",
                "color_rgba_contract": "PixelForge nearest420 conversion from independently verified native planes; no vendor color-RGBA parity claim",
                "generated_test": str(args.test)}
    generated = run([args.moonfmt, "-"], input_text=generate_test(manifest, args.out)).stdout.encode("utf-8")
    args.test.parent.mkdir(parents=True, exist_ok=True)
    args.test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
