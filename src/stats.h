#pragma once

#include "types.h"

double elapsed_seconds(const State *s);
Stats compute_stats(const State *s);

char *stats_path(void);
void append_stats(const State *s, const Stats *st);
int print_recent_stats(int n);
int reset_stats(void);
int print_graph(int n);
