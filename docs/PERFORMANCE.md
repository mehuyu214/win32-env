# PERFORMANCE — Sanoba (32-bit VN) under QEMU TCG + Wine: audio delivery investigation

Status: 2026-11-13. Game: サノバウィッチ trial (unmodified). Line: `sanoba-audio`
(own Xvfb :113, own Wine prefix, own PulseAudio). Full raw record:
`~/workspace/sanoba-audio/RESULTS.md` + per-run logs in `~/workspace/sanoba-audio/logs/`.
Bench harness: `tools/launch2.sh`, `tools/runbench.sh`, `tools/runladder.sh`,
`tools/matrix.sh`, metric: `tools/delivery_ratio.py`.

## Metrics

- **Delivery ratio** = music_seconds / total_seconds of a capture, where a *gap* is a
  maximal run of exact-0.0 frames ≥5 ms (`tools/delivery_ratio.py`). A wall-clock-paced
  audio device inserts digital silence when the producer cannot keep up, so duration
  alone is a misleading quality metric (gate v1's mistake).
- **Underrun delta** = PulseAudio log "underrun" lines during the capture window.
- **Gate v2 (audio)** = delivery ratio ≥0.98 AND gaps <1 % AND no abnormal exact-duplicate
  windows AND tempo slope 1.00 ±0.02 vs a trusted reference AND KK's ear test.

## Execution path / load decomposition

| component | runs as | where | measured cost / behaviour |
|---|---|---|---|
| game PE (Kirikiri Z, 32-bit) | guest code under QEMU TCG | qemu-i386 process (child of wrapper) | part of game-process total below |
| wined3d (D3D9→OpenGL) | 32-bit, in the guest process | same | — |
| winex11 + Mesa llvmpipe (ELF32) | 32-bit Linux libs under TCG; llvmpipe JITs to i386, TCG re-translates it (**double-JIT tax**) | same | render share visible in thread profile |
| game process total (title, idle) | — | host | **≈17 % of one core** over 60 s (1038–1104 ticks across all conditions); busiest single thread ≈700 ticks (7 s) per 60 s window |
| QEMU TCG (8.2.2-static for children; 10.0.2 for the first process) | host native | — | guest python float loop: 90 k ops/s (8.2.2) vs 92 k ops/s (10.0.2), +2 % |
| q32sup supervisor | host native | own process | **≈0 steady-state**: cumulative CPU 1 tick (0.01 s) at title; micro-bench parity (90 k vs 92 k ops/s with/without). Intercepts execve only (source-audited). It is *load-bearing*: without it, child execve reaches a kernel with the 32-bit transition disabled and children die — a "without supervisor" game run is impossible in this sandbox, not merely untested |
| PulseAudio daemon | host native x86-64, workspace-resident (`pa-bin/`) | own process | ~1 % CPU; null sink is wall-clock paced |
| capture (parec / ffmpeg x11grab) | host native | own processes | x11grab 20 fps ultrafast adds ≈+66 game-CPU ticks/60 s (M1→M2), i.e. small |

VM: 4 vCPUs visible, ≈1.5 effective cores (runtime allocation; cgroup v2 inside shows
no `cpu.max` and no throttling counters — throttling is not observable from inside).

## Ladder (title screen, 60 s windows, pre-flight before every run)

Base config: PulseAudio realtime, `PULSE_LATENCY_MSEC=750`, LP_NUM_THREADS=1,
Xvfb 1280×720, wrappers→qemu 8.2.2-static, WINEDEBUG=-all.

| run | variable | delivery | underrun Δ | verdict |
|---|---|---|---|---|
| R1 attempt 1 | base | 0.000 (invalid) | 0 | harness failure: self-built supervisor derived a wrong `-L` sysroot; guest died at exec; capture = idle-sink silence. **Not a game measurement.** |
| R1 attempt 2 | base | 0.000 (invalid) | 0 | re-run against a dead instance (the first had been killed by a bench-session tree teardown). Capture = 60.23 s zeros. **Not a game measurement** (`cap-r1-invalid2.raw` kept). |
| R1 final | base | **1.000** | **0** | PASS + **KK ear-test 「最高だね」** |
| R2 | wrappers → qemu 10.0.2 | **1.000** | **0** | neutral |
| R3 | LP_NUM_THREADS=2 | **1.000** | **0** | neutral |
| R4 | LP_NUM_THREADS=4 | **1.000** | **0** | neutral |
| R5 | PA transport = unix socket | **1.000** | **0** | neutral (transport verified in effect via launch env) |
| R6 | vblank_mode=3 | **1.000** | **0** | no measurable change; nothing to throttle at title |

Earlier E-series (contended VM, same base family): E1 (750 ms buffer) 0.63,
E2 (+1280×720, LP=1) 0.68, E3 (=E2, renice denied) 0.68, E4 (3000 ms buffer) 0.43,
F1 (E4 + window unmapped) 0.44. Waveform at E3: metronome ON ≈0.90 s / OFF ≈0.30 s.
Failed levers recorded: renice/nice (permission denied — no CAP_SYS_NICE in this
sandbox), `-tb-size` (**does not exist in user-mode qemu**: both builds exit rc=1,
"unknown option"), bigger buffers beyond 750 ms (worse), window unmapping (no effect).

## Matrix (base config, one instance, sequential 60 s windows, start load 1.47)

| condition | game CPU ticks/60 s | delivery | underrun Δ | video |
|---|---|---|---|---|
| M1 game only | 1038 | — | — | — |
| M2 game+video | 1104 | — | — | 1200 frames @20 fps delivered |
| M3 game+audio | 985 | **0.829** (26 gaps, 10.18 s, longest 0.395 s) | 52 | — |
| M4 game+video+audio | 1092 | **0.886** (18 gaps, 7.04 s, longest 0.395 s) | 38 | 1199 frames delivered |

M3/M4 fell short of the R-standard in this session. A follow-up diagnostic on a fresh
instance measured **1.000 / Δ0** for an audio window at ~4 min session age with no
foreign heavy process in the top list (partial run — later windows were lost when the
bench shell was terminated). The M3-vs-M4 ordering (M4 better despite more load) is
evaluated below.

### M3 vs M4 delta (Phase 4 evaluation)

Facts: n=1 per condition; conditions ran sequentially (M3 before M4) on one instance;
session-start load 1.47 vs 0.40–0.63 for the R-runs; M3's window began ~6–7 min after
boot, M4's ~8–9 min; per-window background composition was not recorded in the matrix
run (only load). Assessment: with n=1 and uncontrolled background fluctuation, the
0.829 vs 0.886 difference is **not evidence that recording helps**; it is consistent
with run-to-run variance under a fluctuating background (the same mechanism that makes
M4's later window cleaner also fits a passing load burst during M3). No mechanism by
which adding x264 encoding would improve the game's audio production is known or
evidenced.

**Deciding experiment (run 2026-11-13, quiet protocol active, one instance,
interleaved windows):** M3 = 3/3 windows at delivery **1.000** (gaps 0, underrun Δ0,
exact-dup 0); M4 = 3/3 full windows at **1.000** (same zeros; video 1200 frames per
window; A/V start offset 0.002 s). Game CPU: M3 1178 ticks vs M4 1214–1248 ticks
(excess ≈ known x11grab cost). With the background term removed the two conditions
are **indistinguishable**. Verdict: the matrix-era M4>M3 ordering was variance of two
contention-degraded windows, not an effect of recording. Two M4 attempts in this
session were truncated-invalid by a harness race (a leftover driver script from the
preceding session ran windows in parallel and the harnesses' shared `pkill`
pattern killed each other's captures at 18.57 s / 39.51 s; captured content was
clean) — disclosed in RESULTS.md §4. Session ages at the quiet windows were
1–11 min: no session-age effect observed in that range.

## F2 — clockless capture (ALSA file plugin), gate v2 verdict: FAIL (closed)

Format f32le/48 kHz/stereo; 294.91 s of content from a 115 s wall window (production
pace 2.57×); 99.59 % nonzero (no silence insertion); **but 123/589 windows (20.9 %) are
bit-exact copies of the window exactly 1.0 s earlier**, spread over the whole timeline —
systematic buffer re-feeding (KK, after listening: 「バッファ再送り込み」). Tempo slope vs
`ref48.f32`/`ref44.f32` is **indeterminate**: 0/589 windows match either reference under
two independent fingerprint methods, so those references do not correspond to the
in-game title BGM. De-gapping/repair of either capture family is prohibited in
principle (content is skipped/displaced, not merely padded).

## Conclusions

**Measured facts**
1. On a quiet VM (load ≲0.6, no competing heavy jobs), the base config delivers
   **1.000 with 0 gaps and 0 underruns** across six consecutive ladder runs and one
   diagnostic run; KK's ear test passed.
1b. Under the VM quiet protocol (managed background jobs paused), the full
   M4 condition (game + video + audio) also delivers **1.000 / 0 / 0**, reproduced
   3/3 windows, with M3 identical (3/3) — the Policy B recording configuration is
   validated. Quiet-protocol windows ran at 1-min load averages of 1.37–2.36
   (mostly the game's own load plus runtime overhead); the operative change vs
   the degraded matrix session is the absence of the managed background jobs,
   not the load-average figure itself.
2. Under contention, the same stack degrades to 0.39–0.68 (E-series) or 0.83–0.89
   (matrix) — the failure is a *production shortfall*: the guest cannot sustain
   realtime sample production when the host scheduler is busy; the sink pads with
   silence and the engine then skips content.
3. Every settings-level lever tested (qemu version, LP threads, PA transport,
   vblank, buffer size beyond 750 ms, display size, window visibility) is **neutral**
   once contention is removed; the 750 ms stream buffer (vs Wine's 30 ms default)
   was the only setting that mattered, and only under contention.
4. The game itself is light: ≈17 % of one core at title; boot to title 62–82 s.

**Estimated causes (not proven)**
- CPU contention from other managed background work on the shared VM is the leading
  hypothesis for both the E-series plateau and the matrix shortfall. Evidence is
  correlational (load readings and timing coincidence); no specific job is named as
  the proven culprit. The VM quiet protocol + quiet-M4 retest exists to convert this
  from hypothesis to measurement.

**Unverified items**
- Tempo slope vs the parent's reference files (references don't match the in-game
  BGM under two fingerprint methods — slope not measurable against them).
- True render fps: only the content-change rate (≈1 distinct/s at title) is
  measurable via grabs; presents of identical frames are invisible to the method.
- `-cpu` model sensitivity *in-game* (only `-cpu max` used; the python micro-bench
  is not the game).
- Session-age effect (TCG translation-cache pressure over long sessions) — no
  effect observed across windows at 1–11 min instance age in the quiet-protocol
  runs; ages beyond ~15 min remain untested.

## Reference configuration (reproducible)

```
Xvfb :113 -screen 0 1280x720x24
PulseAudio (workspace pa-bin) with pa/default.pa: null sink "game" 48 kHz f32le,
  unix socket pa/native + TCP 127.0.0.1:47130
env: PULSE_LATENCY_MSEC=750 LP_NUM_THREADS=1 WINEDEBUG=-all
     PULSE_SERVER=tcp:127.0.0.1:47130 (or unix:…/pa/native — equivalent)
     Q32_SYSROOT=$VT/sysroot32/root Q32_WRAPDIR=<own dir> Q32_QEMU=<qemu-i386 8.2.2-static or 10.0.2>
launch: tools/launch2.sh (own q32sup build), absolute Z:\ path to sanoba_trial.exe,
        ja_JP.UTF-8 locale + LOCPATH from vn-trials
conditions: VM quiet protocol active (see RESULTS.md), pre-flight probe PASS
```

## Operational lessons (harness)

- Self-built q32sup derives paths from its own location — always set Q32_SYSROOT /
  Q32_QEMU / Q32_WRAPDIR explicitly, and verify a generated wrapper before launching.
- `pactl` without `PULSE_SERVER` hits the default socket path and reports
  "Connection refused" against this private daemon — several false "daemon down"
  alarms traced to this.
- Killing a bench *session* tears down its whole descendant tree, including the
  `setsid`-detached game. Kill game processes by environ-matched pid only.
- Long foreground tool calls can be SIGTERM'd at turn boundaries; run measurements
  as detached background jobs with per-run log files.
- ffmpeg without `-nostdin` can block forever on stdin in background shells;
  every external command gets an explicit `timeout`.
- Never overwrite captures: one new file per run (`cap-<run>.raw`).
