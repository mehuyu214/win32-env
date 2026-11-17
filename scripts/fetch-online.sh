#!/bin/bash
# fetch-online.sh — re-download third-party components from their original sources.
# This is a FALLBACK: the repo's archives/ already contain everything needed.
# Usage: scripts/fetch-online.sh [component ...]   (default: all)
#
# Every argument is processed (the old dispatcher honoured only $1 and
# silently dropped the rest). Exit status is 0 only if every requested
# component was actually fetched (or needs no download) in THIS run:
# downloads land in a temp file first and are moved into archives/ only on
# success, so an interrupted curl never leaves a truncated archive at the
# final path, and a failed re-download is reported as a failure even when
# an older archive is still present — an existence test is never treated
# as proof of a fresh download.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"; mkdir -p archives dl-tmp

fetch_one() { # $1 = url, $2 = archive file name
  local url="$1" name="$2" tmp="dl-tmp/$2.part"
  rm -f "$tmp"
  if ! curl -fL -o "$tmp" "$url"; then
    rm -f "$tmp"
    echo "ERROR: download failed: $url" >&2
    return 1
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "ERROR: download produced an empty file: $url" >&2
    return 1
  fi
  mv -f "$tmp" "archives/$name"
  echo "fetched archives/$name"
}

fetch_wine() {
  echo "Wine 11.21 x86 (Kron4ek/Wine-Builds, LGPL) ..."
  fetch_one \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-x86.tar.xz \
    wine-11.21-x86.tar.xz
}
fetch_wow64() {
  # One asset per component: asking for the plain wow64 build must not
  # also download the staging build (or fail because of it).
  echo "Wine 11.21 amd64 WoW64 (Kron4ek) ..."
  fetch_one \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-amd64-wow64.tar.xz \
    wine-11.21-amd64-wow64.tar.xz \
    || { echo "hint: the wow64 asset name may differ; check the 11.21 release page" >&2; return 1; }
}
fetch_wow64_staging() {
  echo "Wine 11.21 staging amd64 WoW64 (Kron4ek) ..."
  fetch_one \
    https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-staging-amd64-wow64.tar.xz \
    wine-11.21-staging-amd64-wow64.tar.xz \
    || { echo "hint: the staging wow64 asset name may differ; check the 11.21 release page" >&2; return 1; }
}
fetch_pabin() {
  echo "PulseAudio daemon tree (pa-bin/, Ubuntu 24.04 noble, amd64) ..."
  echo "The verified tree is archived in archives/pa-bin.tar.xz; setup.sh restores it."
  echo "To rebuild it from apt instead:"
  echo "  dpkg --add-architecture amd64 && apt-get update   # (native amd64: no-op)"
  echo "  apt-get download pulseaudio pulseaudio-utils libpulse0 libpulse-mainloop-glib0 libspeexdsp1 libtdb1 liborc-0.4-0t64"
  echo "  for d in *.deb; do dpkg-deb -x \$d pa-bin/; done"
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

if [ $# -eq 0 ]; then set -- all; fi
FAILED=0
for comp in "$@"; do
  case "$comp" in
    wine-11.21-x86) fetch_wine || FAILED=1;;
    wine-11.21-amd64-wow64) fetch_wow64 || FAILED=1;;
    wine-11.21-staging-amd64-wow64) fetch_wow64_staging || FAILED=1;;
    qemu-10.0.2-i386) fetch_qemu10;;
    sysroot32-root) fetch_sysroot;;
    pa-bin) fetch_pabin;;
    all) fetch_wine || FAILED=1; fetch_wow64 || FAILED=1; fetch_wow64_staging || FAILED=1; fetch_qemu10; fetch_sysroot; fetch_pabin;;
    *) echo "no online source for: $comp (use archives/ copy)" >&2; FAILED=1;;
  esac
done
if [ "$FAILED" != 0 ]; then
  echo "fetch-online: FAILED for at least one requested component (see above)" >&2
  exit 1
fi
