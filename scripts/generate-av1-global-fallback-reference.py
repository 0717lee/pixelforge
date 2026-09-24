#!/usr/bin/env python3
"""Legal GLOBALMV fallback streams, validated by two independent dav1d builds.

The fixture is a controlled header/tile rewrite of a committed libaom stream.
--check reads files only and does not launch a decoder or modify artifacts.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests/fixtures/av1-global-fallback"
TEST = ROOT / "av1_global_fallback_reference_wbtest.mbt"
BASE = ROOT / "tests/fixtures/av1-inter/inter_screen_content_64x64.obu"
spec = importlib.util.spec_from_file_location("fallback_bits", Path(__file__).with_name("generate-av1-inter-reference.py"))
bits = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bits)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def specs():
    return [
        dict(name="integer_rotzoom_global_residual", integer=True, shear_valid=True,
             matrix=[0, 0, 66048, 256, -256, 66048], tile_byte=0, value=47),
        dict(name="integer_rotzoom_global_skip", integer=True, shear_valid=True,
             matrix=[0, 0, 66048, 256, -256, 66048], tile_byte=0, value=156),
        dict(name="invalid_shear_global_skip", integer=False, shear_valid=False,
             matrix=[0, 0, 73726, 8190, -8190, 73726], tile_byte=2, xor=2),
    ]


def construct(case):
    data = BASE.read_bytes()
    start, payload_at, size = bits.frame_obus(data)[1]
    original = bits._split_bits(data[payload_at:payload_at + size])
    # Positions are relative to the frame OBU payload; FFmpeg trace positions
    # include its two-byte OBU header. Only LAST gets a nonidentity model.
    gm, header_bits = 103, 112
    if original[gm:gm + 7] != [0] * 7 or original[7] or original[42]:
        raise ValueError("base stream no longer matches the recorded syntax")
    matrix = case["matrix"]
    inserted = [1, 1]  # is_global=1, is_rot_zoom=1
    for idx, previous, abs_bits, precision in ((2, 65536, 12, 15), (3, 0, 12, 15), (0, 0, 12, 6), (1, 0, 12, 6)):
        inserted += bits._write_global_param(matrix[idx], previous, idx, abs_bits, precision)
    rewritten = original[:gm] + inserted + original[gm + 1:header_bits]
    if case["integer"]:
        rewritten[7] = 1
        del rewritten[42]  # allow_high_precision_mv is absent for integer MV.
    while len(rewritten) % 8:
        rewritten.append(0)
    tile = bytearray(data[payload_at + header_bits // 8:payload_at + size])
    at = case["tile_byte"]
    if "value" in case:
        tile[at] = case["value"]
    else:
        tile[at] ^= case["xor"]
    payload = bits._pack_bits(rewritten) + tile
    return data[:start] + bytes([0x32]) + bits._leb128(len(payload)) + payload + data[payload_at + size:]


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"Reference command failed: {command}\n{result.stderr[-2000:]}")
    return result


def render(manifest):
    text = '''/// Complete legal GLOBALMV frame streams, independently decoded by dav1d
/// through FFmpeg and the traced dav1d CLI. Every native sample contributes
/// to the checksums; complete pixels and actual GLOBALMV traces are committed.

///|
fn av1_global_fallback_reference_check(data : Array[Byte], integer : Bool,
  shear_valid : Bool, matrix : Array[Int], expected : Array[UInt]) -> Unit raise {
  let (sequence, headers, _) = av1_inter_parse(data, "global fallback")
  let header = headers[1]
  assert_eq(header.force_integer_mv, if integer { 1 } else { 0 })
  assert_eq(header.gm_type[av1_last_frame], av1_gm_rot_zoom)
  assert_eq(header.gm_params[av1_last_frame], matrix)
  assert_eq(av1_warp_from_global_motion(matrix) is Some(_), shear_valid)
  assert_true(av1_inter_frame_supported(header, sequence))
  let frames = av1_video_decode_temporal_unit_planes(av1_video_decoder(), data,
    allow_monochrome=true).unwrap()
  assert_eq(frames.length(), 2)
  for frame in 0..<2 {
    assert_eq((frames[frame].width, frames[frame].height, frames[frame].bit_depth), (64, 64, 8))
    for plane in 0..<3 {
      let pixels = av1_frame_crop(frames[frame], plane)
      let bytes = pixels.map(value => value.to_byte())
      assert_eq((frame, plane, crc32(bytes, 0, bytes.length())),
        (frame, plane, expected[frame * 3 + plane]))
    }
  }
}
'''
    for case in manifest["cases"]:
        data = (OUT / (case["name"] + ".obu")).read_bytes()
        text += f'\n///|\ntest "legal global fallback {case["name"]} matches two dav1d builds" {{\n'
        text += "  let data : Array[Byte] = [" + ", ".join(f"0x{x:02x}" for x in data) + "]\n"
        crcs = ", ".join(f"0x{x:08x}U" for x in case["plane_crc32"])
        text += f'  av1_global_fallback_reference_check(data, {str(case["integer"]).lower()}, {str(case["shear_valid"]).lower()}, {case["matrix"]}, [{crcs}])\n}}\n'
    return text


def canonical(text):
    return re.sub(r",(?=[\])}])", "", re.sub(r"\s+", "", text))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument("--dav1d-trace", help="dav1d CLI with DEBUG_BLOCK_INFO=1; required to prove GLOBALMV use")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((OUT / "manifest.json").read_text())
        if sha(BASE.read_bytes()) != manifest["base_sha256"]:
            raise SystemExit("base stream changed")
        for name, digest in manifest["artifacts"].items():
            if sha((OUT / name).read_bytes()) != digest:
                raise SystemExit(f"artifact changed: {name}")
        for case in manifest["cases"]:
            if construct(case) != (OUT / (case["name"] + ".obu")).read_bytes():
                raise SystemExit("controlled syntax rewrite no longer reproduces fixture")
            if not re.search(r"Post-intermode\[2[,\]]", (OUT / (case["name"] + ".blocks.txt")).read_text()):
                raise SystemExit("missing original-decoder GLOBALMV evidence")
            native = (OUT / (case["name"] + ".reference.yuv")).read_bytes()
            offsets = [(0, 4096), (4096, 5120), (5120, 6144), (6144, 10240), (10240, 11264), (11264, 12288)]
            if len(native) != 12288 or [zlib.crc32(native[lo:hi]) for lo, hi in offsets] != case["plane_crc32"]:
                raise SystemExit("native planes do not reproduce expected pixel checksums")
        if canonical(TEST.read_text()) != canonical(render(manifest)):
            raise SystemExit("expected tests differ from independent decoder artifacts")
        print("Validated three complete GLOBALMV fallback streams; no files changed.")
        return
    if not args.dav1d_trace:
        parser.error("--dav1d-trace is required to regenerate")
    artifacts, cases = {}, []
    OUT.mkdir(parents=True, exist_ok=True)
    def write(name, data):
        (OUT / name).write_bytes(data)
        artifacts[name] = sha(data)
    with tempfile.TemporaryDirectory(prefix="pixelforge-global-fallback-") as folder:
        folder = Path(folder)
        for spec in specs():
            name = spec["name"]
            data = construct(spec)
            source, ffout, cliout = folder / (name + ".obu"), folder / "ffmpeg.yuv", folder / "dav1d.yuv"
            source.write_bytes(data)
            run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-xerror", "-y", "-c:v", "libdav1d", "-i", str(source), "-pix_fmt", "yuv420p", "-f", "rawvideo", str(ffout)])
            cli = run([args.dav1d_trace, "-i", str(source), "-o", str(cliout), "--muxer=yuv"])
            native = ffout.read_bytes()
            if len(native) != 12288 or native != cliout.read_bytes():
                raise RuntimeError("independent full native frame outputs disagree")
            block_trace = "\n".join(line for line in (cli.stdout + "\n" + cli.stderr).splitlines() if line.startswith(("poc=", "Post-"))) + "\n"
            if not re.search(r"Post-intermode\[2[,\]]", block_trace):
                raise RuntimeError("reference stream does not exercise GLOBALMV")
            header = run([args.ffmpeg, "-hide_banner", "-loglevel", "info", "-i", str(source), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"])
            header_trace = "\n".join(re.sub(r"\[trace_headers @ [^]]+\]", "[trace_headers]", line) for line in header.stderr.splitlines() if "[trace_headers @" in line) + "\n"
            write(name + ".obu", data)
            write(name + ".reference.yuv", native)
            write(name + ".blocks.txt", block_trace.encode())
            write(name + ".headers.txt", header_trace.encode())
            offsets = [(0, 4096), (4096, 5120), (5120, 6144), (6144, 10240), (10240, 11264), (11264, 12288)]
            cases.append({**spec, "plane_crc32": [zlib.crc32(native[lo:hi]) for lo, hi in offsets]})
            print(name, "two full native frames and actual GLOBALMV verified")
    manifest = {"base": str(BASE.relative_to(ROOT)).replace("\\", "/"), "base_sha256": sha(BASE.read_bytes()),
                "construction": "controlled uncompressed-header rewrite plus one recorded tile byte change; independently decoded, not original encoder output",
                "specification": "https://aomediacodec.github.io/av1-spec/#inter-prediction-process",
                "reference_source": "dav1d 1.2.1 decode.c gmv_warp_allowed and recon_tmpl.c warp_affine/mc selection",
                "ffmpeg_version": run([args.ffmpeg, "-version"]).stdout.splitlines()[0],
                "dav1d_binary_sha256": sha(Path(args.dav1d_trace).read_bytes()),
                "cases": cases, "artifacts": artifacts}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    formatted = subprocess.run(["moonfmt", "-"], input=render(manifest), text=True, capture_output=True, check=True).stdout
    TEST.write_text(formatted, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
