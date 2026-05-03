#pragma once

#include "types.h"

void on_char(State *s, char c);
void on_backspace(State *s);
void on_char_zen(State *s, char c);
void on_backspace_zen(State *s);
[[nodiscard]] bool word_imperfect(const Word *w);
