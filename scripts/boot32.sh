#!/bin/bash
# boot32.sh — initialise a FRESH 32-bit prefix (not needed when using the restored snapshot).
# Usage: WINEPREFIX=/path/to/new-prefix scripts/boot32.sh
#
# Wineserver lifecycle (verified 2026-11-17, FIXLOG §31): on this stack a
# wineserver spawned as a child of the wineboot client under the same
# q32sup NEVER writes user.reg / system.reg / userdef.reg — the boot
# "succeeds" (drive_c, kernel32.dll, .update-timestamp all appear) but
# the registry files stay missing, so later steps that edit user.reg
# (tools/set-audio-driver.py) fail on first use. A wineserver supervised
# independently (its own q32sup, foreground) serves the same client
# normally and writes all three .reg files when it idle-exits a few
# seconds after the client disconnects. This script therefore:
#   1. starts wineserver -f under its own q32sup,
#   2. runs wineboot --init as a client,
#   3. waits for the server to exit (wineserver -k if it lingers),
#   4. VERIFIES all three .reg files exist; exit 1 if any is missing.
set -euo pipefail
. "$(dirname "$0")/env.sh"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winegstreamer=;mfplat=;wineusb=}"
: "${WINEPREFIX:?set WINEPREFIX to the fresh prefix path}"
mkdir -p "$WINEPREFIX"
WINEPREFIX="$(cd "$WINEPREFIX" && pwd)"
export WINEPREFIX

WSLOG="$(mktemp /tmp/boot32-wineserver.XXXXXX.log)"

# The server's socket directory identifies THIS prefix's wineserver:
# wineserver chdirs into /tmp/.wine-<uid>/server-<dev>-<ino> (device and
# inode of the prefix directory, hex) and creates 'socket' there for as
# long as it runs (both facts verified 2026-11-17). qemu's cwd is that
# directory, which keeps other prefixes' servers out of the waits.
SRVDIR="${TMPDIR:-/tmp}/.wine-$(id -u)/server-$(printf '%x-%x' \
  "$(stat -c %d "$WINEPREFIX")" "$(stat -c %i "$WINEPREFIX")")"
srv_pids() {
  local pid
  for pid in $(pgrep -f 'bin/wineserver' 2>/dev/null || true); do
    if [ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" = "$SRVDIR" ]; then
      echo "$pid"
    fi
  done
}

# 1) Foreground wineserver under its own supervisor.
nohup "$Q32SUP" "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" \
  "$WINE32_HOME/bin/wineserver" -f > "$WSLOG" 2>&1 &
WS_PID=$!

server_up=0
for _ in $(seq 1 30); do
  if [ -n "$(srv_pids)" ] && [ -S "$SRVDIR/socket" ]; then server_up=1; break; fi
  kill -0 "$WS_PID" 2>/dev/null || break
  sleep 2
done
if [ "$server_up" != 1 ]; then
  echo "ERROR: wineserver did not start for $WINEPREFIX; log follows" >&2
  cat "$WSLOG" >&2 || true
  exit 1
fi

# 2) Client boot. A non-zero exit is recorded, not fatal yet: the server
#    still has to be waited out and the registry verified below.
boot_rc=0
"$Q32SUP" "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" \
  "$WINE32_HOME/bin/wine" wineboot --init || boot_rc=$?

# 3) Wait for the server to idle-exit and save the registry; ask it to
#    shut down cleanly if it lingers, and only then stop our own server
#    processes (exact PIDs, this prefix only).
for _ in $(seq 1 18); do
  [ -z "$(srv_pids)" ] && break
  sleep 5
done
if [ -n "$(srv_pids)" ]; then
  "$Q32SUP" "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" \
    "$WINE32_HOME/bin/wineserver" -k || true
  for _ in $(seq 1 6); do
    [ -z "$(srv_pids)" ] && break
    sleep 5
  done
fi
if [ -n "$(srv_pids)" ]; then
  echo "WARNING: wineserver for $WINEPREFIX still running; stopping it" >&2
  kill $(srv_pids) 2>/dev/null || true
  sleep 3
fi

# 4) Verify the registry files were actually written — with real
#    content, not the stubs a freshly started wineserver writes before
#    any client runs (measured 2026-11-17: stubs are user.reg 134 B /
#    system.reg 512 B / userdef.reg 123 B and user.reg has no sections;
#    a real post-wineboot save is ~21 KB / ~1.8 MB / ~4 KB with dozens
#    of sections. The floors below sit far between the two.)
missing=0
for f in user.reg system.reg userdef.reg; do
  if [ ! -s "$WINEPREFIX/$f" ]; then
    echo "ERROR: $WINEPREFIX/$f missing or empty after boot" >&2
    missing=1
  fi
done
if [ "$missing" = 0 ]; then
  if [ "$(wc -c < "$WINEPREFIX/user.reg")" -lt 2048 ] \
     || [ "$(wc -c < "$WINEPREFIX/system.reg")" -lt 100000 ] \
     || [ "$(wc -c < "$WINEPREFIX/userdef.reg")" -lt 1024 ] \
     || [ "$(grep -c '^\[' "$WINEPREFIX/user.reg")" -lt 2 ]; then
    echo "ERROR: registry files in $WINEPREFIX are still start-up stubs, not a post-boot save" >&2
    missing=1
  fi
fi
if [ "$missing" != 0 ]; then
  echo "ERROR: fresh-prefix boot did not produce a complete registry in $WINEPREFIX (wineserver log: $WSLOG)" >&2
  exit 1
fi
if [ "$boot_rc" != 0 ]; then
  echo "ERROR: wineboot exited with status $boot_rc for $WINEPREFIX" >&2
  exit 1
fi
rm -f "$WSLOG"
echo "boot32: prefix initialised and registry verified: $WINEPREFIX"
