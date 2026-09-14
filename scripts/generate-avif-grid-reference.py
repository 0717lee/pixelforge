#!/usr/bin/env python3
"""Assemble conforming AVIF grids from untouched, previously verified AV1 items.

No encoder is run. Source native planes were independently decoded by dav1d;
actual libavif 0.11.1 must reproduce their bounded row-major composition before
any reference is published. Containers are explicitly assembled BMFF fixtures.
"""

from __future__ import annotations

import argparse
import ctypes
import importlib.util
import json
import shutil
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "avif_grid_helpers", Path(__file__).with_name("generate-av1-monochrome-reference.py")
)
assert spec is not None and spec.loader is not None
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
box, full_box = helpers.box, helpers.full_box
sha256, read_hashed, rle = helpers.sha256, helpers.read_hashed, helpers.rle


class ImagePlanes0111(ctypes.Structure):
    """Exact prefix from the version-checked installed libavif 0.11.1 header."""

    _fields_ = [
        ("width", ctypes.c_uint32), ("height", ctypes.c_uint32),
        ("depth", ctypes.c_uint32), ("yuvFormat", ctypes.c_int),
        ("yuvRange", ctypes.c_int), ("chromaSamplePosition", ctypes.c_int),
        ("planes", ctypes.c_void_p * 3), ("rowBytes", ctypes.c_uint32 * 3),
    ]


class ImageAlpha0111(ctypes.Structure):
    _fields_ = ImagePlanes0111._fields_ + [
        ("ownsYUV", ctypes.c_int), ("alphaPlane", ctypes.c_void_p),
        ("alphaRowBytes", ctypes.c_uint32),
    ]


def scalar_native(data: bytes, library) -> tuple[list[bytes], dict[str, int]]:
    image = library.avifImageCreateEmpty()
    decoder = library.avifDecoderCreate()
    try:
        if not image or not decoder:
            raise RuntimeError("libavif allocation failed")
        buffer = ctypes.create_string_buffer(data)
        result = library.avifDecoderReadMemory(decoder, image, buffer, len(data))
        if result:
            raise RuntimeError(f"libavif grid decode failed: {result}")
        info = ImagePlanes0111.from_address(image)
        if info.yuvFormat not in (3, 4):
            raise RuntimeError(f"unexpected libavif pixel format {info.yuvFormat}")
        size = 1 if info.depth == 8 else 2
        planes = []
        for plane in range(1 if info.yuvFormat == 4 else 3):
            width = info.width if plane == 0 else (info.width + 1) // 2
            height = info.height if plane == 0 else (info.height + 1) // 2
            planes.append(b"".join(
                ctypes.string_at(info.planes[plane] + y * info.rowBytes[plane], width * size)
                for y in range(height)
            ))
        return planes, {"width": info.width, "height": info.height, "depth": info.depth,
                        "format": info.yuvFormat, "range": info.yuvRange}
    finally:
        if image:
            library.avifImageDestroy(image)
        if decoder:
            library.avifDecoderDestroy(decoder)


def scalar_decode_result(data: bytes, library) -> int:
    image = library.avifImageCreateEmpty()
    decoder = library.avifDecoderCreate()
    try:
        if not image or not decoder:
            raise RuntimeError("libavif allocation failed")
        buffer = ctypes.create_string_buffer(data)
        return library.avifDecoderReadMemory(decoder, image, buffer, len(data))
    finally:
        if image:
            library.avifImageDestroy(image)
        if decoder:
            library.avifDecoderDestroy(decoder)


def scalar_alpha(data: bytes, library) -> bytes:
    image = library.avifImageCreateEmpty()
    decoder = library.avifDecoderCreate()
    try:
        if not image or not decoder:
            raise RuntimeError("libavif allocation failed")
        buffer = ctypes.create_string_buffer(data)
        result = library.avifDecoderReadMemory(decoder, image, buffer, len(data))
        if result:
            raise RuntimeError(f"actual libavif alpha-grid decode failed: {result}")
        info = ImageAlpha0111.from_address(image)
        if not info.alphaPlane:
            raise RuntimeError("actual libavif found no linked alpha")
        size = 1 if info.depth == 8 else 2
        return b"".join(ctypes.string_at(info.alphaPlane + y * info.alphaRowBytes, info.width * size)
                        for y in range(info.height))
    finally:
        if image:
            library.avifImageDestroy(image)
        if decoder:
            library.avifDecoderDestroy(decoder)


def source_case(folder: str, name: str) -> dict:
    base = Path("tests/fixtures") / folder
    manifest = json.loads((base / "manifest.json").read_text(encoding="utf-8"))
    case = next(case for case in manifest["fixtures"] if case["name"] == name)
    data = read_hashed(base / case["avif_file"], case["avif_sha256"])
    raw = read_hashed(base / case["reference_file"], case["reference_sha256"])
    mdat = helpers.box_payloads(data, b"mdat")
    av1c = helpers.box_payloads(data, b"av1C")
    colr = helpers.box_payloads(data, b"colr")
    if any(len(values) != 1 for values in (mdat, av1c, colr)):
        raise RuntimeError(f"expected one coded image in {name}")
    mono = case.get("monochrome", False)
    depth = case["bit_depth"]
    counts = [4096] if mono else [4096, 1024, 1024]
    planes, position = [], 0
    for count in counts:
        length = count * (1 if depth == 8 else 2)
        planes.append(raw[position:position + length])
        position += length
    if position != len(raw) or case["dimensions"] != [64, 64]:
        raise RuntimeError("grid sources must have independently verified 64x64 planes")
    return {"name": name, "source_avif": str(base / case["avif_file"]),
            "source_avif_sha256": case["avif_sha256"],
            "source_native": str(base / case["reference_file"]),
            "source_native_sha256": case["reference_sha256"],
            "payload": mdat[0], "av1c": av1c[0], "colr": colr[0],
            "planes": planes, "depth": depth, "monochrome": mono}


