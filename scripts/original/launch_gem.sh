#!/bin/bash
export DISPLAY=:99
export WINEPREFIX=$HOME/workspace/vn-trials/wineprefix-hybrid
WINE=$HOME/workspace/vn-trials/wow64/wine-11.21-amd64-wow64/bin/wine
cd $HOME/workspace/vn-trials/downloads/geminism/Trial086p
exec $WINE explorer /desktop=Geminism,1600x900 Geminism.exe >> $HOME/workspace/vn-trials/geminism-run4.log 2>&1
