#include "words.h"
#include "term.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

[[nodiscard]] static int rand_range(int n) { return n > 0 ? rand() % n : 0; }

[[nodiscard]] static double rand_double(void) {
  return (double)rand() / ((double)RAND_MAX + 1.0);
}

void gen_number(Word *w) {
  int len = 1 + rand_range(4);
  w->target[0] = (char)('1' + rand_range(9));
  for (int i = 1; i < len; i++) {
    w->target[i] = (char)('0' + rand_range(10));
  }
  w->target[len] = '\0';
  w->target_len = len;
}

typedef struct {
  const char *from;
  const char *const to[4];
  int n;
} Contraction;

static const Contraction CONTRACTIONS[] = {
    {"are", {"aren't"}, 1},
    {"can", {"can't"}, 1},
    {"could", {"couldn't"}, 1},
    {"did", {"didn't"}, 1},
    {"does", {"doesn't"}, 1},
    {"do", {"don't"}, 1},
    {"had", {"hadn't"}, 1},
    {"has", {"hasn't"}, 1},
    {"have", {"haven't"}, 1},
    {"is", {"isn't"}, 1},
    {"it", {"it's", "it'll"}, 2},
    {"i", {"i'm", "i'll", "i've", "i'd"}, 4},
    {"you", {"you'll", "you're", "you've", "you'd"}, 4},
    {"that", {"that's", "that'll", "that'd"}, 3},
    {"must", {"mustn't", "must've"}, 2},
    {"there", {"there's", "there'll", "there'd"}, 3},
    {"he", {"he's", "he'll", "he'd"}, 3},
    {"she", {"she's", "she'll", "she'd"}, 3},
    {"we", {"we're", "we'll", "we'd"}, 3},
    {"they", {"they're", "they'll", "they'd"}, 3},
    {"should", {"shouldn't", "should've"}, 2},
    {"was", {"wasn't"}, 1},
    {"were", {"weren't"}, 1},
    {"will", {"won't"}, 1},
    {"would", {"wouldn't", "would've"}, 2},
    {"going", {"goin'"}, 1},
};

[[nodiscard]] static const Contraction *lookup_contraction(const Word *w) {
  for (size_t i = 0; i < sizeof(CONTRACTIONS) / sizeof(CONTRACTIONS[0]); i++) {
    const Contraction *c = &CONTRACTIONS[i];
    int klen = (int)strlen(c->from);
    if (klen != w->target_len)
      continue;
    bool match = true;
    for (int j = 0; j < klen; j++) {
      char tc = w->target[j];
      if (tc >= 'A' && tc <= 'Z')
        tc = (char)(tc + 32);
      if (tc != c->from[j]) {
        match = false;
        break;
      }
    }
    if (match)
      return c;
  }
  return nullptr;
}

static void apply_contraction(Word *w, const Contraction *c) {
  const char *repl = c->to[rand_range(c->n)];
  int rlen = (int)strlen(repl);
  if (rlen >= MAX_WORD_LEN + 5)
    return;
  memcpy(w->target, repl, (size_t)rlen);
  w->target[rlen] = '\0';
  w->target_len = rlen;
}

static void wrap(Word *w, char open, char close) {
  int len = w->target_len;
  if (len + 2 >= MAX_WORD_LEN + 5)
    return;
  memmove(w->target + 1, w->target, (size_t)len);
  w->target[0] = open;
  w->target[len + 1] = close;
  w->target[len + 2] = '\0';
  w->target_len = len + 2;
}

static void suffix_char(Word *w, char c) {
  int len = w->target_len;
  if (len + 1 >= MAX_WORD_LEN + 5)
    return;
  w->target[len] = c;
  w->target[len + 1] = '\0';
  w->target_len = len + 1;
}

