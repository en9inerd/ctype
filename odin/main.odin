package ctype

import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:sys/posix"

@(private)
reset_test :: proc(s: ^State) {
	if s.mode == .Zen {
		clear(&s.zen_line)
		s.zen_total_chars = 0
		s.zen_total_words = 0
	} else {
		clear(&s.words)
		s.cur_word           = 0
		s.acc_correct        = 0; s.acc_wrong        = 0
		s.acc_extra          = 0; s.acc_missed       = 0
		s.correct_keys       = 0; s.incorrect_keys   = 0
		s.correct_word_chars = 0; s.correct_word_count = 0
		s.total_spaces       = 0
		s.last_char          = 0
		seed_words(s)
	}
	s.started           = false
	s.start_ts          = {}
	s.end_ts            = {}
	s.last_drawn_second = -1
	s.last_drawn_cur    = -1
	s.last_drawn_typed  = -1
}

@(private)
should_end :: proc(s: ^State) -> bool {
	if s.aborted  do return true
	if !s.started do return false
	if s.mode == .Time  do return elapsed_seconds(s) >= f64(s.duration_target)
	if s.mode == .Words do return s.cur_word >= s.words_target
	return false
}

@(private)
_needs_render :: proc(s: ^State) -> bool {
	if s.needs_render do return true
	if int(elapsed_seconds(s)) != s.last_drawn_second do return true
	if s.mode == .Zen do return len(s.zen_line) != s.last_drawn_typed
	if s.cur_word != s.last_drawn_cur do return true
	tlen := s.cur_word < len(s.words) ? s.words[s.cur_word].typed_len : 0
	return tlen != s.last_drawn_typed
}

@(private)
mark_drawn :: proc(s: ^State) {
	s.last_drawn_second = int(elapsed_seconds(s))
	if s.mode == .Zen {
		s.last_drawn_typed = len(s.zen_line)
	} else {
		s.last_drawn_cur   = s.cur_word
		s.last_drawn_typed = s.cur_word < len(s.words) ? s.words[s.cur_word].typed_len : 0
	}
	s.needs_render = false
}

@(private)
run_test :: proc(s: ^State) {
	detect_palette(s)
	enable_raw_mode()
	install_signals()
	query_size(s)
	if s.cols < MIN_COLS || s.rows < MIN_ROWS do die("terminal too small (need >= 40x10)")

	if s.mode != .Zen do seed_words(s)

	frame: Frame
	reserve(&frame, INITIAL_FRAME_CAP)
	defer delete(frame)

	s.needs_render = true
	s.resized      = true
	render(s, &frame)
	mark_drawn(s)

	pfds := [1]posix.pollfd{{fd = posix.STDIN_FILENO, events = {.IN}}}

	loop: for !should_end(s) {
		if g_die_flag != 0 { s.aborted = true; break }
		if g_resize_flag != 0 {
			g_resize_flag  = 0
			query_size(s)
			s.needs_render = true
			s.resized      = true
		}

		r := posix.poll(cast([^]posix.pollfd)raw_data(pfds[:]), 1, c.int(TICK_MS))
		if int(r) < 0 {
			if posix.errno() == .EINTR do continue
			die("poll")
		}

		if int(r) > 0 && (.IN in pfds[0].revents) {
			buf: [INPUT_BUF_SIZE]byte
			got := posix.read(posix.STDIN_FILENO, cast([^]byte)raw_data(buf[:]), uint(len(buf)))
			if int(got) < 0 {
				if posix.errno() == .EINTR do continue
				die("read")
			}
			input_changed := false
			for i in 0..<int(got) {
				ch := buf[i]
				if ch == 0x03 { s.aborted = true; break loop }
				if ch == 0x1b { break loop }
				if ch == 0x09 {
					reset_test(s)
					s.needs_render = true
					input_changed  = true
					continue
				}
				if ch == 0x7f || ch == 0x08 {
					if s.mode == .Zen { on_backspace_zen(s) } else { on_backspace(s) }
					input_changed = true
					continue
				}
				if ch >= 0x20 && ch < 0x7f {
					if s.mode == .Zen { on_char_zen(s, ch) } else { on_char(s, ch) }
					input_changed = true
				}
			}
			if input_changed && s.mode != .Zen do maybe_refill(s)
		}

		if _needs_render(s) { render(s, &frame); mark_drawn(s) }
	}

	posix.clock_gettime(.MONOTONIC, &s.end_ts)
	disable_raw_mode()

	if s.aborted || !s.started {
		if s.aborted do fmt.println("\naborted.")
		return
	}

	st := compute_stats(s)
	append_stats(s, &st)

	mode_s := s.mode == .Time ? "time" : s.mode == .Zen ? "zen" : "words"
	fmt.println()
	fmt.printfln("  mode      %s",    mode_s)
	fmt.printfln("  time      %.2fs", st.seconds)
	if s.mode == .Zen {
		fmt.printfln("  raw wpm   %.1f", st.raw)
		fmt.printfln("  chars     %d",  s.zen_total_chars)
		fmt.printfln("  words     %d",  s.zen_total_words)
	} else {
		fmt.printfln("  wpm       %.1f",   st.wpm)
		fmt.printfln("  raw wpm   %.1f",   st.raw)
		fmt.printfln("  accuracy  %.1f%%", st.acc * 100.0)
		fmt.printfln("  correct   %d",     st.correct)
		fmt.printfln("  wrong     %d",     st.wrong)
		fmt.printfln("  extra     %d",     st.extra)
		fmt.printfln("  missed    %d",     st.missed)
	}
	p, _ := stats_path(context.temp_allocator)
	fmt.printfln("\n  saved -> %s\n", p)
}

