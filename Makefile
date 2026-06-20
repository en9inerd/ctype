PREFIX   ?= $(HOME)/.local
BIN      := zig-out/bin/ctype
ODIN_BIN := odin-out/ctype
VERSION  := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: all build release run test install uninstall clean stats reset \
        odin-build odin-release odin-run odin-install odin-clean odin-test

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

# --- Odin ---

odin-build:
	mkdir -p odin-out
	odin build odin/ -out:$(ODIN_BIN) -define:CTYPE_VERSION=$(VERSION)

odin-release:
	mkdir -p odin-out
	odin build odin/ -out:$(ODIN_BIN) -define:CTYPE_VERSION=$(VERSION) -o:minimal

odin-run: odin-build
	./$(ODIN_BIN)

odin-install: odin-release
	install -d $(PREFIX)/bin $(PREFIX)/share/ctype
	install -m 755 $(ODIN_BIN) $(PREFIX)/bin/ctype
	install -m 644 assets/words_en.txt $(PREFIX)/share/ctype/words.txt

odin-test:
	odin test odin/ -define:CTYPE_VERSION=$(VERSION)

odin-clean:
	rm -rf odin-out
