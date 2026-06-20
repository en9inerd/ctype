package ctype

import "core:sys/posix"

on_char_zen :: proc(s: ^State, c: byte) {
	if !s.started {
		s.started = true
		posix.clock_gettime(.MONOTONIC, &s.start_ts)
	}
	if c == ' ' && len(s.zen_line) > 0 do s.zen_total_words += 1
	s.zen_total_chars += 1
	if len(s.zen_line) < 4095 {
		append(&s.zen_line, c)
	}
}

on_backspace_zen :: proc(s: ^State) {
	if len(s.zen_line) > 0 {
		deleted := pop(&s.zen_line)
		if s.zen_total_chars > 0 do s.zen_total_chars -= 1
		if deleted == ' ' && s.zen_total_words > 0 do s.zen_total_words -= 1
	}
}

word_imperfect :: proc(w: ^Word) -> bool {
	if w.typed_len != w.target_len do return true
	for i in 0..<w.target_len {
		if w.typed[i] != w.target[i] do return true
	}
	return false
}

on_char :: proc(s: ^State, c: byte) {
	if !s.started {
		s.started = true
		posix.clock_gettime(.MONOTONIC, &s.start_ts)
	}
	if s.cur_word >= len(s.words) do return
	w := &s.words[s.cur_word]

	if c == ' ' {
		if w.typed_len == 0 do return
		if !word_imperfect(w) {
			s.correct_keys       += 1
			s.correct_word_chars += w.target_len
			s.correct_word_count += 1
		} else {
			s.incorrect_keys += 1
		}
		w.finalized     = true
		s.total_spaces += 1
		s.cur_word     += 1
		if s.cur_word >= len(s.words) && s.mode != .Words {
			append_sampled(s, INITIAL_SAMPLES)
		}
	} else if w.typed_len < MAX_TYPED - 1 {
		pos := w.typed_len
		if pos < w.target_len && c == w.target[pos] {
			s.correct_keys += 1
		} else {
			s.incorrect_keys += 1
		}
		w.typed[w.typed_len] = c
		w.typed_len += 1
		if s.mode == .Words &&
		   s.cur_word == s.words_target - 1 &&
		   w.typed_len == w.target_len &&
		   !word_imperfect(w) {
			w.finalized           = true
			s.correct_word_chars += w.target_len
			s.cur_word           += 1
		}
	}
}

on_backspace :: proc(s: ^State) {
	if s.cur_word >= len(s.words) do return
	w := &s.words[s.cur_word]
	if w.typed_len > 0 {
		w.typed_len -= 1
	} else if s.cur_word > 0 {
		prev := &s.words[s.cur_word - 1]
		if word_imperfect(prev) {
			s.cur_word     -= 1
			prev.finalized  = false
			s.total_spaces -= 1
		}
	}
}
