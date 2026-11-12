# 部品目録（インベントリ）

2026-11-12 構築時点の構成要素の一覧。サイズは実測。

## 自作（この環境のために作成）
| 部品 | 実体 | 備考 |
|---|---|---|
| q32sup | `src/q32sup.c`（167行＋復元用パッチ）、`tools/q32sup.orig-x86_64-bin` | ptrace+seccomp 監督。execve を横取りし 32bit ELF を QEMU ラッパー経由に差し替え |
| noexec32 | `src/noexec32.c`、`tools/noexec32.so` | 診断用 LD_PRELOAD |
| 起動スクリプト群 | `scripts/`、`scripts/original/`（当時の全世代） | boot32 / boot32b / run32 / ws32 / launch_sanoba 1〜7 / launch_gem / setup32 |
| テストプログラム | `tests/` | hello32（h.s）、exectest（exectest.s）、cpuid32（cpuid.c/.s）、hello32.exe / hello64.exe（mingw 製 PE） |

## ランタイム
| 部品 | バージョン | サイズ |
|---|---|---|
| QEMU qemu-i386 | 10.0.2（Debian） | バイナリ 11MB、アーカイブ 3.7MB |
| QEMU qemu-i386-static | 8.2.2（Ubuntu） | アーカイブ 1.2MB |
| Wine x86 | 11.21（Kron4ek） | 展開 476MB、アーカイブ 56MB |
| Wine amd64 WoW64 / staging | 11.21（Kron4ek） | 展開 各約 820MB、アーカイブ 94 / 96MB |
| sysroot32 | Ubuntu noble i386 .deb 42本を展開 | 展開 176MB、アーカイブ 22MB、.deb 合計 22MB（+qemu-user-static 15MB） |
| wineprefix32 | Windows 10 相当、win32 | 起動済みスナップショット 展開約 315MB、アーカイブ 48MB／稼働版 340MB、アーカイブ 49MB |

sysroot の .deb 一覧（42本、ファイル名＝パッケージ_バージョン_i386.deb）：
libbrotli1, libbsd0, libbz2-1.0, libc6 (2.39-0ubuntu8.9), libdbus-1-3, libegl1, libexpat1, libfontconfig1, libfreetype6, libgbm1, libgcc-s1, libgl1, libgl1-mesa-dri, libglapi-mesa, libglvnd0, libglx0, libmd0, libpng16-16t64, libstdc++6, libuuid1, libx11-6, libxau6, libxcb1, libxcb-dri3-0, libxcb-present0, libxcb-sync1, libxcb-xfixes0, libxcomposite1, libxcursor1, libxdmcp6, libxext6, libxfixes3, libxi6, libxinerama1, libxkbcommon0, libxrandr2, libxrender1, libxshmfence1, libxxf86vm1, libzstd1, zlib1g
（正確なバージョン文字列は `sysroot32/debs/` のファイル名そのもの）

## ホスト側（apt、VM 交換で消えるため setup.sh --system-packages で再導入）
- Ubuntu 24.04.5 LTS、kernel 7.0.0-44（当時）
- Xvfb 21.1.12、xdotool 3.20160805.1、scrot、ffmpeg、fonts-noto-cjk、gcc 13.3、winetricks 20240105（64bit 側調査で使用）
- Wine 9.0（Ubuntu、wine64）：64bit 側の土台とハイブリッドプレフィックスの素体として使用。32bit 本線では不使用

## 参考にした中間生成物（本リポジトリには要点のみ収録）
- ハイブリッド WoW64 プレフィックス（744MB）：作り方は `docs/HISTORY.md` と STATUS 原典に記録（Wine 9.0 プレフィックスへ Kron4ek の i386-windows 1113ファイルと x86_64-windows を重ね、`.update-timestamp` を一致させる）。64bit 側（Geminism 起動）の土台
- DepotDownloader 3.4.0（64bit）：Steam 体験版取得用。32bit 環境そのものではないため未収録
