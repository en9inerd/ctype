#include "input.h"
#include "render.h"
#include "stats.h"
#include "term.h"
#include "words.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>

static void reset_test(State *s) {
  if (s->mode == MODE_ZEN) {
    s->zen_line_len = 0;
    s->zen_line[0] = '\0';
    s->zen_total_chars = 0;
    s->zen_total_words = 0;
  } else {
    free(s->words);
    s->words = nullptr;
    s->word_count = 0;
    s->word_cap = 0;
    s->cur_word = 0;
    s->acc_correct = s->acc_wrong = s->acc_extra = s->acc_missed = 0;
    s->correct_keys = s->incorrect_keys = 0;
    s->correct_word_chars = s->correct_word_count = s->total_spaces = 0;
    s->last_char = 0;
    seed_words(s);
  }
  s->started = false;
  s->start_ts = (struct timespec){};
  s->end_ts = (struct timespec){};
  s->last_drawn_second = -1;
  s->last_drawn_cur = -1;
  s->last_drawn_typed = -1;
}

[[nodiscard]] static bool should_end(const State *s) {
  if (s->aborted)
    return true;
  if (!s->started)
    return false;
  if (s->mode == MODE_TIME)
    return elapsed_seconds(s) >= (double)s->duration_target;
  if (s->mode == MODE_WORDS)
    return s->cur_word >= s->words_target;
  return false;
}

[[nodiscard]] static bool needs_render(const State *s) {
  if (s->needs_render)
    return true;
  if ((int)elapsed_seconds(s) != s->last_drawn_second)
    return true;
  if (s->mode == MODE_ZEN)
    return s->zen_line_len != s->last_drawn_typed;
  if (s->cur_word != s->last_drawn_cur)
    return true;
  int tlen = s->cur_word < s->word_count ? s->words[s->cur_word].typed_len : 0;
  return tlen != s->last_drawn_typed;
}

static void mark_drawn(State *s) {
  s->last_drawn_second = (int)elapsed_seconds(s);
  if (s->mode == MODE_ZEN) {
    s->last_drawn_typed = s->zen_line_len;
  } else {
    s->last_drawn_cur = s->cur_word;
    s->last_drawn_typed =
        s->cur_word < s->word_count ? s->words[s->cur_word].typed_len : 0;
  }
  s->needs_render = false;
}

static void free_state(State *s) {
  free(s->words);
  free(s->pool);
  free(s->pool_buf);
  *s = (State){};
}

static void seed_rng(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  srand((unsigned)ts.tv_nsec ^ (unsigned)ts.tv_sec ^ (unsigned)getpid());
}

static void run_test(State *s) {
  detect_palette(s);
  enable_raw_mode();
  install_signals();
  query_size(s);
  if (s->cols < MIN_COLS || s->rows < MIN_ROWS)
    die("terminal too small (need >= 40x10)");

  if (s->mode != MODE_ZEN)
    seed_words(s);

  Frame frame = {};
  fb_reserve(&frame, INITIAL_FRAME_CAP);
  s->needs_render = true;
  s->resized = true;
  render(s, &frame);
  mark_drawn(s);

  while (!should_end(s)) {
    if (g_die_flag) {
      s->aborted = true;
      break;
    }
    if (g_resize_flag) {
      g_resize_flag = 0;
      query_size(s);
      s->needs_render = true;
      s->resized = true;
    }

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(STDIN_FILENO, &rfds);
    struct timeval tv = {.tv_sec = 0, .tv_usec = TICK_USEC};
    int r = select(STDIN_FILENO + 1, &rfds, nullptr, nullptr, &tv);
    if (r < 0) {
      if (errno == EINTR)
        continue;
      die("select");
    }

    bool input_changed = false;
    if (r > 0 && FD_ISSET(STDIN_FILENO, &rfds)) {
      char buf[INPUT_BUF_SIZE];
      ssize_t got = read(STDIN_FILENO, buf, sizeof(buf));
      if (got < 0) {
        if (errno == EINTR)
          continue;
        die("read");
      }
      for (ssize_t i = 0; i < got; i++) {
        unsigned char c = (unsigned char)buf[i];
        if (c == 0x03) {
          s->aborted = true;
          goto end;
        }
        if (c == 0x1b)
          goto end;
        if (c == 0x09) {
          reset_test(s);
          s->needs_render = true;
          input_changed = true;
          continue;
        }
        if (c == 0x7f || c == 0x08) {
          if (s->mode == MODE_ZEN)
            on_backspace_zen(s);
          else
            on_backspace(s);
          input_changed = true;
          continue;
        }
        if (c >= 0x20 && c < 0x7f) {
          if (s->mode == MODE_ZEN)
            on_char_zen(s, (char)c);
          else
            on_char(s, (char)c);
          input_changed = true;
          continue;
        }
      }
      if (input_changed && s->mode != MODE_ZEN)
        maybe_refill(s);
    }

    if (needs_render(s)) {
      render(s, &frame);
      mark_drawn(s);
    }
  }
end:
  clock_gettime(CLOCK_MONOTONIC, &s->end_ts);
  free(frame.data);
  disable_raw_mode();

  if (s->aborted || !s->started) {
    if (s->aborted)
      printf("\naborted.\n");
    return;
  }

  Stats st = compute_stats(s);
  append_stats(s, &st);
  const char *mode_s = s->mode == MODE_TIME ? "time"
                       : s->mode == MODE_ZEN  ? "zen"
                                              : "words";
  printf("\n");
  printf("  mode      %s\n", mode_s);
  printf("  time      %.2fs\n", st.seconds);
  if (s->mode == MODE_ZEN) {
    printf("  raw wpm   %.1f\n", st.raw);
    printf("  chars     %d\n", s->zen_total_chars);
    printf("  words     %d\n", s->zen_total_words);
  } else {
    printf("  wpm       %.1f\n", st.wpm);
    printf("  raw wpm   %.1f\n", st.raw);
    printf("  accuracy  %.1f%%\n", st.acc * 100.0);
    printf("  correct   %d\n", st.correct);
    printf("  wrong     %d\n", st.wrong);
    printf("  extra     %d\n", st.extra);
    printf("  missed    %d\n", st.missed);
  }
  printf("\n  saved -> %s\n\n", stats_path());
}

