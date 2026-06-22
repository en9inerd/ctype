PREFIX  ?= $(HOME)/.local
BIN     := odin-out/ctype
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: all build release run test install uninstall clean stats reset

all: build

build:
	mkdir -p odin-out
	odin build odin/ -out:$(BIN) -define:CTYPE_VERSION=$(VERSION)

release:
	mkdir -p odin-out
	odin build odin/ -out:$(BIN) -define:CTYPE_VERSION=$(VERSION) -o:minimal

run: build
	./$(BIN)

test:
	odin test odin/ -define:CTYPE_VERSION=$(VERSION)

install: release
	install -d $(PREFIX)/bin $(PREFIX)/share/ctype
	install -m 755 $(BIN) $(PREFIX)/bin/ctype
	install -m 644 assets/words_en.txt $(PREFIX)/share/ctype/words.txt

uninstall:
	rm -f $(PREFIX)/bin/ctype
	rm -rf $(PREFIX)/share/ctype

clean:
	rm -rf odin-out

stats: build
	./$(BIN) --stats

reset: build
	./$(BIN) --reset-stats
