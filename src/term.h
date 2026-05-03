#pragma once

#include "types.h"
#include <signal.h>
#include <stdarg.h>

#define SYNC_BEGIN "\x1b[?2026h"
#define SYNC_END "\x1b[?2026l"
#define ALT_ON "\x1b[?1049h"
#define ALT_OFF "\x1b[?1049l"
#define HIDE "\x1b[?25l"
#define SHOW "\x1b[?25h"
#define CURSOR_STEADY "\x1b[2 q"
#define CURSOR_DEFAULT "\x1b[0 q"
#define HOME "\x1b[H"
#define CLEAR "\x1b[2J"
#define RESET "\x1b[0m"
#define EOL "\x1b[K"

extern volatile sig_atomic_t g_resize_flag;
extern volatile sig_atomic_t g_die_flag;

[[noreturn]] void die(const char *msg);

void enable_raw_mode(void);
void disable_raw_mode(void);
void install_signals(void);
void query_size(State *s);

void fb_reserve(Frame *f, size_t need);
void fb_reset(Frame *f);
void fb_append(Frame *f, const char *s, size_t n);
void fb_appendz(Frame *f, const char *s);
[[gnu::format(printf, 2, 3)]]
void fb_appendf(Frame *f, const char *fmt, ...);
void fb_flush(Frame *f);

[[maybe_unused]] static inline void fb_byte(Frame *f, char c) {
  fb_reserve(f, 1);
  f->data[f->len++] = c;
}
