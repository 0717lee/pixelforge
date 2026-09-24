# OBU assembly and presentation fixtures

`python scripts/generate-av1-obu-reference.py --ffmpeg <ffmpeg> --dav1d <dav1d>`
repackages existing repository bitstreams and verifies the results with an
independent dav1d decoder. `--check` regenerates into a temporary directory and
compares the committed OBU and native YUV bytes. No new encoded tile entropy is
created by this generator.

- `split_two_tile_groups`: the existing 128×64 two-tile image is repackaged as
  one standalone frame-header OBU followed by two tile-group OBUs. Each group
  contains one tile. Frame-header trailing bits and each group's explicit tile
  range are written according to AV1 §5.3, §5.9 and §5.11. Native YUV is byte
  identical to the original frame.
- `hidden_inter_show_existing`: the existing lossless 64×64 key/inter pair is
  repackaged as three temporal units. Unit 1 shows the key. Unit 2 decodes the
  inter with `show_frame=0, showable_frame=1` and displays reference slot 1 with
  `show_existing_frame`. Unit 3 decodes the original inter again, checking that
  the hidden update and reference display preserve later decoding. The three
  displayed native frames are the original key, original inter and original
  inter, each byte identical to independently decoded source samples.
- `layer_timing_32bit`: the same key/inter pair gains three operating points,
  differing decoder-model presence, temporal IDs 0 and 1, and 32-bit decoder
  delays, buffer-removal times and presentation times. Values include
  `2147483648` and `4294967295`. The first frame codes two removal timestamps,
  the second codes one; the inactive decoder model codes none. Both displayed
  pictures remain byte identical to the original independent YUV.
- `spatial_layer_presentation`: OP0 (`idc=769`) contains spatial layers 0 and 1.
  Three temporal units contain shown layers `[0,1]`, `[0]` and `[0,1]`. Layer 1
  predicts from the lower layer's key frame, so lower-layer reconstruction and
  reference updates remain necessary. The oracle invokes stock dav1d 1.2.1
  with `--alllayers 0` and returns three presentations: inter, key, inter.
  Its historical default `--alllayers 1` is also tested and returns all five
  decoded shown frames; it is not used as the display policy oracle.

AV1 §7.18.1 recommends the highest spatial layer actually present in each
temporal unit of the chosen operating point. [AV1-ISOBMFF §1](https://aomediacodec.github.io/av1-isobmff/#bitstream-features-overview)
explicitly supports simple scalable streams stored in one track while defining
one presentation per temporal unit. PixelForge's batch API returns one selected
presentation for each TD-delimited unit; an input sample's end also closes its
unit. The legacy single-image API returns the first such presentation, while
processing all reference updates. It does not choose the last frame of a
multi-unit input.

`manifest.json` records the source files, decoder version, operations and SHA256
values. `av1_obu_reference_wbtest.mbt` embeds these independently decoded native
planes and compares every displayed sample through the actual video decoder.
`av1_obu_frames_wbtest.mbt` covers missing/duplicate/out-of-order tile groups,
truncated envelopes, layer selection and invalid reference presentations.
