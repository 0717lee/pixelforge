#!/usr/bin/env python3
"""Generate AV1 inverse matrices and goldens from pinned dav1d 1.2.1 C.

    python scripts/generate-av1-qmatrix.py
    python scripts/generate-av1-qmatrix.py --check

Requires Python 3, standalone moonfmt, and a C compiler (cc/gcc, or MoonBit's
bundled tcc on Windows). --source-dir may point at dav1d's src directory. Missing sources
are downloaded to a temporary cache; all three original source hashes are
checked. --check never writes generated repository files.

The production tables are parsed from the static C initializers. Separately,
the ORIGINAL dav1d matrix initialization functions are compiled and executed
to verify every matrix value, including rectangular transposition, 16x16
subsampling, and adjusted 64-dimensional transforms. Generated white-box
tests compare an order-sensitive FNV-1a digest of every expanded matrix.

Dequantization expectations execute the ORIGINAL dc qmatrix branch of
recon_tmpl.c. Only debug printing is removed; a read_golomb macro supplies the
already-decoded coefficient magnitude. This isolates quantization arithmetic
without copying MoonBit's implementation into the oracle. Stress coefficients
fit the syntax's 20-bit magnitude; they are not claims of encoder reachability.
Generated MoonBit tests have no compiler, network or external-file dependency.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://raw.githubusercontent.com/videolan/dav1d/1.2.1/src/"
HASHES = {
    "qm.c": "f314f348dd71b4f11b9ca7441561eb9c018134965e315158dd7595103d6a7816",
    "levels.h": "098f40ddfcdc452338bbbb292d8fd21cac2a5bac9553597f100a998d8ade1260",
    "recon_tmpl.c": "1c238930db8ca79753b9439b39b5e96dd4adddde41dd40d4fc3c774607d6e72f",
}
TABLES = ("4x4_t", "8x4", "8x8_t", "16x4", "16x8", "32x8", "32x16", "32x32_t")
SIZES = ((4, 4), (8, 8), (16, 16), (32, 32), (64, 64),
         (4, 8), (8, 4), (8, 16), (16, 8), (16, 32), (32, 16),
         (32, 64), (64, 32), (4, 16), (16, 4), (8, 32), (32, 8),
         (16, 64), (64, 16))


def sources(directory: Path) -> dict[str, str]:
    result = {}
    for name, expected in HASHES.items():
        path = directory / name
        if path.exists():
            data = path.read_bytes()
        else:
            with urllib.request.urlopen(SOURCE_URL + name, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise RuntimeError(f"Unexpected downloaded {name} source hash")
            directory.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise RuntimeError(f"{name}: SHA-256 {actual}, expected {expected}")
        result[name] = data.decode("utf-8")
    return result


def braced(source: str, marker: str) -> str:
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def static_tables(source: str) -> dict[str, list[bytes]]:
    result = {}
    for name in TABLES:
        declaration = braced(source, "static const uint8_t qm_tbl_" + name + "[")
        count = int(re.search(r"\[\]\[2\]\[(\d+)\]", declaration)[1])
        values = list(map(int, re.findall(r"\d+", declaration.split("{", 1)[1])))
        if len(values) != 30 * count:
            raise RuntimeError(f"Unexpected {name} table size: {len(values)}")
        result[name] = [bytes(values[i:i + count]) for i in range(0, len(values), count)]
    return result


def row_major(tables: dict[str, list[bytes]], level: int, plane: int,
              width: int, height: int) -> bytes:
    width, height = min(32, width), min(32, height)
    index = level * 2 + plane
    if width == height:
        name = f"{width}x{width}_t" if width != 16 else "32x32_t"
        step = 2 if width == 16 else 1
        result = []
        for row in range(height):
            for col in range(width):
                hi, lo = sorted((row * step, col * step), reverse=True)
                result.append(tables[name][index][hi * (hi + 1) // 2 + lo])
        return bytes(result)
    wide, short = max(width, height), min(width, height)
    matrix = tables[f"{wide}x{short}"][index]
    return bytes(matrix[row * wide + col] if width > height else matrix[col * wide + row]
                 for row in range(height) for col in range(width))


def c_oracle(source: dict[str, str]) -> str:
    enums = "\n".join(braced(source["levels.h"], "enum " + name) + ";"
                      for name in ("TxfmSize", "RectTxfmSize"))
    matrices = re.sub(r"^#include[^\n]*", "", source["qm.c"], flags=re.M)
    recon = source["recon_tmpl.c"]
    start = recon.index("        dc_dq = (dc_dq * qm_tbl[0] + 16) >> 5;")
    end = recon.index("        if (rc) ac_qm:", start)
    dequant = recon[start:end]
    # The debug branch is an unbraced printf; remove only that statement.
    dequant = re.sub(r"\s*if \(dbg\)\s*printf\(.*?ts->msac.rng\);", "", dequant, flags=re.S)
    return """/* Header-free declarations also support MoonBit's bundled TinyCC. */
