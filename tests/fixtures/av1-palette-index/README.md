# AV1 bare palette-index references

This corpus covers palette sizes 2–8, Y/UV defaults, adaptive/frozen CDFs,
descending-column wavefront order, direct ns(n) first indices, and all four
right/bottom-padding states. Each of 28 streams contains four maps sharing CDFs;
every map is followed by the 16 equiprobable entropy bits 0xA5D3.

The original AOM context function is exhaustively called for 1,365 valid
edge/interior neighbor combinations. Both its full eight-entry color order and
context are retained. Its inverse rank output is also checked for every legal
current index. Context 1 requires three distinct neighboring colors and is
unreachable with a two-color palette; all other reachable contexts are covered.

Python MsacEncoder independently writes the streams using ranks returned by the
original C oracle and defaults extracted from original AOM declarations. The
unchanged original decode_color_map_tokens and original entropy decoder verify
every complete padded map, marker and ending CDF. The original AOM entropy writer
independently rewrites all maps and must produce byte-identical streams.

This establishes bare palette-index syntax parity, not complete AV1/OBU or image
decoding. Moon parity is supplied by the generated WB and run by the integrator.

Files:

- contexts.bin: 1,365 records of 14 bytes: N, kind (0 top edge / 1 left edge /
  2 interior), left, top-left, top (255 means absent), context, full color order[8].
- streams.bin: concatenated entropy streams; offsets/lengths in manifest.json.
- maps.bin: concatenated full row-major uint8 index maps; offsets in manifest.
- oracle.c: original extracted context/defaults/uniform/map-decoder functions and
  bounded I/O/verification harness. Entropy translation units compile directly
  from the unchanged pinned checkout; no generated copies substitute for them.
- oracle_config.h: standalone entropy configuration used during compilation.

The manifest records file hashes, per-map hashes and CDF states, original source
and fragment hashes, compiler identity, compile command and generation command.
It intentionally contains no full map/pixel arrays. The map dimensions passed
to the decoder are already converted decoded-MI prefixes, not raw crop sizes:
Y cases (width,height,rows,cols) are (8,8,8,8), (32,16,16,24),
(16,32,24,16), (32,32,24,24); UV uses the corresponding half dimensions.

Run the recorded generation command to regenerate. Run the generator with
--check for hash, deterministic binary/WB reconstruction and Python MSAC checks.
No Moon build is executed by this generator; moonfmt only formats the new WB.
