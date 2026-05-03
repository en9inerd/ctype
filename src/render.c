#include "render.h"
#include "stats.h"
#include "term.h"

#include <stdlib.h>
#include <string.h>

#define TC_DIM "\x1b[38;2;100;102;105m"
#define TC_TEXT "\x1b[38;2;209;208;197m"
#define TC_MAIN "\x1b[38;2;226;183;20m"
#define TC_ERR "\x1b[38;2;202;71;84m"
#define TC_ERR_BG "\x1b[48;2;126;42;51m\x1b[38;2;255;255;255m"

#define P_DIM "\x1b[38;5;240m"
#define P_TEXT "\x1b[38;5;253m"
#define P_MAIN "\x1b[38;5;179m"
#define P_ERR "\x1b[38;5;167m"
#define P_ERR_BG "\x1b[48;5;52m\x1b[38;5;231m"

#define UL_ON "\x1b[4m"
#define UL_OFF "\x1b[24m"

void detect_palette(State *s) {
  const char *ct = getenv("COLORTERM");
  bool truecolor = ct && (strstr(ct, "truecolor") || strstr(ct, "24bit"));
  s->pal = truecolor ? (Palette){.dim = TC_DIM,
                                 .text = TC_TEXT,
                                 .main_ = TC_MAIN,
                                 .err = TC_ERR,
                                 .err_bg = TC_ERR_BG}
                     : (Palette){.dim = P_DIM,
                                 .text = P_TEXT,
                                 .main_ = P_MAIN,
                                 .err = P_ERR,
                                 .err_bg = P_ERR_BG};
}

enum { MAX_LAYOUT_LINES = 1024 };

static int layout_lines(const State *s, int max_cols, int *line_first,
                        int max_lines) {
  int n = 1, c = 0;
  line_first[0] = 0;
  for (int wi = 0; wi < s->word_count && n < max_lines; wi++) {
    const Word *w = &s->words[wi];
    int extras =
        w->typed_len > w->target_len ? w->typed_len - w->target_len : 0;
    int wlen = w->target_len + extras;
    if (c != 0 && c + wlen > max_cols) {
      line_first[n++] = wi;
      c = 0;
    }
    c += wlen;
    if (c + 1 <= max_cols) {
      c++;
    } else {
      if (wi + 1 < s->word_count && n < max_lines)
        line_first[n++] = wi + 1;
      c = 0;
    }
  }
  return n;
}

