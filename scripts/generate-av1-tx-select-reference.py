#!/usr/bin/env python3
"""Generate real tx_mode=SELECT references from the fixed16 partition inputs.

This deliberately enables libaom's actual transform-size search. Every encoded
stream must report tx_mode=2 through FFmpeg's header parser; no OBU header or
entropy payload is rewritten. Complete references come from libdav1d.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("tests/fixtures/av1-partition/manifest.json"))
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/av1-tx-select"))
    parser.add_argument("--test", type=Path, default=Path("av1_tx_select_reference_wbtest.mbt"))
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
    for bit_depth in (8, 10, 12):
        source_name = f"split16_64x64_{bit_depth}bit_q30"
        template = source_cases[source_name]
        name = source_name + "_tx_select"
        input_path = args.out / f"{name}.input.yuv"
        obu_path = args.out / f"{name}.obu"
        reference_path = args.out / f"{name}.reference.yuv"
        source_input = args.source.parent / template["input_file"]
        input_data = source_input.read_bytes()
        if sha256(input_data) != template["input_sha256"]:
            raise RuntimeError(f"{source_name}: source input no longer matches its manifest")
        input_path.write_bytes(input_data)
        encode = template["commands"]["encode"].copy()
        encode[0] = args.aomenc
        encode[encode.index("--enable-tx-size-search=0")] = "--enable-tx-size-search=1"
        output_index = encode.index("-o")
        encode[output_index + 1] = str(obu_path)
        encode[output_index + 2] = str(input_path)
        required = ("--cpu-used=0", "--min-partition-size=16", "--max-partition-size=16", "--cq-level=30")
        if any(flag not in encode for flag in required):
            raise RuntimeError(f"{source_name}: source is not the expected fixed16/q30 CPU0 layout")
        run(encode)
        trace_command = [
            args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers",
            "-f", "null", "-",
        ]
        trace = run(trace_command).stderr
        fields = {field: helpers.helpers.trace_value(trace, field) for field in template["header_trace"]}
        expected_fields = {**template["header_trace"], "tx_mode": 2}
        if fields != expected_fields:
            raise RuntimeError(f"{name}: expected actual tx_mode=2 and unchanged sequence constraints\n{fields}\n{expected_fields}")
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
        planes = helpers.unpack_planes(reference, 64, 64, bit_depth)
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
            "dimensions": [64, 64], "bit_depth": bit_depth, "pixel_format": pixel_format, "quantizer": 30,
            "partition_constraints": copy.deepcopy(template["partition_constraints"]),
            "superblock_size": 64, "transform_mode": "SELECT", "transform_type": "DCT_DCT",
            "transform_evidence": "FFmpeg trace_headers parsed tx_mode=2 from the original libaom OBU",
            "input_pattern": copy.deepcopy(template["input_pattern"]),
            "input_file": input_path.name, "input_sha256": sha256(input_data),
            "obu_file": obu_path.name, "obu_bytes": len(stream), "obu_sha256": sha256(stream),
            "reference_file": reference_path.name, "reference_sha256": sha256(reference),
            "reference_planes": plane_records, "header_trace": fields, "loop_filter_levels": loop_levels,
            "color_matrix": 2, "color_matrix_note": "unspecified CICP uses the existing BT.601-family conversion",
            "commands": {"encode": encode, "trace_headers": trace_command, "decode_reference": decode},
        })
        tests.append({"name": name, "width": 64, "height": 64, "bit_depth": bit_depth, "stream": stream, "planes": planes})
        print(f"generated {name}: tx_mode={fields['tx_mode']}, {len(stream)} OBU bytes, distinct Y/U/V {[len(set(p)) for p in planes]}", flush=True)
    # Reuse the full-plane fixture template and the shared white-box comparator.
    source = helpers.generate_test(tests)
    source = source.replace("generate-av1-partition-reference.py", "generate-av1-tx-select-reference.py")
    source = source.replace("libaom partition fixtures", "libaom tx_mode=SELECT fixtures")
    source = source.replace("external libaom dav1d partition ", "external libaom dav1d tx_select ")
    formatted = run([args.moonfmt, "-"], input_text=source).stdout
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    manifest = {
        "scope": "real tx_mode=SELECT in fixed16 DC-intra DCT blocks, SB64, YUV420, 8/10/12-bit; not general AV1 conformance",
        "format": "untouched aomenc OBU and complete independent libdav1d planar references",
        "generation_command": [sys.executable, *sys.argv], "source_manifest": str(args.source),
        "source_manifest_sha256": sha256(args.source.read_bytes()), "encoder_version": encoder_version.group(0),
        "ffmpeg_version": ffmpeg_version, "decoder_version": f"libdav1d {dav1d_version}",
        "generated_test": str(args.test), "generated_test_sha256": sha256(args.test.read_bytes()),
        "reference_test_encoding": "lossless value/count RLE; every coded-depth YUV sample and public RGBA pixel is compared by av1_reference_planes_wbtest.mbt",
        "fixtures": records,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {len(records)} actual tx_mode=SELECT fixtures and {args.test}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
