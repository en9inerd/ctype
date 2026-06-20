package ctype

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"

elapsed_seconds :: proc(s: ^State) -> f64 {
	if !s.started do return 0.0
	now: posix.timespec
	if s.end_ts.tv_sec != 0 {
		now = s.end_ts
	} else {
		posix.clock_gettime(.MONOTONIC, &now)
	}
	d := f64(now.tv_sec  - s.start_ts.tv_sec) +
	     f64(now.tv_nsec - s.start_ts.tv_nsec) / 1e9
	return max(d, 0.001)
}

compute_stats :: proc(s: ^State) -> Stats {
	st: Stats
	st.seconds = elapsed_seconds(s)
	mins := max(st.seconds / 60.0, 1e-6)

	if s.mode == .Zen {
		st.raw = (f64(s.zen_total_chars) / 5.0) / mins
		return st
	}

	st.correct = s.acc_correct
	st.wrong   = s.acc_wrong
	st.extra   = s.acc_extra
	st.missed  = s.acc_missed

	upto := min(s.cur_word + 1, len(s.words))
	for i in 0..<upto {
		w       := &s.words[i]
		cmp_len := min(w.typed_len, w.target_len)
		for j in 0..<cmp_len {
			if w.typed[j] == w.target[j] { st.correct += 1 } else { st.wrong += 1 }
		}
		if w.typed_len > w.target_len do st.extra  += w.typed_len - w.target_len
		if w.finalized && w.typed_len < w.target_len do st.missed += w.target_len - w.typed_len
	}
	st.total_typed = st.correct + st.wrong + st.extra

	wpm_chars := s.correct_word_chars
	wpm_count := s.correct_word_count
	if s.cur_word < len(s.words) {
		w := &s.words[s.cur_word]
		if w.typed_len > 0 && w.typed_len <= w.target_len {
			match := true
			for i in 0..<w.typed_len {
				if w.typed[i] != w.target[i] { match = false; break }
			}
			if match do wpm_chars += w.typed_len
		}
	}
	st.wpm = (f64(wpm_chars + wpm_count) / 5.0) / mins
	st.raw = (f64(st.total_typed + s.total_spaces) / 5.0) / mins
	keys   := s.correct_keys + s.incorrect_keys
	st.acc  = keys > 0 ? f64(s.correct_keys) / f64(keys) : 0.0
	return st
}

MODE_DIR  :: posix.mode_t{.IRUSR, .IWUSR, .IXUSR, .IRGRP, .IXGRP, .IROTH, .IXOTH} // 0o755
MODE_FILE :: posix.mode_t{.IRUSR, .IWUSR, .IRGRP, .IROTH}                          // 0o644

@(private)
mkdir_p :: proc(path: string) -> bool {
	buf := make([]byte, len(path) + 2, context.temp_allocator)
	copy(buf, transmute([]byte)path)
	for i in 1..<len(path) {
		if buf[i] == '/' {
			buf[i] = 0
			posix.mkdir(cstring(raw_data(buf)), MODE_DIR)
			buf[i] = '/'
		}
	}
	r := posix.mkdir(cstring(raw_data(buf)), MODE_DIR)
	return r == posix.result(0) || posix.errno() == .EEXIST
}

stats_path :: proc(allocator := context.allocator) -> (string, bool) {
	xdg,  _ := os.lookup_env_alloc("XDG_DATA_HOME", context.temp_allocator)
	home, _ := os.lookup_env_alloc("HOME",           context.temp_allocator)
	dir: string
	if xdg != "" {
		dir = fmt.tprintf("%s/ctype", xdg)
	} else if home != "" {
		dir = fmt.tprintf("%s/.local/share/ctype", home)
	} else {
		return "", false
	}
	if !mkdir_p(dir) do return "", false
	return fmt.aprintf("%s/stats.jsonl", dir, allocator = allocator), true
}

append_stats :: proc(s: ^State, st: ^Stats) {
	path, ok := stats_path(context.temp_allocator)
	if !ok do return
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	fd := posix.open(cpath, {.WRONLY, .CREAT, .APPEND}, MODE_FILE)
	if int(fd) < 0 do return
	defer posix.close(fd)

	mode_s := s.mode == .Time ? "time" : s.mode == .Zen ? "zen" : "words"
	target := s.mode == .Time ? s.duration_target : s.mode == .Words ? s.words_target : 0
	ts     := i64(posix.time(nil))
	line   := fmt.tprintf(
		"{\"ts\":%d,\"mode\":\"%s\",\"duration\":%.2f,\"target\":%d," +
		"\"wpm\":%.2f,\"raw\":%.2f,\"acc\":%.4f," +
		"\"correct\":%d,\"wrong\":%d,\"extra\":%d,\"missed\":%d}\n",
		ts, mode_s, st.seconds, target, st.wpm, st.raw, st.acc,
		st.correct, st.wrong, st.extra, st.missed)
	b := transmute([]byte)line
	posix.write(fd, cast([^]byte)raw_data(b), uint(len(b)))
}

