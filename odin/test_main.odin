package ctype

import "core:sys/posix"
import "core:testing"

// ─── helpers ───────────────────────────────────────────────────────────────

make_test_state :: proc(targets: []string) -> State {
	s: State
	s.mode         = .Words
	s.words_target = len(targets)
	s.words        = make([dynamic]Word)
	for target in targets {
		w: Word
		tl := min(len(target), MAX_WORD_LEN)
		copy(w.target[:], transmute([]byte)target[:tl])
		w.target_len = tl
		append(&s.words, w)
	}
	s.started = true
	posix.clock_gettime(.MONOTONIC, &s.start_ts)
	return s
}

type_chars :: proc(s: ^State, text: string) {
	for c in transmute([]byte)text do on_char(s, c)
}

destroy_test_state :: proc(s: ^State) {
	delete(s.words)
	delete(s.zen_line)
	s^ = {}
}

approx :: proc(t: ^testing.T, got, expected, eps: f64, loc := #caller_location) {
	d := got - expected
	if d < 0 { d = -d }
	testing.expect(t, d <= eps, loc = loc)
}

// ─── word_imperfect ────────────────────────────────────────────────────────

@(test)
test_word_imperfect_perfect :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("hello")); w.target_len = 5
	copy(w.typed[:],  []byte("hello")); w.typed_len  = 5
	testing.expect(t, !word_imperfect(&w))
}

@(test)
test_word_imperfect_wrong_char :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("hello")); w.target_len = 5
	copy(w.typed[:],  []byte("hallo")); w.typed_len  = 5
	testing.expect(t, word_imperfect(&w))
}

@(test)
test_word_imperfect_too_short :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("hello")); w.target_len = 5
	copy(w.typed[:],  []byte("hel"));   w.typed_len  = 3
	testing.expect(t, word_imperfect(&w))
}

@(test)
test_word_imperfect_too_long :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("hi")); w.target_len = 2
	copy(w.typed[:],  []byte("his")); w.typed_len = 3
	testing.expect(t, word_imperfect(&w))
}

// ─── on_char ───────────────────────────────────────────────────────────────

@(test)
test_on_char_correct :: proc(t: ^testing.T) {
	s := make_test_state([]string{"abc"})
	defer destroy_test_state(&s)
	on_char(&s, 'a')
	testing.expect_value(t, s.words[0].typed_len, 1)
	testing.expect_value(t, s.correct_keys,       1)
	testing.expect_value(t, s.incorrect_keys,     0)
}

@(test)
test_on_char_wrong :: proc(t: ^testing.T) {
	s := make_test_state([]string{"abc"})
	defer destroy_test_state(&s)
	on_char(&s, 'x')
	testing.expect_value(t, s.words[0].typed_len, 1)
	testing.expect_value(t, s.correct_keys,       0)
	testing.expect_value(t, s.incorrect_keys,     1)
}

@(test)
test_on_char_space_correct_word :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hi")
	on_char(&s, ' ')
	testing.expect_value(t, s.cur_word,           1)
	testing.expect_value(t, s.correct_word_count, 1)
	testing.expect_value(t, s.correct_word_chars, 2)
	testing.expect_value(t, s.total_spaces,       1)
	testing.expect(t, s.words[0].finalized)
}

@(test)
test_on_char_space_wrong_word :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hx")
	on_char(&s, ' ')
	testing.expect_value(t, s.cur_word,           1)
	testing.expect_value(t, s.correct_word_count, 0)
	testing.expect_value(t, s.correct_word_chars, 0)
	testing.expect_value(t, s.total_spaces,       1)
	testing.expect_value(t, s.incorrect_keys,     2)
}

@(test)
test_on_char_space_empty_word :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi"})
	defer destroy_test_state(&s)
	on_char(&s, ' ')
	testing.expect_value(t, s.cur_word,    0)
	testing.expect_value(t, s.total_spaces, 0)
}