typedef unsigned char uint8_t;
typedef signed int int32_t;
extern int printf(const char *, ...);
extern int putchar(int);
extern void abort(void);
extern void *memcpy(void *, const void *, unsigned long long);
#define assert(condition) ((condition) ? (void)0 : abort())
#define COLD
#define umin(a,b) ((a) < (b) ? (a) : (b))
typedef int32_t coef;
""" + enums + "\n" + matrices + """
static int oracle_dequant(int value, int q, uint8_t weight, int shift, int depth) {
    unsigned magnitude = value < 0 ? -value : value;
    unsigned oracle_extra = magnitude >= 15 ? magnitude - 15 : 0;
    unsigned dc_tok = magnitude >= 15 ? 15 : magnitude;
    int dc_dq = q;
    int dc_sign = value < 0;
    int dq_shift = shift;
    unsigned cf_max = (1U << (7 + depth)) - 1;
    const uint8_t *qm_tbl = &weight;
    unsigned cul_level;
    coef cf[1];
#define read_golomb(ignored) oracle_extra
""" + dequant + """
#undef read_golomb
    return cf[0];
}
int main(void) {
    static const int sizes[19][2] = {
""" + ",\n".join(f"        {{{w},{h}}}" for w, h in SIZES) + r"""
    };
    dav1d_init_qm_tables();
    for (int level = 0; level < 15; level++)
        for (int plane = 0; plane < 2; plane++)
            for (int tx = 0; tx < 19; tx++) {
                const int w = sizes[tx][0] < 32 ? sizes[tx][0] : 32;
                const int h = sizes[tx][1] < 32 ? sizes[tx][1] : 32;
                const uint8_t *data = dav1d_qm_tbl[level][plane][tx];
                printf("M %d %d %d ", level, plane, tx);
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++)
                        printf("%02x", data[x * h + y]);
                putchar('\n');
            }
    static const int depths[3] = {8,10,12};
    static const int quantizers[3] = {1828,7312,29247};
    static const int weights[4] = {1,32,63,255};
    static const int values[14] = {1,-1,14,-14,15,-15,511,-511,
                                  65537,-65537,524289,-524289,1048575,-1048575};
    for (int b = 0; b < 3; b++)
        for (int w = 0; w < 4; w++)
            for (int shift = 0; shift < 3; shift++)
                for (int v = 0; v < 14; v++)
                    printf("D %d %d %d %d %d %d\n", depths[b], quantizers[b],
                           weights[w], 1 << shift, values[v],
                           oracle_dequant(values[v], quantizers[b], weights[w], shift, depths[b]));
    return 0;
}
"""


def fnv(data: bytes) -> int:
    value = 2166136261
    for byte in data:
        value = ((value ^ byte) * 16777619) & 0xffffffff
    return value


def table_text(source: str, tables: dict[str, list[bytes]]) -> str:
    license_text = source[:source.index("*/") + 2]
    lines = ["// Generated by scripts/generate-av1-qmatrix.py. Do not edit.",
             "// Source: dav1d 1.2.1 src/qm.c, SHA-256 " + HASHES["qm.c"],
             "// Tables: [level * 2 + chroma][position]. Rectangles are row-major."]
    for line in license_text.splitlines()[1:-1]:
        lines.append("//" + re.sub(r"^ \*", "", line))
    for name, matrices in tables.items():
        lines.extend(("", "///|", f"let av1_qmatrix_{name} : Array[Bytes] = ["))
        lines.extend('  b"' + ''.join(f"\\x{byte:02x}" for byte in matrix) + '",'
                     for matrix in matrices)
        lines.append("]")
    return "\n".join(lines) + "\n"


def test_text(hashes: list[int], dequant: list[list[int]]) -> str:
    lines = ["// Generated by scripts/generate-av1-qmatrix.py. Do not edit.",
             "// Matrix hashes: original dav1d 1.2.1 qm.c initialization, transposed",
             "// from dav1d coefficient storage into MoonBit's row-major domain.",
             "// Dequant goldens: original recon_tmpl.c dc qmatrix branch.",
             "// Source SHA-256: qm.c " + HASHES["qm.c"],
             "// Source SHA-256: recon_tmpl.c " + HASHES["recon_tmpl.c"],
             "", "///|", 'test "all qmatrix levels planes and sizes match native dav1d" {',
             "  let sizes : Array[(Int, Int)] = ["]
    lines.extend(f"    ({w}, {h})," for w, h in SIZES)
    lines.extend(("  ]", "  let expected : Array[Int64] = ["))
    for start in range(0, len(hashes), 6):
        lines.append("    " + ", ".join(str(value) + "L" for value in hashes[start:start + 6]) + ",")
    lines.extend(("  ]", "  let mut case_index = 0", "  for level in 0..<15 {",
                  "    for plane in 0..<2 {", "      for size in sizes {",
                  "        let (width, height) = size",
                  "        let dw = if width > 32 { 32 } else { width }",
                  "        let dh = if height > 32 { 32 } else { height }",
                  "        let mut hash = 2166136261L", "        for pos in 0..<(dw * dh) {",
                  "          let weight = av1_qmatrix_weight(level, plane, width, height, pos)",
                  "          hash = ((hash ^ weight.to_int64()) * 16777619L) & 0xFFFFFFFFL",
                  "          if plane == 1 {",
                  "            assert_eq(av1_qmatrix_weight(level, 2, width, height, pos), weight)",
                  "          }", "        }", "        assert_eq(hash, expected[case_index])",
                  "        case_index = case_index + 1", "      }", "    }", "  }", "}",
                  "", "///|", 'test "qmatrix dequantization matches native dav1d across bit depths" {',
                  "  // [bit depth, scalar q, weight, denominator, coefficient, expected].",
                  "  let cases : Array[Array[Int]] = ["))
    lines.extend("    [" + ", ".join(map(str, case)) + "]," for case in dequant)
    lines.extend(("  ]", "  for row in cases {",
                  "    assert_eq(av1_ac_quant(row[0], 255), row[1])",
                  "    let q2 = av1_qmatrix_quant(row[1], row[2])",
                  "    assert_eq(av1_dequant_clip(row[4], q2, row[3].to_int64(), row[0]), row[5])",
                  "  }", "}", ""))
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path,
                        default=Path(tempfile.gettempdir()) / "pixelforge-dav1d-qmatrix-1.2.1")
    bundled_tcc = Path.home() / ".moon/bin/internal/tcc.exe"
    parser.add_argument("--cc", default=shutil.which("cc") or shutil.which("gcc") or
                        (str(bundled_tcc) if bundled_tcc.exists() else "cc"))
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or "moonfmt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = sources(args.source_dir)
    tables = static_tables(source["qm.c"])
    with tempfile.TemporaryDirectory(prefix="pixelforge-qmatrix-oracle-") as directory:
        path = Path(directory)
        c_file = path / "oracle.c"
        c_file.write_text(c_oracle(source), encoding="utf-8")
        executable = path / "oracle.exe"
        command = [args.cc]
        compiler_path = Path(args.cc).resolve()
        moon_root = compiler_path.parent.parent.parent
        if compiler_path.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command.extend(["-B", str(moon_root)])
        command.extend(["-std=c99", "-o", str(executable), str(c_file)])
        subprocess.run(command, check=True)
        output = subprocess.check_output([str(executable)], text=True)
    hashes, dequant = [], []
    coefficients = 0
    for line in output.splitlines():
        fields = line.split()
        if fields[0] == "M":
            level, plane, tx = map(int, fields[1:4])
            original = bytes.fromhex(fields[4])
            expected = row_major(tables, level, plane, *SIZES[tx])
            if original != expected:
                raise RuntimeError(f"Matrix differs from native dav1d: {level=}, {plane=}, {tx=}")
            hashes.append(fnv(original))
            coefficients += len(original)
        elif fields[0] == "D":
            dequant.append(list(map(int, fields[1:])))
        else:
            raise RuntimeError(f"Unexpected oracle line: {line}")
    if len(hashes) != 570 or len(dequant) != 504:
        raise RuntimeError("Incomplete native oracle output")
    outputs = {
        ROOT / "av1_qmatrix_tables.mbt": table_text(source["qm.c"], tables),
        ROOT / "av1_qmatrix_reference_wbtest.mbt": test_text(hashes, dequant),
    }
    for path, content in outputs.items():
        content = subprocess.run([args.moonfmt, "-"], input=content, text=True,
                                 encoding="utf-8", capture_output=True, check=True).stdout
        if args.check:
            if path.read_text(encoding="utf-8") != content:
                raise RuntimeError(f"Generated file is stale: {path.name}")
        else:
            path.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(hashes)} matrices, {coefficients} weights, and {len(dequant)} dequant cases against native dav1d 1.2.1.")
    print("Generated files match." if args.check else "Generated tables and white-box tests.")


if __name__ == "__main__":
    main()
