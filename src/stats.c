#include "stats.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

double elapsed_seconds(const State *s) {
  if (!s->started)
    return 0.0;
  struct timespec now;
  if (s->end_ts.tv_sec)
    now = s->end_ts;
  else
    clock_gettime(CLOCK_MONOTONIC, &now);
  double d = (double)(now.tv_sec - s->start_ts.tv_sec) +
             (double)(now.tv_nsec - s->start_ts.tv_nsec) / 1e9;
  return d < 0.001 ? 0.001 : d;
}

Stats compute_stats(const State *s) {
  Stats st = {};
  st.seconds = elapsed_seconds(s);
  double mins = st.seconds / 60.0;
  if (mins < 1e-6)
    mins = 1e-6;

  if (s->mode == MODE_ZEN) {
    st.raw = ((double)s->zen_total_chars / 5.0) / mins;
    return st;
  }

  st.correct = s->acc_correct;
  st.wrong = s->acc_wrong;
  st.extra = s->acc_extra;
  st.missed = s->acc_missed;
  int upto = s->cur_word < s->word_count ? s->cur_word + 1 : s->cur_word;
  for (int i = 0; i < upto && i < s->word_count; i++) {
    const Word *w = &s->words[i];
    int cmp_len = w->typed_len < w->target_len ? w->typed_len : w->target_len;
    for (int j = 0; j < cmp_len; j++) {
      if (w->typed[j] == w->target[j])
        st.correct++;
      else
        st.wrong++;
    }
    if (w->typed_len > w->target_len)
      st.extra += w->typed_len - w->target_len;
    if (w->finalized && w->typed_len < w->target_len)
      st.missed += w->target_len - w->typed_len;
  }
  st.total_typed = st.correct + st.wrong + st.extra;
  int wpm_chars = s->correct_word_chars;
  int wpm_count = s->correct_word_count;
  if (s->cur_word < s->word_count) {
    const Word *w = &s->words[s->cur_word];
    if (w->typed_len > 0 && w->typed_len <= w->target_len) {
      bool match = true;
      for (int i = 0; i < w->typed_len; i++)
        if (w->typed[i] != w->target[i]) {
          match = false;
          break;
        }
      if (match)
        wpm_chars += w->typed_len;
    }
  }
  st.wpm = ((double)(wpm_chars + wpm_count) / 5.0) / mins;
  st.raw = ((double)(st.total_typed + s->total_spaces) / 5.0) / mins;
  int keys = s->correct_keys + s->incorrect_keys;
  st.acc = keys > 0 ? (double)s->correct_keys / (double)keys : 0.0;
  return st;
}

