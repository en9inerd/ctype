package ctype

import "core:os"

TC_DIM    :: "\x1b[38;2;100;102;105m"
TC_TEXT   :: "\x1b[38;2;209;208;197m"
TC_MAIN   :: "\x1b[38;2;226;183;20m"
TC_ERR    :: "\x1b[38;2;202;71;84m"
TC_ERR_BG :: "\x1b[48;2;126;42;51m\x1b[38;2;255;255;255m"

P_DIM    :: "\x1b[38;5;240m"
P_TEXT   :: "\x1b[38;5;253m"
P_MAIN   :: "\x1b[38;5;179m"
P_ERR    :: "\x1b[38;5;167m"
P_ERR_BG :: "\x1b[48;5;52m\x1b[38;5;231m"

detect_palette :: proc(s: ^State) {
	ct, ok := os.lookup_env_alloc("COLORTERM", context.temp_allocator)
	truecolor := ok && (contains(ct, "truecolor") || contains(ct, "24bit"))
	if truecolor {
		s.pal = {TC_DIM, TC_TEXT, TC_MAIN, TC_ERR, TC_ERR_BG}
	} else {
		s.pal = {P_DIM, P_TEXT, P_MAIN, P_ERR, P_ERR_BG}
	}
}

@(private)
contains :: proc(s, sub: string) -> bool {
	if len(sub) > len(s) do return false
	for i in 0..=len(s)-len(sub) {
		if s[i:i+len(sub)] == sub do return true
	}
	return false
}

MAX_LAYOUT_LINES :: 1024

@(private)
layout_lines :: proc(s: ^State, max_cols: int, line_first: []int) -> int {
	n, c := 1, 0
	line_first[0] = 0
	for wi in 0..<len(s.words) {
		if n >= len(line_first) do break
		w     := &s.words[wi]
		extras := max(0, w.typed_len - w.target_len)
		wlen   := w.target_len + extras
		if c != 0 && c + wlen > max_cols {
			line_first[n] = wi
			n += 1
			c  = 0
		}
		c += wlen
		if c + 1 <= max_cols {
			c += 1
		} else {
			if wi + 1 < len(s.words) && n < len(line_first) {
				line_first[n] = wi + 1
				n += 1
			}
			c = 0
		}
	}
	return n
}

