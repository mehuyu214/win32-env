# 試行錯誤の記録（2026-11-12）

一次資料は `docs/STATUS-original-2026-11-12.md`（当日の作業ログ全文）と `logs/` 以下。
ここはその要約＋教訓。

## フェーズ0: 土台（64bitは動く）
- Wine 9.0（Ubuntu、wine64）+ Xvfb で `wine notepad` のGUI起動に成功。64bit Windowsアプリは動作する
- 日本語ロケール ja_JP.UTF-8 を生成。Wine UI フォントは豆腐（フォント代替未設定）— ゲーム内フォントには影響なし

## フェーズ1: 32bit は「 conclusively blocked」と誤判定
- mingw で hello64.exe / hello32.exe を作成。hello64 は HELLO_FROM_PE を出力し exit 42
- hello32 は `failed to load syswow64\ntdll.dll (c0000135)`。Ubuntu wine64 9.0 は新WoW64用 i386 PE DLL を同梱していない
- Kron4ek の WoW64 ビルド2種（通常 / staging）で検証：
  - Kron4ek wineboot は `rundll32 setupapi,InstallHinfSection` で固まる → **ハイブリッドプレフィックス**で回避（正常な Wine 9.0 プレフィックスに Kron4ek の i386-windows 1113ファイルを syswow64 へ、x86_64-windows を system32 へコピー）
  - プレフィックス更新ゲートは**中身依存**：`.update-timestamp` に実行中 Wine の `wine.inf` の mtime（10進文字列＋CR）を入れると wineboot をスキップできる（vanilla 11.21 = 1793443914、staging = 1793449020、本32bit環境 = 1793442172）
  - それでも PE32 は全滅：プロセス生成後、wow64 系 DLL が一切マップされず syscall ループ。ネイティブ32bit ELF の即セグフォと合わせ、「サンドボックスのCPU層で32bit遷移が無効」が結論になった
- 教訓：この結論自体は正しかったが、「だから32bit Windowsアプリは不可能」という飛躍が間違いだった。**遷移がダメなら、遷移しない方法（全命令を翻訳する）がある**

## フェーズ2: QEMU user mode
- VMがセッション途中で交換され、apt で入れた道具が消えた → **以後の構築物はすべて `~/workspace/` 内に置く**方針に切替（本リポジトリの存在理由）
- multiarch 追加は依存破壊を起こしたため、i386 .deb を `sysroot32/root/` に展開する方式へ
- qemu-i386（8.2 static）で32bit Linuxバイナリ exit 0、32bit Wine 11.21 がバージョン応答 → 土台成立
- しかし hello32.exe 初回実行が240秒タイムアウト（プレフィックス作成が進まない）

## フェーズ3: q32sup
- 切り分け：テストバイナリ＋straceで「QEMU が子 execve をカーネルへ直通させ、そこで子が死ぬ」ことを特定
- QEMU 10.0.2 でも同一 → バージョン問題ではない
- binfmt_misc は登録が黙って飲まれるだけ（機能していない）→ 使えない
- wineserver だけラッパー経由で先行起動する案を経て、最終的に **ptrace+seccomp で execve を全面的に横取りする q32sup** を自作
- 19:18 JST：wineboot 完走、315MBプレフィックス完成、wineserver/services/explorer が32bitで稼働

## フェーズ4: 実ゲーム起動試行
- サノバウィッチ体験版 `sanoba_trial.exe`（PE32 / Kirikiri Z）を q32sup 経由で実行
- Kirikiri Z コア起動、data.xp3 選択、TJS 約30本ロード（`logs/krkr.console.log.sanoba-q32sup`）
- 警告：`Syntax error ... at line 8893 / Invalid character`（19:46:39）、その後 CPU クロック計測を最後にログ停止。画面は黒いまま qemu がCPUを消費し続け、タイトル画面到達は未確認のままセッション終了
- 起動方法の試行錯誤：`launch_sanoba.sh` 〜 `launch_sanoba7.sh`（scripts/original/ に全世代収録）。作業ディレクトリとパスの渡し方（相対→Z:\ 絶対、explorer 経由の有無）が変遷した

## 並行して分かったこと
- Geminism（64bit / Unity）は Wine 仮想デスクトップ `explorer /desktop=...,1600x900` で起動するとタイトルまで到達。素の Xvfb はウィンドウマネージャがなく、Unity が「非アクティブ」と判断して進行しなかった（Player.log の "vsync is broken ... until the game window is moved" がヒント）。**32bit 側の起動でも仮想デスクトップ経由を推奨**する理由
- Majikoi 体験版の全 exe が PE32 と実測（Launcher.exe が入口）。Sakura no Toki / RE:D Cherish! も PE32。いずれも q32sup 経路の候補

## ベンチマーク・実測値
| 項目 | 値 |
|---|---|
| VM | 共有 vCPU 実効 約1.5コア、RAM 7.7GB（当時）、Ubuntu 24.04.5、kernel 7.0.0-44 |
| ネイティブ32bit ELF | exit 139（即セグフォ） |
| qemu-i386 上の32bit Linuxバイナリ | exit 0 |
| 32bit Wine --version 応答 | `wine-11.21`、exit 0 |
| wineboot（q32sup経由、初回） | 完走。所要は競合プロセス凍結後に短縮（正確な秒数は未記録。プレフィックス 315MB 生成） |
| プレフィックス（現在） | 340MB（展開時） |
| ローカルLLM参考値 | Qwen2.5-1.5B Q4_K_M で生成 約9.5 tok/s（このVMのCPU性能の目安） |

## 現在の動作状況（2026-11-12 19:55 時点）
- ✅ 32bit Linuxバイナリ：qemu 経由で実行可能
- ✅ 32bit Wine 本体・wineboot・wineserver 群：q32sup 経由で動作、プレフィックス完成
- ✅ 実ゲーム（サノバ体験版）：エンジン起動＋スクリプトロードまで到達
- ⏳ 実ゲームのタイトル画面表示：未確認（黒画面、処理継続中にセッション終了）
- ❌ ネイティブ32bit実行 / WoW64 経路：サンドボックス制約により不可（回避策が本環境）
