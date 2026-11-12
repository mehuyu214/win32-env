# Running unmodified 32-bit Windows games (verified 2026-11-12)

Goal: run 32-bit Windows games **without modifying the game** — every fix is
on the environment side (QEMU / Wine / q32sup / sysroot libraries / virtual
devices). Test case: Sanoba Witch trial (Kirikiri Z, PE32), which now boots,
renders its title screen, plays audio, accepts mouse input and progresses
into Chapter 1-1. Evidence: `screenshots/sanoba-title-screen.png`,
`screenshots/sanoba-chapter1-1.png`.

## Recipe

1. Base restore: `scripts/setup.sh` + `scripts/verify.sh`.
2. Extend the sysroot: `scripts/games/setup-game-sysroot.sh`
   (adds the audio + GL dependency closure listed below, audits every `.so`,
   and runs the EGL probe).
3. Start Xvfb (`scripts/start-x.sh`, e.g. :99 at 1600x900x24).
4. Launch: `scripts/games/launch-game.sh 'Z:\abs\path\to\game.exe'`
   — the launch script handles locale, audio, GL env and a fresh prefix.

## The four environment fixes (each was a separate wall)

### 1. Japanese locale — Shift_JIS script corruption
Under a non-Japanese locale, Wine's CP932 conversion garbles SJIS text and
Kirikiri dies deterministically (`MainWindow.tjs` line 8893,
"Syntax error / Invalid character U+0081"; the first failing line is the
first SJIS char with trail byte 0x5C — 表 = 95 5C — before a closing quote).
The XP3 archive and the scripts are intact (Adler-32 verified for all
9,307 entries); the game's embedded `readencoding="Shift_JIS"` was already
in effect. Fix: `LANG=LC_ALL=ja_JP.UTF-8` plus `LOCPATH` pointing at a
**locally generated** locale (directory form:
`localedef -i ja_JP -c -f UTF-8 <dir>/ja_JP.UTF-8`). `LANG` alone can fail
`setlocale` — the generated locale is required.

### 2. Fresh prefix — WindowMetrics corruption
A prefix created during early bring-up returned max track size
6357197x6357112 from `get_min_max_info`, forcing every window to
65535x65535; nothing can draw like that. A completely fresh prefix has
normal metrics (116x27), a normal 1280x720 game window and working
Japanese menus. Snapshot the fresh prefix (`tar`) and restore it instead
of reusing a suspect one.

### 3. Audio — virtual ALSA device, real playback
Without 32-bit `libasound`, Wine's mmdevapi finds no driver and game audio
calls throw script exceptions (Sanoba: `bgm.tjs` `buf.play()` on
bgm51.opus). Add `libasound2t64:i386` + `libasound2-data` to the sysroot
and set `ALSA_CONFIG_PATH` to a null-device config
(`scripts/games/asound-null.conf`: `pcm.!default { type null }`).
Verified: mmdevapi selects `winealsa`, DirectSound buffers stream
(Lock/Unlock with real audio data), zero mmdevapi errors, title BGM and
voice play (into the null device — decoded and rendered, silently).

### 4. Rendering — the Mesa vendor that silently never loaded
Symptom chain: EGL client extensions **empty** →
`egl_init: Failed to find required extension
EGL_KHR_client_get_all_proc_addresses` → Wine "couldn't initialize
OpenGL" → `wined3d: Failed to find a suitable pixel format` →
`Direct3DCreate9` returns NULL → game window stays white/black.
Root cause (found with `tools/dlprobe.py`, a ctypes dlopen probe under
qemu-i386 + python3.12:i386): two **runtime** libraries were missing from
the sysroot and a static `NEEDED` audit of the top-level libs did not
catch them:

- `libpciaccess.so.0` — needed by `libEGL_mesa.so.0` and `libgallium`
- `libtinfo.so.6` — needed by `libLLVM.so.20.1`

With the vendor unable to load, glvnd reported zero vendors. Full closure
added (all `:i386`): `mesa-libgallium`, `libllvm20`, `libpciaccess0`,
`libtinfo6`, `libx11-xcb1`, `libxcb-randr0`, `libxcb-shm0`,
`libwayland-client0`, `libsensors5`, `libdrm-amdgpu1`, `libdrm-intel1`,
`libelf1t64`, `libatomic1`, `libffi8`, `libedit2`, `libxml2`, `libicu74`,
`liblzma5` (+ the audio set above). After the fix, `tools/eglprobe.py`
under plain qemu-i386 shows the full client extension list and
`eglInitialize` OK (EGL 1.5, Mesa) on surfaceless and X11 displays; in
game, the renderer is `llvmpipe (LLVM 20.1.2, 256 bits)` and pixel-format
failures drop to 0.

Notes:
- Wine 11.21's winex11 is **EGL-only**: removing `libEGL.so.1` does not
  fall back to GLX (it just errors). Fix EGL; don't chase GLX/indirect.
- The VM has no GPU (`/dev/dri` absent). Xvfb + Mesa swrast/llvmpipe is
  the display stack; a benign `DRI3 error: Could not get DRI3 device`
  warning appears and the software path is used.
- `libvulkan.so.1` is absent; Wine tries Vulkan first, logs one error,
  and falls back to GL. Harmless for D3D9 titles.
- Full per-.so closure audit (in `setup-game-sysroot.sh`) reports only
  `libsystemd.so.0` (via libdbus) missing — benign for games.

## Staged verification (do not skip stages)

1. `tools/eglprobe.py` under qemu-i386: client extensions non-empty,
   `eglInitialize` OK. (`tools/dlprobe.py` pinpoints any `.so` that
   fails to load, with the loader's own error message.)
2. Game boot log: no `err:wgl`, pixel-format failures = 0, renderer
   string = llvmpipe.
3. Screenshot: title screen visible (not white/black).
4. Click START: first scene + dialogue renders; story advances on click.

## Performance note

llvmpipe JIT under QEMU TCG is slow (title/story are fine; expect low
fps). This stack values correctness/compatibility over speed.
