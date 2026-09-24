#!/usr/bin/env python3
"""Untouched libaom fixtures, independent dav1d planes and symbol evidence.

Tools resolve from command-line arguments, environment variables or PATH.
--check regenerates in a TemporaryDirectory and never writes repository files.
The optional DEBUG_BLOCK_INFO dav1d executable is required for block-level
coverage: a frame header permitting a tool is not evidence of its use.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "fixtures" / "av1-mainline"
TEST = ROOT / "av1_mainline_reference_wbtest.mbt"
SOURCES = {
    "libaom": "https://aomedia.googlesource.com/aom/+/refs/tags/v3.6.0/av1/encoder/encodeframe.c",
    "screen_content": "https://aomedia.googlesource.com/aom/+/refs/tags/v3.6.0/av1/encoder/encoder.c",
    "dav1d_symbols": "https://code.videolan.org/videolan/dav1d/-/blob/1.2.1/src/decode.c",
}

INTER_FLAGS = [
    "--deltaq-mode=0", "--enable-intrabc=0", "--enable-palette=0",
    "--enable-cdef=0", "--enable-restoration=0", "--loopfilter-control=0",
    "--enable-tx64=0", "--sb-size=64", "--enable-order-hint=1",
    "--enable-ref-frame-mvs=0", "--enable-warped-motion=0", "--enable-global-motion=0",
    "--enable-obmc=0", "--enable-interintra-comp=0", "--enable-masked-comp=0",
    "--enable-dual-filter=0", "--min-partition-size=16", "--max-partition-size=32",
]


def specs() -> list[dict]:
    result = []
    for tool in ("qmatrix", "intrabc", "deltalf"):
        for depth in (8, 10, 12):
            width = 32 if tool == "qmatrix" else (256 if tool == "intrabc" else 128)
            height = 32 if tool == "qmatrix" else 128
            flags = ["--enable-qm=0", "--enable-intrabc=0", "--deltaq-mode=0",
                     "--enable-cdef=0", "--enable-restoration=0", "--enable-palette=0",
                     "--use-intra-dct-only=1", "--enable-tx64=0", "--sb-size=64"]
            if tool == "qmatrix":
                flags += ["--enable-qm=1", "--qm-min=5", "--qm-max=5",
                          "--min-partition-size=16", "--max-partition-size=16",
                          "--loopfilter-control=0"]
            elif tool == "intrabc":
                flags += ["--enable-intrabc=1", "--tune-content=screen", "--lossless=1"]
            else:
                flags += ["--deltaq-mode=2", "--enable-tpl-model=1", "--delta-lf-mode=1",
                          "--loopfilter-control=1", "--min-partition-size=16",
                          "--max-partition-size=32"]
            result.append(dict(name=f"{tool}_{depth}bit_{width}x{height}", tool=tool,
                               width=width, height=height, bit_depth=depth, frames=1,
                               flags=flags))
    intrabc = next(s for s in result if s["tool"] == "intrabc" and s["bit_depth"] == 8)
    deltalf = next(s for s in result if s["tool"] == "deltalf" and s["bit_depth"] == 8)
    result += [
        dict(deltalf, name="deltalf_filter_8bit_128x128", pattern="ramp", prove_deblock=True,
             flags=deltalf["flags"] + ["--cq-level=48"]),
        dict(intrabc, name="intrabc_residual_8bit_256x128", perturb_copy=True,
             flags=intrabc["flags"] + ["--lossless=0", "--cq-level=24"]),
        dict(intrabc, name="intrabc_444_10bit_256x128", bit_depth=10,
             sampling="444", sub_x=0, sub_y=0),
        dict(name="segmentation_inherit_8bit_128x128", tool="segmentation", pattern="deltalf",
             width=128, height=128, bit_depth=8, frames=4,
             flags=INTER_FLAGS + ["--aq-mode=1", "--passes=2"], require="inherit"),
        dict(name="segmentation_temporal_8bit_128x128", tool="segmentation", pattern="deltalf",
             width=128, height=128, bit_depth=8, frames=4,
             flags=INTER_FLAGS + ["--aq-mode=3", "--enable-tpl-model=0"], require="temporal"),
        dict(name="wedge_8bit_128x128", tool="wedge", encoder="ffmpeg-libaom",
             width=128, height=128, bit_depth=8, frames=4, quality=32,
             flags=INTER_FLAGS + ["--enable-masked-comp=1", "--enable-interinter-wedge=1",
                                 "--enable-diff-wtd-comp=0", "--enable-dist-wtd-comp=0",
                                 "--enable-onesided-comp=1", "--min-partition-size=8"]),
        dict(name="compound_globalwarp_8bit_128x128", tool="compound-globalwarp", encoder="ffmpeg-libaom",
             width=128, height=128, bit_depth=8, frames=4, quality=40,
             flags=INTER_FLAGS + ["--enable-global-motion=1", "--enable-dist-wtd-comp=0",
                                 "--enable-onesided-comp=1"]),
    ]
    for depth in (8, 10, 12):
        result.append(dict(name=f"combined_{depth}bit_420_64x64", tool="combined", encoder="ffmpeg-libaom",
                           width=64, height=64, bit_depth=depth, frames=4, quality=32, flags=[]))
    for sampling, sub_x, sub_y in (("422", 1, 0), ("444", 0, 0)):
        result.append(dict(name=f"combined_10bit_{sampling}_64x64", tool="combined", encoder="ffmpeg-libaom",
                           width=64, height=64, bit_depth=10, frames=4, quality=32, flags=[],
                           sampling=sampling, sub_x=sub_x, sub_y=sub_y))
    result.append(dict(name="combined_10bit_420_256x128_2tiles", tool="combined", encoder="ffmpeg-libaom",
                       width=256, height=128, bit_depth=10, frames=4, quality=32,
                       flags=["--tile-columns=1", "--tile-rows=0"], tile_count=2))
    return result


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resolve(value: str | None, env: str, default: str) -> str:
    requested = value or os.environ.get(env) or default
    found = shutil.which(requested)
    if not found:
        raise SystemExit(f"Cannot find {requested}; supply --{env.lower().replace('_', '-')}")
    return str(Path(found).resolve())


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess:
    proc = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    if proc.returncode:
        raise RuntimeError(f"Command failed ({proc.returncode}): {command}\n"
                           f"{proc.stdout[-3000:]}\n{proc.stderr[-3000:]}")
    return proc


def source(spec: dict) -> bytes:
    width, height, depth = spec["width"], spec["height"], spec["bit_depth"]
    values = []
    for frame in range(spec["frames"]):
        for plane in range(3):
            pw, ph = (width, height) if plane == 0 else (width >> spec.get("sub_x", 1), height >> spec.get("sub_y", 1))
            for y in range(ph):
                for x in range(pw):
                    pattern = spec.get("pattern", spec["tool"])
                    if pattern == "intrabc":
                        # Identical detailed cells in independently decoded SBs.
                        px, py = x % (32 if plane == 0 else 16), y % (32 if plane == 0 else 16)
                        value = 32 + ((px * 37 + py * 19 + (px ^ py) * 13 + plane * 29) % 192)
                    elif pattern == "deltalf":
                        # SB energies differ substantially, yielding nonzero delta-Q/LF.
                        if x < pw // 2 and y < ph // 2:
                            value = 80 + ((x + y + plane * 3) % 9)
                        else:
                            value = 128 + round(43 * math.sin(x * 0.43 + plane) +
                                                39 * math.cos(y * 0.37) +
                                                17 * math.sin((x + y) * 1.13))
                    elif pattern == "wedge":
                        sx = x + frame * 4 if x + y < pw else x - frame * 4
                        value = 128 + round(43 * math.sin(sx * .61 + plane) +
                                            37 * math.cos(y * .49) + 21 * math.sin((sx + y) * .27))
                    elif pattern == "compound-globalwarp":
                        scale = 1 + frame * .004
                        value = round(texture((x - pw / 2) * scale + pw / 2,
                                              (y - ph / 2) * scale + ph / 2, plane))
                    elif pattern == "ramp":
                        value = 32 + (x + 2 * y) % 192
                    elif pattern == "combined":
                        # Fractional translation of detailed, nonneutral planes.
                        sx = x + frame * .75
                        sy = y + frame * .5
                        value = round(texture(sx, sy, plane))
                    else:
                        value = 128 + round(48 * math.sin(x * 0.35 + plane) +
                                            35 * math.cos(y * 0.29) +
                                            11 * math.sin((x + y) * 0.83))
                    if spec.get("require") == "temporal" and frame == 3 and plane == 0 and x < 32 and y < 32:
                        value += 4
                    if spec.get("perturb_copy") and plane == 0 and x >= width // 2 and (x + y) % 5 == 0:
                        value += 3
                    sample = max(0, min(255, value)) << (depth - 8)
                    if pattern == "combined" and depth > 8:
                        sample += (x + 3 * y + plane + frame) % (1 << (depth - 8))
                    values.append(sample)
    return bytes(values) if depth == 8 else struct.pack(f"<{len(values)}H", *values)


def texture(x: float, y: float, plane: int) -> float:
    """Deterministic smooth noise provides real corners for global estimation."""
    xi, yi = math.floor(x / 4), math.floor(y / 4)
    fx, fy = x / 4 - xi, y / 4 - yi
    def sample(a: int, b: int) -> int:
        n = (a * 73856093) ^ (b * 19349663) ^ (plane * 83492791)
        n = (n ^ (n >> 13)) * 1274126177
        return 32 + ((n ^ (n >> 16)) & 191)
    return ((sample(xi, yi) * (1 - fx) + sample(xi + 1, yi) * fx) * (1 - fy) +
            (sample(xi, yi + 1) * (1 - fx) + sample(xi + 1, yi + 1) * fx) * fy)


def header_trace(ffmpeg: str, obu: Path, scratch: Path) -> tuple[bytes, list[dict]]:
    proc = run([ffmpeg, "-hide_banner", "-loglevel", "info", "-i", obu.name,
                "-c:v", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"], scratch)
    lines = []
    frames = []
    current = None
    for line in (proc.stdout + proc.stderr).splitlines():
        match = re.match(r"\[trace_headers @ [^\]]+\]\s?(.*)", line)
        if not match:
            continue
        line = match[1]
        lines.append(line)
        if line == "Frame Header":
            current = {}
            frames.append(current)
        elif line in ("Sequence Header", "Tile Group"):
            current = None
        field = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
        if field and current is not None:
            current[field[1]] = int(field[2])
    return ("\n".join(lines) + "\n").encode(), frames


def symbol_trace(text: str, combined: bool = False) -> bytes:
    # Keep block positions and actual decoded symbols; discard timings and
    # instrumentation outside upstream DEBUG_BLOCK_INFO.
    prefixes = ("poc=", "Post-skip[", "Post-intrabcflag[", "Post-dmv[", "Post-delta_q[",
                "Post-delta_lf[", "Post-segid[", "Post-compflag[", "Post-refs[",
                "Post-compintermode[", "Post-compoundtype[", "Post-interintra[",
                "Post-intermode[", "Post-motionmode[", "Post-y-cf-blk[",
                "Post-segwedge_vs_jntavg[", "Post-seg/wedge[", "Mainline-segment[")
    if combined:
        prefixes += ("Post-cdef_idx[", "Post-lr_", "Post-tx[", "Post-uv-cf-blk[",
                     "Post-filterintramode[", "Post-y_pal[", "Post-uv_pal[", "Post-vartxtree[",
                     "Post-ref[", "Post-residual_mv[")
        # Upstream DEBUG_BLOCK_INFO prints uninitialized union members when
        # the corresponding tool was not selected. They are not coded symbols.
        text = re.sub(r"Post-interintra\[t=0,m=-?\d+,w=-?\d+\]", "Post-interintra[t=0]", text)
        text = re.sub(r"Post-interintra\[t=1,m=(-?\d+),w=-?\d+\]", r"Post-interintra[t=1,m=\1]", text)
        text = re.sub(r"Post-seg/wedge\[0,wedge_idx=-?\d+,sign=(\d+)\]", r"Post-seg/wedge[0,sign=\1]", text)
    return ("\n".join(line for line in text.splitlines() if line.startswith(prefixes)) + "\n").encode()


def evidence(spec: dict, headers: list[dict], symbols: bytes) -> dict:
    if len(headers) != spec["frames"]:
        raise ValueError(f"{spec['name']}: expected {spec['frames']} frame headers, got {len(headers)}")
    text = symbols.decode()
    result = {"frame_headers": headers}
    if spec["tool"] == "qmatrix":
        if not all(h.get("using_qmatrix") == 1 and h.get("qm_y") == 5 for h in headers):
            raise ValueError(f"{spec['name']}: qmatrix was not selected")
        result["matrix_coefficient_blocks"] = len(re.findall(r"Post-y-cf-blk\[.*txtp=0,eob=[0-9]", text))
        if not result["matrix_coefficient_blocks"]:
            raise ValueError(f"{spec['name']}: no nonempty DCT coefficient block trace")
    elif spec["tool"] == "intrabc":
        result["copied_blocks"] = text.count("Post-intrabcflag[0]")
        if not any(h.get("allow_intrabc") == 1 for h in headers) or not result["copied_blocks"]:
            raise ValueError(f"{spec['name']}: no actual intra-block copy selected")
        residuals = 0
        copy_block = False
        for line in text.splitlines():
            if line.startswith("poc="):
                copy_block = False
            elif line.startswith("Post-intrabcflag[0]"):
                copy_block = True
            elif copy_block and re.search(r"Post-y-cf-blk\[.*eob=\d", line):
                residuals += 1
        result["copy_residual_transforms"] = residuals
        if spec.get("perturb_copy") and not residuals:
            raise ValueError(f"{spec['name']}: copied blocks have no nonzero residual")
    elif spec["tool"] == "deltalf":
        deltas = [int(v) for v in re.findall(r"Post-delta_lf\[\d+:(-?\d+)\]", text)]
        result["loop_filter_deltas"] = deltas
        if not any(h.get("delta_lf_present") == 1 for h in headers) or not any(deltas):
            raise ValueError(f"{spec['name']}: no nonzero delta-LF symbols selected")
    elif spec["tool"] == "segmentation":
        result["segment_ids"] = sorted({int(v) for v in re.findall(r"Post-segid\[[^;]+;(\d+)\]", text)})
        if spec["require"] == "inherit":
            if not any(h.get("segmentation_update_map") == 0 and h.get("segmentation_update_data") == 0
                       and h.get("primary_ref_frame", 7) != 7 for h in headers):
                raise ValueError(f"{spec['name']}: segmentation was not inherited")
            if not any(result["segment_ids"]):
                raise ValueError(f"{spec['name']}: no nonzero segment IDs")
        else:
            temporal_pocs = {h["order_hint"] for h in headers if h.get("segmentation_temporal_update") == 1}
            poc = -1
            read_count = 0
            for line in text.splitlines():
                position = re.match(r"poc=(\d+),", line)
                if position:
                    poc = int(position[1])
                if poc in temporal_pocs and line.startswith("Post-skip[0]"):
                    read_count += 1
            result["temporal_non_skip_blocks"] = read_count
            if not read_count:
                raise ValueError(f"{spec['name']}: no non-skipped block reads a temporal segment symbol")
            result["predicted_segment_blocks"] = len(re.findall(r"Mainline-segment\[[^\n]*pred=1,skip=0,[^\n]*temporal=1", text))
    elif spec["tool"] == "wedge":
        result["wedge_blocks"] = text.count("Post-seg/wedge[1,")
        if not result["wedge_blocks"]:
            raise ValueError(f"{spec['name']}: no decoded wedge compound blocks")
    elif spec["tool"] == "compound-globalwarp":
        frame_headers = {h.get("order_hint", -1): h for h in headers}
        poc, refs = -1, []
        total, warped_pairs = 0, 0
        for line in text.splitlines():
            position = re.match(r"poc=(\d+),", line)
            if position:
                poc = int(position[1])
            reference = re.match(r"Post-refs\[(\d+)/(\d+)\]", line)
            if reference:
                refs = [int(reference[1]) + 1, int(reference[2]) + 1]
            if line.startswith("Post-compintermode[6,"):
                total += 1
                header = frame_headers[poc]
                if len(refs) == 2 and all(header.get(f"is_global[{r}]") == 1 for r in refs):
                    warped_pairs += 1
        result.update(global_global_blocks=total, nonidentity_global_pairs=warped_pairs)
        if not warped_pairs:
            raise ValueError(f"{spec['name']}: no compound block uses two nonidentity global models")
    elif spec["tool"] == "combined":
        eobs = [int(value) for value in re.findall(r"Post-y-cf-blk\[[^\n]*eob=(-?\d+)", text)]
        result.update(
            ac_luma_transforms=sum(value > 0 for value in eobs),
            partition_types=sorted({int(value) for value in re.findall(r"poc=[^\n]*bp=(\d+)", text)}),
            adaptive_cdf_frames=sum(h.get("disable_cdf_update") == 0 for h in headers),
            primary_reference_frames=sum(h.get("primary_ref_frame", 7) != 7 for h in headers),
            inter_blocks=text.count("Post-intermode["),
            compound_blocks=text.count("Post-compintermode["),
            motion_modes=sorted({int(value) for value in re.findall(r"Post-motionmode\[(\d+)", text)}),
            cdef_index_symbols=text.count("Post-cdef_idx["),
            wiener_units=text.count("Post-lr_wiener["),
            sgrproj_units=text.count("Post-lr_sgrproj["),
            wedge_blocks=text.count("Post-seg/wedge[1,"),
        )
        if not result["ac_luma_transforms"] or not result["inter_blocks"] or not result["adaptive_cdf_frames"]:
            raise ValueError(f"{spec['name']}: AC, inter prediction and entropy adaptation must be active")
        if not any(h.get("frame_type") == 1 for h in headers):
            raise ValueError(f"{spec['name']}: no real inter frame")
        if spec.get("tile_count") and not all((1 << h.get("tile_cols_log2", 0)) * (1 << h.get("tile_rows_log2", 0)) == spec["tile_count"] for h in headers):
            raise ValueError(f"{spec['name']}: requested tile layout was not signaled")
    return result


def encode(spec: dict, tools: dict, scratch: Path) -> tuple[dict, dict[str, bytes]]:
    name = spec["name"]
    raw = source(spec)
    input_path, obu_path = scratch / f"{name}.input.yuv", scratch / f"{name}.obu"
    input_path.write_bytes(raw)
    command = ["--codec=av1", "--obu", f"--i{spec.get('sampling', '420')}", f"--width={spec['width']}",
               f"--height={spec['height']}", f"--bit-depth={spec['bit_depth']}",
               f"--input-bit-depth={spec['bit_depth']}",
               f"--profile={2 if spec['bit_depth'] == 12 else (1 if spec.get('sampling') == '444' else 0)}", "--fps=1/1",
               f"--limit={spec['frames']}", "--passes=1", "--lag-in-frames=0",
               "--threads=1", "--row-mt=0", "--cpu-used=0", "--end-usage=q",
               "--cq-level=32", "--tile-columns=0", "--tile-rows=0", "--debug",
               "--disable-warning-prompt"] + spec["flags"] + ["-o", obu_path.name, input_path.name]
    encoder_label = "aomenc"
    encoder_library = None
    if spec.get("encoder") == "ffmpeg-libaom":
        pixel_format = f"yuv{spec.get('sampling', '420')}p" + (f"{spec['bit_depth']}le" if spec["bit_depth"] > 8 else "")
        command = ["-y", "-hide_banner", "-loglevel", "info", "-f", "rawvideo",
                   "-pixel_format", pixel_format, "-video_size", f"{spec['width']}x{spec['height']}",
                   "-framerate", "25", "-i", input_path.name, "-frames:v", str(spec["frames"]),
                   "-c:v", "libaom-av1", "-cpu-used", "0", "-crf", str(spec["quality"]),
                   "-b:v", "0", "-threads", "1", "-lag-in-frames", "0"]
        if spec["flags"]:
            command += ["-aom-params", ":".join(flag.removeprefix("--") for flag in spec["flags"])]
        command += ["-f", "obu", obu_path.name]
        encoder_label = "ffmpeg"
    encoded = run([tools[encoder_label]] + command, scratch)
    library = re.search(r"\[libaom-av1 @ [^\]]+\]\s+(v?\d+\.\d+\.\d+[^\r\n]*)", encoded.stderr)
    if library:
        encoder_library = library[1]
    trace, headers = header_trace(tools["ffmpeg"], obu_path, scratch)
    decoder_args = ["-q", "--threads=1", "--framedelay=1", "-i", obu_path.name,
                    "--muxer=yuv", "-o", f"{name}.reference.yuv"]
    run([tools["dav1d"]] + decoder_args, scratch)
    native = (scratch / f"{name}.reference.yuv").read_bytes()
    frame_samples = spec["width"] * spec["height"] + 2 * (spec["width"] >> spec.get("sub_x", 1)) * (spec["height"] >> spec.get("sub_y", 1))
    expected_size = frame_samples * spec["frames"] * (1 if spec["bit_depth"] == 8 else 2)
    if len(native) != expected_size:
        raise ValueError(f"{name}: dav1d produced {len(native)} bytes, expected {expected_size}")
    debug_args = decoder_args[:-1] + [f"{name}.debug.yuv"]
    debug = run([tools["trace_dav1d"]] + debug_args, scratch)
    if native != (scratch / f"{name}.debug.yuv").read_bytes():
        raise ValueError(f"{name}: trace decoder differs from release dav1d")
    symbols = symbol_trace(debug.stdout + debug.stderr, combined=spec["tool"] == "combined")
    facts = evidence(spec, headers, symbols)
    if spec["tool"] == "combined":
        sequence = {}
        in_sequence = False
        for line in trace.decode().splitlines():
            if line == "Sequence Header":
                in_sequence = True
            elif line == "Frame Header":
                in_sequence = False
            field = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
            if in_sequence and field:
                sequence[field[1]] = int(field[2])
        facts["sequence_header"] = sequence
    artifacts = {f"{name}.obu": obu_path.read_bytes(), f"{name}.reference.yuv": native,
                 f"{name}.trace.txt": trace, f"{name}.symbols.txt": symbols}
    nodeblock_args = None
    if spec.get("prove_deblock"):
        if not any(h.get("loop_filter_level[0]", 0) or h.get("loop_filter_level[1]", 0) for h in headers):
            raise ValueError(f"{name}: base luma filter levels are zero")
        nodeblock_args = decoder_args[:-1] + [f"{name}.nodeblock.yuv", "--inloopfilters", "nodeblock"]
        run([tools["dav1d"]] + nodeblock_args, scratch)
        nodeblock = (scratch / f"{name}.nodeblock.yuv").read_bytes()
        if len(nodeblock) != len(native):
            raise ValueError(f"{name}: unfiltered plane length differs")
        unpack = lambda data: list(data) if spec["bit_depth"] == 8 else struct.unpack(f"<{len(data)//2}H", data)
        facts["deblock_changed_samples"] = sum(a != b for a, b in zip(unpack(native), unpack(nodeblock)))
        if not facts["deblock_changed_samples"]:
            raise ValueError(f"{name}: deblocking did not alter any native samples")
        artifacts[f"{name}.nodeblock.yuv"] = nodeblock
    record = dict(spec, encoder_command=[encoder_label] + command,
                  decoder_command=["dav1d"] + decoder_args,
                  trace_command=["dav1d-debug"] + debug_args,
                  source_sha256=sha(raw), evidence=facts,
                  files={key: {"sha256": sha(value), "bytes": len(value)} for key, value in artifacts.items()})
    if encoder_library:
        record["encoder_library_version"] = encoder_library
    if nodeblock_args:
        record["nodeblock_command"] = ["dav1d"] + nodeblock_args
    return record, artifacts


def array(values: list[int], byte: bool = False) -> str:
    return "[\n" + "".join("  " + ", ".join(f"b'\\x{v:02X}'" if byte else str(v) for v in values[i:i+16]) + ",\n"
                             for i in range(0, len(values), 16)) + "]"


def pack_samples(values: list[int], depth: int) -> bytes:
    """Pack runs >= 3; other samples remain in bounded literal packets."""
    packed = bytearray()
    width = 1 if depth == 8 else 2
    def run_length(start: int) -> int:
        end = start + 1
        while end < len(values) and end - start < 130 and values[end] == values[start]:
            end += 1
        return end - start
    def value(v: int) -> None:
        packed.extend(v.to_bytes(width, "little"))
    pos = 0
    while pos < len(values):
        count = run_length(pos)
        if count >= 3:
            packed.append(128 + count - 3)
            value(values[pos])
            pos += count
        else:
            start = pos
            while pos < len(values) and pos - start < 128 and run_length(pos) < 3:
                pos += 1
            packed.append(pos - start - 1)
            for sample in values[start:pos]:
                value(sample)
    return bytes(packed)


EXPAND_HELPER = '''
///|
/// RLE packets preserve literal native-depth samples exactly.
fn av1_mainline_expand(rows : Array[String], bit_depth : Int) -> Array[Int] {
  let bytes : Array[Int] = []
  for row in rows {
    let chars = row.to_array()
    for i in 0..<(chars.length() / 2) {
      let hi = chars[i * 2].to_int()
      let lo = chars[i * 2 + 1].to_int()
      let high = if hi >= 97 { hi - 87 } else { hi - 48 }
      let low = if lo >= 97 { lo - 87 } else { lo - 48 }
      bytes.push((high << 4) | low)
    }
  }
  let samples : Array[Int] = []
  let width = if bit_depth == 8 { 1 } else { 2 }
  let mut pos = 0
  while pos < bytes.length() {
    let control = bytes[pos]
    pos = pos + 1
    if control < 128 {
      for _ in 0..<(control + 1) {
        let sample = if width == 1 {
          bytes[pos]
        } else {
          bytes[pos] | (bytes[pos + 1] << 8)
        }
        samples.push(sample)
        pos = pos + width
      }
    } else {
      let sample = if width == 1 {
        bytes[pos]
      } else {
        bytes[pos] | (bytes[pos + 1] << 8)
      }
      pos = pos + width
      for _ in 0..<(control - 125) {
        samples.push(sample)
      }
    }
  }
  samples
}
'''


def emit_test(records: list[dict], artifacts: dict[str, bytes]) -> bytes:
    out = ["/// Generated by scripts/generate-av1-mainline-reference.py.\n"
           "/// Untouched libaom streams, compared sample-for-sample with dav1d.\n", EXPAND_HELPER]
    for record in records:
        name = record["name"]
        obu = artifacts[f"{name}.obu"]
        raw = artifacts[f"{name}.reference.yuv"]
        samples = list(raw) if record["bit_depth"] == 8 else list(struct.unpack(f"<{len(raw)//2}H", raw))
        out.append(f"\n///|\nlet mainline_{name}_obu : Array[Byte] = {array(list(obu), True)}\n")
        packed = pack_samples(samples, record["bit_depth"]).hex()
        rows = "[\n" + "".join(f'  "{packed[i:i+120]}",\n' for i in range(0, len(packed), 120)) + "]"
        out.append(f"\n///|\nlet mainline_{name}_reference : Array[Int] = av1_mainline_expand({rows}, {record['bit_depth']})\n")
        out.append(f'''\n///|
test "mainline {name}: independent native planes" {{
  let data = mainline_{name}_obu
  let sequence = av1_sequence_info(data).unwrap()
  let payloads = av1_obu_payloads(data, 6)
  assert_eq(payloads.length(), {record['frames']})
  let map = av1_frame_map()
  let reference = mainline_{name}_reference
  let mut offset = 0
  for payload in payloads {{
    let unit : Array[Byte] = [b'\\x32']
    let mut size = payload.length()
    while size >= 128 {{
      unit.push(((size & 127) | 128).to_byte())
      size = size >> 7
    }}
    unit.push(size.to_byte())
    for value in payload {{ unit.push(value) }}
    let frame = match av1_decode_frame_planes(unit, sequence~, map~, allow_monochrome=true) {{
      Some(value) => value
      None => fail("{name}: decode rejected")
    }}
    assert_eq((frame.width, frame.height, frame.bit_depth), ({record['width']}, {record['height']}, {record['bit_depth']}))
    for plane in 0..<3 {{
      let actual = av1_frame_crop(frame, plane)
      for i in 0..<actual.length() {{
        assert_eq((plane, i, actual[i]), (plane, i, reference[offset + i]))
      }}
      offset = offset + actual.length()
    }}
  }}
  assert_eq(offset, reference.length())
}}
''')
    return "".join(out).encode()


def moon_tokens(data: bytes) -> list[str]:
    """Permit moonfmt whitespace changes while checking every generated token."""
    tokens = re.findall(r'//[^\n]*|"(?:[^"\\]|\\.)*"|b\'(?:[^\'\\]|\\.)*\'|\S', data.decode())
    return [token for token in tokens if not token.startswith("//")]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aomenc")
    parser.add_argument("--dav1d")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--trace-dav1d", help="dav1d built with DEBUG_BLOCK_INFO=1")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--select", choices=("qmatrix", "intrabc", "deltalf", "segmentation", "wedge", "compound-globalwarp", "combined"), help="generate one group for decoder bring-up")
    parser.add_argument("--case", action="append", choices=[s["name"] for s in specs()], help="check/generate selected case(s); repeatable")
    parser.add_argument("--list", action="store_true", help="list fixture names without requiring tools")
    args = parser.parse_args()
    if args.list:
        print("\n".join(s["name"] for s in specs()))
        return
    tools = {key: resolve(getattr(args, key), key.upper(), default)
             for key, default in (("aomenc", "aomenc"), ("dav1d", "dav1d"),
                                  ("ffmpeg", "ffmpeg"), ("trace_dav1d", "dav1d-debug"))}
    selected = [s for s in specs() if (not args.select or s["tool"] == args.select)
                and (not args.case or s["name"] in args.case)]
    if not selected:
        parser.error("selection contains no cases")
    selected_names = {s["name"] for s in selected}
    manifest_path = OUT / "manifest.json"
    # Partial bring-up preserves earlier groups and regenerates their shared test.
    records = []
    artifacts = {}
    if (args.select or args.case) and manifest_path.exists():
        for old in json.loads(manifest_path.read_text())["fixtures"]:
            if old["name"] not in selected_names:
                records.append(old)
                for filename in old["files"]:
                    artifacts[filename] = (OUT / filename).read_bytes()
    with tempfile.TemporaryDirectory(prefix="pixelforge-mainline-") as temporary:
        scratch = Path(temporary)
        for spec in selected:
            record, files = encode(spec, tools, scratch)
            records.append(record)
            artifacts.update(files)
            print(f"verified {spec['name']}: {record['evidence'].keys()}", flush=True)
        versions = {
            "aomenc": re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", run([tools["aomenc"], "--help"], scratch).stdout)[0],
            "dav1d": run([tools["dav1d"], "--version"], scratch).stdout.strip(),
            "trace_dav1d": run([tools["trace_dav1d"], "--version"], scratch).stdout.strip(),
            "ffmpeg": run([tools["ffmpeg"], "-version"], scratch).stdout.splitlines()[0],
        }
    records.sort(key=lambda r: r["name"])
    tool_records = {}
    for key, path in tools.items():
        info = dict(version=versions[key], executable_sha256=sha(Path(path).read_bytes()))
        library = Path(path).parent / ("aom.dll" if key == "aomenc" else "dav1d.dll")
        if key != "ffmpeg" and library.exists():
            info["library"] = dict(name=library.name, sha256=sha(library.read_bytes()))
        tool_records[key] = info
    manifest = dict(format_version=1, sources=SOURCES, tools=tool_records, fixtures=records,
                    trace_patch_sha256=sha((OUT / "dav1d-debug.patch").read_bytes()))
    artifacts["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    outputs = {OUT / name: data for name, data in artifacts.items()}
    # moonfmt inserts optional trailing commas as well as whitespace. Format
    # the emitted source before comparing tokens so ordinary project formatting
    # preserves reproducibility without ignoring any reference-value tokens.
    outputs[TEST] = subprocess.run(
        [resolve(None, "MOONFMT", "moonfmt"), "-"],
        input=emit_test(records, artifacts), capture_output=True, check=True,
    ).stdout
    for path, data in outputs.items():
        if args.check:
            equal = path.exists() and (moon_tokens(path.read_bytes()) == moon_tokens(data) if path == TEST
                                       else path.read_bytes() == data)
            if not equal:
                raise SystemExit(f"CHECK FAILED: {path.relative_to(ROOT)} differs")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print(f"{'checked without repository writes' if args.check else 'generated'} "
          f"{len(selected)} selected fixtures; catalog: {len(records)}")


if __name__ == "__main__":
    main()
