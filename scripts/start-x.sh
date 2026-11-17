#!/bin/bash
# start-x.sh — start the virtual display used by the original environment (Xvfb :99, 1600x900x24),
# plus a resident twm window manager on it (generic recipe; see ensure_twm below).
# Readiness is probed with whatever tool exists (xdpyinfo, else xdotool,
# else the X socket) and RE-probed after spawning: "ready" is printed only
# when the display actually answers. (The old version assumed xdpyinfo —
# absent on some hosts, which made its probe fail unconditionally — and
# printed "ready" after a fixed sleep even if Xvfb had died instantly.)
set -euo pipefail
DISP=:99
probe() {
  if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo -display "$DISP" >/dev/null 2>&1
  elif command -v xdotool >/dev/null 2>&1; then
    DISPLAY="$DISP" xdotool getdisplaygeometry >/dev/null 2>&1
  else
    [ -S "/tmp/.X11-unix/X${DISP#:}" ]
  fi
}
# Generic recipe: a window manager must be resident on the game display —
# on a bare Xvfb some titles render but ignore all input (Sakura no Toki).
# twm is started detached; if one is already managing $DISP the new twm
# exits immediately on its own (logged to /tmp/twm99.log), so this is
# safe to run on every start-x invocation.
ensure_twm() {
  if ! command -v twm >/dev/null 2>&1; then
    echo "WARNING: twm not found; no window manager on $DISP (some titles will ignore input)" >&2
    return 0
  fi
  DISPLAY="$DISP" setsid twm >/tmp/twm99.log 2>&1 &
}
if probe; then
  ensure_twm
  echo "DISPLAY=$DISP ready (already running)"
  exit 0
fi
Xvfb "$DISP" -screen 0 1600x900x24 >/tmp/xvfb99.log 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
  if probe; then
    ensure_twm
    echo "DISPLAY=$DISP ready"
    exit 0
  fi
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "ERROR: Xvfb on $DISP exited immediately; see /tmp/xvfb99.log" >&2
    exit 1
  fi
  sleep 0.1
done
echo "ERROR: Xvfb on $DISP did not become ready within 5s; see /tmp/xvfb99.log" >&2
exit 1
