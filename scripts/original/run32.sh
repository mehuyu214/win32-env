#!/bin/bash
# usage: run32.sh <windows-exe-path> [args...]
Q=$HOME/workspace/vn-trials/qemu/usr/bin/qemu-i386-static
R=$HOME/workspace/vn-trials/sysroot32/root
W=$HOME/workspace/vn-trials/wine32/wine-11.21-x86
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix32
export WINEDEBUG=-all
exec $Q -L $R $W/bin/wine "$@"
