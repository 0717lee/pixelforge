/*
 * Copyright © 2020, VideoLAN and dav1d authors
 * Copyright © 2020, Two Orioles, LLC
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


typedef signed char int8_t; typedef short int16_t;
typedef unsigned short uint16_t; typedef unsigned long long uint64_t;
extern int printf(const char *, ...); extern void abort(void);
#define assert(x) ((x) ? (void)0 : abort())
#define INVALID_MV 0x80008000U
static int abs(int v) { return v < 0 ? -v : v; }
static int iclip(int v,int lo,int hi) { return v < lo ? lo : v > hi ? hi : v; }
typedef union mv { struct { int16_t y,x; }; unsigned n; } mv;
typedef union refmvs_mvpair { mv mv[2]; uint64_t n; } refmvs_mvpair;
typedef union refmvs_refpair { int8_t ref[2]; uint16_t pair; } refmvs_refpair;
typedef struct refmvs_candidate { refmvs_mvpair mv; int weight; } refmvs_candidate;
typedef struct refmvs_temporal_block { mv mv; int8_t ref; } refmvs_temporal_block;
typedef struct Dav1dFrameHeader { int force_integer_mv,hp; } Dav1dFrameHeader;
typedef struct refmvs_frame { const Dav1dFrameHeader *frm_hdr; int8_t pocdiff[7]; } refmvs_frame;
static inline void fix_int_mv_precision(mv *const mv) {
    mv->x = (mv->x - (mv->x >> 15) + 3) & ~7U;
    mv->y = (mv->y - (mv->y >> 15) + 3) & ~7U;
}

static inline void fix_mv_precision(const Dav1dFrameHeader *const hdr,
                                    mv *const mv)
{
    if (hdr->force_integer_mv) {
        fix_int_mv_precision(mv);
    } else if (!hdr->hp) {
        mv->x = (mv->x - (mv->x >> 15)) & ~1U;
        mv->y = (mv->y - (mv->y >> 15)) & ~1U;
    }
}

static inline union mv mv_projection(const union mv mv, const int num, const int den) {
    static const uint16_t div_mult[32] = {
           0, 16384, 8192, 5461, 4096, 3276, 2730, 2340,
        2048,  1820, 1638, 1489, 1365, 1260, 1170, 1092,
        1024,   963,  910,  862,  819,  780,  744,  712,
         682,   655,  630,  606,  585,  564,  546,  528
    };
    assert(den > 0 && den < 32);
    assert(num > -32 && num < 32);
    const int frac = num * div_mult[den];
    const int y = mv.y * frac, x = mv.x * frac;
    // Round and clip according to AV1 spec section 7.9.3
    return (union mv) { // 0x3fff == (1 << 14) - 1
        .y = iclip((y + 8192 + (y >> 31)) >> 14, -0x3fff, 0x3fff),
        .x = iclip((x + 8192 + (x >> 31)) >> 14, -0x3fff, 0x3fff)
    };
}

static void add_temporal_candidate(const refmvs_frame *const rf,
                                   refmvs_candidate *const mvstack, int *const cnt,
                                   const refmvs_temporal_block *const rb,
                                   const union refmvs_refpair ref, int *const globalmv_ctx,
                                   const union mv gmv[])
{
    if (rb->mv.n == INVALID_MV) return;

    union mv mv = mv_projection(rb->mv, rf->pocdiff[ref.ref[0] - 1], rb->ref);
    fix_mv_precision(rf->frm_hdr, &mv);

    const int last = *cnt;
    if (ref.ref[1] == -1) {
        if (globalmv_ctx)
            *globalmv_ctx = (abs(mv.x - gmv[0].x) | abs(mv.y - gmv[0].y)) >= 16;

        for (int n = 0; n < last; n++)
            if (mvstack[n].mv.mv[0].n == mv.n) {
                mvstack[n].weight += 2;
                return;
            }
        if (last < 8) {
            mvstack[last].mv.mv[0] = mv;
            mvstack[last].weight = 2;
            *cnt = last + 1;
        }
    } else {
        refmvs_mvpair mvp = { .mv = {
            [0] = mv,
            [1] = mv_projection(rb->mv, rf->pocdiff[ref.ref[1] - 1], rb->ref),
        }};
        fix_mv_precision(rf->frm_hdr, &mvp.mv[1]);

        for (int n = 0; n < last; n++)
            if (mvstack[n].mv.n == mvp.n) {
                mvstack[n].weight += 2;
                return;
            }
        if (last < 8) {
            mvstack[last].mv = mvp;
            mvstack[last].weight = 2;
            *cnt = last + 1;
        }
    }
}
int main(void) {
  for (int policy=0;policy<5;policy++) {
    /* AV1 uncompressed_header: force_integer_mv implies hp == 0. */
    Dav1dFrameHeader hdr={ policy==2, policy!=1 && policy!=2 };
    refmvs_frame rf={0}; rf.frm_hdr=&hdr;
    rf.pocdiff[0]=policy==3?0:1; rf.pocdiff[4]=policy==3?1:-1;
    refmvs_candidate stack[8]={0}; int count=0;
    refmvs_refpair refs={.ref={1,5}};
    if (policy==4) {
      count=8;
      for(int i=0;i<8;i++) {
        stack[i].mv.mv[0].y=i*8; stack[i].mv.mv[1].y=-i*8;
        stack[i].weight=640;
      }
    }
    for(int step=0;step<3;step++) {
      const int y=policy==4?(step==2?65:40):(step==2?33:31);
      const int x=policy==4?0:(step==2?-49:-47);
      refmvs_temporal_block rb={.mv={.y=y,.x=x},.ref=policy>=3?1:2};
      add_temporal_candidate(&rf,stack,&count,&rb,refs,0,0);
    }
    printf("C %d %d\n",policy,count);
    for(int i=0;i<count;i++) printf("M %d %d %d %d %d\n",
      stack[i].mv.mv[0].y,stack[i].mv.mv[0].x,
      stack[i].mv.mv[1].y,stack[i].mv.mv[1].x,stack[i].weight);
  }
  return 0;
}
