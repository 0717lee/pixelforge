#!/usr/bin/env python3
"""Generate real filtered AV1 frames, including CDEF across a tile boundary.

Reference output comes from FFmpeg/libdav1d. A second dav1d CLI must produce the
same filtered bytes; disabling only CDEF while decoding that identical OBU must
change samples, including samples near the two-tile seam. A separately encoded
CDEF-off stream is retained as ancillary evidence, not as the unfiltered source
of the CDEF-on stream.
"""

from __future__ import annotations

import argparse
import importlib.util
import itertools
import json
import math
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path


sys.dont_write_bytecode = True
helper_path = Path(__file__).with_name("generate-av1-partition-reference.py")
helper_spec = importlib.util.spec_from_file_location("av1_partition_reference_helpers", helper_path)
assert helper_spec is not None and helper_spec.loader is not None
helpers = importlib.util.module_from_spec(helper_spec)
helper_spec.loader.exec_module(helpers)
run = helpers.run
sha256 = helpers.sha256

CANDIDATES = ((30, 1), (40, 1), (50, 1), (40, 2), (50, 2))
LAYOUTS = tuple((depth, width, 64, 1 if width == 64 else 2, 1)
                for depth, width in itertools.product((8, 10, 12), (64, 128))) + (
    (10, 64, 128, 1, 2),
    (12, 95, 63, 2, 1),
)
INPUT_PATTERN = {
    "scale": "1 << (bit_depth - 8)",
    "coordinates": "global luma positions X=x,Y=y for Y; X=2*x,Y=2*y for U/V; never reset at a tile seam",
    "carrier": "12*cos(2*pi*X/17) + 8*sin(2*pi*Y/23) + 6*cos(2*pi*(X+Y)/29)",
    "noise": "((X*13 + Y*17 + X*Y*3 + 7) % 23) - 11",
    "noise_v": "((X*19 + Y*11 + X*Y*5 + 3) % 23) - 11",
    "y": "round(scale * (128 + carrier + amplitude*noise))",
    "u": "round(scale * (132 + 0.5*carrier + 0.75*amplitude*noise))",
    "v": "round(scale * (124 - 0.6*carrier + 0.75*amplitude*noise_v))",
    "rounding": "Python round, ties to even",
}


def input_planes(width: int, height: int, depth: int, amplitude: int) -> list[list[int]]:
    scale = 1 << (depth - 8)
    planes = []
    for plane in range(3):
        step = 1 if plane == 0 else 2
        pw, ph = (width + step - 1) // step, (height + step - 1) // step
        values = []
        for y in range(ph):
            for x in range(pw):
                xx, yy = step * x, step * y
                carrier = 12 * math.cos(2 * math.pi * xx / 17) + 8 * math.sin(2 * math.pi * yy / 23) + 6 * math.cos(2 * math.pi * (xx + yy) / 29)
                noise = ((xx * 13 + yy * 17 + xx * yy * 3 + 7) % 23) - 11
                noise_v = ((xx * 19 + yy * 11 + xx * yy * 5 + 3) % 23) - 11
                value = (128 + carrier + amplitude * noise, 132 + 0.5 * carrier + 0.75 * amplitude * noise, 124 - 0.6 * carrier + 0.75 * amplitude * noise_v)[plane]
                values.append(round(scale * value))
        planes.append(values)
    return planes


