#!/usr/bin/env python3
"""Generate AV1 CICP/nclx fixtures with independent dav1d/libavif references.

All fixtures are 4:4:4 to isolate matrix/range conversion from chroma
upsampling. libavif 0.11.1 performs scalar conversion (avoidLibYUV=1), retaining
native precision until the final 8-bit RGBA quantization. Untouched libaom
OBUs are remuxed to AVIF; only unspecified metadata is supplied through nclx.
--check regenerates in temporary storage and does not write repository files.
"""

from __future__ import annotations

import argparse
from decimal import Decimal, localcontext
from fractions import Fraction
import hashlib
import importlib.util
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/fixtures/av1-color"
TEST = ROOT / "av1_color_reference_wbtest.mbt"
sys.dont_write_bytecode = True


def load_scalar():
    spec = importlib.util.spec_from_file_location("av1_monochrome_reference", ROOT / "scripts/generate-av1-monochrome-reference.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(command: list[str], directory: Path) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"Failed {command}\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return result


def specs() -> list[dict]:
    # p/t/m/range are actual bitstream values; nclx supplies independent
    # container declarations where all three sequence fields are unspecified.
    return [
        dict(name="identity_444_8bit", depth=8, p=1, t=13, m=0, full=True),
        dict(name="bt2020_ncl_444_10bit", depth=10, p=9, t=14, m=9, full=False),
        dict(name="nclx709_full_444_8bit", depth=8, p=2, t=2, m=2, full=True, nclx=[1, 13, 1]),
        dict(name="nclx709_limited_444_10bit", depth=10, p=2, t=2, m=2, full=False, nclx=[1, 1, 1]),
        dict(name="fcc_limited_444_8bit", depth=8, p=4, t=4, m=4, full=False),
        dict(name="smpte240_full_444_10bit", depth=10, p=7, t=7, m=7, full=True),
        dict(name="ycgco_full_444_12bit", depth=12, p=1, t=13, m=8, full=True),
        dict(name="derived_ncl_444_12bit", depth=12, p=12, t=13, m=12, full=False),
        dict(name="bt2020_cl_444_10bit", depth=10, p=9, t=14, m=10, full=False, oracle="zscale"),
        dict(name="derived_cl_444_12bit", depth=12, p=12, t=14, m=13, full=False, oracle="zscale"),
        dict(name="ictcp_pq_444_10bit", depth=10, p=9, t=16, m=14, full=False, oracle="zscale"),
        dict(name="ictcp_hlg_444_12bit", depth=12, p=9, t=18, m=14, full=True, oracle="zscale"),
        dict(name="ydzdx_xyz_444_12bit", depth=12, p=10, t=8, m=11, full=True, oracle="h273_xyz"),
        dict(name="ycgco_limited_444_10bit", depth=10, p=1, t=13, m=8, full=False, oracle="h273_ycgco"),
    ]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_transfer(value: float, transfer: int) -> float:
    """H.273 encoding curve, after independent zimg linear reconstruction."""
    value = max(value, 0.0)
    if transfer == 13:
        return 12.92*value if value < .0030412825601275209 else 1.0550107189475866*value**(1/2.4)-.0550107189475866
    if transfer == 14:
        return 4.5 * value if value < .018053968510807 else 1.099296826809442 * value ** .45 - .099296826809442
    if transfer == 16:
        power = value ** .1593017578125
        return ((.8359375 + 18.8515625 * power) / (1 + 18.6875 * power)) ** 78.84375
    if transfer == 18:
        return math.sqrt(3 * value) if value <= 1/12 else .17883277 * math.log(12 * value - .28466892) + .55991073
    raise ValueError("No reference transfer for this case")


def h273_rgba(yuv: bytes, case: dict) -> bytes:
    """Normative paths unavailable in libavif/zscale: YCgCo limited and XYZ.

    XYZ uses an exact rational solve from BT.709 xy/D65 coordinates, rather
    than the decoder's inverse-matrix constants. YCgCo is integer H.273
    equations 54-57, followed by the limited RGB expansion, equations 27-29.
    """
    def solve(matrix, rhs):
        rows = [list(row)+[rhs[i]] for i,row in enumerate(matrix)]
        for col in range(3):
            pivot = rows[col][col]
            rows[col] = [value/pivot for value in rows[col]]
            for row in range(3):
                if row != col:
                    factor = rows[row][col]
                    rows[row] = [a-factor*b for a,b in zip(rows[row],rows[col])]
        return [row[3] for row in rows]
    F = Fraction
    primary = ((F(64,100),F(3,10),F(15,100)),(F(33,100),F(6,10),F(6,100)),(F(3,100),F(1,10),F(79,100)))
    scales = solve(primary,(F(3127,3290),F(1),F(3583,3290)))
    rgb_to_xyz = [[primary[row][col]*scales[col] for col in range(3)] for row in range(3)]
    depth = case["depth"]
    samples = struct.unpack("<768H",yuv)
    maximum, mid, shift = (1<<depth)-1, 1<<(depth-1), 1<<(depth-8)
    result = []
    for i in range(256):
        y,u,v = samples[i],samples[256+i],samples[512+i]
        if case["oracle"] == "h273_ycgco":
            reconstructed = (y-(u-mid)+(v-mid),y+(u-mid),y-(u-mid)-(v-mid))
            nonlinear = [(min(maximum,max(0,value))-16*shift)/(219*shift) for value in reconstructed]
        else:
            yp,up,vp = F(y,maximum),F(u-mid,maximum),F(v-mid,maximum)
            xyz = (2*vp+F(991902,1000000)*yp,yp,(2*up+yp)/F(986566,1000000))
            nonlinear = [source_transfer(float(value),13) for value in solve(rgb_to_xyz,xyz)]
        result.extend(min(255,max(0,int(value*255+.5))) for value in nonlinear)
        result.append(255)
    return bytes(result)


def zscale_source_rgba(data: bytes, transfer: int) -> bytes:
    """Undo zimg's display convention, then apply the source encoding curve.

    zscale has no scene_referred option. Its CL kernel returns linear RGB,
    while a nonlinear RGB output would subsequently apply BT.1886. Requesting
    linear float output avoids that extra display conversion. For HLG,
    agamma=0 applies a common 1.2 OOTF in LMS before the LMS-to-RGB matrix;
    undo that common scalar using the same derived BT.2020 luminance weights.
    The ICtCp inverse matrix and HLG inverse curve themselves remain zimg's.
    npl=1000 (HLG) / 10000 (PQ) removes zimg's display-peak scale.
    """
    channels = struct.unpack("<768f", data)
    result = []
    for i in range(256):
        rgb = [channels[512+i], channels[i], channels[256+i]]
        if transfer == 18:
            l, m, s = [(a * rgb[0] + b * rgb[1] + c * rgb[2]) / 4096
                       for a, b, c in ((1688, 2146, 262), (683, 2951, 462), (99, 309, 3688))]
            luminance = .26270021201126698*l + (1-.26270021201126698-.05930171646986195)*m + .05930171646986195*s
            scale = max(luminance, 1e-30) ** (-1/6)
            rgb = [value * scale for value in rgb]
        result.extend(min(255, max(0, int(source_transfer(value, transfer) * 255 + .5))) for value in rgb)
        result.append(255)
    return bytes(result)


def pq_precision_evidence(yuv: bytes, linear_gbr: bytes, rgba: bytes, depth: int, full: bool) -> list[dict]:
    """80-digit independent H.273 inverse, to audit float32 rounding edges."""
    def solve(matrix, rhs):
        rows = [[Decimal(value) / 4096 for value in row] + [rhs[i]] for i, row in enumerate(matrix)]
        for col in range(3):
            pivot = rows[col][col]
            rows[col] = [value / pivot for value in rows[col]]
            for row in range(3):
                if row != col:
                    factor = rows[row][col]
                    rows[row] = [a - factor * b for a, b in zip(rows[row], rows[col])]
        return [row[3] for row in rows]
    planes = struct.unpack("<768H", yuv)
    floats = struct.unpack("<768f", linear_gbr)
    evidence = []
    with localcontext() as context:
        context.prec = 80
        D = Decimal
        m1, m2 = D(2610)/16384, D(2523)/32
        c1, c2, c3 = D(3424)/4096, D(2413)/128, D(2392)/128
        maximum, scale = (1 << depth)-1, 1 << (depth-8)
        for i in range(256):
            vector = [(D(planes[i]) - (0 if full else 16*scale)) / (maximum if full else 219*scale),
                      D(planes[256+i]-(1 << (depth-1))) / (maximum if full else 224*scale),
                      D(planes[512+i]-(1 << (depth-1))) / (maximum if full else 224*scale)]
            lms = solve(((2048,2048,0),(6610,-13613,7003),(17933,-17390,-543)), vector)
            linear = []
            for value in lms:
                power = max(value, D(0)) ** (1/m2)
                linear.append((max(power-c1, D(0))/(c2-c3*power)) ** (1/m1))
            rgb = solve(((1688,2146,262),(683,2951,462),(99,309,3688)), linear)
            for channel, value in enumerate(rgb):
                power = max(value, D(0)) ** m1
                code = ((c1+c2*power)/(1+c3*power)) ** m2 * 255
                quantized = min(255,max(0,int(code+D('.5'))))
                reference = rgba[4*i+channel]
                if quantized != reference:
                    float_linear = floats[(512,0,256)[channel]+i]
                    float_code = source_transfer(float_linear, 16)*255
                    boundary = D(min(quantized, reference)) + D('.5')
                    if abs(quantized-reference) != 1 or (code-boundary)*(D(float_code)-boundary) > 0 or abs(code-D(float_code)) > D('.25'):
                        raise RuntimeError(f"PQ reference mismatch at {i%16},{i//16},{channel}: H273={code} -> {quantized}, zimg={float_code} -> {reference}")
                    evidence.append(dict(x=i%16,y=i//16,channel="RGB"[channel],
                                         h273_80_digit_code=str(code), zimg_float32_linear=float_linear,
                                         zimg_code=float_code, h273_rgba8=quantized,zimg_rgba8=reference))
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for tool in ("aomenc", "dav1d", "ffmpeg", "moonfmt"):
        parser.add_argument("--" + tool, default=shutil.which(tool) or tool)
    parser.add_argument("--libavif", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    scalar = load_scalar()
    library, version = scalar.scalar_library(args.libavif)
    generated = {}
    manifest = []
    tests = ["// Generated by scripts/generate-av1-color-reference.py. Do not edit.",
             "// Independent dav1d native YUV and libavif scalar / FFmpeg zscale RGBA.", ""]
    with tempfile.TemporaryDirectory(prefix="pixelforge-color-reference-") as temp:
        directory = Path(temp)
        for case in specs():
            name, depth = case["name"], case["depth"]
            maximum = (1 << depth) - 1
            values = []
            for plane in range(3):
                for y in range(16):
                    for x in range(16):
                        # Non-neutral spatial variation, with native low bits
                        # retained instead of only left-shifted 8-bit values.
                        value = (37 * x + 53 * y + 71 * plane + 29) % 192 + 32
                        values.append(min(maximum, value * (1 << (depth - 8)) + (x + 3 * y + plane) % (1 << (depth - 8))))
            raw = bytes(values) if depth == 8 else struct.pack(f"<{len(values)}H", *values)
            if case.get("oracle") == "zscale":
                # Start with valid source-primary nonlinear RGB, then let
                # independent zimg encode the special matrix before libaom.
                rgb_source = directory / (name + ".gbr")
                rgb_source.write_bytes(raw)
                yuv_source = directory / (name + ".source.yuv")
                yuv_format = "yuv444p" if depth == 8 else f"yuv444p{depth}le"
                gbr_format = "gbrp" if depth == 8 else f"gbrp{depth}le"
                color_range = "full" if case["full"] else "limited"
                forward = (f"zscale=matrixin=gbr:primariesin={case['p']}:transferin={case['t']}:rangein=full:"
                           f"matrix={case['m']}:primaries={case['p']}:transfer={case['t']}:range={color_range}:dither=none,"
                           f"format={yuv_format}")
                run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pixel_format",
                     gbr_format, "-s", "16x16", "-i", rgb_source.name, "-vf", forward, "-f", "rawvideo", yuv_source.name], directory)
                raw = yuv_source.read_bytes()
            source = directory / (name + ".y4m")
            sampling = "444" if depth == 8 else f"444p{depth}"
            source.write_bytes((f"YUV4MPEG2 W16 H16 F1:1 Ip A1:1 C{sampling} XCOLORRANGE=" +
                                ("FULL" if case["full"] else "LIMITED") + "\nFRAME\n").encode() + raw)
            obu = directory / (name + ".obu")
            command = [args.aomenc, "--codec=av1", "--obu", "--passes=1", "--limit=1",
                       "--width=16", "--height=16", "--i444", "--profile=" + ("2" if depth == 12 else "1"),
                       f"--input-bit-depth={depth}", f"--bit-depth={depth}", "--cpu-used=6", "--threads=1",
                       "--lossless=1", "--enable-intrabc=0", "--enable-palette=0", "--enable-qm=0",
                       "--enable-cdef=0", "--enable-restoration=0", "--deltaq-mode=0",
                       f"--color-primaries={case['p']}", f"--transfer-characteristics={case['t']}",
                       f"--matrix-coefficients={case['m']}",
                       "-o", obu.name, source.name]
            run(command, directory)
            reference = directory / (name + ".dav1d.yuv")
            run([args.dav1d, "-i", obu.name, "-o", reference.name, "--muxer", "yuv", "--threads", "1"], directory)
            yuv = reference.read_bytes()
            if yuv != raw:
                raise RuntimeError(f"Lossless native reference differs: {name}")
            avif = directory / (name + ".avif")
            run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", obu.name, "-c:v", "copy", avif.name], directory)
            avif_data = avif.read_bytes()
            if case.get("nclx"):
                offset = avif_data.find(b"nclx")
                if offset < 0 or avif_data.find(b"nclx", offset + 4) >= 0:
                    raise RuntimeError("Expected one nclx declaration")
                mutable = bytearray(avif_data)
                struct.pack_into(">HHHB", mutable, offset + 4, *case["nclx"], int(case["full"]) << 7)
                avif_data = bytes(mutable)
                avif.write_bytes(avif_data)
            if case.get("oracle") == "zscale":
                rgb_reference = directory / (name + ".reference.gbr")
                peak = 1000 if case["t"] == 18 else 10000
                inverse = (f"zscale=matrixin={case['m']}:primariesin={case['p']}:transferin={case['t']}:rangein={color_range}:"
                           f"matrix=gbr:primaries={case['p']}:transfer=linear:range=full:dither=none:agamma=0:npl={peak},format=gbrpf32le")
                run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", obu.name,
                     "-vf", inverse, "-f", "rawvideo", rgb_reference.name], directory)
                gbr = rgb_reference.read_bytes()
                if len(gbr) != 768 * 4:
                    raise RuntimeError("Unexpected zscale RGB size")
                rgba = zscale_source_rgba(gbr, case["t"])
            elif case.get("oracle", "").startswith("h273_"):
                rgba = h273_rgba(yuv, case)
            else:
                rgba = scalar.scalar_rgba(avif_data, library)
            record = dict(case, width=16, height=16, yuv_sha256=sha(yuv), rgba_sha256=sha(rgba),
                          obu_sha256=sha(obu.read_bytes()), avif_sha256=sha(avif_data), encoder_args=command[1:])
            if case.get("oracle") == "zscale":
                generated[OUT / (name + ".linear-gbr.f32")] = gbr
                record["reference_args"] = inverse
                if case["t"] == 16:
                    record["rgba8_precision"] = "Only this PQ float32-zimg comparison permits one code value; all native YUV and other RGBA are exact. See 80-digit H.273 boundary evidence."
                    record["rounding_edges"] = pq_precision_evidence(yuv, gbr, rgba, depth, case["full"])
            manifest.append(record)
            for suffix, data in ((".obu", obu.read_bytes()), (".avif", avif_data), (".yuv", yuv), (".rgba", rgba)):
                generated[OUT / (name + suffix)] = data
            samples = list(yuv) if depth == 8 else list(struct.unpack(f"<{len(yuv)//2}H", yuv))
            literal = lambda data: 'b"' + ''.join(f"\\x{value:02x}" for value in data) + '"'
            oracle_name = "zscale" if case.get("oracle") == "zscale" else ("H273 rational reference" if case.get("oracle", "").startswith("h273_") else "scalar libavif")
            tests += ["///|", f'test "CICP and nclx {name} match dav1d and {oracle_name}" {{',
                      "  let obu = " + literal(obu.read_bytes()), "  let avif = " + literal(avif_data),
                      "  let frame = av1_decode_frame_planes(obu.to_array()).unwrap()",
                      f"  assert_eq(frame.bit_depth, {depth})", "  assert_eq(frame.sub_x, 0)", "  assert_eq(frame.sub_y, 0)",
                      "  let expected : Array[Int] = [" + ",".join(map(str, samples)) + "]",
                      "  for plane in 0..<3 {", "    let actual = av1_frame_crop(frame, plane)",
                      "    for i in 0..<256 { assert_eq(actual[i], expected[plane * 256 + i]) }", "  }",
                      "  let container = avif_container_parse(avif.to_array()).unwrap()",
                      f"  assert_eq(container.nclx_full_range, Some({str(case['full']).lower()}))",
                      "  let image = avif_decode(avif.to_array()).unwrap()",
                      "  let rgba = " + literal(rgba),
                      "  for y in 0..<16 {", "    for x in 0..<16 {", "      let pixel = image.get_pixel(x, y)",
                      "      let offset = (y * 16 + x) * 4",
                      ]
            if case.get("oracle") == "zscale" and case["t"] == 16:
                tests += ["      // zimg's float32 PQ inverse crosses four RGBA8 half-code boundaries;",
                          "      // manifest.json records their independent 80-digit H.273 values.",
                          "      let channels = [pixel.0, pixel.1, pixel.2]",
                          "      for channel in 0..<3 {",
                          "        let delta = channels[channel].to_int() - rgba[offset + channel].to_int()",
                          "        assert_true(delta >= -1 && delta <= 1)",
                          "        let precise = match offset + channel {"]
                tests += [f"          {(edge['y']*16+edge['x'])*4+'RGB'.index(edge['channel'])} => {edge['h273_rgba8']}"
                          for edge in record["rounding_edges"]]
                tests += ["          _ => rgba[offset + channel].to_int()", "        }",
                          "        assert_eq(channels[channel].to_int(), precise)",
                          "      }", "      assert_eq(pixel.3, rgba[offset + 3])"]
            else:
                tests += ["      assert_eq(pixel, (rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3]))"]
            tests += ["    }", "  }", "}", ""]
            print(name, "native lossless and", oracle_name, "RGBA recorded")
    metadata = dict(libavif=version, format="16x16 planar 4:4:4, native little endian; RGBA8 row-major",
                    conversion="source-primary nonlinear RGB; scalar libavif avoidLibYUV=1 or zscale linear float agamma=0 plus explicit H.273 source curve and HLG OOTF removal; no gamut/tone conversion", cases=manifest)
    generated[OUT / "manifest.json"] = (json.dumps(metadata, indent=2) + "\n").encode()
    formatted = subprocess.run([args.moonfmt, "-"], input="\n".join(tests), text=True, encoding="utf-8",
                               capture_output=True, check=True).stdout
    generated[TEST] = formatted.encode("utf-8")
    for path, data in generated.items():
        if args.check:
            if path.read_bytes() != data:
                raise RuntimeError(f"Generated reference differs: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("Color references match." if args.check else "Wrote color references and tests.")


if __name__ == "__main__":
    main()
