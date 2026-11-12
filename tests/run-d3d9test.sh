#!/bin/bash
# run-d3d9test.sh — Direct3D9 render-path bisect test for the 32-bit stack.
#
# Runs tests/d3d9test.exe (source: tests/d3d9test.c) under qemu-i386 + Wine.
# The test creates a window, then Direct3DCreate9 -> CreateDevice (HAL) ->
# Clear(magenta) -> Present in a loop, and reads back the front-buffer pixel.
#
# PASS = the test log contains:
#   Direct3DCreate9 -> <non-NULL>
#   CreateDevice HAL hr=0x00000000
#   DEVICE OK
#   frontbuffer(300,300) = 0xffff00ff
# FAIL at "Direct3DCreate9 null" = Wine got no GL context (check the sysroot
# GL closure: scripts/games/setup-game-sysroot.sh, docs/GAME-RUNBOOK.md,
# docs/SANOBA-ENC-REPORT.md §3).
#
# Usage:  DISPLAY=:99 tests/run-d3d9test.sh [variant-name]
# Env:    D3DTEST_PREFIX (default: $VN32_ROOT/wineprefix32-d3dtest, created fresh)
set -u
cd "$(dirname "$0")/.."
. scripts/env.sh
V="${1:-run}"
WORK="$(mktemp -d /tmp/d3d9test.XXXXXX)"
export WINEPREFIX="${D3DTEST_PREFIX:-$VN32_ROOT/wineprefix32-d3dtest}"
export WINEDEBUG=+d3d,+wgl,+loaddll
EXE_WIN='Z:'"$(echo "$VN32_ROOT/tests/d3d9test.exe" | sed 's|/|\\|g')"
cd "$WORK" || exit 1
"$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" "$EXE_WIN" \
  > "d3dtest_$V.wine.log" 2>&1 &
sleep 75
if command -v scrot >/dev/null && [ -n "${DISPLAY:-}" ]; then
  scrot -o "d3dtest_$V.png" 2>/dev/null || true
fi
sleep 45
pkill -f 'd3d9test\.exe' 2>/dev/null || true
sleep 2
echo "=== $V test log (workdir: $WORK) ==="
cat d3d9test.log 2>/dev/null || echo "(no d3d9test.log — Wine did not start the test)"
echo "=== $V wgl/d3d key lines ==="
grep -a -i "egl_init\|couldn't initialize OpenGL\|GL_RENDERER\|Direct3DCreate9\|CreateDevice\|err:wgl\|err:d3d" \
  "d3dtest_$V.wine.log" | grep -av 'not found' | head -20
