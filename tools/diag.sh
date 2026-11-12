#!/bin/bash
# diag.sh -- fresh base instance; A: audio at ~4min age; B: video 60s; C: audio again (~7min age). Top-procs snapshots per window.
SA=$HOME/workspace/sanoba-audio; PB=$SA/pa-bin; W32=$HOME/workspace/win32-env
export LD_LIBRARY_PATH=$PB/usr/lib/x86_64-linux-gnu:$PB/usr/lib/x86_64-linux-gnu/pulseaudio PULSE_SERVER=tcp:127.0.0.1:47130
DL=$SA/logs/run-diag.log; { echo "DIAG age/order test"; date '+start %F %T epoch=%s'; } > $DL
kill $(cat $SA/logs/game.pid) 2>/dev/null
for p in $(pgrep -f qemu); do if grep -qz "WINEPREFIX=/home/hatch/workspace/sanoba-audio/prefix" /proc/$p/environ 2>/dev/null; then kill $p 2>/dev/null; fi; done
sleep 4; rm -f $SA/mywrap/*.sh
PULSE_LATENCY_MSEC=750 LP_NUM_THREADS=1 LOGFILE=$SA/logs/launch-diag.log $W32/tools/launch2.sh >> $DL
for i in $(seq 1 16); do sleep 15; timeout 20 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -i :113 -frames:v 1 /tmp/poll-d.png < /dev/null; D=$(timeout 20 python3 ~/workspace/sanoba-play/scripts/shot.py /tmp/poll-d.png | grep -o 'distinct_sampled=[0-9]*' | cut -d= -f2); [ "${D:-0}" -gt 5000 ] && break; done
sleep 15; echo "boot-to-title done epoch=$(date +%s)" >> $DL
tops(){ echo "-- top procs $(date +%T)" >> $DL; ps aux --sort=-%cpu | head -6 | awk '{printf "%s %s%% %s\n",$2,$3,$11}' >> $DL; }
capwin(){ # $1=label $2=outfile
  tops; U0=$(grep -c -i underrun $SA/logs/pulseaudio.log)
  timeout 70 $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > $2 2>/dev/null & sleep 60; pkill -f "parec -d game.monitor"; sleep 1
  U1=$(grep -c -i underrun $SA/logs/pulseaudio.log); echo "$1 underrun delta: $((U1-U0))" >> $DL
  timeout 60 python3 $W32/tools/delivery_ratio.py $2 >> $DL 2>&1; }
capwin "A audio@fresh" $SA/logs/cap-dA.raw
tops; timeout 70 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 20 -i :113 -t 60 -c:v libx264 -preset ultrafast $SA/logs/dB-vid.mp4 < /dev/null; echo "B video done" >> $DL
capwin "C audio@aged" $SA/logs/cap-dC.raw
date '+end %F %T epoch=%s' >> $DL; echo DIAG DONE >> $DL; cat $DL
