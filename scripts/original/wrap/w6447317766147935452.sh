#!/bin/sh
exec /home/hatch/workspace/vn-trials/qemu10/usr/bin/qemu-i386 -cpu max -L /home/hatch/workspace/vn-trials/sysroot32/root "/home/hatch/workspace/vn-trials/wine32/wine-11.21-x86/lib/wine/../../bin/wineserver" "$@"
