#!/bin/bash
# launch.sh — launch a 32-bit Windows exe inside a Wine virtual desktop (needed for Unity/games
# that stall when their window is never activated under a bare Xvfb with no window manager).
# Usage: scripts/launch.sh <windows-exe> [desktop-name] [WxH]
set -euo pipefail
. "$(dirname "$0")/env.sh"
EXE="${1:?usage: launch.sh <windows-exe> [name] [WxH]}"; NAME="${2:-App32}"; SIZE="${3:-1600x900}"
export DISPLAY="${DISPLAY:-:99}"
exec "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" explorer "/desktop=$NAME,$SIZE" "$EXE"
