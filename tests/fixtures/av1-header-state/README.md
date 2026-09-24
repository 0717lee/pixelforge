# Frame identity and inherited geometry references

This corpus contains ten complete-stream cases. Expected native planes come
from dav1d 1.2.1, independently of the MoonBit decoder.

## Reference-derived dimensions

`inherit_superres_8_to_12`, `inherit_superres_12_to_8` and
`inherit_superres_12_to_16` start as two-frame libaom 3.6.0 encodes. Their second
frame is changed to `frame_size_override_flag=1, found_ref[0]=1`; the redundant
render-size bit is removed. The key picture, superres flag/denominator and all
tile bytes remain unchanged. The generator verifies that dav1d produces exactly
the same two pictures for the original and modified streams.

The inherited value is the reference's display width, 64. The second frame must
recompute its own coding width from its own denominator, including the case
where scaling is switched off. Copying the reference's older coding width or
omitting the three denominator bits fails the sample comparison.

## Small superres widths

The four `small_superres_*` streams are untouched encoder output at widths
8, 16, 17 and 24, height 8, with active denominator 16. Both the encoder and
dav1d use `max(round(display_width * 8 / denominator), min(16, display_width))`
for the coding width. These fixtures establish actual reference-decoder
behavior at the small-width clamp, including active-superres pictures whose
coding and display widths are equal. The old project rule requiring every
plane to grow rejected these encoder-produced streams.

The rule is implemented in dav1d's [`read_frame_size`](https://code.videolan.org/videolan/dav1d/-/blob/1.2.1/src/obu.c),
for both explicit sizes and `found_ref`. The project's older downloaded AV1
syntax text omits this clamp; the full untouched streams and independent pixel
outputs preserve the acceptance evidence rather than assuming the two formulas
agree. Separate whitebox tests also cover lossless/screen-content syntax gates
when the active-superres flag remains set at equal dimensions.

## Frame IDs

`frame_id_wrap_valid` starts as a three-frame encoder stream. The generator
enables three-bit IDs with two-bit deltas, inserts current IDs 6, 7 and 0, and
codes every named reference's required delta. A fourth temporal unit displays
slot 2 with `display_frame_id=0`. No entropy-coded tile byte changes. Dav1d's
four outputs equal the original three pictures with the last picture repeated.

`frame_id_wrap_bad_delta` changes only the seventh reference's delta in the
third frame. `frame_id_wrap_bad_display` changes only the final display ID.
Dav1d reports an explicit frame-header parsing error for each. Its command-line
program can still exit zero after recovering, so the manifest records its real
exit status and the number of partial output frames; acceptance requires both
the parser error and missing pictures. MoonBit must reject the complete input.

## Reproduction

From the repository root, with `aomenc`, `dav1d`, `ffmpeg` and `moonfmt` on PATH:

```sh
python scripts/generate-av1-header-state-reference.py --check
```

Tool paths can be supplied with `--aomenc`, `--dav1d` and `--ffmpeg`. Omit
`--check` to regenerate. Commands, codec versions, source hashes and artifact
hashes are recorded in `manifest.json`. Text hashes use LF line endings.

The generated `av1_header_state_reference_wbtest.mbt` checks every displayed
sample, stored coding widths, current/reference IDs and both rejection cases.
The separate `av1_frame_identity_wbtest.mbt` covers wrap-window endpoints,
invalid-slot preservation, delta limits, previous-ID progression, first-frame
handling and identity updates when no reference slot is refreshed.
