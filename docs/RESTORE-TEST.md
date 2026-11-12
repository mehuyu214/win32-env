# 復元テスト記録（2026-11-12 20:07〜20:19 JST）

「VM が消滅しても GitHub から復元できる」ことを、同一 VM 内のクリーンな clone で検証した記録。

## 手順
1. `git clone file://…/win32-env ~/workspace/restore-test`（git 管理下のファイルのみ＝ GitHub に上がる内容と等価）
2. `scripts/setup.sh` を実行
   - 全アーカイブの SHA-256 検証：OK（qemu 2種、sysroot、Wine x86、wineprefix32、WoW64 2種）
   - 分割パート（`.part-*`）の結合：自動で行われ、検証も通過
   - 展開後のサイズ：qemu10 22MB / sysroot32 176MB / wine32 476MB / wineprefix32 315MB / wow64 1.8GB
   - q32sup のビルド：成功（警告のみ）
   - `SETUP_DONE` を確認
3. `scripts/verify.sh`（全ステージ）を実行

## 結果（verify 全ステージ合格）
```
[1] native 32-bit ELF — segfault（元のサンドボックスと同じ挙動、参考項目）
[2] qemu-i386 runs a 32-bit Linux binary — PASS: hello32-nativ(e)
[3] qemu-i386 + sysroot runs 32-bit Wine --version — PASS: wine-11.21
[4] q32sup binary present and executable — PASS
[5] q32sup end-to-end: wine cmd /c echo — PASS: Q32SUP_OK
verify: PASS=4 FAIL=0
```

ステージ 5 では、復元したプレフィックス上で wineserver / wineboot / services が q32sup 配下で起動し、Windows の `cmd /c echo` が正常に応答した。**復元した環境単体で 32bit Windows プログラムの実行経路が成立することを確認した。**

## テスト中に直した実バグ（復元の再現性に関わるもの）
- tar 展開時の所有者復元がサンドボックスのユーザ名前空間で失敗する → `setup.sh` の展開に `--no-same-owner` を追加（コミット e2bc8c1）
- `tests/hello32` は設計上 13 バイトだけ出力する（`hello32-nativ` まで）→ verify の期待値を実物に合わせて修正（コミット 6318dd9）
