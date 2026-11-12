import ctypes
targets = [
 "libEGL_mesa.so.0",
 "libgallium-25.2.8-0ubuntu0.24.04.4.so",
 "libgbm.so.1",
 "libglapi.so.0",
 "libLLVM.so.20.1",
 "libdrm.so.2",
 "libwayland-client.so.0",
]
for t in targets:
    try:
        lib = ctypes.CDLL(t)
        print("OK  ", t)
    except OSError as e:
        print("FAIL", t, "->", e)
print("DLPROBE DONE")
