#!/bin/bash
Q=$HOME/workspace/vn-trials/qemu/usr/bin/qemu-i386-static
R=$HOME/workspace/vn-trials/sysroot32/root
W=$HOME/workspace/vn-trials/wine32/wine-11.21-x86
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix32
export WINEDLLOVERRIDES="winegstreamer=;mfplat=;wineusb="
exec $Q -cpu max -L $R $W/bin/wine wineboot --init >> $HOME/workspace/vn-trials/wineboot2.log 2>&1
