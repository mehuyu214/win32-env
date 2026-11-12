#!/bin/bash
# verify.sh — staged verification of the restored environment.
#   --quick  : stages 1-4 only (seconds)
#   (default): stages 1-5 (stage 5 boots Wine cmd under q32sup; allow several minutes on 1.5 cores)
set -uo pipefail
. "$(dirname "$0")/env.sh"
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
ng(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "[1] native 32-bit ELF (informational: expected to segfault on the original sandbox)"
if "$VN32_ROOT/tests/hello32" >/dev/null 2>&1; then echo "  native exec works on this host (not required)"; else echo "  native exec blocked/segfault (matches original environment)"; fi

echo "[2] qemu-i386 runs a 32-bit Linux binary"
OUT="$("$QEMU10" -L "$SYSROOT32" "$VN32_ROOT/tests/hello32" 2>/dev/null)"
[ "$OUT" = "hello32-native" ] && ok "qemu hello32: $OUT" || ng "qemu hello32 (got: $OUT)"

echo "[3] qemu-i386 + sysroot runs 32-bit Wine --version"
OUT="$("$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" --version 2>/dev/null)"
echo "$OUT" | grep -q "wine-11.21" && ok "wine version: $OUT" || ng "wine version (got: $OUT)"

echo "[4] q32sup binary present and executable"
[ -x "$Q32SUP" ] && ok "q32sup: $Q32SUP" || ng "q32sup missing — run scripts/setup.sh"

if [ "${1:-}" != "--quick" ]; then
  echo "[5] q32sup end-to-end: wine cmd /c echo under supervision (slow; timeout 900s)"
  OUT="$(timeout 900 "$Q32SUP" "$QEMU10" -cpu max -L "$SYSROOT32" "$WINE32_HOME/bin/wine" cmd /c "echo Q32SUP_OK" 2>/tmp/q32-verify.err)"
  echo "$OUT" | grep -q "Q32SUP_OK" && ok "q32sup wine cmd: Q32SUP_OK" || { ng "q32sup wine cmd (see /tmp/q32-verify.err)"; }
fi
echo "verify: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
