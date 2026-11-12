#!/bin/bash
# boot32.sh — initialise a FRESH 32-bit prefix (not needed when using the restored snapshot).
# Usage: WINEPREFIX=/path/to/new-prefix scripts/boot32.sh
set -euo pipefail
. "$(dirname "$0")/env.sh"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winegstreamer=;mfplat=;wineusb=}"
exec "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" wineboot --init