def unpack_planes(data: bytes, width: int, height: int, depth: int) -> list[list[int]]:
    luma = width * height
    chroma = ((width + 1) // 2) * ((height + 1) // 2)
    count = luma + 2 * chroma
    if len(data) != count * (1 if depth == 8 else 2):
        raise RuntimeError(f"unexpected {width}x{height}/{depth}-bit reference length: {len(data)}")
    values = list(data) if depth == 8 else list(struct.unpack(f"<{count}H", data))
    if any(value >= 1 << depth for value in values):
        raise RuntimeError("reference sample exceeds coded bit depth")
    return [values[:luma], values[luma:luma + chroma], values[luma + chroma:]]


def run_binary(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"command failed: {command!r}\n{result.stderr.decode(errors='replace')}")
    return result


def trace_array(trace: str, name: str, count: int) -> list[int]:
    values = {}
    for index, value in re.findall(rf"\b{re.escape(name)}\[(\d+)\]\s+[^=\n]+=\s*(\d+)", trace):
        index, value = int(index), int(value)
        if index in values and values[index] != value:
            raise RuntimeError(f"inconsistent {name}[{index}]")
        values[index] = value
    if set(values) != set(range(count)):
        raise RuntimeError(f"incomplete {name}: {values}; expected {count} values")
    return [values[index] for index in range(count)]


def differences(left: list[list[int]], right: list[list[int]], width: int, columns: int, rows: int) -> dict[str, object]:
    planes = {}
    for index, (a, b) in enumerate(zip(left, right)):
        pw = width if index == 0 else (width + 1) // 2
        seam = 64 if index == 0 else 32
        band = 2 if index == 0 else 1
        changed = [position for position, (x, y) in enumerate(zip(a, b)) if x != y]
        seam_left = sum(seam - band <= position % pw < seam for position in changed) if columns > 1 else 0
        seam_right = sum(seam <= position % pw < seam + band for position in changed) if columns > 1 else 0
        seam_above = sum(seam - band <= position // pw < seam for position in changed) if rows > 1 else 0
        seam_below = sum(seam <= position // pw < seam + band for position in changed) if rows > 1 else 0
        planes[("y", "u", "v")[index]] = {
            "changed_samples": len(changed), "maximum_absolute_delta": max((abs(x - y) for x, y in zip(a, b)), default=0),
            "changed_left_of_seam": seam_left, "changed_right_of_seam": seam_right,
            "changed_above_seam": seam_above, "changed_below_seam": seam_below,
        }
    return planes


def generate_test(cases: list[dict[str, object]]) -> str:
    source = """/// Generated by scripts/generate-av1-cdef-frame-reference.py.
/// Full filtered dav1d planes from original CDEF-on OBU streams.
fn av1_cdef_frame_reference_compare(
  stream : Array[Byte], avif : Array[Byte], width : Int, height : Int, bit_depth : Int,
  y_runs : Array[Int], u_runs : Array[Int], v_runs : Array[Int],
) -> Unit raise {
  let references = [
    av1_reference_planes_expand(y_runs),
    av1_reference_planes_expand(u_runs),
    av1_reference_planes_expand(v_runs),
  ]
  let frame = av1_decode_frame_planes(stream).unwrap()
  assert_eq((frame.width, frame.height, frame.bit_depth), (width, height, bit_depth))
  for plane in 0..<3 {
    let expected = references[plane]
    let actual = av1_frame_crop(frame, plane)
    assert_eq(actual.length(), expected.length())
    for index in 0..<expected.length() {
      assert_eq((plane, index, actual[index]), (plane, index, expected[index]))
    }
  }
  let expected = av1_yuv420_highbd_to_rgba(
    width, height, references[0], references[1], references[2], bit_depth,
    full_range=frame.full_range, matrix_coefficients=frame.matrix_coefficients,
  ).unwrap()
  let actual = av1_decode(stream).unwrap()
  let container_image = avif_decode_rgba(avif).unwrap()
  assert_eq((container_image.width, container_image.height), (width, height))
  for y in 0..<height {
    for x in 0..<width {
      assert_eq((x, y, actual.get_pixel(x, y)), (x, y, expected.get_pixel(x, y)))
      assert_eq((x, y, container_image.get_pixel(x, y)), (x, y, expected.get_pixel(x, y)))
    }
  }
}
"""
    for case in cases:
        stream = case["stream"]
        rows = ["    " + ", ".join(f"b'\\x{value:02X}'" for value in stream[i:i + 12]) + "," for i in range(0, len(stream), 12)]
        source += f'\n///|\ntest "external libaom dav1d CDEF frame {case["name"]}" {{\n'
        source += "  let stream : Array[Byte] = [\n" + "\n".join(rows) + "\n  ]\n"
        avif = case["avif"]
        avif_rows = ["    " + ", ".join(f"b'\\x{value:02X}'" for value in avif[i:i + 12]) + "," for i in range(0, len(avif), 12)]
        source += "  let avif : Array[Byte] = [\n" + "\n".join(avif_rows) + "\n  ]\n"
        for plane, samples in zip(("y", "u", "v"), case["planes"]):
            source += f"  let {plane}_runs : Array[Int] = " + helpers.helpers.array(helpers.helpers.rle(samples)) + "\n"
        source += f'  av1_cdef_frame_reference_compare(stream, avif, {case["width"]}, {case["height"]}, {case["bit_depth"]}, y_runs, u_runs, v_runs)\n}}\n'
    return source


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("tests/fixtures/av1-intra-modes/manifest.json"))
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-cdef-frame"))
    parser.add_argument("--test", type=Path, default=Path("av1_cdef_frame_reference_wbtest.mbt"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d", default=shutil.which("dav1d") or "dav1d")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source_manifest = json.loads(args.source.read_text(encoding="utf-8"))
    source_cases = {case["name"]: case for case in source_manifest["fixtures"]}
    help_result = run([args.aomenc, "--help"])
    encoder_version = re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", help_result.stdout + help_result.stderr)
    if encoder_version is None:
        raise RuntimeError("could not identify aomenc version")
    ffmpeg_version = run([args.ffmpeg, "-version"]).stdout.splitlines()
    cli_version_result = run([args.dav1d, "--version"])
    dav1d_cli_version = (cli_version_result.stdout + cli_version_result.stderr).strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+[^\r\n]*", dav1d_cli_version):
        raise RuntimeError(f"could not identify dav1d CLI version: {dav1d_cli_version!r}")
    ffmpeg_dav1d_version = None
    records = []
    tests = []
    for depth, width, height, columns, rows in LAYOUTS:
        tile_columns = columns.bit_length() - 1
        tile_rows = rows.bit_length() - 1
        name = f"cdef_{width}x{height}_{columns * rows}tile_{depth}bit"
        input_path = args.out / f"{name}.input.yuv"
        obu_path = args.out / f"{name}.obu"
        reference_path = args.out / f"{name}.reference.yuv"
        unfiltered_path = args.out / f"{name}.unfiltered.yuv"
        template = source_cases[f"split16_64x64_{depth}bit_q30_intra_modes"]
        pixel_format = template["pixel_format"]
        attempts = []
        for quantizer, amplitude in CANDIDATES:
            input_data = helpers.helpers.pack_planes(input_planes(width, height, depth, amplitude), depth)
            input_path.write_bytes(input_data)
            encode = template["commands"]["encode"].copy()
            encode[0] = args.aomenc
            replacements = {"--width": width, "--height": height, "--tile-columns": tile_columns, "--tile-rows": tile_rows, "--enable-cdef": 1, "--cq-level": quantizer}
            for flag, value in replacements.items():
                index = next(index for index, argument in enumerate(encode) if argument.startswith(flag + "="))
                encode[index] = f"{flag}={value}"
            output_index = encode.index("-o")
            encode[output_index + 1] = str(obu_path)
            encode[output_index + 2] = str(input_path)
            run(encode)
            trace_command = [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
            trace = run(trace_command).stderr
            fields = {field: helpers.helpers.trace_value(trace, field) for field in template["header_trace"]}
            expected = {**template["header_trace"], "enable_cdef": 1, "max_frame_width_minus_1": width - 1, "max_frame_height_minus_1": height - 1, "base_q_idx": fields["base_q_idx"]}
            if fields != expected or fields["base_q_idx"] == 0:
                raise RuntimeError(f"{name}: unexpected frame header constraints: {fields}")
            fields["tile_cols_log2"] = helpers.helpers.trace_value(trace, "tile_cols_log2")
            fields["tile_rows_log2"] = helpers.helpers.trace_value(trace, "tile_rows_log2")
            if fields["tile_cols_log2"] != tile_columns or fields["tile_rows_log2"] != tile_rows:
                raise RuntimeError(f"{name}: unexpected tile layout")
            bits = helpers.helpers.trace_value(trace, "cdef_bits")
            damping_minus3 = helpers.helpers.trace_value(trace, "cdef_damping_minus_3")
            strengths = {key: trace_array(trace, key, 1 << bits) for key in ("cdef_y_pri_strength", "cdef_y_sec_strength", "cdef_uv_pri_strength", "cdef_uv_sec_strength")}
            loop_levels = [int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]
            if not loop_levels or any(loop_levels):
                raise RuntimeError(f"{name}: loop filtering is enabled")
            decode = [args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d", "-i", str(obu_path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format, str(reference_path)]
            decoded = run(decode)
            versions = re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)
            if not versions or (ffmpeg_dav1d_version is not None and versions[0] != ffmpeg_dav1d_version):
                raise RuntimeError("missing or inconsistent FFmpeg libdav1d version")
            ffmpeg_dav1d_version = versions[0]
            reference = reference_path.read_bytes()
            planes = unpack_planes(reference, width, height, depth)
            # dav1d 1.2.1's Windows stdout is a text stream and expands 0x0A.
            # Its YUV file muxer opens binary mode, preserving high-depth bytes.
            cli_filtered_path = args.out / f"{name}.cli_filtered.tmp.yuv"
            cli_all = [args.dav1d, "--quiet", "--input", str(obu_path), "--demuxer", "section5", "--muxer", "yuv", "--output", str(cli_filtered_path), "--limit", "1", "--inloopfilters", "all"]
            run_binary(cli_all)
            cli_filtered = cli_filtered_path.read_bytes()
            if cli_filtered != reference:
                raise RuntimeError(f"{name}: dav1d CLI and FFmpeg filtered reference differ")
            cli_filtered_path.unlink()
            cli_nocdef = cli_all.copy()
            cli_nocdef[cli_nocdef.index("--output") + 1] = str(unfiltered_path)
            cli_nocdef[-1] = "nocdef"
            run_binary(cli_nocdef)
            unfiltered = unfiltered_path.read_bytes()
            unfiltered_planes = unpack_planes(unfiltered, width, height, depth)
            changes = differences(planes, unfiltered_planes, width, columns, rows)
            changed_total = sum(plane["changed_samples"] for plane in changes.values())
            seam_left = sum(plane["changed_left_of_seam"] for plane in changes.values())
            seam_right = sum(plane["changed_right_of_seam"] for plane in changes.values())
            seam_above = sum(plane["changed_above_seam"] for plane in changes.values())
            seam_below = sum(plane["changed_below_seam"] for plane in changes.values())
            nonzero = any(value for values in strengths.values() for value in values)
            attempts.append({"quantizer": quantizer, "texture_amplitude": amplitude, "cdef_bits": bits, "nonzero_strength": nonzero, "changed_samples": changed_total, "changed_left_of_seam": seam_left, "changed_right_of_seam": seam_right, "changed_above_seam": seam_above, "changed_below_seam": seam_below})
            if nonzero and changed_total > 0 and (columns == 1 or (seam_left > 0 and seam_right > 0)) and (rows == 1 or (seam_above > 0 and seam_below > 0)):
                break
        else:
            raise RuntimeError(f"{name}: no candidate had observable nonzero CDEF on both sides of the seam: {attempts}")
        off_obu = args.out / f"{name}.cdef_off.obu"
        off_reference = args.out / f"{name}.cdef_off.reference.yuv"
        encode_off = encode.copy()
        encode_off[encode_off.index("--enable-cdef=1")] = "--enable-cdef=0"
        encode_off[encode_off.index("-o") + 1] = str(off_obu)
        run(encode_off)
        decode_off = decode.copy()
        decode_off[decode_off.index("-i") + 1] = str(off_obu)
        decode_off[-1] = str(off_reference)
        run(decode_off)
        off_data = off_reference.read_bytes()
        off_planes = unpack_planes(off_data, width, height, depth)
        avif_path = args.out / f"{name}.avif"
        wrap_avif = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(obu_path), "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif_path)]
        run(wrap_avif)
        avif_reference_path = args.out / f"{name}.avif.reference.tmp.yuv"
        decode_avif = decode.copy()
        decode_avif[decode_avif.index("-i") + 1] = str(avif_path)
        decode_avif[-1] = str(avif_reference_path)
        run(decode_avif)
        if avif_reference_path.read_bytes() != reference:
            raise RuntimeError(f"{name}: remuxed AVIF reference differs from original OBU")
        avif_reference_path.unlink()
        plane_records = {}
        offset = 0
        sample_bytes = 1 if depth == 8 else 2
        for plane, samples in zip(("y", "u", "v"), planes):
            byte_length = len(samples) * sample_bytes
            plane_records[plane] = {"sample_count": len(samples), "byte_offset": offset, "byte_length": byte_length, "sha256": sha256(reference[offset:offset + byte_length]), "minimum": min(samples), "maximum": max(samples), "unique_count": len(set(samples))}
            offset += byte_length
        stream = obu_path.read_bytes()
        records.append({
            "name": name, "dimensions": [width, height], "bit_depth": depth, "pixel_format": pixel_format,
            "tile_grid": [columns, rows], "tile_sizes": [[min(64, width - x * 64), min(64, height - y * 64)] for y in range(rows) for x in range(columns)],
            "superblock_size": 64, "partition_size": 16, "transform_mode": "ONLY_LARGEST",
            "lossless": False, "quantizer": quantizer, "texture_amplitude": amplitude, "input_pattern": INPUT_PATTERN,
            "input_file": input_path.name, "input_sha256": sha256(input_data),
            "obu_file": obu_path.name, "obu_bytes": len(stream), "obu_sha256": sha256(stream),
            "avif_file": avif_path.name, "avif_sha256": sha256(avif_path.read_bytes()), "avif_reference_matches_obu": True,
            "reference_file": reference_path.name, "reference_sha256": sha256(reference), "reference_planes": plane_records,
            "unfiltered_same_obu_file": unfiltered_path.name, "unfiltered_same_obu_sha256": sha256(unfiltered),
            "same_obu_cdef_changes": changes, "cli_filtered_matches_ffmpeg": True, "cli_filtered_sha256": sha256(cli_filtered),
            "header_trace": fields, "loop_filter_levels": loop_levels,
            "cdef": {"bits": bits, "damping_minus_3": damping_minus3, "damping": damping_minus3 + 3, **strengths,
                     "effective_y_secondary": [4 if value == 3 else value for value in strengths["cdef_y_sec_strength"]],
                     "effective_uv_secondary": [4 if value == 3 else value for value in strengths["cdef_uv_sec_strength"]]},
            "matched_cdef_off": {"obu_file": off_obu.name, "obu_sha256": sha256(off_obu.read_bytes()), "reference_file": off_reference.name, "reference_sha256": sha256(off_data), "changes_from_filtered": differences(planes, off_planes, width, columns, rows), "note": "ancillary matched encoder configuration; coefficient entropy and prefilter reconstruction are not assumed identical"},
            "candidate_attempts": attempts,
            "commands": {"encode": encode, "trace_headers": trace_command, "decode_reference": decode, "dav1d_cli_all": cli_all, "dav1d_cli_nocdef_same_obu": cli_nocdef, "encode_cdef_off": encode_off, "decode_cdef_off": decode_off, "wrap_avif_without_reencoding": wrap_avif, "decode_avif_reference": decode_avif},
        })
        tests.append({"name": name, "width": width, "height": height, "bit_depth": depth, "stream": stream, "avif": avif_path.read_bytes(), "planes": planes})
        print(f"generated {name}: q{quantizer}, amplitude={amplitude}, cdef_bits={bits}, damping={damping_minus3 + 3}, changes={changed_total}, seam L/R={seam_left}/{seam_right} T/B={seam_above}/{seam_below}, OBU={len(stream)} bytes", flush=True)
    formatted = run([args.moonfmt, "-"], input_text=generate_test(tests)).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest = {
        "scope": "real frame-level nonzero CDEF on textured YUV420 at 8/10/12 bits, single and horizontal/vertical tiled frames including odd visible dimensions",
        "format": "untouched libaom OBU and complete filtered/unfiltered-same-OBU dav1d planes",
        "generation_command": [sys.executable, *sys.argv], "source_manifest": str(args.source), "source_manifest_sha256": sha256(args.source.read_bytes()),
        "encoder_version": encoder_version.group(0), "ffmpeg_version": ffmpeg_version,
        "ffmpeg_decoder_version": f"libdav1d {ffmpeg_dav1d_version}", "dav1d_cli_version": dav1d_cli_version,
        "same_obu_filter_evidence": "CLI all must equal FFmpeg libdav1d reference; CLI nocdef decodes the identical OBU, isolating actual CDEF sample changes",
        "seam_band": "two luma samples and one chroma sample on each side of x=64 or y=64 according to tile orientation",
        "generated_test": str(args.test), "generated_test_sha256": sha256(args.test.read_bytes()),
        "test_api": "av1_decode_frame_planes(stream) then av1_frame_crop(frame, plane); public av1_decode and automatic avif_decode_rgba are also checked",
        "fixtures": records,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(records)} CDEF frame fixtures and {args.test}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
