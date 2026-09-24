/*
 * Copyright © 2018, VideoLAN and dav1d authors
 * Copyright © 2018, Two Orioles, LLC
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

typedef signed char int8_t;typedef unsigned char uint8_t;
typedef unsigned short uint16_t;typedef short int16_t;typedef int int32_t;
typedef long long int64_t;typedef unsigned long long uint64_t;typedef long long ptrdiff_t;
extern int printf(const char *, ...);extern void abort(void);
#define INT16_MIN (-32768)
#define INT16_MAX 32767
#define assert(x) ((x) ? (void)0 : abort())
#define COLD
static int abs(int v){return v<0?-v:v;}
static int64_t llabs(int64_t v){return v<0?-v:v;}
static int iclip(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static int imin(int a,int b){return a<b?a:b;}
static int apply_sign(int v,int s){return s<0?-v:v;}
static int apply_sign64(int v,int64_t s){return s<0?-v:v;}
static int ulog2(unsigned v){int s=0;while(v>>1){s++;v>>=1;}return s;}
static int u64log2(uint64_t v){int s=0;while(v>>1){s++;v>>=1;}return s;}
typedef union mv{struct{int16_t y,x;};unsigned n;}mv;
typedef struct Dav1dWarpedMotionParams{int type;int32_t matrix[6];union{struct{int16_t alpha,beta,gamma,delta;}p;int16_t abcd[4];}u;}Dav1dWarpedMotionParams;
#define pixel uint16_t
#define HIGHBD_DECL_SUFFIX ,const int bitdepth_max
#define PXSTRIDE(x) ((x)/2)
#define get_intermediate_bits(x) ((x)==4095?2:4)
#define bitdepth_from_max(x) ((x)==4095?12:((x)==1023?10:8))
#define PREP_BIAS ((bitdepth_max)==255?0:8192)
#define iclip_pixel(x) iclip(x,0,bitdepth_max)
static const uint16_t div_lut[257] = {
    16384, 16320, 16257, 16194, 16132, 16070, 16009, 15948, 15888, 15828, 15768,
    15709, 15650, 15592, 15534, 15477, 15420, 15364, 15308, 15252, 15197, 15142,
    15087, 15033, 14980, 14926, 14873, 14821, 14769, 14717, 14665, 14614, 14564,
    14513, 14463, 14413, 14364, 14315, 14266, 14218, 14170, 14122, 14075, 14028,
    13981, 13935, 13888, 13843, 13797, 13752, 13707, 13662, 13618, 13574, 13530,
    13487, 13443, 13400, 13358, 13315, 13273, 13231, 13190, 13148, 13107, 13066,
    13026, 12985, 12945, 12906, 12866, 12827, 12788, 12749, 12710, 12672, 12633,
    12596, 12558, 12520, 12483, 12446, 12409, 12373, 12336, 12300, 12264, 12228,
    12193, 12157, 12122, 12087, 12053, 12018, 11984, 11950, 11916, 11882, 11848,
    11815, 11782, 11749, 11716, 11683, 11651, 11619, 11586, 11555, 11523, 11491,
    11460, 11429, 11398, 11367, 11336, 11305, 11275, 11245, 11215, 11185, 11155,
    11125, 11096, 11067, 11038, 11009, 10980, 10951, 10923, 10894, 10866, 10838,
    10810, 10782, 10755, 10727, 10700, 10673, 10645, 10618, 10592, 10565, 10538,
    10512, 10486, 10460, 10434, 10408, 10382, 10356, 10331, 10305, 10280, 10255,
    10230, 10205, 10180, 10156, 10131, 10107, 10082, 10058, 10034, 10010,  9986,
     9963,  9939,  9916,  9892,  9869,  9846,  9823,  9800,  9777,  9754,  9732,
     9709,  9687,  9664,  9642,  9620,  9598,  9576,  9554,  9533,  9511,  9489,
     9468,  9447,  9425,  9404,  9383,  9362,  9341,  9321,  9300,  9279,  9259,
     9239,  9218,  9198,  9178,  9158,  9138,  9118,  9098,  9079,  9059,  9039,
     9020,  9001,  8981,  8962,  8943,  8924,  8905,  8886,  8867,  8849,  8830,
     8812,  8793,  8775,  8756,  8738,  8720,  8702,  8684,  8666,  8648,  8630,
     8613,  8595,  8577,  8560,  8542,  8525,  8508,  8490,  8473,  8456,  8439,
     8422,  8405,  8389,  8372,  8355,  8339,  8322,  8306,  8289,  8273,  8257,
     8240,  8224,  8208,  8192,
};

static inline int iclip_wmp(const int v) {
    const int cv = iclip(v, INT16_MIN, INT16_MAX);

    return apply_sign((abs(cv) + 32) >> 6, cv) * (1 << 6);
}

static inline int resolve_divisor_32(const unsigned d, int *const shift) {
    *shift = ulog2(d);
    const int e = d - (1 << *shift);
    const int f = *shift > 8 ? (e + (1 << (*shift - 9))) >> (*shift - 8) :
                               e << (8 - *shift);
    assert(f <= 256);
    *shift += 14;
    // Use f as lookup into the precomputed table of multipliers
    return div_lut[f];
}

int dav1d_get_shear_params(Dav1dWarpedMotionParams *const wm) {
    const int32_t *const mat = wm->matrix;

    if (mat[2] <= 0) return 1;

    wm->u.p.alpha = iclip_wmp(mat[2] - 0x10000);
    wm->u.p.beta = iclip_wmp(mat[3]);

    int shift;
    const int y = apply_sign(resolve_divisor_32(abs(mat[2]), &shift), mat[2]);
    const int64_t v1 = ((int64_t) mat[4] * 0x10000) * y;
    const int rnd = (1 << shift) >> 1;
    wm->u.p.gamma = iclip_wmp(apply_sign64((int) ((llabs(v1) + rnd) >> shift), v1));
    const int64_t v2 = ((int64_t) mat[3] * mat[4]) * y;
    wm->u.p.delta = iclip_wmp(mat[5] -
                          apply_sign64((int) ((llabs(v2) + rnd) >> shift), v2) -
                          0x10000);

    return (4 * abs(wm->u.p.alpha) + 7 * abs(wm->u.p.beta) >= 0x10000) ||
           (4 * abs(wm->u.p.gamma) + 4 * abs(wm->u.p.delta) >= 0x10000);
}

static int resolve_divisor_64(const uint64_t d, int *const shift) {
    *shift = u64log2(d);
    const int64_t e = d - (1LL << *shift);
    const int64_t f = *shift > 8 ? (e + (1LL << (*shift - 9))) >> (*shift - 8) :
                                   e << (8 - *shift);
    assert(f <= 256);
    *shift += 14;
    // Use f as lookup into the precomputed table of multipliers
    return div_lut[f];
}

static int get_mult_shift_ndiag(const int64_t px,
                                const int idet, const int shift)
{
    const int64_t v1 = px * idet;
    const int v2 = apply_sign64((int) ((llabs(v1) +
                                        ((1LL << shift) >> 1)) >> shift),
                                v1);
    return iclip(v2, -0x1fff, 0x1fff);
}

static int get_mult_shift_diag(const int64_t px,
                               const int idet, const int shift)
{
    const int64_t v1 = px * idet;
    const int v2 = apply_sign64((int) ((llabs(v1) +
                                        ((1LL << shift) >> 1)) >> shift),
                                v1);
    return iclip(v2, 0xe001, 0x11fff);
}

void dav1d_set_affine_mv2d(const int bw4, const int bh4,
                           const mv mv, Dav1dWarpedMotionParams *const wm,
                           const int bx4, const int by4)
{
    int32_t *const mat = wm->matrix;
    const int rsuy = 2 * bh4 - 1;
    const int rsux = 2 * bw4 - 1;
    const int isuy = by4 * 4 + rsuy;
    const int isux = bx4 * 4 + rsux;

    mat[0] = iclip(mv.x * 0x2000 - (isux * (mat[2] - 0x10000) + isuy * mat[3]),
                   -0x800000, 0x7fffff);
    mat[1] = iclip(mv.y * 0x2000 - (isux * mat[4] + isuy * (mat[5] - 0x10000)),
                   -0x800000, 0x7fffff);
}

int dav1d_find_affine_int(const int (*pts)[2][2], const int np,
                          const int bw4, const int bh4,
                          const mv mv, Dav1dWarpedMotionParams *const wm,
                          const int bx4, const int by4)
{
    int32_t *const mat = wm->matrix;
    int a[2][2] = { { 0, 0 }, { 0, 0 } };
    int bx[2] = { 0, 0 };
    int by[2] = { 0, 0 };
    const int rsuy = 2 * bh4 - 1;
    const int rsux = 2 * bw4 - 1;
    const int suy = rsuy * 8;
    const int sux = rsux * 8;
    const int duy = suy + mv.y;
    const int dux = sux + mv.x;
    const int isuy = by4 * 4 + rsuy;
    const int isux = bx4 * 4 + rsux;

    for (int i = 0; i < np; i++) {
        const int dx = pts[i][1][0] - dux;
        const int dy = pts[i][1][1] - duy;
        const int sx = pts[i][0][0] - sux;
        const int sy = pts[i][0][1] - suy;
        if (abs(sx - dx) < 256 && abs(sy - dy) < 256) {
            a[0][0] += ((sx * sx) >> 2) + sx * 2 + 8;
            a[0][1] += ((sx * sy) >> 2) + sx + sy + 4;
            a[1][1] += ((sy * sy) >> 2) + sy * 2 + 8;
            bx[0] += ((sx * dx) >> 2) + sx + dx + 8;
            bx[1] += ((sy * dx) >> 2) + sy + dx + 4;
            by[0] += ((sx * dy) >> 2) + sx + dy + 4;
            by[1] += ((sy * dy) >> 2) + sy + dy + 8;
        }
    }

    // compute determinant of a
    const int64_t det = (int64_t) a[0][0] * a[1][1] - (int64_t) a[0][1] * a[0][1];
    if (det == 0) return 1;
    int shift, idet = apply_sign64(resolve_divisor_64(llabs(det), &shift), det);
    shift -= 16;
    if (shift < 0) {
        idet <<= -shift;
        shift = 0;
    }

    // solve the least-squares
    mat[2] = get_mult_shift_diag((int64_t) a[1][1] * bx[0] -
                                 (int64_t) a[0][1] * bx[1], idet, shift);
    mat[3] = get_mult_shift_ndiag((int64_t) a[0][0] * bx[1] -
                                  (int64_t) a[0][1] * bx[0], idet, shift);
    mat[4] = get_mult_shift_ndiag((int64_t) a[1][1] * by[0] -
                                  (int64_t) a[0][1] * by[1], idet, shift);
    mat[5] = get_mult_shift_diag((int64_t) a[0][0] * by[1] -
                                 (int64_t) a[0][1] * by[0], idet, shift);

    mat[0] = iclip(mv.x * 0x2000 - (isux * (mat[2] - 0x10000) + isuy * mat[3]),
                   -0x800000, 0x7fffff);
    mat[1] = iclip(mv.y * 0x2000 - (isux * mat[4] + isuy * (mat[5] - 0x10000)),
                   -0x800000, 0x7fffff);

    return 0;
}
const int8_t dav1d_mc_warp_filter[193][8] = {
    // [-1, 0)
    { 0,   0, 127,   1,   0, 0, 0, 0 }, { 0,  -1, 127,   2,   0, 0, 0, 0 },
    { 1,  -3, 127,   4, - 1, 0, 0, 0 }, { 1,  -4, 126,   6,  -2, 1, 0, 0 },
    { 1,  -5, 126,   8, - 3, 1, 0, 0 }, { 1,  -6, 125,  11,  -4, 1, 0, 0 },
    { 1,  -7, 124,  13, - 4, 1, 0, 0 }, { 2,  -8, 123,  15,  -5, 1, 0, 0 },
    { 2,  -9, 122,  18, - 6, 1, 0, 0 }, { 2, -10, 121,  20,  -6, 1, 0, 0 },
    { 2, -11, 120,  22, - 7, 2, 0, 0 }, { 2, -12, 119,  25,  -8, 2, 0, 0 },
    { 3, -13, 117,  27, - 8, 2, 0, 0 }, { 3, -13, 116,  29,  -9, 2, 0, 0 },
    { 3, -14, 114,  32, -10, 3, 0, 0 }, { 3, -15, 113,  35, -10, 2, 0, 0 },
    { 3, -15, 111,  37, -11, 3, 0, 0 }, { 3, -16, 109,  40, -11, 3, 0, 0 },
    { 3, -16, 108,  42, -12, 3, 0, 0 }, { 4, -17, 106,  45, -13, 3, 0, 0 },
    { 4, -17, 104,  47, -13, 3, 0, 0 }, { 4, -17, 102,  50, -14, 3, 0, 0 },
    { 4, -17, 100,  52, -14, 3, 0, 0 }, { 4, -18,  98,  55, -15, 4, 0, 0 },
    { 4, -18,  96,  58, -15, 3, 0, 0 }, { 4, -18,  94,  60, -16, 4, 0, 0 },
    { 4, -18,  91,  63, -16, 4, 0, 0 }, { 4, -18,  89,  65, -16, 4, 0, 0 },
    { 4, -18,  87,  68, -17, 4, 0, 0 }, { 4, -18,  85,  70, -17, 4, 0, 0 },
    { 4, -18,  82,  73, -17, 4, 0, 0 }, { 4, -18,  80,  75, -17, 4, 0, 0 },
    { 4, -18,  78,  78, -18, 4, 0, 0 }, { 4, -17,  75,  80, -18, 4, 0, 0 },
    { 4, -17,  73,  82, -18, 4, 0, 0 }, { 4, -17,  70,  85, -18, 4, 0, 0 },
    { 4, -17,  68,  87, -18, 4, 0, 0 }, { 4, -16,  65,  89, -18, 4, 0, 0 },
    { 4, -16,  63,  91, -18, 4, 0, 0 }, { 4, -16,  60,  94, -18, 4, 0, 0 },
    { 3, -15,  58,  96, -18, 4, 0, 0 }, { 4, -15,  55,  98, -18, 4, 0, 0 },
    { 3, -14,  52, 100, -17, 4, 0, 0 }, { 3, -14,  50, 102, -17, 4, 0, 0 },
    { 3, -13,  47, 104, -17, 4, 0, 0 }, { 3, -13,  45, 106, -17, 4, 0, 0 },
    { 3, -12,  42, 108, -16, 3, 0, 0 }, { 3, -11,  40, 109, -16, 3, 0, 0 },
    { 3, -11,  37, 111, -15, 3, 0, 0 }, { 2, -10,  35, 113, -15, 3, 0, 0 },
    { 3, -10,  32, 114, -14, 3, 0, 0 }, { 2, - 9,  29, 116, -13, 3, 0, 0 },
    { 2,  -8,  27, 117, -13, 3, 0, 0 }, { 2, - 8,  25, 119, -12, 2, 0, 0 },
    { 2,  -7,  22, 120, -11, 2, 0, 0 }, { 1, - 6,  20, 121, -10, 2, 0, 0 },
    { 1,  -6,  18, 122, - 9, 2, 0, 0 }, { 1, - 5,  15, 123, - 8, 2, 0, 0 },
    { 1,  -4,  13, 124, - 7, 1, 0, 0 }, { 1, - 4,  11, 125, - 6, 1, 0, 0 },
    { 1,  -3,   8, 126, - 5, 1, 0, 0 }, { 1, - 2,   6, 126, - 4, 1, 0, 0 },
    { 0,  -1,   4, 127, - 3, 1, 0, 0 }, { 0,   0,   2, 127, - 1, 0, 0, 0 },
    // [0, 1)
    {  0, 0,   0, 127,   1,   0, 0,  0 }, {  0, 0,  -1, 127,   2,   0, 0,  0 },
    {  0, 1,  -3, 127,   4,  -2, 1,  0 }, {  0, 1,  -5, 127,   6,  -2, 1,  0 },
    {  0, 2,  -6, 126,   8,  -3, 1,  0 }, { -1, 2,  -7, 126,  11,  -4, 2, -1 },
    { -1, 3,  -8, 125,  13,  -5, 2, -1 }, { -1, 3, -10, 124,  16,  -6, 3, -1 },
    { -1, 4, -11, 123,  18,  -7, 3, -1 }, { -1, 4, -12, 122,  20,  -7, 3, -1 },
    { -1, 4, -13, 121,  23,  -8, 3, -1 }, { -2, 5, -14, 120,  25,  -9, 4, -1 },
    { -1, 5, -15, 119,  27, -10, 4, -1 }, { -1, 5, -16, 118,  30, -11, 4, -1 },
    { -2, 6, -17, 116,  33, -12, 5, -1 }, { -2, 6, -17, 114,  35, -12, 5, -1 },
    { -2, 6, -18, 113,  38, -13, 5, -1 }, { -2, 7, -19, 111,  41, -14, 6, -2 },
    { -2, 7, -19, 110,  43, -15, 6, -2 }, { -2, 7, -20, 108,  46, -15, 6, -2 },
    { -2, 7, -20, 106,  49, -16, 6, -2 }, { -2, 7, -21, 104,  51, -16, 7, -2 },
    { -2, 7, -21, 102,  54, -17, 7, -2 }, { -2, 8, -21, 100,  56, -18, 7, -2 },
    { -2, 8, -22,  98,  59, -18, 7, -2 }, { -2, 8, -22,  96,  62, -19, 7, -2 },
    { -2, 8, -22,  94,  64, -19, 7, -2 }, { -2, 8, -22,  91,  67, -20, 8, -2 },
    { -2, 8, -22,  89,  69, -20, 8, -2 }, { -2, 8, -22,  87,  72, -21, 8, -2 },
    { -2, 8, -21,  84,  74, -21, 8, -2 }, { -2, 8, -22,  82,  77, -21, 8, -2 },
    { -2, 8, -21,  79,  79, -21, 8, -2 }, { -2, 8, -21,  77,  82, -22, 8, -2 },
    { -2, 8, -21,  74,  84, -21, 8, -2 }, { -2, 8, -21,  72,  87, -22, 8, -2 },
    { -2, 8, -20,  69,  89, -22, 8, -2 }, { -2, 8, -20,  67,  91, -22, 8, -2 },
    { -2, 7, -19,  64,  94, -22, 8, -2 }, { -2, 7, -19,  62,  96, -22, 8, -2 },
    { -2, 7, -18,  59,  98, -22, 8, -2 }, { -2, 7, -18,  56, 100, -21, 8, -2 },
    { -2, 7, -17,  54, 102, -21, 7, -2 }, { -2, 7, -16,  51, 104, -21, 7, -2 },
    { -2, 6, -16,  49, 106, -20, 7, -2 }, { -2, 6, -15,  46, 108, -20, 7, -2 },
    { -2, 6, -15,  43, 110, -19, 7, -2 }, { -2, 6, -14,  41, 111, -19, 7, -2 },
    { -1, 5, -13,  38, 113, -18, 6, -2 }, { -1, 5, -12,  35, 114, -17, 6, -2 },
    { -1, 5, -12,  33, 116, -17, 6, -2 }, { -1, 4, -11,  30, 118, -16, 5, -1 },
    { -1, 4, -10,  27, 119, -15, 5, -1 }, { -1, 4,  -9,  25, 120, -14, 5, -2 },
    { -1, 3,  -8,  23, 121, -13, 4, -1 }, { -1, 3,  -7,  20, 122, -12, 4, -1 },
    { -1, 3,  -7,  18, 123, -11, 4, -1 }, { -1, 3,  -6,  16, 124, -10, 3, -1 },
    { -1, 2,  -5,  13, 125,  -8, 3, -1 }, { -1, 2,  -4,  11, 126,  -7, 2, -1 },
    {  0, 1,  -3,   8, 126,  -6, 2,  0 }, {  0, 1,  -2,   6, 127,  -5, 1,  0 },
    {  0, 1,  -2,   4, 127,  -3, 1,  0 }, {  0, 0,   0,   2, 127,  -1, 0,  0 },
    // [1, 2)
    { 0, 0, 0,   1, 127,   0,   0, 0 }, { 0, 0, 0,  -1, 127,   2,   0, 0 },
    { 0, 0, 1,  -3, 127,   4,  -1, 0 }, { 0, 0, 1,  -4, 126,   6,  -2, 1 },
    { 0, 0, 1,  -5, 126,   8,  -3, 1 }, { 0, 0, 1,  -6, 125,  11,  -4, 1 },
    { 0, 0, 1,  -7, 124,  13,  -4, 1 }, { 0, 0, 2,  -8, 123,  15,  -5, 1 },
    { 0, 0, 2,  -9, 122,  18,  -6, 1 }, { 0, 0, 2, -10, 121,  20,  -6, 1 },
    { 0, 0, 2, -11, 120,  22,  -7, 2 }, { 0, 0, 2, -12, 119,  25,  -8, 2 },
    { 0, 0, 3, -13, 117,  27,  -8, 2 }, { 0, 0, 3, -13, 116,  29,  -9, 2 },
    { 0, 0, 3, -14, 114,  32, -10, 3 }, { 0, 0, 3, -15, 113,  35, -10, 2 },
    { 0, 0, 3, -15, 111,  37, -11, 3 }, { 0, 0, 3, -16, 109,  40, -11, 3 },
    { 0, 0, 3, -16, 108,  42, -12, 3 }, { 0, 0, 4, -17, 106,  45, -13, 3 },
    { 0, 0, 4, -17, 104,  47, -13, 3 }, { 0, 0, 4, -17, 102,  50, -14, 3 },
    { 0, 0, 4, -17, 100,  52, -14, 3 }, { 0, 0, 4, -18,  98,  55, -15, 4 },
    { 0, 0, 4, -18,  96,  58, -15, 3 }, { 0, 0, 4, -18,  94,  60, -16, 4 },
    { 0, 0, 4, -18,  91,  63, -16, 4 }, { 0, 0, 4, -18,  89,  65, -16, 4 },
    { 0, 0, 4, -18,  87,  68, -17, 4 }, { 0, 0, 4, -18,  85,  70, -17, 4 },
    { 0, 0, 4, -18,  82,  73, -17, 4 }, { 0, 0, 4, -18,  80,  75, -17, 4 },
    { 0, 0, 4, -18,  78,  78, -18, 4 }, { 0, 0, 4, -17,  75,  80, -18, 4 },
    { 0, 0, 4, -17,  73,  82, -18, 4 }, { 0, 0, 4, -17,  70,  85, -18, 4 },
    { 0, 0, 4, -17,  68,  87, -18, 4 }, { 0, 0, 4, -16,  65,  89, -18, 4 },
    { 0, 0, 4, -16,  63,  91, -18, 4 }, { 0, 0, 4, -16,  60,  94, -18, 4 },
    { 0, 0, 3, -15,  58,  96, -18, 4 }, { 0, 0, 4, -15,  55,  98, -18, 4 },
    { 0, 0, 3, -14,  52, 100, -17, 4 }, { 0, 0, 3, -14,  50, 102, -17, 4 },
    { 0, 0, 3, -13,  47, 104, -17, 4 }, { 0, 0, 3, -13,  45, 106, -17, 4 },
    { 0, 0, 3, -12,  42, 108, -16, 3 }, { 0, 0, 3, -11,  40, 109, -16, 3 },
    { 0, 0, 3, -11,  37, 111, -15, 3 }, { 0, 0, 2, -10,  35, 113, -15, 3 },
    { 0, 0, 3, -10,  32, 114, -14, 3 }, { 0, 0, 2,  -9,  29, 116, -13, 3 },
    { 0, 0, 2,  -8,  27, 117, -13, 3 }, { 0, 0, 2,  -8,  25, 119, -12, 2 },
    { 0, 0, 2,  -7,  22, 120, -11, 2 }, { 0, 0, 1,  -6,  20, 121, -10, 2 },
    { 0, 0, 1,  -6,  18, 122,  -9, 2 }, { 0, 0, 1,  -5,  15, 123,  -8, 2 },
    { 0, 0, 1,  -4,  13, 124,  -7, 1 }, { 0, 0, 1,  -4,  11, 125,  -6, 1 },
    { 0, 0, 1,  -3,   8, 126,  -5, 1 }, { 0, 0, 1,  -2,   6, 126,  -4, 1 },
    { 0, 0, 0,  -1,   4, 127,  -3, 1 }, { 0, 0, 0,   0,   2, 127,  -1, 0 },
    // dummy (replicate row index 191)
    { 0, 0, 0,   0,   2, 127,  -1, 0 },
};
#define FILTER_WARP_RND(src, x, F, stride, sh) \
    ((F[0] * src[x - 3 * stride] + \
      F[1] * src[x - 2 * stride] + \
      F[2] * src[x - 1 * stride] + \
      F[3] * src[x + 0 * stride] + \
      F[4] * src[x + 1 * stride] + \
      F[5] * src[x + 2 * stride] + \
      F[6] * src[x + 3 * stride] + \
      F[7] * src[x + 4 * stride] + \
      ((1 << (sh)) >> 1)) >> (sh))

#define FILTER_WARP_CLIP(src, x, F, stride, sh) \
    iclip_pixel(FILTER_WARP_RND(src, x, F, stride, sh))

static void warp_affine_8x8t_c(int16_t *tmp, const ptrdiff_t tmp_stride,
                               const pixel *src, const ptrdiff_t src_stride,
                               const int16_t *const abcd, int mx, int my
                               HIGHBD_DECL_SUFFIX)
{
    const int intermediate_bits = get_intermediate_bits(bitdepth_max);
    int16_t mid[15 * 8], *mid_ptr = mid;

    src -= 3 * PXSTRIDE(src_stride);
    for (int y = 0; y < 15; y++, mx += abcd[1]) {
        for (int x = 0, tmx = mx; x < 8; x++, tmx += abcd[0]) {
            const int8_t *const filter =
                dav1d_mc_warp_filter[64 + ((tmx + 512) >> 10)];

            mid_ptr[x] = FILTER_WARP_RND(src, x, filter, 1,
                                         7 - intermediate_bits);
        }
        src += PXSTRIDE(src_stride);
        mid_ptr += 8;
    }

    mid_ptr = &mid[3 * 8];
    for (int y = 0; y < 8; y++, my += abcd[3]) {
        for (int x = 0, tmy = my; x < 8; x++, tmy += abcd[2]) {
            const int8_t *const filter =
                dav1d_mc_warp_filter[64 + ((tmy + 512) >> 10)];

            tmp[x] = FILTER_WARP_RND(mid_ptr, x, filter, 8, 7) - PREP_BIAS;
        }
        mid_ptr += 8;
        tmp += tmp_stride;
    }
}

static void avg_c(pixel *dst, const ptrdiff_t dst_stride,
                  const int16_t *tmp1, const int16_t *tmp2, const int w, int h
                  HIGHBD_DECL_SUFFIX)
{
    const int intermediate_bits = get_intermediate_bits(bitdepth_max);
    const int sh = intermediate_bits + 1;
    const int rnd = (1 << intermediate_bits) + PREP_BIAS * 2;
    do {
        for (int x = 0; x < w; x++)
            dst[x] = iclip_pixel((tmp1[x] + tmp2[x] + rnd) >> sh);

        tmp1 += w;
        tmp2 += w;
        dst += PXSTRIDE(dst_stride);
    } while (--h);
}

static void w_avg_c(pixel *dst, const ptrdiff_t dst_stride,
                    const int16_t *tmp1, const int16_t *tmp2, const int w, int h,
                    const int weight HIGHBD_DECL_SUFFIX)
{
    const int intermediate_bits = get_intermediate_bits(bitdepth_max);
    const int sh = intermediate_bits + 4;
    const int rnd = (8 << intermediate_bits) + PREP_BIAS * 16;
    do {
        for (int x = 0; x < w; x++)
            dst[x] = iclip_pixel((tmp1[x] * weight +
                                  tmp2[x] * (16 - weight) + rnd) >> sh);

        tmp1 += w;
        tmp2 += w;
        dst += PXSTRIDE(dst_stride);
    } while (--h);
}

static void mask_c(pixel *dst, const ptrdiff_t dst_stride,
                   const int16_t *tmp1, const int16_t *tmp2, const int w, int h,
                   const uint8_t *mask HIGHBD_DECL_SUFFIX)
{
    const int intermediate_bits = get_intermediate_bits(bitdepth_max);
    const int sh = intermediate_bits + 6;
    const int rnd = (32 << intermediate_bits) + PREP_BIAS * 64;
    do {
        for (int x = 0; x < w; x++)
            dst[x] = iclip_pixel((tmp1[x] * mask[x] +
                                  tmp2[x] * (64 - mask[x]) + rnd) >> sh);

        tmp1 += w;
        tmp2 += w;
        mask += w;
        dst += PXSTRIDE(dst_stride);
    } while (--h);
}

static void w_mask_c(pixel *dst, const ptrdiff_t dst_stride,
                     const int16_t *tmp1, const int16_t *tmp2, const int w, int h,
                     uint8_t *mask, const int sign,
                     const int ss_hor, const int ss_ver HIGHBD_DECL_SUFFIX)
{
    // store mask at 2x2 resolution, i.e. store 2x1 sum for even rows,
    // and then load this intermediate to calculate final value for odd rows
    const int intermediate_bits = get_intermediate_bits(bitdepth_max);
    const int bitdepth = bitdepth_from_max(bitdepth_max);
    const int sh = intermediate_bits + 6;
    const int rnd = (32 << intermediate_bits) + PREP_BIAS * 64;
    const int mask_sh = bitdepth + intermediate_bits - 4;
    const int mask_rnd = 1 << (mask_sh - 5);
    do {
        for (int x = 0; x < w; x++) {
            const int m = imin(38 + ((abs(tmp1[x] - tmp2[x]) + mask_rnd) >> mask_sh), 64);
            dst[x] = iclip_pixel((tmp1[x] * m +
                                  tmp2[x] * (64 - m) + rnd) >> sh);

            if (ss_hor) {
                x++;

                const int n = imin(38 + ((abs(tmp1[x] - tmp2[x]) + mask_rnd) >> mask_sh), 64);
                dst[x] = iclip_pixel((tmp1[x] * n +
                                      tmp2[x] * (64 - n) + rnd) >> sh);

                if (h & ss_ver) {
                    mask[x >> 1] = (m + n + mask[x >> 1] + 2 - sign) >> 2;
                } else if (ss_ver) {
                    mask[x >> 1] = m + n;
                } else {
                    mask[x >> 1] = (m + n + 1 - sign) >> 1;
                }
            } else {
                mask[x] = m;
            }
        }

        tmp1 += w;
        tmp2 += w;
        dst += PXSTRIDE(dst_stride);
        if (!ss_ver || (h & 1)) mask += w >> ss_hor;
    } while (--h);
}
static COLD void init_chroma(uint8_t *chroma, const uint8_t *luma,
                             const int sign, const int w, const int h,
                             const int ss_ver)
{
    for (int y = 0; y < h; y += 1 + ss_ver) {
        for (int x = 0; x < w; x += 2) {
            int sum = luma[x] + luma[x + 1] + 1;
            if (ss_ver) sum += luma[w + x] + luma[w + x + 1] + 1;
            chroma[x >> 1] = (sum - sign) >> (1 + ss_ver);
        }
        luma += w << ss_ver;
        chroma += w >> 1;
    }
}
static int sample(int x,int y,int list,int plane,int depth) {
  int lim=(1<<depth)-1;int ramp=(x*7+y*3+list*11+plane*17)&(lim>>3);
  return ((x/2+y/3+list+plane)%4<2)?ramp:lim-ramp;
}
static void predict(int16_t *out,int depth,int sx,int sy,int list,int pl) {
  const int bitdepth_max=(1<<depth)-1;
  const int32_t matrices[2][6]={{73728,-32768,65664,256,-256,65664},{-16384,77824,65344,-128,128,65344}};
  Dav1dWarpedMotionParams wm={0};for(int i=0;i<6;i++)wm.matrix[i]=matrices[list][i];
  assert(!dav1d_get_shear_params(&wm));
  const int w=16>>sx,h=16>>sy,rw=32>>sx,rh=32>>sy;
  uint16_t edge[15*15];
  for(int y=0;y<h;y+=8){
    const int src_y=16+((y+4)<<sy);
    const int64_t mat3_y=(int64_t)wm.matrix[3]*src_y+wm.matrix[0];
    const int64_t mat5_y=(int64_t)wm.matrix[5]*src_y+wm.matrix[1];
    for(int x=0;x<w;x+=8){
      const int src_x=16+((x+4)<<sx);
      const int64_t mvx=((int64_t)wm.matrix[2]*src_x+mat3_y)>>sx;
      const int64_t mvy=((int64_t)wm.matrix[4]*src_x+mat5_y)>>sy;
      const int dx=(int)(mvx>>16)-4,dy=(int)(mvy>>16)-4;
      const int mx=(((int)mvx&0xffff)-wm.u.p.alpha*4-wm.u.p.beta*7)&~63;
      const int my=(((int)mvy&0xffff)-wm.u.p.gamma*4-wm.u.p.delta*4)&~63;
      for(int ey=0;ey<15;ey++)for(int ex=0;ex<15;ex++)edge[ey*15+ex]=sample(iclip(dx+ex-3,0,rw-1),iclip(dy+ey-3,0,rh-1),list,pl,depth);
      warp_affine_8x8t_c(out+y*w+x,w,edge+3*15+3,30,wm.u.abcd,mx,my,bitdepth_max);
    }
  }
}
int main(void){
  for(int bd=8;bd<=12;bd+=2)for(int layout=0;layout<3;layout++){
    const int bitdepth_max=(1<<bd)-1;const int sx=layout>0,sy=layout==2;
    int16_t pred[3][2][256];
    for(int pl=0;pl<3;pl++)for(int list=0;list<2;list++){
      int px=pl?sx:0,py=pl?sy:0,n=(16>>px)*(16>>py);
      predict(pred[pl][list],bd,px,py,list,pl);
      printf("P %d %d %d %d",bd,layout,pl,list);
      for(int i=0;i<n;i++)printf(" %d",pred[pl][list][i]+PREP_BIAS);printf("\n");
    }
    for(int mode=0;mode<6;mode++){
      uint8_t mask[256];uint16_t out[256];
      for(int pl=0;pl<3;pl++){
        int px=pl?sx:0,py=pl?sy:0,w=16>>px,h=16>>py;
        int sign=(mode==3||mode==5),sel=sign;
        if(mode==0)avg_c(out,w*2,pred[pl][0],pred[pl][1],w,h,bitdepth_max);
        else if(mode==1)w_avg_c(out,w*2,pred[pl][0],pred[pl][1],w,h,11,bitdepth_max);
        else if(mode<4){
          if(pl==0)w_mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,sign,sx,sy,bitdepth_max);
          else mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,bitdepth_max);
        }else{
          // 16x16 codebook entry4 is horizontal at yoff=28, sign bit4 of0x7bfb is1.
          const int border[8]={0,2,7,21,43,57,62,64};uint8_t luma[256];
          for(int y=0;y<16;y++)for(int x=0;x<16;x++)luma[y*16+x]=64-(y<8?border[y]:64);
          if(pl&&sx)init_chroma(mask,luma,sign,16,16,sy);else for(int i=0;i<256;i++)mask[i]=luma[i];
          mask_c(out,w*2,pred[pl][sel],pred[pl][!sel],w,h,mask,bitdepth_max);
        }
        printf("B %d %d %d %d",bd,layout,mode,pl);
        for(int i=0;i<w*h;i++)printf(" %d",out[i]);printf("\n");
      }
    }
  }return 0;
}
