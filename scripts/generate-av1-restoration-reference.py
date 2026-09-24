#!/usr/bin/env python3
"""Bounded AV1 loop-restoration header reference, no MoonBit builds.

One untouched libaom encode with active Wiener restoration on every plane:
97x65 10-bit 4:2:0, SB64, superres denominator 12, base_q_idx 160, CDEF
active. The bounded stock superres corpus encodes every frame with
--enable-restoration=0, so this fixture exists to lock the real active-LR
frame-header path: three lr_type codes 10 (Wiener), lr_unit_shift 1 (unit
128), lr_uv_shift 0 (chroma unshifted), with tx_mode following at the exact
bit position. The trace's tx_mode ordinal uses FFmpeg's AV1TXMode numbering
(ONLY_4X4=0, TX_MODE_LARGEST=1, TX_MODE_SELECT=2), so ordinal 1 means
TX_MODE_LARGEST and the expected tx_mode_select is false. The synthetic
white-box streams in av1_restoration_header_
wbtest.mbt model the grammar bit-by-bit; this encoder-produced stream proves
the parser consumes an active-LR header without drift.

The noise input is deterministic (random.Random(20260917).getrandbits(10)),
so the whole chain regenerates byte-identically. --check re-derives the
input, re-encodes, re-extracts the FFmpeg trace_headers evidence and
re-renders the canonical white-box test under _refs/.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import random
import re
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]

NAME = "noise_color_10bit_d12_97x65_wiener_u128"
WIDTH, HEIGHT, DEPTH, DENOM = 97, 65, 10, 12
CODED_WIDTH = (WIDTH * 8 + DENOM // 2) // DENOM
SEED = 20260917


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    assert spec is not None and spec.loader is not None
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


fi = module("restoration_frame_helpers", "generate-av1-filter-intra-reference.py")
run, sha256, trace_value = fi.run, fi.sha256, fi.trace_value


def noise_y4m() -> bytes:
    """Deterministic full-range 10-bit 4:2:0 noise; plane order Y, U, V."""
    rng = random.Random(SEED)
    header = f"YUV4MPEG2 W{WIDTH} H{HEIGHT} F1:1 Ip A1:1 C420p10 XCOLORRANGE=FULL\nFRAME\n".encode()
    chroma = ((WIDTH + 1) // 2) * ((HEIGHT + 1) // 2)
    planes = (WIDTH * HEIGHT, chroma, chroma)
    data = bytearray()
    for count in planes:
        for _ in range(count):
            data += rng.getrandbits(10).to_bytes(2, "little")
    return header + bytes(data)


def encoder_command(aomenc: str, output: Path, input_path: Path) -> list[str]:
    """The bounded stock d12 command verbatim with --enable-restoration=1."""
    return [
        aomenc,
        "--superres-mode=1",
        f"--superres-denominator={DENOM}",
        f"--superres-kf-denominator={DENOM}",
        "--enable-diagonal-intra=0",
        "--debug",
        "--disable-warning-prompt",
        "--allintra",
        "--obu",
        "--i420",
        f"--width={WIDTH}",
        f"--height={HEIGHT}",
        "--profile=0",
        f"--bit-depth={DEPTH}",
        f"--input-bit-depth={DEPTH}",
        "--fps=1/1",
        "--limit=1",
        "--cpu-used=0",
        "--threads=1",
        "--end-usage=q",
        "--cq-level=40",
        "--sb-size=64",
        "--tile-columns=0",
        "--tile-rows=0",
        "--aq-mode=0",
        "--deltaq-mode=0",
        "--enable-chroma-deltaq=0",
        "--enable-qm=0",
        "--enable-cdef=1",
        "--enable-restoration=1",
        "--enable-filter-intra=0",
        "--enable-intra-edge-filter=0",
        "--enable-angle-delta=0",
        "--enable-rect-partitions=0",
        "--enable-1to4-partitions=0",
        "--enable-ab-partitions=0",
        "--enable-smooth-intra=1",
        "--enable-paeth-intra=1",
        "--enable-palette=0",
        "--enable-flip-idtx=0",
        "--enable-tx-size-search=0",
        "--use-intra-default-tx-only=1",
        "--min-partition-size=8",
        "--max-partition-size=16",
        "--enable-directional-intra=1",
        "--enable-cfl-intra=0",
        "--enable-intrabc=0",
        "--loopfilter-control=1",
        "-o",
        str(output),
        str(input_path),
    ]


def trace_array(trace: str, name: str) -> list[int]:
    return [int(value) for value in re.findall(rf"{re.escape(name)}\[\d+\]\s+[^=\n]+=\s*(\d+)", trace)]


def header_evidence(trace: str) -> dict[str, object]:
    fields = {
        name: trace_value(trace, name)
        for name in (
            "seq_profile",
            "still_picture",
            "reduced_still_picture_header",
            "max_frame_width_minus_1",
            "max_frame_height_minus_1",
            "use_128x128_superblock",
            "enable_superres",
            "enable_cdef",
            "enable_restoration",
            "high_bitdepth",
            "mono_chrome",
            "color_range",
            "allow_screen_content_tools",
            "use_superres",
            "coded_denom",
            "base_q_idx",
            "tile_cols_log2",
            "tile_rows_log2",
            "uniform_tile_spacing_flag",
            "disable_cdf_update",
            "cdef_damping_minus_3",
            "cdef_bits",
            "lr_unit_shift",
            "lr_uv_shift",
            "tx_mode",
            "reduced_tx_set",
        )
    }
    lr_types = trace_array(trace, "lr_type")
    if fields["seq_profile"] != 0 or fields["still_picture"] != 1 or fields["reduced_still_picture_header"] != 1:
        raise ValueError(f"unexpected sequence header shape: {fields}")
    if fields["max_frame_width_minus_1"] + 1 != WIDTH or fields["max_frame_height_minus_1"] + 1 != HEIGHT:
        raise ValueError("unexpected frame dimensions")
    if fields["use_128x128_superblock"] or fields["mono_chrome"] or not fields["high_bitdepth"] or fields["color_range"] != 1:
        raise ValueError("unexpected format: expected SB64 full-range 10-bit color")
    for tool in ("enable_superres", "enable_cdef", "enable_restoration"):
        if fields[tool] != 1:
            raise ValueError(f"{tool} unexpectedly disabled")
    if fields["use_superres"] != 1 or fields["coded_denom"] + 9 != DENOM:
        raise ValueError("unexpected active superres syntax")
    if fields["base_q_idx"] != 160:
        raise ValueError("unexpected base_q_idx; the fixture pins q index 160")
    if fields["tile_cols_log2"] or fields["tile_rows_log2"] or fields["uniform_tile_spacing_flag"] != 1:
        raise ValueError("unexpected tile geometry")
    if fields["allow_screen_content_tools"] or fields["disable_cdf_update"]:
        raise ValueError("unexpected screen-content/cdf-update syntax")
    if fields["cdef_damping_minus_3"] not in range(0, 4):
        raise ValueError("unexpected CDEF damping syntax")
    # CDEF strength pairs are encoder RD choices on the noise content and
    # shift the LR bit position with their count; the generated test locks the
    # parsed values against this trace, so only well-formedness is required.
    # Secondary strengths follow the repo's established parse-time remap of
    # AOM cdef.c (`sec += (sec == 3)`): the coded value 3 becomes 4.
    cdef = {
        "damping": fields["cdef_damping_minus_3"] + 3,
        "bits": fields["cdef_bits"],
        "y_primary": trace_array(trace, "cdef_y_pri_strength"),
        "y_secondary": [4 if value == 3 else value for value in trace_array(trace, "cdef_y_sec_strength")],
        "uv_primary": trace_array(trace, "cdef_uv_pri_strength"),
        "uv_secondary": [4 if value == 3 else value for value in trace_array(trace, "cdef_uv_sec_strength")],
    }
    if fields["cdef_bits"] not in range(0, 4):
        raise ValueError("unexpected CDEF parameter syntax")
    for name in ("y_primary", "y_secondary", "uv_primary", "uv_secondary"):
        if len(cdef[name]) != 1 << fields["cdef_bits"]:
            raise ValueError(f"CDEF {name} count does not match cdef_bits")
    if lr_types != [2, 2, 2]:
        raise ValueError(f"the fixture must carry active Wiener on all planes: {lr_types}")
    if fields["lr_unit_shift"] != 1 or fields["lr_uv_shift"] != 0:
        raise ValueError("unexpected restoration unit syntax; expected unit 128 with chroma unshifted")
    # FFmpeg's AV1TXMode ordinals are ONLY_4X4=0, TX_MODE_LARGEST=1,
    # TX_MODE_SELECT=2: its increment(tx_mode, LARGEST, SELECT) maps the raw
    # header bit 0 to LARGEST and 1 to SELECT, matching AOM read_tx_mode
    # (bit 1 selects). Ordinal 1 is therefore LARGEST, not SELECT.
    if fields["tx_mode"] not in (0, 1, 2):
        raise ValueError("unexpected tx_mode ordinal")
    tx_mode_select = fields["tx_mode"] == 2
    if fields["reduced_tx_set"] != 0:
        raise ValueError("unexpected reduced_tx_set; the fixture pins it off")
    available = (CODED_WIDTH + 7) // 8 * 8
    sb_cols = (available + 63) // 64
    sb_rows = ((HEIGHT + 7) // 8 * 8 + 63) // 64
    return {
        "headers": fields,
        "lr_types": lr_types,
        "lr_unit_size": 64 << fields["lr_unit_shift"],
        "lr_uv_shift": fields["lr_uv_shift"],
        "tx_mode_select": tx_mode_select,
        "cdef": {"damping": fields["cdef_damping_minus_3"] + 3, "bits": fields["cdef_bits"], **cdef},
        "coded_visible_width": CODED_WIDTH,
        "tile_col_starts_sb": [0, sb_cols],
        "tile_row_starts_sb": [0, sb_rows],
        "dimensions_evidence": "decoded reduced-still maximum dimensions, active superres flag/denominator and FFmpeg trace_headers restoration fields; coded width and superblock counts from the normative formulas",
    }


def byte_rows(data: bytes) -> str:
    return "\n".join(
        "    " + ", ".join(f"b'\\x{value:02X}'" for value in data[i : i + 12]) + ","
        for i in range(0, len(data), 12)
    )


def generated_test(record: dict[str, object], directory: Path) -> str:
    stream = (directory / record["obu_file"]).read_bytes()
    evidence = record["evidence"]
    headers = evidence["headers"]
    text = f"""///|
