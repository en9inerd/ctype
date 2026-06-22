# ctype

A small terminal typing test. Odin. macOS and Linux. No runtime dependencies beyond libc.

```
ctype                # 25 words (default)
ctype -w 50          # 50 words
ctype -t 30          # 30-second sprint
ctype -z             # zen — free typing, raw WPM only
ctype --punct        # sentence-style punctuation, monkeytype-flavored
ctype --numbers      # mix in random numbers (10% of slots)
ctype --stats        # last 10 results
ctype --graph        # WPM trend chart
```

Modifiers compose with any mode: `ctype -t 60 --punct --numbers`.

Tab restarts the current run, Esc ends it, Ctrl-C aborts without saving.

## Install

Homebrew:

```sh
brew install en9inerd/tap/ctype
```

Shell script (downloads prebuilt binary to `~/.local`):

```sh
curl -fsSL https://raw.githubusercontent.com/en9inerd/ctype/master/install.sh | sh
```

Override install prefix: `CTYPE_PREFIX=/usr/local sh install.sh`.
Pin a version: `sh install.sh v0.1.0`.

Both methods install the binary and the default wordlist.

## Building

Requires [Odin](https://odin-lang.org).

```sh
make build    # debug build
make release  # optimized build
make install  # install to ~/.local (PREFIX=... to override)
```

## Wordlist

The runtime searches for a wordlist in this order:

1. `--words <path>` flag
2. `$CTYPE_WORDS` env var
3. `$XDG_DATA_HOME/ctype/words.txt`
4. `~/.local/share/ctype/words.txt`
5. `/usr/local/share/ctype/words.txt`
6. `/usr/share/ctype/words.txt`
7. `<exe>/../share/ctype/words.txt`
8. `./assets/words_en.txt` (repo checkout)

Format: one word per line, printable ASCII, max 30 characters. Non-conforming lines are skipped. Pipe a custom list: `cat words.txt | ctype --words -`.

## Modifiers

`--punct` mirrors monkeytype's English `punctuateWord`: cascading independent rolls with `lastChar` guards. Sentence-start words are capitalized only (no other mark). Mid-sentence words try, in order: sentence-end (10%, sub-rolled `.` 80% / `?` 10% / `!` 10%), quote wrap (1%), single-quote wrap (1.1%), parens (1.2%), colon (1.3%), dash replace (1.4%), semicolon (1.5%), comma (20%), English contraction (50% if word matches table — `are`→`aren't`, `you`→`you're`/`you'll`/...). First match wins.

`--numbers` replaces 10% of word slots with a random 1–4 digit string, no leading zeros.

Both modifiers compose. The wordlist is never mutated; transforms happen on sampled copies.

## Stats

WPM and accuracy match monkeytype:

- WPM = `(correct_word_chars + correct_word_count) / 5 / minutes`. Only fully-correct words contribute chars and count. In-progress word gets partial char credit if all typed chars match so far. Auto-ended last word (words mode) gets char credit but no count (no space pressed).
- Raw WPM = `(all_typed_chars + spaces) / 5 / minutes`.
- Accuracy = `correct_keys / (correct_keys + incorrect_keys)`. Per-keystroke; backspacing and retyping never recovers lost accuracy.

Each completed run appends a JSON line to `~/.local/share/ctype/stats.jsonl`. `ctype --stats` shows the last ten as a table. `ctype --graph [N]` draws a WPM trend chart. `--reset-stats` deletes the file.

## Cross-compile

```sh
odin build odin/ -out:ctype -target:linux_amd64  -o:minimal
odin build odin/ -out:ctype -target:darwin_arm64 -o:minimal
```

Windows is not supported (POSIX termios).

## Layout

```
odin/
├── types.odin   shared structs and constants
├── term.odin    raw mode, signals, frame buffer, ANSI escapes
├── words.odin   wordlist parsing, sampling, punct/numbers, compaction
├── stats.odin   WPM math, JSONL i/o, --stats, --graph
├── input.odin   typing input handling, backspace, auto-end
├── render.odin  palette, viewport scrolling, draw loop
└── main.odin    argv, run loop, input dispatch
```
