#!/bin/bash
# launch2.sh: parameterized Sanoba launch for performance benches (sanoba-audio line, :113)
# env knobs: LP_NUM_THREADS, PULSE_LATENCY_MSEC, PULSE_SERVER, Q32_QEMU_BIN, GALLIUM_HUD, vblank_mode, LOGFILE
set -u
. "$HOME/workspace/sanoba-audio/scripts/common.env"
SA=$HOME/workspace/sanoba-audio
export WINEPREFIX="$SA/prefix"
export Q32_QEMU="${Q32_QEMU_BIN:-$VT/qemu/usr/bin/qemu-i386-static}"
export Q32_WRAPDIR="$SA/mywrap"
export Q32_SYSROOT="$VT/sysroot32/root"
SUP="$SA/q32sup-mine"
QEMU="$VT/qemu10/usr/bin/qemu-i386 -cpu max -L $VT/sysroot32/root"
LOGFILE="${LOGFILE:-/dev/null}"
[ -n "${LAUNCH_PULSE_SERVER:-}" ] && export PULSE_SERVER="$LAUNCH_PULSE_SERVER"
cd /tmp || exit 1
setsid nohup $SUP $QEMU "$WINEBIN" 'Z:\home\hatch\workspace\sanoba-audio\game\sanoba\sanoba_trial.exe' >> "$LOGFILE" 2>&1 &
echo $! > "$SA/logs/game.pid"
echo "launched sup-pid $! Q32_QEMU=$Q32_QEMU LP=${LP_NUM_THREADS:-def} PLM=${PULSE_LATENCY_MSEC:-def} PS=$PULSE_SERVER log=$LOGFILE"
