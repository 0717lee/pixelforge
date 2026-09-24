# Compound temporal motion oracle

`reference.c` contains the unmodified `mv_projection`, `fix_mv_precision`,
`fix_int_mv_precision` and `add_temporal_candidate` function bodies from
dav1d 1.2.1 (`src/refmvs.c` and `src/env.h`), with minimal type declarations
and a small harness. The original BSD license is retained in the source.

Run `python scripts/generate-av1-compound-temporal-reference.py --check` to
compile this standalone oracle in a temporary directory and compare all five
outputs with `oracle.json`. By default it uses MoonBit's bundled TCC; `--cc`
and `--cc-root` override the compiler and TCC runtime root. To independently
re-extract the functions, pass `--source-dir <dav1d-1.2.1>`.

The cases cover signed half rounding, both reference-list projections,
high/low/integer motion precision, duplicate-pair weights, pairs sharing only
their first vector, and merging into a full eight-entry stack. The generated
white-box test compares both vector lists and every weight against C output.
Temporal scan ordering, invalid second-list samples, tile bounds and AV1's
ZeroMvContext rule are separately tested by the normative scan tests.