@(test)
test_on_char_auto_end :: proc(t: ^testing.T) {
	s := make_test_state([]string{"ab", "cd"})
	defer destroy_test_state(&s)
	type_chars(&s, "ab")
	on_char(&s, ' ')
	type_chars(&s, "cd")
	testing.expect_value(t, s.cur_word,           2)
	testing.expect(t, s.words[1].finalized)
	testing.expect_value(t, s.correct_word_chars, 4)
	testing.expect_value(t, s.total_spaces,       1)
	testing.expect_value(t, s.correct_word_count, 1)
}

@(test)
test_on_char_auto_end_wrong_no_trigger :: proc(t: ^testing.T) {
	s := make_test_state([]string{"ab", "cd"})
	defer destroy_test_state(&s)
	type_chars(&s, "ab")
	on_char(&s, ' ')
	type_chars(&s, "cx")
	testing.expect_value(t, s.cur_word, 1)
	testing.expect(t, !s.words[1].finalized)
}

@(test)
test_on_char_no_auto_end_time_mode :: proc(t: ^testing.T) {
	s := make_test_state([]string{"ab"})
	defer destroy_test_state(&s)
	s.mode = .Time
	type_chars(&s, "ab")
	testing.expect_value(t, s.cur_word, 0)
	testing.expect(t, !s.words[0].finalized)
}

// ─── on_backspace ──────────────────────────────────────────────────────────

@(test)
test_on_backspace_delete_char :: proc(t: ^testing.T) {
	s := make_test_state([]string{"abc"})
	defer destroy_test_state(&s)
	type_chars(&s, "ab")
	on_backspace(&s)
	testing.expect_value(t, s.words[0].typed_len, 1)
	testing.expect_value(t, s.words[0].typed[0],  byte('a'))
}

@(test)
test_on_backspace_go_back_imperfect :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hx")
	on_char(&s, ' ')
	testing.expect_value(t, s.cur_word, 1)
	on_backspace(&s)
	testing.expect_value(t, s.cur_word, 0)
	testing.expect(t, !s.words[0].finalized)
	testing.expect_value(t, s.total_spaces, 0)
}

@(test)
test_on_backspace_cant_go_back_perfect :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hi")
	on_char(&s, ' ')
	testing.expect_value(t, s.cur_word, 1)
	on_backspace(&s)
	testing.expect_value(t, s.cur_word, 1)
}

@(test)
test_on_backspace_at_start :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi"})
	defer destroy_test_state(&s)
	on_backspace(&s)
	testing.expect_value(t, s.cur_word,          0)
	testing.expect_value(t, s.words[0].typed_len, 0)
}

// ─── zen mode ──────────────────────────────────────────────────────────────

@(test)
test_zen_char_counting :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_char_zen(&s, 'h')
	on_char_zen(&s, 'i')
	testing.expect_value(t, s.zen_total_chars, 2)
	testing.expect_value(t, s.zen_total_words, 0)
	testing.expect_value(t, len(s.zen_line),   2)
	testing.expect(t, s.started)
}

@(test)
test_zen_space_counts_word :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_char_zen(&s, 'h')
	on_char_zen(&s, 'i')
	on_char_zen(&s, ' ')
	testing.expect_value(t, s.zen_total_chars, 3)
	testing.expect_value(t, s.zen_total_words, 1)
}

@(test)
test_zen_leading_space_no_word :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_char_zen(&s, ' ')
	testing.expect_value(t, s.zen_total_chars, 1)
	testing.expect_value(t, s.zen_total_words, 0)
}

@(test)
test_zen_backspace_char :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_char_zen(&s, 'h')
	on_char_zen(&s, 'i')
	on_backspace_zen(&s)
	testing.expect_value(t, s.zen_total_chars, 1)
	testing.expect_value(t, len(s.zen_line),   1)
}

