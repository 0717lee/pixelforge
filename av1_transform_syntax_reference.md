# AV1 transform syntax reference

This note records the transform syntax order used by the checked-in Go
reference under `_refs/go-av1`. It is intentionally separate from the decoder
implementation so that entropy-state changes can be reviewed against the
reference before they are wired into the tile loop.

## Frame and block order

`header/frame.go:readTxMode` reads `tx_mode_select` after the frame-level loop
restoration fields. Coded-lossless frames force `Only4x4`; otherwise `0` means
`Largest` and `1` means `Select`.

For `TxModeSelect`, `decode/block.go:readBlockTxSize` reads transform depth for
both intra and inter blocks larger than 4x4. Intra blocks use `txDepthCtx` and
the `tx8x8`, `tx16x16`, `tx32x32`, or `tx64x64` CDF selected by
`MaxTxDepth`. Inter blocks use the variable-transform tree and `txfm_split`.
The tree is then traversed before residual decoding.

Inside `decode/residual.go:transformBlock`, the order is:

1. Intra prediction.
2. `readAllZero(plane, tx_size, x4, y4)`.
3. If non-zero, `decode/coeff.go:decodeCoeffs` reads luma `tx_type` first,
   followed by EOB and coefficient levels/signs.
4. The selected inverse transform is applied and the residual is added.

Chroma does not entropy-code a separate transform type. Its type is derived
from `modeToTxfm[uvMode]` and falls back to `DctDct` when that type is not in
the transform set for the block.

## Intra transform type CDFs

`readTransformType` signals a type only when the per-segment qindex is greater
than zero and the selected transform set is not DCT-only. The qindex is the
segment value (`getQIndexSeg`), not merely the frame `base_q_idx`.

For intra blocks, the set is selected as follows:

- square-up size larger than 32: DCT-only;
- reduced transform set or square size 16: `INTRA_2`;
- otherwise: `INTRA_1`.

The default inverse maps are:

- `INTRA_1`: `Idtx, DctDct, VDct, HDct, AdstAdst, AdstDct, DctAdst`;
- `INTRA_2`: `Idtx, DctDct, AdstAdst, AdstDct, DctAdst`.

`INTRA_1` has CDF shape `[txSzSqr][intraDir][8]`; `INTRA_2` has
`[txSzSqr][intraDir][6]`. `intraDir` is the luma mode, except that an active
filter-intra mode remaps to `{DC, V, H, D157, DC}`.

The Go reference also defines the directional transform types `VDct`, `HDct`,
`VAdst`, `HAdst`, `VFlipadst`, and `HFlipadst`. They are distinct transform
types and must not be silently folded into ordinary DCT/ADST dispatch.

Reference locations:

- `_refs/go-av1/decode/txtype.go`
- `_refs/go-av1/decode/block.go`
- `_refs/go-av1/decode/residual.go`
- `_refs/go-av1/decode/coeff.go`
- `_refs/go-av1/cdf/tables_txeob_gen.go`
- `_refs/go-av1/cdf/tables_txsize_gen.go`

