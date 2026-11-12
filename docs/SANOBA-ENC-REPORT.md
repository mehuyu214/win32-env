# Sanoba Witch trial — isolated investigation report (sanoba-enc line)

Environment: `~/workspace/sanoba-enc/`, DISPLAY `:111` (Xvfb 1600x900x24, no window
manager), supervisor `bin/supE` (q32sup), emulator `bin/emuE` = **qemu-i386 8.2.2**
(Debian static), Wine **11.21 x86** (`~/workspace/vn-trials/wine32/wine-11.21-x86`),
guest sysroot = shared `~/workspace/vn-trials/sysroot32/root` (also used by the
:99 main line and :101 invest line). Own game copy in `game/` (pristine XP3),
own prefixes `prefix32/` (old, copied — poisoned, see §2) and `prefix32f/` (fresh).
Policy throughout: the game/EXE/Kirikiri/XP3/TJS were never modified; every fix
is environment-side.

Final state: **all walls down.** Encoding fixed by this line (§1); window poison
identified by the invest line (§2); rendering + audio root-caused and fixed by
the main line in the shared sysroot (§3.6, §4) and **independently verified in
this isolated env** (§3.7): native i386 GL/EGL probes pass, and the standalone
D3D9 test creates a HAL device and presents real magenta pixels. The unmodified
game itself renders its title screen, accepts input, plays audio and reaches
Chapter 1-1 in the main line's env (screenshots in the win32-env repo,
`screenshots/sanoba-title-screen.png`, `sanoba-chapter1-1.png`).

---

## 1. Wall 1 — script encoding (SOLVED by this line, 21:19 JST)

Symptom: deterministic Kirikiri failure after ~30 scripts load:
`MainWindow.tjs` line 8893, "Syntax error / Invalid character", the invalid
character in `krkr.console.log` (UTF-16LE) being exactly **U+0081**.

Mechanism (measured, not guessed):
- `data.xp3` is clean: 9,307 entries, no encryption; all 173 `.tjs` pass
  expanded-size and Adler-32 checks. Only `MainWindow.tjs` has ≥8893 lines
  (14,223 lines, 392,531 bytes, Shift_JIS, CRLF, no BOM).
- Line 8893 (SJIS decode) is mid-concatenation: `…(currentPage? "裏": "表") +
  "メッセージレイヤ" +…`. Its raw bytes contain 表 = `95 5C` — a SJIS character
  whose trail byte is `0x5C` (backslash) — immediately before a closing quote.
- Host-side lexer simulation (`sim_lex.py`, `logs/sim_lex.txt`): SJIS chars with
  trail byte `0x5C` occur on 197 lines, but a `0x5C`-trail char **immediately
  before a closing quote** occurs on only 3 lines; the first is **8893**
  (then 8938, 8973). Every candidate mis-decoding (UTF-8/replace, Latin-1,
  CP1252) produces its first lexer error exactly at 8893.
- The engine's `readencoding` option default IS UTF-8 per the embedded option
  table, **but** the exe's PE TEXT resource id 139 (61 bytes, extracted in
  `work/embedded_resource.bin`, see `logs/pe_rsrc.txt`) is an embedded config
  `readencoding="Shift_JIS"` — and it was already in effect at baseline: a
  bogus-option control run printed the effective list
  `-readencoding=BOGUS_XYZ -readencoding=Shift_JIS -debugwin=no -hkupdaterect=`
  (earlier option wins) and died with "BOGUS_XYZ is unsupported encoding",
  proving command-line options are parsed AND the embedded Shift_JIS value was
  already active. Explicit `-readencoding=Shift_JIS` alone did **not** fix the
  baseline (negative result).
- Root cause: the corruption sits in the **locale-dependent SJIS→wide
  conversion path (Wine CP932 under a non-Japanese/C locale)**, not in the
  archive and not in the readencoding setting.

