#!/usr/bin/env python3
"""Generate the AV1 inter-frame default CDF tables from the cached go-av1 source.

    python scripts/generate-av1-inter-tables.py
    python scripts/generate-av1-inter-tables.py --check

Every `var Default… = [][]uint16{…}` declaration in the nine cached source
files listed in SOURCES below is transcribed; none is hand-copied. The nesting
depth is taken from the Go type (`[]uint16` through `[][][][]uint16`) and the
literals are parsed structurally, so a reshaped upstream table changes the
generated MoonBit types instead of silently passing.

The source hashes are pinned so a changed cache cannot silently alter the
normative inter probabilities. Each innermost slice is one CDF: its final slot
is the mutable adaptation counter, preceded by the 32768 terminator. Because a
tile must adapt probabilities without corrupting the defaults, every table is
emitted twice: as the shared `av1_<name>` literal and as an `av1_<name>_cdfs()`
factory that hands out fresh rows on each call. For a table the decoder uses
verbatim (nothing replicates its rows across contexts) the factory copies the
shared literal instead of carrying a second copy of every probability; see
DERIVE_FACTORIES. MoonBit's standalone `moonfmt` formats the generated text
through a pipe; no package-wide formatter or build is invoked.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import os
import re
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_URL = "https://github.com/mgvs/go-av1/tree/main/cdf"
RELATIVE_DIR = "_refs/go-av1/cdf"
DEFAULT_SOURCE_DIR = os.path.join(ROOT, "_refs", "go-av1", "cdf")
DEFAULT_OUTPUT = os.path.join(ROOT, "av1_inter_tables.mbt")
DEFAULT_MOONFMT = os.path.join(os.path.expanduser("~"), ".moon", "bin", "moonfmt")

# (file, SHA-256 of the exact cached bytes) in emission order.
SOURCES = (
    ("tables_mv_gen.go", "feae1191484cf7b23b5c1a02e2e4dcb5b7be8d91d740ba95a575986df7ed6b2f"),
    ("tables_inter_gen.go", "59b8ad4dee86f69fc461dc12e02d26098869ca665d9eac977b96793c777949dd"),
    ("tables_interp_gen.go", "8f0802cc4889517e99eb6f881a4543f5fd6dbf1b1fe57e2eeeebd2ec224a3355"),
    ("tables_mm_gen.go", "a7d6e45337acb1ee55476079224c9a1250dfb4bf1667a0d49c7c81c745460396"),
    ("tables_comp_gen.go", "e07ba99ae197604cc64d4bf5e3c3f512fb183d58efffc09000ed24f494e76ac8"),
    ("tables_interintra_gen.go", "ac9a20591303c2e6237a279b65cb042b9070e44526dfea34e5c3cd17c05c7208"),
    ("tables_intertx_gen.go", "cd91a79c2bc041846c69cae13b6b45454ec5c7302c6a8d775b5715bc040ab3ac"),
    ("tables_wedge_gen.go", "a4af33027848e4cf41207184d580bd89e2bd5ce8ef5e800bd48facd4fe81bc1b"),
    # Intra blocks that live inside an inter frame read their luma mode from a
    # different table than an intra frame does, so it belongs with the inter set.
    ("tables_ymode_gen.go", "63844b587ccd9f033c419ca1abe3f5363acdf95891a5aaa5707cfd2774de985d"),
)

# One doc-comment body per Go table, naming the syntax element and its index
# order. Indexed dimensions follow the reference decoder's own use of the table
# (go-av1 decode/cdf.go and decode/intermode.go).
DOCS: dict[str, tuple[str, ...]] = {
    "DefaultSingleRefCdf": (
        "Default_Single_Ref_Cdf: [reference-count context 0..2][decision symbol p 0..5]",
        "of the `single_ref` tree, one binary symbol per row. The context compares the",
        "number of available forward against backward reference frames.",
    ),
    "DefaultNewMvCdf": (
        "Default_New_Mv_Cdf: [new_mv context 0..5] built from the nearest-MV stack",
        "count and the two reference frame distances; one binary symbol.",
    ),
    "DefaultZeroMvCdf": (
        "Default_Zero_Mv_Cdf: [zero_mv context 0..1], set when a zero vector is",
        "unlikely because the nearest candidate disagrees with the global motion; one",
        "binary symbol.",
    ),
    "DefaultRefMvCdf": (
        "Default_Ref_Mv_Cdf: [ref_mv context 0..5] from the nearest-MV stack and the",
        "compound reference ordering; one binary symbol selecting the stacked candidate.",
    ),
    "DefaultDrlModeCdf": (
        "Default_Drl_Mode_Cdf: [depth reference list context 0..2] counting how many",
        "neighbours share this block's reference frames; one binary symbol.",
    ),
    "DefaultMvJointCdf": (
        "Default_Mv_Joint_Cdf: the four joints naming which motion vector components",
        "are nonzero. Stored once and replicated by the decoder as [mv_ctx][comp], with",
        "mv_ctx 0 for inter and 1 for intra block copy.",
    ),
    "DefaultMvSignCdf": (
        "Default_Mv_Sign_Cdf: the sign of a nonzero component; replicated as",
        "[mv_ctx][comp].",
    ),
    "DefaultMvClassCdf": (
        "Default_Mv_Class_Cdf: [comp][11 magnitude classes]. Both rows are identical in",
        "the normative table, so the component index carries no information; the",
        "decoder still replicates the rows as [mv_ctx][comp].",
    ),
    "DefaultMvClass0BitCdf": (
        "Default_Mv_Class0_Bit_Cdf: the leading class-0 sub-pel bit, read before the",
        "class-0 fraction; replicated as [mv_ctx][comp].",
    ),
    "DefaultMvClass0FrCdf": (
        "Default_Mv_Class0_Fr_Cdf: [comp][mv_class0_bit 0..1] over the four sub-pel",
        "positions of magnitude class 0; replicated per motion vector context.",
    ),
    "DefaultMvClass0HpCdf": (
        "Default_Mv_Class0_Hp_Cdf: the one-eighth-pel extension of class 0; replicated",
        "as [mv_ctx][comp].",
    ),
    "DefaultMvBitCdf": (
        "Default_Mv_Bit_Cdf: [bit index 0..9] of the magnitude bits used by classes 1..9;",
        "the first ten rows cover the largest classes, so shorter classes read only a",
        "prefix. Replicated as [mv_ctx][comp].",
    ),
    "DefaultMvFrCdf": (
        "Default_Mv_Fr_Cdf: [comp] over the four quarter-pel fractions shared by",
        "magnitude classes 1..9; replicated per motion vector context.",
    ),
    "DefaultMvHpCdf": (
        "Default_Mv_Hp_Cdf: the one-eighth-pel bit for classes 1..9; replicated as",
        "[mv_ctx][comp].",
    ),
    "DefaultIsInterCdf": (
        "Default_Is_Inter_Cdf: [block context 0..3] from the above and left skip states;",
        "one binary symbol.",
    ),
    "DefaultSkipModeCdf": (
        "Default_Skip_Mode_Cdf: [skip context 0..2] from the above and left neighbours;",
        "one binary symbol.",
    ),
    "DefaultInterpFilterCdf": (
        "Default_Interp_Filter_Cdf: [context 0..15] assembled from the interpolation",
        "direction, whether the second reference frame is forward, and the above/left",
        "filter types; three symbols over the switchable sub-pel filters.",
    ),
    "DefaultUseObmcCdf": (
        "Default_Use_Obmc_Cdf: [block mi_size 0..21]; one binary symbol.",
    ),
    "DefaultMotionModeCdf": (
        "Default_Motion_Mode_Cdf: [block mi_size 0..21][3 symbols] selecting plain",
        "interpolation, OBMC or smooth motion.",
    ),
    "DefaultCompModeCdf": (
        "Default_Comp_Mode_Cdf: [compound context 0..4] from the above/left reference",
        "frames; one binary symbol for single versus compound reference.",
    ),
    "DefaultCompRefTypeCdf": (
        "Default_Comp_Ref_Type_Cdf: [context 0..4] over the above/left compound",
        "reference pairs; two symbols for unidirectional versus bidirectional compound.",
    ),
    "DefaultUniCompRefCdf": (
        "Default_Uni_Comp_Ref_Cdf: [reference-count context 0..2][decision symbol p 0..2]",
        "of the unidirectional compound reference tree; one binary symbol per row.",
    ),
    "DefaultCompRefCdf": (
        "Default_Comp_Ref_Cdf: [reference-count context 0..2][decision symbol p 0..2]",
        "for the forward reference of a bidirectional compound block.",
    ),
    "DefaultCompBwdRefCdf": (
        "Default_Comp_Bwd_Ref_Cdf: [reference-count context 0..2][decision symbol p 0..1]",
        "for the backward reference of a bidirectional compound block.",
    ),
    "DefaultCompoundModeCdf": (
        "Default_Compound_Mode_Cdf: [context 0..7] over the reference frame distances;",
        "eight symbols of the compound prediction mode tree.",
    ),
    "DefaultCompGroupIdxCdf": (
        "Default_Comp_Group_Idx_Cdf: [context 0..5] accumulated from the above/left",
        "neighbours; one binary symbol.",
    ),
    "DefaultCompoundIdxCdf": (
        "Default_Compound_Idx_Cdf: [context 0..5] accumulated from the above/left",
        "neighbours and the reference ordering; one binary symbol.",
    ),
    "DefaultInterIntraCdf": (
        "Default_Inter_Intra_Cdf: [block size group 1..3]; two symbols deciding whether",
        "the inter block also mixes in an intra prediction.",
    ),
    "DefaultInterIntraModeCdf": (
        "Default_Inter_Intra_Mode_Cdf: [block size group 1..3][4 symbols] of the intra",
        "mode blended into the inter block.",
    ),
    "DefaultWedgeInterIntraCdf": (
        "Default_Wedge_Inter_Intra_Cdf: [block mi_size 0..21]; one binary symbol.",
    ),
    "DefaultInterTxTypeSet1Cdf": (
        "Default_Inter_Tx_Type_Set1_Cdf: [transform size class 0..1][16 transform types].",
    ),
    "DefaultInterTxTypeSet2Cdf": (
        "Default_Inter_Tx_Type_Set2_Cdf: one context-free CDF over 12 transform types.",
    ),
    "DefaultInterTxTypeSet3Cdf": (
        "Default_Inter_Tx_Type_Set3_Cdf: [transform size class 0..3]; two symbols.",
    ),
    "DefaultCompoundTypeCdf": (
        "Default_Compound_Type_Cdf: [block mi_size 0..21][2 symbols] choosing the",
        "distance-weighted wedge or the average.",
    ),
    "DefaultWedgeIndexCdf": (
        "Default_Wedge_Index_Cdf: [block mi_size 0..21][16 symbols]; the high wedge bits",
        "come from this CDF and the tail is read with ns(5).",
    ),
    "DefaultYModeCdf": (
        "Default_Y_Mode_Cdf: [size group 0..3][10 luma prediction modes]. An intra block",
        "inside an inter frame selects its row by Size_Group[ MiSize ] instead of using",
        "the above and left modes of an intra frame.",
    ),
}

# Tables whose rows are never re-shaped by the decoder (no [mv_ctx][comp]
# replication) get a factory that copies the shared literal instead of a second
# copy of every probability, which would otherwise sit unused next to it.
DERIVE_FACTORIES = {"DefaultYModeCdf"}

TERMINATOR = (32768, 0)

LICENSE = """BSD 2-Clause License

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

