#!/bin/sh
exec /home/hatch/workspace/vn-trials/qemu10/usr/bin/qemu-i386 -cpu max -L /home/hatch/workspace/vn-trials/sysroot32/root "/home/hatch/workspace/vn-trials/wtest/hello32" "$@"
