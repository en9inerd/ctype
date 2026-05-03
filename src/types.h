#pragma once

#include <stddef.h>
#include <time.h>

#ifndef CTYPE_VERSION
#define CTYPE_VERSION "dev"
#endif

enum {
  MAX_WORD_LEN = 30,
  MAX_TYPED = 80,
  MIN_COLS = 40,
  MIN_ROWS = 10,
  MAX_WORDLIST_BYTES = 1 << 20,
  VIEWPORT_LINES = 3,
  INITIAL_SAMPLES = 80,
  REFILL_THRESHOLD = 20,
  TICK_USEC = 100'000,
  MAX_TEXT_WIDTH = 80,
  MIN_TEXT_WIDTH = 20,
  TEXT_MARGIN = 4,
  INPUT_BUF_SIZE = 64,
  INITIAL_FRAME_CAP = 8192,
  DEFAULT_WORDS = 25,
};

typedef enum : unsigned char { MODE_WORDS, MODE_TIME, MODE_ZEN } Mode;

typedef struct {
  char target[MAX_WORD_LEN + 5];
  int target_len;
  char typed[MAX_TYPED];
  int typed_len;
  bool finalized;
} Word;

typedef struct {
  const char *dim, *text, *main_, *err, *err_bg;
} Palette;

typedef struct {
  Mode mode;
  int duration_target;
  int words_target;
  bool punct;
  bool numbers;
  char last_char;

  char **pool;
  int pool_count;
  char *pool_buf;

  Word *words;
  int word_count;
  int word_cap;
  int cur_word;

  bool started;
  struct timespec start_ts;
  struct timespec end_ts;

  int cols, rows;
  bool aborted;
  bool resized;

  Palette pal;

  int last_drawn_second;
  int last_drawn_cur;
  int last_drawn_typed;
  bool needs_render;

  int acc_correct, acc_wrong, acc_extra, acc_missed;

  int correct_keys;
  int incorrect_keys;

  int correct_word_chars;
  int correct_word_count;
  int total_spaces;

  char zen_line[4096];
  int zen_line_len;
  int zen_total_chars;
  int zen_total_words;
} State;

typedef struct {
  int correct, wrong, extra, missed;
  int total_typed;
  double wpm, raw, acc;
  double seconds;
} Stats;

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} Frame;
