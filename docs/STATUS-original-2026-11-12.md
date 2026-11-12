# VN Trials — Status (2026-11-12)

Goal: actually play official free trial editions (体験版) of Yuzusoft VNs on this Linux VM as UI reference for VN ARCADE.
Legal / official sources only. No payment, no phone, no piracy sites.

## Environment — what works and what does not

| Item | Result |
|---|---|
| Wine | **wine-9.0** (Ubuntu 9.0~repack-4build3), wine64 — installed via apt. NOTE: the VM was replaced mid-run once, wiping the first install; reinstalled. System installs do not survive VM replacement. |
| Toolchain | Xvfb, xdotool, scrot, fonts-noto-cjk, winetricks (20240105), unzip, p7zip-full — installed. |
| Wine prefix | `~/workspace/vn-trials/wineprefix` (win64, Windows 10, LANG=ja_JP.UTF-8; ja_JP.UTF-8 locale generated). |
| GUI launch test | **PASS (64-bit)**: `wine notepad` under Xvfb opened a real window (found by xdotool, screenshotted). Screenshot: `screens/wine-notepad-toolchain-test.png`. Caveat: Japanese UI text rendered as tofu boxes in Wine's UI font — fix font substitution (winetricks cjkfonts / registry FontSubstitutes) before judging game text rendering. |
| **32-bit x86 execution** | **BROKEN in this VM sandbox**: even a statically-linked 32-bit hello-world segfaults (exit 139). Consequences: steamcmd (32-bit only) can never run here; wine32 is useless here even if installed (its apt install also fails: local `+hatch1` builds of libzstd1 etc. break multi-arch co-installability). **Only 64-bit Windows binaries can run.** Recent Yuzusoft titles ship 64-bit exes, so this is workable for the trials themselves. |
| Steam client protocol | Works through the egress proxy (DepotDownloader connected and logged in anonymously). |

## Titles

### 千恋＊万花 / Senren Banka — Steam demo route (priority)
- Full game app 1144400; **official free demo appid 1221010** ("Senren＊Banka Trial version", per Steam API + AppInfo).
- steamcmd: unusable (32-bit, segfaults — see above).
- **DepotDownloader 3.4.0** (64-bit, in `~/workspace/vn-trials/depotdownloader/`) was used instead:
  `DepotDownloader -app 1221010 -os windows -dir downloads/senren-demo` (omit `-username` for anonymous; passing `-username anonymous` wrongly triggers a password prompt).
- Result: connected to Steam3, anonymous login OK, AppInfo fetched — then: **"App 1221010 (Senren＊Banka Trial version) is not available from this account."**
  The demo is **not downloadable anonymously**; it needs a real (free) Steam account login. KK's Steam account is `mehuyu214`, but its password is held by KK only (not available to the agent), so this route is **blocked on KK-provided login**.
- Log: `~/workspace/vn-trials/dd-senren.log`. Downloaded: **0 bytes**.
- Japanese trial-zip route: official page mirrors = DMM (blocked domain), DLsite (blocked in our tooling), Getchu id=895010 (see Getchu section), Dengeki-hime (old article, unreachable).

### 喫茶ステラと死神の蝶 / Café Stella — trial zip route
- Official page: https://www.yuzu-soft.com/products/stella/download.html — trial = zip, run `喫茶ステラと死神の蝶_体験版.exe` after unzip.
- Primary trial link = DMM detail yuzu_0004 → **dlsoft.dmm.co.jp is policy-blocked; skipped as instructed**.
- Mirrors listed: **Getchu id=1062475** (see below), **Netride** `http://www.net-ride.com/free_dl/index.php?R_km_url=yuz1` → redirects to `https://www.net-ride.com/mainte/index.html` — **site under maintenance, dead end for now**.
- Steam (app 1829980): **no demo** (API demos: null). Downloaded: **none yet**.

### RIDDLE JOKER — trial zip route
- Official page: https://www.yuzu-soft.com/products/riddle/download.html — trial = zip, run `RIDDLE JOKER体験版.exe`.
- Mirrors: DMM yuzu_0002 (blocked, skipped), DLsite VJ011717 (dlsite.com blocked in our tooling + direct fetches stalled), **Getchu id=986010**, Dengeki-hime 2018 article (fetch failed / unreachable).
- Steam (app 1277930): **no demo**. Downloaded: **none yet**.

### 天使☆騒々 RE-BOOT! — trial zip route
- Official product site is a single-page layout under https://www.yuzu-soft.com/products/ten_sz/ (download section on the top page; there is no separate download.html).
- Trial links found there: DMM yuzu_0008 (blocked, skipped), **Getchu id=1210049**, Netride `R_km_url=xpVH` (maintenance, dead).
- Steam: no Steam release/demo found. Downloaded: **none yet**.