Fix (verified): launch with `LANG=LC_ALL=ja_JP.UTF-8` **and** `LOCPATH`
pointing at a locally generated ja_JP.UTF-8 locale (`locale/` in this env;
`LANG` alone can fail setlocale — the invest line confirmed this too).
Result in `game/savedata/krkr.console.log`: no "Syntax error", no "8893";
`MainWindow.tjs` loaded (820 ms) followed by all later scripts (world,
system, yuzu_system, custom, AfterInit) and 「起動スクリプト実行終了」; KAG
savedata created (`sanoba_trial.cfu`, `datasc.ksd`, `datasu.ksd`,
`data_anchor.ksd`). A locale-off toggle run (21:28, `logs/toggle_off.log`)
was performed by the predecessor as the reproduction control.

## 2. Wall 2 — window poison (found by the invest line, :101)

Prefixes copied from the old vn-trials `wineprefix32` carry corrupted
WindowMetrics-derived values: Wine's `get_min_max_info` returned a max track
size of 6357197x6357112, forcing **every window to 65535x65535** (this env
measured exactly that geometry for its game window on :111), so nothing
rendered. The abnormal values are not stored as text in the prefix; they are
computed at runtime from corrupted inputs. Cure: a **completely fresh
prefix** (normal values 116x27; 32-bit Notepad renders fully — invest line,
screenshot-proven). This env therefore built `prefix32f/` (boot log
`logs/boot_fresh.log`) and uses it for all post-21:34 runs. Related invest-line
finding: launch the exe by **absolute `Z:\` path** — a relative path makes
Kirikiri's data path recurse and die with "Not supported media type".

## 3. Wall 3 — rendering (Direct3D9 gets no GL context)

### 3.0 Framing
Kirikiri's BasicDrawDevice uses Direct3D9 (`Direct3DCreate9`). GDI success ≠
D3D success: with a fresh prefix the invest line got the game window at
1280x720 with working Japanese menus but a **solid white** client area
(`~/workspace/sanoba-invest/screens/gdi-run1.png`). The VM has **no GPU and
no /dev/dri**; the only GL is Mesa software (swrast/llvmpipe) under Xvfb.

### 3.1 The bisect tool
`work/d3d9test.c` / `work/d3d9test.exe` (PE32; build:
`i686-w64-mingw32-gcc -O2 d3d9test.c -ld3d9 -luser32 -lgdi32` — rebuild
verified identical format, 17 sections). It creates a window, calls
`Direct3DCreate9`, `GetDeviceCaps`, `CreateDevice` (HAL, REF fallback),
then loops `Clear(magenta 0xFFFF00FF) → Present`, and at frame 5 reads back
the front-buffer pixel at (300,300) via `GetFrontBufferData`. Runner:
`run_d3dtest.sh <variant>` (fresh `prefix32f`, ja locale, `WINEDEBUG=+d3d,+wgl,+loaddll`,
screenshot + region histogram).

### 3.2 v1_default (21:40) — FAIL at stage 1
```
window created
Direct3DCreate9 -> 00000000
FAIL: Direct3DCreate9 null
```
Wine log chain (`logs/d3dtest_v1_default.wine.log`):
`trace:wgl:egl_init EGL client extensions:` **(empty string)** →
`err:wgl:egl_init Failed to find required extension EGL_KHR_client_get_all_proc_addresses` →
`err:wgl:X11DRV_WineGL_InitOpenglInfo couldn't initialize OpenGL, expect problems` →
`err:d3d:wined3d_caps_gl_ctx_create Failed to find a suitable pixel format` →
`err:d3d:wined3d_adapter_gl_init Failed to get a GL context` → Create9 NULL.
The failure is entirely in the Wine→OpenGL layer, before any game code.

### 3.3 v3_vendor (21:43) — FAIL, loader env broke libEGL
With `__EGL_VENDOR_LIBRARY_DIRS` → sysroot (predecessor's GL launcher
pattern): `err:wgl:egl_init Failed to load libEGL.so.1: libEGL.so.1: cannot
open shared object file` → GLX fallback table equally empty (glClear etc.
not found) → Create9 NULL. Negative. (Post-hoc context from the main line:
Wine 11.21's winex11 is **EGL-only** — there is no GLX fallback to rescue a
broken EGL load; hiding libEGL.so.1 just errors. The whole GLX/indirect
route is dead on this Wine.)

