#!/bin/bash
# run32.sh — run a 32-bit Windows program under qemu-i386 + 32-bit Wine, supervised by q32sup.
# Usage: scripts/run32.sh <windows-exe> [args...]
# Environment: DISPLAY must point at an X server (start one with scripts/start-x.sh).
set -euo pipefail
. "$(dirname "$0")/env.sh"
if [ $# -lt 1 ]; then echo "usage: run32.sh <windows-exe> [args...]" >&2; exit 2; fi
exec "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" "$@"
