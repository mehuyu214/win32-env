# 第三者コンポーネントの出典とライセンス

いずれも再配布条件のあるフリーソフトウェアであり、出典から再取得する手順を `scripts/fetch-online.sh` に用意してある。本リポジトリへの収録は、復元可能性（同一バイナリでの再現）を目的とする。

| コンポーネント | バージョン | 出典 | ライセンス |
|---|---|---|---|
| QEMU (qemu-i386) | 10.0.2（Debian `1:10.0.2+ds-2+deb13u1~bpo12+1`） | Debian パッケージ（deb.debian.org、bookworm-backports/trixie 系）からバイナリ抽出 | GPLv2 |
| QEMU (qemu-i386-static) | 8.2.2（Ubuntu `1:8.2.2+ds-0ubuntu1.18`、qemu-user-static） | Ubuntu noble。`.deb` 自体を `sysroot32/debs/` に収録 | GPLv2 |
| Wine（x86 / amd64 WoW64 / staging WoW64） | 11.21 | Kron4ek/Wine-Builds の GitHub Releases（https://github.com/Kron4ek/Wine-Builds/releases/tag/11.21） | LGPL 2.1 |
| 32bit sysroot ライブラリ群 | Ubuntu 24.04 noble の i386 パッケージ 42 本（libc6 2.39 等） | Ubuntu archive（archive.ubuntu.com）。`.deb` ファイル名＝正確なバージョンは `sysroot32/debs/` と `docs/COMPONENTS.md` 参照 | 各パッケージのライセンス（GPL/LGPL/Apache 等） |
| ホストツール | Xvfb、xdotool、scrot、fonts-noto-cjk 等 | Ubuntu noble（apt） | 各々のライセンス |

除外したもの（再配布しない）：
- 体験版ゲーム等の著作物データ（zip・展開済みゲーム・セーブデータ）。入手経路と実測情報のみ `docs/STATUS-original-2026-11-12.md` に記録
- 認証情報・秘密鍵・トークン類は一切含まない
