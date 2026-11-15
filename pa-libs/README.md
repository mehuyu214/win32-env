# pa-libs — i386 PulseAudio/ALSA runtime libraries for the guest

Extracted i386 libraries (Ubuntu noble) that Wine's `winepulse.so` /
`winealsa.so` need at load time. The game sysroot has no `libpulse.so.0`,
so without these Wine falls back to ALSA and then to silence (the ALSA
config in the sysroot references a pulse plugin that is also missing).

Contents (114 files, ~7.5 MB) are the library subset previously assembled
for the win32-perf / compat lines (see `MANIFEST.txt`): libpulse0
(`libpulse.so.0.24.2`, `libpulsecommon-16.1.so`), libasound2-plugins
(`alsa-lib/libasound_module_*_pulse.so`), libsndfile1, libspeexdsp1,
libsystemd0, libapparmor1, libcap2, libgcrypt20, libgpg-error0,
libasyncns0 and their `.so` dependencies already present in the sysroot.

`launch-game.sh` (AUDIO_ROUTE=pulse) prepends
`pa-libs/usr/lib/i386-linux-gnu` (+ `/pulseaudio`) to `LD_LIBRARY_PATH`.
QEMU user-mode passes the variable into the guest; the guest loader
resolves the host-absolute path by QEMU's prefix-fallback. This is the
same mechanism the compat/rotation lines used (win32-perf `libs32`).
