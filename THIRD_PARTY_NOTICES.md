# Third-party notices

The AV1/AVIF source files named below are now maintained in the independent
`0717lee/moonav1` package. These notices remain here because PixelForge's Web
artifacts include that dependency. Original source history is preserved in
PixelForge through `6f0c711c54f89d34f3e2ef97cde7a0a45458583d`.

## libaom reference algorithms

The AV1 CfL prediction and probability defaults in `av1_cfl.mbt`, directional
prediction in `av1_directional_predict.mbt`, and reference-availability tables
and rules in `av1_intra_edges.mbt`, and the deblocking kernels and traversal in
`av1_loop_filter.mbt` and `av1_loop_filter_frame.mbt`, and filter-intra prediction
in `av1_filter_intra.mbt`, and palette syntax and probability tables in
`av1_palette.mbt` and `av1_palette_index.mbt`, and the horizontal
super-resolution filter table and scalar convolution in `av1_superres.mbt`,
and the loop-restoration unit-count rule, configuration validation and grid
layout in `av1_restoration_config.mbt`
are transcribed from libaom at revision
`8e7b6a567df174d795479b92b4ac766d271add73`. The original source is available
at <https://aomedia.googlesource.com/aom/>. It uses the following BSD 2-Clause
License and the [Alliance for Open Media Patent License 1.0](https://www.aomedia.org/license/patent).

Copyright (c) 2016, Alliance for Open Media. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## go-av1 reference tables

The AV1 default CDF and quantizer tables in the `av1_*tables.mbt` files,
including the intra-mode tables and the `Subpel_Filters` interpolation kernels
in `av1_interp_tables.mbt`, were transcribed from corresponding tables in the
`github.com/mgvs/go-av1` project. The general sequence and frame-header grammar
(`av1_parse_sequence_payload`, `av1_parse_frame_prefix`, the reference-list
derivation and the global-motion sub-exponential coders) and the eight-tap
subpel motion-compensation kernel in `av1_mc.mbt` follow the same project's
`header/`, `decode/intermode.go` and `decode/mc.go` algorithms, and its
`decode/subpel_gen.go` source hash is pinned in the generated table header.
Correctness is settled against the AV1 specification and dav1d output rather
than against that implementation, and where the two disagree the specification
wins. It is distributed under the BSD 2-Clause License:

Copyright (c) 2026, Oleksandr Zhabotynskyi

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## dav1d inverse quantization matrices

The AV1 inverse quantization matrix data in `av1_qmatrix_tables.mbt` is
transcribed from dav1d 1.2.1 `src/qm.c`. Matrix selection and coefficient
dequantization in `av1_qmatrix.mbt` and `av1_coeff_decode.mbt` follow AV1
sections 5.9.14 and 7.12.3 and are checked against dav1d's native C code.
`scripts/generate-av1-qmatrix.py` compiles the original matrix initialization
functions and the DC quantization-matrix branch from `src/recon_tmpl.c` to
generate the reference tests. It pins the SHA-256 of all reference sources;
the generated source retains the original copyright and license notice.
The SGR arithmetic checks in `av1_sgr_unsigned_reference_wbtest.mbt` are
generated by `scripts/generate-av1-sgr-reference.py`, compiling the original
`boxsum3`, `boxsum5`, and `selfguided_filter` routines from
`src/looprestoration_tmpl.c` and its `src/tables.c` lookup table. Both source
hashes are pinned; this verifies the unsigned statistics reproduced with
wide integer products in `av1_restoration_filter.mbt`.
The original sources are available at
<https://code.videolan.org/videolan/dav1d/-/tree/1.2.1/src> and
<https://github.com/videolan/dav1d/tree/1.2.1/src> under the BSD 2-Clause License:

Copyright © 2018, VideoLAN and dav1d authors
Copyright © 2018-2021, VideoLAN and dav1d authors
Copyright © 2018, Two Orioles, LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
