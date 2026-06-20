#!/bin/bash
set -euo pipefail

DIST_DIR="dist"
VERSION=${VERSION:-dev}
TARGET_FILTER=${TARGET_FILTER:-}       # e.g. "linux" or "darwin" — empty = all
DESCRIPTION="Terminal typing test"
MAINTAINER="en9inerd"
URL="https://github.com/en9inerd/ctype"

# detect native arch for cross-compile lld check
case "$(uname -m)" in
  x86_64)  NATIVE_ARCH="amd64" ;;
  aarch64) NATIVE_ARCH="arm64" ;;
  arm64)   NATIVE_ARCH="arm64" ;;
  *)       NATIVE_ARCH="unknown" ;;
esac

mkdir -p "$DIST_DIR" odin-out

targets=(
  "linux_amd64:x86_64-linux:amd64"
  "linux_arm64:aarch64-linux:arm64"
  "darwin_amd64:x86_64-macos:"
  "darwin_arm64:aarch64-macos:"
)

for entry in "${targets[@]}"; do
  IFS=':' read -r odin_target artifact_target deb_arch <<< "$entry"

  if [[ -n "$TARGET_FILTER" && "$odin_target" != *"$TARGET_FILTER"* ]]; then
    continue
  fi

  # use lld when cross-compiling between linux architectures
  linker_flag=""
  if [[ "$odin_target" == linux_* ]] && [[ "$odin_target" != *"$NATIVE_ARCH"* ]]; then
    linker_flag="-linker:lld"
  fi

  echo "Building ctype for $odin_target (v$VERSION)"
  odin build odin/ -out:odin-out/ctype -target:$odin_target \
    -define:CTYPE_VERSION="$VERSION" -o:aggressive $linker_flag

  staging=$(mktemp -d)
  cp odin-out/ctype "$staging/ctype"
  cp assets/words_en.txt "$staging/words.txt"

  tar -czf "$DIST_DIR/ctype_${artifact_target}.tar.gz" -C "$staging" ctype words.txt
  rm -rf "$staging"

  if [[ -n "$deb_arch" ]]; then
    pkg_dir=$(mktemp -d)
    mkdir -p "$pkg_dir/usr/local/bin"
    mkdir -p "$pkg_dir/usr/local/share/ctype"
    mkdir -p "$pkg_dir/DEBIAN"

    cp odin-out/ctype "$pkg_dir/usr/local/bin/ctype"
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