/// Generated by scripts/generate-av1-restoration-reference.py.
/// One untouched libaom encode with active Wiener loop restoration on every
/// plane, from deterministic 10-bit noise input (seed {SEED}). The bounded
/// stock superres corpus encodes with --enable-restoration=0, so this fixture
/// locks the real active-LR header path the synthetic white-box streams only
/// model bit-by-bit. Every expectation below is the unmodified FFmpeg
/// trace_headers evidence of the committed OBU.

///|
test "external restoration frame {record["name"]}" {{
  let stream : Array[Byte] = [
{byte_rows(stream)}
  ]
  let seq = av1_sequence_info(stream).unwrap()
  assert_eq(seq.profile, {headers["seq_profile"]})
  assert_eq(seq.reduced_still_picture_header, true)
  assert_eq((seq.width, seq.height), ({WIDTH}, {HEIGHT}))
  assert_eq(seq.bit_depth, {DEPTH})
  assert_eq(seq.monochrome, false)
  assert_eq((seq.subsampling_x, seq.subsampling_y), (true, true))
  assert_eq(seq.use_128x128_superblock, false)
  assert_eq((seq.enable_superres, seq.enable_cdef, seq.enable_restoration), (true, true, true))
  assert_eq(seq.full_range, true)
  let frames = av1_obu_payloads(stream, 6)
  assert_eq(frames.length(), 1)
  let frame = av1_parse_stage1_frame(frames[0], seq,
    allow_monochrome=true, allow_highbd=true).unwrap()
  assert_eq((frame.frame_width, frame.upscaled_width, frame.superres_denom), ({evidence["coded_visible_width"]}, {WIDTH}, {DENOM}))
  assert_eq(frame.base_q_idx, {headers["base_q_idx"]})
  assert_eq(frame.disable_cdf_update, false)
  assert_eq(frame.allow_screen_content_tools, false)
  assert_eq(frame.coded_lossless, false)
  assert_eq((frame.tile_cols, frame.tile_rows), (1, 1))
  assert_eq(frame.tile_col_starts_sb, {evidence["tile_col_starts_sb"]})
  assert_eq(frame.tile_row_starts_sb, {evidence["tile_row_starts_sb"]})
  // tx_mode_select follows AOM read_tx_mode: raw bit 1 selects TX_MODE_SELECT.
  // The FFmpeg trace ordinal is ONLY_4X4=0/LARGEST=1/SELECT=2, where ordinal 1
  // is TX_MODE_LARGEST, not SELECT; this fixture's trace ordinal is 1.
  assert_eq((frame.tx_mode_select, frame.reduced_tx_set), ({"true" if evidence["tx_mode_select"] else "false"}, false))
  let cdef = frame.cdef.unwrap()
  assert_eq((cdef.bits, cdef.damping), ({evidence["cdef"]["bits"]}, {evidence["cdef"]["damping"]}))
  assert_eq(cdef.y_primary, {evidence["cdef"]["y_primary"]})
  assert_eq(cdef.y_secondary, {evidence["cdef"]["y_secondary"]})
  assert_eq(cdef.uv_primary, {evidence["cdef"]["uv_primary"]})
  assert_eq(cdef.uv_secondary, {evidence["cdef"]["uv_secondary"]})
  let restoration = frame.restoration.unwrap()
  assert_eq(restoration.modes, [Av1RestorationWiener, Av1RestorationWiener, Av1RestorationWiener])
  assert_eq(restoration.unit_sizes, [{", ".join(str(size) for size in [evidence["lr_unit_size"]] * 3)}])
  assert_eq(av1_restoration_active(restoration), true)
  let layout = av1_restoration_layout(
    restoration, {evidence["coded_visible_width"]}, {WIDTH}, {HEIGHT}, false, true, true, {DENOM},
  ).unwrap()
  assert_eq(layout.unit_cols, [1, 1, 1])
  assert_eq(layout.unit_rows, [1, 1, 1])
}}
"""
    return text


def readme(record: dict[str, object]) -> str:
    evidence = record["evidence"]
    command = " ".join(record["encoder_command"])
    return f"""# AV1 active loop-restoration header reference

