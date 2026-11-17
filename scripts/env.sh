# Common environment for the restored 32-bit Wine/QEMU stack.
# Source this file:  . scripts/env.sh
# VN32_ROOT defaults to the repository root (parent of scripts/).
VN32_ROOT="${VN32_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
export VN32_ROOT
export QEMU10="$VN32_ROOT/qemu10/usr/bin/qemu-i386"
export QEMU8="$VN32_ROOT/qemu/usr/bin/qemu-i386-static"
export SYSROOT32="$VN32_ROOT/sysroot32/root"
export WINE32_HOME="$VN32_ROOT/wine32/wine-11.21-x86"
export WINEPREFIX="${WINEPREFIX:-$VN32_ROOT/wineprefix32}"
export Q32SUP="$VN32_ROOT/qemu10/q32sup"
# Generic recipe (docs/GAME-COMPAT.md): CPU model max,-avx2. AVX2 in the
# "max" model makes some titles die with illegal instructions (Majikoi);
# q32sup also reads Q32_CPU for the wrappers it generates, so exporting
# it here covers both the direct qemu launches and supervised execs.
export Q32_CPU="${Q32_CPU:-max,-avx2}"
export WINEDEBUG="${WINEDEBUG:--all}"
