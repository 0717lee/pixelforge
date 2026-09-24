/* Original AOM fragments retain their BSD-2-Clause and Patent licenses. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#ifdef NDEBUG
#error The palette oracle requires active C assertions.
#endif
#include "aom_dsp/bitreader.h"
#include "aom_dsp/bitwriter.h"
#define PALETTE_MAX_SIZE 8
#define PALETTE_MIN_SIZE 2
#define PALETTE_SIZES 7
#define PALETTE_COLORS 8
#define PALETTE_COLOR_INDEX_CONTEXTS 5
#define NUM_PALETTE_NEIGHBORS 3
#define MAX_COLOR_CONTEXT_HASH 8
#define ACCT_STR __func__


static const aom_cdf_prob default_palette_y_color_index_cdf
    [PALETTE_SIZES][PALETTE_COLOR_INDEX_CONTEXTS][CDF_SIZE(PALETTE_COLORS)] = {
      {
          { AOM_CDF2(28710) },
          { AOM_CDF2(16384) },
          { AOM_CDF2(10553) },
          { AOM_CDF2(27036) },
          { AOM_CDF2(31603) },
      },
      {
          { AOM_CDF3(27877, 30490) },
          { AOM_CDF3(11532, 25697) },
          { AOM_CDF3(6544, 30234) },
          { AOM_CDF3(23018, 28072) },
          { AOM_CDF3(31915, 32385) },
      },
      {
          { AOM_CDF4(25572, 28046, 30045) },
          { AOM_CDF4(9478, 21590, 27256) },
          { AOM_CDF4(7248, 26837, 29824) },
          { AOM_CDF4(19167, 24486, 28349) },
          { AOM_CDF4(31400, 31825, 32250) },
      },
      {
          { AOM_CDF5(24779, 26955, 28576, 30282) },
          { AOM_CDF5(8669, 20364, 24073, 28093) },
          { AOM_CDF5(4255, 27565, 29377, 31067) },
          { AOM_CDF5(19864, 23674, 26716, 29530) },
          { AOM_CDF5(31646, 31893, 32147, 32426) },
      },
      {
          { AOM_CDF6(23132, 25407, 26970, 28435, 30073) },
          { AOM_CDF6(7443, 17242, 20717, 24762, 27982) },
          { AOM_CDF6(6300, 24862, 26944, 28784, 30671) },
          { AOM_CDF6(18916, 22895, 25267, 27435, 29652) },
          { AOM_CDF6(31270, 31550, 31808, 32059, 32353) },
      },
      {
          { AOM_CDF7(23105, 25199, 26464, 27684, 28931, 30318) },
          { AOM_CDF7(6950, 15447, 18952, 22681, 25567, 28563) },
          { AOM_CDF7(7560, 23474, 25490, 27203, 28921, 30708) },
          { AOM_CDF7(18544, 22373, 24457, 26195, 28119, 30045) },
          { AOM_CDF7(31198, 31451, 31670, 31882, 32123, 32391) },
      },
      {
          { AOM_CDF8(21689, 23883, 25163, 26352, 27506, 28827, 30195) },
          { AOM_CDF8(6892, 15385, 17840, 21606, 24287, 26753, 29204) },
          { AOM_CDF8(5651, 23182, 25042, 26518, 27982, 29392, 30900) },
          { AOM_CDF8(19349, 22578, 24418, 25994, 27524, 29031, 30448) },
          { AOM_CDF8(31028, 31270, 31504, 31705, 31927, 32153, 32392) },
      },
    };

static const aom_cdf_prob default_palette_uv_color_index_cdf
    [PALETTE_SIZES][PALETTE_COLOR_INDEX_CONTEXTS][CDF_SIZE(PALETTE_COLORS)] = {
      {
          { AOM_CDF2(29089) },
          { AOM_CDF2(16384) },
          { AOM_CDF2(8713) },
          { AOM_CDF2(29257) },
          { AOM_CDF2(31610) },
      },
      {
          { AOM_CDF3(25257, 29145) },
          { AOM_CDF3(12287, 27293) },
          { AOM_CDF3(7033, 27960) },
          { AOM_CDF3(20145, 25405) },
          { AOM_CDF3(30608, 31639) },
      },
      {
          { AOM_CDF4(24210, 27175, 29903) },
          { AOM_CDF4(9888, 22386, 27214) },
          { AOM_CDF4(5901, 26053, 29293) },
          { AOM_CDF4(18318, 22152, 28333) },
          { AOM_CDF4(30459, 31136, 31926) },
      },
      {
          { AOM_CDF5(22980, 25479, 27781, 29986) },
          { AOM_CDF5(8413, 21408, 24859, 28874) },
          { AOM_CDF5(2257, 29449, 30594, 31598) },
          { AOM_CDF5(19189, 21202, 25915, 28620) },
          { AOM_CDF5(31844, 32044, 32281, 32518) },
      },
      {
          { AOM_CDF6(22217, 24567, 26637, 28683, 30548) },
          { AOM_CDF6(7307, 16406, 19636, 24632, 28424) },
          { AOM_CDF6(4441, 25064, 26879, 28942, 30919) },
          { AOM_CDF6(17210, 20528, 23319, 26750, 29582) },
          { AOM_CDF6(30674, 30953, 31396, 31735, 32207) },
      },
      {
          { AOM_CDF7(21239, 23168, 25044, 26962, 28705, 30506) },
          { AOM_CDF7(6545, 15012, 18004, 21817, 25503, 28701) },
          { AOM_CDF7(3448, 26295, 27437, 28704, 30126, 31442) },
          { AOM_CDF7(15889, 18323, 21704, 24698, 26976, 29690) },
          { AOM_CDF7(30988, 31204, 31479, 31734, 31983, 32325) },
      },
      {
          { AOM_CDF8(21442, 23288, 24758, 26246, 27649, 28980, 30563) },
          { AOM_CDF8(5863, 14933, 17552, 20668, 23683, 26411, 29273) },
          { AOM_CDF8(3415, 25810, 26877, 27990, 29223, 30394, 31618) },
          { AOM_CDF8(17965, 20084, 22232, 23974, 26274, 28402, 30390) },
          { AOM_CDF8(31190, 31329, 31516, 31679, 31825, 32026, 32322) },
      },
    };

const int av1_palette_color_index_context_lookup[MAX_COLOR_CONTEXT_HASH + 1] = {
  -1, -1, 0, -1, -1, 4, 3, 2, 1
};

int av1_get_palette_color_index_context(const uint8_t *color_map, int stride,
                                        int r, int c, int palette_size,
                                        uint8_t *color_order, int *color_idx) {
  assert(palette_size <= PALETTE_MAX_SIZE);
  assert(r > 0 || c > 0);

  // Get color indices of neighbors.
  int color_neighbors[NUM_PALETTE_NEIGHBORS];
  color_neighbors[0] = (c - 1 >= 0) ? color_map[r * stride + c - 1] : -1;
  color_neighbors[1] =
      (c - 1 >= 0 && r - 1 >= 0) ? color_map[(r - 1) * stride + c - 1] : -1;
  color_neighbors[2] = (r - 1 >= 0) ? color_map[(r - 1) * stride + c] : -1;

  // The +10 below should not be needed. But we get a warning "array subscript
  // is above array bounds [-Werror=array-bounds]" without it, possibly due to
  // this (or similar) bug: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=59124
  int scores[PALETTE_MAX_SIZE + 10] = { 0 };
  int i;
  static const int weights[NUM_PALETTE_NEIGHBORS] = { 2, 1, 2 };
  for (i = 0; i < NUM_PALETTE_NEIGHBORS; ++i) {
    if (color_neighbors[i] >= 0) {
      scores[color_neighbors[i]] += weights[i];
    }
  }

  int inverse_color_order[PALETTE_MAX_SIZE];
  for (i = 0; i < PALETTE_MAX_SIZE; ++i) {
    color_order[i] = i;
    inverse_color_order[i] = i;
  }

  // Get the top NUM_PALETTE_NEIGHBORS scores (sorted from large to small).
  for (i = 0; i < NUM_PALETTE_NEIGHBORS; ++i) {
    int max = scores[i];
    int max_idx = i;
    for (int j = i + 1; j < palette_size; ++j) {
      if (scores[j] > max) {
        max = scores[j];
        max_idx = j;
      }
    }
    if (max_idx != i) {
      // Move the score at index 'max_idx' to index 'i', and shift the scores
      // from 'i' to 'max_idx - 1' by 1.
      const int max_score = scores[max_idx];
      const uint8_t max_color_order = color_order[max_idx];
      for (int k = max_idx; k > i; --k) {
        scores[k] = scores[k - 1];
        color_order[k] = color_order[k - 1];
        inverse_color_order[color_order[k]] = k;
      }
      scores[i] = max_score;
      color_order[i] = max_color_order;
      inverse_color_order[color_order[i]] = i;
    }
  }

  if (color_idx != NULL)
    *color_idx = inverse_color_order[color_map[r * stride + c]];

  // Get hash value of context.
  int color_index_ctx_hash = 0;
  static const int hash_multipliers[NUM_PALETTE_NEIGHBORS] = { 1, 2, 2 };
  for (i = 0; i < NUM_PALETTE_NEIGHBORS; ++i) {
    color_index_ctx_hash += scores[i] * hash_multipliers[i];
  }
  assert(color_index_ctx_hash > 0);
  assert(color_index_ctx_hash <= MAX_COLOR_CONTEXT_HASH);

  // Lookup context from hash.
  const int color_index_ctx =
      av1_palette_color_index_context_lookup[color_index_ctx_hash];
  assert(color_index_ctx >= 0);
  assert(color_index_ctx < PALETTE_COLOR_INDEX_CONTEXTS);
  return color_index_ctx;
}

typedef aom_cdf_prob (*MapCdf)[PALETTE_COLOR_INDEX_CONTEXTS]
                              [CDF_SIZE(PALETTE_COLORS)];
// Pointer to a const three-dimensional array whose first dimension is
// PALETTE_SIZES.
typedef const int (*ColorCost)[PALETTE_COLOR_INDEX_CONTEXTS][PALETTE_COLORS];
/* clang-format on */

