#!/bin/bash
# Launch an UNMODIFIED 32-bit Windows game on the q32sup/QEMU/Wine stack.
# Verified 2026-11-12 with the Sanoba Witch trial (title screen renders,
# audio plays, story progresses). Usage:
#   scripts/games/launch-game.sh 'Z:\path\to\game.exe' [logfile]
# Environment:
#   AUDIO_ROUTE=alsa-null (default; sound streams to a silent ALSA device)
#             | pulse     (audible via Wine's winepulse driver — works in
#                          winecfg but Cave Story's audio init fails with
#                          "Failed to create context" in-game, 2026-11-16)
#             | alsa-pulse (audible via winealsa + the ALSA PulseAudio
#                          plugin; guest snd_pcm_open("default") verified
#                          2026-11-16: 440 Hz sine reached the "game"
#                          sink, RMS 0.11027)
#   GAME_WINEPREFIX=<path>  game prefix (default: <repo>/wineprefix-games).
#                          NOTE: env.sh exports WINEPREFIX=<repo>/wineprefix32
#                          (the restored snapshot prefix); games must NOT
#                          inherit it — that was the old "prefix mixup" bug.
#   WINEDLLOVERRIDES        (default: mscoree=d — a missing Wine Mono would
#                          otherwise block startup with a modal install dialog)
# Requires: base setup (scripts/setup.sh) + scripts/games/setup-game-sysroot.sh,
# and an X server (scripts/start-x.sh) on DISPLAY (default :99).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"
# QEMU override for A/B work: Q32_QEMU=<path to qemu-i386> (default: the
# repo's QEMU 10.0.2). The override is also honoured by the wineboot step.
QEMU10="${Q32_QEMU:-$QEMU10}"