VAR_RE = re.compile(r"^var\s+(\w+)\s*=\s*((?:\[\s*\w*\]\s*)+)(\w+)\s*", re.M)


def moonbit_name(go_name: str) -> str:
    """DefaultMvClass0FrCdf -> av1_mv_class0_fr (and the matching _cdfs suffix)."""
    stem = go_name
    if stem.startswith("Default"):
        stem = stem[len("Default"):]
    if stem.endswith("Cdf"):
        stem = stem[:-len("Cdf")]
    split = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", stem)
    split = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", split)
    return "av1_" + split.lower()


def array_type(depth: int) -> str:
    return "Int" if depth == 0 else "Array[%s]" % array_type(depth - 1)


def literal(values: list, indent: int) -> str:
    """Render one CDF row per line; moonfmt reflows anything too wide."""
    pad = "  " * indent
    if values and not isinstance(values[0], list):
        return "%s[%s]" % (pad, ", ".join(str(v) for v in values))
    lines = [pad + "["]
    for child in values:
        lines.append(literal(child, indent + 1) + ",")
    lines.append(pad + "]")
    return "\n".join(lines)


def shape_of(values: list) -> list[int]:
    shape = []
    node = values
    while isinstance(node, list):
        shape.append(len(node))
        node = node[0] if node else None
    return shape