typedef struct {
  int rows;
  int cols;
  int n_colors;
  int plane_width;
  int plane_height;
  uint8_t *color_map;
  MapCdf map_cdf;
  ColorCost color_cost;
} Av1ColorMapParam;

static inline int get_unsigned_bits(unsigned int num_values) {
  return num_values > 0 ? get_msb(num_values) + 1 : 0;
}

static inline int av1_read_uniform(aom_reader *r, int n) {
  const int l = get_unsigned_bits(n);
  const int m = (1 << l) - n;
  const int v = aom_read_literal(r, l - 1, ACCT_STR);
  assert(l != 0);
  if (v < m)
    return v;
  else
    return (v << 1) - m + aom_read_literal(r, 1, ACCT_STR);
}

static inline void write_uniform(aom_writer *w, int n, int v) {
  const int l = get_unsigned_bits(n);
  const int m = (1 << l) - n;
  if (l == 0) return;
  if (v < m) {
    aom_write_literal(w, v, l - 1);
  } else {
    aom_write_literal(w, m + ((v - m) >> 1), l - 1);
    aom_write_literal(w, (v - m) & 1, 1);
  }
}

static void decode_color_map_tokens(Av1ColorMapParam *param, aom_reader *r) {
  uint8_t color_order[PALETTE_MAX_SIZE];
  const int n = param->n_colors;
  uint8_t *const color_map = param->color_map;
  MapCdf color_map_cdf = param->map_cdf;
  int plane_block_width = param->plane_width;
  int plane_block_height = param->plane_height;
  int rows = param->rows;
  int cols = param->cols;

  // The first color index.
  color_map[0] = av1_read_uniform(r, n);
  assert(color_map[0] < n);

  // Run wavefront on the palette map index decoding.
  for (int i = 1; i < rows + cols - 1; ++i) {
    for (int j = AOMMIN(i, cols - 1); j >= AOMMAX(0, i - rows + 1); --j) {
      const int color_ctx = av1_get_palette_color_index_context(
          color_map, plane_block_width, (i - j), j, n, color_order, NULL);
      const int color_idx = aom_read_symbol(
          r, color_map_cdf[n - PALETTE_MIN_SIZE][color_ctx], n, ACCT_STR);
      assert(color_idx >= 0 && color_idx < n);
      color_map[(i - j) * plane_block_width + j] = color_order[color_idx];
    }
  }
  // Copy last column to extra columns.
  if (cols < plane_block_width) {
    for (int i = 0; i < rows; ++i) {
      memset(color_map + i * plane_block_width + cols,
             color_map[i * plane_block_width + cols - 1],
             (plane_block_width - cols));
    }
  }
  // Copy last row to extra rows.
  for (int i = rows; i < plane_block_height; ++i) {
    memcpy(color_map + i * plane_block_width,
           color_map + (rows - 1) * plane_block_width, plane_block_width);
  }
}


