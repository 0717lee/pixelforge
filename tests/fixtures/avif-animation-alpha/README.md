# Stateful AVIF animation alpha references

The base containers were encoded directly with **libavif 0.11.1 / libaom**,
using `avifEncoderAddImage` three times followed by `avifEncoderFinish`. The
color and alpha tracks each mark only their first sample as a sync sample.
Both tracks therefore require their own persistent AV1 reference state.

Every 16x16 input frame has distinct full-range monochrome color and independent
alpha coverage. The three streams use 8, 10 and 12-bit depth, with alpha values
covering zero, full coverage and low native bits. Sample durations are 100, 200
and 300 at timescale 1000. The generator records codec versions in
`manifest.json`.

The expected RGBA pixels come from an independent complete-container read with
libavif (`avifDecoderSetSource(TRACKS)`, parse, then three next-image calls),
followed by scalar conversion with `avoidLibYUV=1`. The native decoded alpha
plane must exactly equal the lossless encoder input. Scalar RGBA must also equal
full-range UNORM conversion of that native input. No PixelForge output is used
to generate the expected pixels.

For every bit depth, the independent decoder also verifies:

- Swapping the two `trak` boxes preserves every pixel and primary-track time.
- Doubling the alpha track's media timescale and all its durations preserves
  synchronization with the unchanged color track.

An unassociated-alpha fixture is independently verified to decode opaque color.
Three further 8/10/12-bit fixtures use colored 4:4:4 frames with alpha. Their
AV1 color descriptions stay unspecified while only the primary track's sample
entry `nclx` changes to BT.709. Actual libavif conversion verifies that this
changes RGB while preserving alpha and timing, exercising track-level metadata
application before final conversion.
Six additional fixtures corrupt associations, alpha times, av1C depth, visual
sample geometry or the sample count. Their rejection is a PixelForge metadata
contract; it is not presented as libavif rejection parity.

The source layout uses `trak/tref/auxl`, an `auxv` auxiliary handler and the
`auxi` alpha URN in the auxiliary `av01` sample entry. `auxC` is the corresponding
static-image property, not the track sample-entry box. Normative references:
[AVIF auxiliary sequences](https://aomediacodec.github.io/av1-avif/#auxiliary-images)
and [AV1 ISOBMFF temporal-unit samples](https://aomediacodec.github.io/av1-isobmff/).

From the repository root:

```sh
python scripts/generate-avif-animation-alpha-reference.py --libavif /path/to/avif.dll
python scripts/generate-avif-animation-alpha-reference.py --check
```

Regeneration requires the version-checked libavif 0.11.1 ABI, Python and
`moonfmt`. `--check` needs no codec DLL and only reads artifact hashes and the
generated expected tests. Tests compare every RGBA byte in all three frames.