def check_rows(name: str, values: list, notices: list[str]) -> tuple[int, int]:
    """Validate every innermost CDF row; return the row and element counts."""
    total = 0
    rows: list[list[int]] = []

    def walk(node: list) -> None:
        if any(not isinstance(child, list) for child in node) and any(
            isinstance(child, list) for child in node
        ):
            raise ValueError("%s: ragged nesting mixes rows and values" % name)
        if isinstance(node[0], list):
            widths = {len(child) for child in node}
            if len(widths) > 1:
                notices.append("%s: sibling groups of %s rows" % (name, sorted(widths)))
            for child in node:
                walk(child)
        else:
            rows.append(node)

    walk(values)
    for row in rows:
        total += len(row)
        if len(row) < 3 or any(type(v) is not int for v in row):
            raise ValueError("%s: malformed CDF row %s" % (name, row))
        if tuple(row[-2:]) != TERMINATOR:
            raise ValueError("%s: CDF row lacks the 32768 terminator and 0 counter" % name)
        body = row[:-2]
        if any(a >= b for a, b in zip(body, body[1:])):
            notices.append("%s: non-strictly increasing CDF row %s" % (name, row))
        if row[0] <= 0:
            notices.append("%s: leading cumulative frequency is %d" % (name, row[0]))
    distinct = {tuple(row) for row in rows}
    if len(distinct) < len(rows):
        notices.append(
            "%s: %d of %d CDF rows are duplicates" % (name, len(rows) - len(distinct), len(rows))
        )
    return len(rows), total