@(test)
test_zen_backspace_space_decrements_word :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_char_zen(&s, 'h')
	on_char_zen(&s, 'i')
	on_char_zen(&s, ' ')
	testing.expect_value(t, s.zen_total_words, 1)
	on_backspace_zen(&s)
	testing.expect_value(t, s.zen_total_words, 0)
	testing.expect_value(t, s.zen_total_chars, 2)
}

@(test)
test_zen_backspace_empty :: proc(t: ^testing.T) {
	s: State; s.mode = .Zen
	defer destroy_test_state(&s)
	on_backspace_zen(&s)
	testing.expect_value(t, s.zen_total_chars, 0)
	testing.expect_value(t, len(s.zen_line),   0)
}

// ─── compute_stats ─────────────────────────────────────────────────────────

@(test)
test_stats_perfect_words :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hello", "world"})
	defer destroy_test_state(&s)
	type_chars(&s, "hello"); on_char(&s, ' ')
	type_chars(&s, "world")
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, 2.2, 0.01)
	approx(t, st.raw, 2.2, 0.01)
	approx(t, st.acc, 1.0, 0.001)
	testing.expect_value(t, st.correct, 10)
	testing.expect_value(t, st.wrong,    0)
}

@(test)
test_stats_with_wrong_word :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hi"); on_char(&s, ' ')
	type_chars(&s, "gx"); on_char(&s, ' ')
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, 0.6, 0.01)
	approx(t, st.raw, 1.2, 0.01)
	testing.expect_value(t, st.correct, 3)
	testing.expect_value(t, st.wrong,   1)
}

@(test)
test_stats_auto_end_no_space_credit :: proc(t: ^testing.T) {
	s := make_test_state([]string{"ab", "cd"})
	defer destroy_test_state(&s)
	type_chars(&s, "ab"); on_char(&s, ' ')
	type_chars(&s, "cd")
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, 1.0, 0.01)
	approx(t, st.raw, 1.0, 0.01)
}

@(test)
test_stats_wpm_equals_raw_at_perfect_accuracy :: proc(t: ^testing.T) {
	s := make_test_state([]string{"test", "word", "here"})
	defer destroy_test_state(&s)
	type_chars(&s, "test"); on_char(&s, ' ')
	type_chars(&s, "word"); on_char(&s, ' ')
	type_chars(&s, "here")
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, st.raw, 0.01)
}

@(test)
test_stats_partial_credit :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hello", "world"})
	defer destroy_test_state(&s)
	type_chars(&s, "hello"); on_char(&s, ' ')
	type_chars(&s, "wor")
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, 1.8, 0.01)
}

@(test)
test_stats_no_partial_credit_if_wrong :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hello", "world"})
	defer destroy_test_state(&s)
	type_chars(&s, "hello"); on_char(&s, ' ')
	type_chars(&s, "wox")
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.wpm, 1.2, 0.01)
}

@(test)
test_stats_accuracy :: proc(t: ^testing.T) {
	s := make_test_state([]string{"abcd"})
	defer destroy_test_state(&s)
	on_char(&s, 'a'); on_char(&s, 'b')
	on_char(&s, 'x'); on_char(&s, 'd')
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.acc, 0.75, 0.001)
}

@(test)
test_stats_extra_chars :: proc(t: ^testing.T) {
	s := make_test_state([]string{"hi", "go"})
	defer destroy_test_state(&s)
	type_chars(&s, "hixx"); on_char(&s, ' ')
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	testing.expect_value(t, st.extra, 2)
	testing.expect_value(t, st.wrong, 0)
}

@(test)
test_stats_zen :: proc(t: ^testing.T) {
	s: State
	s.mode    = .Zen
	s.started = true
	posix.clock_gettime(.MONOTONIC, &s.start_ts)
	s.zen_total_chars = 50
	s.end_ts = s.start_ts; s.end_ts.tv_sec += 60
	st := compute_stats(&s)
	approx(t, st.raw, 10.0, 0.01)
	approx(t, st.wpm,  0.0, 0.01)
}

