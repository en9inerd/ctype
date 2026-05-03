#include "input.h"
#include "words.h"

#include <time.h>

void on_char_zen(State *s, char c) {
  if (!s->started) {
    s->started = true;
    clock_gettime(CLOCK_MONOTONIC, &s->start_ts);
  }
  if (c == ' ' && s->zen_line_len > 0)
    s->zen_total_words++;
  s->zen_total_chars++;
  if (s->zen_line_len < (int)sizeof(s->zen_line) - 1) {
    s->zen_line[s->zen_line_len++] = c;
    s->zen_line[s->zen_line_len] = '\0';
  }
}

void on_backspace_zen(State *s) {
  if (s->zen_line_len > 0) {
    char deleted = s->zen_line[--s->zen_line_len];
    s->zen_line[s->zen_line_len] = '\0';
    if (s->zen_total_chars > 0)
      s->zen_total_chars--;
    if (deleted == ' ' && s->zen_total_words > 0)
      s->zen_total_words--;
  }
}

void on_char(State *s, char c) {
  if (!s->started) {
    s->started = true;
    clock_gettime(CLOCK_MONOTONIC, &s->start_ts);
  }
  if (s->cur_word >= s->word_count)
    return;
  Word *w = &s->words[s->cur_word];

  if (c == ' ') {
    if (w->typed_len == 0)
      return;
    bool ok = (w->typed_len == w->target_len);
    for (int i = 0; ok && i < w->target_len; i++)
      if (w->typed[i] != w->target[i])
        ok = false;
    if (ok) {
      s->correct_keys++;
      s->correct_word_chars += w->target_len;
      s->correct_word_count++;
    } else {
      s->incorrect_keys++;
    }
    w->finalized = true;
    s->total_spaces++;
    s->cur_word++;
    if (s->cur_word >= s->word_count && s->mode != MODE_WORDS) {
      append_sampled(s, INITIAL_SAMPLES);
    }
  } else if (w->typed_len < MAX_TYPED - 1) {
    int pos = w->typed_len;
    if (pos < w->target_len && c == w->target[pos])
      s->correct_keys++;
    else
      s->incorrect_keys++;
    w->typed[w->typed_len++] = c;
    w->typed[w->typed_len] = '\0';
    if (s->mode == MODE_WORDS && s->cur_word == s->words_target - 1 &&
        w->typed_len == w->target_len) {
      bool match = true;
      for (int i = 0; i < w->target_len; i++)
        if (w->typed[i] != w->target[i]) {
          match = false;
          break;
        }
      if (match) {
        w->finalized = true;
        s->correct_word_chars += w->target_len;
        s->cur_word++;
      }
    }
  }
}

[[nodiscard]] bool word_imperfect(const Word *w) {
  if (w->typed_len != w->target_len)
    return true;
  for (int i = 0; i < w->target_len; i++) {
    if (w->typed[i] != w->target[i])
      return true;
  }
  return false;
}

void on_backspace(State *s) {
  if (s->cur_word >= s->word_count)
    return;
  Word *w = &s->words[s->cur_word];
  if (w->typed_len > 0) {
    w->typed[--w->typed_len] = '\0';
  } else if (s->cur_word > 0) {
    Word *prev = &s->words[s->cur_word - 1];
    if (word_imperfect(prev)) {
      s->cur_word--;
      prev->finalized = false;
      s->total_spaces--;
    }
  }
}
