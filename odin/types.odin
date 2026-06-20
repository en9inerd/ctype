package ctype

import "core:sys/posix"

CTYPE_VERSION :: #config(CTYPE_VERSION, "dev")

MAX_WORD_LEN       :: 30
MAX_TYPED          :: 80
MIN_COLS           :: 40
MIN_ROWS           :: 10
MAX_WORDLIST_BYTES :: 1 << 20
VIEWPORT_LINES     :: 3
INITIAL_SAMPLES    :: 80
REFILL_THRESHOLD   :: 20
TICK_MS            :: 100
INITIAL_FRAME_CAP  :: 8192
MAX_TEXT_WIDTH     :: 80
MIN_TEXT_WIDTH     :: 20
TEXT_MARGIN        :: 4
INPUT_BUF_SIZE     :: 64
DEFAULT_WORDS      :: 25

Mode :: enum u8 { Words, Time, Zen }

Word :: struct {
	target:     [MAX_WORD_LEN + 5]byte,
	target_len: int,
	typed:      [MAX_TYPED]byte,
	typed_len:  int,
	finalized:  bool,
}

Palette :: struct {
	dim, text, main_, err, err_bg: string,
}

State :: struct {
	mode:            Mode,
	duration_target: int,
	words_target:    int,
	punct:           bool,
	numbers:         bool,
	last_char:       byte,

	pool:     []string,
	pool_buf: []byte,

	words:    [dynamic]Word,
	cur_word: int,

	started:  bool,
	start_ts: posix.timespec,
	end_ts:   posix.timespec,

	cols, rows: int,
	aborted:    bool,
	resized:    bool,

	pal: Palette,

	last_drawn_second: int,
	last_drawn_cur:    int,
	last_drawn_typed:  int,
	needs_render:      bool,

	acc_correct, acc_wrong, acc_extra, acc_missed: int,
	correct_keys, incorrect_keys:                  int,
	correct_word_chars, correct_word_count:        int,
	total_spaces:                                  int,

	zen_line:        [dynamic]byte,
	zen_total_chars: int,
	zen_total_words: int,
}

Stats :: struct {
	correct, wrong, extra, missed: int,
	total_typed:                   int,
	wpm, raw, acc:                 f64,
	seconds:                       f64,
}

Frame :: [dynamic]byte
