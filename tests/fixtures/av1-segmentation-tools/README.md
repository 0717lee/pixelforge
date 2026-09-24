# Segmentation tool references

The nine streams contain an unchanged libaom key picture followed by a fully
constructed inter tile. The general frame prefix, reference list and geometry
come from `base.obu`; the generator rewrites `segmentation_params`, loop-filter
parameters and the complete entropy payload. These are deliberately constructed
conformance streams, not untouched encoder output.

The range encoder and bit writer come from `scripts/craft_av1_fixture.py`.
Only the small normative CDF subset used here is embedded in the generator, so
no `_refs` cache is needed. Release dav1d 1.2.1 and a separate debug dav1d build
must produce identical native YUV for every complete stream before a reference
is accepted.

| Fixture | Exercised behavior |
| --- | --- |
| `forced_skip` | Segment id precedes skip; SKIP suppresses skip/reference/mode symbols while `is_inter` is still read. |
| `forced_intra_reference` | REF_FRAME=0 suppresses `is_inter` and selects intra DC prediction within an inter frame. |
| `forced_inter_reference` | REF_FRAME=1 suppresses `is_inter` and reference selection while retaining the inter-mode tree. |
| `forced_global_translation` | GLOBALMV selects single-reference global prediction without `is_inter`, reference or mode symbols; a nonzero translation changes samples. |
| `lf_baseline` | Four 32×32 global-predicted blocks with Y-vertical/Y-horizontal/U/V base levels all 16. |
| `alt_lf_y_vertical` | ALT_LF_Y_V=-16 changes 704 luma samples from the LF baseline. |
| `alt_lf_y_horizontal` | ALT_LF_Y_H=-16 changes 640 luma samples. |
| `alt_lf_u` | ALT_LF_U=-16 changes 238 U samples only. |
| `alt_lf_v` | ALT_LF_V=-16 changes 238 V samples only. |

All cases explicitly code segment zero before skip. The LF cases also enable
GLOBALMV to keep their entropy payload identical while changing one filter
component. The `.symbols.txt` files retain the constructed frame's upstream
`DEBUG_BLOCK_INFO` transcript. The generator verifies the number of preskip
segment symbols, the presence/absence of skip and intra symbols, the absence of
reference symbols, and the final arithmetic range against its encoded symbol
sequence. FFmpeg header traces independently verify the enabled features.

`*.reference.yuv` contains both displayed 64×64 8-bit 4:2:0 frames, tightly
packed as Y/U/V: 6144 bytes per frame. The generated whitebox tests compare all
110592 samples across the nine two-frame streams and check saved segment state.
No expected sample is produced by the MoonBit decoder.

To reproduce, put libaom 3.6.0 `aomenc`, dav1d 1.2.1, FFmpeg `trace_headers`
and `moonfmt` on PATH. Build a second dav1d 1.2.1 executable with
`DEBUG_BLOCK_INFO=1` enabled in its source configuration, then run from the
repository root:

```sh
python scripts/generate-av1-segmentation-tools-reference.py --trace-dav1d /path/to/debug/dav1d --check
```

Use `--aomenc`, `--dav1d` and `--ffmpeg` to override tools. Omit `--check` to
regenerate. `manifest.json` records the source hash, encoder command, versions,
constructed symbol sequence, header fields and artifact hashes. Text hashes use
LF endings; binary outputs retain their exact bytes.
