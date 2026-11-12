#!/bin/bash
# Launch an UNMODIFIED 32-bit Windows game on the q32sup/QEMU/Wine stack.
# Verified 2026-11-12 with the Sanoba Witch trial (title screen renders,
# audio plays, story progresses). Usage:
#   scripts/games/launch-game.sh 'Z:\path\to\game.exe' [logfile]
# Requires: base setup (scripts/setup.sh) + scripts/games/setup-game-sysroot.sh,
# and an X server (scripts/start-x.sh) on DISPLAY (default :99).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"

EXE="${1:?usage: launch-game.sh 'Z:\\path\\to\\game.exe' [logfile]}"
LOG="${2:-$VN32_ROOT/logs/game-launch.log}"
export DISPLAY="${DISPLAY:-:99}"

# 1) Japanese locale (directory form). Without it, Wine's CP932 conversion
#    under a non-Japanese locale garbles Shift_JIS game scripts
#    (Kirikiri: deterministic "Syntax error / Invalid character" deep in
#    MainWindow.tjs). LANG alone can fail setlocale; a real generated
#    locale + LOCPATH is required.
LOCALE_DIR="$VN32_ROOT/locales"
if [ ! -f "$LOCALE_DIR/ja_JP.UTF-8/LC_CTYPE" ]; then
  mkdir -p "$LOCALE_DIR"
  localedef -i ja_JP -c -f UTF-8 "$LOCALE_DIR/ja_JP.UTF-8"
fi
export LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 LOCPATH="$LOCALE_DIR"

# 2) Virtual audio: ALSA null device. With libasound (i386) in the sysroot,
#    Wine's mmdevapi selects winealsa and DirectSound buffers really stream
#    (silently) instead of throwing in game scripts (e.g. bgm buf.play()).
export ALSA_CONFIG_PATH="$HERE/asound-null.conf"

# 3) Software GL: Mesa llvmpipe from the sysroot (no GPU on this VM).
export __EGL_VENDOR_LIBRARY_DIRS="$SYSROOT32/usr/share/glvnd/egl_vendor.d"
export LIBGL_DRIVERS_PATH="$SYSROOT32/usr/lib/i386-linux-gnu/dri"

# 4) FRESH prefix. A prefix built during early bring-up can carry corrupted
#    WindowMetrics (max track size 6357197x6357112) that forces every window
#    to 65535x65535 and breaks all drawing. Never reuse such a prefix.
export WINEPREFIX="${WINEPREFIX:-$VN32_ROOT/wineprefix-games}"
if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
  echo "booting fresh prefix: $WINEPREFIX"
  WINEDEBUG=-all "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" \
    "$WINE32_HOME/bin/wine" wineboot --init >> "$LOG" 2>&1
  # wineboot's rundll32 child can linger under emulation; the prefix is
  # complete once system32 exists. Snapshot it for reuse:
  #   tar -cf wineprefix-games-pristine.tar -C "$VN32_ROOT" wineprefix-games
fi

export WINEDEBUG="${WINEDEBUG:--all}"
cd /tmp || exit 1
# Launch by ABSOLUTE Z:\ path: a relative/symlink path makes Kirikiri
# recurse its data path and die.
exec "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" \
  "$WINE32_HOME/bin/wine" "$EXE" >> "$LOG" 2>&1