def parse_tables(source_dir: str) -> list[dict]:
    """Read every uint16 table literal in the pinned Go sources."""
    tables: list[dict] = []
    for filename, digest in SOURCES:
        path = os.path.join(source_dir, filename)
        data = open(path, "rb").read()
        actual = hashlib.sha256(data).hexdigest()
        if actual != digest:
            raise ValueError(
                "%s: SHA-256 %s, expected %s; re-verify the cache before regenerating"
                % (filename, actual, digest)
            )
        text = data.decode("utf-8").replace("\r\n", "\n")
        for match in VAR_RE.finditer(text):
            go_name, brackets, element = match.group(1), match.group(2), match.group(3)
            if element != "uint16":
                raise ValueError("%s: %s holds %s, not uint16" % (filename, go_name, element))
            depth = brackets.count("[")
            if not 1 <= depth <= 4:
                raise ValueError("%s: %s nests %d levels" % (filename, go_name, depth))
            start = text.index("{", match.end())
            end, open_depth = start + 1, 1
            while open_depth and end < len(text):
                open_depth += (text[end] == "{") - (text[end] == "}")
                end += 1
            if open_depth:
                raise ValueError("%s: unterminated literal for %s" % (filename, go_name))
            body = text[start:end]
            if re.fullmatch(r"[\s\d{},]+", body) is None:
                raise ValueError("%s: non-numeric literal for %s" % (filename, go_name))
            values = ast.literal_eval(body.replace("{", "[").replace("}", "]"))
            tables.append(
                {
                    "go": go_name,
                    "file": filename,
                    "name": moonbit_name(go_name),
                    "depth": depth,
                    "values": values,
                    "derive": go_name in DERIVE_FACTORIES,
                }
            )
    if not tables:
        raise ValueError("no Go tables found in %s" % source_dir)
    seen: dict[str, str] = {}
    for table in tables:
        if table["name"] in seen:
            raise ValueError("%s and %s collide on %s" % (seen[table["name"]], table["go"], table["name"]))
        seen[table["name"]] = table["go"]
        if table["go"] not in DOCS:
            raise ValueError("%s has no doc comment; refusing to emit it undocumented" % table["go"])
        if shape_of(table["values"]) and len(shape_of(table["values"])) != table["depth"]:
            raise ValueError(
                "%s: type declares %d levels, literal has %d"
                % (table["go"], table["depth"], len(shape_of(table["values"])))
            )
    return tables