static void usage(FILE *f) {
  fprintf(f,
          "ctype %s — terminal typing test\n"
          "\n"
          "usage: ctype [options]\n"
          "\n"
          "modes:\n"
          "  -w N                   type N words (default: 25)\n"
          "  -t N                   timed, N seconds\n"
          "  -z, --zen              free typing, raw WPM only\n"
          "\n"
          "options:\n"
          "  --words PATH           wordlist file (- for stdin)\n"
          "  --punct                add sentence-style punctuation\n"
          "  --numbers              mix in random numbers (10%%)\n"
          "  --stats                print last 10 results\n"
          "  --graph [N]            WPM trend chart (default last 50)\n"
          "  --reset-stats          delete stats file\n"
          "  -h, --help\n"
          "  -v, --version\n"
          "\n"
          "keys: type chars, space advances, backspace corrects,\n"
          "      Tab restarts, Esc ends, Ctrl-C aborts.\n",
          CTYPE_VERSION);
}

int main(int argc, char **argv) {
  State s = {.mode = MODE_WORDS, .words_target = DEFAULT_WORDS};
  const char *words_arg = nullptr;
  bool mode_set = false;

  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
      usage(stdout);
      return 0;
    }
    if (!strcmp(a, "-v") || !strcmp(a, "--version")) {
      printf("ctype %s\n", CTYPE_VERSION);
      return 0;
    }
    if (!strcmp(a, "--stats"))
      return print_recent_stats(10);
    if (!strcmp(a, "--reset-stats"))
      return reset_stats();
    if (!strcmp(a, "--graph")) {
      int n = 50;
      if (i + 1 < argc) {
        int v = atoi(argv[i + 1]);
        if (v > 0) {
          n = v;
          i++;
        }
      }
      return print_graph(n);
    }
    if (!strcmp(a, "-z") || !strcmp(a, "--zen")) {
      if (mode_set) {
        fprintf(stderr, "ctype: only one mode allowed\n");
        return 2;
      }
      s.mode = MODE_ZEN;
      mode_set = true;
    } else if (!strcmp(a, "-t")) {
      if (mode_set) {
        fprintf(stderr, "ctype: only one mode allowed\n");
        return 2;
      }
      if (++i >= argc) {
        fprintf(stderr, "-t needs value\n");
        return 2;
      }
      s.mode = MODE_TIME;
      s.duration_target = atoi(argv[i]);
      mode_set = true;
      if (s.duration_target <= 0) {
        fprintf(stderr, "-t must be > 0\n");
        return 2;
      }
    } else if (!strcmp(a, "-w")) {
      if (mode_set) {
        fprintf(stderr, "ctype: only one mode allowed\n");
        return 2;
      }
      if (++i >= argc) {
        fprintf(stderr, "-w needs value\n");
        return 2;
      }
      s.mode = MODE_WORDS;
      s.words_target = atoi(argv[i]);
      mode_set = true;
      if (s.words_target <= 0) {
        fprintf(stderr, "-w must be > 0\n");
        return 2;
      }
    } else if (!strcmp(a, "--words")) {
      if (++i >= argc) {
        fprintf(stderr, "--words needs value\n");
        return 2;
      }
      words_arg = argv[i];
    } else if (!strcmp(a, "--punct")) {
      s.punct = true;
    } else if (!strcmp(a, "--numbers")) {
      s.numbers = true;
    } else {
      fprintf(stderr, "ctype: unknown arg: %s\n", a);
      usage(stderr);
      return 2;
    }
  }

  seed_rng();
  if (s.mode != MODE_ZEN)
    load_wordlist(&s, words_arg);
  run_test(&s);
  free_state(&s);
  return 0;
}