**One untouched libaom encode with active Wiener restoration on every
plane**: {WIDTH}x{HEIGHT} 10-bit 4:2:0, SB64, superres denominator {DENOM},
base_q_idx 160, CDEF active. The bounded stock superres corpus encodes every
frame with `--enable-restoration=0`, so no real stream there exercises the
active-LR frame-header path; this fixture fills exactly that gap.

The committed OBU ships with its wrapped input noise
(`.input.y4m`, deterministic seed {SEED}) and the FFmpeg `trace_headers`
transcript (`.trace.txt`) that acts as the syntax oracle. The generated
white-box test `_refs/av1_restoration_reference_wbtest.mbt` embeds the OBU
and asserts the parsed `Av1SequenceInfo`, `Av1FrameHeaderInfo` and
`Av1RestorationConfig` against that evidence: three Wiener modes, unit size
128 (lr_unit_shift 1), chroma unshifted (lr_uv_shift 0), coded width
{evidence["coded_visible_width"]} under denominator {DENOM}, and the
restoration grid on the upscaled plane (AOM `av1_alloc_restoration_struct`).

This is a stage-1 header gate: loop filtering itself lands with the Wiener
and SGR kernel stages, at which point this stream can be upgraded with a
native dav1d reference like the superres corpus.

## Reproduce and check

