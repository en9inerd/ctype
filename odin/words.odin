package ctype

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"


Contraction :: struct {
	from: string,
	to:   [4]string,
	n:    int,
}

CONTRACTIONS :: []Contraction{
	{"are",    {"aren't",  "",        "",       ""},  1},
	{"can",    {"can't",   "",        "",       ""},  1},
	{"could",  {"couldn't","",        "",       ""},  1},
	{"did",    {"didn't",  "",        "",       ""},  1},
	{"does",   {"doesn't", "",        "",       ""},  1},
	{"do",     {"don't",   "",        "",       ""},  1},
	{"had",    {"hadn't",  "",        "",       ""},  1},
	{"has",    {"hasn't",  "",        "",       ""},  1},
	{"have",   {"haven't", "",        "",       ""},  1},
	{"is",     {"isn't",   "",        "",       ""},  1},
	{"it",     {"it's",    "it'll",   "",       ""},  2},
	{"i",      {"i'm",     "i'll",    "i've",   "i'd"}, 4},
	{"you",    {"you'll",  "you're",  "you've", "you'd"}, 4},
	{"that",   {"that's",  "that'll", "that'd", ""},  3},
	{"must",   {"mustn't", "must've", "",       ""},  2},
	{"there",  {"there's", "there'll","there'd",""},  3},
	{"he",     {"he's",    "he'll",   "he'd",   ""},  3},
	{"she",    {"she's",   "she'll",  "she'd",  ""},  3},
	{"we",     {"we're",   "we'll",   "we'd",   ""},  3},
	{"they",   {"they're", "they'll", "they'd", ""},  3},
	{"should", {"shouldn't","should've","",     ""},  2},
	{"was",    {"wasn't",  "",        "",       ""},  1},
	{"were",   {"weren't", "",        "",       ""},  1},
	{"will",   {"won't",   "",        "",       ""},  1},
	{"would",  {"wouldn't","would've","",       ""},  2},
	{"going",  {"goin'",   "",        "",       ""},  1},
}

gen_number :: proc(w: ^Word) {
	n := 1 + rand.int_max(4)
	w.target[0] = byte('1' + rand.int_max(9))
	for i in 1..<n do w.target[i] = byte('0' + rand.int_max(10))
	w.target_len = n
}

@(private)
lookup_contraction :: proc(w: ^Word) -> ^Contraction {
	target_str := string(w.target[:w.target_len])
	lower: [MAX_WORD_LEN + 5]byte
	for i in 0..<w.target_len {
		c := w.target[i]
		lower[i] = c >= 'A' && c <= 'Z' ? c + 32 : c
	}
	low := string(lower[:w.target_len])
	for &c in CONTRACTIONS {
		if c.from == low do return &c
		_ = target_str
	}
	return nil
}

@(private)
apply_contraction :: proc(w: ^Word, c: ^Contraction) {
	repl := c.to[rand.int_max(c.n)]
	if len(repl) >= MAX_WORD_LEN + 5 do return
	copy(w.target[:], transmute([]byte)repl)
	w.target_len = len(repl)
}

@(private)
wrap_word :: proc(w: ^Word, open, close: byte) {
	n := w.target_len
	if n + 2 >= MAX_WORD_LEN + 5 do return
	copy(w.target[1:], w.target[:n])
	w.target[0]     = open
	w.target[n + 1] = close
	w.target_len     = n + 2
}

@(private)
suffix_char :: proc(w: ^Word, c: byte) {
	n := w.target_len
	if n + 1 >= MAX_WORD_LEN + 5 do return
	w.target[n] = c
	w.target_len = n + 1
}

apply_punct :: proc(w: ^Word, last_char: ^byte) {
	if w.target_len == 0 do return
	lc := last_char^
	should_cap := lc == 0 || lc == '.' || lc == '?' || lc == '!'

	if should_cap {
		if w.target[0] >= 'a' && w.target[0] <= 'z' do w.target[0] -= 32
	} else if rand.float64() < 0.10 && lc != '.' && lc != ',' {
		sub := rand.float64()
		if sub <= 0.8      { suffix_char(w, '.') }
		else if sub < 0.9  { suffix_char(w, '?') }
		else               { suffix_char(w, '!') }
	} else if rand.float64() < 0.01  && lc != ',' && lc != '.'             { wrap_word(w, '"',  '"')  }
	else if   rand.float64() < 0.011 && lc != ',' && lc != '.'             { wrap_word(w, '\'', '\'') }
	else if   rand.float64() < 0.012 && lc != ',' && lc != '.'             { wrap_word(w, '(',  ')')  }
	else if   rand.float64() < 0.013 && lc != ',' && lc != '.' && lc != ';' && lc != ':' { suffix_char(w, ':') }
	else if   rand.float64() < 0.014 && lc != ',' && lc != '.' && lc != '-' {
		w.target[0] = '-'; w.target_len = 1
	} else if rand.float64() < 0.015 && lc != ',' && lc != '.' && lc != ';' && lc != ':' { suffix_char(w, ';') }
	else if   rand.float64() < 0.2   && lc != ','                          { suffix_char(w, ',') }
	else if   rand.float64() < 0.5 {
		if c := lookup_contraction(w); c != nil do apply_contraction(w, c)
	}

	last_char^ = w.target[w.target_len - 1]
}

