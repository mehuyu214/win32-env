#!/bin/bash
# fpsprobe.sh <seconds> <out-prefix>: x11grab <display> at 30fps, count distinct frames (game fps proxy)
# The distinct-fps denominator is the ACTUAL captured duration (frames / 30),
# not a fixed constant — the old version divided by a hardcoded 12.0 even
# when a different capture length was requested.
D=${1:-12}; OUT=${2:-/tmp/fpsprobe}; DISP="${DISPLAY:-:113}"
ffmpeg -nostdin -y -v error -f x11grab -video_size 1280x720 -framerate 30 -i "$DISP" -t "$D" -c:v libx264 -preset ultrafast "${OUT}.mp4" < /dev/null
python3 - "$OUT" << 'PYEOF'
import subprocess, hashlib, sys
out=sys.argv[1]
r=subprocess.run(['ffmpeg','-nostdin','-v','error','-i',out+'.mp4','-vf','scale=160:90,format=gray','-f','rawvideo','-'],capture_output=True)
buf=r.stdout; fs=160*90; n=len(buf)//fs; seen=set()
for i in range(n): seen.add(hashlib.md5(buf[i*fs:(i+1)*fs]).hexdigest())
dur = n / 30.0
print(f"frames_total={n} distinct={len(seen)} captured_s={dur:.2f} distinct_fps={len(seen)/dur:.2f}" if dur > 0 else "frames_total=0 distinct=0 captured_s=0")
PYEOF