static int mkdir_p(const char *path) {
  char buf[4096];
  size_t len = strlen(path);
  if (len >= sizeof(buf))
    return -1;
  memcpy(buf, path, len + 1);
  for (size_t i = 1; i < len; i++) {
    if (buf[i] == '/') {
      buf[i] = '\0';
      if (mkdir(buf, 0755) != 0 && errno != EEXIST)
        return -1;
      buf[i] = '/';
    }
  }
  if (mkdir(buf, 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

char *stats_path(void) {
  static char buf[4096];
  const char *xdg = getenv("XDG_DATA_HOME");
  const char *home = getenv("HOME");
  if (xdg && *xdg)
    snprintf(buf, sizeof(buf), "%s/ctype", xdg);
  else if (home && *home)
    snprintf(buf, sizeof(buf), "%s/.local/share/ctype", home);
  else
    return nullptr;
  if (mkdir_p(buf) != 0)
    return nullptr;
  size_t l = strlen(buf);
  snprintf(buf + l, sizeof(buf) - l, "/stats.jsonl");
  return buf;
}

void append_stats(const State *s, const Stats *st) {
  char *p = stats_path();
  if (!p)
    return;
  FILE *f = fopen(p, "a");
  if (!f)
    return;
  const char *mode_s = s->mode == MODE_TIME ? "time"
                       : s->mode == MODE_ZEN  ? "zen"
                                              : "words";
  int target = s->mode == MODE_TIME    ? s->duration_target
               : s->mode == MODE_WORDS ? s->words_target
                                       : 0;
  fprintf(f,
          "{\"ts\":%lld,\"mode\":\"%s\",\"duration\":%.2f,\"target\":%d,"
          "\"wpm\":%.2f,\"raw\":%.2f,\"acc\":%.4f,"
          "\"correct\":%d,\"wrong\":%d,\"extra\":%d,\"missed\":%d}\n",
          (long long)time(nullptr), mode_s, st->seconds, target, st->wpm,
          st->raw, st->acc, st->correct, st->wrong, st->extra, st->missed);
  fclose(f);
}

int print_recent_stats(int n) {
  char *p = stats_path();
  if (!p) {
    fprintf(stderr, "no $HOME/$XDG_DATA_HOME\n");
    return 1;
  }
  FILE *f = fopen(p, "r");
  if (!f) {
    printf("no stats yet (%s)\n", p);
    return 0;
  }

  char *lines[256];
  int count = 0;
  char buf[2048];
  while (fgets(buf, sizeof(buf), f)) {
    if (count == 256) {
      free(lines[0]);
      memmove(lines, lines + 1, sizeof(char *) * 255);
      count = 255;
    }
    lines[count++] = strdup(buf);
  }
  fclose(f);

  int start = count - n;
  if (start < 0)
    start = 0;
  printf("%-12s %-7s %5s %5s %5s\n", "ts", "mode", "wpm", "raw", "acc");
  for (int i = 0; i < count; i++) {
    if (i >= start) {
      long long ts = 0;
      char mode[16] = {};
      double wpm = 0, raw = 0, acc = 0;
      sscanf(lines[i], "{\"ts\":%lld,\"mode\":\"%15[^\"]\"", &ts, mode);
      char *p2;
      if ((p2 = strstr(lines[i], "\"wpm\":")))
        sscanf(p2, "\"wpm\":%lf", &wpm);
      if ((p2 = strstr(lines[i], "\"raw\":")))
        sscanf(p2, "\"raw\":%lf", &raw);
      if ((p2 = strstr(lines[i], "\"acc\":")))
        sscanf(p2, "\"acc\":%lf", &acc);
      printf("%-12lld %-7s %5.1f %5.1f %4.1f%%\n", ts, mode, wpm, raw,
             acc * 100.0);
    }
    free(lines[i]);
  }
  return 0;
}

int reset_stats(void) {
  char *p = stats_path();
  if (!p)
    return 1;
  if (unlink(p) == 0) {
    printf("removed %s\n", p);
    return 0;
  }
  if (errno == ENOENT) {
    printf("no stats file\n");
    return 0;
  }
  perror("unlink");
  return 1;
}

int print_graph(int n) {
  char *p = stats_path();
  if (!p) {
    fprintf(stderr, "no $HOME/$XDG_DATA_HOME\n");
    return 1;
  }
  FILE *f = fopen(p, "r");
  if (!f) {
    printf("no stats yet (%s)\n", p);
    return 0;
  }

  if (n < 1)
    n = 50;
  if (n > 512)
    n = 512;

  double wpms[512];
  int count = 0;
  char buf[2048];
  while (fgets(buf, sizeof(buf), f)) {
    char *p2 = strstr(buf, "\"wpm\":");
    if (!p2)
      continue;
    double w = 0;
    if (sscanf(p2, "\"wpm\":%lf", &w) != 1)
      continue;
    if (count < n) {
      wpms[count++] = w;
    } else {
      memmove(wpms, wpms + 1, sizeof(double) * (size_t)(n - 1));
      wpms[n - 1] = w;
    }
  }
  fclose(f);

  if (count == 0) {
    printf("no completed sessions yet\n");
    return 0;
  }

  double mn = wpms[0], mx = wpms[0], sum = 0;
  for (int i = 0; i < count; i++) {
    if (wpms[i] < mn)
      mn = wpms[i];
    if (wpms[i] > mx)
      mx = wpms[i];
    sum += wpms[i];
  }
  double avg = sum / count;
  double last = wpms[count - 1];

  constexpr int H = 8;
  static const char *BLOCKS[9] = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"};
  double range = mx - mn;
  if (range < 1.0)
    range = 1.0;

  printf("WPM trend (last %d, file: %s)\n\n", count, p);
  for (int r = H - 1; r >= 0; r--) {
    double row_top = mn + range * (double)(r + 1) / H;
    double row_bot = mn + range * (double)r / H;
    if (r == H - 1)
      printf("%5.0f ┤", mx);
    else if (r == 0)
      printf("%5.0f ┤", mn);
    else if (r == H / 2)
      printf("%5.0f ┤", mn + range / 2);
    else
      printf("      │");
    for (int i = 0; i < count; i++) {
      double w = wpms[i];
      int level;
      if (w >= row_top)
        level = 8;
      else if (w <= row_bot)
        level = 0;
      else {
        level = (int)(((w - row_bot) / (row_top - row_bot)) * 8.0 + 0.5);
        if (level > 8)
          level = 8;
      }
      fputs(BLOCKS[level], stdout);
    }
    putchar('\n');
  }
  printf("      └");
  for (int i = 0; i < count; i++)
    putchar('-');
  putchar('\n');

  printf("\n  min %.1f   avg %.1f   max %.1f   last %.1f\n\n", mn, avg, mx,
         last);
  return 0;
}