```powershell
python scripts/generate-av1-restoration-reference.py
python scripts/generate-av1-restoration-reference.py --check
```

The noise input regenerates byte-identically from the seed, so `--check`
re-derives it, re-encodes with the manifest command and verifies the OBU,
trace evidence and the canonical generated test.

## Encoder command

```text
{command}
```
"""


def manifest(args, record: dict[str, object], test_text: str) -> dict[str, object]:
    encoder = run([args.aomenc, "--help"])
    return {
        "scope": "bounded 1 active loop-restoration header reference; untouched libaom encode with Wiener on every plane",
        "fixture": record,
        "files": {
            "obu": record["obu_file"],
            "input_y4m": record["input_file"],
            "trace": record["trace_file"],
        },
        "generation_command": [sys.executable, *sys.argv],
        "versions": {
            "encoder": re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", encoder.stdout + encoder.stderr).group(0),
            "ffmpeg": run([args.ffmpeg, "-version"]).stdout.splitlines()[0],
        },
        "support_hashes": {
            "scripts/generate-av1-filter-intra-reference.py": sha256(
                (ROOT / "scripts/generate-av1-filter-intra-reference.py").read_bytes()
            )
        },
        "normative_sources": [
            "https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/common/restoration.c",
            "https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/av1/decoder/decodeframe.c",
        ],
        "reference_contract": "FFmpeg trace_headers oracle against av1_parse_stage1_frame; no pixel assertion until the filter stages land",
        "test_status": "canonical generated white-box test under _refs",
        "generated_test": str(args.test),
        "generated_test_sha256": sha256(test_text.encode("utf-8")),
    }


def build_record(args) -> tuple[dict[str, object], str]:
    input_path = args.out / f"{NAME}.input.y4m"
    obu_path = args.out / f"{NAME}.obu"
    trace_path = args.out / f"{NAME}.trace.txt"
    input_path.write_bytes(noise_y4m())
    command = encoder_command(args.aomenc, obu_path, input_path)
    run(command)
    trace = run(
        [args.ffmpeg, "-hide_banner", "-i", str(obu_path), "-c", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"]
    ).stderr
    trace_path.write_text(trace, encoding="utf-8", newline="\n")
    evidence = header_evidence(trace)
    record = {
        "name": NAME,
        "kind": "stock-active-lr",
        "dimensions": [WIDTH, HEIGHT],
        "superres_denom": DENOM,
        "bit_depth": DEPTH,
        "monochrome": False,
        "input_file": input_path.name,
        "input_sha256": sha256(input_path.read_bytes()),
        "obu_file": obu_path.name,
        "obu_sha256": sha256(obu_path.read_bytes()),
        "trace_file": trace_path.name,
        "trace_sha256": sha256(trace_path.read_bytes()),
        "encoder_command": command,
        "input_recipe": {
            "seed": SEED,
            "rng": "random.Random(seed).getrandbits(10)",
            "plane_order": ["Y", "U", "V"],
            "sample_encoding": "uint16 little-endian, 4:2:0",
        },
        "evidence": evidence,
        "provenance": "untouched libaom encoder output with active restoration",
    }
    return record, trace


def check(args) -> int:
    data = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    record = data["fixture"]
    directory = args.out
    if noise_y4m() != (directory / record["input_file"]).read_bytes():
        raise ValueError("deterministic noise input changed")
    committed = (directory / record["obu_file"]).read_bytes()
    command = list(record["encoder_command"])
    command[0] = args.aomenc
    output = directory / ".recheck.obu"
    command[command.index("-o") + 1] = str(output)
    run(command)
    if output.read_bytes() != committed:
        raise ValueError("re-encode diverged from the committed OBU")
    output.unlink()
    trace = (directory / record["trace_file"]).read_text(encoding="utf-8")
    if header_evidence(trace) != record["evidence"]:
        raise ValueError("actual restoration header evidence changed")
    for name in ("input", "obu", "trace"):
        path = directory / record[f"{name}_file"]
        if sha256(path.read_bytes()) != record[f"{name}_sha256"]:
            raise ValueError(f"artifact hash mismatch: {path.name}")
    for path, expected in data["support_hashes"].items():
        if sha256((ROOT / path).read_bytes()) != expected:
            raise ValueError(f"source hash mismatch: {path}")
    formatted = run([args.moonfmt, "-"], input_text=generated_test(record, directory)).stdout
    if args.test.read_text(encoding="utf-8") != formatted:
        raise ValueError("canonical generated restoration test changed")
    print(
        f"checked 1 active restoration reference: deterministic noise input, byte-identical re-encode, "
        f"trace evidence and the canonical generated test"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-restoration")
    parser.add_argument("--test", type=Path, default=ROOT / "_refs/av1_restoration_reference_wbtest.mbt")
    for name in ("aomenc", "ffmpeg", "moonfmt"):
        parser.add_argument("--" + name, default=shutil.which(name) or name)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return check(args)
    args.out.mkdir(parents=True, exist_ok=True)
    if (args.out / "manifest.json").exists():
        raise ValueError("bounded restoration reference already exists")
    record, _ = build_record(args)
    text = run([args.moonfmt, "-"], input_text=generated_test(record, args.out)).stdout
    args.test.write_text(text, encoding="utf-8", newline="\n")
    data = manifest(args, record, text)
    (args.out / "README.md").write_text(readme(record), encoding="utf-8", newline="\n")
    (args.out / "manifest.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(NAME, "active Wiener header reference generated", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
