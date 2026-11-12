# Audio capture investigation — realtime pacing on an emulated stack (2026-11-12, in progress)

Goal: record the **unmodified** Sanoba Witch trial with its own BGM as a
simultaneous audio+video capture (for an AI gameplay-commentary series).
Owner's constraints, which shape everything below:

- The game is never modified. All fixes are environment-side.
- In-game settings for the recording: VOICE off, SE/BGV/movie volume 0,
  BGM 50, master 100 (Yuzusoft's guidelines prohibit voice/SE in published
  videos; music is allowed for non-commercial creative videos).
- BGM must be captured **simultaneously** with the video. Recording the
  music separately and dubbing it over footage is explicitly forbidden by
  the owner, because the result would not match the scenes.

## Baseline: playback works; *paced capture* is the problem

Normal play audio has been solved since 2026-11-12 21:36–21:54
(see `docs/GAME-RUNBOOK.md` and the runbook history):

- Sysroot gained `libasound2t64:i386` + `libasound2-data`; with
  `ALSA_CONFIG_PATH` pointing at a null-device config
  (`pcm.!default { type null }`), mmdevapi loads `winealsa.drv`,
  DirectSound buffers stream (24,000-byte Lock/Unlock writes), mmdevapi
  errors are 0, and `bgm51.opus` plays with no exceptions.

So the game produces correct audio into a virtual device. The open problem
is narrower: capturing that audio **at the correct real-time pace** while
the producer — a 32-bit game under QEMU TCG translation, rendering via
llvmpipe software rasterisation on a VM with ~1.5 shared CPU cores —
struggles to feed a real-time consumer.

## Measurement method: the delivery ratio

A virtual device that is under-fed does not drop the stream; it keeps its
wall-clock schedule by inserting **digital silence** (exact `0.0` samples).
The capture therefore has the *correct total duration* even when most of
it is padding — **duration alone is a misleading metric**, and an early
gate based on it produced a false pass (Attempt 2 below).

The metric used throughout this investigation:

```
delivery_ratio = music_seconds / total_seconds
music_seconds  = total_seconds − Σ (lengths of exact-zero runs ≥ threshold)
```

- A *gap* is a maximal run of frames in which **both** channels are
  exactly `0.0`, at least `--gap-ms` long (default 5 ms = 240 frames at
  48 kHz). Real program material essentially never does this in both
  channels at once; device-inserted silence always does.
- Implemented as a reusable tool: **`tools/delivery_ratio.py`**
  (raw float32le input; prints total/music/gap statistics and the ratio).
- Reference measurement, PulseAudio capture `cap-e2.raw`:
  total 59.82 s, music 40.54 s, 51 gaps totalling 19.27 s → **ratio 0.678**.

## Attempt 1 — ALSA file-plugin capture (DISCARDED)

Setup: ALSA config `pcm.!default { type file; slave.pcm "nulldev"; ... }`
writes the played PCM to a file while the game "plays" into a null slave;
video recorded simultaneously with x11grab.

Measured facts:

