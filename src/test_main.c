#include "input.h"
#include "stats.h"
#include "types.h"
#include "words.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_pass = 0;
static int g_fail = 0;

#define ASSERT(expr)                                                           \
  do {                                                                         \
    if (expr) {                                                                \
      g_pass++;                                                                \
    } else {                                                                   \
      g_fail++;                                                                \
      fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr);        \
    }                                                                          \
  } while (0)

#define ASSERT_INT_EQ(a, b)                                                    \
  do {                                                                         \
    int _a = (a), _b = (b);                                                    \
    if (_a == _b) {                                                            \
      g_pass++;                                                                \
    } else {                                                                   \
      g_fail++;                                                                \
      fprintf(stderr, "  FAIL %s:%d: %s == %d, expected %d\n", __FILE__,       \
              __LINE__, #a, _a, _b);                                           \
    }                                                                          \
  } while (0)

#define ASSERT_DBL_NEAR(a, b, eps)                                             \
  do {                                                                         \
    double _a = (a), _b = (b);                                                 \
    if (fabs(_a - _b) <= (eps)) {                                              \
      g_pass++;                                                                \
    } else {                                                                   \
      g_fail++;                                                                \
      fprintf(stderr, "  FAIL %s:%d: %s == %.6f, expected %.6f (±%g)\n",       \
              __FILE__, __LINE__, #a, _a, _b, (eps));                          \
    }                                                                          \
  } while (0)

#define RUN(fn)                                                                \
  do {                                                                         \
    int _before = g_fail;                                                      \
    printf("  %s ... ", #fn);                                                  \
    fn();                                                                      \
    printf("%s\n", g_fail == _before ? "ok" : "FAILED");                       \
  } while (0)

static void set_word(Word *w, const char *target) {
  int len = (int)strlen(target);
  memcpy(w->target, target, (size_t)len + 1);
  w->target_len = len;
  w->typed_len = 0;
  w->typed[0] = '\0';
  w->finalized = false;
}

static void type_word(State *s, const char *text) {
  for (int i = 0; text[i]; i++)
    on_char(s, text[i]);
}

static State make_state(int n_words, const char **targets) {
  State s = {.mode = MODE_WORDS, .words_target = n_words};
  s.words = calloc((size_t)n_words, sizeof(Word));
  s.word_count = n_words;
  s.word_cap = n_words;
  for (int i = 0; i < n_words; i++)
    set_word(&s.words[i], targets[i]);
  s.started = true;
  clock_gettime(CLOCK_MONOTONIC, &s.start_ts);
  return s;
}

static void free_test_state(State *s) {
  free(s->words);
  *s = (State){};
}

static void test_word_imperfect_perfect(void) {
  Word w = {};
  set_word(&w, "hello");
  memcpy(w.typed, "hello", 5);
  w.typed_len = 5;
  ASSERT(!word_imperfect(&w));
}

static void test_word_imperfect_wrong_char(void) {
  Word w = {};
  set_word(&w, "hello");
  memcpy(w.typed, "hallo", 5);
  w.typed_len = 5;
  ASSERT(word_imperfect(&w));
}

static void test_word_imperfect_too_short(void) {
  Word w = {};
  set_word(&w, "hello");
  memcpy(w.typed, "hel", 3);
  w.typed_len = 3;
  ASSERT(word_imperfect(&w));
}

static void test_word_imperfect_too_long(void) {
  Word w = {};
  set_word(&w, "hi");
  memcpy(w.typed, "his", 3);
  w.typed_len = 3;
  ASSERT(word_imperfect(&w));
}

static void test_on_char_correct(void) {
  const char *words[] = {"abc"};
  State s = make_state(1, words);
  on_char(&s, 'a');
  ASSERT_INT_EQ(s.words[0].typed_len, 1);
  ASSERT_INT_EQ(s.correct_keys, 1);
  ASSERT_INT_EQ(s.incorrect_keys, 0);
  free_test_state(&s);
}

static void test_on_char_wrong(void) {
  const char *words[] = {"abc"};
  State s = make_state(1, words);
  on_char(&s, 'x');
  ASSERT_INT_EQ(s.words[0].typed_len, 1);
  ASSERT_INT_EQ(s.correct_keys, 0);
  ASSERT_INT_EQ(s.incorrect_keys, 1);
  free_test_state(&s);
}

static void test_on_char_space_correct_word(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hi");
  on_char(&s, ' ');
  ASSERT_INT_EQ(s.cur_word, 1);
  ASSERT_INT_EQ(s.correct_word_count, 1);
  ASSERT_INT_EQ(s.correct_word_chars, 2);
  ASSERT_INT_EQ(s.total_spaces, 1);
  ASSERT(s.words[0].finalized);
  free_test_state(&s);
}

static void test_on_char_space_wrong_word(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hx");
  on_char(&s, ' ');
  ASSERT_INT_EQ(s.cur_word, 1);
  ASSERT_INT_EQ(s.correct_word_count, 0);
  ASSERT_INT_EQ(s.correct_word_chars, 0);
  ASSERT_INT_EQ(s.total_spaces, 1);
  ASSERT_INT_EQ(s.incorrect_keys, 2);
  free_test_state(&s);
}

static void test_on_char_space_empty_word(void) {
  const char *words[] = {"hi"};
  State s = make_state(1, words);
  on_char(&s, ' ');
  ASSERT_INT_EQ(s.cur_word, 0);
  ASSERT_INT_EQ(s.total_spaces, 0);
  free_test_state(&s);
}

static void test_on_char_auto_end(void) {
  const char *words[] = {"ab", "cd"};
  State s = make_state(2, words);
  s.words_target = 2;
  type_word(&s, "ab");
  on_char(&s, ' ');
  type_word(&s, "cd");
  ASSERT_INT_EQ(s.cur_word, 2);
  ASSERT(s.words[1].finalized);
  ASSERT_INT_EQ(s.correct_word_chars, 4);
  ASSERT_INT_EQ(s.total_spaces, 1);
  ASSERT_INT_EQ(s.correct_word_count, 1);
  free_test_state(&s);
}

static void test_on_char_auto_end_wrong_no_trigger(void) {
  const char *words[] = {"ab", "cd"};
  State s = make_state(2, words);
  s.words_target = 2;
  type_word(&s, "ab");
  on_char(&s, ' ');
  type_word(&s, "cx");
  ASSERT_INT_EQ(s.cur_word, 1);
  ASSERT(!s.words[1].finalized);
  free_test_state(&s);
}

static void test_on_char_no_auto_end_time_mode(void) {
  const char *words[] = {"ab"};
  State s = make_state(1, words);
  s.mode = MODE_TIME;
  s.words_target = 1;
  type_word(&s, "ab");
  ASSERT_INT_EQ(s.cur_word, 0);
  ASSERT(!s.words[0].finalized);
  free_test_state(&s);
}

static void test_on_backspace_delete_char(void) {
  const char *words[] = {"abc"};
  State s = make_state(1, words);
  type_word(&s, "ab");
  on_backspace(&s);
  ASSERT_INT_EQ(s.words[0].typed_len, 1);
  ASSERT(s.words[0].typed[0] == 'a');
  free_test_state(&s);
}

static void test_on_backspace_go_back_imperfect(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hx");
  on_char(&s, ' ');
  ASSERT_INT_EQ(s.cur_word, 1);
  on_backspace(&s);
  ASSERT_INT_EQ(s.cur_word, 0);
  ASSERT(!s.words[0].finalized);
  ASSERT_INT_EQ(s.total_spaces, 0);
  free_test_state(&s);
}

static void test_on_backspace_cant_go_back_perfect(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hi");
  on_char(&s, ' ');
  ASSERT_INT_EQ(s.cur_word, 1);
  on_backspace(&s);
  ASSERT_INT_EQ(s.cur_word, 1);
  free_test_state(&s);
}

static void test_on_backspace_at_start(void) {
  const char *words[] = {"hi"};
  State s = make_state(1, words);
  on_backspace(&s);
  ASSERT_INT_EQ(s.cur_word, 0);
  ASSERT_INT_EQ(s.words[0].typed_len, 0);
  free_test_state(&s);
}

static void test_zen_char_counting(void) {
  State s = {.mode = MODE_ZEN};
  on_char_zen(&s, 'h');
  on_char_zen(&s, 'i');
  ASSERT_INT_EQ(s.zen_total_chars, 2);
  ASSERT_INT_EQ(s.zen_total_words, 0);
  ASSERT_INT_EQ(s.zen_line_len, 2);
  ASSERT(s.started);
}

static void test_zen_space_counts_word(void) {
  State s = {.mode = MODE_ZEN};
  on_char_zen(&s, 'h');
  on_char_zen(&s, 'i');
  on_char_zen(&s, ' ');
  ASSERT_INT_EQ(s.zen_total_chars, 3);
  ASSERT_INT_EQ(s.zen_total_words, 1);
}

static void test_zen_leading_space_no_word(void) {
  State s = {.mode = MODE_ZEN};
  on_char_zen(&s, ' ');
  ASSERT_INT_EQ(s.zen_total_chars, 1);
  ASSERT_INT_EQ(s.zen_total_words, 0);
}

static void test_zen_backspace_char(void) {
  State s = {.mode = MODE_ZEN};
  on_char_zen(&s, 'h');
  on_char_zen(&s, 'i');
  on_backspace_zen(&s);
  ASSERT_INT_EQ(s.zen_total_chars, 1);
  ASSERT_INT_EQ(s.zen_line_len, 1);
}

static void test_zen_backspace_space_decrements_word(void) {
  State s = {.mode = MODE_ZEN};
  on_char_zen(&s, 'h');
  on_char_zen(&s, 'i');
  on_char_zen(&s, ' ');
  ASSERT_INT_EQ(s.zen_total_words, 1);
  on_backspace_zen(&s);
  ASSERT_INT_EQ(s.zen_total_words, 0);
  ASSERT_INT_EQ(s.zen_total_chars, 2);
}

static void test_zen_backspace_empty(void) {
  State s = {.mode = MODE_ZEN};
  on_backspace_zen(&s);
  ASSERT_INT_EQ(s.zen_total_chars, 0);
  ASSERT_INT_EQ(s.zen_line_len, 0);
}

static void test_stats_perfect_words(void) {
  const char *words[] = {"hello", "world"};
  State s = make_state(2, words);
  type_word(&s, "hello");
  on_char(&s, ' ');
  type_word(&s, "world");
  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, 2.2, 0.01);
  ASSERT_DBL_NEAR(st.raw, 2.2, 0.01);
  ASSERT_DBL_NEAR(st.acc, 1.0, 0.001);
  ASSERT_INT_EQ(st.correct, 10);
  ASSERT_INT_EQ(st.wrong, 0);
  free_test_state(&s);
}

static void test_stats_with_wrong_word(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hi");
  on_char(&s, ' ');
  type_word(&s, "gx");
  on_char(&s, ' ');

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, 0.6, 0.01);
  ASSERT_DBL_NEAR(st.raw, 1.2, 0.01);
  ASSERT_INT_EQ(st.correct, 3);
  ASSERT_INT_EQ(st.wrong, 1);
  free_test_state(&s);
}

static void test_stats_auto_end_no_space_credit(void) {
  const char *words[] = {"ab", "cd"};
  State s = make_state(2, words);
  s.words_target = 2;
  type_word(&s, "ab");
  on_char(&s, ' ');
  type_word(&s, "cd");

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, 1.0, 0.01);
  ASSERT_DBL_NEAR(st.raw, 1.0, 0.01);
  free_test_state(&s);
}

