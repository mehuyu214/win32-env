#!/bin/bash
# fpsprobe.sh <seconds> <out-prefix>: x11grab :113 at 30fps, count distinct frames (game fps proxy)
D=${1:-12}; OUT=${2:-/tmp/fpsprobe}
ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 30 -i :113 -t $D -c:v libx264 -preset ultrafast ${OUT}.mp4 < /dev/null
python3 - "$OUT" << 'PYEOF'
import subprocess, hashlib, sys
out=sys.argv[1]
r=subprocess.run(['ffmpeg','-nostdin','-v','error','-i',out+'.mp4','-vf','scale=160:90,format=gray','-f','rawvideo','-'],capture_output=True)
buf=r.stdout; fs=160*90; n=len(buf)//fs; seen=set()
for i in range(n): seen.add(hashlib.md5(buf[i*fs:(i+1)*fs]).hexdigest())
print(f"frames_total={n} distinct={len(seen)} distinct_fps={len(seen)/12.0:.2f}")
PYEOF