@(private)
usage :: proc(use_stderr: bool) {
	text := fmt.tprintf(
		"ctype %s — terminal typing test\n\n" +
		"usage: ctype [options]\n\n" +
		"modes:\n" +
		"  -w N                   type N words (default: 25)\n" +
		"  -t N                   timed, N seconds\n" +
		"  -z, --zen              free typing, raw WPM only\n\n" +
		"options:\n" +
		"  --words PATH           wordlist file (- for stdin)\n" +
		"  --punct                add sentence-style punctuation\n" +
		"  --numbers              mix in random numbers (10%%)\n" +
		"  --stats                print last 10 results\n" +
		"  --graph [N]            WPM trend chart (default last 50)\n" +
		"  --reset-stats          delete stats file\n" +
		"  -h, --help\n" +
		"  -v, --version\n\n" +
		"keys: type chars, space advances, backspace corrects,\n" +
		"      Tab restarts, Esc ends, Ctrl-C aborts.\n",
		CTYPE_VERSION)
	if use_stderr { fmt.eprint(text) } else { fmt.print(text) }
}

when !ODIN_TEST {
main :: proc() {
	ts: posix.timespec
	posix.clock_gettime(.MONOTONIC, &ts)
	rand.reset(u64(ts.tv_nsec) ~ u64(ts.tv_sec) ~ u64(posix.getpid()))

	s: State
	s.mode              = .Words
	s.words_target      = DEFAULT_WORDS
	s.last_drawn_second = -1
	s.last_drawn_cur    = -1
	s.last_drawn_typed  = -1

	args      := os.args[1:]
	words_arg := ""
	mode_set  := false

	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch a {
		case "-h", "--help":
			usage(false); return
		case "-v", "--version":
			fmt.printfln("ctype %s", CTYPE_VERSION); return
		case "--stats":
			os.exit(print_recent_stats(10))
		case "--reset-stats":
			os.exit(reset_stats())
		case "--graph":
			n := 50
			if i + 1 < len(args) {
				if v, ok := strconv.parse_int(args[i + 1]); ok && v > 0 {
					n = v; i += 1
				}
			}
			os.exit(print_graph(n))
		case "-z", "--zen":
			if mode_set { fmt.eprintln("ctype: only one mode allowed"); os.exit(2) }
			s.mode = .Zen; mode_set = true
		case "-t":
			if mode_set { fmt.eprintln("ctype: only one mode allowed"); os.exit(2) }
			i += 1
			if i >= len(args) { fmt.eprintln("-t needs value"); os.exit(2) }
			v, ok := strconv.parse_int(args[i])
			if !ok || v <= 0 { fmt.eprintln("-t must be > 0"); os.exit(2) }
			s.mode = .Time; s.duration_target = v; mode_set = true
		case "-w":
			if mode_set { fmt.eprintln("ctype: only one mode allowed"); os.exit(2) }
			i += 1
			if i >= len(args) { fmt.eprintln("-w needs value"); os.exit(2) }
			v, ok := strconv.parse_int(args[i])
			if !ok || v <= 0 { fmt.eprintln("-w must be > 0"); os.exit(2) }
			s.mode = .Words; s.words_target = v; mode_set = true
		case "--words":
			i += 1
			if i >= len(args) { fmt.eprintln("--words needs value"); os.exit(2) }
			words_arg = args[i]
		case "--punct":
			s.punct = true
		case "--numbers":
			s.numbers = true
		case:
			fmt.eprintfln("ctype: unknown arg: %s", a)
			usage(true)
			os.exit(2)
		}
	}

	if s.mode != .Zen do load_wordlist(&s, words_arg)
	run_test(&s)

	delete(s.words)
	delete(s.zen_line)
	delete(s.pool)
	delete(s.pool_buf)
}
} // when !ODIN_TEST
