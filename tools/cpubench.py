import time, sys
t0=time.time(); n=0; x=0.0
while time.time()-t0 < 10.0:
    for i in range(20000):
        x += i*0.5; x *= 1.0000001; x -= i*0.25
    n+=20000
print(f"iters={n} ops_per_sec={n/10.0:.0f} x={x:.1f}")
