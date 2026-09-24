# Original C directional prediction references

The 672 cases cover every combination of 8 directional modes, 7 angle deltas
(-3 through 3), and 3 bit depths (8, 10, 12), with four edge variants per
combination. The 168 combinations rotate through all 19 legal transform shapes.
Inputs include complete edges, missing edges, partial edges, missing extensions,
smooth-neighbor filter selection, filter-disabled pairs, and extreme samples.

The oracle extracts unchanged scalar functions and tables from libaom revision
`8e7b6a567df174d795479b92b4ac766d271add73`. The original high-bit-depth directional
builder performs edge preparation, corner filtering, edge filtering, upsampling,
and Z1/Z2/Z3 or scalar V/H prediction. The C shim supplies an x64 ABI, packs the
reference plane, selects scalar dispatch, and counts executed paths. Its unused
filter-intra branch fails if reached. Original rounding and clipping functions
remain intact; source-file hashes and every extraction are recorded in the
manifest. C source and executables exist only in temporary OS directories.

Availability counts are explicit inputs. Frame, partition, superblock, and tile
rules that derive those counts belong to integration validation.

`output.bin` contains **479,808 native samples** (959,616 bytes), concatenated in
case order and row-major order within each case. Every depth uses unsigned
16-bit little-endian storage. The manifest supplies byte offsets, sample counts,
input formulas, per-case SHA-256/CRC-32, source hashes, compiler identity, and the
complete normalized generation command. Its binary SHA-256 is:

```text
7caccd1a834c2b006c28772c44c192379473c361f0bda19e06524d3026a5f3f0
```

The optional prospective white-box file has 24 test groups. All 672 cases check
the CRC-32 of every native sample, output extent, and sample range. All 36 TX4x4
cases additionally compare their complete 16-pixel arrays. These expectations
come from the C binary. The generator formats this file independently and leaves
MoonBit runtime validation to the coordinated build step.

Actual original-C path counts are 57 upsampling calls, 13 lower-limit and 13
upper-limit upsampling clips, 162 corner filters, and 571 nonzero-strength edge
filters. Edge-filter invocation counts for strengths 0/1/2/3 are
`77 / 53 / 53 / 465`. Filter-enabled and filter-disabled outputs differ in 162
paired inputs. Each of the six missing/partial-edge policies has 28 cases.

From the repository root, use a local libaom checkout whose files match the
manifest's pinned hashes:

```powershell
python scripts/generate-av1-directional-reference.py --source-dir path/to/aom --test
python scripts/generate-av1-directional-reference.py --source-dir path/to/aom --check
```

`--cc` selects the C compiler; the default is MoonBit's bundled TinyCC when
available. `--moonfmt` selects the standalone formatter. `--out` selects the
binary/manifest directory. `--test` defaults to
`_refs/av1_directional_predict_wbtest.mbt` and requires an output beneath `_refs`.
`--check` recompiles the original C, compares every binary byte and deterministic
case field, and checks the prospective test recorded in the manifest. Source
hash rejection and binary-tampering rejection have also been verified.

Upstream source: [libaom pinned revision](https://aomedia.googlesource.com/aom/+/8e7b6a567df174d795479b92b4ac766d271add73/).
Copyright (c) 2016, Alliance for Open Media. All rights reserved.
[BSD software license](https://www.aomedia.org/license/software) and
[patent license](https://www.aomedia.org/license/patent).
