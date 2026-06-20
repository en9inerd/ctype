#!/bin/bash
set -euo pipefail

VERSION="${1:?version required}"
DIST="${2:?dist dir required}"
TAP_REPO="${3:?tap repo URL required}"

sha_of() { shasum -a 256 "${DIST}/$1" | awk '{print $1}'; }

SHA_LINUX_X86_64=$(sha_of ctype_x86_64-linux.tar.gz)
SHA_LINUX_ARM64=$(sha_of ctype_aarch64-linux.tar.gz)
SHA_MACOS_X86_64=$(sha_of ctype_x86_64-macos.tar.gz)
SHA_MACOS_ARM64=$(sha_of ctype_aarch64-macos.tar.gz)

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git clone "$TAP_REPO" "$TMPDIR/tap"
cp packaging/homebrew/ctype.rb "$TMPDIR/tap/Formula/ctype.rb"

sed -i.bak \
  -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
  -e "s/SHA256_LINUX_X86_64/${SHA_LINUX_X86_64}/g" \
  -e "s/SHA256_LINUX_ARM64/${SHA_LINUX_ARM64}/g" \
  -e "s/SHA256_MACOS_X86_64/${SHA_MACOS_X86_64}/g" \
  -e "s/SHA256_MACOS_ARM64/${SHA_MACOS_ARM64}/g" \
  "$TMPDIR/tap/Formula/ctype.rb"
rm -f "$TMPDIR/tap/Formula/ctype.rb.bak"

cd "$TMPDIR/tap"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Formula/ctype.rb
git commit -m "ctype ${VERSION}" || true
git push

echo "Updated homebrew-tap Formula/ctype.rb to v${VERSION}"