// ─── gen_number ────────────────────────────────────────────────────────────

@(test)
test_gen_number_no_leading_zero :: proc(t: ^testing.T) {
	for _ in 0..<500 {
		w: Word
		gen_number(&w)
		testing.expect(t, w.target[0] >= '1' && w.target[0] <= '9')
		testing.expect(t, w.target_len >= 1 && w.target_len <= 4)
		for i in 0..<w.target_len {
			testing.expect(t, w.target[i] >= '0' && w.target[i] <= '9')
		}
		testing.expect_value(t, w.target[w.target_len], byte(0))
	}
}

// ─── parse_wordlist ────────────────────────────────────────────────────────

@(test)
test_parse_wordlist_basic :: proc(t: ^testing.T) {
	data := []byte("hello\nworld\nfoo\n")
	pool, ok := parse_wordlist(data)
	defer if pool != nil { delete(pool) }
	testing.expect(t, ok)
	testing.expect_value(t, len(pool), 3)
	if len(pool) >= 3 {
		testing.expect_value(t, pool[0], "hello")
		testing.expect_value(t, pool[1], "world")
		testing.expect_value(t, pool[2], "foo")
	}
}

@(test)
test_parse_wordlist_skip_long :: proc(t: ^testing.T) {
	data := []byte("hi\nabcdefghijklmnopqrstuvwxyz12345\nok\n")
	pool, ok := parse_wordlist(data)
	defer if pool != nil { delete(pool) }
	testing.expect(t, ok)
	testing.expect_value(t, len(pool), 2)
	if len(pool) >= 2 {
		testing.expect_value(t, pool[0], "hi")
		testing.expect_value(t, pool[1], "ok")
	}
}

@(test)
test_parse_wordlist_skip_nonascii :: proc(t: ^testing.T) {
	data := []byte("good\nbad\x80word\nfine\n")
	pool, ok := parse_wordlist(data)
	defer if pool != nil { delete(pool) }
	testing.expect(t, ok)
	testing.expect_value(t, len(pool), 2)
	if len(pool) >= 2 {
		testing.expect_value(t, pool[0], "good")
		testing.expect_value(t, pool[1], "fine")
	}
}

@(test)
test_parse_wordlist_trim_whitespace :: proc(t: ^testing.T) {
	data := []byte("  hello  \n  world  \n")
	pool, ok := parse_wordlist(data)
	defer if pool != nil { delete(pool) }
	testing.expect(t, ok)
	testing.expect_value(t, len(pool), 2)
	if len(pool) >= 2 {
		testing.expect_value(t, pool[0], "hello")
		testing.expect_value(t, pool[1], "world")
	}
}

@(test)
test_parse_wordlist_empty :: proc(t: ^testing.T) {
	data := []byte("\n\n\n")
	pool, ok := parse_wordlist(data)
	testing.expect(t, !ok)
	testing.expect_value(t, len(pool), 0)
}

@(test)
test_parse_wordlist_crlf :: proc(t: ^testing.T) {
	data := []byte("one\r\ntwo\r\n")
	pool, ok := parse_wordlist(data)
	defer if pool != nil { delete(pool) }
	testing.expect(t, ok)
	testing.expect_value(t, len(pool), 2)
	if len(pool) >= 2 {
		testing.expect_value(t, pool[0], "one")
		testing.expect_value(t, pool[1], "two")
	}
}

// ─── apply_punct ───────────────────────────────────────────────────────────

@(test)
test_punct_capitalize_first :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("hello")); w.target_len = 5
	lc: byte = 0
	apply_punct(&w, &lc)
	testing.expect_value(t, w.target[0], byte('H'))
}

@(test)
test_punct_capitalize_after_period :: proc(t: ^testing.T) {
	w: Word
	copy(w.target[:], []byte("world")); w.target_len = 5
	lc: byte = '.'
	apply_punct(&w, &lc)
	testing.expect_value(t, w.target[0], byte('W'))
}
