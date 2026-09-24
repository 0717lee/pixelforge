# AVIF dimensions and layer selectors

Eight valid complete AVIFs exercise sequence maxima 128x128 with an actual
64x64 frame, the default highest layer, essential a1op=1, essential lsel=0/1,
and lsel=0xffff. The two spatial layers have different real image pixels.
The lower layer supplies references for the higher layer within one sync TU.
Two grid cases exercise a coded cell with different sequence maxima and OP1.
Seven malformed or unsatisfiable selections test rejection.

The generator reuses committed libaom tile payloads, changing only AV1 frame
and sequence headers. Independent libavif 0.11.1/dav1d reads the entire AVIF;
each native sample must equal the stock dav1d decode of the source frame.
RGBA is libavif's scalar nearest-chroma output with container BT.709 nclx.
Full native and RGBA bytes are committed alongside checksums and file hashes.
Whitebox regressions embed both distinct native/RGBA references and compare
every sample through primary, RGBA, and grid entry points as applicable.

Regenerate with the manifest command. `--check` only reads existing files.
The required property semantics are AVIF sections 2.2.2 and 2.3.2:
https://aomediacodec.github.io/av1-avif/
The fixtures and generator are project-owned; no decoder source is vendored.