- Capture: 130,698,240 bytes, identified empirically as **float32le,
  stereo, 48000 Hz** (100 % of sampled values in [−1, 1], peak 0.195;
  cross-correlation against the original `BGM51.opus` scores **0.437 at
  48 kHz vs 0.069 at 44.1 kHz** — the content is genuinely the game's BGM).
- But the file/null device consumes samples **instantly** — it has no
  clock — so the stream is not paced at all. Aligned against the
  simultaneously recorded 72.9 s video, the capture contained **164.4 s of
  audio: the audio clock ran at 2.26× real time**.
- Self-similarity analysis of the muxed audio (0.5 s spectral-fingerprint
  windows) found multiple **exact matches (distance 0.0) at exactly
  +1.0 s offsets** (0.0≈1.0, 1.5≈2.5, 3.5≈4.5, 5.5≈6.5 …) and 29/145
  windows with a near-duplicate within 20 s: the engine re-feeds identical
  buffer segments when unthrottled. The corruption is in the content, not
  just the timing, so no stretch/resample repair is legitimate.

The muxed `sanoba-audio.mp4` from this attempt was discarded.

## Attempt 2 — PulseAudio null sink + monitor capture (current route)

Setup: a host PulseAudio daemon on a private address
(`PULSE_SERVER=tcp:127.0.0.1:47130`) with a **null sink** — a sink with a
real wall clock, intended to pace the producer — and the guest connected
through a self-supplied i386 `libpulse` stack (`winepulse`; ALSA pulse
plugin as the alternate route). The sink's monitor source is captured with
`parec` as float32le / 48 kHz / stereo.

### Gate v1 false pass

The first 60 s pacing test appeared to pass:

- Captured duration **59.99 s** for a 60 s wall-clock window.
- **0/50** exact-duplicate 0.5 s windows at +1.0 s offsets (vs. many in
  Attempt 1).

The owner's listening test rejected it ("constantly slow", not choppy).
Deeper measurement of the same capture (`cap60.raw`) showed why gate v1
was insufficient:

- **741 silence gaps > 5 ms, totalling 36.4 s — 61 % of the capture**;
  longest single gap 0.167 s.
- **18,840 underrun events** in `pulseaudio.log` for the session.
- Zero-stripping the inserted silence leaves only **23.54 s of actual
  music in 60 s → delivery ratio 0.39**.

### Corrected defect model

The dominant defect is **not** dropped audio. When the producer is late,
the sink inserts silence and the producer's samples are delivered
afterwards, in order — so the stream is **time-stretched**: the music
progresses at ~0.4× real speed, which is perceived as *constantly slow*
rather than choppy. Additionally, once starvation is severe enough, the
engine's **play cursor overtakes its write cursor** and chunks are
genuinely **skipped** — that part is unrecoverable after the fact
(see the de-gap experiment below).

## Load reduction (measured)

The capture does not run on an idle VM: other investigation lines run
their own emulated games on the same ~1.5 shared cores. Under the owner's
load-shedding orders (competing emulation paused, browser windows closed,
display reduced 1600×900 → 1280×720, capture processes reniced,
single-job capture discipline):

| capture | conditions | delivery ratio |
|---|---|---|
| cap60 | 1600×900, other lines active | 0.39 |
| cap-e1 | load reduction in progress | 0.63 |
| cap-e2 | 1280×720, competing jobs paused | 0.68 |
| cap-e3 | same as e2 | 0.68 |

Improvement is real but **plateaus at ≈0.68**, well below the ≥0.98
target — tuning around the edges is not enough; see the ladder below.

## De-gap join experiment (REJECTED)

Hypothesis (owner's suggestion): if the samples themselves are genuine
and in order, stripping the inserted silence and concatenating should
restore natural tempo. A joined proof was built from `cap-e2.raw`
(59.8 s → 40.5 s after removing all ≥10 ms zero runs, with short
crossfades at the joins).

Result: the owner rejected it by ear — it still **skips** (「とんでる」).
That is consistent with the corrected defect model: chunks lost to
play-cursor overtake are not present in the capture at all, and no
post-processing can invent them. **De-gapping is a diagnostic, not a
fix, and must not be used for deliverables.**

## Ruled out by inspection (verified launch configuration)

Two initially suspected causes were checked against the actual launch
configuration (`sanoba-audio/scripts/common.env`) and are **not** the
problem:

- **Wine debug logging**: `WINEDEBUG` already defaults to `-all`
  (`export WINEDEBUG=${WINEDEBUG:--all}`). The multi-megabyte game logs
  seen during the investigation are not Wine debug-channel output.
- **Guest CPU model**: QEMU is already launched with **`-cpu max`**, so
  the guest sees the full TCG feature set.

Verified current launch configuration (audio line):

```
q32sup82 + qemu-i386 10.0.2  (-cpu max, -L sysroot32/root)
Wine 11.21 x86, LANG=LC_ALL=ja_JP.UTF-8 + LOCPATH=<locally generated locale>
LD_LIBRARY_PATH=<own libs32 i386: libpulse etc.>
PULSE_SERVER=tcp:127.0.0.1:47130
WINEDEBUG=-all (default)
```

## Optimization ladder (in progress)

One variable at a time; each step is judged by **delivery ratio +
in-game fps**, not by duration. Remaining suspects, in planned order:

1. **QEMU translation-cache size** — `-tb-size` is currently unset.
   Test 512, then 1024, to rule out re-translation churn across the
   Wine+game working set.
2. **q32sup overhead benchmark** — every Wine process runs under the
   ptrace+seccomp supervisor. Caveat: q32sup exists because QEMU passes
   guest `execve` to the host kernel, where 32-bit children die; the
   supervisor intercepts and reroutes them. Plain QEMU may therefore
   not be viable for Wine's children at all — *measure* the overhead,
   don't assume the wrapper can be dropped.
3. **PulseAudio transport** — the client currently connects over
   `tcp:127.0.0.1:47130`; a Unix socket removes per-packet overhead.
4. **llvmpipe threading** — `LP_NUM_THREADS=1` vs `2` on 1.5 shared
   cores (thread contention is a plausible jitter source).
5. **Frame pacing** — measure the title-screen fps; if the engine
   redraws uncapped, try Mesa `vblank_mode=3`.
6. **Capture discipline / priorities** — one heavy job at a time during
   captures; PulseAudio daemon and the game process at raised priority
   (`renice`); no screenshot polling or analysis work during a capture
   window.

## Quality gate v2 (definition)

A capture configuration is only accepted when **all** of these hold:

1. **Delivery ratio ≥ 0.98** on a 60 s capture
   (`tools/delivery_ratio.py`).
2. **Silence gaps < 1 %** of total duration; no exact-duplicate windows
   in the self-similarity check.
3. Tempo verified against the reference track (fingerprint slope
   1.00 ± 0.02) once the ratio is near 1 — this also discriminates a
   possible constant sample-rate mismatch (48 kHz vs 44.1 kHz = 0.92×),
   which the delivery ratio alone cannot see.
4. **The owner's ear test passes** on a 30 s proof clip.

Nothing ships on numbers alone; gate items 1–3 exist to protect item 4,
after gate v1 passed two numeric checks and still failed the ear.

## Status

- Playback into a virtual device: **solved** (baseline above).
- Paced, gap-free capture: **not yet achieved** — best delivery ratio
  0.68, optimization ladder in progress.
- The commentary-series BGM clips (`sanoba-bgm-story.mp4`,
  `sanoba-bgm-system.mp4`) stay queued behind gate v2.
