PREFIX  ?= $(HOME)/.local
BIN     := zig-out/bin/ctype
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: all build release run test install uninstall clean stats reset

all: build

build:
	zig build -Dversion=$(VERSION)

release:
	zig build -Doptimize=ReleaseFast -Dversion=$(VERSION)

run: build
	./$(BIN)

test:
	zig build test -Dversion=$(VERSION)

install:
	zig build install -Doptimize=ReleaseFast -Dversion=$(VERSION) --prefix $(PREFIX)

uninstall:
	rm -f $(PREFIX)/bin/ctype
	rm -rf $(PREFIX)/share/ctype

clean:
	rm -rf zig-out .zig-cache

stats: build
	./$(BIN) --stats

reset: build
	./$(BIN) --reset-stats
