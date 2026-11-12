# Game compatibility status (2026-11-12)

Per-game results for running **unmodified** 32-bit Windows trial games on
this VM (QEMU i386 TCG + 32-bit Wine 11.21 + q32sup, llvmpipe software
rendering, no GPU). Policy, binding for all lines: **never modify a
game** — no script rewrites, no archive changes, no config hacks; every
fix is environment-side. The base recipe is `docs/GAME-RUNBOOK.md`
(fresh prefix per game, `LANG=LC_ALL=ja_JP.UTF-8` + locally generated
locale via `LOCPATH`, absolute `Z:\` exe path, ALSA null audio config,
shared sysroot with the GL/audio dependency closure).

## Status table

| Game | Status | Evidence / notes |
|---|---|---|
| Sanoba Witch trial （サノバウィッチ体験版, Kirikiri Z) | ✅ **Playable** | Title → START → Chapter 1-1 story, SAVE/LOAD, SYSTEM (display + sound tabs), BACKLOG all working; 26 screenshots, several videos. Audio streams (see `docs/AUDIO-INVESTIGATION.md` for the separate capture-pacing problem). |
| Stella （喫茶ステラと死神の蝶 体験版， Kirikiri) | ✅ **Boots + title + in-game** | Fullscreen title after a long white fade (~4 min); opening text scenes and message-window UI reached; 7 screenshots + title video. |
| Sakura no Toki （サクラノ刻 第I章体験版） | ⚠️ **Boots, never renders** | Window opens with the correct title 「サクラノ刻第I章体験版 - Ver1.0.0」, client area stays solid white for 3+ min. An initial pack-file error was fixed by adding a `game.pfs` hardlink (the pack is looked up by exe base name). Engine starts and creates savedata; no frame is ever presented. Separate diagnosis track, not yet run. |
| RE:D Cherish! （体験版プラス) | ❌ **Segfault after first-run dialog** | First-run dialog （初起動時のウインドウモードを設定します） works; after clicking OK the guest dies: `qemu: uncaught target signal 11 (Segmentation fault)`. Identical in plain and Wine-virtual-desktop launches. |
| Majikoi （真剣で私に恋しなさい！ 体験版） | ❌ **Extraction fixed; now segfaults like RE:D** | Was an incomplete copy (see below). With the complete tree it boots to the **same signal-11 signature** as RE:D Cherish!, immediately after the libEGL DRI3 warning pair; screen stays black. Shared environment root cause suspected. |
| Senren Banka （千恋＊万花, Steam) | ⏭️ **Blocked** | Licence is on the owner's Steam account, but downloading needs the owner's Steam mobile-app QR approval. Not an environment problem. |

(Geminism, 64-bit / Unity + Utage, was verified playable earlier via a
Wine virtual desktop and is not part of this 32-bit ladder.)

## Majikoi: the extraction defect (FIXED)

The trial ships as a 3-part RAR5 SFX (`hawkeye_0027.part1.exe /
.part2.rar / .part3.rar`, 3,279.8 MB total, 34 entries). The only
extracted tree on the VM (3.5 GB, 33 files) was missing **exactly one
entry — the main game executable itself**:

- `majikoi_trial_special2/まじこい.exe` (1,846,784 B, PE32 GUI),
  stored in part 3 under its Japanese filename.
- Everything else matched the archive inventory byte-for-byte
  (all `.pac` data files, Launcher/Setup/Filechk/StartUpTool/Uninstall,
  Movie/*.mpg, DirectX/ redist, readme).

The bundled Launcher ran and honestly reported the missing exe
("game exe not found"), which is what exposed the defect. Fix:
**complete re-extraction with unrar-nonfree 7.00** (obtained as a .deb
and unpacked into the workspace — no system install) into
`win32-compat/games/majikoi/`; all 34 entries present, extraction exit 0.
Note `7z` cannot do this archive: it fails on the RAR5 compression
method (`m3:25`, Unsupported Method).

## The shared crash signature (Majikoi + RE:D Cherish!)

Both games now die identically:

```
wine processes exec → libEGL prints the DRI3 warning pair →
qemu: uncaught target signal 11 (Segmentation fault)
```

Sanoba and Stella (both Kirikiri) survive the same stack. Import tables
(host-side `objdump`) show the two engines differ, so the faulting module
may differ despite the identical outer signature:

- `まじこい.exe`: d3d9.dll + **d3dx9_35.dll** + DINPUT8 + DSOUND +
  MSVFW32. (Its bundled `DirectX/` folder is exactly the AUG2007
  d3dx9_35 redist.)
- RE:D Cherish! exe: **no** d3d9 import; its `Pal.dll` uses gdiplus +
  DSOUND + vorbisfile (FX.dll / RESOURCE.dll alongside).

Ranked hypotheses (from the compat line's `DIAG-PLAN.md`):

1. **llvmpipe LLVM JIT vs QEMU TCG** — JIT-compiled shader code faults
   when a game compiles real shaders; Kirikiri's fixed-function path
   never triggers it. Test: `GALLIUM_DRIVER=softpipe`.
2. **`-cpu max` feature exposure** — a CPUID leaf the engines
   mis-handle. Test: `-cpu pentium3`, then `qemu32`.
3. **QEMU 10.0.2 TCG regression**. Test: QEMU 8.2.2 static.
4. **Wine builtin `d3dx9_35` stub** (Majikoi only). Test: a
   `WINEDEBUG=+seh` run names the faulting module; if it is d3dx9_35,
   the proposed fix is a *prefix-side* DLL override using the native
   d3dx9_35 from the game's own bundled cab — still not a game edit.

Planned run order (one variable at a time, 1280×720):
`+seh` backtrace for Majikoi → softpipe variant → `-cpu` variants →
QEMU 8.2.2 → same ladder for RE:D Cherish!. Sakura no Toki is a separate
track: `+loaddll`/`+d3d` boot log, the EGL probe inside its prefix, and a
check for component load gaps Sanoba never needed (d3dcompiler, d3dx9,
xinput, mfplat). **Regression rule:** after any proposed shared change,
Sanoba + Stella title boots are re-verified before the change is
adopted; sysroot changes are proposals to the repo, applied centrally,
never unilaterally by an investigation line.

**Current state: this ladder is PAUSED.** Under the owner's
load-shedding order, all heavy emulation on the compat line is on hold
while the audio-pacing fix (`docs/AUDIO-INVESTIGATION.md`) has VM
priority; the diagnostic scripts are prepared and the line resumes on
release.
