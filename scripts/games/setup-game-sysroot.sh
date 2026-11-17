#!/bin/bash
# Extend the base 32-bit sysroot with the audio + OpenGL closure needed to
# actually RUN games (title rendering + sound), verified 2026-11-12 with the
# Sanoba Witch trial (unmodified). Run AFTER scripts/setup.sh.
# The extra .deb files live in sysroot32/debs/ (copied there 2026-11-12).
# Failures are tracked in FAIL and reported via the exit code at the end —
# a missing .deb, a failed extraction, an incomplete dependency closure or
# an unrunnable EGL probe must not exit 0.
set -u
FAIL=0
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
libegl-mesa0_ libglx-mesa0_ libdrm2_ libxcb-glx0_
"
mkdir -p "$SYSROOT32"
for pat in $DEBS; do
  for d in "$VN32_ROOT"/sysroot32/debs/${pat}*.deb; do
    [ -f "$d" ] || { echo "MISSING DEB: $pat" >&2; FAIL=1; continue; }
    if dpkg-deb -x "$d" "$SYSROOT32"; then
      echo "extracted $(basename "$d")"
    else
      echo "EXTRACT FAILED: $(basename "$d")" >&2; FAIL=1
    fi
  done
done
# sysroot uses merged-usr layout; make sure the links exist
[ -e "$SYSROOT32/lib" ] || ln -s usr/lib "$SYSROOT32/lib"
[ -e "$SYSROOT32/bin" ] || ln -s usr/bin "$SYSROOT32/bin"
ldconfig -r "$SYSROOT32" 2>/dev/null || true
# ALSA -> PulseAudio plugin modules. libasound resolves its plugins from
# the sysroot's alsa-lib dir (NOT via LD_LIBRARY_PATH), and no
# libasound2-plugins .deb is vendored in sysroot32/debs/ — so install the
# three pulse modules from the repo's vendored pa-libs (noble
# libasound2-plugins 1.2.11). Without them, winealsa finds no usable
# device and the alsa-pulse route is silent (reproduced 2026-11-16:
# "Cannot open shared library libasound_module_conf_pulse.so").
mkdir -p "$SYSROOT32/usr/lib/i386-linux-gnu/alsa-lib"
for m in pcm_pulse ctl_pulse conf_pulse; do
  if cp -n "$VN32_ROOT/pa-libs/usr/lib/i386-linux-gnu/alsa-lib/libasound_module_${m}.so" \
    "$SYSROOT32/usr/lib/i386-linux-gnu/alsa-lib/"; then
    echo "installed libasound_module_${m}.so"
  else
    echo "FAILED to install libasound_module_${m}.so" >&2; FAIL=1
  fi
done

echo "=== dependency closure audit (every .so in the sysroot) ==="
R="$SYSROOT32/usr/lib/i386-linux-gnu"
# Known-benign misses: libsystemd.so.0 (needed by libdbus; Wine tolerates
# its absence) and libpulsecommon-16.1.so (lives in $R/pulseaudio/, a
# subdir the top-level scan cannot see — the loader finds it via the
# libpulse RUNPATH). Any other missing library fails the audit.
BENIGN=" libsystemd.so.0 libpulsecommon-16.1.so "
MISS=0
for so in "$R"/*.so.* "$R"/dri/*.so; do
  [ -f "$so" ] || continue
  for lib in $(readelf -d "$so" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/'); do
    if [ ! -e "$R/$lib" ]; then
      case "$BENIGN" in
        *" $lib "*) echo "missing (known-benign): $lib (needed by $(basename "$so"))";;
        *) echo "MISSING $lib (needed by $(basename "$so"))"; MISS=1;;
      esac
    fi
  done
done
if [ "$MISS" -eq 0 ]; then
  echo "closure OK"
else
  echo "closure INCOMPLETE (see MISSING above)" >&2; FAIL=1
fi

echo "=== EGL probe (pure Linux, no Wine) ==="
if [ -x "$SYSROOT32/usr/bin/python3.12" ]; then
  PROBE_OUT="$(DISPLAY="${DISPLAY:-:99}" \
  __EGL_VENDOR_LIBRARY_DIRS="$SYSROOT32/usr/share/glvnd/egl_vendor.d" \
  "$QEMU10" -cpu "$Q32_CPU" -L "$SYSROOT32" "$SYSROOT32/usr/bin/python3.12" \
    "$VN32_ROOT/tools/eglprobe.py" 2>&1)"
  echo "$PROBE_OUT" | head -12
  # The probe itself exits 0 even when EGL is dead — check its output.
  if echo "$PROBE_OUT" | grep -q "EGL_KHR_client_get_all_proc_addresses" \
     && echo "$PROBE_OUT" | grep -q "eglInitialize: 1"; then
    echo "EGL PROBE PASS (client extensions non-empty, eglInitialize OK)"
  else
    echo "EGL PROBE FAIL (see output above)" >&2
    exit 1
  fi
else
  echo "ERROR: python3.12 not in sysroot; the EGL probe cannot run, so this setup is unverified" >&2
  FAIL=1
fi

if [ "$FAIL" != 0 ]; then
  echo "setup-game-sysroot: FAILED (see errors above)" >&2
  exit 1
fi
echo "setup-game-sysroot: OK"
