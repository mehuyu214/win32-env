#!/bin/bash
# fetch-online.sh — re-download third-party components from their original sources.
# This is a FALLBACK: the repo's archives/ already contain everything needed.
# Usage: scripts/fetch-online.sh [component ...]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"; mkdir -p archives dl-tmp
want(){ [ $# -eq 0 ] || { for c in "$@"; do [ "$c" = "$1" ] && return 0; done; return 1; }; }
# NOTE: want() usage below passes the component name as $1 via helper:
fetch_wine() {
  echo "Wine 11.21 x86 (Kron4ek/Wine-Builds, LGPL) ..."
  curl -fL -o archives/wine-11.21-x86.tar.xz \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-x86.tar.xz
}
fetch_wow64() {
  echo "Wine 11.21 amd64 WoW64 (Kron4ek) ..."
  curl -fL -o archives/wine-11.21-amd64-wow64.tar.xz \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-amd64-wow64.tar.xz || echo "wow64 asset name may differ; use archives/ copy"
  curl -fL -o archives/wine-11.21-staging-amd64-wow64.tar.xz \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-staging-amd64-wow64.tar.xz || echo "staging wow64 asset name may differ; use archives/ copy"
}
fetch_qemu10() {
  echo "QEMU 10.0.2 (Debian qemu-user, GPLv2) ..."
  echo "Original binaries: Debian 1:10.0.2+ds-2+deb13u1~bpo12+1 (bookworm-backports/trixie)."
  echo "Try: apt-get download qemu-user  on Debian 13, or browse https://deb.debian.org/debian/pool/main/q/qemu/"
  echo "The archived copy in archives/qemu-10.0.2-i386.tar.xz is the verified original; prefer it."
}
fetch_sysroot() {
  echo "32-bit sysroot (.deb set, Ubuntu 24.04 noble, i386) ..."
  echo "Exact .deb files are stored in sysroot32/debs/. To rebuild from apt:"
  echo "  dpkg --add-architecture i386 && apt-get update"
  echo "  apt-get download \$(ls sysroot32/debs/ | sed 's/_.*//')   # names = package list"
  echo "  for d in *.deb; do dpkg-deb -x \$d sysroot32/root/; done"
  echo "  ln -sf usr/lib sysroot32/root/lib   # if the loader path needs it (see docs)"
}
case "${1:-all}" in
  wine-11.21-x86) fetch_wine;;
  wine-11.21-amd64-wow64|wine-11.21-staging-amd64-wow64) fetch_wow64;;
  qemu-10.0.2-i386) fetch_qemu10;;
  sysroot32-root) fetch_sysroot;;
  all) fetch_wine; fetch_wow64; fetch_qemu10; fetch_sysroot;;
  *) echo "no online source for: $1 (use archives/ copy)" ;;
esac