### PARQUET (Steam app 1662840)
- **Paid game (¥2,500), no demo** (API demos: null). **Off the table** — do not buy; a Steam purchase is not possible for the agent anyway (no Steam password held, no Steam-usable payment method). Awaiting KK decision if ever wanted.

## Getchu mirror — exact findings (needs a live-browser agent)
- Getchu serves an age-verification gate to plain HTTP clients. Gate flow (verified by direct fetch earlier):
  `https://www.getchu.com/php/attestation.html?aurl=<item URL>` → entry link `https://www.getchu.com/item/<id>/?gc=gc` (sets the gate cookie) → item page loads (~95–106 KB).
- Item pages fetched for 1062475 / 895010 / 986010: they are **package-version shop pages**. Their HTML contains **no direct trial-zip link** (the site-wide "体験版・動画DL" nav entry is commented out; the only dl.getchu.com reference is the DL shop top page).
- **getchu.com is policy-blocked in the agent's browser-fetch tool** (same class as dlsite.com), and this subagent cannot operate a live browser. **Remaining step for a browser-capable agent**: open the item page in the real browser, pass the age gate by clicking, and check in the rendered page whether a trial-download button/section exists and what host/filename/size it resolves to. If Getchu only offers the trial via its DL shop with account+downloader, record that and stop.

## Bottom line
- Toolchain is ready and proven for 64-bit Windows games (Wine 9.0 + Xvfb + screenshot pipeline).
- **No trial has been downloaded yet.** Every official free route currently ends at one of:
  1. Steam demo needs KK's Steam login (Senren 1221010),
  2. a policy-blocked domain (DMM / DLsite),
  3. a maintenance-dead mirror (Netride),
  4. Getchu — needs a live-browser pass through the age gate to determine whether a direct trial file exists at all.
- Next unblocking actions, in order: (a) browser-capable agent checks Getchu item pages past the gate; (b) KK logs into Steam once (or provides login via the secure flow) so DepotDownloader can fetch demo 1221010.

## 32-bit Windows exe test (2026-11-12 15:1x JST, measured)
- Built test PEs with mingw-w64: hello64.exe (PE32+) and hello32.exe (PE32).
- hello64.exe under Wine: RAN (printed HELLO_FROM_PE, exit 42 as coded). 64-bit Windows apps confirmed working.
- hello32.exe: FAILED — wine: failed to load syswow64\ntdll.dll (c0000135); prefix syswow64 is empty; Ubuntu wine64 9.0 ships no new-WoW64 i386 PE DLLs (/usr/lib/.../wine/i386-windows has only zlib1.dll). Traditional wine32 route needs native 32-bit ELF exec, which this VM blocks (measured segfault). Conclusion: 32-bit Windows games (most older eroge) cannot run in this VM as-is; only 64-bit-exe titles can.
## WoW64 deep-dive (2026-11-12 15:4x–16:0x JST) — 32-bit execution conclusively blocked by the sandbox

Question: can 32-bit Windows exes run here via Wine's new WoW64? Answer: **No — the block is in the sandbox's CPU/syscall layer, below Wine.** Two independent WoW64 builds fail identically at the same instruction-level step.

### Workarounds that DID work (prefix plumbing solved)
- Kron4ek wineboot on a fresh prefix wedges in `rundll32 setupapi,InstallHinfSection` (both Wow64Install and DefaultInstall passes; blocked in `anon_pipe_read`, plus `start_rpcss Failed to open RpcSs service` errors). Abandoned fresh-prefix init entirely.
- **Hybrid prefix** built instead: `wineprefix-hybrid` = copy of the healthy system-Wine-9.0 prefix, with ALL files from Kron4ek `lib/wine/i386-windows/` (1113) copied into `drive_c/windows/syswow64/` and `lib/wine/x86_64-windows/*` into `system32/`.
- Prefix-update gate is **content-based**: `.update-timestamp` must contain the running wine's `share/wine/wine.inf` mtime as decimal text + CR (vanilla 11.21: `1793443914`; staging 11.21: `1793449020`). With matching content the Kron4ek wine skips wineboot on the hybrid prefix; services/winedevice/rpcss then start normally. (If a wedged wineboot from a previous attempt is still alive on the prefix, new launches silently queue behind it — kill that prefix's wineserver first.)

### Control (same build, same prefix)
- 64-bit `C:\windows\system32\hostname.exe` under Kron4ek 11.21 + hybrid prefix: prints `HTCH-RUNTIME`, **exit 0**. Prefix, build, Xvfb :99, wineserver all healthy.

