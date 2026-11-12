import ctypes, sys
def err(tag):
    print(tag, "eglGetError=0x%x" % egl.eglGetError())
try:
    egl = ctypes.CDLL("libEGL.so.1")
    print("libEGL.so.1 loaded OK")
except OSError as e:
    print("libEGL LOAD FAILED:", e); sys.exit(1)
egl.eglQueryString.restype = ctypes.c_char_p
egl.eglQueryString.argtypes = [ctypes.c_void_p, ctypes.c_int]
egl.eglGetError.restype = ctypes.c_int
s = egl.eglQueryString(None, 0x3055)
print("CLIENT EXTENSIONS:", repr(s))
# surfaceless platform 0x31DD
egl.eglGetPlatformDisplay.restype = ctypes.c_void_p
egl.eglGetPlatformDisplay.argtypes = [ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
egl.eglInitialize.restype = ctypes.c_uint
egl.eglInitialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
for name, plat, native in (("SURFACELESS", 0x31DD, None),):
    d = egl.eglGetPlatformDisplay(plat, native, None)
    print(name, "display:", hex(d) if d else d)
    if d:
        mj, mn = ctypes.c_int(), ctypes.c_int()
        ok = egl.eglInitialize(ctypes.c_void_p(d), ctypes.byref(mj), ctypes.byref(mn))
        print(name, "eglInitialize:", ok, "version", mj.value, mn.value)
        if ok:
            print(name, "VENDOR:", repr(egl.eglQueryString(ctypes.c_void_p(d), 0x3053)))
            print(name, "DISPLAY EXT:", repr(egl.eglQueryString(ctypes.c_void_p(d), 0x3055))[:200])
        else:
            err(name + " init fail")
# X11 platform via libX11
try:
    x11 = ctypes.CDLL("libX11.so.6")
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xd = x11.XOpenDisplay(b":99")
    print("XOpenDisplay(:99):", hex(xd) if xd else xd)
    if xd:
        d = egl.eglGetPlatformDisplay(0x31D5, ctypes.c_void_p(xd), None)
        print("X11 display:", hex(d) if d else d)
        if d:
            mj, mn = ctypes.c_int(), ctypes.c_int()
            ok = egl.eglInitialize(ctypes.c_void_p(d), ctypes.byref(mj), ctypes.byref(mn))
            print("X11 eglInitialize:", ok, mj.value, mn.value)
            if ok:
                print("X11 VENDOR:", repr(egl.eglQueryString(ctypes.c_void_p(d), 0x3053)))
            else:
                err("X11 init fail")
except OSError as e:
    print("libX11 failed:", e)
print("PROBE DONE")
