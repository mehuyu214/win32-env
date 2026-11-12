#!/bin/bash
# runbench.sh <run-id> <game-pid> [audio-secs] -- pre-flight + timed audio capture + video verify
SA=$HOME/workspace/sanoba-audio; PB=$SA/pa-bin; W32=$HOME/workspace/win32-env
export LD_LIBRARY_PATH=$PB/usr/lib/x86_64-linux-gnu:$PB/usr/lib/x86_64-linux-gnu/pulseaudio PULSE_SERVER=tcp:127.0.0.1:47130
RID=$1; GPID=$2; ASECS=${3:-60}
RL=$SA/logs/run-$RID.log
{ echo "RUN $RID game_pid=$GPID"; date '+start %F %T epoch=%s'; uptime; } > $RL
echo "=== PRE-FLIGHT (a) sink-input ===" >> $RL; timeout 10 $PB/usr/bin/pactl list short sink-inputs >> $RL 2>&1
timeout 12 $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > /tmp/probe-$RID.raw 2>/dev/null &
sleep 6; pkill -f "parec -d game.monitor"; sleep 1
timeout 30 python3 -c "
import numpy as np,sys
d=np.fromfile('/tmp/probe-$RID.raw',dtype='<f4'); x=d[:(len(d)//2)*2].reshape(-1,2)
nz=(~np.all(x==0,axis=1)).mean()
print(f'PREFLIGHT probe: frames={len(x)} audio_s={len(x)/48000:.2f} nonzero={nz:.3f} peak={np.abs(x).max():.3f} rms={np.sqrt((x.astype(np.float64)**2).mean()):.4f} pass={nz>0.5 and np.abs(x).max()>0.01}')" >> $RL 2>&1
snap(){ for t in /proc/$GPID/task/*; do echo "$(basename $t) $(awk '{print $14+$15}' $t/stat)" 2>/dev/null; done; }
snap > /tmp/thr0-$RID.txt; U0=$(grep -c -i underrun $SA/logs/pulseaudio.log)
A0=$(date +%s.%N); timeout $((ASECS+10)) $PB/usr/bin/parec -d game.monitor --format=float32le --rate=48000 --channels=2 > $SA/logs/cap-$RID.raw 2>/dev/null &
sleep $ASECS; pkill -f "parec -d game.monitor"; sleep 1; A1=$(date +%s.%N)
python3 -c "print(f'audio window wall: {$A1-$A0:.2f}s')" >> $RL
U1=$(grep -c -i underrun $SA/logs/pulseaudio.log); echo "underrun delta: $((U1-U0))" >> $RL
snap > /tmp/thr1-$RID.txt; echo "thread CPU deltas (ticks):" >> $RL; join /tmp/thr0-$RID.txt /tmp/thr1-$RID.txt | awk '{d=$3-$2; if(d>0) print $1, d}' | sort -k2 -rn | head -8 >> $RL
timeout 60 python3 $W32/tools/delivery_ratio.py $SA/logs/cap-$RID.raw >> $RL 2>&1
V0=$(date +%s.%N); timeout 30 ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 20 -i :113 -t 10 -c:v libx264 -preset ultrafast $SA/logs/$RID-vid.mp4 < /dev/null; V1=$(date +%s.%N)
python3 -c "print(f'video grab wall: {$V1-$V0:.2f}s')" >> $RL
timeout 20 ffprobe -v error -show_entries format=duration,size -of csv=p=0 $SA/logs/$RID-vid.mp4 >> $RL 2>&1
timeout 60 python3 -c "
import subprocess, hashlib
r=subprocess.run(['ffmpeg','-nostdin','-v','error','-i','$SA/logs/$RID-vid.mp4','-vf','scale=160:90,format=gray','-f','rawvideo','-'],capture_output=True,timeout=50)
buf=r.stdout; fs=160*90; n=len(buf)//fs; seen=set()
for i in range(n): seen.add(hashlib.md5(buf[i*fs:(i+1)*fs]).hexdigest())
print(f'video frames={n} distinct={len(seen)} distinct_per_s={len(seen)/10.0:.2f}')" >> $RL 2>&1
date '+end %F %T epoch=%s' >> $RL; echo "RUN $RID DONE" >> $RL
