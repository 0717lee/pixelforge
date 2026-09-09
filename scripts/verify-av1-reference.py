#!/usr/bin/env python3
"""Generate and externally verify small libaom AV1/AVIF reference fixtures.

The encoder output is copied byte-for-byte; no OBU rewriting is performed.  The
script is intentionally self-contained so fixtures can be regenerated with a
known ffmpeg/libaom build and checked with the independent dav1d decoder.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

W = H = 64
YUV_BYTES = W * H + 2 * (W // 2) * (H // 2)
AOM_PARAMS = (
    "enable-cdef=0:enable-restoration=0:enable-filter-intra=0:"
    "enable-intra-edge-filter=0:enable-angle-delta=0:"
    "enable-rect-partitions=0:enable-1to4-partitions=0:enable-ab-partitions=0:"
    "enable-smooth-intra=0:enable-paeth-intra=0:enable-palette=0:"
    "enable-flip-idtx=0:enable-tx64=1:enable-tx-size-search=0:use-intra-default-tx-only=1:"
    "min-partition-size=64:max-partition-size=64"
)

CASES = (
    ("dc_zero_q30", (128, 128, 128), 30),
    ("dc_y_low_q10", (64, 128, 128), 10),
    ("dc_y_high_q50", (192, 128, 128), 50),
    ("dc_u_low_q10", (128, 64, 128), 10),
    ("dc_v_high_q30", (128, 128, 192), 30),
    ("dc_yuv_mixed_q50", (96, 160, 64), 50),
)


def run(cmd: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, check=True, text=True, capture_output=capture)
    except subprocess.CalledProcessError as exc:
        if exc.stderr:
            print(exc.stderr)
        raise


def plane_bytes(values: tuple[int, int, int]) -> bytes:
    y, u, v = values
    return bytes([y]) * (W * H) + bytes([u]) * 1024 + bytes([v]) * 1024


def digest_plane(data: bytes, start: int, size: int) -> dict[str, object]:
    p = data[start : start + size]
    return {
        "sha256": hashlib.sha256(p).hexdigest(),
        "unique": sorted(set(p)),
        "first64_hex": p[:64].hex(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("tests/fixtures/av1"))
    ap.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    ap.add_argument("--aomenc", default=shutil.which("aomenc") or "aomenc")
    args = ap.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="av1-fixtures-") as td:
        tmp = Path(td)
        for name, vals, crf in CASES:
            src = tmp / f"{name}.yuv"
            obu = out / f"{name}.obu"
            avif = out / f"{name}.avif"
            dec = tmp / f"{name}.decoded.yuv"
            dec_avif = tmp / f"{name}.avif.decoded.yuv"
            rgba = tmp / f"{name}.decoded.rgba"
            src.write_bytes(plane_bytes(vals))
            # aomenc exposes tx-size-search; ffmpeg's wrapper does not.  This
            # forces frame tx_mode=ONLY_LARGEST (1), yielding a single 64x64
            # luma transform and 32x32 chroma transforms.
            aom_args = [
                args.aomenc, "--allintra", "--obu", "--width=64", "--height=64",
                "--bit-depth=8", "--input-bit-depth=8", "--fps=1/1", "--limit=1",
                "--cpu-used=0", "--threads=1", "--end-usage=q", f"--cq-level={crf}",
                "--enable-cdef=0", "--enable-restoration=0", "--enable-filter-intra=0",
                "--enable-intra-edge-filter=0", "--enable-angle-delta=0",
                "--enable-rect-partitions=0", "--enable-1to4-partitions=0", "--enable-ab-partitions=0",
                "--enable-smooth-intra=0", "--enable-paeth-intra=0", "--enable-palette=0",
                "--enable-flip-idtx=0", "--enable-tx64=1", "--enable-tx-size-search=0",
                "--use-intra-default-tx-only=1", "--min-partition-size=64", "--max-partition-size=64",
                "-o", str(obu), str(src),
            ]
            run(aom_args, capture=True)
            run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "obu", "-i", str(obu),
                 "-c", "copy", "-frames:v", "1", "-f", "avif", str(avif)])
            # Decode with ffmpeg's libdav1d decoder (independent of libaom).
            run([
                args.ffmpeg, "-hide_banner", "-loglevel", "error", "-c:v", "libdav1d",
                "-i", str(obu), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p", str(dec),
            ])
            decoded = dec.read_bytes()
            if len(decoded) != YUV_BYTES:
                raise RuntimeError(f"{name}: decoded {len(decoded)} bytes, expected {YUV_BYTES}")
            run([
                args.ffmpeg, "-hide_banner", "-loglevel", "error", "-c:v", "libdav1d",
                "-i", str(avif), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p", str(dec_avif),
            ])
            if dec_avif.read_bytes() != decoded:
                raise RuntimeError(f"{name}: AVIF and raw OBU decode differ")
            run([
                args.ffmpeg, "-hide_banner", "-loglevel", "error", "-c:v", "libdav1d",
                "-i", str(obu), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", str(rgba),
            ])
            rgba_bytes = rgba.read_bytes()
            # trace_headers gives a reproducible qidx and sequence filter flags.
            traced = subprocess.run(
                [args.ffmpeg, "-hide_banner", "-i", str(obu), "-c", "copy",
                 "-bsf:v", "trace_headers", "-f", "null", "NUL"],
                text=True, capture_output=True,
            )
            trace = traced.stdout + traced.stderr
            q = re.search(r"base_q_idx\s+[^=]+=\s*(\d+)", trace)
            tx_mode = re.search(r"tx_mode\s+[^=]+=\s*(\d+)", trace)
            filter_flags = {
                key: int(m.group(1))
                for key in ("enable_cdef", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter")
                if (m := re.search(rf"{key}\s+[^=]+=\s*(\d+)", trace))
            }
            expected_flags = {"enable_cdef", "enable_restoration", "enable_filter_intra", "enable_intra_edge_filter"}
            if traced.returncode or q is None or tx_mode is None or int(tx_mode.group(1)) != 1 or set(filter_flags) != expected_flags or any(v != 0 for v in filter_flags.values()):
                raise RuntimeError(f"{name}: trace_headers validation failed\n{trace}")
            records.append({
                "name": name, "input_yuv": list(vals), "crf": crf,
                "qidx": int(q.group(1)) if q else None,
                "tx_mode": int(tx_mode.group(1)) if tx_mode else None,
                "obu_bytes": len(obu.read_bytes()),
                "obu_sha256": hashlib.sha256(obu.read_bytes()).hexdigest(),
                "obu_hex": obu.read_bytes().hex(),
                "avif_bytes": len(avif.read_bytes()),
                "avif_sha256": hashlib.sha256(avif.read_bytes()).hexdigest(),
                "decoded": {
                    "y": digest_plane(decoded, 0, 4096),
                    "u": digest_plane(decoded, 4096, 1024),
                    "v": digest_plane(decoded, 5120, 1024),
                    "rgba_sha256": hashlib.sha256(rgba_bytes).hexdigest(),
                    "rgba_first64_hex": rgba_bytes[:64].hex(),
                },
                "trace_flags": filter_flags,
            })
    manifest = {
        "format": "AV1 low-overhead OBU and AVIF",
        "dimensions": [W, H], "pixel_format": "yuv420p", "bit_depth": 8,
        "encoder": "aomenc libaom usage=allintra (tx-size-search=0)",
        "generation_command": "python scripts/verify-av1-reference.py --out tests/fixtures/av1",
        "external_decoder": "ffmpeg libdav1d",
        "aom_params": AOM_PARAMS, "fixtures": records,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"verified {len(records)} fixtures in {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