parse_wordlist :: proc(data: []byte) -> ([]string, bool) {
	text  := string(data)
	pool  := make([dynamic]string, 0, 256)
	start := 0
	for start <= len(text) {
		end := start
		for end < len(text) && text[end] != '\n' && text[end] != '\r' do end += 1
		line := strings.trim_space(text[start:end])
		if len(line) > 0 && len(line) <= MAX_WORD_LEN {
			ok := true
			for c in transmute([]byte)line {
				if c < 0x20 || c >= 0x7f { ok = false; break }
			}
			if ok do append(&pool, line)
		}
		next := end
		for next < len(text) && (text[next] == '\n' || text[next] == '\r') do next += 1
		if next == start do break
		start = next
	}
	if len(pool) == 0 { delete(pool); return nil, false }
	return pool[:], true
}

@(private)
file_exists :: proc(path: string) -> bool {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	st: posix.stat_t
	return posix.stat(cpath, &st) == posix.result(0)
}

@(private)
resolve_wordlist_path :: proc(cli_arg: string) -> string {
	if cli_arg != "" do return cli_arg

	if env, ok := os.lookup_env_alloc("CTYPE_WORDS", context.temp_allocator); ok && env != "" do return env

	xdg,  _ := os.lookup_env_alloc("XDG_DATA_HOME", context.temp_allocator)
	home, _ := os.lookup_env_alloc("HOME",           context.temp_allocator)
	if xdg != "" {
		p, _ := filepath.join([]string{xdg, "ctype", "words.txt"}, context.temp_allocator)
		if file_exists(p) do return p
	} else if home != "" {
		p, _ := filepath.join([]string{home, ".local", "share", "ctype", "words.txt"}, context.temp_allocator)
		if file_exists(p) do return p
	}

	if file_exists("/usr/local/share/ctype/words.txt") do return "/usr/local/share/ctype/words.txt"
	if file_exists("/usr/share/ctype/words.txt")       do return "/usr/share/ctype/words.txt"

	if len(os.args) > 0 {
		dir  := filepath.dir(os.args[0])
		p, _ := filepath.join([]string{dir, "..", "share", "ctype", "words.txt"}, context.temp_allocator)
		if file_exists(p) do return p
	}

	if file_exists("./assets/words_en.txt") do return "./assets/words_en.txt"
	return ""
}

load_wordlist :: proc(s: ^State, cli_arg: string) {
	path := resolve_wordlist_path(cli_arg)
	if path == "" {
		fmt.eprintln("ctype: no wordlist found. Try --words <file>, set CTYPE_WORDS,")
		fmt.eprintln("or run `make install` to put words.txt in $PREFIX/share/ctype/.")
		os.exit(1)
	}

	data: []byte
	read_err: os.Error
	if path == "-" {
		data, read_err = os.read_entire_file_from_file(os.stdin, context.allocator)
	} else {
		data, read_err = os.read_entire_file_from_path(path, context.allocator)
	}
	if read_err != nil do die("read wordlist")
	if len(data) > MAX_WORDLIST_BYTES {
		delete(data)
		die("wordlist too large")
	}

	pool, ok := parse_wordlist(data)
	if !ok {
		delete(data)
		die("wordlist empty")
	}
	s.pool_buf = data
	s.pool     = pool
}

append_sampled :: proc(s: ^State, n: int) {
	for i in 0..<n {
		w: Word
		if s.numbers && rand.float64() < 0.10 {
			gen_number(&w)
		} else {
			t  := s.pool[rand.int_max(len(s.pool))]
			tl := min(len(t), MAX_WORD_LEN)
			copy(w.target[:], transmute([]byte)t[:tl])
			w.target_len = tl
		}
		if s.punct do apply_punct(&w, &s.last_char)
		append(&s.words, w)
	}
}

seed_words :: proc(s: ^State) {
	if s.mode == .Zen do return
	append_sampled(s, s.mode == .Words ? s.words_target : INITIAL_SAMPLES)
}

compact_words :: proc(s: ^State) {
	if s.cur_word < 64 do return
	for i in 0..<s.cur_word {
		w       := &s.words[i]
		cmp_len := min(w.typed_len, w.target_len)
		for j in 0..<cmp_len {
			if w.typed[j] == w.target[j] { s.acc_correct += 1 }
			else                         { s.acc_wrong   += 1 }
		}
		if w.typed_len > w.target_len do s.acc_extra  += w.typed_len - w.target_len
		if w.finalized && w.typed_len < w.target_len do s.acc_missed += w.target_len - w.typed_len
	}
	remaining := len(s.words) - s.cur_word
	copy(s.words[:], s.words[s.cur_word:])
	resize(&s.words, remaining)
	s.cur_word       = 0
	s.last_drawn_cur = -1
}

maybe_refill :: proc(s: ^State) {
	if s.mode == .Words || s.mode == .Zen do return
	if len(s.words) - s.cur_word < REFILL_THRESHOLD {
		compact_words(s)
		append_sampled(s, INITIAL_SAMPLES)
	}
}
