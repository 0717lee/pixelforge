#!/usr/bin/env python3
"""Generate the AV1 general (non reduced-still) frame-header fixtures.

Phase D of the AVIF decoder needs real multi-frame bitstreams: every earlier
fixture is a reduced still picture, which hides the whole inter-frame grammar
(show_existing_frame, frame_type, order_hint, the reference list,
interpolation/motion-mode signalling, reference_select, allow_warped_motion and
global_motion).

Each fixture is one untouched libaom encode of deterministic input.  The
script records the encoder command line, the FFmpeg ``trace_headers``
transcript, and dav1d's native planes.  The transcript is the syntax oracle:
the declared expectations in FIXTURES are checked against it, so a parser that
silently re-syncs onto a different bit offset fails here rather than in the
MoonBit suite.

Usage:
    python scripts/generate-av1-inter-reference.py
    python scripts/generate-av1-inter-reference.py --check
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE_DIR = os.path.join(ROOT, "tests", "fixtures", "av1-inter")

AOMENC = r"D:\ProgramData\anaconda3\Library\bin\aomenc.EXE"
DAV1D = r"D:\ProgramData\anaconda3\Library\bin\dav1d.EXE"
FFMPEG = os.path.join(
    os.path.expanduser("~"),
    "AppData",
    "Local",
    "Microsoft",
    "WinGet",
    "Packages",
    "Gyan.FFmpeg.Shared_Microsoft.Winget.Source_8wekyb3d8bbwe",
    "ffmpeg-9.0.1-full_build-shared",
    "bin",
    "ffmpeg.exe",
)

WIDTH, HEIGHT, FRAMES = 64, 64, 2

# Inter-tool switches for the "everything off" fixture.  libaom segfaults past
# two frames in the anaconda build, so every fixture here is key + one inter
# frame; the simplest possible block syntax keeps the first inter milestone
# debuggable.
MINIMAL_FLAGS = [
    "--error-resilient=0",
    "--enable-dual-filter=0",
    "--enable-order-hint=0",
    "--enable-ref-frame-mvs=0",
    "--enable-warped-motion=0",
    "--enable-obmc=0",
    "--enable-global-motion=0",
    "--enable-masked-comp=0",
    "--enable-dist-wtd-comp=0",
    "--enable-diff-wtd-comp=0",
    "--enable-interintra-comp=0",
    "--enable-interinter-wedge=0",
    "--enable-interintra-wedge=0",
    "--enable-onesided-comp=0",
    "--enable-tx64=0",
    "--enable-intrabc=0",
    "--enable-palette=0",
]

# Frame-header facts taken from the FFmpeg transcript, keyed by the transcript's
# own field names.  `None` means "this field is not present in the transcript".
GENERAL_SEQUENCE = {
    "seq_profile": 0,
    "still_picture": 0,
    "reduced_still_picture_header": 0,
    "timing_info_present_flag": 0,
    "initial_display_delay_present_flag": 0,
    "operating_points_cnt_minus_1": 0,
    "frame_id_numbers_present_flag": 0,
    "use_128x128_superblock": 1,
    "enable_filter_intra": 1,
    "enable_intra_edge_filter": 1,
    "enable_interintra_compound": 1,
    "enable_masked_compound": 1,
    "enable_warped_motion": 1,
    "enable_dual_filter": 1,
    "enable_order_hint": 1,
    "enable_jnt_comp": 1,
    "enable_ref_frame_mvs": 1,
    "seq_choose_screen_content_tools": 1,
    "seq_choose_integer_mv": 1,
    "order_hint_bits_minus_1": 6,
    "enable_superres": 0,
    "enable_cdef": 1,
    "enable_restoration": 1,
    "high_bitdepth": 0,
    "mono_chrome": 0,
    "separate_uv_delta_q": 0,
    "film_grain_params_present": 0,
}

FIXTURES = [
    {
        "name": "general_inter_64x64",
        "flags": [],
        # Frame 0 is a key frame behind a general header; frame 1 is inter.
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "frame_size_override_flag": 0,
                "order_hint": 0,
                "render_and_frame_size_different": 0,
                "disable_frame_end_update_cdf": 0,
                "segmentation_enabled": 0,
                "delta_q_present": 0,
                "using_qmatrix": 0,
                "reduced_tx_set": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "frame_size_override_flag": 0,
                "order_hint": 1,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "frame_refs_short_signaling": 0,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[1]": 0,
                "ref_frame_idx[2]": 0,
                "ref_frame_idx[3]": 0,
                "ref_frame_idx[4]": 0,
                "ref_frame_idx[5]": 0,
                "ref_frame_idx[6]": 0,
                "render_and_frame_size_different": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 1,
                "use_ref_frame_mvs": 1,
                "disable_frame_end_update_cdf": 0,
                "segmentation_enabled": 0,
                "delta_q_present": 0,
                "using_qmatrix": 0,
                "reference_select": 0,
                "allow_warped_motion": 1,
                "reduced_tx_set": 0,
                "is_global[1]": 0,
                "is_global[4]": 0,
                "is_global[7]": 0,
            },
        ],
        "sequence_expectations": GENERAL_SEQUENCE,
        "decode_frames": 1,
    },
    {
        "name": "inter_minimal_64x64",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "disable_frame_end_update_cdf": 0,
                "reference_select": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # Two fixtures whose inter tree stays coarse on purpose: the sub-8-tap and
    # entropy work is easiest to settle where aom does not answer a whole-frame
    # motion with a thicket of 4x16 strips (see inter_minimal_64x64, which does).
    {
        "name": "inter_still_64x64",
        "input": "still",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                # A repeated frame needs no switchable filter, so this fixture
                # also covers the fixed `interpolation_filter` path.
                "is_filter_switchable": 0,
                "interpolation_filter": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
                # Both levels zero means loop_filter_level[2..3] are not even
                # signalled (see AV1 6.8.2), so deblocking is a no-op here.
                "loop_filter_level[0]": 0,
                "loop_filter_level[1]": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 0,
                "cdef_bits": 0,
                "lr_type[0]": 0,
                "lr_type[1]": 0,
                "lr_type[2]": 0,
                "reduced_tx_set": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        "name": "inter_shift_64x64",
        "input": "shift",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                # The fractional translation makes aom switch the interpolation
                # filter on, so the per-block filter symbol is exercised.
                "is_filter_switchable": 1,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
                # Chroma filtering is live in this stream (level[1] is 4), which
                # is the first fixture that needs the inter loop-filter deltas.
                "loop_filter_level[0]": 0,
                "loop_filter_level[1]": 4,
                "loop_filter_level[2]": 0,
                "loop_filter_level[3]": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 0,
                "cdef_bits": 0,
                "lr_type[0]": 0,
                "lr_type[1]": 0,
                "lr_type[2]": 0,
                "reduced_tx_set": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # A 64x16 frame is the smallest stream found so far that reproduces the
    # inter right-edge defect: the frame decodes (the tile budget fits), the key
    # frame is exact, and only the last three luma columns and the last chroma
    # column are wrong. Keep this fixture even while the pixels are known-bad:
    # it is the reproducer for the empty motion-vector-stack bug.
    {
        "name": "inter_edge_64x16",
        "input": "strip",
        "width": 64,
        "height": 16,
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
]


def encode_input(path: str, kind: str = "ramp", width: int = 64, height: int = 64) -> None:
    """Write the deterministic 2-frame 4:2:0 source selected by ``kind``.

    A slowly translating ramp gives the encoder a clean single-reference motion
    field, which is what the first inter milestone needs; the chroma planes
    shift per frame so chroma motion compensation is exercised too.

    The two additional sources exist because aom's partition search on ``ramp``
    descends into narrow 4x16 strips, which is the hardest possible tree to
    debug entropy against.  ``still`` (frame 1 repeats frame 0 exactly) and
    ``shift`` (a true half-pixel translation of a band-limited sinusoid, so no
    discontinuity invites fine splits) keep the inter tree coarse; ``shift``
    additionally forces a fractional motion vector, which is what exercises the
    8-tap interpolation kernel rather than a plain copy.
    """
    cw, ch = width // 2, height // 2
    header = "YUV4MPEG2 W%d H%d F1:1 Ip A1:1 C420mpeg2\n" % (width, height)
    frames = []
    for n in range(FRAMES):
        if kind == "strip":
            # The sawtooth of ``ramp`` in strict raster order for every plane.
            # Byte layout matters: this is the source that reproduces the
            # right-edge inter defect on a 64x16 frame, where the ramp's own
            # chroma layout does not.
            luma = bytes(
                max(0, min(255, 40 + ((x + n * 3) % 32)))
                for y in range(height)
                for x in range(width)
            )
            cb = bytes((128 + (y % 5) + n) & 0xFF for y in range(ch) for x in range(cw))
            cr = bytes((120 + (x % 7) - n) & 0xFF for y in range(ch) for x in range(cw))
        elif kind == "still":
            luma = bytes(
                max(0, min(255, 96 + 3 * (y % 16) + (x % 8)))
                for y in range(height)
                for x in range(width)
            )
            cb = bytes([(128 + (y % 6)) & 0xFF for _ in range(cw) for y in range(ch)])
            cr = bytes([(120 + (x % 6)) & 0xFF for y in range(ch) for x in range(cw)])
        elif kind == "shift":
            # Frame 1 is sampled 2.5 luma pixels further along a small-amplitude
            # horizontal sinusoid, so the true motion is fractional and uniform
            # over the whole frame and no discontinuity invites fine splits.
            #
            # The amplitude and periods are not cosmetic: this libaom build
            # segfaults at encoder teardown on higher-contrast translations
            # (a 44-count, period-48 wave of the same shape crashes), so the
            # source stays deliberately gentle.
            def smooth(
                x: float, y: float, off: float, period: float, vertical: float
            ) -> int:
                return max(
                    0,
                    min(
                        255,
                        int(
                            round(
                                128.0
                                + 8.0 * math.sin(2.0 * math.pi * (x - off) / period)
                                + vertical * math.sin(2.0 * math.pi * y / 32.0)
                            )
                        ),
                    ),
                )

            off = 2.5 * n
            luma = bytes(
                smooth(float(x), float(y), off, 64.0, 10.0)
                for y in range(height)
                for x in range(width)
            )
            # Chroma samples the same shape half as often horizontally, and keeps
            # the identical displacement in chroma units, i.e. five luma pixels.
            cb = bytes(
                smooth(2.0 * x, float(y), off, 128.0, 2.0)
                for y in range(ch)
                for x in range(cw)
            )
            cr = bytes(
                smooth(2.0 * x, float(y), off, 128.0, 2.0)
                for y in range(ch)
                for x in range(cw)
            )
        else:
            luma = bytes(
                max(0, min(255, 40 + ((x + n * 3) % 32)))
                for _ in range(height)
                for x in range(width)
            )
            cb = bytes([(128 + (y % 5) + n) & 0xFF for _ in range(cw) for y in range(ch)])
            cr = bytes([(120 + (x % 7) - n) & 0xFF for y in range(ch) for x in range(cw)])
        assert len(luma) == width * height
        assert len(cb) == cw * ch and len(cr) == cw * ch
        frames.append(luma + cb + cr)
    with open(path, "wb") as fh:
        fh.write(header.encode())
        for frame in frames:
            fh.write(b"FRAME\n" + frame)


def trace_fields(obu: str, committed: str) -> list[dict[str, int]]:
    """Parse FFmpeg's trace_headers output into one field dict per frame.

    The transcript is written to `committed` (the shipped `.trace.txt`) from the
    freshly encoded `obu`, so checking never rewrites evidence from a stale file.
    """
    proc = subprocess.run(
        [
            FFMPEG,
            "-hide_banner",
            "-bsf:v",
            "trace_headers",
            "-i",
            obu,
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    text = re.sub(r"\[trace_headers @ [0-9a-f]+\] ", "", proc.stdout + proc.stderr)
    # FFmpeg appends its own muxing summary, which carries a heap address and a
    # speed figure.  Neither is evidence, and leaving them in rewrote the
    # committed transcripts on every run.
    cut = text.find("Output #")
    if cut >= 0:
        text = text[:cut].rstrip() + "\n"
    with open(committed, "w", encoding="utf-8") as fh:
        fh.write(text)
    frames: list[dict[str, int]] = []
    current: dict[str, int] | None = None
    for line in text.splitlines():
        if line.startswith("Frame Header"):
            current = {}
            frames.append(current)
            continue
        if line.startswith("Tile Group") or line.startswith("Sequence Header"):
            current = None
            continue
        if current is None:
            continue
        m = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
        if m:
            current[m.group(1)] = int(m.group(2))
    return frames


def sequence_fields(trace_path: str) -> dict[str, int]:
    """Re-read the transcript for the sequence header block."""
    with open(trace_path, encoding="utf-8") as fh:
        text = fh.read()
    fields: dict[str, int] = {}
    inside = False
    for line in text.splitlines():
        if line.startswith("Sequence Header"):
            inside = True
            continue
        if inside and line.startswith("Frame Header"):
            break
        if not inside:
            continue
        m = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
        if m:
            fields[m.group(1)] = int(m.group(2))
    return fields


def check_expectations(label: str, fields: dict[str, int], expected: dict[str, int]) -> None:
    for key, value in expected.items():
        if key not in fields:
            raise SystemExit("FAIL %s: transcript has no %s" % (label, key))
        if fields[key] != value:
            raise SystemExit(
                "FAIL %s: %s is %d, expected %d" % (label, key, fields[key], value)
            )


def run(fixture: dict, check: bool) -> dict:
    """Encode one fixture and verify it against the declared evidence.

    In ``--check`` mode the freshly derived bytes are compared against what is
    already committed instead of being rewritten, so a compiler or tool change
    that moves any bit fails loudly here rather than in the MoonBit suite.
    """
    name = fixture["name"]
    width = fixture.get("width", WIDTH)
    height = fixture.get("height", HEIGHT)
    os.makedirs(FIXTURE_DIR, exist_ok=True)
    y4m = os.path.join(FIXTURE_DIR, name + ".input.y4m")
    obu = os.path.join(FIXTURE_DIR, name + ".obu")
    ref = os.path.join(FIXTURE_DIR, name + ".reference.yuv")
    if check:
        for path in (obu, ref):
            if not os.path.exists(path):
                raise SystemExit("FAIL: %s is missing; generate it first" % path)
        committed_obu = open(obu, "rb").read()
        committed_ref = open(ref, "rb").read()
    scratch = os.path.join(FIXTURE_DIR, name + ".check.obu")
    encode_input(y4m, fixture.get("input", "ramp"), width, height)
    cmd = [
        AOMENC,
        "--codec=av1",
        "--obu",
        "--i420",
        "--width=%d" % width,
        "--height=%d" % height,
        "--bit-depth=8",
        "--fps=1/1",
        "--limit=%d" % FRAMES,
        "--lag-in-frames=0",
        "--threads=1",
        "--cpu-used=0",
        "--end-usage=q",
        "--cq-level=32",
        "--tile-columns=0",
        "--tile-rows=0",
        "--debug",
        "--disable-warning-prompt",
    ] + fixture["flags"] + ["-o", scratch, y4m]
    proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if proc.returncode != 0:
        raise SystemExit("aomenc failed for %s:\n%s" % (name, proc.stdout[-2000:]))
    trace = os.path.join(FIXTURE_DIR, name + ".trace.txt")
    frames = trace_fields(scratch, trace)
    if len(frames) != FRAMES:
        raise SystemExit("%s: expected %d frame headers, traced %d" % (name, FRAMES, len(frames)))
    for index, expected in enumerate(fixture["frames"]):
        check_expectations("%s frame %d" % (name, index), frames[index], expected)
    if fixture["sequence_expectations"] is not None:
        check_expectations(
            "%s sequence" % name,
            sequence_fields(trace),
            fixture["sequence_expectations"],
        )
    decoded = os.path.join(FIXTURE_DIR, name + ".check.yuv")
    proc = subprocess.run(
        [DAV1D, "-q", "-i", scratch, "-o", decoded],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if proc.returncode != 0:
        raise SystemExit("dav1d failed for %s:\n%s" % (name, proc.stdout + proc.stderr))
    plane = width * height + 2 * (width // 2) * (height // 2)
    fresh_obu = open(scratch, "rb").read()
    data = open(decoded, "rb").read()
    for path in (scratch, decoded):
        os.remove(path)
    if len(data) != plane * FRAMES:
        raise SystemExit("%s: dav1d gave %d bytes, expected %d" % (name, len(data), plane * FRAMES))
    if check:
        if fresh_obu != committed_obu:
            raise SystemExit(
                "FAIL %s: the re-encoded OBU differs from the committed one (%d vs %d bytes)"
                % (name, len(fresh_obu), len(committed_obu))
            )
        if data != committed_ref:
            raise SystemExit("FAIL %s: dav1d's planes differ from the committed ones" % name)
    else:
        for path, blob in ((obu, fresh_obu), (ref, data)):
            with open(path, "wb") as fh:
                fh.write(blob)
    return {
        "name": name,
        "command": " ".join(cmd),
        "obu_sha256": hashlib.sha256(fresh_obu).hexdigest(),
        "reference_sha256": hashlib.sha256(data).hexdigest(),
        "frame_planes": [data[i * plane : (i + 1) * plane] for i in range(FRAMES)],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    built = [run(f, args.check) for f in FIXTURES]
    if args.check:
        print("verified %d fixtures against their committed evidence" % len(built))
        return
    with open(os.path.join(FIXTURE_DIR, "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(
            {
                "encoder": AOMENC,
                "oracle_trace": FFMPEG,
                "reference_decoder": DAV1D,
                "source_dimensions": [WIDTH, HEIGHT],
                "frames_per_fixture": FRAMES,
                "fixtures": [
                    {k: v for k, v in item.items() if k != "frame_planes"}
                    for item in built
                ],
                "notes": "libaom in this build crashes past two frames, so each fixture is one key frame plus one inter frame.",
            },
            fh,
            indent=2,
            sort_keys=True,
        )
    print("generated %d fixtures; run scripts/emit-av1-inter-test.py to refresh the test" % len(built))


if __name__ == "__main__":
    main()
