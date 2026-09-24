#!/usr/bin/env python3
"""Regenerate AV1 grain update/inheritance/show-existing references.

The encoder emits three unchanged pictures with complete film-grain updates.
Two INTER grain parameter sets are replaced with legal reference inheritance;
seeds and tile bytes remain untouched. A fourth show-existing picture selects
the third picture. Independent dav1d runs prove both native and displayed
samples equal the original encoder stream, with its last picture repeated.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-film-grain"
TEST = ROOT / "av1_film_grain_sequence_reference_wbtest.mbt"


def run(command: list[str], cwd: Path) -> str:
    completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                               encoding="utf-8", errors="replace")
    if completed.returncode:
        raise RuntimeError(f"{command}: {completed.returncode}\n{completed.stderr[-4000:]}")
    return completed.stdout + completed.stderr


def resolve(value: str) -> str:
    path = shutil.which(value)
    if not path:
        raise RuntimeError(f"Executable not found: {value}")
    return str(Path(path).resolve())


def leb(value: int) -> bytes:
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def packets(data: bytes) -> list[tuple[int, bytes, bytes, int]]:
    result, pos = [], 0
    while pos < len(data):
        start = pos
        header = data[pos]
        assert header & 2 and not header & 0x81
        pos += 1 + bool(header & 4)
        prefix = data[start:pos]
        length, shift = 0, 0
        while True:
            byte = data[pos]
            pos += 1
            length |= (byte & 127) << shift
            if byte < 128:
                break
            shift += 7
        assert pos + length <= len(data)
        result.append(((header >> 3) & 15, prefix, data[pos:pos + length], pos - start))
        pos += length
    return result


def trace(ffmpeg: str, stream: Path, scratch: Path) -> tuple[bytes, list[dict]]:
    text = run([ffmpeg, "-hide_banner", "-loglevel", "info", "-i", stream.name,
                "-c:v", "copy", "-bsf:v", "trace_headers", "-f", "null", "-"], scratch)
    lines, frames, current = [], [], None
    for raw in text.splitlines():
        match = re.match(r"\[trace_headers @ [^\]]+\]\s?(.*)", raw)
        if not match:
            continue
        line = match[1]
        lines.append(line)
        if line == "Frame Header":
            current = {}
            frames.append(current)
        elif line in ("Sequence Header", "Tile Group"):
            current = None
        field = re.match(r"\s*(\d+)\s+(\S+)\s+([01]+)\s*=\s*(-?\d+)\s*$", line)
        if field and current is not None:
            current[field[2]] = dict(bit=int(field[1]), width=len(field[3]), value=int(field[4]))
    return ("\n".join(lines) + "\n").encode(), frames


def inherited_stream(original: bytes, frames: list[dict]) -> bytes:
    out = bytearray()
    index = 0
    for kind, prefix, payload, overhead in packets(original):
        if kind == 6:
            if index:
                fields = frames[index]
                assert fields["frame_type"]["value"] == 1
                assert fields["update_grain"]["value"] == 1
                slot = index - 1
                assert slot in [fields[f"ref_frame_idx[{i}]"]["value"] for i in range(7)]
                update = fields["update_grain"]["bit"] - overhead * 8
                end = fields["clip_to_restricted_range"]["bit"] + 1 - overhead * 8
                tile = payload[(end + 7) // 8:]
                bits = "".join(f"{b:08b}" for b in payload)
                new_header = bits[:update] + "0" + f"{slot:03b}"
                new_header += "0" * (-len(new_header) % 8)
                payload = bytes(int(new_header[i:i + 8], 2) for i in range(0, len(new_header), 8)) + tile
            index += 1
        out += prefix + leb(len(payload)) + payload
    assert index == 3
    # Temporal delimiter, FRAME_HEADER(show_existing=1, slot=2), trailing bit.
    out += bytes([0x12, 0x00, 0x1A, 0x01, 0xA8])
    return bytes(out)


def decode(dav1d: str, stream: Path, scratch: Path, grain: bool) -> bytes:
    target = scratch / (stream.stem + (".display.yuv" if grain else ".native.yuv"))
    run([dav1d, "-q", "--threads=1", "--framedelay=1", "--filmgrain", str(int(grain)),
         "--muxer=yuv", "-i", stream.name, "-o", target.name], scratch)
    return target.read_bytes()


def encode(depth: int, tools: dict[str, str], scratch: Path) -> tuple[dict, dict[str, bytes]]:
    name = f"sequence_inherit_{depth}bit"
    source = [value << (depth - 8) for value, count in ((96, 4096), (128, 1024), (160, 1024)) for _ in range(count)] * 3
    raw = bytes(source) if depth == 8 else struct.pack(f"<{len(source)}H", *source)
    input_file = scratch / f"{name}.input.yuv"
    input_file.write_bytes(raw)
    encoder = scratch / f"{name}.encoder.obu"
    flags = ["--codec=av1", "--obu", "--i420", "--width=64", "--height=64",
             f"--bit-depth={depth}", f"--input-bit-depth={depth}", f"--profile={2 if depth == 12 else 0}",
             "--fps=1/1", "--limit=3", "--passes=2", "--lag-in-frames=0", "--threads=1", "--row-mt=0",
             "--cpu-used=0", "--end-usage=q", "--cq-level=28", "--tile-columns=0", "--tile-rows=0",
             "--debug", "--disable-warning-prompt", "--film-grain-test=1", "--deltaq-mode=0",
             "--enable-intrabc=0", "--enable-palette=0", "--enable-cdef=0", "--enable-restoration=0",
             "--loopfilter-control=0", "--enable-tx64=0", "--sb-size=64", "--enable-order-hint=1",
             "--enable-ref-frame-mvs=0", "--enable-warped-motion=0", "--enable-global-motion=0",
             "--enable-obmc=0", "--enable-interintra-comp=0", "--enable-masked-comp=0",
             "--enable-dual-filter=0", "--min-partition-size=16", "--max-partition-size=32",
             "-o", encoder.name, input_file.name]
    run([tools["aomenc"]] + flags, scratch)
    encoder_trace, frames = trace(tools["ffmpeg"], encoder, scratch)
    assert len(frames) == 3
    transformed = scratch / f"{name}.obu"
    transformed.write_bytes(inherited_stream(encoder.read_bytes(), frames))
    inherited_trace, inherited = trace(tools["ffmpeg"], transformed, scratch)
    assert len(inherited) == 4, inherited
    assert [f.get("grain_seed", {}).get("value") for f in inherited[:3]] == [f["grain_seed"]["value"] for f in frames]
    assert [f["film_grain_params_ref_idx"]["value"] for f in inherited[1:3]] == [0, 1]
    assert inherited[3]["frame_to_show_map_idx"]["value"] == 2
    frame_bytes = 6144 * (1 if depth == 8 else 2)
    native, display = decode(tools["dav1d"], transformed, scratch, False), decode(tools["dav1d"], transformed, scratch, True)
    clean_original = decode(tools["dav1d"], encoder, scratch, False)
    grain_original = decode(tools["dav1d"], encoder, scratch, True)
    assert len(native) == len(display) == 4 * frame_bytes
    assert native == clean_original + clean_original[-frame_bytes:]
    assert display == grain_original + grain_original[-frame_bytes:]
    assert native != display
    assert display[:frame_bytes] != display[frame_bytes:2 * frame_bytes]
    artifacts = {encoder.name: encoder.read_bytes(), transformed.name: transformed.read_bytes(),
                 f"{name}.encoder.trace.txt": encoder_trace, f"{name}.trace.txt": inherited_trace,
                 f"{name}.native.yuv": native, f"{name}.display.yuv": display}
    record = dict(name=name, bit_depth=depth, width=64, height=64, encoder_frames=3, displayed_frames=4,
                  seeds=[f["grain_seed"]["value"] for f in frames], inherited_slots=[0, 1], show_existing_slot=2,
                  encoder_command=["aomenc"] + flags,
                  source_sha256=hashlib.sha256(raw).hexdigest(),
                  files={key: dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest()) for key, data in artifacts.items()})
    return record, artifacts


def hex_literal(data: bytes) -> str:
    return "\n".join('    "' + data[i:i + 96].hex() + '"' + (' +' if i + 96 < len(data) else '') for i in range(0, len(data), 96))


def emit_test(records: list[dict], artifacts: dict[str, bytes]) -> bytes:
    text = '''/// Generated by scripts/generate-av1-film-grain-sequence-reference.py.
/// All displayed samples and native reference slots are checked against dav1d.

///|
fn av1_grain_sequence_hex(text : String) -> Array[Byte] {
  let chars = text.to_array()
  let output : Array[Byte] = []
  let nibble = fn(c : Char) { if c >= '0' && c <= '9' { c.to_int() - 48 } else { c.to_int() - 87 } }
  for i in 0..<(chars.length() / 2) { output.push((nibble(chars[2*i]) * 16 + nibble(chars[2*i+1])).to_byte()) }
  output
}

///|
fn av1_grain_sequence_samples(data : Array[Byte], depth : Int) -> Array[Int] {
  if depth == 8 { data.map(b => b.to_int()) } else {
    Array::makei(data.length()/2, i => data[2*i].to_int() | (data[2*i+1].to_int() << 8))
  }
}
'''
    for record in records:
        name, depth = record["name"], record["bit_depth"]
        text += f'\n///|\ntest "film grain sequence {depth} bit matches dav1d and preserves native references" {{\n'
        for variable, suffix in (("encoded", ".encoder.obu"), ("inherited", ".obu"), ("expected", ".display.yuv"), ("native", ".native.yuv")):
            expression = "av1_grain_sequence_hex(\n" + hex_literal(artifacts[name + suffix]) + "\n  )"
            if variable in ("expected", "native"):
                expression = f"av1_grain_sequence_samples({expression}, {depth})"
            text += f"  let {variable} = {expression}\n"
        text += '''  for variant in 0..<2 {
    let map = av1_frame_map()
    let (_, displayed) = av1_decode_obu_planes(if variant == 0 { encoded } else { inherited }, map, None, false).unwrap()
    assert_eq(displayed.length(), if variant == 0 { 3 } else { 4 })
    for frame in 0..<displayed.length() {
      let mut offset = frame * 6144
      for plane in 0..<3 {
        let actual = av1_frame_crop(displayed[frame], plane)
        for i in 0..<actual.length() { assert_eq(actual[i], expected[offset+i]) }
        offset = offset + actual.length()
      }
    }
    // Key refreshed all eight slots; the two inter frames refresh slots 1/2.
    for slot in 0..<8 {
      let stored = map.slots[slot].unwrap()
      let source_frame = if slot == 1 || slot == 2 { slot } else { 0 }
      let mut offset = source_frame * 6144
      for plane in 0..<3 {
        for i in 0..<stored.planes[plane].length() { assert_eq(stored.planes[plane][i], native[offset+i]) }
        offset = offset + stored.planes[plane].length()
      }
    }
  }
}
'''
    return text.encode()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aomenc", default="aomenc")
    parser.add_argument("--dav1d", default="dav1d")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    tools = {name: resolve(getattr(args, name)) for name in ("aomenc", "dav1d", "ffmpeg")}
    artifacts, records = {}, []
    with tempfile.TemporaryDirectory(prefix="pixelforge-grain-sequence-") as directory:
        scratch = Path(directory)
        for depth in (8, 10, 12):
            record, files = encode(depth, tools, scratch)
            records.append(record)
            artifacts.update(files)
        versions = {"aomenc": re.search(r"AOMedia Project AV1 Encoder[^\r\n]+", run([tools["aomenc"], "--help"], scratch))[0],
                    "dav1d": run([tools["dav1d"], "--version"], scratch).strip(),
                    "ffmpeg": run([tools["ffmpeg"], "-version"], scratch).splitlines()[0]}
    test = emit_test(records, artifacts)
    with tempfile.TemporaryDirectory(prefix="pixelforge-grain-format-") as directory:
        formatted = Path(directory) / TEST.name
        formatted.write_bytes(test)
        run([resolve("moonfmt"), "-w", str(formatted)], ROOT)
        test = formatted.read_bytes().replace(b"\r\n", b"\n")
    artifacts["sequence-manifest.json"] = (json.dumps(dict(versions=versions, fixtures=records, whitebox_sha256=hashlib.sha256(test).hexdigest()), indent=2) + "\n").encode()
    for name, data in artifacts.items():
        path = OUT / name
        if args.check:
            existing = path.read_bytes() if path.exists() else None
            if existing is not None and path.suffix in (".txt", ".json"):
                existing = existing.replace(b"\r\n", b"\n")
            if existing != data:
                raise RuntimeError(f"Reference differs: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    if args.check:
        if TEST.read_bytes().replace(b"\r\n", b"\n") != test:
            raise RuntimeError(f"Whitebox differs: {TEST}")
    else:
        TEST.write_bytes(test)
    print(f"{'Checked' if args.check else 'Generated'} 3 grain sequences: 8/10/12-bit, update/inherit/show-existing, native/display exact")


if __name__ == "__main__":
    main()
