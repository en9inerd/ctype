#!/bin/sh
set -eu

REPO="en9inerd/ctype"
PREFIX="${CTYPE_PREFIX:-${HOME}/.local}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/ctype"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

detect_target() {
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os_tag="macos" ;;
    Linux)  os_tag="linux" ;;
    *)      die "unsupported OS: $os" ;;
  esac

  case "$arch" in
    x86_64|amd64)   arch_tag="x86_64" ;;
    arm64|aarch64)   arch_tag="aarch64" ;;
    *)               die "unsupported arch: $arch" ;;
  esac

  printf '%s-%s' "$arch_tag" "$os_tag"
}

latest_version() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/'
  else
    die "need curl or wget"
  fi
}

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1"
  else
    wget -qO "$2" "$1"
  fi
}

main() {
  target="$(detect_target)"
  version="${1:-}"

  if [ -z "$version" ]; then
    printf 'fetching latest version...\n'
    version="$(latest_version)"
    [ -n "$version" ] || die "could not determine latest version"
  fi

  # strip leading v if present
  version_bare="${version#v}"
  tag="v${version_bare}"

  url="https://github.com/${REPO}/releases/download/${tag}/ctype_${target}.tar.gz"
  printf 'downloading %s\n' "$url"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  download "$url" "${tmpdir}/ctype.tar.gz"
  tar xzf "${tmpdir}/ctype.tar.gz" -C "$tmpdir"

  mkdir -p "$BIN_DIR" "$SHARE_DIR"
  install -m 755 "${tmpdir}/ctype" "$BIN_DIR/ctype"
  install -m 644 "${tmpdir}/words.txt" "$SHARE_DIR/words.txt"

  printf 'installed ctype %s to %s\n' "$tag" "$PREFIX"

  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) printf 'note: add %s to your PATH\n' "$BIN_DIR" ;;
  esac
}

main "$@"