### 3.4 Host gate (KK-specified, 21:49) — host stack is HEALTHY
Native amd64 tools (Ubuntu mesa-utils/-bin 9.0.0-2, extracted not installed)
on :111, verbatim in `logs/glxinfo_gate.log`:
- `DISPLAY=:111 glxinfo -B` → direct rendering: **Yes**, renderer
  **llvmpipe (LLVM 20.1.2, 256 bits)**, Mesa **25.2.8**, GL 4.5 core/compat,
  GLES 3.2.
- `DISPLAY=:111 LIBGL_ALWAYS_INDIRECT=1 glxinfo -B` → **FAILS**:
  `BadValue … X_GLXCreateNewContext`. Indirect GLX is broken at the X
  protocol level on this Xvfb — negative, rules out the indirect shortcut.
- `DISPLAY=:111 eglinfo -B` → GBM platform fails (no /dev/dri, expected);
  **X11 platform initializes** (EGL 1.5, Mesa, llvmpipe), surfaceless and
  device platforms also OK.

### 3.5 Native i386 bisect (21:47–21:50) — failure is BELOW Wine
Debian bookworm `mesa-utils(-bin) 8.5.0-1` i386 binaries (Ubuntu publishes
no i386 mesa-utils for noble), run under plain `emuE` (qemu-i386, `-L`
sysroot, no Wine, no supervisor), logs in `logs/native_i386_gl.log`:
- `glxinfo -B` → `Error: couldn't find RGB GLX visual or fbconfig`
- `eglinfo -B` → `EGL client extensions string:` **empty** (the exact Wine
  symptom) + `eglInitialize failed` on the default display.
⇒ Per the decision tree, the root layer is the guest 32-bit GL stack /
qemu / env, not Wine.

Forensics gathered at that point (all in `logs/native_*`, `logs/lddebug_v1.log`):
- `LD_DEBUG=libs`: the full chain loads — `/lib/i386-linux-gnu/libEGL.so.1`
  (glvnd, guest view = sysroot) → libGLdispatch init → `libEGL_mesa.so.0`
  searched, and its whole dependency chain searched (libgallium-25.2.8,
  libgbm, libdrm, libLLVM.so.20.1, …). "Searched" ≠ "opened": the trace dies
  around libdrm_intel → libpciaccess.so.0 resolution.
- ELF verification: every loaded GL library is a proper ELF32 i386 object.
- A recursive filename-presence audit of the NEEDED closure (49 sonames from
  libEGL_mesa/libGLX_mesa/libGL/libEGL) reported **nothing missing** — this
  audit method was later proven insufficient (§3.6): it checks top-level
  NEEDED entries by filename, not runtime dlopen resolution of the full
  transitive closure inside the guest.
- `LD_PRELOAD=/lib/i386-linux-gnu/libEGL_mesa.so.0` printed "cannot open
  shared object file" for the preload and a fatal libpciaccess error for
  the main program — a preload-under-qemu artifact; discarded as evidence
  (the same libpciaccess opens fine via normal search in `-strace`).
- qemu `-strace` run (`logs/native_strace.log`): libpciaccess.so.0 opened
  successfully (fd 3); only 40 failed syscalls, all benign (missing
  /etc/ld.so.preload, `set_robust_list` ENOSYS, `/dev/dri` ENOENT probe).
  In that same run eglinfo already printed the FULL client-extension list
  (incl. `EGL_KHR_client_get_all_proc_addresses`) and surfaceless
  initialized with driver `swrast` — the first sign the stack had flipped
  (see §3.6 timing note).

### 3.6 Resolution (main line, 21:36–21:54 — `~/workspace/vn-trials/STATUS.md`)
The main line root-caused it with a **ctypes dlopen probe**
(`tools/dlprobe.py`, python3.12:i386 inside the sysroot under qemu), which
exposed what static audits missed: the glvnd Mesa vendor silently never
registered because **two runtime libraries were missing from the shared
sysroot**:
- **libpciaccess.so.0** — needed by libEGL_mesa/libgallium at device-probe time;
- **libtinfo.so.6** — needed by libLLVM.so.20.1.

Fix = add the full GL/audio closure to the sysroot (all :i386):
mesa-libgallium, libllvm20, libpciaccess0, libtinfo6, libx11-xcb1,
libxcb-randr0, libxcb-shm0, libwayland-client0, libsensors5, libdrm-amdgpu1,
libdrm-intel1, libelf1t64, libatomic1, libffi8, libedit2, libxml2, libicu74,
liblzma5 (+ libasound set, §4; + a python3.12 i386 probe stack). A closure
audit over every sysroot `.so` is now clean except libsystemd.so.0 (libdbus;
benign, unrelated).

