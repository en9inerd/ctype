package ctype

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:sys/posix"

SYNC_BEGIN     : string : "\x1b[?2026h"
SYNC_END       : string : "\x1b[?2026l"
ALT_ON         : string : "\x1b[?1049h"
ALT_OFF        : string : "\x1b[?1049l"
HIDE           : string : "\x1b[?25l"
SHOW           : string : "\x1b[?25h"
CURSOR_STEADY  : string : "\x1b[2 q"
CURSOR_DEFAULT : string : "\x1b[0 q"
HOME           : string : "\x1b[H"
CLEAR          : string : "\x1b[2J"
RESET          : string : "\x1b[0m"
EOL            : string : "\x1b[K"
UL_ON          : string : "\x1b[4m"
UL_OFF         : string : "\x1b[24m"

ENTER_SEQ : string : ALT_ON + CURSOR_STEADY + HIDE + HOME + CLEAR
LEAVE_SEQ : string : SHOW + CURSOR_DEFAULT + ALT_OFF

SIGWINCH :: posix.Signal(28)

when ODIN_OS == .Darwin {
	TIOCGWINSZ :: c.ulong(0x40087468)
} else when ODIN_OS == .Linux {
	TIOCGWINSZ :: c.ulong(0x5413)
}

Winsize :: struct { ws_row, ws_col, ws_xpixel, ws_ypixel: u16 }

foreign import libc "system:c"
foreign libc {
	ioctl :: proc(fd: c.int, request: c.ulong, #c_vararg rest: ..any) -> c.int ---
}

g_orig_termios: posix.termios
g_raw_active:   bool
g_resize_flag:  i32
g_die_flag:     i32

die :: proc(msg: string) {
	disable_raw_mode()
	fmt.eprintfln("ctype: %s", msg)
	os.exit(1)
}

@(private)
_raw_write :: proc(s: string) {
	b := transmute([]byte)s
	if len(b) > 0 {
		posix.write(posix.STDOUT_FILENO, cast([^]byte)raw_data(b), uint(len(b)))
	}
}

disable_raw_mode :: proc() {
	if g_raw_active {
		posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &g_orig_termios)
		_raw_write(LEAVE_SEQ)
		g_raw_active = false
	}
}

@(private)
_atexit_cb :: proc "c" () {
	context = runtime.default_context()
	disable_raw_mode()
}

enable_raw_mode :: proc() {
	if !bool(posix.isatty(posix.STDIN_FILENO)) do die("stdin is not a tty")
	if posix.tcgetattr(posix.STDIN_FILENO, &g_orig_termios) != posix.result(0) do die("tcgetattr")
	posix.atexit(_atexit_cb)

	raw := g_orig_termios
	raw.c_lflag -= {.ECHO, .ICANON, .IEXTEN}
	raw.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
	raw.c_oflag -= {.OPOST}
	raw.c_cc[.VMIN]  = 0
	raw.c_cc[.VTIME] = 0
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != posix.result(0) do die("tcsetattr")

	_raw_write(ENTER_SEQ)
	g_raw_active = true
}

@(private) on_winch      :: proc "c" (_: posix.Signal) { g_resize_flag = 1 }
@(private) on_die_signal :: proc "c" (_: posix.Signal) { g_die_flag    = 1 }

@(private)
on_crash :: proc "c" (sig: posix.Signal) {
	context = runtime.default_context()
	disable_raw_mode()
	sa: posix.sigaction_t
	posix.sigaction(sig, &sa, nil)
	posix.raise(sig)
}

install_signals :: proc() {
	sa: posix.sigaction_t

	sa.sa_handler = on_winch
	posix.sigaction(SIGWINCH, &sa, nil)

	sa.sa_handler = on_die_signal
	posix.sigaction(.SIGTERM, &sa, nil)
	posix.sigaction(.SIGHUP,  &sa, nil)
	posix.sigaction(.SIGINT,  &sa, nil)

	sa.sa_handler = on_crash
	sa.sa_flags   = {.RESETHAND, .SA_NODEFER}
	posix.sigaction(.SIGSEGV, &sa, nil)
	posix.sigaction(.SIGBUS,  &sa, nil)
	posix.sigaction(.SIGFPE,  &sa, nil)
	posix.sigaction(.SIGILL,  &sa, nil)
	posix.sigaction(.SIGABRT, &sa, nil)
}

query_size :: proc(s: ^State) {
	ws: Winsize
	if ioctl(1, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0 {
		s.cols = 80; s.rows = 24
	} else {
		s.cols = int(ws.ws_col); s.rows = int(ws.ws_row)
	}
}

fb_reset   :: #force_inline proc(f: ^Frame) { clear(f) }
fb_byte    :: #force_inline proc(f: ^Frame, b: byte) { append(f, b) }

fb_appendz :: #force_inline proc(f: ^Frame, s: string) {
	append(f, ..transmute([]byte)s)
}

fb_appendf :: proc(f: ^Frame, format: string, args: ..any) {
	s := fmt.tprintf(format, ..args)
	append(f, ..transmute([]byte)s)
}

fb_flush :: proc(f: ^Frame) {
	data := f[:]
	off  := 0
	for off < len(data) {
		rem := len(data) - off
		n   := posix.write(posix.STDOUT_FILENO, cast([^]byte)raw_data(data[off:]), uint(rem))
		if int(n) < 0 {
			if posix.errno() == .EINTR do continue
			break
		}
		if int(n) == 0 do break
		off += int(n)
	}
}
