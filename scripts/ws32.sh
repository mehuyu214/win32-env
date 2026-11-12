#!/bin/sh
# ws32.sh — wineserver wrapper; set WINESERVER=$PWD/scripts/ws32.sh if a tool needs it.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/qemu10/usr/bin/qemu-i386" -cpu max -L "$ROOT/sysroot32/root" "$ROOT/wine32/wine-11.21-x86/bin/wineserver" "$@"
