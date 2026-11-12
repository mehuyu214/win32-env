# トラブルシューティング

## 起動・実行系

### wineboot が終わらない / 子プロセスが即死する
- **原因**：q32sup を経由せず qemu を直接叩いている。QEMU は子プロセスの execve をホストカーネルに直通させ、カーネル側で 32bit 遷移が無効なため子が死ぬ。
- **対処**：必ず `scripts/run32.sh` / `scripts/boot32.sh` / `scripts/launch.sh`（内部で q32sup を使う）から起動する。
- **切り分け**：`tests/exectest`（execve で hello32 を呼ぶテスト）を qemu 直と q32sup 経由で比べると差が見える。

### `wine: failed to load syswow64\ntdll.dll (c0000135)`
- Ubuntu 純正 wine64 (9.0) で PE32 を開いたときのエラー。新 WoW64 用の i386 PE DLL が同梱されていない。この経路は本環境では使わない（使っても互換モード遷移で固まる）。32bit 専用ビルド（Kron4ek x86）＋ qemu を使うこと。

### PE32 のプロセスが生成されたまま固まる（CPU は回る）
- WoW64 経路の典型症状。wow64.dll 系がマップされず syscall ループに入っている。本環境（qemu + q32sup）に切り替える。

### ゲームがロゴ / 黒画面で進まない（プロセスは生きている）
- Xvfb にはウィンドウマネージャがなく、ゲームウィンドウがアクティブ化されないと Unity 等が「非アクティブ」と判断して進まないことがある（Geminism で実証、Player.log の "vsync is broken ... until the game window is moved" がヒントだった）。
- **対処**：`scripts/launch.sh`（`wine explorer /desktop=名前,1600x900` 経由）で起動する。

### 画面が真っ黒でログだけ進む
- Kirikiri 系ではエンジン起動後も描画まで時間がかかる場合がある。まず `savedata/krkr.console.log` の進行を見る。CPU を食い続けているなら翻訳処理中。競合プロセス（他の qemu / ゲーム）を止めると大きく改善する。

### プレフィックスが毎回更新（wineboot）を始める
- `.update-timestamp` の中身（10進文字列＋CR）が、実行中 Wine の `share/wine/wine.inf` の mtime と一致していないと更新が走る。本環境の値は `1793442172`。スナップショット展開直後は一致しているはずなので、勝手に書き換えないこと。
- 前回の wineboot が固まったまま残っていると、後続の起動がその wineserver の後ろに黙って並ぶ。該当プレフィックスの wineserver を終了してから再試行する。

### `qemu10/wrap/` のラッパーが古いパスを指す
- ラッパースクリプトは初回 exec 時に生成される絶対パス入りの生成物。リポジトリを別の場所に clone した場合は空から生成されるので問題ないが、作業ツリーごとコピーした場合は `rm -f qemu10/wrap/*.sh` して再生成させる。

### フォントが豆腐（□）になる
- Wine の UI フォントの代替設定の問題。ゲーム内フォントには影響しないことが多い。本格的に直す場合は winetricks cjkfonts 相当の導入や FontSubstitutes レジストリ調整を行う（当時の未了タスク）。

### 音が出ない
- 仮想環境にオーディオデバイスがない場合、FMOD 等が無音で継続する。ゲーム進行には影響しないことが多い。

## 復元系

### SHA-256 検証で落ちる
- 分割パートの欠け・取り違えを確認する。`cat archives/<name>.tar.xz.part-* | sha256sum` と `archives/<name>.tar.xz.sha256` を比較できる。再 clone / 再ダウンロードで解消することがほとんど。

### setup.sh の後に qemu が「共有ライブラリがない」と言う
- qemu-i386（動的リンク版）はホストの amd64 ライブラリで動く。通常の Ubuntu/Debian で問題ないはずだが、最小環境では `ldd qemu10/usr/bin/qemu-i386` で不足を確認する。代替として static 版（`qemu/usr/bin/qemu-i386-static`、8.2.2）も収録してある（ただし q32sup の QEMU 既定は 10.0.2 側。`Q32_QEMU` で差し替え可能だが、static 版は子プロセスの扱いが異なるため未検証）。

### gcc がない / q32sup がビルドできない
- `scripts/setup.sh --system-packages` で gcc 等が入る。ビルド済みのオリジナルバイナリ（`tools/q32sup.orig-x86_64-bin`）は当時の絶対パス前提なので、そのままでは使えない。必ずソースからビルドすること。

### そもそもホストでネイティブ 32bit が動く環境だった
- その場合は本環境を使わず、通常の wine32 / WoW64 でよい。本環境は「32bit 遷移が塞がれたサンドボックス」専用の回避策。
