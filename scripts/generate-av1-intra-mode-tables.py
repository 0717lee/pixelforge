#!/usr/bin/env python3
"""Generate fresh mutable AV1 intra-mode CDF factories from verified Go tables.

    python scripts/generate-av1-intra-mode-tables.py
    python scripts/generate-av1-intra-mode-tables.py --check

Requires the cached go-av1 CDF sources and MoonBit's standalone moonfmt. Supply
--source-dir or --moonfmt for non-default locations. Only the generated text is
formatted through stdin/stdout; no package-wide formatter or build is invoked.

The four exact Go table names below were independently compared in full against
the official AV1 default tables. Source hashes are pinned so a changed cache
cannot silently alter the generated CDFs. Each CDF includes its terminal 32768
entry and initial adaptation count 0. Literal arrays inside function bodies
create fresh rows on every call, allowing tile-local probability adaptation.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TABLE_URL = "https://raw.githubusercontent.com/AOMediaCodec/av1-spec/master/10.additional.tables.md"
CONTEXT_URL = "https://raw.githubusercontent.com/AOMediaCodec/av1-spec/master/09.parsing.process.md"
SOURCE_HASHES = {
    "tables_gen.go": "583c969851ff9f5fc42369ab77adf80944ce1c049636d0e2dbb7d435daebcdd4",
    "tables_angle_gen.go": "e817a2a2816d1c189e1c54e67c8edd2218b5c0a261043c6611ca663b428acb52",
}
TABLES = (
    ("DefaultIntraFrameYModeCdf", "tables_gen.go", (5, 5, 14)),
    ("DefaultUvModeCflNotAllowedCdf", "tables_gen.go", (13, 14)),
    ("DefaultUvModeCflAllowedCdf", "tables_gen.go", (13, 15)),
    ("DefaultAngleDeltaCdf", "tables_angle_gen.go", (8, 8)),
)
MODE_CONTEXT = (0, 1, 2, 3, 4, 4, 4, 4, 3, 0, 1, 2, 0)

# Retain the source project's complete BSD notice with the generated tables.
SOURCE_LICENSE = """BSD 2-Clause License

Copyright (c) 2026, Oleksandr Zhabotynskyi

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."""


def parse_table(source: str, name: str, dimensions: tuple[int, ...]) -> list:
    match = re.search(r"^var " + re.escape(name) + r"\s*=\s*(?:\[\])+uint16\s*", source, re.M)
    if match is None:
        raise ValueError(f"missing exact Go table declaration: {name}")
    start = source.index("{", match.end())
    end, depth = start + 1, 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    body = source[start:end]
    if depth or re.fullmatch(r"[\s\d{},]+", body) is None:
        raise ValueError(f"invalid numeric table literal: {name}")
    values = ast.literal_eval(body.replace("{", "[").replace("}", "]"))

    def validate(node: list, shape: tuple[int, ...]) -> None:
        if not isinstance(node, list) or len(node) != shape[0]:
            raise ValueError(f"{name}: expected dimensions {dimensions}")
        if len(shape) > 1:
            for child in node:
                validate(child, shape[1:])
        elif (node[-2:] != [32768, 0] or any(type(v) is not int for v in node)
              or node[0] <= 0 or any(a >= b for a, b in zip(node[:-2], node[1:-1]))):
            raise ValueError(f"{name}: invalid CDF row or adaptation count")

    validate(values, dimensions)
    return values


def array_literal(values: list | tuple) -> str:
    if isinstance(values[0], list):
        return "[\n" + ",\n".join(array_literal(row) for row in values) + ",\n]"
    return "[" + ", ".join(map(str, values)) + "]"


def generate(source_dir: Path) -> str:
    sources = {}
    for filename, expected in SOURCE_HASHES.items():
        data = (source_dir / filename).read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise ValueError(f"{filename}: SHA-256 {actual}, expected {expected}")
        print(f"{filename}: SHA-256 {actual}")
        sources[filename] = data.decode("utf-8")
    tables = {name: parse_table(sources[filename], name, shape)
              for name, filename, shape in TABLES}
    text = [
        "// Generated by scripts/generate-av1-intra-mode-tables.py. Do not edit.\n",
        "// AV1 normative mode defaults; each call returns fresh mutable CDF rows.\n",
        f"// Official default tables: {TABLE_URL}\n",
        f"// Official Intra_Mode_Context mapping: {CONTEXT_URL}\n",
        "// Source: https://github.com/mgvs/go-av1/tree/main/cdf\n",
    ]
    for filename, digest in SOURCE_HASHES.items():
        text.append(f"// _refs/go-av1/cdf/{filename} SHA-256: {digest}\n")
    text.append("//\n")
    text.extend("//" + (" " + line if line else "") + "\n" for line in SOURCE_LICENSE.splitlines())
    text.append("\n///|\n// Indexed by above/left Intra_Mode_Context; 13 modes plus adaptation count.\n")
    text.append("fn av1_intra_y_mode_cdfs() -> Array[Array[Array[Int]]] {\n")
    text.append(array_literal(tables["DefaultIntraFrameYModeCdf"]) + "\n}\n")
    text.append("\n///|\n// Indexed by the raw YMode. CfL adds a fourteenth UV symbol.\n")
    text.append("fn av1_intra_uv_mode_cdfs(cfl_allowed : Bool) -> Array[Array[Int]] {\n")
    text.append("if cfl_allowed {\n" + array_literal(tables["DefaultUvModeCflAllowedCdf"]) + "\n} else {\n")
    text.append(array_literal(tables["DefaultUvModeCflNotAllowedCdf"]) + "\n}\n}\n")
    text.append("\n///|\n// Shared by Y and UV; indexed by directional mode minus V_PRED.\n")
    text.append("fn av1_intra_angle_cdfs() -> Array[Array[Int]] {\n")
    text.append(array_literal(tables["DefaultAngleDeltaCdf"]) + "\n}\n")
    text.append("\n///|\n// Input is one of the thirteen AV1 intra modes, numbered 0 through 12.\n")
    text.append("fn av1_intra_mode_context(mode : Int) -> Int {\n")
    text.append("let contexts : Array[Int] = " + array_literal(MODE_CONTEXT) + "\ncontexts[mode]\n}\n")
    return "".join(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "_refs/go-av1/cdf")
    parser.add_argument("--output", type=Path, default=ROOT / "av1_intra_mode_tables.mbt")
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true", help="verify current generated file without writing")
    args = parser.parse_args()
    formatter = shutil.which(args.moonfmt)
    if formatter is None:
        parser.error(f"MoonBit formatter not found: {args.moonfmt}; supply --moonfmt path/to/moonfmt")
    generated = subprocess.run([formatter, "-"], input=generate(args.source_dir),
                               text=True, encoding="utf-8", capture_output=True, check=True).stdout
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
            raise RuntimeError(f"{args.output}: generated tables differ; regenerate without --check")
        print(f"Reproducibility check passed: {args.output}")
    else:
        args.output.write_text(generated, encoding="utf-8", newline="\n")
        print(f"Wrote {args.output}")
    print("Generated full 5x5x14 Y, 13x14/15 UV and 8x8 angle CDFs; 13 mode contexts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
