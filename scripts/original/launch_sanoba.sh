#!/bin/bash
Q=$HOME/workspace/vn-trials/qemu/usr/bin/qemu-i386-static
R=$HOME/workspace/vn-trials/sysroot32/root
W=$HOME/workspace/vn-trials/wine32/wine-11.21-x86
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix32
export WINEDEBUG=-all
export DISPLAY=:99
cd $HOME/workspace/vn-trials/downloads/sanoba/*/ || exit 1
pwd >> $HOME/workspace/vn-trials/sanoba-qemu.log
exec $Q -cpu max -L $R $W/bin/wine explorer /desktop=Sanoba,1600x900 sanoba_trial.exe >> $HOME/workspace/vn-trials/sanoba-qemu.log 2>&1
