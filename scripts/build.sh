#!/bin/bash
set -euo pipefail

DIST_DIR="dist"
VERSION=${VERSION:-dev}
DESCRIPTION="Terminal typing test"
MAINTAINER="en9inerd"
URL="https://github.com/en9inerd/ctype"

mkdir -p "$DIST_DIR"

targets=(
  "x86_64-linux-musl"
  "aarch64-linux-musl"
  "x86_64-macos"
  "aarch64-macos"
)

deb_arch_map() {
  case "$1" in
    x86_64-linux-musl)  echo "amd64" ;;
    aarch64-linux-musl) echo "arm64" ;;
    *) echo "" ;;
  esac
}

for target in "${targets[@]}"; do
  echo "Building ctype for $target (v$VERSION)"
  zig build -Doptimize=ReleaseFast -Dtarget="$target" -Dversion="$VERSION"

  staging=$(mktemp -d)
  cp zig-out/bin/ctype "$staging/ctype"
  cp assets/words_en.txt "$staging/words.txt"

  tar -czf "$DIST_DIR/ctype_${target}.tar.gz" -C "$staging" ctype words.txt
  rm -rf "$staging"

  deb_arch=$(deb_arch_map "$target")
  if [[ -n "$deb_arch" ]]; then
    pkg_dir=$(mktemp -d)
    mkdir -p "$pkg_dir/usr/local/bin"
    mkdir -p "$pkg_dir/usr/local/share/ctype"
    mkdir -p "$pkg_dir/DEBIAN"

    cp zig-out/bin/ctype "$pkg_dir/usr/local/bin/ctype"
    chmod 755 "$pkg_dir/usr/local/bin/ctype"
    cp assets/words_en.txt "$pkg_dir/usr/local/share/ctype/words.txt"

    cat > "$pkg_dir/DEBIAN/control" <<EOF
Package: ctype
Version: ${VERSION}
Architecture: ${deb_arch}
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
Homepage: ${URL}
Section: utils
Priority: optional
EOF

    deb_name="ctype_${VERSION}_${deb_arch}.deb"
    dpkg-deb --build --root-owner-group "$pkg_dir" "$DIST_DIR/$deb_name"
    rm -rf "$pkg_dir"
  fi
done

echo ""
echo "Built artifacts:"
ls -lh "$DIST_DIR/"
