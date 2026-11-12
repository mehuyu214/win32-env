#!/bin/bash
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix32
export WINEDEBUG=-all
export DISPLAY=:99
cd /tmp || exit 1
exec $HOME/workspace/vn-trials/qemu10/q32sup $HOME/workspace/vn-trials/qemu10/usr/bin/qemu-i386 -cpu max -L $HOME/workspace/vn-trials/sysroot32/root $HOME/workspace/vn-trials/wine32/wine-11.21-x86/bin/wine explorer '/desktop=Sanoba,1600x900' 'Z:\home\hatch\workspace\vn-trials\sanoba-real\sanoba_trial.exe' >> $HOME/workspace/vn-trials/sanoba-qemu12.log 2>&1
