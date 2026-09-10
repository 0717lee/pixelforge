# External AV1 reference fixtures

Seven 64x64, 8-bit `yuv420p` single-frame libaom samples are provided as raw
low-overhead OBU (`*.obu`) and AVIF (`*.avif`) files. `manifest.json` records
the source Y/U/V constants, CRF and parsed `base_q_idx`, OBU/AVIF hashes and
the expected libdav1d-decoded YUV/RGBA plane hashes. The encoder sequence header
has CDEF, restoration, filter-intra and intra-edge filtering disabled.
Frame headers use `tx_mode=1` (ONLY_LARGEST), giving one 64x64 luma block and
32x32 chroma blocks.
`ac_y_cosine_q30` adds a non-constant luma cosine with neutral chroma; its
manifest entry records the complete decoded luma row and verifies all 64 rows
are identical.

Regenerate and verify all files from the repository root:

```text
python scripts/verify-av1-reference.py --out tests/fixtures/av1
```

The script invokes the `aomenc` libaom tool (ffmpeg's wrapper does not expose
the transform-size search switch) and independently decodes both OBU and AVIF
with ffmpeg's `libdav1d`; it never edits encoded OBU bytes.
