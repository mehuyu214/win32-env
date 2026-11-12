#!/bin/bash
# start-x.sh — start the virtual display used by the original environment (Xvfb :99, 1600x900x24).
set -euo pipefail
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
  Xvfb :99 -screen 0 1600x900x24 >/tmp/xvfb99.log 2>&1 &
  sleep 1
fi
echo "DISPLAY=:99 ready"