def compose_native(sources: list[dict], rows: int, columns: int,
                   width: int, height: int) -> list[bytes]:
    size = 1 if sources[0]["depth"] == 8 else 2
    planes = []
    for plane in range(len(sources[0]["planes"])):
        tile = 64 if plane == 0 else 32
        pw = width if plane == 0 else (width + 1) // 2
        ph = height if plane == 0 else (height + 1) // 2
        output = bytearray(pw * ph * size)
        for index, source in enumerate(sources):
            ox, oy = index % columns * tile, index // columns * tile
            cw, ch = min(tile, pw - ox), min(tile, ph - oy)
            if cw <= 0 or ch <= 0:
                raise RuntimeError("unused grid cell")
            for y in range(ch):
                dst = ((oy + y) * pw + ox) * size
                src = y * tile * size
                output[dst:dst + cw * size] = source["planes"][plane][src:src + cw * size]
        planes.append(bytes(output))
    return planes


def assemble(sources: list[dict], rows: int, columns: int, width: int, height: int,
             *, wide_payload: bool = False, idat: bool = False,
             wide_ids: bool = False) -> tuple[bytes, dict]:
    if len(sources) != rows * columns:
        raise RuntimeError("wrong tile count")
    first = sources[0]
    if any((source["depth"], source["monochrome"], source["av1c"], source["colr"]) !=
           (first["depth"], first["monochrome"], first["av1c"], first["colr"])
           for source in sources):
        raise RuntimeError("incompatible grid tile properties")
    depth, mono = first["depth"], first["monochrome"]
    # Deliberately make pitm select a non-first item and dimg order differ from
    # numeric item order. These are legal, observable container behaviors.
    primary = 70001 if wide_ids else 9
    tile_ids = [primary + 20 + ((index * 3) % len(sources)) for index in range(len(sources))]
    grid = bytes([0, int(wide_payload), rows - 1, columns - 1])
    grid += struct.pack(">II" if wide_payload else ">HH", width, height)
    items = list(zip(tile_ids, (source["payload"] for source in sources))) + [(primary, grid)]
    item_format = ">I" if wide_ids else ">H"
    item_id = lambda value: struct.pack(item_format, value)
    ftyp = box(b"ftyp", b"avif" + bytes(4) + b"avifmif1miaf")
    hdlr = full_box(b"hdlr", 0, 0, bytes(4) + b"pict" + bytes(12) + b"PixelForge grid reference\0")
    pitm = full_box(b"pitm", int(wide_ids), 0, item_id(primary))
    entries = b""
    for identifier, _ in sorted(items):
        typ = b"grid" if identifier == primary else b"av01"
        entries += full_box(b"infe", 3 if wide_ids else 2, 0 if typ == b"grid" else 1,
                            item_id(identifier) + bytes(2) + typ + b"Image\0")
    iinf = full_box(b"iinf", 0, 0, struct.pack(">H", len(items)) + entries)
    properties = [
        full_box(b"ispe", 0, 0, struct.pack(">II", width, height)),
        full_box(b"ispe", 0, 0, struct.pack(">II", 64, 64)),
        full_box(b"pixi", 0, 0, bytes([1 if mono else 3] + [depth] * (1 if mono else 3))),
        box(b"colr", first["colr"]), box(b"av1C", first["av1c"]),
    ]
    associations = struct.pack(">I", len(items))
    for identifier, _ in sorted(items):
        props = [1, 3, 4] if identifier == primary else [2, 3, 4, 0x85]
        associations += item_id(identifier) + bytes([len(props)] + props)
    iprp = box(b"iprp", box(b"ipco", b"".join(properties)) +
               full_box(b"ipma", int(wide_ids), 0, associations))
    dimg = item_id(primary) + struct.pack(">H", len(tile_ids)) + b"".join(map(item_id, tile_ids))
    iref = full_box(b"iref", int(wide_ids), 0, box(b"dimg", dimg))
    payload = b"".join(data for _, data in items)

    def meta(start: int) -> bytes:
        version = 2 if wide_ids else int(idat)
        locations = b"\x44\x00" + struct.pack(">I" if version == 2 else ">H", len(items))
        offset = 0 if idat else start
        for identifier, data in items:
            locations += item_id(identifier)
            if version:
                locations += struct.pack(">H", int(idat))
            locations += struct.pack(">HHII", 0, 1, offset, len(data))
            offset += len(data)
        iloc = full_box(b"iloc", version, 0, locations)
        return full_box(b"meta", 0, 0, hdlr + pitm + iloc + iinf + iprp + iref +
                        (box(b"idat", payload) if idat else b""))

    placeholder = meta(0)
    container = ftyp + meta(len(ftyp) + len(placeholder) + 8)
    if not idat:
        container += box(b"mdat", payload)
    return container, {"primary_item_id": primary, "tile_item_ids": tile_ids,
                       "grid_payload_hex": grid.hex(), "wide_payload": wide_payload,
                       "iloc_version": 2 if wide_ids else int(idat),
                       "construction_method": int(idat), "wide_item_ids": wide_ids}


