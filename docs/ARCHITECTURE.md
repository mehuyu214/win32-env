# 技術的な仕組み — なぜ「普通の方法」では動かず、q32sup で動くのか

## 1. このVMサンドボックスの制約（実測）

| 検証 | 結果 |
|---|---|
| ネイティブ32bit Linux ELF（静的リンク最小プログラム）の実行 | 即セグフォルト（exit 139）。アーキテクチャ追加（`dpkg --add-architecture i386`）前後で不変 |
| `/proc/sys/abi/ia32_emulation` | サンドボックス内に存在せず、有効化スイッチに触れない |
| Wine の新WoW64（Kron4ek 11.21 amd64-wow64 / staging、両方）で PE32 実行 | プロセス生成（NtCreateUserProcess）までは成功するが、wow64.dll / wow64cpu.dll / wow64win.dll が一切マップされず、子プロセスが最初の32bit互換モード遷移で syscall ループ（utime 872 / stime 1946 ticks、ページフォルト凍結） |
| `ptrace` attach | EPERM、`/proc/<pid>/stack` EPERM、`/proc/<pid>/syscall` 空 — gofer 型の仲介サンドボックスカーネルの様相 |
| binfmt_misc | 登録が黙って飲み込まれるだけで機能しない（見せかけ） |
| steamcmd（32bitのみ） | 上記理由で実行不可。代わりに64bitの DepotDownloader を使用 |

つまり障害は Wine の設定・ビルド・プレフィックスの問題ではなく、**サンドボックスのCPU/syscall層で32bitコードセグメントへの遷移自体が無効化されている**ことだった。

## 2. 突破口：CPUエミュレーション（QEMU user mode）

32bitコードをホストCPUで「実行」するのではなく、**QEMU がユーザーモードで命令を翻訳（TCG）する**分にはサンドボックスは干渉しない。

- `qemu-i386` 上で32bit Linuxテストバイナリが exit 0（実測 2026-11-12）
- 32bitライブラリはシステムに multiarch で入れると依存が壊れた（ローカル `+hatch1` ビルドの libzstd1 等が co-install 不可）ため、**Ubuntu noble の i386 .deb 42本をダウンロードだけして `sysroot32/root/` に展開**し、`qemu -L sysroot32/root` で使う。これによりシステム状態に依存せず、ワークスペースごと持ち運べる
- その上で **Kron4ek Wine 11.21 の x86（32bit）ビルド**が `wine-11.21` と応答（exit 0）

## 3. 残った問題：Wine の子プロセス spawn

単体では動くのに、当初 `hello32.exe` の初回実行（プレフィックス作成＝wineboot）が 240 秒タイムアウトした。strace とテストバイナリ（`tests/exectest`）で切り分けた結果：

- **QEMU は子プロセスの execve をホストカーネルに直接渡す**
- カーネルは exec を受理するが、32bit遷移が無効化されているため子が即死する
- wineserver / services / explorer など、Wine は多数の32bit子プロセスを spawn するため、最初の1段で詰む

## 4. 解決：q32sup（ptrace + seccomp 監督プロセス）

`src/q32sup.c`（この環境のために自作、C言語・単一ファイル）：

1. 子プロセスに **seccomp フィルタ**を入れる：`execve` / `execveat` のときだけ `SECCOMP_RET_TRACE` で止める
2. 親が **ptrace**（`PTRACE_O_TRACESECCOMP | TRACEFORK | TRACEVFORK | TRACECLONE | EXITKILL`）で全子孫を監督する
3. execve 対象パスを tracee メモリから読み（`process_vm_readv`）、**ELFヘッダを確認**（ELFCLASS32 かつ EM_386）
4. 32bit ELF なら、そのバイナリ専用の **ラッパースクリプト**を生成（`qemu10/wrap/w<hash>.sh`、中身は `exec qemu-i386 -cpu max -L <sysroot> "<target>" "$@"`）し、execve の第1引数を tracee のスタック上のスクラッチ領域に書いたラッパーパスへ差し替える（`PTRACE_POKEDATA` + レジスタ書き換え。execveat は AT_FDCWD に正規化）
5. 64bit ELF や非ELFはそのまま通す

これにより Wine の全子プロセスが「sh → qemu-i386 → 32bitバイナリ」という形で再入し、エミュレーションの連鎖が保たれる。

付随ツール `src/noexec32.c` は逆向きの実験用 LD_PRELOAD：32bit ELF への execve を ENOEXEC で塞ぎ、どの経路が32bit実行を試みるかを観測するために使った（診断用、本番経路では不要）。

## 5. 結果（2026-11-12 19:18 JST）

- `wineboot` が完走し、**315MB の32bitプレフィックス `wineprefix32/` が生成**された（本リポジトリには現在のスナップショット 340MB を収録）
- wineserver / services / explorer がすべて32bitのままエミュレーション下で動作し、専用デスクトップが表示された
- その後、実ゲーム『サノバウィッチ』体験版（PE32、Kirikiri Z）の `sanoba_trial.exe` が実行され、Kirikiri Z コア 1.2.0.3 起動・data.xp3 選択・TJSスクリプト約30本ロードまで到達した（`logs/krkr.console.log.sanoba-q32sup`）。タイトル画面の表示確認は未完（黒画面のままCPU消費が続き、セッションが区切れた）。詳細は `docs/HISTORY.md`

## 6. 速度について

- このVMの実効CPUは共有1.5コア程度。TCG翻訳はシングルスレッド寄りで重い
- 競合排除が効く：64bit側で動かしていた Geminism（Unity）のループを SIGSTOP で凍結して wineboot を通した
- プレフィックス作成は一回だけのコストなので、**作成済みスナップショットを配布**して回避する（本リポジトリの `wineprefix32.tar.xz`）
- QEMU は `-cpu max` 指定。マルチスレッドTCG（MTTCG）は user mode の i386 では限定的
