# MoonAV1 dependency snapshot

This is a pinned copy of the independently maintained **0717lee/moonav1** module.
Source revision: **9f0f0c31a3ab35f169836223e6505b584882a15a**. It is included so a fresh PixelForge checkout
can build without an unpublished registry package or a sibling source directory.
MoonAV1 has no public repository or Mooncakes release at this stage.

The authoritative local project is the workspace's sibling **moonav1** directory.
Do not edit this snapshot. Commit changes there, then run from PixelForge:

    node scripts/vendor-moonav1.mjs ../moonav1
    node scripts/vendor-moonav1.mjs --check

The checked-in **moon.work** resolves the versioned import to this directory.
The snapshot includes the decoder's embedded tests, public interface and licenses;
reference-generation tools and the full fixture corpus remain in MoonAV1.
PixelForge retains its browser/Worker integration fixtures.

Use **avif_decode_rgba**, **avif_decode_animation**, or **av1_decode** for decoding;
see [the public interface](pkg.generated.mbti). RGBA output is straight RGBA8;
there is no encoder or HDR tone mapping. [Source provenance](PROVENANCE.md) and
[third-party notices](THIRD_PARTY_NOTICES.md) retain the original attribution.
The [pre-extraction implementation and reference documentation](https://github.com/0717lee/pixelforge/tree/6f0c711c54f89d34f3e2ef97cde7a0a45458583d)
remain available in PixelForge history. Extraction does not remove that history
or reclassify the previous work as new implementation.
