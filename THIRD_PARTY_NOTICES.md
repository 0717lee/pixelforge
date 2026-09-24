# Third-party notices

PixelForge uses the following dependencies in its retained image-processing,
codec-adapter and native CLI paths. Their Apache-2.0 license text is available
in [LICENSE](LICENSE); additional upstream notices are retained below.

| Dependency | Version | Use and upstream source |
| --- | --- | --- |
| `mizchi/image` | 0.4.3 | JPEG decode/encode, WebP encode and browser AVIF encoding adapter; [image-mbt](https://github.com/mizchi/image-mbt) |
| `mizchi/zlib` | 0.4.8 | PNG compression used by the image adapter; [zlib.mbt](https://github.com/mizchi/zlib.mbt) |
| `moonbitlang/x` | 0.5.1 | Native CLI filesystem access; [moonbitlang/x](https://github.com/moonbitlang/x) |
| `moonbitlang/core` | 0.10.11+6ff76a5f9 | Standard-library types and image-processing mathematics; [moonbitlang/core](https://github.com/moonbitlang/core) |

The resolved dependency metadata declares Apache-2.0 for each package.
`moonbitlang/x` filesystem sources retain:

> Copyright 2025 International Digital Economy Academy

The browser AVIF adapter uses host encoding facilities. PixelForge does not
bundle a native codec binary through that adapter.

## MoonBit core upstream NOTICE

The following is the complete NOTICE distributed with the pinned MoonBit core
version. It preserves the standard library's attribution and additional math
licenses alongside generated PixelForge artifacts.

This product includes software developed at
International Digital Economy Academy (https://www.idea.edu.cn/).

File double/exp.mbt, double/pow_nonjs.mbt is adapted from v8 (https://v8.dev), which is adapted from fdlibm (http://www.netlib.org/fdlibm).

License from fdlibm:
Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
Developed at SunSoft, a Sun Microsystems, Inc. business.
Permission to use, copy, modify, and distribute this
software is freely granted, provided that this notice
is preserved.

License from v8:
The original source code covered by the above license above has been
modified significantly by Google Inc.
Copyright 2016, the V8 project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

File random/random.mbt is adapted from Golang's [`math/rand/v2`](https://pkg.go.dev/math/rand/v2) package.

Files `internal/strconv/strconv_eisel_lemire.mbt` and
`internal/strconv/strconv_eisel_lemire_table.mbt` are adapted from Go 1.26.2's
`internal/strconv/atofeisel.go` and generated `internal/strconv/pow10tab.go`.

License from Golang:
Copyright 2009 The Go Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

File `float/exp.mbt`, `float/log.mbt`, `double/mod_nonjs.mbt` and `double/scalbn.mbt` is adapted from
[musl](https://www.musl-libc.org/). Specifically:

- `float/log.mbt` is adapted from `src/math/logf.c`, `src/math/logf_data.h`,
  and `src/math/logf_data.c`.
- `float/exp.mbt` is adapted from `src/math/expf.c`, `src/math/exp2f_data.h`,
  and `src/math/exp2f_data.c`.
- `double/mod_nonjs.mbt` is adapted from `src/math/fmod.c`.
- `double/scalbn.mbt` is adapted from `src/math/scalbn.c`.
- `math/hyperbolic.mbt` is adapted from `src/math/sinh.c`, `src/math/cosh.c`,
`src/math/tanh.c`, `src/math/asinh.c`, `src/math/acosh.c`, and `src/math/atanh.c`.

`float/log.mbt` and `float/exp.mbt` files are Copyright (c) 2017-2018 Arm Limited and licensed under the MIT
license.

Here is a copy of MIT license:

Copyright (c) 2017-2018 Arm Limited.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

`double/mod_nonjs.mbt`, `double/scalbn.mbt`, `math/algebraic.mbt`,
`math/log.mbt` and `math/pow.mbt` are licensed under the following license:

Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.

Developed at SunPro, a Sun Microsystems, Inc. business.
Permission to use, copy, modify, and distribute this
software is freely granted, provided that this notice
is preserved.

Copyright (c) 1992-2026 The FreeBSD Project.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.