Timing note from this line (honest record): in the enc env the failure was
reproducible until ~21:49 and gone from 21:50 on. The only sysroot artifact
this line observed changing at 21:49 was `etc/ld.so.cache` (rewritten,
183 bytes) — an interim "stale cache" hypothesis was recorded and is
**superseded** by the main line's dlopen-probe measurement: the cache
rewrite was a side effect of the same sysroot package operation that added
the missing libraries. The libraries were the cause; the cache was a
coincidence of timing.

With the closure in place, the main line's `tools/eglprobe.py` under plain
qemu-i386 shows full client extensions incl.
`EGL_KHR_client_get_all_proc_addresses` and `eglInitialize` OK (EGL 1.5
Mesa) on surfaceless **and** X11. In-game: wgl errors gone, pixel-format
failures 0 (was 96–121), renderer "llvmpipe (LLVM 20.1.2, 256 bits)",
title screen rendered, START → Chapter 1-1, mouse input works.

### 3.7 Independent verification in THIS env (post-fix, qemu 8.2.2)
- Native i386, plain, no env tricks (`logs/native_i386_gl_run2.log`):
  `glxinfo -B` → direct rendering: **Yes**, llvmpipe, GL 4.5, Mesa 25.2.8.
  `eglinfo -B` → **X11 platform initializes** (EGL 1.5, driver name swrast),
  surfaceless OK; GBM/Wayland still fail (no /dev/dri / no compositor —
  expected and irrelevant). (The memory figures glxinfo prints under qemu
  are garbage-huge — a qemu sysinfo reporting quirk, cosmetic.)
- d3d9test **v4_default** (21:52, config identical to failing v1;
  `logs/d3dtest_v4_default.log`):
  ```
  Direct3DCreate9 -> 0036dc28
  adapter: driver=nvd3dum.dll desc=NVIDIA GeForce GTX 470   (Wine card guess)
  GetDeviceCaps HAL hr=0x00000000
  CreateDevice HAL hr=0x00000000 dev=00365b30
  DEVICE OK
  frontbuffer(300,300) = 0xffff00ff   ← the magenta Clear color, read back
  frames=234 firstClear=0x00000000 firstPresent=0x00000000 DONE
  ```
  Wine log: `GL_RENDERER: "llvmpipe (LLVM 20.1.2, 256 bits)"`, no wgl err
  lines (only harmless "optional EXT function not found" warnings). Note:
  Wine's `trace:wgl:egl_init EGL client extensions:` line still *prints*
  with an empty-looking tail in v4 — the trace line alone is not the
  verdict; device creation + renderer + read-back pixels are.
- d3d9test **v5_visual** (21:56): same full pass (Create9 0036e380, device
  OK, frontbuffer 0xffff00ff); xdotool found the window (104,123, 632x453).
  Screenshot caveat: the `scrot` taken ~2 s after window creation on this
  WM-less :111 is all-black (`screens/d3dtest_v5_visual.png`) — the frame
  was captured before the window's content was presented to the root
  window. Pixel evidence for this env therefore rests on the
  `GetFrontBufferData` read-back (twice), and for the game itself on the
  main line's real title screenshots. An earlier launcher bug in this
  script (extra `wine` argv token, no window at all) was found and fixed;
  the failed first attempt is `logs/d3dtest_v5_visual.wine.log` at 21:53.
- Perf data point: 234 Clear+Present frames in 25 s ≈ **9.4 fps** for a
  trivial loop under qemu TCG (Wine boot dominates wall-clock); the main
  line reports the game title/story run at low but usable speed under
  llvmpipe+TCG.
- Cross-check: this env's qemu is **8.2.2**, the main line's is 10.0.2 —
  post-fix, both pass every stage; the qemu-version axis of the original
  investigation matrix is thereby answered (not the differentiator).
  Likewise `GALLIUM_DRIVER` selection never needed forcing: llvmpipe
  initializes correctly once its library closure is complete, so the
  softpipe-vs-llvmpipe JIT hypothesis is moot.

