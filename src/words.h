#pragma once

#include "types.h"

void load_wordlist(State *s, const char *cli_arg);
void seed_words(State *s);
void append_sampled(State *s, int n);
void maybe_refill(State *s);

void gen_number(Word *w);
void apply_punct(Word *w, char *last_char);
[[nodiscard]] char **parse_wordlist(char *buf, size_t len, int *out_count);