static void test_stats_wpm_equals_raw_at_perfect_accuracy(void) {
  const char *words[] = {"test", "word", "here"};
  State s = make_state(3, words);
  type_word(&s, "test");
  on_char(&s, ' ');
  type_word(&s, "word");
  on_char(&s, ' ');
  type_word(&s, "here");

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, st.raw, 0.01);
  free_test_state(&s);
}

static void test_stats_partial_credit(void) {
  const char *words[] = {"hello", "world"};
  State s = make_state(2, words);
  type_word(&s, "hello");
  on_char(&s, ' ');
  type_word(&s, "wor");

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, 1.8, 0.01);
  free_test_state(&s);
}

static void test_stats_no_partial_credit_if_wrong(void) {
  const char *words[] = {"hello", "world"};
  State s = make_state(2, words);
  type_word(&s, "hello");
  on_char(&s, ' ');
  type_word(&s, "wox");

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.wpm, 1.2, 0.01);
  free_test_state(&s);
}

static void test_stats_accuracy(void) {
  const char *words[] = {"abcd"};
  State s = make_state(1, words);
  on_char(&s, 'a');
  on_char(&s, 'b');
  on_char(&s, 'x');
  on_char(&s, 'd');

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.acc, 0.75, 0.001);
  free_test_state(&s);
}