### The failure (all PE32 programs, both builds)
Test programs: syswow64 `cmd.exe` (/c echo), syswow64 `hostname.exe`, mingw-built `hello32.exe` (copies kept in `~/workspace/vn-trials/wtest/`), and the real **Sanoba Witch trial exe** (md5-verified copy `sanoba_trial.exe`, launched via ASCII symlink `sanoba-game/`). Every one shows the identical signature:
- Process is created (NtCreateUserProcess succeeds; +process trace confirms), main image + 32-bit ntdll + 64-bit ntdll mapped from the install tree.
- **wow64.dll / wow64cpu.dll / wow64win.dll are never mapped**; no 32-bit DLL loads; the child emits zero debug output after creation.
- Single thread spins forever at 60–99% CPU, ~2/3 of it kernel time (e.g. utime 872 / stime 1946 ticks over ~28 s), page-fault counters frozen — a tight syscall loop at the first transition into 32-bit compatibility-mode execution, before any guest code runs.
- Identical result on Kron4ek **wine-11.21-amd64-wow64** and **wine-11.21-staging-amd64-wow64**.

### Why this is the sandbox, not Wine
- Same sandbox already measured: a native statically-linked 32-bit Linux ELF segfaults instantly (exit 139) — the kernel layer cannot execute 32-bit code segments in any form (native ELF or WoW64 compatibility mode).
- Introspection fits a mediated sandbox kernel: `ptrace` attach → EPERM, `/proc/<pid>/stack` → EPERM, `/proc/<pid>/syscall` empty, gofer-style giant inode numbers on host files.
- Conclusion: **no Wine-side fix exists** (build, prefix, or flags) — 32-bit Windows games, including the Sanoba trial and the other mostly-32-bit Yuzusoft trials, cannot run in this VM. 64-bit-exe titles remain fully workable (Wine 9.0 system prefix or the hybrid prefix). Re-test only if the VM's kernel/sandbox changes.
- Housekeeping: all test wineservers killed; system prefix `wineprefix` untouched; wedged `wineprefix-wow64` left as-is (dead). mingw cross-compilers/scrot exist only in some exec generations (system state does not persist across VM generations) — hello32/hello64 sources+binaries preserved under `~/workspace/vn-trials/wtest/`.

