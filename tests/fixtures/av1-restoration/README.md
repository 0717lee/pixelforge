# AV1 active loop-restoration header reference

**One untouched libaom encode with active Wiener restoration on every
plane**: 97x65 10-bit 4:2:0, SB64, superres denominator 12,
base_q_idx 160, CDEF active. The bounded stock superres corpus encodes every
frame with `--enable-restoration=0`, so no real stream there exercises the
active-LR frame-header path; this fixture fills exactly that gap.

The committed OBU ships with its wrapped input noise
(`.input.y4m`, deterministic seed 20260917) and the FFmpeg `trace_headers`
transcript (`.trace.txt`) that acts as the syntax oracle. The generated
white-box test `_refs/av1_restoration_reference_wbtest.mbt` embeds the OBU
and asserts the parsed `Av1SequenceInfo`, `Av1FrameHeaderInfo` and
`Av1RestorationConfig` against that evidence: three Wiener modes, unit size
128 (lr_unit_shift 1), chroma unshifted (lr_uv_shift 0), coded width
65 under denominator 12, and the
restoration grid on the upscaled plane (AOM `av1_alloc_restoration_struct`).

This is a stage-1 header gate: loop filtering itself lands with the Wiener
and SGR kernel stages, at which point this stream can be upgraded with a
native dav1d reference like the superres corpus.

## Reproduce and check

```powershell
python scripts/generate-av1-restoration-reference.py
python scripts/generate-av1-restoration-reference.py --check
```

The noise input regenerates byte-identically from the seed, so `--check`
re-derives it, re-encodes with the manifest command and verifies the OBU,
trace evidence and the canonical generated test.

## Encoder command

```text
D:\ProgramData\anaconda3\Library\bin\aomenc.EXE --superres-mode=1 --superres-denominator=12 --superres-kf-denominator=12 --enable-diagonal-intra=0 --debug --disable-warning-prompt --allintra --obu --i420 --width=97 --height=65 --profile=0 --bit-depth=10 --input-bit-depth=10 --fps=1/1 --limit=1 --cpu-used=0 --threads=1 --end-usage=q --cq-level=40 --sb-size=64 --tile-columns=0 --tile-rows=0 --aq-mode=0 --deltaq-mode=0 --enable-chroma-deltaq=0 --enable-qm=0 --enable-cdef=1 --enable-restoration=1 --enable-filter-intra=0 --enable-intra-edge-filter=0 --enable-angle-delta=0 --enable-rect-partitions=0 --enable-1to4-partitions=0 --enable-ab-partitions=0 --enable-smooth-intra=1 --enable-paeth-intra=1 --enable-palette=0 --enable-flip-idtx=0 --enable-tx-size-search=0 --use-intra-default-tx-only=1 --min-partition-size=8 --max-partition-size=16 --enable-directional-intra=1 --enable-cfl-intra=0 --enable-intrabc=0 --loopfilter-control=1 -o C:\Users\谦友Lee\Desktop\Project\mb\pixelforge\tests\fixtures\av1-restoration\noise_color_10bit_d12_97x65_wiener_u128.obu C:\Users\谦友Lee\Desktop\Project\mb\pixelforge\tests\fixtures\av1-restoration\noise_color_10bit_d12_97x65_wiener_u128.input.y4m
```
