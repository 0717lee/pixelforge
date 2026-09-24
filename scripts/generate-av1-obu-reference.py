#!/usr/bin/env python3
"""Repackage existing AV1 fixtures, then validate their pixels with dav1d.

The split-tile fixture changes only OBU packaging. The hidden-inter fixture
changes show_frame, inserts showable_frame, and adds show-existing; entropy
bytes are preserved. --check writes only a temporary directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-obu-assembly"
WB = ROOT / "av1_obu_reference_wbtest.mbt"


def leb(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    return bytes(out + bytes([value]))


def obu(kind, payload, extension=None):
    header = bytes([(kind << 3) | 2 | (4 if extension is not None else 0)])
    if extension is not None:
        header += bytes([extension])
    return header + leb(len(payload)) + payload


def packets(data):
    pos = 0
    out = []
    while pos < len(data):
        first = pos
        header = data[pos]
        pos += 1
        if header & 4:
            pos += 1
        size = 0
        shift = 0
        while True:
            byte = data[pos]
            pos += 1
            size |= (byte & 127) << shift
            shift += 7
            if not byte & 128:
                break
        out.append((header >> 3, data[pos:pos + size], pos - first))
        pos += size
    return out


def trace_frames(ffmpeg, path):
    result = subprocess.run([ffmpeg, "-v", "verbose", "-i", str(path), "-c", "copy",
                             "-bsf:v", "trace_headers", "-f", "null", "-"],
                            capture_output=True, check=True)
    frames = []
    active = None
    for line in result.stderr.decode(errors="replace").splitlines():
        if line.endswith(" Frame Header"):
            active = {}
            frames.append(active)
        elif line.endswith(" Tile Group"):
            active = None
        elif active is not None:
            match = re.search(r"]\s+(\d+)\s+(\S+)\s+([01]*)\s*=\s*(\d+)\s*$", line)
            if match:
                pos, name, bits, value = match.groups()
                if name != "zero_bit":
                    active[name] = (int(pos), len(bits), int(value))
    return frames


def bits(data):
    return "".join(f"{byte:08b}" for byte in data)


def packed(value):
    value += "0" * (-len(value) % 8)
    return bytes(int(value[pos:pos + 8], 2) for pos in range(0, len(value), 8))


def decode(dav1d, path, output, all_layers=None):
    options = [] if all_layers is None else ["--alllayers", str(all_layers)]
    subprocess.run([dav1d, "-q", "--threads=1", "--framedelay=1"] + options + ["-i", str(path),
                    "--muxer=yuv", "-o", str(output)], check=True, capture_output=True)
    return output.read_bytes()


def emit_array(name, data):
    rows = ["  " + ", ".join(f"0x{x:02x}" for x in data[pos:pos + 24]) + ","
            for pos in range(0, len(data), 24)]
    return f"///|\nlet {name} : Array[Byte] = [\n" + "\n".join(rows) + "\n]\n"


def generate(ffmpeg, dav1d, dest):
    dest.mkdir(parents=True, exist_ok=True)
    split_source = ROOT / "tests/fixtures/av1-multitile/tiles2x1_8bit_q10.obu"
    stream = packets(split_source.read_bytes())
    frame = next(p for p in stream if p[0] == 6)
    fields = trace_frames(ffmpeg, split_source)[0]
    end = max(pos + width for pos, width, _ in fields.values()) - frame[2] * 8
    header = packed(bits(frame[1])[:end] + "1")
    group = frame[1][(end + 7) // 8:]
    assert group[0] == 0  # Full-frame tile group, aligned to the next byte.
    size_bytes = fields["tile_size_bytes_minus1"][2] + 1
    first_size = int.from_bytes(group[1:1 + size_bytes], "little") + 1
    first = group[1 + size_bytes:1 + size_bytes + first_size]
    second = group[1 + size_bytes + first_size:]
    assert first and second
    # tile_start_and_end_present_flag=1; tg_start/end are each one bit.
    split = b"".join(obu(kind, payload) for kind, payload, _ in stream if kind != 6)
    split += obu(3, header) + obu(4, b"\x80" + first) + obu(4, b"\xe0" + second)
    split_name = "split_two_tile_groups"
    (dest / f"{split_name}.obu").write_bytes(split)
    expected = decode(dav1d, split_source, dest / "source_tiles.reference.yuv")
    actual = decode(dav1d, dest / f"{split_name}.obu", dest / f"{split_name}.reference.yuv")
    assert actual == expected

    source = ROOT / "tests/fixtures/av1-inter/inter_lossless_64x64.obu"
    original = packets(source.read_bytes())
    frames = [p for p in original if p[0] == 6]
    assert len(frames) == 2
    fields = trace_frames(ffmpeg, source)[1]
    payload = frames[1][1]
    offset = frames[1][2] * 8
    end = max(pos + width for pos, width, _ in fields.values()) - offset
    show = fields["show_frame"][0] - offset
    source_bits = bits(payload)[:end]
    assert source_bits[show] == "1"
    hidden_header = source_bits[:show] + "01" + source_bits[show + 1:]
    hidden = packed(hidden_header) + payload[(end + 7) // 8:]
    refresh = fields["refresh_frame_flags"][2]
    slot = (refresh & -refresh).bit_length() - 1
    show_existing = obu(3, packed("1" + f"{slot:03b}" + "1"))
    sequence = next(p[1] for p in original if p[0] == 1)
    td = obu(2, b"")
    # The second temporal unit decodes the hidden inter and presents it via
    # show-existing. The final inter verifies subsequent reference/CDF state.
    combined = td + obu(1, sequence) + obu(6, frames[0][1])
    combined += td + obu(6, hidden) + show_existing
    combined += td + obu(6, frames[1][1])
    hidden_name = "hidden_inter_show_existing"
    (dest / f"{hidden_name}.obu").write_bytes(combined)
    reference = decode(dav1d, source, dest / "source_inter.reference.yuv")
    displayed = decode(dav1d, dest / f"{hidden_name}.obu", dest / f"{hidden_name}.reference.yuv")
    frame_size = 64 * 64 * 3 // 2
    assert len(displayed) == frame_size * 3
    assert displayed[:frame_size * 2] == reference
    assert displayed[frame_size * 2:] == reference[frame_size:]
    # Three operating points: the default accepts temporal layers 0 and 1;
    # the second accepts layer 0 only; the third has no decoder model. This
    # forces both actual layer IDs and decoder_model_present_for_this_op to
    # determine how many unsigned 32-bit removal timestamps a frame consumes.
    original_sequence = bits(sequence)
    assert original_sequence[:29] == "0" * 29
    timing = "1" + f"{1:032b}{24:032b}" + "01"
    timing += f"{31:05b}{1:032b}{31:05b}{31:05b}"
    timing += "0" + f"{2:05b}"  # no initial-display delay; three OPs
    for idc, present in [(259, True), (257, True), (0, False)]:
        timing += f"{idc:012b}{0:05b}" + ("1" if present else "0")
        if present:
            timing += f"{0xffffffff:032b}{0x80000000:032b}" + "0"
    timed_sequence = packed(original_sequence[:5] + timing + original_sequence[29:])
    timed = td + obu(1, timed_sequence)
    source_fields = trace_frames(ffmpeg, source)
    for frame_index, (frame, fields) in enumerate(zip(frames, source_fields)):
        payload, header_bytes = frame[1:]
        frame_end = max(pos + width for pos, width, _ in fields.values()) - header_bytes * 8
        header_bits = bits(payload)[:frame_end]
        show_end = fields["show_frame"][0] + 1 - header_bytes * 8
        anchor = fields["primary_ref_frame"] if "primary_ref_frame" in fields else fields["frame_size_override_flag"]
        removal_start = anchor[0] + anchor[1] - header_bytes * 8
        removals = [0x80000000, 0xfffffffe] if frame_index == 0 else [0xffffffff]
        updated = header_bits[:removal_start] + "1" + "".join(f"{t:032b}" for t in removals) + header_bits[removal_start:]
        presentation = 0x80000000 if frame_index == 0 else 0xffffffff
        updated = updated[:show_end] + f"{presentation:032b}" + updated[show_end:]
        updated_payload = packed(updated) + payload[(frame_end + 7) // 8:]
        if frame_index:
            timed += td
        timed += obu(6, updated_payload, extension=frame_index << 5)
    timing_name = "layer_timing_32bit"
    (dest / f"{timing_name}.obu").write_bytes(timed)
    timed_pixels = decode(dav1d, dest / f"{timing_name}.obu", dest / f"{timing_name}.reference.yuv")
    assert timed_pixels == reference
    # OP0 includes temporal layer zero and spatial layers zero and one. Layer
    # one's inter picture predicts from layer zero's key picture in the same
    # TU. The middle TU has only layer zero, so output selection must fall back
    # to the highest layer actually present instead of dropping that TU.
    spatial_sequence = packed(original_sequence[:12] + f"{769:012b}" + original_sequence[24:])
    spatial = td + obu(1, spatial_sequence)
    spatial += obu(6, frames[0][1], extension=0) + obu(6, frames[1][1], extension=8)
    spatial += td + obu(6, frames[0][1], extension=0)
    spatial += td + obu(6, frames[0][1], extension=0) + obu(6, frames[1][1], extension=8)
    spatial_name = "spatial_layer_presentation"
    (dest / f"{spatial_name}.obu").write_bytes(spatial)
    default_layers = decode(dav1d, dest / f"{spatial_name}.obu", dest / "spatial_default.yuv")
    spatial_pixels = decode(dav1d, dest / f"{spatial_name}.obu", dest / f"{spatial_name}.reference.yuv", all_layers=0)
    key, inter = reference[:frame_size], reference[frame_size:]
    assert default_layers == key + inter + key + key + inter
    assert spatial_pixels == inter + key + inter
    version = subprocess.run([dav1d, "--version"], capture_output=True, check=True)
    manifest = {
        "generator": "python scripts/generate-av1-obu-reference.py --ffmpeg <ffmpeg> --dav1d <dav1d>",
        "decoder_version": (version.stdout + version.stderr).decode().strip(),
        "fixtures": [
            {"name": split_name, "source": split_source.relative_to(ROOT).as_posix(), "displayed_frames": 1,
             "operation": "frame OBU becomes standalone frame header and two independently framed one-tile groups"},
            {"name": hidden_name, "source": source.relative_to(ROOT).as_posix(), "displayed_frames": 3,
             "operation": "hide inter, show saved slot in same temporal unit, decode a following inter", "slot": slot},
            {"name": timing_name, "source": source.relative_to(ROOT).as_posix(), "displayed_frames": 2,
             "operation": "three OPs with model presence flags, temporal IDs 0/1, full-width unsigned timing fields"},
            {"name": spatial_name, "source": source.relative_to(ROOT).as_posix(), "displayed_frames": 3,
             "operation": "three TUs with spatial IDs [0,1], [0], [0,1]; OP0 idc=769",
             "stock_dav1d_default_frames": 5, "presentation_decoder_args": ["--alllayers", "0"]},
        ],
    }
    for fixture in manifest["fixtures"]:
        fixture["sha256"] = {ext: hashlib.sha256((dest / (fixture["name"] + ext)).read_bytes()).hexdigest()
                             for ext in (".obu", ".reference.yuv")}
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return {split_name: (split, actual, 128, 64, 1), hidden_name: (combined, displayed, 64, 64, 3),
            timing_name: (timed, timed_pixels, 64, 64, 2),
            spatial_name: (spatial, spatial_pixels, 64, 64, 3)}


def whitebox(fixtures):
    out = "/// Generated by scripts/generate-av1-obu-reference.py; dav1d native YUV is the oracle.\n\n"
    for name, (data, expected, width, height, count) in fixtures.items():
        out += emit_array("obu_" + name + "_data", data) + "\n"
        out += emit_array("obu_" + name + "_reference", expected) + "\n"
        out += f'''///|
test "OBU assembly {name}: independent displayed native planes" {{
  let decoder = av1_video_decoder()
  let frames = av1_video_decode_temporal_unit_planes(decoder, obu_{name}_data).unwrap()
  assert_eq(frames.length(), {count})
  let mut offset = 0
  for frame in frames {{
    assert_eq((frame.width, frame.height), ({width}, {height}))
    for plane in 0..<3 {{
      for value in av1_frame_crop(frame, plane) {{
        assert_eq(value, obu_{name}_reference[offset].to_int())
        offset = offset + 1
      }}
    }}
  }}
  assert_eq(offset, obu_{name}_reference.length())
}}
\n'''
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    parser.add_argument("--dav1d", default=os.environ.get("DAV1D", "dav1d"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pixelforge-obu-") as temp:
        output = Path(temp)
        fixtures = generate(args.ffmpeg, args.dav1d, output)
        wb = whitebox(fixtures)
        names = ["manifest.json"] + [name + ext for name in fixtures for ext in (".obu", ".reference.yuv")]
        if args.check:
            for name in names:
                assert (OUT / name).read_bytes() == (output / name).read_bytes(), name
            # moonfmt may reflow generated source; executable fixtures remain exact.
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            for name in names:
                shutil.copyfile(output / name, OUT / name)
            WB.write_text(wb, encoding="utf-8", newline="\n")
        print("Verified standalone tile groups and hidden-frame/show-existing sequence with dav1d")


if __name__ == "__main__":
    main()