static void emit_cdf(MapCdf cdf, int n) {
  for (int k = 0; k < 5; ++k) {
    for (int j = 0; j < n; ++j) printf(" %d", 32768 - cdf[n - 2][k][j]);
    printf(" %d", cdf[n - 2][k][n]);
  }
}
static void print_hex(const uint8_t *data, int size) {
  for (int i = 0; i < size; ++i) printf("%02x", data[i]);
}
static int read_hex(const char *hex, uint8_t *data, int capacity) {
  int length = (int)strlen(hex);
  assert(!(length & 1) && length / 2 <= capacity);
  for (int i = 0; i < length / 2; ++i) {
    unsigned int value;
    assert(sscanf(hex + i * 2, "%2x", &value) == 1);
    data[i] = value;
  }
  return length / 2;
}
int main(void) {
  char command[8];
  while (scanf("%7s", command) == 1) {
    if (command[0] == 'C') {
      int n, kind, left, top_left, top;
      assert(scanf("%d%d%d%d%d", &n, &kind, &left, &top_left, &top) == 5);
      uint8_t map[9] = { 0 }, order[8], inverse_order[8];
      int row = kind == 0 ? 0 : 1, col = kind == 1 ? 0 : 1;
      if (left >= 0) map[row * 3 + col - 1] = left;
      if (top >= 0) map[(row - 1) * 3 + col] = top;
      if (top_left >= 0) map[(row - 1) * 3 + col - 1] = top_left;
      int context = av1_get_palette_color_index_context(map, 3, row, col, n, order, NULL);
      for (int value = 0; value < n; ++value) {
        int rank = -1;
        map[row * 3 + col] = value;
        assert(av1_get_palette_color_index_context(map, 3, row, col, n,
                                                   inverse_order, &rank) == context);
        assert(!memcmp(order, inverse_order, 8));
        assert(rank >= 0 && rank < n && order[rank] == value);
      }
      printf("C %d", context);
      for (int i = 0; i < 8; ++i) printf(" %d", order[i]);
      printf("\n");
    } else if (command[0] == 'T') {
      int plane, n;
      assert(scanf("%d%d", &plane, &n) == 2);
      aom_cdf_prob cdf[7][5][9];
      memcpy(cdf, plane ? default_palette_uv_color_index_cdf : default_palette_y_color_index_cdf,
             sizeof(cdf));
      printf("T"); emit_cdf(cdf, n); printf("\n");
    } else if (command[0] == 'V') {
      int n, plane, allow_update, map_count;
      char input_hex[65536];
      uint8_t input[32768], output[32768];
      assert(scanf("%d%d%d%d%65535s", &n, &plane, &allow_update, &map_count, input_hex) == 5);
      int size = read_hex(input_hex, input, sizeof(input));
      aom_cdf_prob decode_cdf[7][5][9], encode_cdf[7][5][9];
      memcpy(decode_cdf, plane ? default_palette_uv_color_index_cdf : default_palette_y_color_index_cdf,
             sizeof(decode_cdf));
      memcpy(encode_cdf, decode_cdf, sizeof(encode_cdf));
      aom_reader reader;
      assert(aom_reader_init(&reader, input, size) == 0);
      reader.allow_update_cdf = allow_update;
      aom_writer writer;
      aom_start_encode(&writer, output, sizeof(output));
      writer.allow_update_cdf = allow_update;
      for (int index = 0; index < map_count; ++index) {
        int width, height, rows, cols;
        uint8_t expected[4096], decoded[4096], order[8];
        char map_hex[8193];
        assert(scanf("%d%d%d%d%8192s", &width, &height, &rows, &cols, map_hex) == 5);
        assert(read_hex(map_hex, expected, sizeof(expected)) == width * height);
        memset(decoded, 255, sizeof(decoded));
        Av1ColorMapParam param = { rows, cols, n, width, height, decoded, decode_cdf, NULL };
        decode_color_map_tokens(&param, &reader);
        int marker = aom_read_literal(&reader, 16, ACCT_STR);
        assert(marker == 0xA5D3 && !memcmp(decoded, expected, width * height));
        write_uniform(&writer, n, expected[0]);
        for (int diagonal = 1; diagonal < rows + cols - 1; ++diagonal) {
          for (int col = AOMMIN(diagonal, cols - 1); col >= AOMMAX(0, diagonal - rows + 1); --col) {
            int rank;
            int context = av1_get_palette_color_index_context(expected, width,
                diagonal - col, col, n, order, &rank);
            aom_write_symbol(&writer, rank, encode_cdf[n - 2][context], n);
          }
        }
        aom_write_literal(&writer, 0xA5D3, 16);
        assert(!memcmp(decode_cdf, encode_cdf, sizeof(decode_cdf)));
        printf("V %d %d ", index, marker);
        print_hex(decoded, width * height);
        emit_cdf(decode_cdf, n); printf("\n");
      }
      assert(!aom_reader_has_overflowed(&reader));
      int written = aom_stop_encode(&writer);
      assert(written >= 0 && writer.pos <= sizeof(output));
      printf("W "); print_hex(output, writer.pos); printf("\n");
    } else {
      fprintf(stderr, "unexpected command %s\n", command);
      return 2;
    }
  }
  return 0;
}