void apply_punct(Word *w, char *last_char) {
  if (w->target_len == 0)
    return;

  bool should_cap = (*last_char == 0 || *last_char == '.' ||
                     *last_char == '?' || *last_char == '!');
  char lc = *last_char;

  if (should_cap) {
    if (w->target[0] >= 'a' && w->target[0] <= 'z')
      w->target[0] = (char)(w->target[0] - 32);
  } else if (rand_double() < 0.10 && lc != '.' && lc != ',') {
    double sub = rand_double();
    if (sub <= 0.8)
      suffix_char(w, '.');
    else if (sub < 0.9)
      suffix_char(w, '?');
    else
      suffix_char(w, '!');
  } else if (rand_double() < 0.01 && lc != ',' && lc != '.') {
    wrap(w, '"', '"');
  } else if (rand_double() < 0.011 && lc != ',' && lc != '.') {
    wrap(w, '\'', '\'');
  } else if (rand_double() < 0.012 && lc != ',' && lc != '.') {
    wrap(w, '(', ')');
  } else if (rand_double() < 0.013 && lc != ',' && lc != '.' && lc != ';' &&
             lc != ':') {
    suffix_char(w, ':');
  } else if (rand_double() < 0.014 && lc != ',' && lc != '.' && lc != '-') {
    w->target[0] = '-';
    w->target[1] = '\0';
    w->target_len = 1;
  } else if (rand_double() < 0.015 && lc != ',' && lc != '.' && lc != ';' &&
             lc != ':') {
    suffix_char(w, ';');
  } else if (rand_double() < 0.2 && lc != ',') {
    suffix_char(w, ',');
  } else if (rand_double() < 0.5) {
    const Contraction *c = lookup_contraction(w);
    if (c)
      apply_contraction(w, c);
  }

  *last_char = w->target[w->target_len - 1];
}

[[nodiscard]] static char *read_all(int fd, size_t *out_size) {
  size_t cap = 4096, len = 0;
  char *buf = malloc(cap);
  if (!buf)
    return nullptr;
  for (;;) {
    if (len + 4096 > cap) {
      cap *= 2;
      if (cap > MAX_WORDLIST_BYTES * 2) {
        free(buf);
        errno = EFBIG;
        return nullptr;
      }
      char *nb = realloc(buf, cap);
      if (!nb) {
        free(buf);
        return nullptr;
      }
      buf = nb;
    }
    ssize_t n = read(fd, buf + len, cap - len);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      free(buf);
      return nullptr;
    }
    if (n == 0)
      break;
    len += (size_t)n;
    if (len > MAX_WORDLIST_BYTES) {
      free(buf);
      errno = EFBIG;
      return nullptr;
    }
  }
  *out_size = len;
  return buf;
}

[[nodiscard]] char **parse_wordlist(char *buf, size_t len, int *out_count) {
  int cap = 256, n = 0;
  char **arr = malloc(sizeof(char *) * (size_t)cap);
  if (!arr)
    return nullptr;

  size_t i = 0;
  while (i < len) {
    while (i < len && (buf[i] == '\n' || buf[i] == '\r' || buf[i] == ' ' ||
                       buf[i] == '\t'))
      i++;
    if (i >= len)
      break;
    size_t start = i;
    while (i < len && buf[i] != '\n' && buf[i] != '\r')
      i++;
    size_t end = i;
    while (i < len && (buf[i] == '\n' || buf[i] == '\r'))
      i++;
    while (end > start && (buf[end - 1] == ' ' || buf[end - 1] == '\t'))
      end--;
    if (end == start || end - start > MAX_WORD_LEN)
      continue;
    bool ok = true;
    for (size_t k = start; k < end; k++) {
      unsigned char c = (unsigned char)buf[k];
      if (c < 0x20 || c >= 0x7f) {
        ok = false;
        break;
      }
    }
    if (!ok)
      continue;
    buf[end] = '\0';
    if (n >= cap) {
      cap *= 2;
      char **na = realloc(arr, sizeof(char *) * (size_t)cap);
      if (!na) {
        free(arr);
        return nullptr;
      }
      arr = na;
    }
    arr[n++] = buf + start;
  }
  *out_count = n;
  return arr;
}

[[nodiscard]] static char *exe_dir(void) {
  static char path[4096];
#if defined(__APPLE__)
  uint32_t sz = sizeof(path);
  if (_NSGetExecutablePath(path, &sz) != 0)
    return nullptr;
#elif defined(__linux__)
  ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
  if (n <= 0)
    return nullptr;
  path[n] = '\0';
#else
  return nullptr;
#endif
  char *slash = strrchr(path, '/');
  if (!slash)
    return nullptr;
  *slash = '\0';
  return path;
}

[[nodiscard]] static bool file_exists(const char *p) {
  struct stat st;
  return stat(p, &st) == 0 && S_ISREG(st.st_mode);
}

