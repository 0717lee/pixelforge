#!/usr/bin/env python3
"""Generate real AV1 references with the seven DC/axis/smooth/Paeth predictors.

Reuse retained partition-corpus inputs and exact encoder commands, enable the
requested prediction modes, and decode untouched OBU streams with libdav1d.
The complete planar reference is compared through the existing color converter.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import itertools
import json
import re
import shutil
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

LAYOUTS = ("split16_64x64", "split32_64x64", "adaptive_128x64")
PREDICTOR_FLAGS = {
    "--enable-directional-intra": 1,
    "--enable-diagonal-intra": 0,
    "--enable-smooth-intra": 1,
    "--enable-paeth-intra": 1,
    "--enable-angle-delta": 0,
    "--enable-cfl-intra": 0,
    "--enable-palette": 0,
    "--enable-filter-intra": 0,
    "--enable-intra-edge-filter": 0,
    "--enable-cdef": 0,
    "--enable-restoration": 0,
    "--loopfilter-control": 0,
    "--enable-tx-size-search": 0,
    "--use-intra-default-tx-only": 1,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("tests/fixtures/av1-partition/manifest.json"))
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-intra-modes"))
    parser.add_argument("--test", type=Path, default=Path("av1_intra_mode_reference_wbtest.mbt"))
    parser.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
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
    records = []
    tests = []
    dav1d_version = None
    for bit_depth, layout in itertools.product((8, 10, 12), LAYOUTS):
        source_name = f"{layout}_{bit_depth}bit_q30"
        template = source_cases[source_name]
        width, height = template["dimensions"]
        name = source_name + "_intra_modes"
        input_path = args.out / f"{name}.input.yuv"
        obu_path = args.out / f"{name}.obu"
        reference_path = args.out / f"{name}.reference.yuv"
        source_input = args.source.parent / template["input_file"]
        input_data = source_input.read_bytes()
        if sha256(input_data) != template["input_sha256"]:
            raise RuntimeError(f"{source_name}: source input no longer matches the manifest")
        input_path.write_bytes(input_data)
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        for flag, value in PREDICTOR_FLAGS.items():
            indices = [index for index, argument in enumerate(encode) if argument.startswith(flag + "=")]
            if len(indices) > 1:
                raise RuntimeError(f"{source_name}: duplicate encoder flag {flag}")
            if indices:
                encode[indices[0]] = f"{flag}={value}"
            else:
                encode.insert(1, f"{flag}={value}")
        output_index = encode.index("-o")
        encode[output_index + 1] = str(obu_path)
        encode[output_index + 2] = str(input_path)
        run(encode)
        trace_command = [
            args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers",
            "-f", "null", "-",
        ]
        trace = run(trace_command).stderr
        fields = {field: helpers.helpers.trace_value(trace, field) for field in template["header_trace"]}
        if fields != template["header_trace"] or fields["tx_mode"] != 1:
            raise RuntimeError(f"{name}: unexpected sequence, quantization, or transform-mode change\n{fields}")
        loop_levels = [int(value) for value in re.findall(r"loop_filter_level\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]
        if not loop_levels or any(loop_levels):
            raise RuntimeError(f"{name}: loop filtering was not disabled")
        pixel_format = template["pixel_format"]
        decode = [
            args.ffmpeg, "-hide_banner", "-loglevel", "verbose", "-y", "-c:v", "libdav1d",
            "-i", str(obu_path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pixel_format,
            str(reference_path),
        ]
        decoded = run(decode)
        versions = re.findall(r"libdav1d\s+([0-9][^\s]*)", decoded.stderr)
        if not versions or (dav1d_version is not None and versions[0] != dav1d_version):
            raise RuntimeError(f"{name}: missing or inconsistent libdav1d version")
        dav1d_version = versions[0]
        reference = reference_path.read_bytes()
        planes = helpers.unpack_planes(reference, width, height, bit_depth)
        if any(len(set(plane)) == 1 for plane in planes):
            raise RuntimeError(f"{name}: expected nonconstant reference Y, U and V")
        plane_records = {}
        offset = 0
        sample_bytes = 1 if bit_depth == 8 else 2
        for plane, values in zip(("y", "u", "v"), planes):
            byte_length = len(values) * sample_bytes
            plane_records[plane] = {
                "sample_count": len(values), "byte_offset": offset, "byte_length": byte_length,
                "sha256": sha256(reference[offset:offset + byte_length]), "minimum": min(values),
                "maximum": max(values), "unique_count": len(set(values)),
            }
            offset += byte_length
        stream = obu_path.read_bytes()
        records.append({
            "name": name, "source_case": source_name, "source_input_file": str(source_input),
            "dimensions": [width, height], "bit_depth": bit_depth, "pixel_format": pixel_format, "quantizer": 30,
            "partition_constraints": copy.deepcopy(template["partition_constraints"]),
            "superblock_size": 64, "transform_mode": "ONLY_LARGEST",
            "transform_type": "intra default DCT/ADST selected according to mode and transform size",
            "predictors_permitted": ["DC", "V", "H", "SMOOTH", "SMOOTH_V", "SMOOTH_H", "PAETH"],
            "predictor_flags": PREDICTOR_FLAGS,
            "mode_coverage_note": "encoder mode searches are enabled; individual chosen prediction symbols are not inferred from header traces",
            "input_pattern": copy.deepcopy(template["input_pattern"]),
            "input_file": input_path.name, "input_sha256": sha256(input_data),
            "obu_file": obu_path.name, "obu_bytes": len(stream), "obu_sha256": sha256(stream),
            "reference_file": reference_path.name, "reference_sha256": sha256(reference),
            "reference_planes": plane_records, "header_trace": fields, "loop_filter_levels": loop_levels,
            "color_matrix": 2, "color_matrix_note": "unspecified CICP uses the existing BT.601-family conversion",
            "commands": {"encode": encode, "trace_headers": trace_command, "decode_reference": decode},
        })
        tests.append({"name": name, "width": width, "height": height, "bit_depth": bit_depth, "stream": stream, "planes": planes})
        print(f"generated {name}: {len(stream)} OBU bytes, distinct Y/U/V {[len(set(p)) for p in planes]}", flush=True)
    source = helpers.generate_test(tests)
    source = source.replace("generate-av1-partition-reference.py", "generate-av1-intra-mode-reference.py")
    source = source.replace("libaom partition fixtures", "libaom axis/smooth/Paeth intra fixtures")
    source = source.replace("external libaom dav1d partition ", "external libaom dav1d intra_modes ")
    formatted = run([args.moonfmt, "-"], input_text=source).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest = {
        "scope": "DC/V/H/SMOOTH/SMOOTH_V/SMOOTH_H/PAETH searches on fixed and adaptive partitions, SB64, YUV420, 8/10/12-bit",
        "format": "untouched aomenc OBU and complete independent libdav1d planar references",
        "generation_command": [sys.executable, *sys.argv], "source_manifest": str(args.source),
        "source_manifest_sha256": sha256(args.source.read_bytes()), "encoder_version": encoder_version.group(0),
        "ffmpeg_version": ffmpeg_version, "decoder_version": f"libdav1d {dav1d_version}",
        "generated_test": str(args.test), "generated_test_sha256": sha256(args.test.read_bytes()),
        "reference_test_encoding": "lossless value/count RLE; every coded-depth YUV sample and public RGBA pixel is compared by av1_reference_planes_wbtest.mbt",
        "fixtures": records,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(records)} intra-mode fixtures and {args.test}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
