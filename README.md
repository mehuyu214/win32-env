# win32-env — 32bit Windows プログラム実行環境（QEMU + Wine + q32sup）

**サンドボックスで 32bit コード実行が無効化された Linux VM 上で、32bit Windows アプリケーションを動かすための環境一式。**

2026-11-12 に構築・実証された環境を、VM が消滅しても **このリポジトリだけで完全に復元できる** 形で保存したものです。自作ツール `q32sup` のソース、QEMU / Wine / 32bit sysroot のバイナリアーカイブ、起動済み Wine プレフィックス、起動スクリプト、設定、検証ログ、試行錯誤の記録までを含みます。

---

## まずここから / 現在の状態（2026-11-16）

**これは何か**：GPU のない共有 VM の上で、**無改造の 32bit Windows ゲーム**を動かすための汎用環境。構成は qemu-i386（ユーザーモード TCG 翻訳）＋ 自作監督プロセス q32sup ＋ 32bit Wine 11.21 ＋ i386 Mesa sysroot（llvmpipe ソフトウェア描画）。

**到達点**：

- 『サノバウィッチ』体験版が**無改造のままプレイ可能**（タイトル画面表示、本編 Chapter 1-1 への進行、入力、セーブ系画面まで確認）。レンダリングの真因は sysroot 側の不足ライブラリ 2 本（`libpciaccess.so.0` / `libtinfo.so.6`）で、環境側修正のみで解決した
- **音声もリアルタイムでクリーンに再生・録音できる**（PulseAudio 経由、音声供給比率 **1.000**＝無音ギャップ 0・アンダーラン 0 を複数回再現。※これは専用プレフィックス＋専用 PA 構成でのサノバ実測）。ただし条件付き：**VM が静かであること**。他ジョブと CPU を取り合うと供給比率は 0.83〜0.89 まで落ちる（実測）。測定・録画の前には [tools/quiet.sh](tools/quiet.sh) で管理下の定期ジョブを一時停止する「静音プロトコル」を適用すること。性能調査の全記録は [docs/PERFORMANCE.md](docs/PERFORMANCE.md)。**注意：汎用ランチャー（`scripts/games/launch-game.sh`）経由のゲーム内音声はタイトルにより未解決**（下記「2026-11-16 修正ラウンド」参照）
- ゲームの起動手順は [docs/GAME-RUNBOOK.md](docs/GAME-RUNBOOK.md) と `scripts/games/`（ゲームごとに新規プレフィックス、日本語ロケール、絶対パス `Z:\` で exe を起動）
- 音声調査の記録：方法と失敗の経緯は [docs/AUDIO-INVESTIGATION.md](docs/AUDIO-INVESTIGATION.md)、実測の主記録（スナップショット）は [docs/AUDIO-RESULTS.md](docs/AUDIO-RESULTS.md)
- タイトル別の互換性は [docs/GAME-COMPAT.md](docs/GAME-COMPAT.md)。なお 2026-11-14 の互換性スイープで当時未解決だったタイトルはすべて解決済み：『サクラノ刻』＝ウィンドウマネージャ不在が原因（twm 常駐で解決）、『RE:D Cherish!』＝約 17 分・例外 0 で本編可、『まじこい』＝CPU モデル `max,-avx2` で解決。汎用レシピは **q32sup 系監督 + `max,-avx2` + twm 常駐 +（速度が必要な場合は）virgl**
- 描画高速化：virgl/vtest は **実施済み**（ゲスト側 `GALLIUM_DRIVER=virpipe`）。サノバ本編で v2 スコア平均 **4.75 pts/s**（llvmpipe 比で大幅改善）、現行の最良構成。経緯と棄却した代替案（partial-Present 等）は [docs/ARCHITECTURE-OPTIMIZATION.md](docs/ARCHITECTURE-OPTIMIZATION.md) と性能記録参照

**2026-11-16 修正ラウンド（外部レビュー対応）**：外部からの指摘・提案を受け、全項目を自前スタックで実測検証したうえで取り込んだ。詳細は [FIXLOG-20261116.md](FIXLOG-20261116.md)。要点（すべて本 VM での実測値）：

- **速度（正直な現状）**：標準の QEMU 10.0.2 では『洞窟物語』のタイプライタ表示が **約 0.55〜0.60 文字/秒**（実時間の 3〜4 割程度）と遅い。**QEMU 7.2.22 では同条件で 5 文字/秒以上（約 9 倍）**、タイトル到達も約 60 秒（10.0.2 のコールド起動は wineboot＋Mono ダイアログ込みで約 9 分）。ただし **7.2.22 は Kirikiri 系タイトルを起動できない**（『RIDDLE JOKER』0/5、『サノバウィッチ』0/2、いずれも Wine 起動中に wineserver が落ちる。同条件で 10.0.2 は両方起動可）。したがって **デフォルトは 10.0.2 のまま**とし、7.2.22 は効果のあるタイトル向けの選択肢として .deb を `sysroot32/debs/` に同梱した（bookworm 版 qemu-user 7.2 + libcapstone4 + liburing2）
- **q32sup を作り直した**：memfd ラッパー既定化＋fd 固定で ELF 判定と exec の TOCTOU を緩和、シェルクォート徹底、execveat の dirfd 解決、Q32_CPU の文字種検証、seccomp 失敗時のエラー表示。テストバッテリー全通過
- **復元性の穴を塞いだ**：sysroot に不足していた i386 の EGL/GLX 関連 .deb 4 本を追加し、`scripts/verify.sh` の EGL プローブが実際に合否を判定するよう修正（従来は無言で素通り）。`setup.sh` は正常終了で exit 0・冪等に
- **ランチャーのバグ修正**：相対パス起動（`cd /tmp`）の廃止、Wine Mono ダイアログで wineboot が固まる問題（DLL オーバーライドの export 順序）、音声ドライバ設定スクリプトの無言失敗（レジストリ見出しのタイムスタンプ付き書式に正規表現で対応＋再読検証）
- **フォント（文字化け対策）**：IPA ゴシックから必要グリフ（10,250 字/書体）のサブセットを生成して導入する `scripts/games/setup-game-fonts.sh` を追加。notepad / コンソールで日本語表示をスクリーンショット検証済み（`screenshots/fonts-*`）。原本 ipag.ttf はリポジトリに同梱していないため、`scripts/fetch-online.sh fonts-ipag` で Ubuntu の fonts-ipafont-gothic パッケージから取得する（`fonts-src/` に展開。当時の原本とバイト一致を検証済み）
- **音声の正直な状態**：ランチャーに PulseAudio 経路を配線（i386 PA ライブラリを `pa-libs/` に同梱、`AUDIO_ROUTE=pulse|alsa-pulse|alsa-null`）。winecfg のテスト音が PA 経由で鳴ることは実測確認済み。**しかし『洞窟物語』ではゲーム内音声がまだ鳴らない**（ゲーム内 DirectSound 初期化が失敗する。MMDevice の状態説は実験で棄却済み。調査継続中 — FIXLOG §§11/14）。「音声対応」とは書かない
- **PRoot との比較（実測）**：getpid 20 万回で q32sup+QEMU **89 ms** に対し PRoot+QEMU **5,412 ms**（約 61 倍）。さらに PRoot 配下ではネストした exec が無言で消え、Wine は何も作らず終了する。代替監督にはならない
- **CSMT**：『洞窟物語』タイプライタでは unset / 0 / 1 で差なし（23 文字/2 秒で同一）。ゲーム用プレフィックスには採用しない
- **フットプリント**：展開後の作業ツリーは約 4.4 GB（うち調査用 WoW64 ツリー 1.6 GB）。中核（QEMU＋sysroot＋Wine＋プレフィックス）だけなら約 1.24 GB。起動はタイトルまで約 60 秒〜2 分（タイトル・条件による）

**絶対ルール**：**ゲーム本体は一切改造しない**（EXE・XP3・アーカイブ・スクリプトに触らない）。修正はすべて環境側（QEMU / Wine / q32sup / Mesa / ライブラリ / 仮想デバイス）で行うこと。

---

## これは何か / なぜ普通の方法では動かないのか

対象 VM（Ubuntu 24.04、共有 1.5 コア級のサンドボックス）では、カーネル層で **32bit コードセグメントへの遷移が無効化** されています（実測：静的リンクの 32bit Linux ELF が即セグフォルト、exit 139）。そのため、

- ネイティブの wine32 は使えない
- Wine の新 WoW64（64bit プロセス内で 32bit PE を動かす方式）も、互換モード遷移の最初の段で固まる
- Steam の steamcmd（32bit）のようなバイナリも実行できない

という状態でした。突破口は **「遷移せず、全命令を翻訳する」** ことです：

1. **QEMU user mode（qemu-i386）** が 32bit 命令を TCG 翻訳して実行する（サンドボックスは干渉しない）
2. 32bit ライブラリ一式はシステムに入れず、**sysroot としてワークスペース内に展開**（`qemu -L`）するので、VM 交換やシステム初期化の影響を受けない
3. QEMU は子プロセスの `execve` をホストカーネルへ直通させてしまい、Wine の子プロセス（wineserver 等）がそこで死ぬ問題を、自作の監督プロセス **q32sup** が解決する：seccomp で `execve`/`execveat` を捕捉し、ptrace で対象が 32bit ELF のときだけ、そのバイナリ専用の「QEMU 経由ラッパースクリプト」に exec 先を差し替える

結果として、32bit Wine 11.21 の `wineboot` が完走し、wineserver / services / explorer がすべて 32bit のままエミュレーション下で動き、実ゲーム（『サノバウィッチ』体験版、PE32 / Kirikiri Z）のエンジン起動とスクリプトロードまで到達しました。仕組みの詳細は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、経緯は [docs/HISTORY.md](docs/HISTORY.md) を参照してください。

## クイックスタート（復元）

前提：x86_64 Linux、git、gcc、xz-utils。GUI を使う場合は Xvfb 等の X サーバ。

```bash
git clone https://github.com/mehuyu214/win32-env.git
cd win32-env
scripts/setup.sh            # archives/ から全コンポーネントを展開し、q32sup をビルド
scripts/verify.sh --quick   # 検証ステージ 1〜4（数秒）
scripts/verify.sh           # 検証ステージ 5 まで（q32sup 経由で wine cmd を実行。低速環境では数分）
```

ホスト側ツール（Xvfb / xdotool / scrot / 日本語フォント）もまとめて入れる場合：

```bash
scripts/setup.sh --system-packages --verify
```

32bit Windows プログラムの実行：

```bash
scripts/start-x.sh                       # Xvfb :99（1600x900）を起動
DISPLAY=:99 scripts/run32.sh <32bit.exe> [引数...]
DISPLAY=:99 scripts/launch.sh <32bit.exe>  # Wine 仮想デスクトップ経由（ゲーム向け推奨）
```

プレフィックスを新規に作り直す場合（通常は不要。作成済みスナップショットが展開される）：

```bash
WINEPREFIX=/path/to/new-prefix scripts/boot32.sh
```

## リポジトリ構成

| パス | 内容 |
|---|---|
| `src/q32sup.c` | 自作監督ツールのソース（相対パス解決パッチ版。どのディレクトリに置いても動く） |
| `src/q32sup.c.original` | オリジナルソース（当時の絶対パスハードコードのまま、原典として保存） |
| `src/noexec32.c` | 診断用 LD_PRELOAD（32bit execve を塞いで経路を観測する実験ツール） |
| `tools/` | 当時のビルド済みバイナリ（`q32sup.orig-x86_64-bin`、`noexec32.so`） |
| `scripts/` | 復元・実行用スクリプト（下記）。`scripts/original/` に当時のスクリプト全世代を原典保存 |
| `archives/` | バイナリアーカイブ群（下記）。20MB を超えるものは `.part-*` に分割して収録し、`setup.sh` が結合・検証・展開する |
| `sysroot32/debs/` | sysroot の素材料である .deb 77 本・合計 103.8MB（99.0MiB）。内訳：Ubuntu noble i386 基底 41 本＋ゲーム用クロージャ 32 本（`scripts/games/setup-game-sysroot.sh` の DEBS。libasound2-data の _all 1 本を含む）＋ amd64 4 本（qemu-user-static と QEMU 7.2.22（Debian bookworm）用 qemu-user / libcapstone4 / liburing2） |
| `tests/` | 検証用テストプログラム（`hello32` 静的 ELF、`hello32.exe` / `hello64.exe`、execve 切り分け用 `exectest`、CPUID 測定用 `cpuid32`、各ソース） |
| `logs/` | 構築・起動時の検証ログ一式（qemu セットアップ、wineboot、サノバ起動各回、Kirikiri コンソールログ等） |
| `screenshots/` | 起動デスクトップ等の証跡スクリーンショット |
| `docs/` | 技術解説、履歴、トラブルシューティング、部品目録、当日の作業記録原典（`STATUS-original-2026-11-12.md`） |

### archives/ の中身

| アーカイブ | 内容 | 展開後 |
|---|---|---|
| `qemu-10.0.2-i386.tar.xz` (3.7MB) | QEMU 10.0.2 の `qemu-i386` 一式（Debian パッケージから抽出） | `qemu10/usr/` |
| `qemu-8.2.2-i386-static.tar.xz` (1.2MB) | QEMU 8.2.2 static 版 `qemu-i386-static`（初期検証で使用） | `qemu/usr/` |
| `sysroot32-root.tar.xz` (22MB) | 32bit sysroot 展開済みツリー（展開時 176MB） | `sysroot32/root/` |
| `wine-11.21-x86.tar.xz` (56MB, 3 分割) | Kron4ek Wine 11.21 の 32bit（x86）ビルド（展開時 476MB） | `wine32/wine-11.21-x86/` |
| `wineprefix32.tar.xz` (48MB, 3 分割) | **起動済み 32bit プレフィックス**（2026-11-12 19:09 のクリーンなスナップショット。展開時 約 315MB） | `wineprefix32/` |
| `wineprefix32-live-snapshot.tar.xz` (49MB, 3 分割) | 同プレフィックスの 19:52 時点スナップショット（レジストリ最新版。稼働中取得のため参考用） | 手動展開 |
| `wine-11.21-amd64-wow64.tar.xz` (94MB, 5 分割) | Kron4ek Wine 11.21 WoW64 ビルド（調査用。64bit 側・Geminism 等で使用） | `wow64/` |
| `wine-11.21-staging-amd64-wow64.tar.xz` (96MB, 5 分割) | 同 staging 版（調査用） | `wow64/` |
| `pa-bin.tar.xz` (1.4MB) | ホスト用 PulseAudio デーモン一式（Ubuntu noble amd64 の .deb から抽出。`scripts/start-pa.sh` が使う） | `pa-bin/` |

各アーカイブの SHA-256 は `archives/SHA256SUMS.txt` と個別 `.sha256` にあり、`setup.sh` が展開前に自動検証します。オリジナルファイルのハッシュは `docs/SHA256SUMS.originals.txt` に記録しています。

> **ゲーム本体は含まれません。** 体験版ゲーム等の著作物データ（ダウンロード zip、展開済みゲーム、セーブデータ）は再配布できないため除外しました。対象タイトル・入手経路（公式 DMM / Steam）・各 exe のビット数実測結果は `docs/STATUS-original-2026-11-12.md` に記録してあります。復元した環境で `scripts/run32.sh <入手した exe>` とすれば同じように実行できます。

## スクリプト一覧

| スクリプト | 役割 |
|---|---|
| `scripts/setup.sh` | 復元の本体。アーカイブの結合・SHA-256 検証・展開、q32sup のビルドまでを一括実行。`--online`（不足分を原典から再取得試行）、`--system-packages`（apt でホストツール導入）、`--verify` |
| `scripts/verify.sh` | 段階検証。1: ネイティブ実行可否（参考）、2: qemu で 32bit Linux バイナリ、3: 32bit Wine のバージョン応答、4: q32sup の存在、5: q32sup 経由で `wine cmd /c echo` の実走 |
| `scripts/run32.sh` | 32bit Windows exe を q32sup + qemu + Wine32 で実行 |
| `scripts/launch.sh` | Wine 仮想デスクトップ経由の起動（ウィンドウがアクティブ化されないと進まないゲーム向け） |
| `scripts/boot32.sh` | 新規プレフィックスの wineboot（スナップショットを使わない場合） |
| `scripts/ws32.sh` | wineserver ラッパー（`WINESERVER` 環境変数に指定する用途） |
| `scripts/start-x.sh` | Xvfb :99（1600x900x24）の起動 |
| `scripts/env.sh` | 共通環境変数（`VN32_ROOT` を起点に各パスを解決） |
| `scripts/fetch-online.sh` | 第三者コンポーネントを原典（Kron4ek GitHub Releases、Debian、Ubuntu）から再取得するフォールバック手順 |

すべてのスクリプトはリポジトリの場所に依存しません（`$HOME/workspace/vn-trials` のような絶対パスは排除済み）。q32sup も実行ファイル自身の位置から QEMU / sysroot / wrap ディレクトリを解決します（上書き用に `Q32_QEMU` / `Q32_SYSROOT` / `Q32_WRAPDIR` 環境変数あり）。

## 動作状況（2026-11-12 時点）

- ✅ 32bit Linux バイナリ：qemu-i386 経由で正常実行（exit 0）
- ✅ 32bit Wine 11.21：バージョン応答、wineboot 完走、プレフィックス生成（315MB）
- ✅ wineserver / services / explorer：32bit のまま q32sup 配下で稼働、専用デスクトップ表示
- ✅ 実ゲーム『サノバウィッチ』体験版（PE32 / Kirikiri Z）：エンジン起動、data.xp3 選択、TJS スクリプト約 30 本ロード（`logs/krkr.console.log.sanoba-q32sup`）
- ⏳ 実ゲームのタイトル画面到達：未確認（黒画面のまま処理継続中にセッションが区切れた。その後も別セッションで継続試行中）→ **その後 2026-11-13 にタイトル到達・本編プレイ可能・音声 1.000 を確認。現在の状態は冒頭セクション参照**
- ❌ ネイティブ 32bit 実行 / WoW64 経路：サンドボックス制約により不可（本環境がその回避策）

速度の目安：VM の実効 CPU は共有 1.5 コア程度と小さく、TCG 翻訳越しの初回起動は重いです。プレフィックス作成はスナップショット配布で回避済み。競合する重いプロセスがあると極端に遅くなるため、検証時は他のエミュレーションを止めるのが有効です。

## トラブルシューティング

代表的なもの（全文は [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)）：

- **子プロセスが即死する / wineboot が進まない** → q32sup を経由していない可能性。必ず `scripts/run32.sh` / `boot32.sh`（＝ q32sup 配下）で起動すること。素の qemu 直叩きでは Wine の子プロセス spawn が死にます
- **`qemu10/wrap/` に古いラッパーが残っている** → ラッパーは絶対パスを含む生成物です。環境を移動したら `qemu10/wrap/*.sh` を消して再生成させること（復元直後は空になっています）
- **ゲームがロゴや黒画面で止まる** → ウィンドウがアクティブ化されていない可能性。`scripts/launch.sh`（仮想デスクトップ経由）で起動すること
- **プレフィックスが更新を要求して wineboot が走る** → `.update-timestamp` の中身は Wine の `wine.inf` の mtime と一致している必要があります（本環境では `1793442172`）。詳細は docs 参照

## ライセンス・再配布について

- 自作部分（`src/`、`scripts/`、`tests/` のソース、ドキュメント）はこのリポジトリの作成者によるものです
- QEMU は GPLv2、Wine は LGPL 2.1、Ubuntu/Debian パッケージは各々のライセンスに従います。出典と取得先は [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) に明記してあり、いずれも再取得可能な形で手順を残しています
- ゲーム等の著作物データ、認証情報・秘密鍵類は含まれていません

## 関連リンク

- 当日の作業記録（原典）: [docs/STATUS-original-2026-11-12.md](docs/STATUS-original-2026-11-12.md)
- ゲーム実行レシピ: [docs/GAME-RUNBOOK.md](docs/GAME-RUNBOOK.md) / ゲーム互換性状況: [docs/GAME-COMPAT.md](docs/GAME-COMPAT.md)
- 音声キャプチャのペーシング調査（delivery ratio 法・品質ゲート v2・最適化ラダー）: [docs/AUDIO-INVESTIGATION.md](docs/AUDIO-INVESTIGATION.md)。測定ツールは `tools/delivery_ratio.py`
- 技術解説: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) / 試行錯誤の履歴: [docs/HISTORY.md](docs/HISTORY.md)
- 部品目録: [docs/COMPONENTS.md](docs/COMPONENTS.md)
