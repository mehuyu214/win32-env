#!/bin/bash
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix32
export WINESERVER=$HOME/workspace/vn-trials/ws32.sh
export WINEDEBUG=-all
Q10=$HOME/workspace/vn-trials/qemu10/usr/bin/qemu-i386
R=$HOME/workspace/vn-trials/sysroot32/root
W=$HOME/workspace/vn-trials/wine32/wine-11.21-x86
exec $Q10 -cpu max -L $R $W/bin/wine wineboot --init >> $HOME/workspace/vn-trials/wineboot5.log 2>&1
