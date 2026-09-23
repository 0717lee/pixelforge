#!/usr/bin/env python3
"""Generate the AV1 general (non reduced-still) frame-header fixtures.

Phase D of the AVIF decoder needs real multi-frame bitstreams: every earlier
fixture is a reduced still picture, which hides the whole inter-frame grammar
(show_existing_frame, frame_type, order_hint, the reference list,
interpolation/motion-mode signalling, reference_select, allow_warped_motion and
global_motion).

Each fixture is one untouched libaom encode of deterministic input.  The
script records the encoder command line, the FFmpeg ``trace_headers``
transcript, and dav1d's native planes.  The transcript is the syntax oracle:
the declared expectations in FIXTURES are checked against it, so a parser that
silently re-syncs onto a different bit offset fails here rather than in the
MoonBit suite.

Usage:
    python scripts/generate-av1-inter-reference.py
    python scripts/generate-av1-inter-reference.py --check
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE_DIR = os.path.join(ROOT, "tests", "fixtures", "av1-inter")

AOMENC = r"D:\ProgramData\anaconda3\Library\bin\aomenc.EXE"
DAV1D = r"D:\ProgramData\anaconda3\Library\bin\dav1d.EXE"
FFMPEG = os.path.join(
    os.path.expanduser("~"),
    "AppData",
    "Local",
    "Microsoft",
    "WinGet",
    "Packages",
    "Gyan.FFmpeg.Shared_Microsoft.Winget.Source_8wekyb3d8bbwe",
    "ffmpeg-9.0.1-full_build-shared",
    "bin",
    "ffmpeg.exe",
)

WIDTH, HEIGHT, FRAMES = 64, 64, 2

# Inter-tool switches for the "everything off" fixture.  libaom segfaults past
# two frames in the anaconda build, so every fixture here is key + one inter
# frame; the simplest possible block syntax keeps the first inter milestone
# debuggable.
# The adaptive-quantisation encode: the base flags with the order hint on,
# which is what makes the inter frame's `primary_ref_frame` and reference list
# answer the way a real playback stream does.
AQ_FLAGS = [
    "--error-resilient=0",
    "--enable-dual-filter=0",
    "--enable-order-hint=1",
    "--enable-ref-frame-mvs=0",
    "--enable-warped-motion=0",
    "--enable-obmc=0",
    "--enable-global-motion=0",
    "--enable-masked-comp=0",
    "--enable-dist-wtd-comp=0",
    "--enable-diff-wtd-comp=0",
    "--enable-interintra-comp=0",
    "--enable-interinter-wedge=0",
    "--enable-interintra-wedge=0",
    "--enable-onesided-comp=0",
    "--enable-tx64=0",
    "--enable-intrabc=0",
    "--enable-palette=0",
]

MINIMAL_FLAGS = [
    "--error-resilient=0",
    "--enable-dual-filter=0",
    "--enable-order-hint=0",
    "--enable-ref-frame-mvs=0",
    "--enable-warped-motion=0",
    "--enable-obmc=0",
    "--enable-global-motion=0",
    "--enable-masked-comp=0",
    "--enable-dist-wtd-comp=0",
    "--enable-diff-wtd-comp=0",
    "--enable-interintra-comp=0",
    "--enable-interinter-wedge=0",
    "--enable-interintra-wedge=0",
    "--enable-onesided-comp=0",
    "--enable-tx64=0",
    "--enable-intrabc=0",
    "--enable-palette=0",
]

# Frame-header facts taken from the FFmpeg transcript, keyed by the transcript's
# own field names.  `None` means "this field is not present in the transcript".
GENERAL_SEQUENCE = {
    "seq_profile": 0,
    "still_picture": 0,
    "reduced_still_picture_header": 0,
    "timing_info_present_flag": 0,
    "initial_display_delay_present_flag": 0,
    "operating_points_cnt_minus_1": 0,
    "frame_id_numbers_present_flag": 0,
    "use_128x128_superblock": 1,
    "enable_filter_intra": 1,
    "enable_intra_edge_filter": 1,
    "enable_interintra_compound": 1,
    "enable_masked_compound": 1,
    "enable_warped_motion": 1,
    "enable_dual_filter": 1,
    "enable_order_hint": 1,
    "enable_jnt_comp": 1,
    "enable_ref_frame_mvs": 1,
    "seq_choose_screen_content_tools": 1,
    "seq_choose_integer_mv": 1,
    "order_hint_bits_minus_1": 6,
    "enable_superres": 0,
    "enable_cdef": 1,
    "enable_restoration": 1,
    "high_bitdepth": 0,
    "mono_chrome": 0,
    "separate_uv_delta_q": 0,
    "film_grain_params_present": 0,
}

FIXTURES = [
    {
        "name": "general_inter_64x64",
        "flags": [],
        # Frame 0 is a key frame behind a general header; frame 1 is inter.
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "frame_size_override_flag": 0,
                "order_hint": 0,
                "render_and_frame_size_different": 0,
                "disable_frame_end_update_cdf": 0,
                "segmentation_enabled": 0,
                "delta_q_present": 0,
                "using_qmatrix": 0,
                "reduced_tx_set": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "frame_size_override_flag": 0,
                "order_hint": 1,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "frame_refs_short_signaling": 0,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[1]": 0,
                "ref_frame_idx[2]": 0,
                "ref_frame_idx[3]": 0,
                "ref_frame_idx[4]": 0,
                "ref_frame_idx[5]": 0,
                "ref_frame_idx[6]": 0,
                "render_and_frame_size_different": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 1,
                "use_ref_frame_mvs": 1,
                "disable_frame_end_update_cdf": 0,
                "segmentation_enabled": 0,
                "delta_q_present": 0,
                "using_qmatrix": 0,
                "reference_select": 0,
                "allow_warped_motion": 1,
                "reduced_tx_set": 0,
                "is_global[1]": 0,
                "is_global[4]": 0,
                "is_global[7]": 0,
            },
        ],
        "sequence_expectations": GENERAL_SEQUENCE,
        "decode_frames": 1,
    },
    {
        "name": "inter_minimal_64x64",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "disable_frame_end_update_cdf": 0,
                "reference_select": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # Two fixtures whose inter tree stays coarse on purpose: the sub-8-tap and
    # entropy work is easiest to settle where aom does not answer a whole-frame
    # motion with a thicket of 4x16 strips (see inter_minimal_64x64, which does).
    {
        "name": "inter_still_64x64",
        "input": "still",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                # A repeated frame needs no switchable filter, so this fixture
                # also covers the fixed `interpolation_filter` path.
                "is_filter_switchable": 0,
                "interpolation_filter": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
                # Both levels zero means loop_filter_level[2..3] are not even
                # signalled (see AV1 6.8.2), so deblocking is a no-op here.
                "loop_filter_level[0]": 0,
                "loop_filter_level[1]": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 0,
                "cdef_bits": 0,
                "lr_type[0]": 0,
                "lr_type[1]": 0,
                "lr_type[2]": 0,
                "reduced_tx_set": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        "name": "inter_shift_64x64",
        "input": "shift",
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                # The fractional translation makes aom switch the interpolation
                # filter on, so the per-block filter symbol is exercised.
                "is_filter_switchable": 1,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
                # Chroma levels are zero, so only Y is deblocked here - and this
                # wave is so smooth that dav1d's output does not move whatever the
                # Y level is, which is why the loop-filter fixture is not based on
                # it.
                "loop_filter_level[0]": 0,
                "loop_filter_level[1]": 4,
                "loop_filter_level[2]": 0,
                "loop_filter_level[3]": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 0,
                "cdef_bits": 0,
                "lr_type[0]": 0,
                "lr_type[1]": 0,
                "lr_type[2]": 0,
                "reduced_tx_set": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # A 64x16 frame is the smallest stream found so far that reproduces the
    # inter right-edge defect: the frame decodes (the tile budget fits), the key
    # frame is exact, and only the last three luma columns and the last chroma
    # column are wrong. Keep this fixture even while the pixels are known-bad:
    # it is the reproducer for the empty motion-vector-stack bug.
    {
        "name": "inter_edge_64x16",
        "input": "strip",
        "width": 64,
        "height": 16,
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # The encoder will not produce a loop-filter delta update at all here, so this
    # fixture takes inter_minimal_64x64's verified bytes and rewrites the frame
    # header's loop-filter fields by hand (see splice_loop_filter_deltas). Its
    # pixels are dav1d's, regenerated from the spliced stream like any other
    # fixture, and the FFmpeg transcript below is the syntax evidence.
    #
    # The base levels are not decorative: inter_minimal's sawtooth ramp varies
    # only along x, so a vertical Y level is what makes deblocking visible, and
    # the horizontal level is deliberately at the 32 boundary to give the two
    # directions different nShift values.
    {
        "name": "inter_lf_delta_64x64",
        "splice": {
            "base": "inter_minimal_64x64",
            "frame": 1,
            "header_bytes": 14,
            "level_bit": 76,
            "delta_update_bit": 92,
            "levels": [30, 33, 20, 16],
            # The rows this frame actually reads carry the negative deltas: an
            # inter block takes LAST and modeType 1, an intra block takes INTRA.
            # Both signs therefore appear where a filtered edge can show them,
            # and the four rows are distinct so a wrong index moves a sample.
            "ref_deltas": {0: 3, 1: -6, 2: 5, 3: -2},
            "mode_deltas": {0: 2, 1: -4},
        },
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
                "loop_filter_level[0]": 30,
                "loop_filter_level[1]": 33,
                "loop_filter_level[2]": 20,
                "loop_filter_level[3]": 16,
                "loop_filter_sharpness": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 1,
                "loop_filter_ref_deltas[0]": 3,
                "loop_filter_ref_deltas[1]": -6,
                "loop_filter_ref_deltas[2]": 5,
                "loop_filter_ref_deltas[3]": -2,
                "loop_filter_mode_deltas[0]": 2,
                "loop_filter_mode_deltas[1]": -4,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # The frame-context inheritance fixture. Every stream this encoder produces
    # here says primary_ref_frame = PRIMARY_REF_NONE, because within a two-frame
    # group there is nothing worth inheriting, so the load_cdfs / load_previous
    # branch of AV1 5.11 is otherwise unreachable. Two same-width header fields
    # are rewritten in place to get there: the key frame's
    # disable_frame_end_update_cdf becomes 1 (so the distributions it leaves
    # behind are the fresh ones the inter frame's tile was in fact coded against)
    # and the inter frame's primary_ref_frame becomes 0, which names that key
    # frame through ref_frame_idx[0]. dav1d's planes are regenerated from the
    # result; they measured identical to the base stream's, which is what makes
    # this a usable first rung - see the README.
    {
        "name": "inter_primary_ref_64x64",
        "patch": {
            "base": "inter_minimal_64x64",
            "patches": [
                {
                    "frame": 0,
                    "bit": 24,
                    "width": 1,
                    "expect": 0,
                    "value": 1,
                },
                {
                    "frame": 1,
                    "bit": 24,
                    "width": 3,
                    "expect": 7,
                    "value": 0,
                },
            ],
        },
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 0,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # The same field rewritten on its own, with the key frame left alone: this is
    # the stream that actually *needs* the inherited entropy state. Its tile bits
    # were coded against freshly initialised distributions, but the header now
    # loads the key frame's adapted ones, so a decoder that starts from scratch
    # disagrees with dav1d over most of the picture. Measured at generation time,
    # that disagreement is pinned in the test as explicit per-plane sample counts
    # until the snapshot in AV1 7.21 exists; the counts are the fence.
    {
        "name": "inter_cdf_inherit_64x64",
        "patch": {
            "base": "inter_minimal_64x64",
            "patches": [
                {
                    "frame": 1,
                    "bit": 24,
                    "width": 3,
                    "expect": 7,
                    "value": 0,
                },
            ],
        },
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "primary_ref_frame": 0,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_motion_mode_switchable": 0,
                "reference_select": 0,
                "delta_q_present": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        "name": "inter_compound_64x64",
        "patch": {
            "base": "inter_shift_64x64",
            "patches": [
                {
                    "frame": 1,
                    "bit": 128,
                    "width": 1,
                    "expect": 0,
                    "value": 1,
                },
            ],
        },
        "flags": MINIMAL_FLAGS,
        "frames": [
            {
                "show_existing_frame": 0,
                "frame_type": 0,
                "show_frame": 1,
                "disable_frame_end_update_cdf": 0,
            },
            {
                "show_existing_frame": 0,
                "frame_type": 1,
                "show_frame": 1,
                "error_resilient_mode": 0,
                "disable_cdf_update": 0,
                "allow_screen_content_tools": 0,
                "primary_ref_frame": 7,
                "refresh_frame_flags": 2,
                "ref_frame_idx[0]": 0,
                "ref_frame_idx[6]": 0,
                "allow_high_precision_mv": 0,
                "is_filter_switchable": 1,
                "is_motion_mode_switchable": 0,
                # The one patched bit: the block layer now reads comp_mode, and
                # libaom never emits it for this two-frame group.
                "reference_select": 1,
                "delta_q_present": 0,
                "loop_filter_level[0]": 0,
                "loop_filter_level[1]": 4,
                "loop_filter_level[2]": 0,
                "loop_filter_level[3]": 0,
                "loop_filter_delta_enabled": 1,
                "loop_filter_delta_update": 0,
                "cdef_bits": 0,
                "lr_type[0]": 0,
                "lr_type[1]": 0,
                "lr_type[2]": 0,
                "reduced_tx_set": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        "name": "inter_skipmode_64x64",
        "frame_count": 3,
        "patched_encode": {
            "append_frame_copy": True,
            "input": "shift",
            "flags": [
                "--error-resilient=0",
                "--enable-dual-filter=0",
                "--enable-order-hint=1",
                "--enable-ref-frame-mvs=0",
                "--enable-warped-motion=0",
                "--enable-obmc=0",
                "--enable-global-motion=0",
                "--enable-masked-comp=0",
                "--enable-dist-wtd-comp=0",
                "--enable-diff-wtd-comp=0",
                "--enable-interintra-comp=0",
                "--enable-interinter-wedge=0",
                "--enable-interintra-wedge=0",
                "--enable-onesided-comp=0",
                "--enable-tx64=0",
                "--enable-intrabc=0",
                "--enable-palette=0",
            ],
            # Frame 2 is a byte copy of frame 1 appended behind a temporal
            # delimiter; these bit positions are the trace's for that frame.
            # The key frame's order hint is moved ahead of the copy's, the
            # copy's LAST2 is repointed at the middle frame's slot, and the
            # copy's own hint is set between the two so the derivation finds
            # one reference on either side.
            "patches": [
                {"frame": 0, "bit": 23, "width": 7, "expect": 0, "value": 7},
                {"frame": 2, "bit": 24, "width": 7, "expect": 1, "value": 2},
                {"frame": 2, "bit": 46, "width": 3, "expect": 0, "value": 1},
                {"frame": 2, "bit": 136, "width": 1, "expect": 0, "value": 1},
                {"frame": 2, "bit": 137, "width": 1, "expect": 0, "value": 1},
            ],
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 0,
                "order_hint": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 1,
                "skip_mode_present": 1,
                "order_hint": 2,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 2,
    },
    {
        "name": "inter_distcomp_64x64",
        "patched_encode": {
            "append_frame_copy": False,
            "input": "shift",
            "flags": [
                "--error-resilient=0",
                "--enable-dual-filter=0",
                # Order hints are what the distance weighting reads its
                # distances from, and the jnt-comp switches are what make the
                # compound blocks code `compound_idx` instead of always
                # averaging.
                "--enable-order-hint=1",
                "--enable-diff-wtd-comp=1",
                "--enable-dist-wtd-comp=1",
                "--enable-masked-comp=0",
                "--enable-ref-frame-mvs=0",
                "--enable-warped-motion=0",
                "--enable-obmc=0",
                "--enable-global-motion=0",
                "--enable-interintra-comp=0",
                "--enable-interinter-wedge=0",
                "--enable-interintra-wedge=0",
                "--enable-onesided-comp=0",
                "--enable-tx64=0",
                "--enable-intrabc=0",
                "--enable-palette=0",
            ],
            "patches": [
                {"frame": 1, "bit": 136, "width": 1, "expect": 0, "value": 1},
            ],
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 1,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        # The difference-weighted compound blend. Two header edits plus one bit
        # of the inter frame's tile entropy: the same `reference_select` bit
        # that opens the compound grammar, `enable_masked_compound` in the
        # sequence header, and one flipped bit of the tile payload (byte 17 of
        # frame 1's payload). The first two are equal-width header rewrites;
        # the third changes how the symbols after it decode, which is what makes
        # a compound block exist at all - libaom never emits one for a
        # two-frame group. A 32x8 block then reads `comp_group_idx` 1 and
        # `compound_type` as COMPOUND_DIFFWTD.
        "name": "inter_diffwtd_64x64",
        "patched_encode": {
            "append_frame_copy": False,
            "input": "shift",
            "flags": [
                "--error-resilient=0",
                "--enable-dual-filter=0",
                "--enable-order-hint=1",
                "--enable-diff-wtd-comp=1",
                "--enable-dist-wtd-comp=1",
                "--enable-masked-comp=0",
                "--enable-ref-frame-mvs=0",
                "--enable-warped-motion=0",
                "--enable-obmc=0",
                "--enable-global-motion=0",
                "--enable-interintra-comp=0",
                "--enable-interinter-wedge=0",
                "--enable-interintra-wedge=0",
                "--enable-onesided-comp=0",
                "--enable-tx64=0",
                "--enable-intrabc=0",
                "--enable-palette=0",
            ],
            "patches": [
                {"frame": 1, "bit": 136, "width": 1, "expect": 0, "value": 1},
            ],
            "seq_patch": {"bit": 70, "width": 1, "expect": 0, "value": 1},
            "tile_patches": [
                {"frame": 1, "offset": 17, "bit": 5, "expect": 0},
            ],
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 1,
            },
        ],
        "sequence_expectations": {
            "enable_masked_compound": 1,
        },
        "decode_frames": 1,
    },
    {
        # Global motion: the one rung no libaom flag can produce for these
        # groups. `inject_global_motion` sets is_global for LAST_FRAME on
        # inter_minimal_64x64 and writes a translation model against the default
        # identity, which shifts the rest of the header by the inserted width.
        # No block asks for GLOBAL(Global)MV in the base, so the picture is
        # unchanged - which is what makes the inserted width measurable: a
        # wrong width desynchronises the header and moves the pixels.
        "name": "inter_globalmv_64x64",
        "gm_inject": {
            "base": "inter_minimal_64x64",
            "frame": 1,
            "gm_offset": 102,
            "base_header_bytes": 14,
            "allow_high_precision_mv": False,
            "translation": (3, -5),
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 0,
                # The transcript's own gm_params values are the raw subexp
                # symbols, which is the encodable form of the two deltas - the
                # frame gate and the model both come from them.
                "gm_params[1][0]": 6,
                "gm_params[1][1]": 9,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        # The rotate-zoom global-motion rung, and the reason the frame gate can
        # open for models beyond a translation: `av1_warp_predict` drives a
        # GLOBAL(Global)MV block through the model per pixel, exactly as it
        # drives a LOCALWARP block. The injected model is a small rotation with
        # a 512/65536 x scale and a 256/65536 shear, which the shear test keeps
        # representable; no block of the base asks for GLOBAL(Global)MV, but a
        # non-translation model still removes the subpel filter symbol those
        # blocks would read, so the tiles re-symbolise and the reference planes
        # are committed for that decode.
        "name": "inter_globalmv_rotzoom_64x64",
        "gm_inject": {
            "base": "inter_minimal_64x64",
            "frame": 1,
            "gm_offset": 102,
            "base_header_bytes": 14,
            "allow_high_precision_mv": False,
            "model": "rotzoom",
            "matrix": [0, 0, 65536 + 512, 256],
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 0,
                # The transcript's own values are the raw subexp symbols, which
                # is the encodable form of the two coefficients that are coded;
                # the second model row and the translation follow from them.
                "gm_params[1][2]": 512,
                "gm_params[1][3]": 256,
                "gm_params[1][0]": 0,
                "gm_params[1][1]": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        # LOCALWARP. `inter_warped_64x64` is the one stream whose inter frame
        # reads the three-symbol `motion_mode` branch - its blocks sit where
        # `find_warp_samples` reports a candidate - and libaom codes every one
        # of them SIMPLE, because a uniform translation costs less than a warp
        # model. Flipping one bit of that frame's tile payload makes a block
        # decode LOCALWARP instead, and the symbols after it re-symbolise; the
        # bit was found by brute force with the debug dav1d build, which prints
        # every block's decoded motion mode.
        "name": "inter_localwarp_64x64",
        "tile_patch_of": {
            "base": "inter_warped_64x64",
            "name": "inter_localwarp_64x64",
            "offset": 67,
            "bit": 0,
            "expect": 1,
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 0,
                "allow_warped_motion": 1,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    {
        "name": "inter_interintra_64x64",
        "patched_encode": {
            "append_frame_copy": False,
            "input": "ramp",
            "flags": list(MINIMAL_FLAGS),
            # One equal-width bit in the sequence header turns the interintra
            # grammar on for a group libaom never picks it for.
            "seq_patch": {"bit": 69, "width": 1, "expect": 0, "value": 1},
            "patches": [],
        },
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "reference_select": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
    # The only stream in the repository whose encoder actually writes a segment
    # map: `--aq-mode=2` (complexity adaptive quantization) makes libaom spend
    # `segmentation_enabled` on the key frame with one ALT_Q feature per active
    # segment, and to re-flag the inter frame's map update on the following
    # frame. Nothing else here reaches `segment_id`, which is exactly the piece
    # the residual stage needed.
    {
        "name": "inter_segmentation_64x64",
        "input": "ramp",
        "flags": AQ_FLAGS + ["--aq-mode=2"],
        "frames": [
            {
                "frame_type": 0,
                "show_frame": 1,
                "base_q_idx": 49,
                "segmentation_enabled": 1,
                # ALT_Q only: the loop-filter, reference, skip and global-motion
                # levels are what the decoder still refuses, so asserting their
                # absence is what keeps this fixture decodable.
                "feature_enabled[0][0]": 1,
                "feature_enabled[1][0]": 1,
                "feature_enabled[2][0]": 1,
                "feature_enabled[3][0]": 0,
                "feature_enabled[4][0]": 1,
                "feature_enabled[5][0]": 0,
                "feature_enabled[6][0]": 0,
                "feature_enabled[7][0]": 0,
                "feature_value[0][0]": -28,
                "feature_value[1][0]": -18,
                "feature_value[2][0]": -7,
                "feature_value[4][0]": 10,
                "delta_q_present": 0,
            },
            {
                "frame_type": 1,
                "show_frame": 1,
                "base_q_idx": 128,
                "segmentation_enabled": 1,
                "feature_enabled[0][0]": 0,
                "primary_ref_frame": 7,
                "delta_q_present": 0,
            },
        ],
        "sequence_expectations": None,
        "decode_frames": 1,
    },
]


def encode_input(path: str, kind: str = "ramp", width: int = 64, height: int = 64) -> None:
    """Write the deterministic 2-frame 4:2:0 source selected by ``kind``.

    A slowly translating ramp gives the encoder a clean single-reference motion
    field, which is what the first inter milestone needs; the chroma planes
    shift per frame so chroma motion compensation is exercised too.

    The two additional sources exist because aom's partition search on ``ramp``
    descends into narrow 4x16 strips, which is the hardest possible tree to
    debug entropy against.  ``still`` (frame 1 repeats frame 0 exactly) and
    ``shift`` (a true half-pixel translation of a band-limited sinusoid, so no
    discontinuity invites fine splits) keep the inter tree coarse; ``shift``
    additionally forces a fractional motion vector, which is what exercises the
    8-tap interpolation kernel rather than a plain copy.
    """
    cw, ch = width // 2, height // 2
    header = "YUV4MPEG2 W%d H%d F1:1 Ip A1:1 C420mpeg2\n" % (width, height)
    frames = []
    for n in range(FRAMES):
        if kind == "strip":
            # The sawtooth of ``ramp`` in strict raster order for every plane.
            # Byte layout matters: this is the source that reproduces the
            # right-edge inter defect on a 64x16 frame, where the ramp's own
            # chroma layout does not.
            luma = bytes(
                max(0, min(255, 40 + ((x + n * 3) % 32)))
                for y in range(height)
                for x in range(width)
            )
            cb = bytes((128 + (y % 5) + n) & 0xFF for y in range(ch) for x in range(cw))
            cr = bytes((120 + (x % 7) - n) & 0xFF for y in range(ch) for x in range(cw))
        elif kind == "still":
            luma = bytes(
                max(0, min(255, 96 + 3 * (y % 16) + (x % 8)))
                for y in range(height)
                for x in range(width)
            )
            cb = bytes([(128 + (y % 6)) & 0xFF for _ in range(cw) for y in range(ch)])
            cr = bytes([(120 + (x % 6)) & 0xFF for y in range(ch) for x in range(cw)])
        elif kind == "shift":
            # Frame 1 is sampled 2.5 luma pixels further along a small-amplitude
            # horizontal sinusoid, so the true motion is fractional and uniform
            # over the whole frame and no discontinuity invites fine splits.
            #
            # The amplitude and periods are not cosmetic: this libaom build
            # segfaults at encoder teardown on higher-contrast translations
            # (a 44-count, period-48 wave of the same shape crashes), so the
            # source stays deliberately gentle.
            def smooth(
                x: float, y: float, off: float, period: float, vertical: float
            ) -> int:
                return max(
                    0,
                    min(
                        255,
                        int(
                            round(
                                128.0
                                + 8.0 * math.sin(2.0 * math.pi * (x - off) / period)
                                + vertical * math.sin(2.0 * math.pi * y / 32.0)
                            )
                        ),
                    ),
                )

            off = 2.5 * n
            luma = bytes(
                smooth(float(x), float(y), off, 64.0, 10.0)
                for y in range(height)
                for x in range(width)
            )
            # Chroma samples the same shape half as often horizontally, and keeps
            # the identical displacement in chroma units, i.e. five luma pixels.
            cb = bytes(
                smooth(2.0 * x, float(y), off, 128.0, 2.0)
                for y in range(ch)
                for x in range(cw)
            )
            cr = bytes(
                smooth(2.0 * x, float(y), off, 128.0, 2.0)
                for y in range(ch)
                for x in range(cw)
            )
        else:
            luma = bytes(
                max(0, min(255, 40 + ((x + n * 3) % 32)))
                for _ in range(height)
                for x in range(width)
            )
            cb = bytes([(128 + (y % 5) + n) & 0xFF for _ in range(cw) for y in range(ch)])
            cr = bytes([(120 + (x % 7) - n) & 0xFF for y in range(ch) for x in range(cw)])
        assert len(luma) == width * height
        assert len(cb) == cw * ch and len(cr) == cw * ch
        frames.append(luma + cb + cr)
    with open(path, "wb") as fh:
        fh.write(header.encode())
        for frame in frames:
            fh.write(b"FRAME\n" + frame)


def trace_fields(obu: str, committed: str) -> list[dict[str, int]]:
    """Parse FFmpeg's trace_headers output into one field dict per frame.

    The transcript is written to `committed` (the shipped `.trace.txt`) from the
    freshly encoded `obu`, so checking never rewrites evidence from a stale file.
    """
    proc = subprocess.run(
        [
            FFMPEG,
            "-hide_banner",
            "-bsf:v",
            "trace_headers",
            "-i",
            obu,
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    text = re.sub(r"\[trace_headers @ [0-9a-f]+\] ", "", proc.stdout + proc.stderr)
    # FFmpeg appends its own muxing summary, which carries a heap address and a
    # speed figure.  Neither is evidence, and leaving them in rewrote the
    # committed transcripts on every run.
    cut = text.find("Output #")
    if cut >= 0:
        text = text[:cut].rstrip() + "\n"
    with open(committed, "w", encoding="utf-8") as fh:
        fh.write(text)
    frames: list[dict[str, int]] = []
    current: dict[str, int] | None = None
    for line in text.splitlines():
        if line.startswith("Frame Header"):
            current = {}
            frames.append(current)
            continue
        if line.startswith("Tile Group") or line.startswith("Sequence Header"):
            current = None
            continue
        if current is None:
            continue
        m = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
        if m:
            current[m.group(1)] = int(m.group(2))
    return frames


def sequence_fields(trace_path: str) -> dict[str, int]:
    """Re-read the transcript for the sequence header block."""
    with open(trace_path, encoding="utf-8") as fh:
        text = fh.read()
    fields: dict[str, int] = {}
    inside = False
    for line in text.splitlines():
        if line.startswith("Sequence Header"):
            inside = True
            continue
        if inside and line.startswith("Frame Header"):
            break
        if not inside:
            continue
        m = re.match(r"\s*\d+\s+(\S+)\s+\S*\s*=\s*(-?\d+)\s*$", line)
        if m:
            fields[m.group(1)] = int(m.group(2))
    return fields


def check_expectations(label: str, fields: dict[str, int], expected: dict[str, int]) -> None:
    for key, value in expected.items():
        if key not in fields:
            raise SystemExit("FAIL %s: transcript has no %s" % (label, key))
        if fields[key] != value:
            raise SystemExit(
                "FAIL %s: %s is %d, expected %d" % (label, key, fields[key], value)
            )


def _split_bits(data: bytes) -> list[int]:
    return [(byte >> i) & 1 for byte in data for i in range(7, -1, -1)]


def _pack_bits(bits: list[int]) -> bytes:
    while len(bits) % 8:
        bits = bits + [0]
    out = bytearray()
    for start in range(0, len(bits), 8):
        value = 0
        for bit in bits[start : start + 8]:
            value = (value << 1) | bit
        out.append(value)
    return bytes(out)


def _leb128(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def frame_obus(data: bytes) -> list[tuple[int, int, int]]:
    """Every OBU_FRAME, as (header start, payload start, payload length)."""
    found: list[tuple[int, int, int]] = []
    pos = 0
    while pos < len(data):
        header = data[pos]
        kind = (header >> 3) & 0x0F
        scan = pos + 1
        if (header >> 2) & 1:
            scan += 1
        size = 0
        shift = 0
        if (header >> 1) & 1:
            while True:
                byte = data[scan]
                size |= (byte & 0x7F) << shift
                scan += 1
                shift += 7
                if not byte & 0x80:
                    break
        if kind == 6:
            found.append((pos, scan, size))
        pos = scan + size
    return found


def _bits_of(value : int, count : int) -> list[int]:
    return [(value >> (count - 1 - i)) & 1 for i in range(count)]


def _ns_bits(value : int, count : int) -> list[int]:
    """The bits `decode_unsigned_max(count)` reads for `value` in [0, count)."""
    if count <= 1:
        return []
    width = count.bit_length()
    m = (1 << width) - count
    if value < m:
        return _bits_of(value, width - 1)
    shifted = value + m
    return _bits_of(shifted >> 1, width - 1) + _bits_of(shifted & 1, 1)


def _subexp_bits(value : int, num_syms : int) -> list[int]:
    """The bits `decode_subexp(num_syms)` reads to return `value`."""
    out : list[int] = []
    i = 0
    mk = 0
    while True:
        b = 3 if i == 0 else 3 + i - 1
        a = 1 << b
        if num_syms <= mk + 3 * a:
            return out + _ns_bits(value - mk, num_syms - mk)
        if value < mk + a:
            return out + [0] + _bits_of(value - mk, b)
        out.append(1)
        i += 1
        mk += a


def _recenter(r : int, x : int) -> int:
    """The `v` that `inverse_recenter(r, v)` maps to `x`."""
    if x > 2 * r:
        return x
    if x >= r:
        return 2 * (x - r)
    return 2 * (r - x) - 1


def _write_signed_subexp_with_ref(delta : int, mx : int, ref : int) -> list[int]:
    """Bits for `decode_signed_subexp_with_ref(-mx, mx + 1, ref) == delta`."""
    num_syms = 2 * mx + 1
    r = ref + mx
    x = delta + mx
    if (r << 1) <= num_syms:
        v = _recenter(r, x)
    else:
        v = _recenter(num_syms - 1 - r, num_syms - 1 - x)
    return _subexp_bits(v, num_syms)


def _write_global_param(mat_value : int, prev_value : int, idx : int,
                        abs_bits : int, prec_bits : int) -> list[int]:
    """Bits for one `read_global_param` (AV1 5.9.24).

    `mat_value` is the model coefficient in WARPEDMODEL_PREC_BITS units,
    `prev_value` the inherited one, and `idx` the coefficient's position: the
    diagonal entries (idx 2 and 5) carry the identity bias and are coded one bit
    finer than the rest, which is what the halved reference in libdav1d's parser
    encodes.
    """
    prec_diff = 16 - prec_bits
    bias = (1 << 16) if idx % 3 == 2 else 0
    sub = (1 << prec_bits) if idx % 3 == 2 else 0
    mx = 1 << abs_bits
    base = (prev_value >> prec_diff) - sub
    delta = (mat_value - bias) >> prec_diff
    return _write_signed_subexp_with_ref(delta, mx, base)


def inject_global_motion(spec: dict) -> bytes:
    """Signal a translation warp model for one reference of a frame header.

    libaom will not emit global motion for these tiny groups whatever the
    encoder flags say: the neighbour-based motion predictor makes a uniform
    translation cost less per block than the model's own ~30 bits, so every
    `is_global` comes back zero. The rewrite takes the committed base stream,
    sets `is_global` for LAST_FRAME, writes a TRANSLATION model against the
    inherited default, and shifts the rest of the header by the inserted width.
    Nothing else moves: the tile payload is byte-aligned behind the
    uncompressed header, so it is copied through untouched and the picture it
    decodes to is identical to the base's. That the inserted width is exactly
    what the grammar reads is then provable in both directions - the frame
    decodes, and dav1d's planes do not move.
    """
    base = os.path.join(FIXTURE_DIR, spec["base"] + ".obu")
    data = open(base, "rb").read()
    frames = frame_obus(data)
    start, payload_at, size = frames[spec["frame"]]
    bits = _split_bits(data[payload_at : payload_at + size])
    at = spec["gm_offset"]
    header_bits = spec["base_header_bytes"] * 8
    assert bits[at] == 0, "%s already models reference 1" % spec["base"]
    assert bits[at + 1 : at + 8] == [0] * 7, "%s models another reference" % spec["base"]
    # A translation model codes only its two components, and both are coded
    # against the default identity model because the base names PRIMARY_REF_NONE.
    model = spec.get("model", "translation")
    if model == "translation":
        hp = 0 if spec["allow_high_precision_mv"] else 1
        abs_bits = 9 - hp
        mx = 1 << abs_bits
        row, col = spec["translation"]
        # is_global, is_rot_zoom = 0, is_translation = 1.
        inserted : list[int] = [1, 0, 1]
        inserted += _write_signed_subexp_with_ref(row, mx, 0)
        inserted += _write_signed_subexp_with_ref(col, mx, 0)
    elif model == "rotzoom":
        # is_global, is_rot_zoom = 1. The second model row is derived from the
        # first by the grammar, so only two coefficients are coded, and the
        # translation components then follow on the affine model's own
        # precision (12 absolute bits, 6 precision bits).
        mat = spec["matrix"]
        inserted : list[int] = [1, 1]
        inserted += _write_global_param(mat[2], 1 << 16, 2, 12, 15)
        inserted += _write_global_param(mat[3], 0, 3, 12, 15)
        inserted += _write_global_param(mat[0], 0, 0, 12, 6)
        inserted += _write_global_param(mat[1], 0, 1, 12, 6)
    else:
        raise SystemExit("unknown global-motion model %r" % model)
    out = bits[:at] + inserted + bits[at + 1 : header_bits]
    while len(out) % 8:
        out.append(0)
    # The tile payload is byte-aligned behind the header in the *base*, so it
    # starts at `base_header_bytes`; the new header is wider, and only the
    # bytes after the new one are untouched header padding.
    payload = (
        _pack_bits(out)
        + data[payload_at + spec["base_header_bytes"] : payload_at + size]
    )
    body = bytearray()
    body.append((6 << 3) | (1 << 1))
    body += _leb128(len(payload))
    body += payload
    return data[:start] + bytes(body) + data[payload_at + size :]


def inject_tile_patch_of(spec: dict) -> bytes:
    """Flip one bit of an already committed frame's tile entropy.

    `inter_warped_64x64` is the one stream whose inter frame reads the
    three-symbol `motion_mode` branch at all - its blocks sit where
    `find_warp_samples` finds a candidate - and libaom codes every one of them
    SIMPLE. One bit of the tile payload flipped is what makes a block decode
    LOCALWARP instead: the symbols after it re-symbolise into a different legal
    decode, which dav1d's planes on the patched stream are the truth for. The
    offender is found by brute force with the instrumented dav1d, which prints
    every block's decoded motion mode.
    """
    base = os.path.join(FIXTURE_DIR, spec["base"] + ".obu")
    data = open(base, "rb").read()
    index = spec["offset"]
    if index >= len(data):
        raise SystemExit("%s: tile patch %d out of range" % (spec["name"], index))
    current = data[index]
    bit = (current >> spec["bit"]) & 1
    assert bit == spec["expect"], (
        "%s: byte %d bit %d is %d, expected %d"
        % (spec["name"], spec["offset"], spec["bit"], bit, spec["expect"])
    )
    return data[:index] + bytes([current ^ (1 << spec["bit"])]) + data[index + 1 :]


def splice_loop_filter_deltas(spec: dict) -> bytes:
    """Rewrite one verified frame header's loop filter configuration.

    libaom will not emit what Phase D needs here: it writes
    ``loop_filter_delta_update = 0`` whatever ``--delta-lf-mode`` says, and it
    picks zero base levels for these tiny streams, which leaves the whole frame
    undeblocked. Every field involved - ``f(6)`` levels,
    ``f(1)`` flags and ``su(1+6)`` values - is a raw fixed-width bit field in the
    uncompressed header, so rewriting them only shifts the following header
    syntax. The tile's entropy-coded payload is copied unchanged, which is why
    the inserted width has to come out a whole number of bytes.

    ``level_bit`` and ``delta_update_bit`` are FFmpeg trace positions, which count
    from the start of the OBU header, and ``header_bytes`` is the width of the
    uncompressed header in the base stream.
    """
    base = os.path.join(FIXTURE_DIR, spec["base"] + ".obu")
    data = open(base, "rb").read()
    frames = frame_obus(data)
    start, payload_at, size = frames[spec["frame"]]
    header_bits = spec["header_bytes"] * 8
    bits = _split_bits(data[payload_at : payload_at + size])
    shift = (payload_at - start) * 8
    level = spec["level_bit"] - shift
    update = spec["delta_update_bit"] - shift
    # The base stream must be in the configuration being left behind: both Y
    # levels zero, so no chroma levels are coded and no filtering happens.
    assert bits[level : level + 12] == [0] * 12, "%s already filters" % spec["base"]
    assert bits[level + 15] == 1, "%s has loop_filter_delta_enabled = 0" % spec["base"]
    assert bits[update] == 0, "%s already carries delta updates" % spec["base"]

    inserted: list[int] = [1]
    for index, values in (
        (range(8), spec["ref_deltas"]),
        (range(2), spec["mode_deltas"]),
    ):
        for i in index:
            if i in values:
                inserted.append(1)
                # su(1+6) is a seven-bit two's complement value, so a negative
                # delta is written with its top bit set.
                for bit in range(6, -1, -1):
                    inserted.append((values[i] & 0x7F) >> bit & 1)
            else:
                inserted.append(0)
    written: list[int] = []
    for value in spec["levels"]:
        for bit in range(5, -1, -1):
            written.append((value >> bit) & 1)
    out = bits[:level] + written + bits[level + 12 : update] + inserted
    out += bits[update + 1 : header_bits]
    assert len(out) % 8 == 0, "splice would desynchronise the tile data"
    payload = _pack_bits(out) + data[payload_at + header_bits // 8 : payload_at + size]
    body = bytearray()
    body.append((6 << 3) | (1 << 1))
    body += _leb128(len(payload))
    body += payload
    return data[:start] + bytes(body) + data[payload_at + size :]


def patch_header_fields(spec: dict) -> bytes:
    """Rewrite fixed-width frame header fields in place, moving no other bit.

    Each patch names a frame, the FFmpeg trace position of one of its uncompressed
    header fields, that field's width and both the value found there in the base
    stream and the value to write instead. Because the width is unchanged the tile
    payload stays byte-for-byte identical, which is what makes this the cheap way
    to reach a header value the encoder will not choose: ``primary_ref_frame`` is
    always 7 (PRIMARY_REF_NONE) for these two-frame streams because libaom has
    nothing to inherit from within its own two-frame group, and
    ``disable_frame_end_update_cdf`` follows the same all-or-nothing logic.
    """
    base = os.path.join(FIXTURE_DIR, spec["base"] + ".obu")
    data = open(base, "rb").read()
    frames = frame_obus(data)
    payloads = {}
    for patch in spec["patches"]:
        start, payload_at, size = frames[patch["frame"]]
        bits = payloads.get(patch["frame"])
        if bits is None:
            bits = _split_bits(data[payload_at : payload_at + size])
            payloads[patch["frame"]] = (bits, start, payload_at, size)
        offset = patch["bit"] - (payload_at - start) * 8
        found = 0
        for bit in bits[offset : offset + patch["width"]]:
            found = found * 2 + bit
        assert found == patch["expect"], (
            "%s frame %d field at bit %d is %d, expected %d"
            % (spec["base"], patch["frame"], patch["bit"], found, patch["expect"])
        )
        for index, shift in enumerate(range(patch["width"] - 1, -1, -1)):
            bits[offset + index] = (patch["value"] >> shift) & 1
    # Every patch keeps its field's width, so the OBU offsets stay valid and the
    # payloads can be spliced back in one at a time.
    for bits, start, payload_at, size in payloads.values():
        data = data[:payload_at] + _pack_bits(bits) + data[payload_at + size :]
    return data


def build_patched_encode(spec: dict, base: bytes) -> bytes:
    """Encode-derived patched streams: rewrite header bits, optionally appending
    a copy of the base's last frame first.

    libaom cannot produce some of the streams this suite needs. Skip mode wants
    two references whose order hints sit on either side of the frame's own hint,
    which a two-frame encode cannot express and this libaom build crashes past;
    distance-weighted compound wants `reference_select` on a group where libaom
    never chooses compound at all. Both are reached the same way: encode a base
    with encoder flags the stream will carry but not use, optionally append a
    byte-for-byte copy of the last inter frame behind a fresh temporal
    delimiter, then rewrite fixed-width header bits in place. Nothing moves, so
    every bit position quoted in the spec is the one the trace reports, and the
    tile entropy of every frame is untouched. The result is a legal,
    semantically determined stream whose dav1d decoding is the truth, exactly
    like the other patched fixtures.
    """
    data = base
    seq = spec.get("seq_patch")
    if seq is not None:
        # The sequence header is its own OBU ahead of the first frame; an
        # equal-width bit there reaches a frame-level switch without moving
        # any later bit, which is how a frame grammar the encoder never picks
        # gets pinned.
        start = payload_at = None
        i = 0
        while i < len(data):
            h = data[i]
            typ = (h >> 3) & 15
            has_size = (h >> 1) & 1
            j = i + 1
            if has_size:
                size = 0
                shift = 0
                while True:
                    b = data[j]
                    j += 1
                    size |= (b & 0x7F) << shift
                    shift += 7
                    if not (b & 0x80):
                        break
                if typ == 1:
                    start, payload_at, obu_size = i, j, size
                    break
                i = j + size
            else:
                i = j
        bits = _split_bits(data[payload_at : payload_at + obu_size])
        off = seq["bit"] - (payload_at - start) * 8
        found = 0
        for bit in bits[off : off + seq["width"]]:
            found = found * 2 + bit
        assert found == seq["expect"], (
            "%s sequence field at bit %d is %d, expected %d"
            % (spec["name"], seq["bit"], found, seq["expect"])
        )
        for index, shift in enumerate(range(seq["width"] - 1, -1, -1)):
            bits[off + index] = (seq["value"] >> shift) & 1
        data = data[:payload_at] + _pack_bits(bits) + data[payload_at + obu_size :]
    for tile in spec.get("tile_patches", []):
        # A single bit inside one frame's tile entropy. Changing it changes how
        # the symbols after it decode, which is how a tool the encoder never
        # emits can be reached at all: the mask-compound branch, for instance,
        # is only read for a compound block, and no two-frame group carries one.
        # Everything downstream of the flipped bit is still a determined,
        # legal decode - dav1d's output on the result is the evidence.
        frames = frame_obus(data)
        start, payload_at, size = frames[tile["frame"]]
        index = payload_at + tile["offset"]
        if index >= len(data):
            raise SystemExit("%s: tile patch %d out of range" % (spec["name"], index))
        current = data[index]
        bit = (current >> tile["bit"]) & 1
        assert bit == tile["expect"], (
            "%s: tile byte %d bit %d is %d, expected %d"
            % (spec["name"], tile["offset"], tile["bit"], bit, tile["expect"])
        )
        data = (
            data[:index]
            + bytes([current ^ (1 << tile["bit"])])
            + data[index + 1 :]
        )
    if spec.get("append_frame_copy", False):
        frames = frame_obus(data)
        last_start, _, _ = frames[-1]
        # A temporal delimiter in front of every frame OBU, as the base has.
        data = data + bytes([0x12, 0x00]) + data[last_start:]
    frames = frame_obus(data)
    payloads: dict[int, tuple[list[int], int, int]] = {}
    for patch in spec["patches"]:
        start, payload_at, size = frames[patch["frame"]]
        entry = payloads.get(patch["frame"])
        if entry is None:
            entry = (_split_bits(data[payload_at : payload_at + size]), start, payload_at, size)
            payloads[patch["frame"]] = entry
        bits = entry[0]
        offset = patch["bit"] - (payload_at - start) * 8
        width = patch["width"]
        found = 0
        for bit in bits[offset : offset + width]:
            found = found * 2 + bit
        assert found == patch["expect"], (
            "%s frame %d field at bit %d is %d, expected %d"
            % (spec["name"], patch["frame"], patch["bit"], found, patch["expect"])
        )
        for index, shift in enumerate(range(width - 1, -1, -1)):
            bits[offset + index] = (patch["value"] >> shift) & 1
    for bits, start, payload_at, size in payloads.values():
        data = data[:payload_at] + _pack_bits(bits) + data[payload_at + size :]
    return data


def run(fixture: dict, check: bool) -> dict:
    """Encode one fixture and verify it against the declared evidence.

    In ``--check`` mode the freshly derived bytes are compared against what is
    already committed instead of being rewritten, so a compiler or tool change
    that moves any bit fails loudly here rather than in the MoonBit suite.
    """
    name = fixture["name"]
    width = fixture.get("width", WIDTH)
    height = fixture.get("height", HEIGHT)
    nframes = fixture.get("frame_count", FRAMES)
    os.makedirs(FIXTURE_DIR, exist_ok=True)
    y4m = os.path.join(FIXTURE_DIR, name + ".input.y4m")
    obu = os.path.join(FIXTURE_DIR, name + ".obu")
    ref = os.path.join(FIXTURE_DIR, name + ".reference.yuv")
    if check:
        for path in (obu, ref):
            if not os.path.exists(path):
                raise SystemExit("FAIL: %s is missing; generate it first" % path)
        committed_obu = open(obu, "rb").read()
        committed_ref = open(ref, "rb").read()
    scratch = os.path.join(FIXTURE_DIR, name + ".check.obu")
    if "splice" in fixture:
        command = "hand-splice of %s (see splice_loop_filter_deltas)" % fixture["splice"]["base"]
        with open(scratch, "wb") as fh:
            fh.write(splice_loop_filter_deltas(fixture["splice"]))
    elif "tile_patch_of" in fixture:
        spec = fixture["tile_patch_of"]
        command = "one flipped tile bit of %s (see inject_tile_patch_of)" % spec["base"]
        with open(scratch, "wb") as fh:
            fh.write(inject_tile_patch_of(spec))
    elif "gm_inject" in fixture:
        command = "global-motion injection into %s (see inject_global_motion)" % fixture["gm_inject"]["base"]
        with open(scratch, "wb") as fh:
            fh.write(inject_global_motion(fixture["gm_inject"]))
    elif "patch" in fixture:
        command = "header field patch of %s (see patch_header_fields)" % fixture["patch"]["base"]
        with open(scratch, "wb") as fh:
            fh.write(patch_header_fields(fixture["patch"]))
    elif "patched_encode" in fixture:
        spec = fixture["patched_encode"]
        spec["name"] = name
        encode_input(y4m, spec.get("input", "shift"), width, height)
        # The appended copy of the last frame accounts for one frame of the
        # spec's total; without it the base encode carries them all.
        limit = nframes - (1 if spec.get("append_frame_copy", False) else 0)
        cmd = [
            AOMENC,
            "--codec=av1",
            "--obu",
            "--i420",
            "--width=%d" % width,
            "--height=%d" % height,
            "--bit-depth=8",
            "--fps=1/1",
            "--limit=%d" % limit,
            "--lag-in-frames=0",
            "--threads=1",
            "--cpu-used=0",
            "--end-usage=q",
            "--cq-level=32",
            "--tile-columns=0",
            "--tile-rows=0",
            "--debug",
            "--disable-warning-prompt",
        ] + spec["flags"] + ["-o", scratch, y4m]
        command = " ".join(cmd)
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
        if proc.returncode != 0:
            raise SystemExit("aomenc failed for %s:\n%s" % (name, proc.stdout[-2000:]))
        base = open(scratch, "rb").read()
        with open(scratch, "wb") as fh:
            fh.write(build_patched_encode(spec, base))
    else:
        encode_input(y4m, fixture.get("input", "ramp"), width, height)
        cmd = [
            AOMENC,
            "--codec=av1",
            "--obu",
            "--i420",
            "--width=%d" % width,
            "--height=%d" % height,
            "--bit-depth=8",
            "--fps=1/1",
            "--limit=%d" % FRAMES,
            "--lag-in-frames=0",
            "--threads=1",
            "--cpu-used=0",
            "--end-usage=q",
            "--cq-level=32",
            "--tile-columns=0",
            "--tile-rows=0",
            "--debug",
            "--disable-warning-prompt",
        ] + fixture["flags"] + ["-o", scratch, y4m]
        command = " ".join(cmd)
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
        if proc.returncode != 0:
            raise SystemExit("aomenc failed for %s:\n%s" % (name, proc.stdout[-2000:]))
    trace = os.path.join(FIXTURE_DIR, name + ".trace.txt")
    frames = trace_fields(scratch, trace)
    if len(frames) != nframes:
        raise SystemExit("%s: expected %d frame headers, traced %d" % (name, nframes, len(frames)))
    for index, expected in enumerate(fixture["frames"]):
        check_expectations("%s frame %d" % (name, index), frames[index], expected)
    if fixture["sequence_expectations"] is not None:
        check_expectations(
            "%s sequence" % name,
            sequence_fields(trace),
            fixture["sequence_expectations"],
        )
    decoded = os.path.join(FIXTURE_DIR, name + ".check.yuv")
    proc = subprocess.run(
        [DAV1D, "-q", "-i", scratch, "-o", decoded],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if proc.returncode != 0:
        raise SystemExit("dav1d failed for %s:\n%s" % (name, proc.stdout + proc.stderr))
    plane = width * height + 2 * (width // 2) * (height // 2)
    fresh_obu = open(scratch, "rb").read()
    data = open(decoded, "rb").read()
    for path in (scratch, decoded):
        os.remove(path)
    if len(data) != plane * nframes:
        raise SystemExit("%s: dav1d gave %d bytes, expected %d" % (name, len(data), plane * nframes))
    if "gm_inject" in fixture:
        # The injected model is the only header change, but the picture does
        # move: the base reads no subpel-filter symbol for a GLOBAL(Global)MV
        # block, and a translation model makes that block read one, so the tile
        # symbols after it re-symbolise into a different legal decode. dav1d's
        # planes on the patched stream are the truth for that decode, which is
        # what the MoonBit test pins sample-exactly.
        pass
    if check:
        if fresh_obu != committed_obu:
            raise SystemExit(
                "FAIL %s: the re-encoded OBU differs from the committed one (%d vs %d bytes)"
                % (name, len(fresh_obu), len(committed_obu))
            )
        if data != committed_ref:
            raise SystemExit("FAIL %s: dav1d's planes differ from the committed ones" % name)
    else:
        for path, blob in ((obu, fresh_obu), (ref, data)):
            with open(path, "wb") as fh:
                fh.write(blob)
    return {
        "name": name,
        "command": command,
        "obu_sha256": hashlib.sha256(fresh_obu).hexdigest(),
        "reference_sha256": hashlib.sha256(data).hexdigest(),
        "frame_planes": [data[i * plane : (i + 1) * plane] for i in range(nframes)],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    built = [run(f, args.check) for f in FIXTURES]
    if args.check:
        print("verified %d fixtures against their committed evidence" % len(built))
        return
    with open(os.path.join(FIXTURE_DIR, "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(
            {
                "encoder": AOMENC,
                "oracle_trace": FFMPEG,
                "reference_decoder": DAV1D,
                "source_dimensions": [WIDTH, HEIGHT],
                "frames_per_fixture": FRAMES,
                "fixtures": [
                    {k: v for k, v in item.items() if k != "frame_planes"}
                    for item in built
                ],
                "notes": "libaom in this build crashes past two frames, so each fixture is one key frame plus one inter frame.",
            },
            fh,
            indent=2,
            sort_keys=True,
            # The manifest records the encoder command lines verbatim, and
            # this workspace's path contains non-ASCII characters; escaping
            # them would make the file unreadable to the people re-running it.
            ensure_ascii=False,
        )
    print("generated %d fixtures; run scripts/emit-av1-inter-test.py to refresh the test" % len(built))


if __name__ == "__main__":
    main()
