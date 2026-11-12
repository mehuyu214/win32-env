#!/bin/bash
# setup.sh — restore the full 32-bit Windows execution environment from this repo.
# Usage:
#   scripts/setup.sh [--online] [--system-packages] [--verify]
#     (default)        extract everything from archives/ (offline, no downloads)
#     --online         if an archive is missing, try scripts/fetch-online.sh first
#     --system-packages  also install host tools (Xvfb, xdotool, scrot, fonts) via apt (needs sudo/root)
#     --verify         run scripts/verify.sh at the end
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ONLINE=0; SYSPKG=0; VERIFY=0
for a in "$@"; do case "$a" in
  --online) ONLINE=1;; --system-packages) SYSPKG=1;; --verify) VERIFY=1;;
  *) echo "unknown option: $a" >&2; exit 2;; esac; done

join_parts() { # $1 = base name in archives/ ; assembles $1.tar.xz from split parts if needed
  local base="$1"
  if [ -f "archives/$base.tar.xz" ]; then return 0; fi
  if ls archives/"$base".tar.xz.part-* >/dev/null 2>&1; then
    echo "  joining archives/$base.tar.xz from parts"
    cat archives/"$base".tar.xz.part-* > "archives/$base.tar.xz"
    return 0
  fi
  return 1
}
need() { # $1=base $2=human label
  if ! join_parts "$1"; then
    if [ "$ONLINE" = 1 ]; then scripts/fetch-online.sh "$1" || true; fi
  fi
  if [ ! -f "archives/$1.tar.xz" ]; then echo "MISSING archive: archives/$1.tar.xz ($2)" >&2; exit 1; fi
  ( cd archives && sha256sum -c "$1.tar.xz.sha256" )
}
extract() { # $1=base $2=dest $3=strip-components(0/1 via tar transform dir name $4)
  echo "extracting $1 -> $2"
  mkdir -p "$2"
  tar --no-same-owner -xJf "archives/$1.tar.xz" -C "$2" ${4:+--strip-components=1}
}

if [ "$SYSPKG" = 1 ]; then
  echo "== installing host packages (Xvfb/xdotool/scrot/fonts/gcc) =="
  SUDO=""; [ "$(id -u)" != 0 ] && SUDO="sudo"
  $SUDO apt-get update
  $SUDO apt-get install -y xvfb xdotool scrot fonts-noto-cjk gcc libc6-dev xz-utils tar coreutils procps
fi

echo "== verifying + extracting archives =="
need qemu-10.0.2-i386 "QEMU 10.0.2 i386"
need qemu-8.2.2-i386-static "QEMU 8.2.2 static i386"
need sysroot32-root "32-bit sysroot"
need wine-11.21-x86 "Wine 11.21 x86 (Kron4ek)"
need wineprefix32 "booted 32-bit Wine prefix"
need wine-11.21-amd64-wow64 "Wine 11.21 WoW64 (investigation)"
need wine-11.21-staging-amd64-wow64 "Wine 11.21 staging WoW64 (investigation)"

extract qemu-10.0.2-i386 qemu10-tmp 0; mv qemu10-tmp/qemu10-pkg/usr qemu10/ 2>/dev/null || { mkdir -p qemu10; mv qemu10-tmp/qemu10-pkg/usr qemu10/; }; rm -rf qemu10-tmp
extract qemu-8.2.2-i386-static qemu-tmp 0; mkdir -p qemu; mv qemu-tmp/qemu8-pkg/usr qemu/; rm -rf qemu-tmp
extract sysroot32-root sysroot32 0
extract wine-11.21-x86 wine32 0
extract wineprefix32 . 0
mkdir -p wow64
cp archives/wine-11.21-amd64-wow64.tar.xz archives/wine-11.21-staging-amd64-wow64.tar.xz wow64/
tar --no-same-owner -xJf wow64/wine-11.21-amd64-wow64.tar.xz -C wow64
tar --no-same-owner -xJf wow64/wine-11.21-staging-amd64-wow64.tar.xz -C wow64

echo "== building q32sup from source =="
mkdir -p qemu10/wrap
gcc -O2 -Wall -o qemu10/q32sup src/q32sup.c
chmod +x qemu10/q32sup qemu10/usr/bin/qemu-i386 sysroot32/root/lib/ld-linux.so.2 2>/dev/null || true
cp tools/noexec32.so qemu10/ 2>/dev/null || true

echo "== path fixups =="
# The restored prefix contains no absolute host paths except dosdevices z: -> / (portable).
# Old wrapper scripts from the original session are NOT restored into qemu10/wrap:
# q32sup regenerates them with this machine's paths on first run.
echo "SETUP_DONE root=$ROOT"
echo "Next: scripts/verify.sh   (quick checks)   |   scripts/run32.sh <exe>   (run a 32-bit Windows exe)"
[ "$VERIFY" = 1 ] && scripts/verify.sh