render :: proc(s: ^State, f: ^Frame) {
	max_cols := clamp(s.cols - TEXT_MARGIN, MIN_TEXT_WIDTH, MAX_TEXT_WIDTH)
	x_off    := max(1, (s.cols - max_cols) / 2 + 1)

	stats_row := 2
	words_row := max(stats_row + 2, s.rows / 2 - 1)
	hint_row  := max(words_row + VIEWPORT_LINES, s.rows - 2)

	st := compute_stats(s)

	fb_reset(f)
	fb_appendz(f, SYNC_BEGIN + HIDE)
	if s.resized {
		fb_appendz(f, HOME + CLEAR)
		s.resized = false
	}

	fb_appendf(f, "\x1b[%d;%dH%s", stats_row, x_off, s.pal.main_)
	switch s.mode {
	case .Time:
		rem := max(0, s.duration_target - int(st.seconds))
		fb_appendf(f, "time %ds  %ds left  wpm %d  acc %d%%",
			s.duration_target, rem, int(st.wpm + 0.5), int(st.acc * 100.0 + 0.5))
	case .Words:
		fb_appendf(f, "words %d  %d/%d  wpm %d  acc %d%%",
			s.words_target, s.cur_word, s.words_target,
			int(st.wpm + 0.5), int(st.acc * 100.0 + 0.5))
	case .Zen:
		fb_appendf(f, "zen  %.1fs  raw wpm %d", st.seconds, int(st.raw + 0.5))
	}
	fb_appendz(f, RESET + EOL)

	if s.mode == .Zen {
		fb_appendf(f, "\x1b[%d;%dH", words_row, x_off)
		zlen  := len(s.zen_line)
		start := max(0, zlen - max_cols)
		fb_appendz(f, s.pal.text)
		for i in start..<zlen do fb_byte(f, s.zen_line[i])
		fb_appendz(f, s.pal.main_); fb_appendz(f, UL_ON)
		fb_byte(f, ' ')
		fb_appendz(f, UL_OFF + RESET)
		drawn := min(zlen, max_cols) + 1
		for drawn < max_cols { fb_byte(f, ' '); drawn += 1 }
		fb_appendz(f, EOL)
		for r in 1..<VIEWPORT_LINES {
			fb_appendf(f, "\x1b[%d;%dH" + EOL, words_row + r, x_off)
		}
	} else {
		line_first_buf: [MAX_LAYOUT_LINES]int
		line_first := line_first_buf[:]
		n_lines    := layout_lines(s, max_cols, line_first)

		cur_line := 0
		for l := n_lines - 1; l >= 0; l -= 1 {
			if line_first[l] <= s.cur_word { cur_line = l; break }
		}

		view_start := cur_line > 0 ? cur_line - 1 : 0
		if view_start + VIEWPORT_LINES > n_lines && n_lines > VIEWPORT_LINES {
			view_start = n_lines - VIEWPORT_LINES
		}

		wi_begin    := line_first[view_start]
		row, col    := 0, 0
		row_written : [VIEWPORT_LINES]bool
		cur_color   : string

		for wi in wi_begin..<len(s.words) {
			w      := &s.words[wi]
			extras := max(0, w.typed_len - w.target_len)
			wlen   := w.target_len + extras

			if col != 0 && col + wlen > max_cols {
				fb_appendz(f, EOL)
				row += 1; col = 0
				if row >= VIEWPORT_LINES do break
			}
			if col == 0 {
				fb_appendf(f, "\x1b[%d;%dH", words_row + row, x_off)
				row_written[row] = true
				cur_color = ""
			}

			for ci in 0..<w.target_len {
				is_cursor := wi == s.cur_word && ci == w.typed_len
				color: string
				if ci < w.typed_len {
					color = w.typed[ci] == w.target[ci] ? s.pal.text : s.pal.err
				} else if is_cursor {
					color = s.pal.main_
				} else {
					color = s.pal.dim
				}
				if is_cursor do fb_appendz(f, UL_ON)
				if color != cur_color { fb_appendz(f, color); cur_color = color }
				fb_byte(f, w.target[ci])
				if is_cursor { fb_appendz(f, UL_OFF); cur_color = "" }
			}
			for ei in 0..<extras {
				if s.pal.err_bg != cur_color { fb_appendz(f, s.pal.err_bg); cur_color = s.pal.err_bg }
				fb_byte(f, w.typed[w.target_len + ei])
			}

			cursor_space := false
			if wi == s.cur_word && w.typed_len >= w.target_len + extras {
				fb_appendz(f, RESET); fb_appendz(f, s.pal.main_); fb_appendz(f, UL_ON)
				fb_byte(f, ' ')
				fb_appendz(f, UL_OFF)
				col         += 1
				cursor_space = true
			}
			fb_appendz(f, RESET)
			cur_color = ""
			col += wlen

			if !cursor_space {
				if col + 1 <= max_cols {
					fb_byte(f, ' ')
					col += 1
				} else {
					fb_appendz(f, EOL)
					row += 1; col = 0
					if row >= VIEWPORT_LINES do break
				}
			}
		}
		if row < VIEWPORT_LINES && row_written[row] do fb_appendz(f, EOL)
		for r in 0..<VIEWPORT_LINES {
			if !row_written[r] {
				fb_appendf(f, "\x1b[%d;%dH" + EOL, words_row + r, x_off)
			}
		}
	}

	fb_appendf(f, "\x1b[%d;%dH%sEsc end  Tab restart  Ctrl-C abort%s" + EOL,
		hint_row, x_off, s.pal.dim, RESET)
	fb_appendz(f, SYNC_END)
	fb_flush(f)
}
