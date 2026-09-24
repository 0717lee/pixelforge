# Legal global-motion fallback streams

AV1 section 7.11.3.1 derives `useWarp` per prediction. `force_integer_mv=1`
disables warped interpolation. A nontranslation model whose shear parameters
are not representable also selects ordinary motion compensation. Neither case
invalidates the frame. The same decision appears in dav1d's
`gmv_warp_allowed` derivation in `src/decode.c`.

These are controlled conformance streams, not untouched encoder output. Starting
from the committed libaom `inter_screen_content_64x64.obu`, the generator changes
the second uncompressed frame header and one tile byte. It records every change
in the manifest. The integer fixtures set the integer-MV bit and remove the
now-absent high-precision-MV bit; all models are written with the normative
signed-subexponential grammar.

The three fixtures exercise:

- Integer motion with a valid rotate/zoom model and a GLOBALMV block with residual.
- The same integer-motion model with a skipped GLOBALMV block.
- A legal rotate/zoom model outside the warp shear limits, selecting ordinary
  MC for an actual GLOBALMV block.

FFmpeg's libdav1d decoder with `-xerror` and a separately built dav1d 1.2.1 CLI
must both decode **two complete 64x64 YUV420 frames** and agree on all 12,288
native bytes. Traces from the original dav1d decoder include
`Post-intermode[2,...]`, proving that the stream actually selects GLOBALMV.
`*.reference.yuv` retains every native pixel, `*.blocks.txt` retains the block
evidence and `*.headers.txt` retains normalized FFmpeg syntax traces.

```sh
python scripts/generate-av1-global-fallback-reference.py --ffmpeg /path/to/ffmpeg --dav1d-trace /path/to/dav1d-debug
python scripts/generate-av1-global-fallback-reference.py --check
```

For regeneration, build dav1d 1.2.1 with `DEBUG_BLOCK_INFO=1` in `src/decode.c`
to obtain the block trace. The generated frame pixels do not depend on the
trace instrumentation. `--check` only reads files; it reproduces the controlled
bitstream rewrite, validates hashes and every plane checksum, and verifies
the recorded GLOBALMV evidence and generated test expectations.

Normative reference: [AV1 inter prediction](https://aomediacodec.github.io/av1-spec/#inter-prediction-process).