static void test_stats_extra_chars(void) {
  const char *words[] = {"hi", "go"};
  State s = make_state(2, words);
  type_word(&s, "hixx");
  on_char(&s, ' ');

  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_INT_EQ(st.extra, 2);
  ASSERT_INT_EQ(st.wrong, 0);
  free_test_state(&s);
}

static void test_stats_zen(void) {
  State s = {.mode = MODE_ZEN, .started = true};
  clock_gettime(CLOCK_MONOTONIC, &s.start_ts);
  s.zen_total_chars = 50;
  s.end_ts = s.start_ts;
  s.end_ts.tv_sec += 60;

  Stats st = compute_stats(&s);
  ASSERT_DBL_NEAR(st.raw, 10.0, 0.01);
  ASSERT_DBL_NEAR(st.wpm, 0.0, 0.01);
}

static void test_gen_number_no_leading_zero(void) {
  srand(42);
  for (int i = 0; i < 500; i++) {
    Word w = {};
    gen_number(&w);
    ASSERT(w.target[0] >= '1' && w.target[0] <= '9');
    ASSERT(w.target_len >= 1 && w.target_len <= 4);
    for (int j = 0; j < w.target_len; j++)
      ASSERT(w.target[j] >= '0' && w.target[j] <= '9');
    ASSERT(w.target[w.target_len] == '\0');
  }
}

