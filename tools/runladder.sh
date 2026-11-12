#!/bin/bash
# runladder.sh <rid> [VAR=VAL ...] -- kill game, relaunch with env, wait title, runbench
SA=$HOME/workspace/sanoba-audio; W32=$HOME/workspace/win32-env; RID=$1; shift
GPID_OLD=$(cat $SA/logs/game.pid 2>/dev/null); kill $GPID_OLD 2>/dev/null
for p in $(pgrep -f qemu); do if grep -qz "WINEPREFIX=/home/hatch/workspace/sanoba-audio/prefix" /proc/$p/environ 2>/dev/null; then kill $p 2>/dev/null; fi; done
sleep 4; rm -f $SA/mywrap/*.sh
env "$@" LOGFILE=$SA/logs/launch-$RID.log $W32/tools/launch2.sh
for i in $(seq 1 16); do sleep 15; timeout 20 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -i :113 -frames:v 1 /tmp/poll-$RID.png < /dev/null; D=$(timeout 20 python3 ~/workspace/sanoba-play/scripts/shot.py /tmp/poll-$RID.png | grep -o 'distinct_sampled=[0-9]*' | cut -d= -f2); [ "${D:-0}" -gt 5000 ] && { echo "title at poll $i"; break; }; done
sleep 15
GPID=""; for p in $(pgrep -f qemu); do if grep -qz "WINEPREFIX=/home/hatch/workspace/sanoba-audio/prefix" /proc/$p/environ 2>/dev/null && grep -qz "sanoba_trial" /proc/$p/cmdline 2>/dev/null && [ "$(ls /proc/$p/task | wc -l)" -gt 20 ]; then GPID=$p; fi; done
echo "game pid=$GPID"
$SA/scripts/runbench.sh $RID $GPID 60
cat $SA/logs/run-$RID.log
