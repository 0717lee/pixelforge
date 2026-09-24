# Film-grain sequence references

These fixtures exercise film-grain parameter updates, reference inheritance,
new seeds and show-existing output at 8, 10 and 12 bits. They supplement the
older `rs_grain1.obu` still-image fixture in this directory.

For each depth, `sequence_inherit_<depth>bit.encoder.obu` is the untouched
libaom 3.6.0 output for three identical 64×64 4:2:0 pictures. Each frame codes a
complete parameter set, with seeds 45231, 48612 and 51993. The reproducible
encoder command and source hash are recorded in `sequence-manifest.json`.

The corresponding `.obu` makes two explicit syntax changes: the two inter
frames replace their full grain update with `update_grain=0`, referencing slots
0 and 1 respectively. Their seeds and entropy-coded tile bytes are unchanged.
A fourth temporal unit displays slot 2 through `show_existing_frame`.
The `.trace.txt` files are normalized FFmpeg `trace_headers` output proving
those fields and their bit offsets.

`*.native.yuv` comes from dav1d 1.2.1 with `--filmgrain 0`.
`*.display.yuv` comes from a separate dav1d run with `--filmgrain 1`.
Both are tightly packed Y, U and V for all four displayed pictures; high-bit
depth samples are unsigned 16-bit little-endian. The generator verifies that
each output equals the untouched encoder stream's output with its last frame
repeated. It also verifies that grain changes samples and that distinct seeds
produce distinct displayed pictures.

Run from the repository root with `aomenc`, `dav1d`, `ffmpeg` and `moonfmt` on
PATH, or provide explicit codec executable paths:

```sh
python scripts/generate-av1-film-grain-sequence-reference.py --check
```

Omit `--check` to regenerate. Generation uses a temporary directory and does
not modify the older still-image files. Codec versions are pinned in the
manifest; a different encoder version can produce different legal bytes.
Text hashes use LF line endings; binary references are compared byte-for-byte.

The generated whitebox tests run both original and inherited streams through
the decoder's OBU sequence entry point. They compare every displayed sample,
then compare all eight stored reference slots with grain-free dav1d samples.
That final comparison catches accidental mutation of reference pictures when
film grain is applied to displayed output.