## 4. Audio track (solved by the main line; independent track from rendering)
The `bgm51.opus` `buf.play()` exceptions (bgm.tjs(329), custom.tjs(1712))
are caught by the game's own try/catch and were **not** assumed to block
the title. Real cause: no audio device and no 32-bit libasound in the
sysroot, so Wine's audio driver never loaded. Fix (main line, env-side):
add `libasound2t64:i386` + `libasound2-data` to the sysroot and point
`ALSA_CONFIG_PATH` at a null-device config (`pcm.!default { type null }`).
Verified there: mmdevapi "Successfully loaded winealsa.drv / Selecting
driver alsa", DirectSound buffer Lock/Unlock streaming (24000-byte
writes), mmdevapi errors 0 — the BGM actually streams into the virtual
device and the exceptions are gone. The game was **not** modified. The enc
line did not independently re-run the game for audio; it inherits the same
shared-sysroot libraries (its `work/deb/` holds the libasound deb the
predecessor fetched for this purpose).

## 5. Staged checklist (KK's gates)
| Stage | Verdict | Evidence |
|---|---|---|
| GL context creation | ✅ | native glxinfo/eglinfo (run2); Wine wgl init clean in v4 |
| Direct3D9 object + device | ✅ | d3d9test v4/v5: Create9 non-NULL, CreateDevice HAL hr=0 |
| Test pixels drawn | ✅ | frontbuffer read-back 0xFFFF00FF (magenta), v4+v5 |
| Title screen | ✅ | main line :99, `screenshots/sanoba-title-screen.png` (repo) |
| Mouse/keyboard input | ✅ | main line: START clicked, menus work |
| Story progresses | ✅ | main line: Chapter 1-1, `sanoba-chapter1-1.png` |
| Audio actually plays | ✅ | main line: winealsa + ALSA null, DS streaming, errors 0 |
| Perf measured | ✅ | d3d9test ≈9.4 fps trivial loop (qemu 8.2.2 TCG); game low-but-playable (main line) |

## 6. Negatives worth keeping
- `-readencoding=Shift_JIS` alone: no effect (already in effect via PE config).
- Old copied prefix: unusable for rendering (WindowMetrics poison) — always fresh.
- Relative-path exe launch: Kirikiri data-path recursion — always absolute `Z:\`.
- `LIBGL_ALWAYS_INDIRECT=1`: fails on host (X_GLXCreateNewContext BadValue) — dead end.
- `UseEGL=N` / GLX route: dead on Wine 11.21 (winex11 is EGL-only); invest line also saw no help from it.
- v3 vendor-dirs variant: pointing `__EGL_VENDOR_LIBRARY_DIRS` at the sysroot broke libEGL.so.1 resolution entirely.
- EGL GBM/Wayland platforms: fail (no /dev/dri, no compositor) — expected, not the bug.
- Static NEEDED/filename audits: **insufficient** for dlopen-time closure — use a runtime dlopen probe.
- libvulkan.so.1 absent: Wine logs it and falls back to GL — harmless for this title.

## 7. Reproduction
- This env: `wine_fresh.sh` (fresh prefix32f + ja locale/LOCPATH) and
  `run_d3dtest.sh <variant>` for the D3D9 gate; launchers `launch_enc_ja*.sh`
  document the earlier (poisoned-prefix) attempts.
- Generic, clone-and-run: **github mehuyu214/win32-env** — commit `16f2384`
  (main line) adds `scripts/games/setup-game-sysroot.sh` (closure + audit +
  EGL probe), `scripts/games/launch-game.sh`, `docs/GAME-RUNBOOK.md`,
  `tools/dlprobe.py`, `tools/eglprobe.py`, title/chapter screenshots.
  This line's additions: `tests/d3d9test.c`, `tests/d3d9test.exe`,
  `tests/run-d3d9test.sh`, and this report as `docs/SANOBA-ENC-REPORT.md`.

Attribution: §1 by the sanoba-enc line; §2 and the GDI data point by the
sanoba-invest line (:101); §3.6/§4 resolution and the game-level proofs by
the main line (:99, vn-trials STATUS.md 2026-11-12 21:36–21:54 JST);
§3.4/§3.5/§3.7 verification by the sanoba-enc line (successor investigator).
