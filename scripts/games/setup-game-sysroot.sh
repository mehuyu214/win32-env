#!/bin/bash
# Extend the base 32-bit sysroot with the audio + OpenGL closure needed to
# actually RUN games (title rendering + sound), verified 2026-11-12 with the
# Sanoba Witch trial (unmodified). Run AFTER scripts/setup.sh.
# The extra .deb files live in sysroot32/debs/ (copied there 2026-11-12).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../env.sh"

DEBS="
libasound2t64_ libasound2-data_
mesa-libgallium_ libllvm20_ libpciaccess0_ libtinfo6_
libx11-xcb1_ libxcb-randr0_ libxcb-shm0_ libwayland-client0_
libsensors5_ libdrm-amdgpu1_ libdrm-intel1_ libelf1t64_
libatomic1_ libffi8_ libedit2_ libxml2_ libicu74_ liblzma5_
python3.12-minimal_ libpython3.12-minimal_ libpython3.12-stdlib_ python3.12_
libsqlite3-0_ libncursesw6_ libreadline8t64_ libssl3t64_
"
mkdir -p "$SYSROOT32"
for pat in $DEBS; do
  for d in "$VN32_ROOT"/sysroot32/debs/${pat}*.deb; do
    [ -f "$d" ] || { echo "MISSING DEB: $pat"; continue; }
    dpkg-deb -x "$d" "$SYSROOT32" && echo "extracted $(basename "$d")"
  done
done
# sysroot uses merged-usr layout; make sure the links exist
[ -e "$SYSROOT32/lib" ] || ln -s usr/lib "$SYSROOT32/lib"
[ -e "$SYSROOT32/bin" ] || ln -s usr/bin "$SYSROOT32/bin"
ldconfig -r "$SYSROOT32" 2>/dev/null || true

echo "=== dependency closure audit (every .so in the sysroot) ==="
R="$SYSROOT32/usr/lib/i386-linux-gnu"
MISS=0
for so in "$R"/*.so.* "$R"/dri/*.so; do
  [ -f "$so" ] || continue
  for lib in $(readelf -d "$so" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/'); do
    if [ ! -e "$R/$lib" ]; then echo "MISSING $lib (needed by $(basename "$so"))"; MISS=1; fi
  done
done
# Known-benign: libsystemd.so.0 (libdbus) may be reported; Wine tolerates it.
[ "$MISS" -eq 0 ] && echo "closure OK"

echo "=== EGL probe (pure Linux, no Wine) ==="
if [ -x "$SYSROOT32/usr/bin/python3.12" ]; then
  DISPLAY="${DISPLAY:-:99}" \
  __EGL_VENDOR_LIBRARY_DIRS="$SYSROOT32/usr/share/glvnd/egl_vendor.d" \
  "$QEMU10" -cpu max -L "$SYSROOT32" "$SYSROOT32/usr/bin/python3.12" \
    "$VN32_ROOT/tools/eglprobe.py" 2>&1 | head -12
  echo "PASS = client extensions non-empty incl. EGL_KHR_client_get_all_proc_addresses"
  echo "       and eglInitialize OK on SURFACELESS and X11."
else
  echo "python3.12 not in sysroot; skip eglprobe"
fi
