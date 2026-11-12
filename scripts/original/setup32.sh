#!/bin/bash
exec > ~/workspace/vn-trials/qemu32-setup.log 2>&1
set -x
apt-get update
dpkg --add-architecture i386
apt-get update
apt-get install -y qemu-user xdotool ffmpeg libc6:i386 libstdc++6:i386 libx11-6:i386 libxext6:i386 libxrender1:i386 libxrandr2:i386 libxcursor1:i386 libxi6:i386 libxfixes3:i386 libxinerama1:i386 libfreetype6:i386 libfontconfig1:i386 libgl1:i386 libasound2t64:i386 libpulse0:i386 libdbus-1-3:i386 zlib1g:i386 libxkbcommon0:i386 libxcomposite1:i386 libxxf86vm1:i386
mkdir -p ~/workspace/vn-trials/wine32
curl -sL -o ~/workspace/vn-trials/wine32/wine-x86.tar.xz https://github.com/Kron4ek/Wine-Builds/releases/download/11.21/wine-11.21-x86.tar.xz
tar -xf ~/workspace/vn-trials/wine32/wine-x86.tar.xz -C ~/workspace/vn-trials/wine32
echo SETUP32_DONE