static void test_parse_wordlist_basic(void) {
  char buf[] = "hello\nworld\nfoo\n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 3);
  if (count >= 3) {
    ASSERT(!strcmp(arr[0], "hello"));
    ASSERT(!strcmp(arr[1], "world"));
    ASSERT(!strcmp(arr[2], "foo"));
  }
  free(arr);
}

static void test_parse_wordlist_skip_long(void) {
  char buf[] = "hi\nabcdefghijklmnopqrstuvwxyz12345\nok\n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 2);
  if (count >= 2) {
    ASSERT(!strcmp(arr[0], "hi"));
    ASSERT(!strcmp(arr[1], "ok"));
  }
  free(arr);
}

static void test_parse_wordlist_skip_nonascii(void) {
  char buf[] = "good\nbad\x80word\nfine\n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 2);
  if (count >= 2) {
    ASSERT(!strcmp(arr[0], "good"));
    ASSERT(!strcmp(arr[1], "fine"));
  }
  free(arr);
}

static void test_parse_wordlist_trim_whitespace(void) {
  char buf[] = "  hello  \n  world  \n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 2);
  if (count >= 2) {
    ASSERT(!strcmp(arr[0], "hello"));
    ASSERT(!strcmp(arr[1], "world"));
  }
  free(arr);
}

static void test_parse_wordlist_empty(void) {
  char buf[] = "\n\n\n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 0);
  free(arr);
}

static void test_parse_wordlist_crlf(void) {
  char buf[] = "one\r\ntwo\r\n";
  int count = 0;
  char **arr = parse_wordlist(buf, strlen(buf), &count);
  ASSERT(arr != nullptr);
  ASSERT_INT_EQ(count, 2);
  if (count >= 2) {
    ASSERT(!strcmp(arr[0], "one"));
    ASSERT(!strcmp(arr[1], "two"));
  }
  free(arr);
}

static void test_punct_capitalize_first(void) {
  srand(999999);
  Word w = {};
  set_word(&w, "hello");
  char lc = 0;
  apply_punct(&w, &lc);
  ASSERT(w.target[0] == 'H');
}

static void test_punct_capitalize_after_period(void) {
  srand(999999);
  Word w = {};
  set_word(&w, "world");
  char lc = '.';
  apply_punct(&w, &lc);
  ASSERT(w.target[0] == 'W');
}

int main(void) {
  printf("word_imperfect:\n");
  RUN(test_word_imperfect_perfect);
  RUN(test_word_imperfect_wrong_char);
  RUN(test_word_imperfect_too_short);
  RUN(test_word_imperfect_too_long);

  printf("on_char:\n");
  RUN(test_on_char_correct);
  RUN(test_on_char_wrong);
  RUN(test_on_char_space_correct_word);
  RUN(test_on_char_space_wrong_word);
  RUN(test_on_char_space_empty_word);
  RUN(test_on_char_auto_end);
  RUN(test_on_char_auto_end_wrong_no_trigger);
  RUN(test_on_char_no_auto_end_time_mode);

  printf("on_backspace:\n");
  RUN(test_on_backspace_delete_char);
  RUN(test_on_backspace_go_back_imperfect);
  RUN(test_on_backspace_cant_go_back_perfect);
  RUN(test_on_backspace_at_start);

  printf("zen mode:\n");
  RUN(test_zen_char_counting);
  RUN(test_zen_space_counts_word);
  RUN(test_zen_leading_space_no_word);
  RUN(test_zen_backspace_char);
  RUN(test_zen_backspace_space_decrements_word);
  RUN(test_zen_backspace_empty);

  printf("compute_stats:\n");
  RUN(test_stats_perfect_words);
  RUN(test_stats_with_wrong_word);
  RUN(test_stats_auto_end_no_space_credit);
  RUN(test_stats_wpm_equals_raw_at_perfect_accuracy);
  RUN(test_stats_partial_credit);
  RUN(test_stats_no_partial_credit_if_wrong);
  RUN(test_stats_accuracy);
  RUN(test_stats_extra_chars);
  RUN(test_stats_zen);

  printf("gen_number:\n");
  RUN(test_gen_number_no_leading_zero);

  printf("parse_wordlist:\n");
  RUN(test_parse_wordlist_basic);
  RUN(test_parse_wordlist_skip_long);
  RUN(test_parse_wordlist_skip_nonascii);
  RUN(test_parse_wordlist_trim_whitespace);
  RUN(test_parse_wordlist_empty);
  RUN(test_parse_wordlist_crlf);

  printf("apply_punct:\n");
  RUN(test_punct_capitalize_first);
  RUN(test_punct_capitalize_after_period);

  printf("\n%d passed, %d failed\n", g_pass, g_fail);
  return g_fail > 0 ? 1 : 0;
}
