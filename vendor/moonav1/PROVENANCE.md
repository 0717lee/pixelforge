# Source provenance

MoonAV1 is extracted from the AV1/AVIF implementation in [0717lee/pixelforge](https://github.com/0717lee/pixelforge).

- Source revision: [`6f0c711c54f89d34f3e2ef97cde7a0a45458583d`](https://github.com/0717lee/pixelforge/tree/6f0c711c54f89d34f3e2ef97cde7a0a45458583d).
- Extraction date: 2026-09-24.
- Source scope: root `av1*.mbt` and `avif*.mbt`, their image/byte-reading support, independent AV1/AVIF fixtures, reference generators and third-party notices.
- Original implementation and review history remains in PixelForge. The [source handoff](https://github.com/0717lee/pixelforge/blob/6f0c711c54f89d34f3e2ef97cde7a0a45458583d/HANDOFF.md) describes the original acceptance evidence.

The extraction creates an independent package and maintenance boundary. It does not make pre-existing decoding algorithms, tests or fixtures newly implemented work. Any competition or contribution report should identify this baseline and separately list work performed after extraction.

MoonAV1 is currently a local canonical repository: no public MoonAV1 repository has been created and no Mooncakes package has been published. PixelForge preserves the public implementation history and existing codec entry points. Its local `main` includes migration commit `e366566e95b59173738bdb9bbbc5376550bd92cb`; this does not imply a remote update.

PixelForge distributes a `vendor/moonav1` snapshot from a fixed committed MoonAV1 revision and resolves it through a checked-in `moon.work`. Its synchronization tool records the source revision and verifies the generated contents. Decoder changes belong in MoonAV1, followed by a new generated snapshot; vendored files are not maintained separately. The snapshot includes source, embedded tests, interfaces and notices, while the complete fixtures and reference generators remain in the canonical library. Public hosting and package publication are separate future decisions.

Algorithm and table sources include libaom, go-av1 and dav1d. Their notices are retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Fixture manifests retain encoder/decoder versions, commands, hashes and comparison conventions. Reference pixels are not regenerated merely to make migration tests pass.

The PixelForge-wide count of 1546 tests belongs to the original repository at the source revision. MoonAV1 has its own test count and verification record; these must not be conflated.
