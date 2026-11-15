#!/bin/bash
# start-pa.sh — start the repo's private PulseAudio daemon (idempotent).
# Sink "game" 48kHz float32le, TCP 127.0.0.1:47130 + unix socket.
# Exit 0 when the daemon is up and the "game" sink is listed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VN32_ROOT="${VN32_ROOT:-$(cd "$HERE/.." && pwd)}"
PA_PORT="${PA_PORT:-47130}"
LOG="${PA_LOG:-$VN32_ROOT/logs/pa.log}"
mkdir -p "$(dirname "$LOG")" "$VN32_ROOT/pa"

# PulseAudio refuses to run when it cannot create its runtime symlink
# (the sandbox's write gate blocks ~/.config/pulse) — point the runtime
# dir at /tmp and make it private.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/pa-runtime}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

# Locate the daemon binary: repo-local extracted tree first, then the
# perf line's vendored tree (same noble extraction, this VM), then the
# system binary.
find_pa() {
  for b in "$VN32_ROOT/pa-bin/usr/bin/pulseaudio" \
           "/home/hatch/workspace/win32-perf/pa-bin/usr/bin/pulseaudio"; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  command -v pulseaudio 2>/dev/null
}
PA_BIN="$(find_pa)"
if [ -z "$PA_BIN" ]; then
  echo "start-pa.sh: no pulseaudio binary found (install pulseaudio, or extract the noble amd64 debs into $VN32_ROOT/pa-bin)" >&2
  exit 1
fi
PA_ROOT="$(cd "$(dirname "$PA_BIN")/../.." && pwd)"
PACTLD="${PA_ROOT}/usr/bin/pactl"
[ -x "$PACTLD" ] || PACTLD="pactl"

sink_up() {
  PULSE_SERVER="tcp:127.0.0.1:$PA_PORT" "$PACTLD" list sinks short 2>/dev/null | grep -q "game"
}
if sink_up; then echo "PulseAudio already up (sink 'game' on :$PA_PORT)"; exit 0; fi

# Render the daemon config from the template (socket path is repo-local).
sed -e "s|@ROOT@|$VN32_ROOT|g" -e "s|@PORT@|$PA_PORT|g" "$VN32_ROOT/pa/default.pa.tmpl" > /tmp/win32env-pa-default.pa

# Module search path: the modules live under
# <root>/usr/lib/pulse-<ver>/modules (68 .so files), while libpulsecore
# lives in <root>/usr/lib/x86_64-linux-gnu/pulseaudio — two different
# dirs, both needed (module dir via --dl-search-path, lib dir via
# LD_LIBRARY_PATH). The original script assumed both were the pulseaudio
# dir and the daemon died at module load ("Daemon startup without any
# loaded modules"); fixed 2026-11-16 after a VM replacement exposed it.
MODDIR="$(ls -d "$PA_ROOT"/usr/lib/pulse-*/modules 2>/dev/null | head -1)"
# Loader path: top lib dir + pulseaudio dir (libpulsecore) + the modules
# dir itself — several modules link helper libs that live next to them
# (e.g. module-native-protocol-tcp.so needs libprotocol-native.so, which
# sits in the modules dir; without it the protocol modules fail and the
# daemon comes up with no sockets at all — reproduced 2026-11-16).
LIBDIR="$PA_ROOT/usr/lib/x86_64-linux-gnu:$PA_ROOT/usr/lib/x86_64-linux-gnu/pulseaudio${MODDIR:+:$MODDIR}"
export LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ -n "$MODDIR" ]; then
  DL="--dl-search-path=$MODDIR"
else
  DL=""
fi
setsid nohup "$PA_BIN" -n --exit-idle-time=-1 -F /tmp/win32env-pa-default.pa $DL >> "$LOG" 2>&1 &
PA_PID=$!
for _ in $(seq 1 20); do
  sink_up && { echo "PulseAudio started (pid $PA_PID, sink 'game' on :$PA_PORT)"; exit 0; }
  sleep 1
done
echo "start-pa.sh: daemon did not bring up sink 'game' (see $LOG)" >&2
exit 1