def render(tables: list[dict]) -> tuple[str, str, list[str]]:
    notices: list[str] = []
    elements = 0
    rows_total = 0
    lines = [
        "// Generated by scripts/generate-av1-inter-tables.py. Do not edit.",
        "// AV1 normative inter defaults; each factory returns fresh mutable CDF rows.",
        "// Source: %s" % SOURCE_URL,
    ]
    for filename, digest in SOURCES:
        lines.append("// %s/%s SHA-256: %s" % (RELATIVE_DIR, filename, digest))
    lines.append("//")
    lines.extend("//" + (" " + line if line else "") for line in LICENSE.splitlines())
    for table in tables:
        rows, elements_in_table = check_rows(table["go"], table["values"], notices)
        rows_total += rows
        elements += elements_in_table
        moon_type = array_type(table["depth"])
        lines.append("///|")
        lines.extend("/// " + text for text in DOCS[table["go"]])
        lines.append("/// Go source: %s in %s, shape %s." % (
            table["go"], table["file"], "x".join(map(str, shape_of(table["values"])))))
        lines.append("let %s : %s = %s" % (table["name"], moon_type, literal(table["values"], 0)))
        lines.append("///|")
        lines.append("/// Fresh %s rows for one tile, so that probability adaptation cannot" % table["go"])
        lines.append("/// corrupt these defaults. Retain the result for the tile's lifetime.")
        lines.append("fn %s_cdfs() -> %s {" % (table["name"], moon_type))
        if table["derive"]:
            lines.append(
                "  Array::makei(%s.length(), i => Array::copy(%s[i]))"
                % (table["name"], table["name"])
            )
        else:
            lines.append(literal(table["values"], 1))
        lines.append("}")
    blocks = []
    for index, line in enumerate(lines):
        if line == "///|" and index:
            blocks.append("")
        blocks.append(line)
    generated = "\n".join(blocks) + "\n"
    summary = "%d tables, %d factories, %d CDF rows, %d elements" % (
        len(tables), len(tables), rows_total, elements)
    return generated, summary, notices


def format_source(source: str, moonfmt: str) -> str:
    """Pipe the generated text through the standalone MoonBit formatter on stdin."""
    proc = subprocess.run(
        [moonfmt, "-"],
        input=source,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=True,
    )
    if not proc.stdout.strip():
        raise ValueError("moonfmt produced no output: %s" % proc.stderr.strip())
    return proc.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or DEFAULT_MOONFMT)
    parser.add_argument("--check", action="store_true",
                        help="verify the committed file without writing it")
    args = parser.parse_args()
    moonfmt = shutil.which(args.moonfmt)
    if moonfmt is None:
        parser.error("MoonBit formatter not found: %s; supply --moonfmt path/to/moonfmt"
                     % args.moonfmt)
    generated, summary, notices = render(parse_tables(args.source_dir))
    formatted = format_source(generated, moonfmt)
    if args.check:
        current = ""
        if os.path.exists(args.output):
            current = open(args.output, encoding="utf-8", newline="").read().replace("\r\n", "\n")
        if current != formatted:
            raise SystemExit(
                "%s is stale: the cached Go tables or this generator changed.\n"
                "Regenerate it with: python scripts/generate-av1-inter-tables.py"
                % os.path.basename(args.output))
        print("reproducibility check passed: %s (%s)" % (args.output, summary))
        return 0
    with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(formatted)
    print("wrote %s (%d bytes, %s)" % (args.output, len(formatted), summary))
    for notice in notices:
        print("note: %s" % notice)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