## 2026-11-12 16:42 — Stella trial (yuzu_0004) downloaded to this server via DMM
- Route that finally worked: KK registered a DMM account himself in the device browser (mehuyu214@proton.me; Muse read the auth code from Proton and entered it at KK's order), KK free-"purchased" the Stella trial into the library, then in the CLOUD browser Muse signed in with the Vault-saved DMM login and downloaded from the library. Earlier "dlsoft is policy-blocked" was wrong for the live browsers — both device and cloud browsers open dlsoft fine (age check → login); the block had only been seen on a link-following/fetch path that morning.
- Wayback route checked and empty: Stella's official mirrors were Getchu (trial.getchu.com/D100/1062475/cs_trial.zip) and NetRide — neither zip is archived (pages only). suezou was never a Stella mirror.
- File: ~/workspace/vn-trials/yuzu_0004.zip — 1,162,082,541 bytes (matches the library's 1108.25MB display), 61 entries, CRC test passed. Main exe 「喫茶ステラと死神の蝶_体験版.exe」 is PE 32-bit x86 (Kirikiri, data.xp3) — so, per the WoW64 verdict above, it cannot be launched in this VM; the zip is kept as the obtained trial artifact. A second duplicate download (UUID-named in the browser) was still in flight at placement time; dedupe on arrival.

## 2026-11-12 16:44–16:50 — Stella launch attempt + system analysis published
- At KK's request the real Stella trial exe was launched on the hybrid WoW64 prefix (Kron4ek 11.21): froze with the identical signature as Sanoba/test exes — process created, CPU time 0, zero wow64.dll/syswow64 mappings in /proc/<pid>/maps, no window after 2+ minutes. Wineserver killed afterwards. Verdict unchanged, now confirmed on the actual Stella exe.
- KK's pivot adopted: static system analysis instead of execution. Findings: Kirikiri Z core + TJS2 + KAG (exe strings), 27 plugin DLLs mapped by role (motionplayer, psbfile/psd, wuvorbis/wuopus, wfTypicalDSP, yuzuex, KAGParserEx…), data.xp3 (1,307,187,984 B) has an encrypted index (not even filenames readable in plaintext), and every binary ships a 212-byte .sig signature file. No game content extracted or decrypted.
- Report: ~/workspace/vn-trials/stella-system-analysis.md, published to GitHub: https://github.com/mehuyu214/vn-games-preview/blob/main/research/stella-system-analysis.md (commit fd10894, content verified via the live page).
- The duplicate DMM download (second yuzu_0004.zip, SHA-256 identical df20fd3d…) was deleted; only ~/workspace/vn-trials/yuzu_0004.zip is kept.

## 2026-11-12 18:15 Geminism PLAYABLE (breakthrough)
- Geminism trial (craftwork_0002, CRAFTWORK) downloaded via DMM library (474,687,436 bytes, zip CRC OK), extracted to downloads/geminism/Trial086p. Geminism.exe = PE32+ x86-64, Unity 2021.3.25f1 IL2CPP + Utage 3.11.9.
- First launch (plain Xvfb :99, hybrid prefix, Kron4ek Wine 11.21) froze forever on the CRAFTWORK logo: engine started (Player.log: D3D11 OK, "Utage Ver 3.11.9 Start!"), CPU ~10% of one core, clicks/Enter via XTest and xdotool had no effect, no standalone video files exist (all packed in .assets).
- Root cause: Xvfb has no window manager, so the game window was never activated; Unity treated the app as inactive and never advanced. Player.log hint: "vsync is broken ... until the game window is moved."
- FIX: relaunch inside a Wine virtual desktop: `wine explorer /desktop=Geminism,1600x900 Geminism.exe` (same hybrid prefix). Title screen appeared immediately (桔梗/深紅 はじめから, つづきから, クイックロード, 解放要素, 環境設定). Started 桔梗 scenario; opening lines and first location card (廃校 解体現場 AM 2:11) render; Japanese text renders (game font). Sound: FMOD found no audio device (emulated, silent) — gameplay unaffected.
- Screenshots: screens/geminism-vd1.png (title), geminism-play1.png (first line), geminism-play3.png (廃校 location card).
- Other trials measured same day: Sakura no Toki (mnphs_0012) exe = PE32 32-bit (cannot run); RE:D Cherish! (spal_0174) exe = PE32 32-bit (cannot run); Majikoi (hawkeye_0027) still downloading.
- Also verified: Muse browsers refuse localhost/private-IP navigation (noVNC route dead); Tailscale connector is client-only (hosts nothing). Local LLM test: llama.cpp + Qwen2.5-1.5B Q4_K_M runs at ~9.5 tok/s generation on this VM (~/workspace/local-ai/).

## 2026-11-12 18:49–19:49 JST — 32-bit breakthrough OVERTURNS the WoW64 verdict (q32sup)
- The "32-bit conclusively blocked" verdict above is now WRONG. New tool: q32sup, a custom ptrace+seccomp supervisor (`~/workspace/vn-trials/qemu10/q32sup`) that intercepts qemu-i386's execve of child processes and reroutes them through a wrapper script, so Wine's child-process spawns survive the sandbox's disabled 32-bit transition. Diagnosis: qemu passed child execve straight to the kernel, where 32-bit mode is disabled; binfmt_misc is non-functional here (registrations silently swallowed).
- Result 19:18 JST: wineboot completed under qemu+32-bit Wine 11.21 — 315MB prefix `wineprefix32/`, snapshot `prefix32-booted.tar` (328,488,960 B, 10:09 UTC). wineserver, services, explorer all running 32-bit under emulation; dedicated desktop displayed.
- Sanoba launch in progress (started 19:46 JST, `launch_sanoba6.sh`, still running at 19:49 JST): the real `sanoba_trial.exe` (PE32, Kirikiri Z) is EXECUTING — `sanoba-real/savedata/krkr.console.log` (19:46:36–39 UTC) shows Kirikiri Z core 1.2.0.3 started, data.xp3 selected, and ~30 TJS scripts loaded (HistoryLayer, BGM, SE, Voice, Movie, MessageLayer, Menus, motion, etc.). One warning to watch: `Syntax error (syntax error) at line 8893 / Invalid character` at 19:46:39, then CPU-clock measurement 19:46:57, then no new log lines for ~3 min; screen at 19:48 is still black (no game window yet) while qemu processes are still burning CPU. Verdict pending: engine booted, title screen NOT yet confirmed.
- Speed notes (KK asked how to make it faster): VM has ~1.5 effective cores; Geminism's Unity loop was SIGSTOP-frozen to free CPU during wineboot; qemu uses `-cpu max` + multi-threaded TCG planned; prefix snapshot avoids repeating the one-off boot cost.
- Majikoi bitness MEASURED 2026-11-12 19:49 JST (was "not yet measured"): all exes in `downloads/majikoi/extracted/majikoi_trial_special2/` are PE32 32-bit (Launcher.exe, Setup.exe, Filechk.exe, StartUpTool.exe, Uninstall.exe, DirectX/DXSETUP.exe). Same q32sup route should apply once Sanoba's launch is confirmed; entry point is Launcher.exe.
- Sakura no Toki / RE:D Cherish! exes were already measured PE32 32-bit earlier the same day, so they are now also candidates for the q32sup route (previously written off as unrunnable).