[[nodiscard]] static char *resolve_wordlist_path(const char *cli_arg) {
  static char buf[4096];

  if (cli_arg)
    return strdup(cli_arg);

  const char *env = getenv("CTYPE_WORDS");
  if (env && *env)
    return strdup(env);

  const char *xdg = getenv("XDG_DATA_HOME");
  const char *home = getenv("HOME");
  if (xdg && *xdg) {
    snprintf(buf, sizeof(buf), "%s/ctype/words.txt", xdg);
    if (file_exists(buf))
      return strdup(buf);
  } else if (home && *home) {
    snprintf(buf, sizeof(buf), "%s/.local/share/ctype/words.txt", home);
    if (file_exists(buf))
      return strdup(buf);
  }
  if (file_exists("/usr/local/share/ctype/words.txt"))
    return strdup("/usr/local/share/ctype/words.txt");
  if (file_exists("/usr/share/ctype/words.txt"))
    return strdup("/usr/share/ctype/words.txt");

  char *ed = exe_dir();
  if (ed) {
    snprintf(buf, sizeof(buf), "%s/../share/ctype/words.txt", ed);
    if (file_exists(buf))
      return strdup(buf);
  }
  if (file_exists("./assets/words_en.txt"))
    return strdup("./assets/words_en.txt");

  return nullptr;
}

void load_wordlist(State *s, const char *cli_arg) {
  char *path = resolve_wordlist_path(cli_arg);
  if (!path) {
    fprintf(
        stderr,
        "ctype: no wordlist found. Try --words <file>, set CTYPE_WORDS,\n"
        "or run `make install` to put words.txt in $PREFIX/share/ctype/.\n");
    exit(1);
  }

  int fd = strcmp(path, "-") == 0 ? STDIN_FILENO : open(path, O_RDONLY);
  if (fd < 0) {
    int e = errno;
    free(path);
    errno = e;
    die("open wordlist");
  }

  size_t len = 0;
  char *buf = read_all(fd, &len);
  if (fd != STDIN_FILENO)
    close(fd);
  if (!buf) {
    free(path);
    die("read wordlist");
  }

  int n = 0;
  char **arr = parse_wordlist(buf, len, &n);
  if (!arr || n == 0) {
    free(buf);
    free(arr);
    free(path);
    die("wordlist empty");
  }

  s->pool = arr;
  s->pool_count = n;
  s->pool_buf = buf;
  free(path);
}

static void ensure_word_capacity(State *s, int needed) {
  if (s->word_cap >= needed)
    return;
  int cap = s->word_cap ? s->word_cap : 32;
  while (cap < needed)
    cap *= 2;
  Word *nw = realloc(s->words, sizeof(Word) * (size_t)cap);
  if (!nw)
    die("oom");
  s->words = nw;
  s->word_cap = cap;
}

void append_sampled(State *s, int n) {
  ensure_word_capacity(s, s->word_count + n);
  for (int i = 0; i < n; i++) {
    Word *w = &s->words[s->word_count + i];
    *w = (Word){};
    if (s->numbers && rand_double() < 0.10) {
      gen_number(w);
    } else {
      const char *t = s->pool[rand_range(s->pool_count)];
      int tl = (int)strlen(t);
      if (tl > MAX_WORD_LEN)
        tl = MAX_WORD_LEN;
      memcpy(w->target, t, (size_t)tl);
      w->target[tl] = '\0';
      w->target_len = tl;
    }
    if (s->punct)
      apply_punct(w, &s->last_char);
  }
  s->word_count += n;
}

void seed_words(State *s) {
  if (s->mode == MODE_ZEN)
    return;
  append_sampled(s, s->mode == MODE_WORDS ? s->words_target : INITIAL_SAMPLES);
}

static void compact_words(State *s) {
  if (s->cur_word < 64)
    return;
  for (int i = 0; i < s->cur_word; i++) {
    const Word *w = &s->words[i];
    int cmp_len = w->typed_len < w->target_len ? w->typed_len : w->target_len;
    for (int j = 0; j < cmp_len; j++) {
      if (w->typed[j] == w->target[j])
        s->acc_correct++;
      else
        s->acc_wrong++;
    }
    if (w->typed_len > w->target_len)
      s->acc_extra += w->typed_len - w->target_len;
    if (w->finalized && w->typed_len < w->target_len)
      s->acc_missed += w->target_len - w->typed_len;
  }
  int remaining = s->word_count - s->cur_word;
  memmove(s->words, s->words + s->cur_word, sizeof(Word) * (size_t)remaining);
  s->word_count = remaining;
  s->cur_word = 0;
  s->last_drawn_cur = -1;
}

void maybe_refill(State *s) {
  if (s->mode == MODE_WORDS || s->mode == MODE_ZEN)
    return;
  if (s->word_count - s->cur_word < REFILL_THRESHOLD) {
    compact_words(s);
    append_sampled(s, INITIAL_SAMPLES);
  }
}