void render(State *s, Frame *f) {
  int max_cols = s->cols - TEXT_MARGIN;
  if (max_cols > MAX_TEXT_WIDTH)
    max_cols = MAX_TEXT_WIDTH;
  if (max_cols < MIN_TEXT_WIDTH)
    max_cols = MIN_TEXT_WIDTH;
  int x_off = (s->cols - max_cols) / 2 + 1;
  if (x_off < 1)
    x_off = 1;

  int stats_row = 2;
  int words_row = s->rows / 2 - 1;
  int hint_row = s->rows - 2;
  if (words_row < stats_row + 2)
    words_row = stats_row + 2;
  if (hint_row < words_row + VIEWPORT_LINES)
    hint_row = words_row + VIEWPORT_LINES;

  Stats st = compute_stats(s);

  fb_reset(f);
  fb_appendz(f, SYNC_BEGIN HIDE);
  if (s->resized) {
    fb_appendz(f, HOME CLEAR);
    s->resized = false;
  }

  fb_appendf(f, "\x1b[%d;%dH%s", stats_row, x_off, s->pal.main_);
  switch (s->mode) {
  case MODE_TIME: {
    int rem = s->duration_target - (int)st.seconds;
    if (rem < 0)
      rem = 0;
    fb_appendf(f, "time %ds  %ds left  wpm %d  acc %d%%",
               s->duration_target, rem, (int)(st.wpm + 0.5),
               (int)(st.acc * 100.0 + 0.5));
    break;
  }
  case MODE_WORDS:
    fb_appendf(f, "words %d  %d/%d  wpm %d  acc %d%%", s->words_target,
               s->cur_word, s->words_target, (int)(st.wpm + 0.5),
               (int)(st.acc * 100.0 + 0.5));
    break;
  case MODE_ZEN:
    fb_appendf(f, "zen  %.1fs  raw wpm %d", st.seconds, (int)(st.raw + 0.5));
    break;
  }
  fb_appendz(f, RESET EOL);

  if (s->mode == MODE_ZEN) {
    fb_appendf(f, "\x1b[%d;%dH", words_row, x_off);
    int vis_len = s->zen_line_len;
    if (vis_len > max_cols)
      vis_len = max_cols;
    int start = s->zen_line_len > max_cols ? s->zen_line_len - max_cols : 0;
    fb_appendz(f, s->pal.text);
    for (int i = start; i < s->zen_line_len; i++)
      fb_byte(f, s->zen_line[i]);
    fb_appendz(f, s->pal.main_);
    fb_appendz(f, UL_ON);
    fb_byte(f, ' ');
    fb_appendz(f, UL_OFF RESET);
    int drawn = vis_len + 1;
    while (drawn < max_cols) {
      fb_byte(f, ' ');
      drawn++;
    }
    fb_appendz(f, EOL);
    for (int r = 1; r < VIEWPORT_LINES; r++)
      fb_appendf(f, "\x1b[%d;%dH" EOL, words_row + r, x_off);
  } else {
    int line_first[MAX_LAYOUT_LINES];
    int n_lines = layout_lines(s, max_cols, line_first, MAX_LAYOUT_LINES);

    int cur_line = 0;
    for (int l = n_lines - 1; l >= 0; l--) {
      if (line_first[l] <= s->cur_word) {
        cur_line = l;
        break;
      }
    }

    int view_start = cur_line > 0 ? cur_line - 1 : 0;
    if (view_start + VIEWPORT_LINES > n_lines && n_lines > VIEWPORT_LINES)
      view_start = n_lines - VIEWPORT_LINES;

    int wi_begin = line_first[view_start];
    int row = 0, col = 0;
    bool row_written[VIEWPORT_LINES] = {};
    const char *cur_color = nullptr;

    for (int wi = wi_begin; wi < s->word_count; wi++) {
      Word *w = &s->words[wi];
      int extras =
          w->typed_len > w->target_len ? w->typed_len - w->target_len : 0;
      int wlen = w->target_len + extras;

      if (col != 0 && col + wlen > max_cols) {
        fb_appendz(f, EOL);
        row++;
        col = 0;
        if (row >= VIEWPORT_LINES)
          break;
      }

      if (col == 0) {
        fb_appendf(f, "\x1b[%d;%dH", words_row + row, x_off);
        row_written[row] = true;
        cur_color = nullptr;
      }

      for (int ci = 0; ci < w->target_len; ci++) {
        bool is_cursor = (wi == s->cur_word && ci == w->typed_len);
        const char *color;
        if (ci < w->typed_len)
          color = (w->typed[ci] == w->target[ci]) ? s->pal.text : s->pal.err;
        else if (is_cursor)
          color = s->pal.main_;
        else
          color = s->pal.dim;

        if (is_cursor)
          fb_appendz(f, UL_ON);
        if (color != cur_color) {
          fb_appendz(f, color);
          cur_color = color;
        }
        fb_byte(f, w->target[ci]);
        if (is_cursor) {
          fb_appendz(f, UL_OFF);
          cur_color = nullptr;
        }
      }
      for (int ei = 0; ei < extras; ei++) {
        if (s->pal.err_bg != cur_color) {
          fb_appendz(f, s->pal.err_bg);
          cur_color = s->pal.err_bg;
        }
        fb_byte(f, w->typed[w->target_len + ei]);
      }
      bool cursor_space = false;
      if (wi == s->cur_word && w->typed_len >= w->target_len + extras) {
        fb_appendz(f, RESET);
        fb_appendz(f, s->pal.main_);
        fb_appendz(f, UL_ON);
        fb_byte(f, ' ');
        fb_appendz(f, UL_OFF);
        col++;
        cursor_space = true;
      }
      fb_appendz(f, RESET);
      cur_color = nullptr;

      col += wlen;
      if (!cursor_space) {
        if (col + 1 <= max_cols) {
          fb_byte(f, ' ');
          col++;
        } else {
          fb_appendz(f, EOL);
          row++;
          col = 0;
          if (row >= VIEWPORT_LINES)
            break;
        }
      }
    }
    if (row < VIEWPORT_LINES && row_written[row])
      fb_appendz(f, EOL);
    for (int r = 0; r < VIEWPORT_LINES; r++) {
      if (!row_written[r])
        fb_appendf(f, "\x1b[%d;%dH" EOL, words_row + r, x_off);
    }
  }

  fb_appendf(f, "\x1b[%d;%dH%sEsc end  Tab restart  Ctrl-C abort%s" EOL,
             hint_row, x_off, s->pal.dim, RESET);

  fb_appendz(f, SYNC_END);
  fb_flush(f);
}
