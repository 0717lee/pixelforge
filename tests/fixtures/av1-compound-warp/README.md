# Compound global-warp scalar references

These references exercise both `GLOBAL_GLOBALMV` lists before compound blending.
They are function-level pixel references, not complete encoded AV1 streams.

The generator extracts unchanged scalar bodies from **dav1d 1.2.1**:

- `src/mc_tmpl.c`: `warp_affine_8x8t_c`, `avg_c`, `w_avg_c`, `mask_c`, `w_mask_c`.
- `src/warpmv.c`: affine-model shear derivation.
- `src/tables.c`: the 193-phase warp filter table.
- `src/wedge.c`: `init_chroma` for sign-dependent chroma mask rounding.

The standalone harness supplies model coordinates, replicated frame edges and
deterministic inputs. It uses `uint16_t` source storage at every depth; sample
arithmetic and the signed-buffer `PREP_BIAS` match each original depth. PixelForge
uses an unbiased `Int` buffer, so prediction rows add the dav1d bias back before
comparison. The scalar function bodies are included in `reference.c`, with the
original BSD-2-Clause notice also retained in [LICENSE](LICENSE).

The 216 groups contain 39,936 samples across 8/10/12-bit and 4:4:4/4:2:2/4:2:0:

- 54 unclipped predictions from two distinct affine models; every group contains
  fractional precision and filter overshoot.
- 162 final planes using average, distance weights 11/5, both difference-mask
  signs and both wedge signs (16x16 horizontal codebook entry 4).

`oracle.txt` retains every decimal sample in row-major order. `P` rows identify
depth, layout, plane and reference list; `B` rows identify depth, layout, blend
and plane. Layouts 0/1/2 mean 444/422/420; blends 0..5 follow the order above.
Tests compare CRC32 over signed int32 little-endian samples for every group,
plus three complete arrays for direct debugging. `manifest.json` records file
hashes, extracted-function hashes and the reference-source provenance.

From the repository root:

```sh
python scripts/generate-av1-compound-warp-reference.py --source-dir /path/to/dav1d-1.2.1
python scripts/generate-av1-compound-warp-reference.py --check
python scripts/generate-av1-compound-warp-reference.py --check --source-dir /path/to/dav1d-1.2.1
```

Regeneration needs Python, a C compiler (`--cc` can select it), and `moonfmt`.
The bundled MoonBit TCC is selected when no `cc` is found. `--check` reads files
only: it verifies artifact hashes, all group extents and the committed expected
tests; an optional source directory also verifies the exact extracted C.
Upstream source: <https://code.videolan.org/videolan/dav1d/-/tree/1.2.1>.