EXE="${1:?usage: launch-game.sh 'Z:\\path\\to\\game.exe' [logfile]}"
LOG="${2:-$VN32_ROOT/logs/game-launch.log}"
# The log path is resolved against the CURRENT directory: make it absolute
# now, before the launcher cds into the game directory below.
case "$LOG" in /*) ;; *) LOG="$(pwd)/$LOG";; esac
export DISPLAY="${DISPLAY:-:99}"

# 1) Japanese locale (directory form). Without it, Wine's CP932 conversion
#    under a non-Japanese locale garbles Shift_JIS game scripts
#    (Kirikiri: deterministic "Syntax error / Invalid character" deep in
#    MainWindow.tjs). LANG alone can fail setlocale; a real generated
#    locale + LOCPATH is required.
LOCALE_DIR="$VN32_ROOT/locales"
if [ ! -f "$LOCALE_DIR/ja_JP.UTF-8/LC_CTYPE" ]; then
  mkdir -p "$LOCALE_DIR"
  # Fail loudly: a silent localedef failure leaves LOCPATH pointing at a
  # locale that was never generated, and the game garbles Shift_JIS text.
  if ! localedef -i ja_JP -c -f UTF-8 "$LOCALE_DIR/ja_JP.UTF-8" \
     || [ ! -f "$LOCALE_DIR/ja_JP.UTF-8/LC_CTYPE" ]; then
    echo "ERROR: localedef failed to generate ja_JP.UTF-8 in $LOCALE_DIR; aborting" >&2
    exit 1
  fi
fi
export LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 LOCPATH="$LOCALE_DIR"

# 2) Audio route.
AUDIO_ROUTE="${AUDIO_ROUTE:-alsa-null}"
if [ "$AUDIO_ROUTE" = "pulse" ]; then
  # Audible audio: start the repo PulseAudio daemon (idempotent) and
  # point Wine at it. Target: a sink-input appears on the "game" sink
  # and the monitor capture carries real BGM (verify per game).
  "$VN32_ROOT/scripts/start-pa.sh" || echo "WARNING: start-pa.sh failed; continuing" >&2
  export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:47130}"
  export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-750}"
  unset ALSA_CONFIG_PATH
elif [ "$AUDIO_ROUTE" = "alsa-pulse" ]; then
  # Audible audio via winealsa: the ALSA "default" PCM is the PulseAudio
  # plugin (pa/alsa-pulse.conf), so Wine's DirectSound buffers stream to
  # the repo PA daemon's "game" sink. The pulse ALSA modules live in the
  # sysroot's alsa-lib dir (installed by setup-game-sysroot.sh); the
  # plugin needs libpulse from pa-libs on the guest loader path (below).
  "$VN32_ROOT/scripts/start-pa.sh" || echo "WARNING: start-pa.sh failed; continuing" >&2
  export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:47130}"
  export PULSE_LATENCY_MSEC="${PULSE_LATENCY_MSEC:-750}"
  export ALSA_CONFIG_PATH="$VN32_ROOT/pa/alsa-pulse.conf"
else
  # Virtual audio: ALSA null device. With libasound (i386) in the sysroot,
  # Wine's mmdevapi selects winealsa and DirectSound buffers really stream
  # (silently) instead of throwing in game scripts (e.g. bgm buf.play()).
  export ALSA_CONFIG_PATH="$HERE/asound-null.conf"
fi

# 3) Software GL: Mesa llvmpipe from the sysroot (no GPU on this VM).
export __EGL_VENDOR_LIBRARY_DIRS="$SYSROOT32/usr/share/glvnd/egl_vendor.d"
export LIBGL_DRIVERS_PATH="$SYSROOT32/usr/lib/i386-linux-gnu/dri"

# 4) Game prefix. Never reuse the restored snapshot prefix (wineprefix32)
#    for games, and never reuse a prefix whose WindowMetrics are poisoned
#    (max track size 6357197x6357112 forces every window to 65535x65535
#    and breaks all drawing). A fresh prefix is booted on first use.
# Wine Mono modal: on a prefix without Mono, session init pops a blocking
# "install Wine Mono?" dialog and the game never starts. This export MUST
# precede the wineboot below — a fresh-prefix boot shows the dialog before
# any game starts (reproduced 2026-11-16 on wineprefix-games). No .NET is
# needed for these games; disable it unless the caller says otherwise.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=d}"
export WINEPREFIX="${GAME_WINEPREFIX:-$VN32_ROOT/wineprefix-games}"
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
  echo "booting fresh prefix: $WINEPREFIX"
  WINEDEBUG=-all "$Q32SUP" "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" \
    "$WINE32_HOME/bin/wine" wineboot --init >> "$LOG" 2>&1
  # wineboot's rundll32 child can linger under emulation; the prefix is
  # complete once system32 exists. Snapshot it for reuse:
  #   tar -cf wineprefix-games-pristine.tar -C "$VN32_ROOT" wineprefix-games
  # Re-check: under `set -u` a failed wineboot does not abort this script,
  # and exec'ing the game into a half-built prefix fails much less clearly.
  if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
    echo "ERROR: wineboot did not complete: $WINEPREFIX/drive_c/windows/system32/kernel32.dll still missing (see $LOG)" >&2
    exit 1
  fi
fi

# For the pulse / alsa-pulse routes, make the prefix select the matching
# driver (direct user.reg edit while wineserver is stopped — `wine reg add`
# does not persist on this stack), and give the guest loader the i386
# PulseAudio runtime. The game sysroot has no libpulse.so.0, so without
# pa-libs Wine's winepulse.so cannot load and the ALSA pulse plugin cannot
# connect (reproduced 2026-11-16: "Cannot open shared library
# libasound_module_conf_pulse.so", no sink-input on the PA daemon).
# LD_LIBRARY_PATH is passed through QEMU into the guest; the guest loader
# resolves the host-absolute path via QEMU's prefix fallback. Caller-set
# entries (e.g. a QEMU 7.2 host lib dir) are kept ahead of pa-libs.
if [ "$AUDIO_ROUTE" = "pulse" ] || [ "$AUDIO_ROUTE" = "alsa-pulse" ]; then
  if [ "$AUDIO_ROUTE" = "pulse" ]; then _drv=pulse; else _drv=alsa; fi
  if [ -x "$VN32_ROOT/tools/set-audio-driver.py" ]; then
    "$VN32_ROOT/tools/set-audio-driver.py" "$WINEPREFIX" "$_drv" >> "$LOG" 2>&1 \
      || echo "WARNING: set-audio-driver.py failed; audio driver not set" | tee -a "$LOG" >&2
  else
    echo "WARNING: $VN32_ROOT/tools/set-audio-driver.py missing; audio driver NOT set (game will be silent)" | tee -a "$LOG" >&2
  fi
  export LD_LIBRARY_PATH="$VN32_ROOT/pa-libs/usr/lib/i386-linux-gnu:$VN32_ROOT/pa-libs/usr/lib/i386-linux-gnu/pulseaudio${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export WINEDEBUG="${WINEDEBUG:--all}"
# 5) cd into the game's own directory, derived from the absolute Z:\ path
#    (or the C:\ path, resolved through the prefix's drive_c).
#    Several engines (GameMaker, Kirikiri-adjacent) read data files relative
#    to the cwd; the old `cd /tmp` broke them (e.g. Warning Forever could
#    not open data.bin). The launch itself stays on the absolute Z:\ path:
#    a relative/symlink path makes Kirikiri recurse its data path and die.
case "$EXE" in
  /*) GAMEDIR="$(dirname "$EXE")" ;;
  Z:*|z:*) _u="${EXE#Z:}"; _u="${_u#z:}"; _u="${_u//\\//}"; GAMEDIR="$(dirname "/$_u")" ;;
  C:*|c:*) _u="${EXE#C:}"; _u="${_u#c:}"; _u="${_u//\\//}"; GAMEDIR="$(dirname "$WINEPREFIX/drive_c$_u")" ;;
  *) GAMEDIR="" ;;
esac
if [ -n "${GAMEDIR:-}" ] && [ -d "$GAMEDIR" ]; then
  cd "$GAMEDIR" || exit 1
else
  echo "WARNING: game dir '$GAMEDIR' not found; staying in $(pwd)" >&2
fi
exec "$Q32SUP" "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" \
  "$WINE32_HOME/bin/wine" "$EXE" >> "$LOG" 2>&1
