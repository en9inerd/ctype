#include "term.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static const char ENTER_SEQ[] = ALT_ON CURSOR_STEADY HIDE HOME CLEAR;
static const char LEAVE_SEQ[] = SHOW CURSOR_DEFAULT ALT_OFF;

static struct termios g_orig_termios;
static bool g_raw_active = false;
volatile sig_atomic_t g_resize_flag = 0;
volatile sig_atomic_t g_die_flag = 0;

[[noreturn]] void die(const char *msg) {
  disable_raw_mode();
  fprintf(stderr, "ctype: %s", msg);
  if (errno)
    fprintf(stderr, ": %s", strerror(errno));
  fputc('\n', stderr);
  exit(1);
}

void disable_raw_mode(void) {
  if (g_raw_active) {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
    [[maybe_unused]] ssize_t r =
        write(STDOUT_FILENO, LEAVE_SEQ, sizeof(LEAVE_SEQ) - 1);
    g_raw_active = false;
  }
}

void enable_raw_mode(void) {
  if (!isatty(STDIN_FILENO))
    die("stdin is not a tty");
  if (tcgetattr(STDIN_FILENO, &g_orig_termios) == -1)
    die("tcgetattr");
  atexit(disable_raw_mode);

  struct termios raw = g_orig_termios;
  raw.c_lflag &= ~((tcflag_t)(ECHO | ICANON | IEXTEN));
  raw.c_iflag &= ~((tcflag_t)(IXON | ICRNL | BRKINT | INPCK | ISTRIP));
  raw.c_oflag &= ~((tcflag_t)OPOST);
  raw.c_cc[VMIN] = 0;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1)
    die("tcsetattr");

  [[maybe_unused]] ssize_t r =
      write(STDOUT_FILENO, ENTER_SEQ, sizeof(ENTER_SEQ) - 1);
  g_raw_active = true;
}

static void on_winch([[maybe_unused]] int sig) { g_resize_flag = 1; }
static void on_die_signal([[maybe_unused]] int sig) { g_die_flag = 1; }

static void on_crash(int sig) {
  disable_raw_mode();
  struct sigaction sa = {.sa_handler = SIG_DFL};
  sigaction(sig, &sa, nullptr);
  raise(sig);
}

void install_signals(void) {
  struct sigaction sa = {};
  sa.sa_handler = on_winch;
  sigaction(SIGWINCH, &sa, nullptr);

  sa.sa_handler = on_die_signal;
  sigaction(SIGTERM, &sa, nullptr);
  sigaction(SIGHUP, &sa, nullptr);
  sigaction(SIGINT, &sa, nullptr);

  sa.sa_handler = on_crash;
  sa.sa_flags = SA_RESETHAND | SA_NODEFER;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
  sigaction(SIGFPE, &sa, nullptr);
  sigaction(SIGILL, &sa, nullptr);
  sigaction(SIGABRT, &sa, nullptr);
}

void query_size(State *s) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0) {
    s->cols = 80;
    s->rows = 24;
  } else {
    s->cols = ws.ws_col;
    s->rows = ws.ws_row;
  }
}

void fb_reserve(Frame *f, size_t need) {
  if (f->cap - f->len >= need)
    return;
  size_t cap = f->cap ? f->cap : 4096;
  while (cap - f->len < need)
    cap *= 2;
  char *p = realloc(f->data, cap);
  if (!p)
    die("oom");
  f->data = p;
  f->cap = cap;
}

void fb_reset(Frame *f) { f->len = 0; }

void fb_append(Frame *f, const char *s, size_t n) {
  fb_reserve(f, n);
  memcpy(f->data + f->len, s, n);
  f->len += n;
}

void fb_appendz(Frame *f, const char *s) { fb_append(f, s, strlen(s)); }

void fb_appendf(Frame *f, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  va_list aq;
  va_copy(aq, ap);
  int n = vsnprintf(nullptr, 0, fmt, aq);
  va_end(aq);
  if (n < 0) {
    va_end(ap);
    return;
  }
  fb_reserve(f, (size_t)n + 1);
  vsnprintf(f->data + f->len, f->cap - f->len, fmt, ap);
  f->len += (size_t)n;
  va_end(ap);
}

void fb_flush(Frame *f) {
  size_t off = 0;
  while (off < f->len) {
    ssize_t w = write(STDOUT_FILENO, f->data + off, f->len - off);
    if (w < 0) {
      if (errno == EINTR)
        continue;
      break;
    }
    off += (size_t)w;
  }
}
