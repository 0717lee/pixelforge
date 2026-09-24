#!/usr/bin/env python3
"""Generate bare AV1 palette-index references from the pinned original AOM C.

The original context function supplies every rank permutation. Independent
Python MSAC streams are checked by the original C palette decoder and writer.
This is an index-syntax corpus, not an OBU encoder or full-image pixel oracle.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
REVISION = "8e7b6a567df174d795479b92b4ac766d271add73"
MARKER = 0xA5D3
SOURCES = [
    "av1/common/entropymode.c", "av1/common/entropymode.h",
    "av1/common/blockd.h", "av1/common/common.h", "av1/common/enums.h",
    "av1/decoder/detokenize.c", "av1/decoder/decoder.h",
    "av1/encoder/bitstream.c", "aom_dsp/entcode.c", "aom_dsp/entdec.c",
    "aom_dsp/entenc.c", "aom_dsp/bitreader.c", "aom_dsp/bitwriter.c",
]
COMPILE_SOURCES = ["aom_dsp/" + name + ".c" for name in
                   ("entcode", "entdec", "entenc", "bitreader", "bitwriter")]
CONFIG = """/* Standalone entropy-only oracle configuration. */
#define CONFIG_ACCOUNTING 0
#define CONFIG_BITSTREAM_DEBUG 0
#define CONFIG_RD_DEBUG 0
#define CONFIG_AV1_HIGHBITDEPTH 1
#define CONFIG_REALTIME_ONLY 0
#define ARCH_X86_64 1
#define ARCH_X86 0
/* WORDS_BIGENDIAN must be undefined on this little-endian host. */
#define INLINE inline
"""


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_text(value) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def run(command, **kwargs):
    if kwargs.get("text"):
        kwargs.setdefault("encoding", "utf-8")
    return subprocess.run(command, check=True, capture_output=True, **kwargs)


def arithmetic_module():
    spec = importlib.util.spec_from_file_location("palette_index_msac", ROOT / "scripts/craft_av1_fixture.py")
    assert spec and spec.loader
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def default_compiler():
    if shutil.which("cc"):
        return shutil.which("cc")
    visual_studio = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio"
    available = sorted(visual_studio.glob("*/BuildTools/VC/Tools/MSVC/*/bin/Hostx64/x64/cl.exe"))
    return str(available[-1]) if available else "cc"


def balanced(text: str, token: str, declaration=False) -> str:
    start = text.index(token)
    opening = text.index("{", start)
    depth = 0
    for end in range(opening, len(text)):
        if text[end] == "{":
            depth += 1
        elif text[end] == "}":
            depth -= 1
            if depth == 0:
                return text[start:end + 1 + int(declaration)]
    raise RuntimeError(f"unterminated original source fragment: {token}")


def source_files(source_dir: Path):
    revision = run(["git", "-C", str(source_dir), "rev-parse", "HEAD"], text=True).stdout.strip()
    if revision != REVISION:
        raise RuntimeError(f"AOM revision {revision}; expected {REVISION}")
    names = set(SOURCES)
    pending = list(names)
    # Record original local headers reached by quoted includes as provenance.
    while pending:
        name = pending.pop()
        text = (source_dir / name).read_text(encoding="utf-8")
        for include in re.findall(r'^\s*#\s*include\s+"([^"]+)"', text, re.M):
            if include not in names and (source_dir / include).is_file():
                names.add(include)
                pending.append(include)
    run(["git", "-C", str(source_dir), "diff", "--exit-code", REVISION, "--", *sorted(names)])
    return {name: (source_dir / name).read_text(encoding="utf-8") for name in sorted(names)}


C_MAIN = r'''
static void emit_cdf(MapCdf cdf, int n) {
  for (int k = 0; k < 5; ++k) {
    for (int j = 0; j < n; ++j) printf(" %d", 32768 - cdf[n - 2][k][j]);
    printf(" %d", cdf[n - 2][k][n]);
  }
}
static void print_hex(const uint8_t *data, int size) {
  for (int i = 0; i < size; ++i) printf("%02x", data[i]);
}
static int read_hex(const char *hex, uint8_t *data, int capacity) {
  int length = (int)strlen(hex);
  assert(!(length & 1) && length / 2 <= capacity);
  for (int i = 0; i < length / 2; ++i) {
    unsigned int value;
    assert(sscanf(hex + i * 2, "%2x", &value) == 1);
    data[i] = value;
  }
  return length / 2;
}
int main(void) {
  char command[8];
  while (scanf("%7s", command) == 1) {
    if (command[0] == 'C') {
      int n, kind, left, top_left, top;
      assert(scanf("%d%d%d%d%d", &n, &kind, &left, &top_left, &top) == 5);
      uint8_t map[9] = { 0 }, order[8], inverse_order[8];
      int row = kind == 0 ? 0 : 1, col = kind == 1 ? 0 : 1;
      if (left >= 0) map[row * 3 + col - 1] = left;
      if (top >= 0) map[(row - 1) * 3 + col] = top;
      if (top_left >= 0) map[(row - 1) * 3 + col - 1] = top_left;
      int context = av1_get_palette_color_index_context(map, 3, row, col, n, order, NULL);
      for (int value = 0; value < n; ++value) {
        int rank = -1;
        map[row * 3 + col] = value;
        assert(av1_get_palette_color_index_context(map, 3, row, col, n,
                                                   inverse_order, &rank) == context);
        assert(!memcmp(order, inverse_order, 8));
        assert(rank >= 0 && rank < n && order[rank] == value);
      }
      printf("C %d", context);
      for (int i = 0; i < 8; ++i) printf(" %d", order[i]);
      printf("\n");
    } else if (command[0] == 'T') {
      int plane, n;
      assert(scanf("%d%d", &plane, &n) == 2);
      aom_cdf_prob cdf[7][5][9];
      memcpy(cdf, plane ? default_palette_uv_color_index_cdf : default_palette_y_color_index_cdf,
             sizeof(cdf));
      printf("T"); emit_cdf(cdf, n); printf("\n");
    } else if (command[0] == 'V') {
      int n, plane, allow_update, map_count;
      char input_hex[65536];
      uint8_t input[32768], output[32768];
      assert(scanf("%d%d%d%d%65535s", &n, &plane, &allow_update, &map_count, input_hex) == 5);
      int size = read_hex(input_hex, input, sizeof(input));
      aom_cdf_prob decode_cdf[7][5][9], encode_cdf[7][5][9];
      memcpy(decode_cdf, plane ? default_palette_uv_color_index_cdf : default_palette_y_color_index_cdf,
             sizeof(decode_cdf));
      memcpy(encode_cdf, decode_cdf, sizeof(encode_cdf));
      aom_reader reader;
      assert(aom_reader_init(&reader, input, size) == 0);
      reader.allow_update_cdf = allow_update;
      aom_writer writer;
      aom_start_encode(&writer, output, sizeof(output));
      writer.allow_update_cdf = allow_update;
      for (int index = 0; index < map_count; ++index) {
        int width, height, rows, cols;
        uint8_t expected[4096], decoded[4096], order[8];
        char map_hex[8193];
        assert(scanf("%d%d%d%d%8192s", &width, &height, &rows, &cols, map_hex) == 5);
        assert(read_hex(map_hex, expected, sizeof(expected)) == width * height);
        memset(decoded, 255, sizeof(decoded));
        Av1ColorMapParam param = { rows, cols, n, width, height, decoded, decode_cdf, NULL };
        decode_color_map_tokens(&param, &reader);
        int marker = aom_read_literal(&reader, 16, ACCT_STR);
        assert(marker == 0xA5D3 && !memcmp(decoded, expected, width * height));
        write_uniform(&writer, n, expected[0]);
        for (int diagonal = 1; diagonal < rows + cols - 1; ++diagonal) {
          for (int col = AOMMIN(diagonal, cols - 1); col >= AOMMAX(0, diagonal - rows + 1); --col) {
            int rank;
            int context = av1_get_palette_color_index_context(expected, width,
                diagonal - col, col, n, order, &rank);
            aom_write_symbol(&writer, rank, encode_cdf[n - 2][context], n);
          }
        }
        aom_write_literal(&writer, 0xA5D3, 16);
        assert(!memcmp(decode_cdf, encode_cdf, sizeof(decode_cdf)));
        printf("V %d %d ", index, marker);
        print_hex(decoded, width * height);
        emit_cdf(decode_cdf, n); printf("\n");
      }
      assert(!aom_reader_has_overflowed(&reader));
      int written = aom_stop_encode(&writer);
      assert(written >= 0 && writer.pos <= sizeof(output));
      printf("W "); print_hex(output, writer.pos); printf("\n");
    } else {
      fprintf(stderr, "unexpected command %s\n", command);
      return 2;
    }
  }
  return 0;
}
'''


def oracle_source(sources):
    fragments = []
    parts = ["""/* Original AOM fragments retain their BSD-2-Clause and Patent licenses. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#ifdef NDEBUG
#error The palette oracle requires active C assertions.
#endif
#include "aom_dsp/bitreader.h"
#include "aom_dsp/bitwriter.h"
#define PALETTE_MAX_SIZE 8
#define PALETTE_MIN_SIZE 2
#define PALETTE_SIZES 7
#define PALETTE_COLORS 8
#define PALETTE_COLOR_INDEX_CONTEXTS 5
#define NUM_PALETTE_NEIGHBORS 3
#define MAX_COLOR_CONTEXT_HASH 8
#define ACCT_STR __func__
"""]

    def extract(name, token, declaration=False):
        fragment = balanced(sources[name], token, declaration)
        parts.append(fragment)
        fragments.append({"source": name, "start_line": sources[name][:sources[name].index(token)].count("\n") + 1,
                          "token": token, "sha256": sha(fragment.encode())})

    for plane in ("y", "uv"):
        extract("av1/common/entropymode.c", "static const aom_cdf_prob default_palette_" + plane + "_color_index_cdf", True)
    extract("av1/common/entropymode.c", "const int av1_palette_color_index_context_lookup[", True)
    extract("av1/common/entropymode.c", "int av1_get_palette_color_index_context(")
    blockd = sources["av1/common/blockd.h"]
    start = blockd.index("typedef aom_cdf_prob (*MapCdf)")
    end = blockd.index("} Av1ColorMapParam;", start) + len("} Av1ColorMapParam;")
    parts.append(blockd[start:end])
    fragments.append({"source": "av1/common/blockd.h", "start_line": blockd[:start].count("\n") + 1,
                      "token": "MapCdf/ColorCost/Av1ColorMapParam", "sha256": sha(blockd[start:end].encode())})
    extract("av1/common/common.h", "static inline int get_unsigned_bits(")
    extract("av1/decoder/decoder.h", "static inline int av1_read_uniform(")
    extract("av1/encoder/bitstream.c", "static inline void write_uniform(")
    extract("av1/decoder/detokenize.c", "static void decode_color_map_tokens(")
    parts.append(C_MAIN)
    return "\n\n".join(parts), fragments


def compile_oracle(args, source, temporary):
    compiler = Path(shutil.which(args.cc) or args.cc).resolve()
    (temporary / "config").mkdir()
    (temporary / "config/aom_config.h").write_text(CONFIG, encoding="utf-8", newline="\n")
    (temporary / "oracle.c").write_text(source, encoding="utf-8", newline="\n")
    executable = temporary / "oracle.exe"
    command = [str(compiler)]
    environment = os.environ.copy()
    if compiler.name.lower() == "cl.exe":
        environment["VSLANG"] = "1033"
        msvc_root = compiler.parents[3]
        sdk_root = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Windows Kits/10"
        sdk_include = sorted(path for path in (sdk_root / "Include").iterdir() if (path / "ucrt/stdio.h").is_file())[-1]
        command += ["/nologo", "/std:c11", "/O2", "/D_CRT_SECURE_NO_WARNINGS"]
        for path in (temporary, args.source_dir, msvc_root / "include", sdk_include / "ucrt", sdk_include / "shared", sdk_include / "um"):
            command += ["/I" + str(path)]
        command += [str(temporary / "oracle.c"), *[str(args.source_dir / name) for name in COMPILE_SOURCES]]
        command += ["/Fe:" + str(executable), "/Fo:" + str(temporary) + os.sep, "/link"]
        for path in (msvc_root / "lib/x64", sdk_root / "Lib" / sdk_include.name / "ucrt/x64", sdk_root / "Lib" / sdk_include.name / "um/x64"):
            command += ["/LIBPATH:" + str(path)]
        environment["PATH"] = str(compiler.parent) + os.pathsep + environment.get("PATH", "")
    else:
        moon_root = compiler.parent.parent.parent
        if compiler.parent.name == "internal" and (moon_root / "lib/libtcc1.a").exists():
            command += ["-B", str(moon_root)]
        command += ["-I", str(temporary), "-I", str(args.source_dir), str(temporary / "oracle.c")]
        command += [str(args.source_dir / name) for name in COMPILE_SOURCES]
        command += ["-o", str(executable)]
    print("Compiling original AOM entropy coder and palette map decoder", flush=True)
    try:
        compiled = run(command, text=True, env=environment, cwd=temporary)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(error.stderr or error.stdout) from error
    version = run([str(compiler), "/?" if compiler.name.lower() == "cl.exe" else "-v"], text=True, env=environment)
    return executable, {"path": str(compiler), "sha256": sha(compiler.read_bytes()),
                        "version": "\n".join((version.stderr + version.stdout).strip().splitlines()[:3]),
                        "command": [part.replace(str(temporary), "<temporary>") for part in command],
                        "diagnostics": compiled.stdout + compiled.stderr}


def query(executable, lines):
    try:
        result = run([str(executable)], input="\n".join(lines) + "\n", text=True)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"original C oracle failed: {error.returncode}\n{error.stderr}\n{error.stdout[-2000:]}") from error
    return result.stdout.splitlines()


def context_inputs():
    for n in range(2, 9):
        for value in range(n):
            yield n, 0, value, -1, -1
            yield n, 1, -1, -1, value
        for left, top_left, top in itertools.product(range(n), repeat=3):
            yield n, 2, left, top_left, top


def read_contexts(binary):
    if len(binary) != 1365 * 14:
        raise RuntimeError("exhaustive context corpus extent changed")
    result = {}
    for offset in range(0, len(binary), 14):
        n, kind, left, top_left, top, context, *order = binary[offset:offset + 14]
        left, top_left, top = (value if value != 255 else -1 for value in (left, top_left, top))
        result[n, left, top_left, top] = (context, order)
    if len(result) != 1365:
        raise RuntimeError("duplicate context input")
    return result


def get_context_oracles(executable, sources):
    inputs = list(context_inputs())
    lines = query(executable, ["C " + " ".join(map(str, item)) for item in inputs] +
                  [f"T {plane} {n}" for plane in range(2) for n in range(2, 9)])
    if len(lines) != len(inputs) + 14:
        raise RuntimeError("original C context/default row count changed")
    binary = bytearray()
    for item, line in zip(inputs, lines):
        fields = line.split()
        if fields[0] != "C" or len(fields) != 10:
            raise RuntimeError("invalid original C context record")
        context, *order = map(int, fields[1:])
        if sorted(order) != list(range(8)) or not 0 <= context < 5:
            raise RuntimeError("invalid original C full color order/context")
        binary.extend(value & 255 for value in (*item, context, *order))
    defaults = []
    for plane in range(2):
        table = balanced(sources["av1/common/entropymode.c"],
                         "static const aom_cdf_prob default_palette_" + ("y" if plane == 0 else "uv") + "_color_index_cdf", True)
        parsed = re.findall(r"AOM_CDF([2-8])\(([^)]+)\)", table)
        if len(parsed) != 35:
            raise RuntimeError("original default palette CDF table changed")
        groups = []
        for n in range(2, 9):
            fields = lines[len(inputs) + plane * 7 + n - 2].split()
            values = list(map(int, fields[1:]))
            if fields[0] != "T" or len(values) != 5 * (n + 1):
                raise RuntimeError("invalid C default palette CDF output")
            rows = [values[k * (n + 1):(k + 1) * (n + 1)] for k in range(5)]
            for k, row in enumerate(rows):
                arity, text = parsed[(n - 2) * 5 + k]
                expected = [int(value.strip()) for value in text.split(",")] + [32768, 0]
                if int(arity) != n or row != expected:
                    raise RuntimeError("C/Python original CDF extraction differs")
            groups.append(rows)
        defaults.append(groups)
    return bytes(binary), defaults


def literal(encoder, value, bits):
    for bit in range(bits - 1, -1, -1):
        encoder.write_bool((value >> bit) & 1)


def uniform(encoder, value, n):
    bits = n.bit_length()
    split = (1 << bits) - n
    if value < split:
        literal(encoder, value, bits - 1)
    else:
        literal(encoder, split + (value - split) // 2, bits - 1)
        literal(encoder, (value - split) & 1, 1)


def read_literal(decoder, bits):
    value = 0
    for _ in range(bits):
        value = (value << 1) | decoder.bool()
    return value


def read_uniform(decoder, n):
    bits, split = n.bit_length(), (1 << n.bit_length()) - n
    value = read_literal(decoder, bits - 1)
    return value if value < split else value * 2 - split + decoder.bool()


def wavefront(rows, cols):
    for diagonal in range(1, rows + cols - 1):
        for col in range(min(diagonal, cols - 1), max(0, diagonal - rows + 1) - 1, -1):
            yield diagonal - col, col


def context_at(contexts, indices, width, row, col, n):
    return contexts[n, indices[row * width + col - 1] if col else -1,
                    indices[(row - 1) * width + col - 1] if row and col else -1,
                    indices[(row - 1) * width + col] if row else -1]


def padded_map(n, width, height, rows, cols, seed, first):
    indices = [255] * (width * height)
    state = seed
    for row in range(rows):
        for col in range(cols):
            state = (1664525 * state + 1013904223) & 0xFFFFFFFF
            indices[row * width + col] = ((state >> 16) ^ (row * 3 + col)) % n
    for row, values in enumerate(((0, 0, 1), (0, 1, 0), (0, 2 % n, 0))):
        indices[row * width:row * width + 3] = values
    free = [(row, col) for row in range(rows) for col in range(cols) if row >= 3 or col >= 3]
    for i, (row, col) in enumerate(free[:n - 1]):
        indices[row * width + col] = (i + 1) % n
    indices[0] = first
    pad(indices, width, height, rows, cols)
    return indices


def pad(indices, width, height, rows, cols):
    for row in range(rows):
        indices[row * width + cols:(row + 1) * width] = [indices[row * width + cols - 1]] * (width - cols)
    for row in range(rows, height):
        indices[row * width:(row + 1) * width] = indices[(rows - 1) * width:rows * width]


def make_streams(defaults, contexts, arithmetic):
    streams, maps, cases = bytearray(), bytearray(), []
    for n, plane, active in itertools.product(range(2, 9), range(2), (False, True)):
        shapes = (((8, 8, 8, 8), (32, 16, 16, 24), (16, 32, 24, 16), (32, 32, 24, 24)) if plane == 0 else
                  ((4, 4, 4, 4), (16, 8, 8, 12), (8, 16, 12, 8), (16, 16, 12, 12)))
        case = {"index": len(cases), "palette_size": n, "plane": plane, "allow_update": active,
                "stream_offset": len(streams), "maps": []}
        encoder = arithmetic.MsacEncoder()
        encoder.allow_update = active
        cdfs = [row.copy() for row in defaults[plane][n - 2]]
        for index, (width, height, rows, cols) in enumerate(shapes):
            first = (0, n - 1, n // 2, max(0, n - 2))[index]
            seed = 1709 + n * 97 + plane * 17 + index * 31
            indices = padded_map(n, width, height, rows, cols, seed, first)
            context_counts, rank_counts = [0] * 5, [0] * n
            uniform(encoder, indices[0], n)
            for row, col in wavefront(rows, cols):
                context, order = context_at(contexts, indices, width, row, col, n)
                rank = order.index(indices[row * width + col])
                encoder.encode_symbol(cdfs[context], rank)
                context_counts[context] += 1
                rank_counts[rank] += 1
            literal(encoder, MARKER, 16)
            binary = bytes(indices)
            case["maps"].append({"index": index, "width": width, "height": height, "rows": rows, "cols": cols,
                                 "seed": seed, "first_index": first, "map_offset": len(maps), "map_size": len(binary),
                                 "map_sha256": sha(binary), "context_counts": context_counts, "rank_counts": rank_counts,
                                 "symbol_count": rows * cols - 1, "marker": MARKER,
                                 "ending_cdfs": [row.copy() for row in cdfs]})
            maps.extend(binary)
        stream = encoder.finish()
        case.update(stream_size=len(stream), stream_sha256=sha(stream))
        streams.extend(stream)
        cases.append(case)
    return cases, bytes(streams), bytes(maps)


def verify_python(cases, streams, maps, defaults, contexts, arithmetic):
    totals = [0] * 5
    for case in cases:
        n, plane = case["palette_size"], case["plane"]
        stream = streams[case["stream_offset"]:case["stream_offset"] + case["stream_size"]]
        if sha(stream) != case["stream_sha256"]:
            raise RuntimeError("stream hash mismatch")
        decoder = arithmetic.MsacDecoder(stream, allow_update=case["allow_update"])
        cdfs = [row.copy() for row in defaults[plane][n - 2]]
        observed_contexts = set()
        for item in case["maps"]:
            width, height, rows, cols = (item[key] for key in ("width", "height", "rows", "cols"))
            indices = [255] * (width * height)
            indices[0] = read_uniform(decoder, n)
            counts, ranks = [0] * 5, [0] * n
            for row, col in wavefront(rows, cols):
                context, order = context_at(contexts, indices, width, row, col, n)
                rank = decoder.symbol(cdfs[context])
                indices[row * width + col] = order[rank]
                counts[context] += 1
                ranks[rank] += 1
            pad(indices, width, height, rows, cols)
            expected = maps[item["map_offset"]:item["map_offset"] + item["map_size"]]
            if bytes(indices) != expected or sha(expected) != item["map_sha256"]:
                raise RuntimeError("Python MSAC decoded palette map differs")
            if counts != item["context_counts"] or ranks != item["rank_counts"]:
                raise RuntimeError("context/rank coverage differs")
            if read_literal(decoder, 16) != MARKER or cdfs != item["ending_cdfs"]:
                raise RuntimeError("marker or ending CDF mismatch")
            if not case["allow_update"] and cdfs != defaults[plane][n - 2]:
                raise RuntimeError("frozen CDF changed")
            observed_contexts |= {k for k, count in enumerate(counts) if count}
            totals = [a + b for a, b in zip(totals, counts)]
        required = {0, 2, 3, 4} if n == 2 else set(range(5))
        if observed_contexts != required:
            raise RuntimeError(f"missing reachable contexts in stream {case['index']}: {observed_contexts}")
    return {"context_cases": len(contexts), "original_c_inverse_rank_checks": sum(n * (n ** 3 + 2 * n) for n in range(2, 9)),
            "stream_cases": len(cases), "map_cases": sum(len(c["maps"]) for c in cases),
            "context_symbol_counts": totals, "context1_unreachable_for_palette_size2": True,
            "first_index_is_ns": True, "markers_checked_after_every_map": True,
            "shared_cdf_maps_per_stream": 4, "padding": ["none", "right", "bottom", "right_and_bottom"],
            "decoded_mi_geometry": "Y 8/32/16 dimensions with 24-pixel prefixes; UV half dimensions with 12-pixel prefixes"}


def verify_c(executable, cases, streams, maps):
    commands = []
    for case in cases:
        stream = streams[case["stream_offset"]:case["stream_offset"] + case["stream_size"]]
        commands.append(f"V {case['palette_size']} {case['plane']} {int(case['allow_update'])} {len(case['maps'])} {stream.hex()}")
        for item in case["maps"]:
            data = maps[item["map_offset"]:item["map_offset"] + item["map_size"]]
            commands.append(" ".join(str(item[key]) for key in ("width", "height", "rows", "cols")) + " " + data.hex())
    result = iter(query(executable, commands))
    for case in cases:
        n = case["palette_size"]
        for item in case["maps"]:
            fields = next(result).split()
            expected = maps[item["map_offset"]:item["map_offset"] + item["map_size"]]
            if fields[:3] != ["V", str(item["index"]), str(MARKER)] or bytes.fromhex(fields[3]) != expected:
                raise RuntimeError("original C map or marker mismatch")
            flat = list(map(int, fields[4:]))
            cdfs = [flat[k * (n + 1):(k + 1) * (n + 1)] for k in range(5)]
            if len(flat) != 5 * (n + 1) or cdfs != item["ending_cdfs"]:
                raise RuntimeError("original C ending CDF differs")
        fields = next(result).split()
        expected_stream = streams[case["stream_offset"]:case["stream_offset"] + case["stream_size"]]
        if fields[0] != "W" or bytes.fromhex(fields[1]) != expected_stream:
            actual_stream = bytes.fromhex(fields[1])
            first = next((i for i, (a, b) in enumerate(zip(actual_stream, expected_stream)) if a != b), min(len(actual_stream), len(expected_stream)))
            raise RuntimeError(f"original C writer bytes differ in stream {case['index']}: C={len(actual_stream)} Python={len(expected_stream)} first={first}; tails C={actual_stream[-8:].hex()} Python={expected_stream[-8:].hex()}")
        case["original_c_writer_sha256"] = sha(expected_stream)
    if next(result, None) is not None:
        raise RuntimeError("extra original C output")


def hex_rows(binary):
    return "[\n" + "\n".join('  "' + binary[i:i + 48].hex() + '",' for i in range(0, len(binary), 48)) + "\n]"


def mbt_array(values):
    return "[" + ", ".join(str(v) for v in values) + "]"


def render_test(cases, streams, maps, contexts_binary, defaults):
    output = ["""///|
/// Generated by scripts/generate-av1-palette-index-reference.py.
/// Original AOM context, full map decoder, entropy writer and CDF parity.
fn av1_palette_index_reference_bytes(rows : Array[String]) -> Array[Byte] {
  let result : Array[Byte] = []
  for row in rows {
    let chars = row.to_array()
    for i in 0..<(chars.length() / 2) {
      let hi = chars[i * 2].to_int()
      let lo = chars[i * 2 + 1].to_int()
      let high = if hi >= 97 { hi - 87 } else { hi - 48 }
      let low = if lo >= 97 { lo - 87 } else { lo - 48 }
      result.push(((high << 4) | low).to_byte())
    }
  }
  result
}
""", "///|\nfn av1_palette_index_reference_contexts() -> Array[Byte] {\n  av1_palette_index_reference_bytes(" + hex_rows(contexts_binary) + ")\n}\n"]
    for n in range(2, 9):
        output.append(f'''///|
test "original AOM palette full color order N{n} exhaustive" {{
  let data = av1_palette_index_reference_contexts()
  for offset = 0; offset < data.length(); offset = offset + 14 {{
    if data[offset].to_int() != {n} {{ continue }}
    let kind = data[offset + 1].to_int()
    let row = if kind == 0 {{ 0 }} else {{ 1 }}
    let col = if kind == 1 {{ 0 }} else {{ 1 }}
    let indices : Array[Int] = Array::make(9, -777)
    if col > 0 {{ indices[row * 3 + col - 1] = data[offset + 2].to_int() }}
    if row > 0 && col > 0 {{ indices[(row - 1) * 3 + col - 1] = data[offset + 3].to_int() }}
    if row > 0 {{ indices[(row - 1) * 3 + col] = data[offset + 4].to_int() }}
    let (context, order) = av1_palette_index_context(indices, 3, row, col, {n}).unwrap()
    assert_eq((offset, context), (offset, data[offset + 5].to_int()))
    assert_eq(order.length(), 8)
    for i in 0..<8 {{ assert_eq((offset, i, order[i]), (offset, i, data[offset + 6 + i].to_int())) }}
  }}
}}
''')
    for case in cases:
        n, plane, active = case["palette_size"], case["plane"], str(case["allow_update"]).lower()
        data = streams[case["stream_offset"]:case["stream_offset"] + case["stream_size"]]
        output.append(f'///|\ntest "original AOM palette index N{n} {"Y" if plane == 0 else "UV"} {"adaptive" if case["allow_update"] else "frozen"} four maps" {{\n')
        output.append("  let stream = av1_palette_index_reference_bytes(" + hex_rows(data) + ")\n")
        output.append(f"  let decoder = av1_msac_new(stream, {active})\n  let state = av1_palette_state(8, 8)\n  let cdfs = state.{'y_index' if plane == 0 else 'uv_index'}[{n - 2}]\n")
        for context, row in enumerate(defaults[plane][n - 2]):
            output.append(f"  assert_eq(cdfs[{context}], {mbt_array(row)})\n")
        for item in case["maps"]:
            idx = item["index"]
            expected = maps[item["map_offset"]:item["map_offset"] + item["map_size"]]
            output.append(f"  let actual_{idx} = av1_palette_decode_index_map(decoder, {n}, {item['width']}, {item['height']}, {item['rows']}, {item['cols']}, cdfs).unwrap()\n")
            output.append(f"  let expected_{idx} = av1_palette_index_reference_bytes(" + hex_rows(expected) + ")\n")
            output.append(f"  assert_eq(actual_{idx}.length(), expected_{idx}.length())\n  for i in 0..<actual_{idx}.length() {{ assert_eq((i, actual_{idx}[i]), (i, expected_{idx}[i].to_int())) }}\n")
            output.append(f"  assert_eq(av1_palette_literal(decoder, 16), {MARKER})\n")
            for context, row in enumerate(item["ending_cdfs"]):
                output.append(f"  assert_eq(cdfs[{context}], {mbt_array(row)})\n")
        output.append(f"  assert_eq(decoder.allow_update, {active})\n  assert_true(decoder.symbol_max_bits >= -14)\n}}\n")
    return "\n".join(output)


README = """# AV1 bare palette-index references

This corpus covers palette sizes 2–8, Y/UV defaults, adaptive/frozen CDFs,
descending-column wavefront order, direct ns(n) first indices, and all four
right/bottom-padding states. Each of 28 streams contains four maps sharing CDFs;
every map is followed by the 16 equiprobable entropy bits 0xA5D3.

The original AOM context function is exhaustively called for 1,365 valid
edge/interior neighbor combinations. Both its full eight-entry color order and
context are retained. Its inverse rank output is also checked for every legal
current index. Context 1 requires three distinct neighboring colors and is
unreachable with a two-color palette; all other reachable contexts are covered.

Python MsacEncoder independently writes the streams using ranks returned by the
original C oracle and defaults extracted from original AOM declarations. The
unchanged original decode_color_map_tokens and original entropy decoder verify
every complete padded map, marker and ending CDF. The original AOM entropy writer
independently rewrites all maps and must produce byte-identical streams.

This establishes bare palette-index syntax parity, not complete AV1/OBU or image
decoding. Moon parity is supplied by the generated WB and run by the integrator.

Files:

- contexts.bin: 1,365 records of 14 bytes: N, kind (0 top edge / 1 left edge /
  2 interior), left, top-left, top (255 means absent), context, full color order[8].
- streams.bin: concatenated entropy streams; offsets/lengths in manifest.json.
- maps.bin: concatenated full row-major uint8 index maps; offsets in manifest.
- oracle.c: original extracted context/defaults/uniform/map-decoder functions and
  bounded I/O/verification harness. Entropy translation units compile directly
  from the unchanged pinned checkout; no generated copies substitute for them.
- oracle_config.h: standalone entropy configuration used during compilation.

The manifest records file hashes, per-map hashes and CDF states, original source
and fragment hashes, compiler identity, compile command and generation command.
It intentionally contains no full map/pixel arrays. The map dimensions passed
to the decoder are already converted decoded-MI prefixes, not raw crop sizes:
Y cases (width,height,rows,cols) are (8,8,8,8), (32,16,16,24),
(16,32,24,16), (32,32,24,24); UV uses the corresponding half dimensions.

Run the recorded generation command to regenerate. Run the generator with
--check for hash, deterministic binary/WB reconstruction and Python MSAC checks.
No Moon build is executed by this generator; moonfmt only formats the new WB.
"""


def check(args):
    manifest = json.loads((args.out / "manifest.json").read_text(encoding="utf-8"))
    if manifest["generator_sha256"] != sha(Path(__file__).read_bytes()):
        raise RuntimeError("generator changed; regenerate corpus")
    for name, expected in manifest["files"].items():
        if sha((args.out / name).read_bytes()) != expected:
            raise RuntimeError(f"artifact hash mismatch: {name}")
    contexts_binary = (args.out / "contexts.bin").read_bytes()
    contexts = read_contexts(contexts_binary)
    streams, maps = ((args.out / name).read_bytes() for name in ("streams.bin", "maps.bin"))
    arithmetic = arithmetic_module()
    if sha((ROOT / "scripts/craft_av1_fixture.py").read_bytes()) != manifest["msac_source_sha256"]:
        raise RuntimeError("independent MSAC implementation changed")
    cases, expected_streams, expected_maps = make_streams(manifest["defaults"], contexts, arithmetic)
    if streams != expected_streams or maps != expected_maps:
        raise RuntimeError("deterministic corpus reconstruction changed")
    for actual, expected in zip(manifest["cases"], cases):
        if {key: value for key, value in actual.items() if key != "original_c_writer_sha256"} != expected:
            raise RuntimeError("deterministic case metadata changed")
    coverage = verify_python(manifest["cases"], streams, maps, manifest["defaults"], contexts, arithmetic)
    if coverage != manifest["coverage"]:
        raise RuntimeError("coverage changed")
    raw = render_test(cases, streams, maps, contexts_binary, manifest["defaults"])
    if sha(raw.encode()) != manifest["unformatted_wb_sha256"] or sha(args.test.read_bytes()) != manifest["wb_sha256"]:
        raise RuntimeError("generated WB content changed")
    print(f"Checked {len(contexts)} original C contexts, 28 streams, 112 maps, all markers/CDFs and deterministic artifacts")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path(os.environ.get("TEMP", ".")) / "aom-ref-6693dbe8-0996-419e-94c4-cba21f4b7509")
    parser.add_argument("--cc", default=default_compiler())
    parser.add_argument("--moonfmt", default=shutil.which("moonfmt") or str(Path.home() / ".moon/bin/moonfmt.exe"))
    parser.add_argument("--out", type=Path, default=ROOT / "tests/fixtures/av1-palette-index")
    parser.add_argument("--test", type=Path, default=ROOT / "_refs/av1_palette_index_reference_wbtest.mbt")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    args.source_dir = args.source_dir.resolve()
    if args.check:
        check(args)
        return
    sources = source_files(args.source_dir)
    source, fragments = oracle_source(sources)
    arithmetic = arithmetic_module()
    with tempfile.TemporaryDirectory(prefix="pixelforge-palette-index-") as name:
        executable, compiler = compile_oracle(args, source, Path(name))
        context_binary, defaults = get_context_oracles(executable, sources)
        contexts = read_contexts(context_binary)
        cases, streams, maps = make_streams(defaults, contexts, arithmetic)
        coverage = verify_python(cases, streams, maps, defaults, contexts, arithmetic)
        verify_c(executable, cases, streams, maps)
    raw = render_test(cases, streams, maps, context_binary, defaults)
    formatted = run([args.moonfmt, "-"], input=raw, text=True).stdout
    args.out.mkdir(parents=True, exist_ok=True)
    args.test.parent.mkdir(parents=True, exist_ok=True)
    args.test.write_text(formatted, encoding="utf-8", newline="\n")
    artifacts = {"contexts.bin": context_binary, "streams.bin": streams, "maps.bin": maps,
                 "oracle.c": source.encode(), "oracle_config.h": CONFIG.encode(), "README.md": README.encode()}
    for name, data in artifacts.items():
        (args.out / name).write_bytes(data)
    manifest = {"scope": "bare palette index syntax; no OBUs or full-image pixels", "revision": REVISION,
                "source_urls": [f"https://aomedia.googlesource.com/aom/+/{REVISION}/{name}" for name in SOURCES],
                "source_sha256": {name: sha((args.source_dir / name).read_bytes()) for name in sources},
                "original_fragments": fragments, "compiler": compiler, "generator_sha256": sha(Path(__file__).read_bytes()),
                "msac_source_sha256": sha((ROOT / "scripts/craft_av1_fixture.py").read_bytes()),
                "generation_command": [sys.executable, str(Path(__file__).resolve()), "--source-dir", str(args.source_dir),
                                       "--cc", compiler["path"], "--moonfmt", args.moonfmt,
                                       "--out", str(args.out.resolve()), "--test", str(args.test.resolve())],
                "verification": {"original_c_context_exhaustive": True, "original_c_full_map_decoder": True,
                                 "original_c_entropy_decoder": True, "original_c_writer_byte_identical": True,
                                 "python_msac_roundtrip": True, "moon_tests_run_by_generator": False},
                "files": {name: sha(data) for name, data in artifacts.items()}, "coverage": coverage,
                "wb_file": args.test.relative_to(ROOT).as_posix(), "wb_sha256": sha(args.test.read_bytes()),
                "unformatted_wb_sha256": sha(raw.encode()), "defaults": defaults, "cases": cases}
    (args.out / "manifest.json").write_text(json_text(manifest), encoding="utf-8", newline="\n")
    print("Original C context/map/CDF and writer-byte verification passed", flush=True)
    check(args)


if __name__ == "__main__":
    main()
