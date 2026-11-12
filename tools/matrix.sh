#!/bin/bash
SA=$HOME/workspace/sanoba-audio; PB=$SA/pa-bin; W32=$HOME/workspace/win32-env
export LD_LIBRARY_PATH=$PB/usr/lib/x86_64-linux-gnu:$PB/usr/lib/x86_64-linux-gnu/pulseaudio PULSE_SERVER=tcp:127.0.0.1:47130
ML=$SA/logs/run-matrix.log; { echo "MATRIX base config"; date '+start %F %T epoch=%s'; uptime; } > $ML
# relaunch base
kill $(cat $SA/logs/game.pid) 2>/dev/null
for p in $(pgrep -f qemu); do if grep -qz "WINEPREFIX=/home/hatch/workspace/sanoba-audio/prefix" /proc/$p/environ 2>/dev/null; then kill $p 2>/dev/null; fi; done
sleep 4; rm -f $SA/mywrap/*.sh
PULSE_LATENCY_MSEC=750 LP_NUM_THREADS=1 LOGFILE=$SA/logs/launch-matrix.log $W32/tools/launch2.sh >> $ML
for i in $(seq 1 16); do sleep 15; timeout 20 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -i :113 -frames:v 1 /tmp/poll-m.png < /dev/null; D=$(timeout 20 python3 ~/workspace/sanoba-play/scripts/shot.py /tmp/poll-m.png | grep -o 'distinct_sampled=[0-9]*' | cut -d= -f2); [ "${D:-0}" -gt 5000 ] && break; done
sleep 15
GPID=""; for p in $(pgrep -f qemu); do if grep -qz "WINEPREFIX=/home/hatch/workspace/sanoba-audio/prefix" /proc/$p/environ 2>/dev/null && grep -qz "sanoba_trial" /proc/$p/cmdline 2>/dev/null && [ "$(ls /proc/$p/task | wc -l)" -gt 20 ]; then GPID=$p; fi; done
echo "game pid=$GPID" >> $ML
snap(){ for t in /proc/$GPID/task/*; do echo "$(basename $t) $(awk '{print $14+$15}' $t/stat)" 2>/dev/null; done; }
tot(){ join /tmp/m0.txt /tmp/m1.txt | awk '{d=$3-$2; s+=d} END {print s}'; }
# pre-flight
timeout 10 $PB/usr/bin/pactl list short sink-inputs >> $ML 2>&1
timeout 12 $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > /tmp/probe-m.raw 2>/dev/null & sleep 6; pkill -f "parec -d game.monitor"; sleep 1
timeout 30 python3 -c "
import numpy as np
d=np.fromfile('/tmp/probe-m.raw',dtype='<f4'); x=d[:(len(d)//2)*2].reshape(-1,2)
nz=(~np.all(x==0,axis=1)).mean(); print(f'PREFLIGHT nonzero={nz:.3f} peak={np.abs(x).max():.3f} pass={nz>0.5}')" >> $ML 2>&1
# M1 game only
snap > /tmp/m0.txt; sleep 60; snap > /tmp/m1.txt; echo "M1 game-only: total game CPU ticks/60s = $(tot)" >> $ML
# M2 game+video
snap > /tmp/m0.txt; timeout 70 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 20 -i :113 -t 60 -c:v libx264 -preset ultrafast $SA/logs/m2-vid.mp4 < /dev/null; snap > /tmp/m1.txt
echo "M2 game+video: total game CPU ticks/60s = $(tot)" >> $ML
timeout 20 ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames,avg_frame_rate -of csv=p=0 $SA/logs/m2-vid.mp4 >> $ML 2>&1
timeout 60 python3 -c "
import subprocess, hashlib
r=subprocess.run(['ffmpeg','-nostdin','-v','error','-i','$SA/logs/m2-vid.mp4','-vf','scale=160:90,format=gray','-f','rawvideo','-'],capture_output=True,timeout=50)
buf=r.stdout; fs=160*90; n=len(buf)//fs; seen=set()
for i in range(n): seen.add(hashlib.md5(buf[i*fs:(i+1)*fs]).hexdigest())
print(f'M2 video frames={n} distinct={len(seen)} distinct_per_s={len(seen)/60.0:.2f}')" >> $ML 2>&1
# M3 game+audio
snap > /tmp/m0.txt; U0=$(grep -c -i underrun $SA/logs/pulseaudio.log)
timeout 70 $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > $SA/logs/cap-m3.raw 2>/dev/null & sleep 60; pkill -f "parec -d game.monitor"; sleep 1
snap > /tmp/m1.txt; U1=$(grep -c -i underrun $SA/logs/pulseaudio.log)
echo "M3 game+audio: total game CPU ticks/60s = $(tot), underrun delta = $((U1-U0))" >> $ML
timeout 60 python3 $W32/tools/delivery_ratio.py $SA/logs/cap-m3.raw >> $ML 2>&1
# M4 game+video+audio
snap > /tmp/m0.txt; U0=$(grep -c -i underrun $SA/logs/pulseaudio.log)
timeout 70 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 20 -i :113 -t 60 -c:v libx264 -preset ultrafast $SA/logs/m4-vid.mp4 < /dev/null &
timeout 70 $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > $SA/logs/cap-m4.raw 2>/dev/null & sleep 62; pkill -f "parec -d game.monitor"; sleep 1
snap > /tmp/m1.txt; U1=$(grep -c -i underrun $SA/logs/pulseaudio.log)
echo "M4 game+video+audio: total game CPU ticks/60s = $(tot), underrun delta = $((U1-U0))" >> $ML
timeout 60 python3 $W32/tools/delivery_ratio.py $SA/logs/cap-m4.raw >> $ML 2>&1
timeout 20 ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames,avg_frame_rate -of csv=p=0 $SA/logs/m4-vid.mp4 >> $ML 2>&1
timeout 60 python3 -c "
import subprocess, hashlib
r=subprocess.run(['ffmpeg','-nostdin','-v','error','-i','$SA/logs/m4-vid.mp4','-vf','scale=160:90,format=gray','-f','rawvideo','-'],capture_output=True,timeout=50)
buf=r.stdout; fs=160*90; n=len(buf)//fs; seen=set()
for i in range(n): seen.add(hashlib.md5(buf[i*fs:(i+1)*fs]).hexdigest())
print(f'M4 video frames={n} distinct={len(seen)} distinct_per_s={len(seen)/60.0:.2f}')" >> $ML 2>&1
date '+end %F %T epoch=%s' >> $ML; echo "MATRIX DONE" >> $ML; cat $ML
