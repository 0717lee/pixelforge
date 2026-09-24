# AV1 frame-level superres references

**Eighteen complete superres frame references**: sixteen untouched libaom
encodes and two explicitly constructed q0 headers. The stock encodes cover
denominators 9–16 at 10-bit color 97×65, 8/12-bit color and monochrome
129×65 at denominator 12, 10-bit color and monochrome 385×65 in two tiles at
denominator 12, and 10-bit color and monochrome 128×64 at denominator 12. Every
stream is a single intra still frame with actual horizontal scaling.

Each fixture ships the raw OBU (`.obu`), the wrapped AVIF (`.avif`), the
aomenc trace (`.trace.txt`), the dav1d native YUV planes (`.reference.yuv`,
upscaled display resolution, yuv420p10le and friends), the FFmpeg/libdav1d
raw RGBA (`.raw_ffmpeg.rgba`) and the scalar libavif RGBA conversion
(`.scalar_libavif.rgba`). The `nocdef`, `nodeblock` and `none` variants are
dav1d `--inloopfilters` toggles: they prove the decoder still observes
deblocking, CDEF and superres as separately composable stages, with changed
sample counts recorded per plane in the manifest.

The two constructed headers reuse unchanged q0 stock tile entropy to exercise
the screen-content tools, absent intrabc syntax and the restoration-types gate
that active scaling retains even under CodedLossless. They are decoded as
128×64 display frames, so their `--append-grid-pair` output cells also
integrate with the MIAF 4:2:0 grid path (even 128×64 display cells, both axes
at least 64).

Native planes are asserted against dav1d directly; color RGBA uses the
established nearest-4:2:0 conversion contract from the exact native planes and
decoded range/matrix, monochrome RGBA uses the actual scalar libavif UNORM
conversion, and vendor RGBA is retained without a color-parity assertion. The
raw AV1 and AVIF entries must agree on every pixel.

`manifest.json` records encoder commands, header facts, per-file SHA-256,
native plane ranges, filter-order evidence, tool versions and complete
provenance.

## Reproduce and check

```powershell
python scripts/generate-av1-superres-reference.py
python scripts/generate-av1-superres-reference.py --check
```

Generation requires aomenc, FFmpeg with libdav1d, the dav1d CLI with
`--inloopfilters`, Python and moonfmt. Options are `--out`, `--test`,
`--aomenc`, `--ffmpeg`, `--dav1d`, `--moonfmt`, `--libavif-scalar` and
`--check`; `--append-grid-pair` adds exactly the two even 128×64 display cells
for AVIF integration. `--check` needs no encoders: it verifies deterministic
reconstruction, per-file hashes and the generated test's exact file hash.