def byte_array(label: str, data: bytes) -> str:
    rows = ["    " + ", ".join(f"b'\\x{v:02X}'" for v in data[i:i + 12]) + ","
            for i in range(0, len(data), 12)]
    return f"  let {label} : Array[Byte] = [\n" + "\n".join(rows) + "\n  ]\n"


def generate_test(manifest: dict, base: Path) -> str:
    source = """/// Generated by scripts/generate-avif-grid-reference.py.
/// Native planes are dav1d-decoded tile composition independently checked by
/// actual libavif; color RGBA follows PixelForge's nearest-420 public contract.
fn avif_grid_reference_check(
  container : Array[Byte], width : Int, height : Int, rows : Int, columns : Int,
  primary : Int, item_ids : Array[Int], expected : Image,
) -> Unit raise {
  let descriptor = avif_grid_descriptor(container).unwrap()
  assert_eq((descriptor.output_width, descriptor.output_height), (width, height))
  assert_eq((descriptor.rows, descriptor.columns, descriptor.item_id), (rows, columns, primary))
  assert_eq(descriptor.tiles.length(), item_ids.length())
  for index in 0..<item_ids.length() {
    assert_eq(descriptor.tiles[index].item_id, item_ids[index])
  }
  let grid = avif_decode_grid_auto(container).unwrap()
  let rgba = avif_decode_rgba(container).unwrap()
  let primary_image = avif_decode(container).unwrap()
  for actual in [grid, rgba, primary_image] {
    assert_eq((actual.width, actual.height), (width, height))
    for y in 0..<height {
      for x in 0..<width {
        assert_eq((x, y, actual.get_pixel(x, y)), (x, y, expected.get_pixel(x, y)))
      }
    }
  }
}
"""
    for record in manifest["fixtures"] + manifest.get("primary_item_cases", []):
        width, height = record["dimensions"]
        depth = record["bit_depth"]
        source += f'\n///|\ntest "external AVIF grid {record["name"]}" {{\n'
        source += byte_array("container", read_hashed(base / record["file"], record["sha256"]))
        native = read_hashed(base / record["native_file"], record["native_sha256"])
        if record["monochrome"]:
            rgba = read_hashed(base / record["scalar_rgba_file"], record["scalar_rgba_sha256"])
            source += "  let gray = av1_reference_planes_expand(" + json.dumps(rle(list(rgba[::4]))) + ")\n"
            source += f"  let expected = Image::new({width}, {height})\n"
            source += f"  for index in 0..<gray.length() {{\n    let value = gray[index].to_byte()\n    expected.set_pixel(index % {width}, index / {width}, value, value, value, b'\\xFF')\n  }}\n"
        else:
            counts = [width * height, ((width + 1) // 2) * ((height + 1) // 2)]
            counts.append(counts[1])
            position = 0
            for label, count in zip(("y", "u", "v"), counts):
                length = count * (1 if depth == 8 else 2)
                values = helpers.unpack(native[position:position + length], count, depth)
                source += f"  let {label} = av1_reference_planes_expand(" + json.dumps(rle(values)) + ")\n"
                position += length
            full_range = str(record["libavif_image"]["range"] == 1).lower()
            source += f"  let expected = av1_yuv420_highbd_to_rgba({width}, {height}, y, u, v, {depth}, full_range={full_range}, matrix_coefficients={record['matrix_coefficients']}).unwrap()\n"
        if record.get("primary_is_av01"):
            source += "  assert_true(avif_grid_descriptor(container) is None)\n  assert_true(avif_decode_grid_auto(container) is None)\n"
            source += "  for actual in [avif_decode(container).unwrap(), avif_decode_rgba(container).unwrap()] {\n"
            source += f"    assert_eq((actual.width, actual.height), ({width}, {height}))\n"
            source += f"    for y in 0..<{height} {{\n      for x in 0..<{width} {{\n        assert_eq((x, y, actual.get_pixel(x, y)), (x, y, expected.get_pixel(x, y)))\n      }}\n    }}\n  }}\n}}\n"
        else:
            source += f"  avif_grid_reference_check(container, {width}, {height}, {record['rows']}, {record['columns']}, {record['primary_item_id']}, {json.dumps(record['tile_item_ids'])}, expected)\n}}\n"
    for record in manifest.get("negative_cases", []):
        source += f'\n///|\ntest "AVIF grid rejects {record["name"]}" {{\n'
        source += byte_array("container", read_hashed(base / record["file"], record["sha256"]))
        source += "  assert_true(avif_decode_grid_auto(container) is None)\n  assert_true(avif_decode(container) is None)\n  assert_true(avif_decode_rgba(container) is None)\n}\n"
    return source


def binding_cases(source: dict, base: Path, library) -> tuple[list[dict], list[dict]]:
    original, metadata = assemble([source] * 4, 2, 2, 96, 98)
    selected_id = metadata["tile_item_ids"][0]
    selected = bytearray(original)
    struct.pack_into(">H", selected, original.index(b"pitm") + 8, selected_id)
    old_entry = full_box(b"infe", 2, 1, struct.pack(">HH", selected_id, 0) + b"av01Image\0")
    entry = original.index(old_entry)
    selected[entry + 9:entry + 12] = bytes(3)
    data = bytes(selected)
    planes, info = scalar_native(data, library)
    if planes != source["planes"] or (info["width"], info["height"]) != (64, 64):
        raise RuntimeError("libavif did not select the pitm coded image")
    rgba = helpers.scalar_rgba(data, library)
    name = "primary_av01_with_secondary_grid_8bit"
    primary = {"name": name, "dimensions": [64, 64], "primary_is_av01": True,
               "primary_item_id": selected_id, "secondary_grid_id": metadata["primary_item_id"],
               "bit_depth": 8, "monochrome": False, "matrix_coefficients": 2,
               "libavif_image": info, "file": name + ".avif", "sha256": sha256(data),
               "native_file": name + ".reference.yuv", "native_sha256": sha256(b"".join(planes)),
               "scalar_rgba_file": name + ".scalar.rgba", "scalar_rgba_sha256": sha256(rgba),
               "sources_in_dimg_order": [{k: value for k, value in source.items()
                                          if k.startswith("source_") or k == "name"}]}
    for filename, content in ((primary["file"], data), (primary["native_file"], b"".join(planes)),
                              (primary["scalar_rgba_file"], rgba)):
        (base / filename).write_bytes(content)
    negatives = []

    def record(name: str, data: bytes, expected: int, note: str) -> None:
        result = scalar_decode_result(data, library)
        if result != expected:
            raise RuntimeError(f"unexpected actual libavif outcome for {name}: {result}, expected {expected}")
        filename = name + ".avif"
        (base / filename).write_bytes(data)
        negatives.append({"name": name, "file": filename, "sha256": sha256(data),
                          "actual_libavif_result": result, "note": note})
        print(f"verified negative {name}: actual libavif result {result}")

    odd, _ = assemble([source] * 4, 2, 2, 95, 98)
    record("odd_420_output_width", odd, 18, "libavif rejects: MIAF 7.3.11.4.2 requires even grid output dimensions on subsampled axes")
    changed = bytearray(original)
    struct.pack_into(">I", changed, original.index(b"ispe") + 8, 98)
    record("primary_ispe_width_mismatch", bytes(changed), 0,
           "strict metadata-consistency regression: libavif 0.11.1 accepts and replaces primary ispe width with grid width; this is not vendor rejection parity")
    changed = bytearray(original)
    changed[original.index(b"av1C") + 6] ^= 0x40
    record("tile_av1c_depth_mismatch", bytes(changed), 9, "libavif rejects 8-bit pixi versus 10-bit av1C")
    changed = bytearray(original)
    struct.pack_into(">H", changed, original.index(b"dimg") + 8, 500)
    record("dimg_missing_target", bytes(changed), 18, "one ordered tile reference points at a missing item")
    changed = bytearray(original)
    grid_location = original.index(b"iloc") - 4 + 16 + 4 * 14
    struct.pack_into(">I", changed, grid_location + 10, 7)
    record("truncated_grid_extent", bytes(changed), 18, "grid payload extent omits the final height byte")
    changed = bytearray(original)
    struct.pack_into(">I", changed, original.index(b"iloc") - 4 + 16 + 6, 0xFFFFFFF0)
    record("tile_extent_beyond_file", bytes(changed), 9, "large unsigned extent offset lies beyond file and must not narrow or wrap")
    changed = bytearray(original)
    changed[-8] = 1
    record("unsupported_grid_version", bytes(changed), 18, "grid version one is reserved")
    return [primary], negatives


def assemble_alpha_grids(color: list[dict], alpha: list[dict], rows: int,
                         columns: int, width: int, height: int, *,
                         color_grid: bool, alpha_grid: bool) -> tuple[bytes, dict]:
    depth = color[0]["depth"]
    if any(source["depth"] != depth or source["monochrome"] for source in color):
        raise RuntimeError("invalid original color source")
    if any(source["depth"] != depth or not source["monochrome"] for source in alpha):
        raise RuntimeError("alpha must be monochrome and match master bit depth")
    count = rows * columns
    if len(color) != (count if color_grid else 1) or len(alpha) != (count if alpha_grid else 1):
        raise RuntimeError("invalid graph source count")
    if (not color_grid or not alpha_grid) and (width, height) != (64, 64):
        raise RuntimeError("mixed arrangements use the unchanged 64x64 coded image dimensions")
    primary, auxiliary = 9, 10
    color_ids = [29 + ((index * 3) % count) for index in range(count)] if color_grid else [primary]
    alpha_ids = [49 + ((index * 3) % count) for index in range(count)] if alpha_grid else [auxiliary]
    grid = bytes([0, 0, rows - 1, columns - 1]) + struct.pack(">HH", width, height)
    items = [(identifier, b"av01", source["payload"], False)
             for identifier, source in zip(color_ids, color)]
    items += [(identifier, b"av01", source["payload"], True)
              for identifier, source in zip(alpha_ids, alpha)]
    if color_grid:
        items.append((primary, b"grid", grid, False))
    if alpha_grid:
        items.append((auxiliary, b"grid", grid, True))
    ftyp = box(b"ftyp", b"avif" + bytes(4) + b"avifmif1miaf")
    hdlr = full_box(b"hdlr", 0, 0, bytes(4) + b"pict" + bytes(12) + b"PixelForge alpha grid reference\0")
    pitm = full_box(b"pitm", 0, 0, struct.pack(">H", primary))
    entries = b"".join(full_box(b"infe", 2, int(identifier != primary),
                                struct.pack(">HH", identifier, 0) + typ + b"Image\0")
                       for identifier, typ, _, _ in sorted(items))
    iinf = full_box(b"iinf", 0, 0, struct.pack(">H", len(items)) + entries)
    properties = [
        full_box(b"ispe", 0, 0, struct.pack(">II", width, height)),
        full_box(b"ispe", 0, 0, struct.pack(">II", 64, 64)),
        full_box(b"pixi", 0, 0, bytes([3, depth, depth, depth])),
        full_box(b"pixi", 0, 0, bytes([1, depth])),
        box(b"colr", color[0]["colr"]), box(b"colr", alpha[0]["colr"]),
        box(b"av1C", color[0]["av1c"]), box(b"av1C", alpha[0]["av1c"]),
        full_box(b"auxC", 0, 0, b"urn:mpeg:mpegB:cicp:systems:auxiliary:alpha\0"),
    ]
    associations = struct.pack(">I", len(items))
    for identifier, typ, _, is_alpha in sorted(items):
        props = [1 if identifier in (primary, auxiliary) else 2, 4 if is_alpha else 3, 6 if is_alpha else 5]
        if typ == b"av01":
            props.append(0x88 if is_alpha else 0x87)
        if identifier == auxiliary:
            props.append(0x89)
        associations += struct.pack(">HB", identifier, len(props)) + bytes(props)
    iprp = box(b"iprp", box(b"ipco", b"".join(properties)) + full_box(b"ipma", 0, 0, associations))
    references = box(b"auxl", struct.pack(">HHH", auxiliary, 1, primary))
    for enabled, identifier, targets in ((color_grid, primary, color_ids), (alpha_grid, auxiliary, alpha_ids)):
        if enabled:
            references += box(b"dimg", struct.pack(">HH", identifier, len(targets)) +
                              b"".join(struct.pack(">H", target) for target in targets))
    iref = full_box(b"iref", 0, 0, references)

    def meta(start: int) -> bytes:
        locations = b"\x44\x00" + struct.pack(">H", len(items))
        offset = start
        for identifier, _, payload, _ in items:
            locations += struct.pack(">HHHII", identifier, 0, 1, offset, len(payload))
            offset += len(payload)
        return full_box(b"meta", 0, 0, hdlr + pitm + full_box(b"iloc", 0, 0, locations) + iinf + iprp + iref)

    placeholder = meta(0)
    data = ftyp + meta(len(ftyp) + len(placeholder) + 8) + box(b"mdat", b"".join(item[2] for item in items))
    return data, {"primary_item_id": primary, "alpha_item_id": auxiliary,
                  "primary_type": "grid" if color_grid else "av01",
                  "alpha_type": "grid" if alpha_grid else "av01",
                  "auxl": {"from": auxiliary, "to": primary},
                  "color_dimg_order": color_ids if color_grid else [],
                  "alpha_dimg_order": alpha_ids if alpha_grid else [],
                  "auxc_item": auxiliary, "av1c_items": color_ids + alpha_ids}


def generate_alpha_test(manifest: dict, base: Path) -> str:
    text = """/// Generated by scripts/generate-avif-grid-reference.py --alpha.
/// Native alpha is independently checked with actual libavif. Eight-bit alpha
/// is that library's scalar UNORM coverage, never a monochrome RGB conversion.
fn avif_grid_alpha_reference_check(
  container : Array[Byte], width : Int, height : Int, expected : Image,
  alpha_runs : Array[Int],
) -> Unit raise {
  let alpha = av1_reference_planes_expand(alpha_runs)
  let actual_alpha = avif_decode_alpha(container).unwrap()
  let rgba = avif_decode_rgba(container).unwrap()
  let primary = avif_decode(container).unwrap()
  let info = avif_container_parse(container).unwrap()
  assert_true(info.has_alpha)
  let auxiliary = avif_alpha_item_descriptor(container).unwrap()
  assert_eq((auxiliary.item_id, auxiliary.width, auxiliary.height), (10, width, height))
  assert_eq(actual_alpha.length(), width * height)
  assert_eq((rgba.width, rgba.height), (width, height))
  for index in 0..<alpha.length() {
    let x = index % width
    let y = index / width
    let color = expected.get_pixel(x, y)
    assert_eq(primary.get_pixel(x, y), color)
    assert_eq((index, actual_alpha[index].to_int()), (index, alpha[index]))
    assert_eq(rgba.get_pixel(x, y), (color.0, color.1, color.2, alpha[index].to_byte()))
  }
}
"""
    for record in manifest["fixtures"]:
        width, height = record["dimensions"]
        depth = record["bit_depth"]
        text += f'\n///|\ntest "external AVIF grid alpha {record["name"]}" {{\n'
        text += byte_array("container", read_hashed(base / record["file"], record["sha256"]))
        data = read_hashed(base / record["native_color_file"], record["native_color_sha256"])
        count_y = width * height
        count_uv = ((width + 1) // 2) * ((height + 1) // 2)
        position = 0
        for label, count in (("y", count_y), ("u", count_uv), ("v", count_uv)):
            length = count * (1 if depth == 8 else 2)
            text += f"  let {label} = av1_reference_planes_expand(" + json.dumps(rle(helpers.unpack(data[position:position + length], count, depth))) + ")\n"
            position += length
        alpha = read_hashed(base / record["alpha8_file"], record["alpha8_sha256"])
        text += "  let alpha_runs : Array[Int] = " + json.dumps(rle(list(alpha))) + "\n"
        text += f"  let expected = av1_yuv420_highbd_to_rgba({width}, {height}, y, u, v, {depth}, full_range=false, matrix_coefficients=2).unwrap()\n"
        text += f"  avif_grid_alpha_reference_check(container, {width}, {height}, expected, alpha_runs)\n}}\n"
    return text


def alpha_main(args) -> int:
    manifest_path = args.out / "alpha-manifest.json"
    if args.check_alpha:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for record in manifest["fixtures"]:
            for label in ("native_color", "native_alpha", "alpha8", "scalar_rgba"):
                read_hashed(args.out / record[label + "_file"], record[label + "_sha256"])
            read_hashed(args.out / record["file"], record["sha256"])
            for source in record["color_sources"] + record["alpha_sources"]:
                read_hashed(Path(source["source_avif"]), source["source_avif_sha256"])
                read_hashed(Path(source["source_native"]), source["source_native_sha256"])
        helpers.verify_generated_test(manifest, generate_alpha_test(manifest, args.out), args.moonfmt)
        return 0
    library, version = helpers.scalar_library(args.libavif_scalar)
    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for depth in (8, 10, 12):
        color = source_case("av1-cdef-frame", f"cdef_64x64_1tile_{depth}bit")
        mono = source_case("av1-monochrome", f"mono_64x64_1tile_{depth}bit_q30")
        ramp = source_case("av1-monochrome", f"mono_64x64_1tile_{depth}bit_q0")
        arrangements = [(True, True, 2, 2, 96, 98)]
        if depth == 10:
            arrangements += [(False, True, 1, 1, 64, 64), (True, False, 1, 1, 64, 64)]
        for color_grid, alpha_grid, rows, columns, width, height in arrangements:
            colors = [color] * (rows * columns if color_grid else 1)
            alphas = [ramp, mono, mono, ramp] if rows == 2 else [ramp]
            name = f"alpha_{'grid' if color_grid else 'av01'}_{'grid' if alpha_grid else 'av01'}_{depth}bit"
            data, graph = assemble_alpha_grids(colors, alphas, rows, columns, width, height,
                                               color_grid=color_grid, alpha_grid=alpha_grid)
            actual_color, info = scalar_native(data, library)
            expected_color = compose_native(colors, rows, columns, width, height)
            actual_alpha = scalar_alpha(data, library)
            expected_alpha = compose_native(alphas, rows, columns, width, height)[0]
            if actual_color != expected_color or actual_alpha != expected_alpha:
                raise RuntimeError(f"actual libavif grid planes differ from independent tile composition: {name}")
            rgba = helpers.scalar_rgba(data, library)
            alpha8 = rgba[3::4]
            maximum = (1 << depth) - 1
            native = helpers.unpack(actual_alpha, width * height, depth)
            normalized = bytes((sample * 255 + maximum // 2) // maximum for sample in native)
            if normalized != alpha8:
                raise RuntimeError("actual scalar libavif alpha differs from rounded UNORM")
            record = {"name": name, "dimensions": [width, height], "bit_depth": depth,
                      "rows": rows, "columns": columns, **graph, "libavif_image": info,
                      "native_color_exact": True, "native_alpha_exact": True,
                      "alpha8_exact_rounded_unorm": True,
                      "color_sources": [{k: v for k, v in source.items() if k.startswith("source_") or k == "name"} for source in colors],
                      "alpha_sources": [{k: v for k, v in source.items() if k.startswith("source_") or k == "name"} for source in alphas],
                      "file": name + ".avif", "sha256": sha256(data)}
            (args.out / record["file"]).write_bytes(data)
            for label, suffix, content in (("native_color", ".color.yuv", b"".join(actual_color)),
                                            ("native_alpha", ".alpha.yuv", actual_alpha),
                                            ("alpha8", ".alpha8.raw", alpha8),
                                            ("scalar_rgba", ".scalar.rgba", rgba)):
                record[label + "_file"] = name + suffix
                record[label + "_sha256"] = sha256(content)
                (args.out / record[label + "_file"]).write_bytes(content)
            records.append(record)
            print(f"verified {name}: exact native color, native alpha and scalar UNORM alpha")
    manifest = {"scope": "three 2x2 color-grid/alpha-grid AVIFs at 8/10/12 bits, plus two valid 10-bit mixed grid/coded arrangements",
                "provenance": "BMFF assembly of unchanged original libaom color/monochrome coded image items; no encoder search",
                "reference_source": "https://raw.githubusercontent.com/AOMediaCodec/libavif/v0.11.1/src/read.c",
                "reference_source_lines": "3490-3528 alpha graph selection; 3550-3615 independent grid or coded tile construction; 3990-4017 native alpha composition",
                "specification": "https://aomediacodec.github.io/av1-avif/v1.2.0.html#auxiliary-image-items-and-sequences",
                "scalar_libavif_version": version, "scalar_libavif_path": args.libavif_scalar,
                "alpha_contract": "native monochrome coverage preserved through grid assembly; final 8-bit alpha is round(sample*255/((1<<depth)-1)), independently checked against actual scalar libavif",
                "color_contract": "existing nearest-420 PixelForge RGBA API applied to independently decoded full-depth color planes; scalar vendor RGBA retained without claiming color-byte parity",
                "fixtures": records, "generated_test": str(args.alpha_test)}
    generated = helpers.run([args.moonfmt, "-"], input_text=generate_alpha_test(manifest, args.out)).stdout.encode("utf-8")
    args.alpha_test.parent.mkdir(parents=True, exist_ok=True)
    args.alpha_test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


def generate_native_test(manifest: dict, base: Path) -> str:
    text = """/// Canonical dav1d tile planes, independently checked with actual libavif.
/// Native samples must survive grid assembly before RGB or alpha narrowing.
fn avif_grid_frame_reference_compare(
  container : Array[Byte], width : Int, height : Int, depth : Int,
  references : Array[Array[Int]],
) -> Unit raise {
  let descriptor = avif_grid_descriptor(container).unwrap()
  let frame = avif_decode_grid_frame(container, descriptor).unwrap()
  assert_eq((frame.width, frame.height, frame.coded_width, frame.bit_depth), (width, height, width, depth))
  assert_eq(frame.planes.length(), references.length())
  for plane in 0..<references.length() {
    let actual = av1_frame_crop(frame, plane)
    let expected = references[plane]
    assert_eq(actual.length(), expected.length())
    for index in 0..<expected.length() {
      assert_eq((plane, index, actual[index]), (plane, index, expected[index]))
    }
  }
}
"""
    for record in manifest["fixtures"]:
        name = record["name"]
        width, height = record["dimensions"]
        depth = record["bit_depth"]
        text += f'\n///|\n/// Native reference SHA256: {record["native_sha256"]}\ntest "grid retains canonical native samples {name}" {{\n'
        text += byte_array("container", read_hashed(base / record["file"], record["sha256"]))
        native = read_hashed(base / record["native_file"], record["native_sha256"])
        counts = [width * height]
        if not record["monochrome"]:
            counts += [((width + 1) // 2) * ((height + 1) // 2)] * 2
        position = 0
        references = []
        for plane, count in enumerate(counts):
            length = count * (1 if depth == 8 else 2)
            values = helpers.unpack(native[position:position + length], count, depth)
            position += length
            text += f"  let plane{plane} = av1_reference_planes_expand(" + json.dumps(rle(values)) + ")\n"
            references.append(f"plane{plane}")
        text += f"  avif_grid_frame_reference_compare(container, {width}, {height}, {depth}, [" + ", ".join(references) + "])\n}\n"
    text += """
///|
fn avif_grid_frame_pair_descriptor(first_size : Int, second_size : Int) -> AvifGridDescriptor {
  {
    item_id: 1, rows: 1, columns: 2, output_width: 128, output_height: 64,
    tiles: [
      { item_id: 2, extents: [{ offset: 0, length: first_size, construction_method: 0 }] },
      { item_id: 3, extents: [{ offset: first_size, length: second_size, construction_method: 0 }] },
    ],
  }
}
"""
    for pair in manifest["inconsistent_pairs"]:
        payloads = []
        for source in pair["sources"]:
            data = read_hashed(Path(source["source_avif"]), source["source_avif_sha256"])
            mdat = helpers.box_payloads(data, b"mdat")
            if len(mdat) != 1 or sha256(mdat[0]) != source["payload_sha256"]:
                raise RuntimeError("inconsistent-pair original coded payload changed")
            payloads.append(mdat[0])
        text += f'\n///|\ntest "native grid rejects {pair["name"]}" {{\n'
        text += byte_array("data", b"".join(payloads))
        text += f"  let descriptor = avif_grid_frame_pair_descriptor({len(payloads[0])}, {len(payloads[1])})\n  assert_true(avif_decode_grid_frame(data, descriptor) is None)\n}}\n"
    return text


def native_main(args) -> int:
    manifest_path = args.out / "native-manifest.json"
    if args.check_native:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        helpers.verify_generated_test(manifest, generate_native_test(manifest, args.out), args.moonfmt)
        return 0
    original = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    names = ["mono_2x2_8bit", "mono_2x2_10bit", "mono_2x2_12bit", "color_2x2_10bit"]
    records = [next(record for record in original["fixtures"] if record["name"] == name) for name in names]
    first = source_case("av1-cdef-frame", "cdef_64x64_1tile_8bit")
    pairs = []
    for name, folder, case in (("mixed_depth", "av1-cdef-frame", "cdef_64x64_1tile_10bit"),
                               ("mixed_plane_count", "av1-monochrome", "mono_64x64_1tile_8bit_q30")):
        second = source_case(folder, case)
        pairs.append({"name": name, "sources": [
            {"source_avif": source["source_avif"], "source_avif_sha256": source["source_avif_sha256"],
             "payload_sha256": sha256(source["payload"])} for source in (first, second)
        ]})
    manifest = {"scope": "native-grid exact sample retention at 8/10/12 bits and rejection of valid but inconsistent coded cells",
                "provenance": "reuses canonical existing grid native references and original coded AV1 payloads, without encoding or changing fixture bytes",
                "fixtures": records, "inconsistent_pairs": pairs, "generated_test": str(args.native_test)}
    generated = helpers.run([args.moonfmt, "-"], input_text=generate_native_test(manifest, args.out)).stdout.encode("utf-8")
    # Preserve the original six-test draft exactly; changes to the expectation
    # generator must never silently replace the independently reviewed oracle.
    expected = "9294b2336730643d3c7376539d776f1d82344e8edfc0b6ccd1a444346b7ef9df"
    if sha256(generated) != expected:
        raise RuntimeError(f"native six-test reference changed: {sha256(generated)}")
    args.native_test.parent.mkdir(parents=True, exist_ok=True)
    args.native_test.write_bytes(generated)
    manifest["generated_test_sha256"] = sha256(generated)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"generated unchanged {args.native_test}: SHA256 {sha256(generated)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("tests/fixtures/avif-grid"))
    parser.add_argument("--test", type=Path, default=Path("_refs/avif-grid/avif_grid_reference_wbtest.mbt"))
    parser.add_argument("--libavif-scalar", default=shutil.which("avif.dll") or "avif.dll")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--alpha", action="store_true", help="generate the separate grid-alpha corpus, preserving opaque-grid references")
    parser.add_argument("--check-alpha", action="store_true")
    parser.add_argument("--alpha-test", type=Path, default=Path("_refs/avif-grid/avif_grid_alpha_reference_wbtest.mbt"))
    parser.add_argument("--native-test", type=Path, help="regenerate the original six native-grid tests from canonical references")
    parser.add_argument("--check-native", action="store_true")
    args = parser.parse_args()
    if args.native_test is not None or args.check_native:
        return native_main(args)
    if args.alpha or args.check_alpha:
        return alpha_main(args)
    if args.check:
        manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
        for record in manifest["fixtures"] + manifest.get("primary_item_cases", []):
            for file_key, hash_key in (("file", "sha256"), ("native_file", "native_sha256"),
                                       ("scalar_rgba_file", "scalar_rgba_sha256")):
                read_hashed(args.out / record[file_key], record[hash_key])
            for source in record["sources_in_dimg_order"]:
                read_hashed(Path(source["source_avif"]), source["source_avif_sha256"])
                read_hashed(Path(source["source_native"]), source["source_native_sha256"])
        for record in manifest.get("negative_cases", []):
            read_hashed(args.out / record["file"], record["sha256"])
        helpers.verify_generated_test(manifest, generate_test(manifest, args.out), args.moonfmt)
        return 0
    library, version = helpers.scalar_library(args.libavif_scalar)
    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for depth in (8, 10, 12):
        color = source_case("av1-cdef-frame", f"cdef_64x64_1tile_{depth}bit")
        mono = source_case("av1-monochrome", f"mono_64x64_1tile_{depth}bit_q30")
        ramp = source_case("av1-monochrome", f"mono_64x64_1tile_{depth}bit_q0")
        for monochrome, shape in ((False, (1, 2)), (False, (2, 2)), (True, (1, 2)), (True, (2, 2))):
            rows, columns = shape
            sources = ([ramp, mono] if rows == 1 else [mono, ramp, ramp, mono]) if monochrome else [color] * (rows * columns)
            name = f"{'mono' if monochrome else 'color'}_{rows}x{columns}_{depth}bit"
            variants = [(name, False, False, False)]
            if depth == 10 and rows == 2:
                variants += [(name + "_wide32_idat_ids32", True, True, True)]
                if monochrome:
                    variants += [(name + "_idat", False, True, False)]
            for name, wide_payload, idat, wide_ids in variants:
                width = 95 if monochrome else 96
                height = (63 if rows == 1 else 97) if monochrome else (62 if rows == 1 else 98)
                data, metadata = assemble(sources, rows, columns, width, height,
                                          wide_payload=wide_payload, idat=idat, wide_ids=wide_ids)
                native, info = scalar_native(data, library)
                composed = compose_native(sources, rows, columns, width, height)
                if native != composed:
                    raise RuntimeError(f"actual libavif planes differ from independently decoded tile composition: {name}")
                rgba = helpers.scalar_rgba(data, library)
                if monochrome and any(rgba[i] != rgba[i + 1] or rgba[i] != rgba[i + 2] or rgba[i + 3] != 255 for i in range(0, len(rgba), 4)):
                    raise RuntimeError("unexpected monochrome scalar RGBA")
                files = {"file": name + ".avif", "native_file": name + ".reference.yuv",
                         "scalar_rgba_file": name + ".scalar.rgba"}
                for key, content in (("file", data), ("native_file", b"".join(native)), ("scalar_rgba_file", rgba)):
                    (args.out / files[key]).write_bytes(content)
                records.append({"name": name, "dimensions": [width, height], "rows": rows,
                                "columns": columns, "tile_dimensions": [64, 64], "bit_depth": depth,
                                "monochrome": monochrome, **metadata, **files,
                                "sha256": sha256(data), "native_sha256": sha256(b"".join(native)),
                                "scalar_rgba_sha256": sha256(rgba), "libavif_image": info,
                                "matrix_coefficients": struct.unpack_from(">H", sources[0]["colr"], 8)[0],
                                "native_equal_dav1d_tile_composition": True,
                                "sources_in_dimg_order": [{k: value for k, value in source.items()
                                                           if k.startswith("source_") or k == "name"} for source in sources]})
                print(f"verified {name}: {len(data)} bytes, exact native planes and scalar RGBA")
    primary, negative = binding_cases(source_case("av1-cdef-frame", "cdef_64x64_1tile_8bit"), args.out, library)
    manifest = {"scope": "opaque 64x64-source AVIF grids at 8/10/12 bits; actual cropped native pixels and distinct monochrome tile order",
                "provenance": "standards-compliant BMFF assembly of untouched original libaom AV1 payloads; no encoder search, no syntax mutation",
                "oracle": "actual libavif 0.11.1 native YUV equals independently dav1d-decoded source tile composition; scalar RGB uses avoidLibYUV=1",
                "scalar_libavif_version": version, "scalar_libavif_path": args.libavif_scalar,
                "color_rgba_contract": "PixelForge nearest-neighbor 4:2:0 API conversion of independently validated full-depth native planes; no claim of scalar libavif color RGBA parity",
                "fixtures": records, "primary_item_cases": primary, "negative_cases": negative,
                "generated_test": str(args.test)}
    text = helpers.run([args.moonfmt, "-"], input_text=generate_test(manifest, args.out)).stdout.encode("utf-8")
    args.test.parent.mkdir(parents=True, exist_ok=True)
    args.test.write_bytes(text)
    manifest["generated_test_sha256"] = sha256(text)
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
