# Architecture optimization — moving work out of QEMU TCG (feasibility study, 2026-11-12)

Design-level investigation (KK's order, 2026-11-12 23:49). No game launches,
no benchmarks, no sysroot changes were performed for this document; it is
based on the workspace's own files, binaries and prior measured reports,
plus upstream sources. The goal it serves: raise the audio delivery ratio
from its measured 0.68 plateau to ≥0.98 and make the unmodified games
comfortable to operate/record — by changing **where code executes**, not
by tuning settings (levels 1–2 live in `docs/AUDIO-INVESTIGATION.md` and
the performance line's ladder).

Legend used throughout: **FACT** = verified from files/binaries/measured
reports in this workspace. **ESTIMATE** = reasoned projection, not
measured. **UNKNOWN** = not determinable without a later experiment.

Policy reminder: the game is never modified; everything below is
environment-side.

---

## 1. Ground truth about this VM (all FACT, measured 2026-11-12)

| Property | Value | Evidence |
|---|---|---|
| Host arch / visible CPUs | x86_64, `nproc` = 4 (≈1.5 effective cores, shared) | `uname -m`, project measurement |
| `/dev/kvm` | **absent** | `ls /dev/kvm` |
| `/dev/dri` | **absent** (no GPU, no render node) | `ls /dev/dri` |
| binfmt_misc | not mounted; registrations are silently swallowed, non-functional | `ls /proc/sys/fs/binfmt_misc/`, `docs/ARCHITECTURE.md` §1 |
| `/proc/sys/abi/` | contains only `vsyscall32`; no `ia32_emulation` toggle reachable | `ls /proc/sys/abi/` |
| Sandbox shape | gofer-type mediated kernel: `ptrace` attach → EPERM, `/proc/<pid>/stack` → EPERM | `docs/ARCHITECTURE.md` §1 |
| Native 32-bit Linux ELF | **instant segfault** (exit 139), static minimal binary, before/after `dpkg --add-architecture i386` | `docs/ARCHITECTURE.md` §1, `~/workspace/vn-trials/STATUS.md` |
| Host kernel config | claims `CONFIG_IA32_EMULATION=y` — but the sandbox's mediated syscall/CPU layer overrides this in practice; the empirical rows above are what count | `zgrep /proc/config.gz` vs. measured behaviour |
| Host native GL | Mesa 25.2.8 x86_64 present (`libEGL_mesa.so.0`, `libgallium-25.2.8`), llvmpipe healthy: native `glxinfo` direct=Yes, GL 4.5 | enc report §3.4; `ldconfig -p` |
| X server | `/usr/bin/Xvfb`, ELF64 native | `readelf -h /usr/bin/Xvfb` |

The one-sentence summary of the sandbox: **x86_64 code runs natively;
32-bit code segments cannot execute natively in any form** — neither as a
standalone ELF32 process nor as a compatibility-mode segment inside a
64-bit process (see §3). Any architecture for this VM must therefore get
its speed from *minimising the amount of code that has to be emulated at
all*, because the code that is emulated runs under QEMU TCG.

## 2. Current execution path — where a D3D9 draw call actually goes (FACT)

Launch chain (from `scripts/games/launch-game.sh` and
`sanoba-audio/scripts/common.env`, identical in structure):

```
q32sup (native x86_64 supervisor, ptrace+seccomp)
└─ qemu-i386 10.0.2  -cpu max -L sysroot32/root        [TCG translation]
   └─ Wine 11.21 x86 loader (ELF32)                     [TCG]
      └─ sanoba_trial.exe (PE32, Kirikiri Z)            [TCG]
```

Inside the game process, one `Direct3DDevice9::DrawPrimitive` flows:

| # | Hop | Code | Bitness / form | Executes |
|---|---|---|---|---|
| 1 | Kirikiri BasicDrawDevice → `Direct3DCreate9` / draw calls | game exe | PE32 | TCG |
| 2 | D3D9 → OpenGL translation | Wine `d3d9.dll`, `wined3d.dll` (builtins) | PE32 | TCG |
| 3 | GL entry + windowing glue | Wine `opengl32` PE side → `win32u` → `winex11.drv` Unix side | PE32 → **ELF32** (`lib/wine/i386-unix/winex11.so`) | TCG |
| 4 | EGL dispatch | glvnd `libEGL.so.1` → `libEGL_mesa.so.0` (sysroot) | ELF32 | TCG |
| 5 | GL state tracker + rasterizer | Mesa `libgallium-25.2.8` → **llvmpipe**, shaders JIT-compiled by `libLLVM.so.20.1` | ELF32 | TCG |
| 6 | Present | 32-bit `libX11`/`libxcb` (sysroot) → X protocol | ELF32 | TCG |
| 7 | Display | **Xvfb** | ELF64 | **native** |

Evidence for the table: the current Wine build
(`~/workspace/vn-trials/wine32/wine-11.21-x86`) ships only
`i386-unix` + `i386-windows`; `readelf` on its `i386-unix/winex11.so` →
ELF32/80386. The launch scripts pin the guest GL stack into the sysroot
(`__EGL_VENDOR_LIBRARY_DIRS=…/sysroot32/root/usr/share/glvnd/egl_vendor.d`,
`LIBGL_DRIVERS_PATH=…/sysroot32/root/usr/lib/i386-linux-gnu/dri`), and
`readelf` on the sysroot's `libEGL_mesa.so.0` → ELF32/80386. In-game the
renderer string is `llvmpipe (LLVM 20.1.2, 256 bits)` (runbook).

Audio path (for completeness): game (PE32) → `dsound`/`mmdevapi` (PE32) →
`winealsa`/`winepulse` Unix side (ELF32) → 32-bit `libasound`/`libpulse`
→ **PulseAudio daemon: native x86_64 host process** (audio line) or an
ALSA null device. The heavy audio endpoint is already native; the
delivery-ratio problem is the *producer's* cadence under TCG, not the
daemon.

Also already native today: `q32sup` itself, Xvfb, the PulseAudio daemon,
and any host-side capture tooling (ffmpeg/x11grab). Everything else —
wineserver, services.exe, explorer, every Wine process — is ELF32 under
qemu-i386, with q32sup re-wrapping every child `execve` back into
qemu-i386 (mechanism: `docs/ARCHITECTURE.md` §4).

### 2.1 The double-JIT tax (the suspicion, stated precisely)

llvmpipe is itself a JIT: it compiles GLSL to LLVM IR and then to i386
machine code at runtime. On a native i386 host that generated code would
then run at full CPU speed. Here, QEMU TCG must translate those
JIT-generated i386 blocks into x86_64 host code on the fly — including
re-translation when translation blocks churn — and TCG-executed code
carries the usual order-of-magnitude-class slowdown for tight loops
(general TCG behaviour; ESTIMATE as applied to this workload). So
rasterization pays three times: (a) LLVM JIT compilation itself runs
under TCG (shader-compile stalls), (b) TCG translation of the JIT output,
(c) TCG execution inefficiency of the rasterizer inner loops, with
llvmpipe's 256-bit vector code decomposed by TCG.

Measured anchors consistent with this (not a proof of the split):
- The standalone D3D9 bisect test (trivial `Clear`+`Present` loop)
  reaches ≈**9.4 fps** (234 frames / 25 s) under this stack (enc report
  §3.7; note the loop is present-bound and Wine boot dominates wall
  clock — it is an anchor, not a rasterizer benchmark).
- Load-shedding raised the audio delivery ratio 0.39 → 0.68 and then it
  **plateaued** despite further tuning (`docs/AUDIO-INVESTIGATION.md`).

**UNKNOWN (honest gap):** no per-component profile exists yet. Nobody has
measured what fraction of a frame's cost is llvmpipe vs. wined3d
translation vs. game logic vs. raw TCG overhead. The performance line's
ladder (LP_NUM_THREADS, softpipe comparison, tb-size) will narrow this;
the PoC in §6 includes an attribution step before any game-level claim.

## 3. Correction of the record: the WoW64 asset and its test history

Asset (FACT): `~/workspace/vn-trials/wow64/` still contains
- `wine-wow64.tar.xz` — Kron4ek **wine-11.21-amd64-wow64**, 97,860,312 B
  (93.3 MiB compressed / 809.1 MiB uncompressed, `xz -l`), and
- `wine-staging-wow64.tar.xz` (99,958,200 B), plus both builds already
  extracted (`wine-11.21-amd64-wow64/`, `wine-11.21-staging-amd64-wow64/`).

The assumption that this build "was never set up or tested" is **not**
what the workspace record says. `~/workspace/vn-trials/STATUS.md`
(2026-11-12 15:4x–16:0x, "WoW64 deep-dive") and `docs/ARCHITECTURE.md` §1
record an extensive test: fresh-prefix wineboot (wedged in `rundll32
setupapi`), a hybrid prefix (system Wine 9.0 prefix + Kron4ek
`i386-windows` files in `syswow64`), and test programs — syswow64
`cmd.exe`, `hostname.exe`, a mingw-built `hello32.exe`, the **real Sanoba
trial exe** and the **real Stella trial exe** — on **both** the amd64-wow64
and staging-amd64-wow64 builds. Every run shows the identical signature:

- `NtCreateUserProcess` succeeds;
- `wow64.dll` / `wow64cpu.dll` / `wow64win.dll` are **never mapped**; no
  32-bit DLL loads; the child prints nothing;
- the child syscall-loops at the **first 32-bit compatibility-mode
  transition** (utime 872 / stime 1946 ticks in one sample, page-fault
  freeze).

Conclusion already recorded then, and still standing: the block is in
the sandbox's CPU/syscall layer, below Wine. This matters for planning:
"try WoW64" is not an unexplored cheap experiment — it is a measured
dead end in its native form, and §4 explains the one form in which the
WoW64 *split* can still be obtained here.

## 4. The decisive WoW64 fact (verified from the binaries)

The Kron4ek amd64-wow64 build's layout, inspected directly:

```
lib/wine/
├── i386-windows/     PE32 DLLs: d3d9.dll, wined3d.dll, ntdll.dll, …
├── x86_64-unix/      ELF64 .so: winex11.so, opengl32.so, winealsa.so, winepulse.so
└── x86_64-windows/   PE64 DLLs: wow64.dll, wow64cpu.dll, wow64win.dll, …
```
There is **no `i386-unix` directory at all**. `readelf`: `bin/wine` and
`bin/wineserver` → ELF64 x86-64; `x86_64-unix/winex11.so` → ELF64 x86-64;
`i386-windows/wined3d.dll` → PE32.

So in new-WoW64 mode the process is a **native 64-bit process** in which:

| Component | Form | Would execute |
|---|---|---|
| wine loader, wineserver, services | ELF64 | **natively** |
| Unix-side drivers: `winex11`, `opengl32` Unix side, `winealsa`, `winepulse`, `win32u`, ntdll Unix side | ELF64 `.so` | **natively** |
| Host libraries they call: **Mesa libEGL/libGL (x86_64)**, libX11, libasound/libpulse clients | ELF64 (host's own) | **natively** |
| **llvmpipe rasterizer + LLVM JIT** | inside host x86_64 Mesa | **natively** |
| PE-side DLLs: game exe, Kirikiri, `d3d9.dll`, **`wined3d.dll`**, `ntdll`/`kernel32` PE halves | PE32 | 32-bit compat-mode segments |
| Mode crossings PE↔Unix | `wow64`/`wow64cpu` thunk layer (PE64) | CPU segment switch (CS 0x23↔0x33) inside the process |

**Answer to the deciding question: yes — in new-WoW64 mode the entire
Unix-side graphics stack (`winex11` + Mesa + llvmpipe) is native 64-bit
code.** WoW64's split is exactly the split this project wants: only PE
code (the game and Wine's PE-side translation layer, incl. wined3d's
D3D9→GL logic) stays 32-bit; everything heavy and Unix-side — above all
the rasterizer — leaves the emulator entirely. On an ordinary x86_64
Linux host the 32-bit PE code *also* runs natively (compat mode is a CPU
feature, not emulation), so no emulator is involved at all.

On **this** VM the single blocker is the compat-mode segment transition
itself, which the sandbox's mediated kernel breaks (§1, §3). WoW64
alone therefore cannot work here — not because of anything in Wine, the
build, or the prefix (all were varied in the deep-dive), but because the
32-bit code has no working way to execute natively.

That leaves exactly two families of routes to the same split:

- **(A) Keep the PE process emulated wholesale** (today's qemu-i386
  process), but move the *rendering* out of it across a process boundary
  → the virgl/vtest candidate (C1). The seam moves from "PE↔Unix inside
  Wine" to "GL command stream between two processes".
- **(B) Keep the WoW64 process shape** (native 64-bit process, native
  Unix side) and replace the broken compat-mode switch with an
  **in-process CPU emulator** for the PE code → the emulator-DLL
  candidate (C2). This is the Hangover architecture, which upstream Wine
  now supports as a designed interface (§5, C2).

## 5. Candidates

### C1 — virgl over vtest: rasterization in a native host process ⭐ recommended next

**Mechanism.** Mesa's virgl Gallium driver does not rasterize; it
serializes GL state/draw commands into the virgl protocol. virglrenderer
(the library inside `virgl_test_server`) deserializes and executes them
against a real GL stack. The two sides normally meet through a
virtio-gpu device — but virglrenderer also ships a **vtest** transport:
a plain Unix socket, built for testing virgl *without* a VM. The Flatpak
and Podman projects use exactly this to give sandboxed apps host-side GL
with no VM and no KVM (Sebastian Wick, "Improving the Flatpak Graphics
Drivers Situation"). In our stack: the guest keeps qemu-i386 + q32sup +
32-bit Wine unchanged; only the guest Mesa's driver changes — llvmpipe
out, virgl in. The server is a native x86_64 process rendering on the
host's native Mesa/llvmpipe.

**Fit to this VM (FACT checks).**
- No KVM, no virtio device, no system-mode emulation needed — vtest is
  a socket between two user processes. ✔
- The guest driver **already exists in the sysroot**:
  `sysroot32/root/usr/lib/i386-linux-gnu/dri/virtio_gpu_dri.so` (the
  virgl Gallium driver, ELF32, part of Ubuntu's standard Mesa set) —
  and `LIBGL_DRIVERS_PATH` in the launch scripts already points at that
  directory. No guest Mesa rebuild is required to start.
- The host server is packaged: `virgl-server` 1.0.0-1ubuntu2 +
  `libvirglrenderer1` in Ubuntu noble/universe (apt metadata checked;
  not installed — fetch the .debs into the workspace, per project
  practice of download-only extraction).
- The vtest protocol negotiates its version between client and server
  (Mesa has explicit negotiation code), which softens the
  Mesa-25.2-client vs. virglrenderer-1.0-server version gap.
- Presentation: with vtest, rendered results are read back and the
  guest-side software winsys puts the image on screen via X
  (Airlie's description of the harness). Mesa's EGL X11 platform has a
  software presentation path of exactly this shape.

**Required changes.** (1) Fetch/extract `virgl-server` (+deps) into the
workspace; run `virgl_test_server` natively with a private socket path.
(2) Launch env for the guest: select the virgl driver and point it at
the socket (gallium driver override + `VTEST_SOCKET_NAME` — exact env
surface to confirm in PoC step 1). (3) Nothing in Wine, qemu, q32sup,
or the game.

**Expected effect (ESTIMATE).** Removes cost classes (a)–(c) of §2.1
for rasterization: no LLVM JIT under TCG, no TCG translation of JIT
output, native llvmpipe execution. The guest retains: game logic,
wined3d translation, virgl command encoding (a thin serializer — vastly
cheaper than rasterizing), and per-frame readback presentation. For a
2D VN (texture uploads + quad compositing) a **3–10× improvement of the
render-bound portion** is a reasonable planning estimate; what that does
to the 9.4 fps anchor and to the 0.68 delivery ratio depends on the
un-profiled split (§2.1), which is why the PoC measures both before any
game-level claim.

**Compatibility risks.**
- The presentation seam is the main UNKNOWN: whether winex11's EGL
  usage (window surfaces on X11) composes cleanly with a vtest-backed
  virgl screen under Xvfb, and the per-frame readback cost at 1280×720
  (the final `XPutImage` leg runs through the guest's 32-bit X11 client
  under TCG — a ~3.7 MB/frame copy; measure, don't assume).
- virgl's GL ceiling: virgl exposes up to ~GL 4.3-class features on a
  GL 4.5 host. wined3d's D3D9 path needs far less. Low risk.
- vtest is upstream's *test* harness; its maintainers do not promise a
  production security/stability boundary. Acceptable here (single-user
  VM, our own socket, our own processes) but recorded honestly.
- One GL connection per rendering process; `virgl_test_server` forks
  per connection. Only game processes render. Low risk.
- 32-bit client ↔ 64-bit server is the normal Flatpak arrangement; the
  protocol is fixed-width streams. Low risk.

**Variant (note only):** the same server also speaks **Venus** (Vulkan
serialization, `virgl_test_server --venus`). If a future title's best
path were D3D→Vulkan (DXVK/vkd3d are PE-side and would still be
emulated) → Venus → host lavapipe (native), the transport already
exists. More moving parts than virgl-GL for D3D9 titles; not the first
move.

### C2 — WoW64 + in-process emulator DLL (the modern Hangover) — best end state, biggest build

**Mechanism.** §4's table has one row that needs a CPU: the PE32 code.
Upstream Wine (10.0+) implements a **CPU-emulation interface** for
exactly this: the WoW64 layer can delegate execution of the foreign-arch
PE code to an external emulator library instead of running it in a CPU
compat mode. This is how x86 Windows apps run on ARM64 hosts today —
Wine's code (including the whole Unix side and Mesa) is native ARM64;
only the app's PE code is JIT-translated by the emulator DLL inside the
same process: FEX ships `libwow64fex.dll` (i386 guests) /
`libarm64ecfex.dll` (x86_64 guests); Box64 ships `wowbox64.dll`; Valve
ships this pairing in Proton for ARM64. The emulator is selected via
the `HKLM\Software\Microsoft\Wow64` registry keys.

**Fit to this VM.** The architecture fits perfectly — it is the only
candidate that removes *everything* except PE code from emulation:
Mesa/winex11 native (as in §4), **plus** native wineserver, native
X11/audio client stacks, no per-process qemu, no q32sup execve
patching, and PE↔Unix crossings become in-process calls instead of
qemu syscall emulation. **But:** every existing emulator DLL is a
*foreign-arch PE* (ARM64). For an x86_64 host there is **no
off-the-shelf emulator DLL** — one would have to be built: QEMU's TCG
(i386 target) wrapped behind Wine's wow64 emulator interface, in the
spirit of the original Hangover (which compiled qemu as Wine DLLs) but
against the now-stable upstream interface instead of Hangover's Wine
fork patches.

**Required changes.** A real development project: build a
`wow64qemu`-style DLL (PE64, x86_64) embedding qemu's TCG core;
implement the interface surface FEX implements (context
save/restore/switch, syscall thunking into ntdll); integrate with the
Kron4ek wow64 build already on disk (§3). Person-weeks class, high
uncertainty (ESTIMATE), and it must be debugged inside a sandbox whose
ptrace restrictions already hamper low-level work.

**Expected effect (ESTIMATE).** Highest ceiling of all candidates: the
§4 split plus native server/client processes. PE-side emulation cost
(game + wined3d) remains TCG-class, comparable to today's qemu-i386 —
this candidate does not make the *game's own code* faster, it removes
everything around it.

**Compatibility risks.** Interface drift across Wine versions;
qemu-TCG-as-a-library is not an upstream-supported qemu configuration;
debugging an emulator DLL inside the gofer sandbox may hit the same
walls that killed other low-level approaches. Verdict: **the right
long-term track; the wrong next step.**

### C3 — Native new WoW64 alone

**Verdict: dead, measured.** Two builds (amd64-wow64, staging), hybrid
and fresh prefixes, five test programs including the real Sanoba and
Stella exes — all fail identically at the first compat-mode transition
(§3). Nothing about Wine configuration can fix a sandbox that cannot
execute 32-bit code segments. Do not re-attempt without a change in the
sandbox itself.

### C4 — qemu-x86_64 hosting the WoW64 Wine build

**Mechanism.** Run the ELF64 wine process under `qemu-x86_64` (the
binary is already in the tree: `vn-trials/qemu10/usr/bin/qemu-x86_64`,
QEMU 10.0.2). TCG emulates the whole 64-bit process, including the
compat-mode segments for PE32 code (TCG implements segment switching
in software, so the sandbox's native-transition block does not apply).

**Why it ranks low.** Mesa would run as **TCG-translated x86_64 code** —
the rasterizer stays inside an emulator; the double-JIT tax of §2.1
persists (llvmpipe JIT output re-translated by TCG). Wins are limited
to: one emulator generation for everything, 64-bit llvmpipe code
quality, and qemu's own execve-following for child processes (children
stay emulated automatically). Whether qemu-user's handling of Wine's
specific wow64 switch machinery (LDT manipulation, signal frames, TLS
switching) works at all is **UNKNOWN** — historically fragile.
ESTIMATE: modest and uncertain gains, real integration risk. Only
worth a cheap probe (hello32 under wow64 Wine under qemu-x86_64) if
C1's seam fails.

### C5 — FEX (as emulator, or via its thunk libraries)

**Verdict: not runnable on this host.** FEX is an x86/x86_64 user-mode
emulator **for AArch64 hosts only** (upstream packaging: "supports only
AArch64 as a host"; requires ARMv8.0+). There is no supported x86_64-host
build to run. Its value to this project is as design evidence, twice
over: (a) its WoW64 emulator DLLs are C2's existence proof; (b) its
ThunkLibs list — `libEGL, libGL, libSDL2, libX11, libasound, libdrm,
libvulkan, libwayland-client` forwarded to host-native libraries — is
the canonical answer to "which library seams are worth forwarding when
an emulator owns the process". Note that FEX-style ELF-level thunking
cannot be transplanted onto our qemu-i386 stack directly: the thunk
mechanism lives inside the emulator's own process model.

### C6 — Box86 / Box64 family

**Verdict: technique donor only.** Box64/Box32 target non-x86 hosts
(ARM64, RISC-V, LoongArch); there is no x86_64-host port to run here.
Box64's contribution to this design space — wrapped native libraries
for hot APIs, and `wowbox64.dll` as another C2-style emulator DLL
(ARM64 PE) — is already accounted for in C2/C5. Nothing separately
actionable on this VM.

### C7 — virglrenderer via virtio-gpu (system-mode)

**Verdict: inapplicable here.** The virtio-gpu transport requires a
device model, which exists only in system-mode emulation (qemu-system
+ a guest OS). User-mode qemu has no devices at all; there is also no
`/dev/kvm` (TCG system emulation of a whole Windows guest would be a
different, far heavier universe and abandons the Wine approach
entirely). The vtest transport (C1) exists precisely to get
virglrenderer's benefits without this requirement.

### C8 — Custom EGL/GL proxy (hand-built thunk layer)

**Mechanism.** A guest-side 32-bit shim replacing libEGL/libGL that
marshals calls over a socket/shared memory to a native 64-bit GL
executor process.

**Why it ranks below C1.** An EGL-only proxy cannot work: EGL is just
context/surface management — the GL calls (and thus llvmpipe) would
still execute in the guest. A *GL-level* proxy is a stateful,
pointer-heavy marshalling problem (buffers, shaders, textures, sync) —
i.e. re-implementing virgl, badly, alone. C1 is the upstream,
maintained implementation of this exact idea. C8 survives only as a
fallback if C1's presentation seam proves impossible *and* C2 is
rejected on effort — and even then it should speak the virgl protocol
rather than invent one.

### C9 — Indirect GLX (let the native X server render)

**Verdict: dead, measured twice.** (1) Wine 11.21's winex11 is
EGL-only; removing libEGL does not fall back to GLX (runbook §4).
(2) Host-side indirect GLX itself fails on this Xvfb at the protocol
level (`LIBGL_ALWAYS_INDIRECT=1 glxinfo` → `X_GLXCreateNewContext`
BadValue; enc report §3.4). Closed.

### C10 — Native 64-bit wineserver with emulated 32-bit clients (Level-2 micro-split)

**Mechanism.** Keep today's stack; replace only the wineserver binary
with the ELF64 one from the already-downloaded wow64 build (§3).
Wine's server protocol is bitness-independent and both builds are
Kron4ek 11.21, so the protocol version should match. q32sup passes
ELF64 execve targets through natively by design
(`docs/ARCHITECTURE.md` §4), so the server would run natively while
clients stay under qemu-i386.

**Expected effect (ESTIMATE).** wineserver is chatty (window/message/
registry/synchronization traffic); removing it from TCG should give a
small, broad responsiveness gain — single-digit to low-double-digit
percent on UI-heavy paths, near zero on raster-bound paths. Cheap to
test (one binary swap, one boot test) once the measurement lines free
the VM; risk is a protocol-version mismatch, which fails loudly at
startup rather than silently. This is a level-2 item, listed here
because it is the only *other* place a native/emulated seam already
exists in the current architecture.

## 6. Ranking and the PoC sketch for C1 (virgl over vtest)

| Rank | Candidate | Removes Mesa from TCG? | Removes more? | Effort | Risk | Status |
|---|---|---|---|---|---|---|
| 1 | **C1 virgl/vtest** | **Yes** | No (render only) | Days | Medium (presentation seam) | **PoC below** |
| 2 | C2 WoW64 + emulator DLL | Yes | Yes — everything except PE code | Person-weeks+ | High | Long-term track |
| 3 | C10 native wineserver | No | Server process only | Hours | Low | Quick test later |
| 4 | C4 qemu-x86_64 + WoW64 | No (TCG, 64-bit flavour) | No | Days | Medium-high | Fallback probe only |
| 5 | C8 custom GL proxy | Yes, if ever finished | No | Person-weeks | High | Dominated by C1 |
| — | C3 native WoW64 | — | — | — | — | **Dead (measured)** |
| — | C9 indirect GLX | — | — | — | — | **Dead (measured)** |
| — | C7 virtio-gpu | — | — | — | — | Inapplicable (user-mode) |
| — | C5 FEX / C6 Box64 | — | — | — | — | Wrong host arch; design evidence only |

### PoC plan for C1 — DO NOT RUN until the measurement lines release the VM

Phase 0 — host side, no guest, no game.
1. Fetch `virgl-server` + `libvirglrenderer1` (.deb, download-only) into
   the workspace; extract; start `virgl_test_server` natively on a
   private socket (e.g. `/tmp/virgl-arch.sock`).
2. PASS: server starts, binds the socket, and initializes against host
   Mesa (llvmpipe) without a rendernode. KILL: server cannot create any
   context without `/dev/dri` in this build → re-scope (build
   virglrenderer from source with surfaceless support, or stop).

Phase 1 — guest probe, no Wine, no game.
3. Run the existing `tools/eglprobe.py` under plain qemu-i386 (no
   supervisor needed) with the launch env changed in exactly one way:
   gallium driver = virgl (driver-override env) + `VTEST_SOCKET_NAME`
   pointing at the Phase-0 socket. Also run the enc line's native i386
   `eglinfo -B` the same way as a second angle.
4. PASS: `eglInitialize` OK on the **X11 platform** (surfaceless alone
   is not sufficient) and the renderer string identifies the virgl/host
   path (not `llvmpipe` in-guest). Measure probe wall time vs. the
   llvmpipe baseline. KILL: the vtest winsys cannot be selected without
   a DRM fd in Ubuntu's Mesa 25.2 build, or X11-platform init fails
   while surfaceless works → C1's seam is broken; stop and re-rank
   (C2 scoping, C4 probe).

Phase 2 — D3D gate, still no game.
5. Run `tests/run-d3d9test.sh` (the enc line's bisect) under the virgl
   env, same methodology as the 9.4 fps baseline (25 s window).
6. PASS: `CreateDevice` HAL hr=0 **and** front-buffer read-back =
   `0xFFFF00FF` **and** fps materially above 9.4. Record the fps and the
   guest/host CPU split (`top` per process) for the report.
   KILL: read-back wrong, hangs, or fps ≤ baseline after the
   presentation cost — the readback/putimage leg is eating the win;
   stop, document numbers, re-rank.

Phase 3 — game gate (only with the VM free, and after the perf line's
profiling rider in §6.1).
7. Sanoba at 1280×720, conditions identical to the cap-e2/e3 runs:
   title-screen screenshot, then a 60 s PulseAudio capture.
8. PASS: title renders correctly **and** delivery ratio
   (`tools/delivery_ratio.py`) materially above the 0.68 plateau.
   Gate v2 still applies in full — including KK's ear test on a 30 s
   proof before any deliverable is claimed. A ratio that does not move
   would mean the bottleneck was never the rasterizer (see §2.1's
   honest gap) — that negative result is valuable and must be reported
   as such, not tuned around.

### 6.1 Attribution rider

Before Phase 3, consume the performance line's in-flight measurements
(tb-size verdict, LP_NUM_THREADS sweep, a softpipe-vs-llvmpipe d3d9test
comparison) so the virgl delta can be attributed to rasterization
rather than to load noise. If softpipe ≈ llvmpipe fps on d3d9test, the
render path is *not* the dominant cost and C1's priority drops — say so
in the follow-up report and re-rank before spending Phase-3 effort.

## 7. Open questions (UNKNOWN until a later line tests them)

1. Exact env surface for selecting virgl+vtest in Ubuntu's Mesa 25.2.8
   i386 build (driver override variable + socket variable + whether the
   loader needs a dummy DRM fd). Phase 1 answers this.
2. Whether winex11's EGL window surfaces present correctly through the
   vtest readback path under Xvfb, and the real per-frame cost of that
   leg under TCG. Phases 1–2 answer this.
3. virglrenderer 1.0.0 (noble) protocol compatibility with a Mesa
   25.2.8 client over vtest (negotiation exists; the pairing is
   untested). Phase 1 answers this.
4. qemu-x86_64's handling of Wine 11's wow64 switch machinery (only
   relevant if C4 is ever probed).
5. The true per-component cost split of a Sanoba frame (llvmpipe vs.
   wined3d vs. game logic vs. TCG fixed overhead). The perf line's
   ladder + §6.1 narrow this; a full answer may need in-guest
   profiling that the sandbox's ptrace restrictions complicate.
6. Whether an x86_64-host wow64 emulator DLL exists anywhere
   off-the-shelf (none found in this study; FEX/Box64 DLLs are ARM64
   PEs). If one surfaces, C2's effort estimate collapses and it should
   be re-ranked immediately.

## 8. Sources

Workspace (primary): `docs/ARCHITECTURE.md` (§1 sandbox measurements,
§4 q32sup mechanism), `docs/GAME-RUNBOOK.md` (§4 GL stack),
`docs/AUDIO-INVESTIGATION.md` (delivery-ratio method, 0.68 plateau,
verified launch config), `docs/GAME-COMPAT.md`,
`~/workspace/vn-trials/STATUS.md` (WoW64 deep-dive, 2026-11-12
15:4x–16:0x), `~/workspace/sanoba-enc/REPORT.md` (§3.4 host GL gate,
§3.7 d3d9test 9.4 fps), `scripts/games/launch-game.sh`,
`~/workspace/sanoba-audio/scripts/common.env` (read-only),
`readelf`/`xz -l`/directory inspection of
`~/workspace/vn-trials/wow64/wine-11.21-amd64-wow64/` and of the current
`wine-11.21-x86` build and sysroot, live checks of `/dev/kvm`,
`/dev/dri`, `/proc/sys/fs/binfmt_misc`, `/proc/sys/abi`, `apt-cache
policy virgl-server`.

Upstream: Wine 10.0 release notes (x86 emulation interface for WoW64;
emulator selected via `HKLM\Software\Microsoft\Wow64`, FEX implements
it as ARM64EC); FEX-Emu project (AArch64 hosts only; ThunkLibs /
library forwarding for libEGL/libGL/libasound/…; `libwow64fex.dll`);
Sebastian Wick, "Improving the Flatpak Graphics Drivers Situation"
(vtest as a Unix-socket transport to virglrenderer, used by Flatpak /
Podman without a VM); David Airlie on the virgl test harness (vtest
winsys, readback + putimage presentation); Mesa virgl vtest winsys
sources (protocol version negotiation).