print_recent_stats :: proc(n: int) -> int {
	path, ok := stats_path(context.temp_allocator)
	if !ok { fmt.eprintln("no $HOME/$XDG_DATA_HOME"); return 1 }

	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil { fmt.printfln("no stats yet (%s)", path); return 0 }

	lines := strings.split_lines(string(data), context.temp_allocator)
	start := max(0, len(lines) - n)

	fmt.printf("%-12s %-7s %5s %5s %5s\n", "ts", "mode", "wpm", "raw", "acc")
	for line in lines[start:] {
		if line == "" do continue
		ts   := parse_json_i64(line, "\"ts\":")
		mode := parse_json_str(line, "\"mode\":\"", '"')
		wpm  := parse_json_f64(line, "\"wpm\":")
		raw  := parse_json_f64(line, "\"raw\":")
		acc  := parse_json_f64(line, "\"acc\":")
		fmt.printf("%-12d %-7s %5.1f %5.1f %4.1f%%\n", ts, mode, wpm, raw, acc * 100.0)
	}
	return 0
}

reset_stats :: proc() -> int {
	path, ok := stats_path(context.temp_allocator)
	if !ok do return 1
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if posix.unlink(cpath) == posix.result(0) {
		fmt.printfln("removed %s", path)
		return 0
	}
	if posix.errno() == .ENOENT {
		fmt.println("no stats file")
		return 0
	}
	fmt.eprintfln("unlink failed: errno %d", int(posix.errno()))
	return 1
}

print_graph :: proc(count: int) -> int {
	n := clamp(count, 1, 512)
	path, ok := stats_path(context.temp_allocator)
	if !ok { fmt.eprintln("no $HOME/$XDG_DATA_HOME"); return 1 }

	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil { fmt.printfln("no stats yet (%s)", path); return 0 }

	wpms  := make([]f64, n, context.temp_allocator)
	found := 0
	text  := string(data)
	for line in strings.split_lines_iterator(&text) {
		if line == "" do continue
		w := parse_json_f64(line, "\"wpm\":")
		if w == 0 do continue
		if found < n {
			wpms[found] = w
			found += 1
		} else {
			copy(wpms, wpms[1:])
			wpms[n - 1] = w
		}
	}
	wpms = wpms[:found]

	if found == 0 { fmt.println("no completed sessions yet"); return 0 }

	mn, mx, sum := wpms[0], wpms[0], 0.0
	for w in wpms { mn = min(mn, w); mx = max(mx, w); sum += w }
	avg  := sum / f64(found)
	last := wpms[found - 1]

	H     :: 8
	rng   := mx - mn
	if rng < 1.0 do rng = 1.0

	blocks := [9]string{" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

	fmt.printfln("WPM trend (last %d, file: %s)\n", found, path)
	for r := H - 1; r >= 0; r -= 1 {
		row_top := mn + rng * f64(r + 1) / H
		row_bot := mn + rng * f64(r)     / H
		if      r == H - 1 { fmt.printf("%5.0f ┤", mx) }
		else if r == 0      { fmt.printf("%5.0f ┤", mn) }
		else if r == H / 2  { fmt.printf("%5.0f ┤", mn + rng / 2) }
		else                { fmt.printf("      │") }
		for w in wpms {
			level: int
			if      w >= row_top { level = 8 }
			else if w <= row_bot { level = 0 }
			else {
				level = clamp(int((w - row_bot) / (row_top - row_bot) * 8.0 + 0.5), 0, 8)
			}
			fmt.print(blocks[level])
		}
		fmt.println()
	}
	fmt.printf("      └")
	for _ in wpms do fmt.print("-")
	fmt.println()
	fmt.printfln("\n  min %.1f   avg %.1f   max %.1f   last %.1f\n", mn, avg, mx, last)
	return 0
}

@(private)
parse_json_i64 :: proc(s, key: string) -> i64 {
	i := strings.index(s, key)
	if i < 0 do return 0
	v, _ := strconv.parse_i64(strings.trim_left_space(s[i + len(key):]))
	return v
}

@(private)
parse_json_f64 :: proc(s, key: string) -> f64 {
	i := strings.index(s, key)
	if i < 0 do return 0
	v, _ := strconv.parse_f64(strings.trim_left_space(s[i + len(key):]))
	return v
}

@(private)
parse_json_str :: proc(s, key: string, end_char: byte) -> string {
	i := strings.index(s, key)
	if i < 0 do return ""
	rest := s[i + len(key):]
	j    := strings.index_byte(rest, end_char)
	if j < 0 do return rest
	return rest[:j]
}
